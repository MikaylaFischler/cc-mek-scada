local log    = require("scada-common.log")
local mqueue = require("scada-common.mqueue")
local ppm    = require("scada-common.ppm")
local util   = require("scada-common.util")

local threads = {}

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local MAIN_CLOCK    = 1   -- (1Hz, 20 ticks)
local RPS_SLEEP     = 250 -- (250ms, 5 ticks)
local COMMS_SLEEP   = 150 -- (150ms, 3 ticks)
local SP_CTRL_SLEEP = 250 -- (250ms, 5 ticks)

local BURN_RATE_RAMP_mB_s = 5.0

local MQ__RPS_CMD = {
    SCRAM = 1,
    DEGRADED_SCRAM = 2,
    TRIP_TIMEOUT = 3
}

local MQ__COMM_CMD = {
    SEND_STATUS = 1
}

-- main thread
---@param smem plc_shared_memory
---@param init function
function threads.thread__main(smem, init)
    local public = {}   ---@class thread

    -- execute thread
    function public.exec()
        log.debug("main thread init, clock inactive")

        -- send status updates at 2Hz (every 10 server ticks) (every loop tick)
        -- send link requests at 0.5Hz (every 40 server ticks) (every 4 loop ticks)
        local LINK_TICKS = 4
        local ticks_to_update = 0
        local loop_clock = util.new_clock(MAIN_CLOCK)

        -- load in from shared memory
        local networked     = smem.networked
        local plc_state     = smem.plc_state
        local plc_dev       = smem.plc_dev

        -- event loop
        while true do
            -- get plc_sys fields (may have been set late due to degraded boot)
            local rps           = smem.plc_sys.rps
            local plc_comms     = smem.plc_sys.plc_comms
            local conn_watchdog = smem.plc_sys.conn_watchdog

---@diagnostic disable-next-line: undefined-field
            local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

            -- handle event
            if event == "timer" and loop_clock.is_clock(param1) then
                -- core clock tick
                if networked then
                    -- start next clock timer
                    loop_clock.start()

                    -- send updated data
                    if not plc_state.no_modem then
                        if plc_comms.is_linked() then
                            smem.q.mq_comms_tx.push_command(MQ__COMM_CMD.SEND_STATUS)
                        else
                            if ticks_to_update == 0 then
                                plc_comms.send_link_req()
                                ticks_to_update = LINK_TICKS
                            else
                                ticks_to_update = ticks_to_update - 1
                            end
                        end
                    end
                end
            elseif event == "modem_message" and networked and plc_state.init_ok and not plc_state.no_modem then
                -- got a packet
                local packet = plc_comms.parse_packet(param1, param2, param3, param4, param5)
                if packet ~= nil then
                    -- pass the packet onto the comms message queue
                    smem.q.mq_comms_rx.push_packet(packet)
                end
            elseif event == "timer" and networked and plc_state.init_ok and conn_watchdog.is_timer(param1) then
                -- haven't heard from server recently? shutdown reactor
                plc_comms.unlink()
                smem.q.mq_rps.push_command(MQ__RPS_CMD.TRIP_TIMEOUT)
            elseif event == "peripheral_detach" then
                -- peripheral disconnect
                local type, device = ppm.handle_unmount(param1)

                if type ~= nil and device ~= nil then
                    if type == "fissionReactor" then
                        println_ts("reactor disconnected!")
                        log.error("reactor disconnected!")
                        plc_state.no_reactor = true
                        plc_state.degraded = true
                    elseif networked and type == "modem" then
                        -- we only care if this is our wireless modem
                        if device == plc_dev.modem then
                            println_ts("wireless modem disconnected!")
                            log.error("comms modem disconnected!")
                            plc_state.no_modem = true

                            if plc_state.init_ok then
                                -- try to scram reactor if it is still connected
                                smem.q.mq_rps.push_command(MQ__RPS_CMD.DEGRADED_SCRAM)
                            end

                            plc_state.degraded = true
                        else
                            log.warning("non-comms modem disconnected")
                        end
                    end
                end
            elseif event == "peripheral" then
                -- peripheral connect
                local type, device = ppm.mount(param1)

                if type ~= nil and device ~= nil then
                    if type == "fissionReactor" then
                        -- reconnected reactor
                        plc_dev.reactor = device

                        smem.q.mq_rps.push_command(MQ__RPS_CMD.SCRAM)

                        println_ts("reactor reconnected.")
                        log.info("reactor reconnected")
                        plc_state.no_reactor = false

                        if plc_state.init_ok then
                            rps.reconnect_reactor(plc_dev.reactor)
                            if networked then
                                plc_comms.reconnect_reactor(plc_dev.reactor)
                            end
                        end

                        -- determine if we are still in a degraded state
                        if not networked or not plc_state.no_modem then
                            plc_state.degraded = false
                        end
                    elseif networked and type == "modem" then
                        if device.isWireless() then
                            -- reconnected modem
                            plc_dev.modem = device

                            if plc_state.init_ok then
                                plc_comms.reconnect_modem(plc_dev.modem)
                            end

                            println_ts("wireless modem reconnected.")
                            log.info("comms modem reconnected")
                            plc_state.no_modem = false

                            -- determine if we are still in a degraded state
                            if not plc_state.no_reactor then
                                plc_state.degraded = false
                            end
                        else
                            log.info("wired modem reconnected")
                        end
                    end
                end

                -- if not init'd and no longer degraded, proceed to init
                if not plc_state.init_ok and not plc_state.degraded then
                    plc_state.init_ok = true
                    init()
                end
            elseif event == "clock_start" then
                -- start loop clock
                loop_clock.start()
                log.debug("main thread clock started")
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                log.info("terminate requested, main thread exiting")
                -- rps handles reactor shutdown
                plc_state.shutdown = true
                break
            end
        end
    end

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local plc_state = smem.plc_state

        while not plc_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(result)
            end

            -- if status is true, then we are probably exiting, so this won't matter
            -- if not, we need to restart the clock
            -- this thread cannot be slept because it will miss events (namely "terminate" otherwise)
            if not plc_state.shutdown then
                log.info("main thread restarting now...")

---@diagnostic disable-next-line: undefined-field
                os.queueEvent("clock_start")
            end
        end
    end

    return public
end

-- RPS operation thread
---@param smem plc_shared_memory
function threads.thread__rps(smem)
    local public = {}   ---@class thread

    -- execute thread
    function public.exec()
        log.debug("rps thread start")

        -- load in from shared memory
        local networked   = smem.networked
        local plc_state   = smem.plc_state
        local plc_dev     = smem.plc_dev

        local rps_queue   = smem.q.mq_rps

        local was_linked  = false
        local last_update = util.time()

        -- thread loop
        while true do
            -- get plc_sys fields (may have been set late due to degraded boot)
            local rps         = smem.plc_sys.rps
            local plc_comms   = smem.plc_sys.plc_comms
            -- get reactor, may have changed do to disconnect/reconnect
            local reactor     = plc_dev.reactor

            -- RPS checks
            if plc_state.init_ok then
                -- SCRAM if no open connection
                if networked and not plc_comms.is_linked() then
                    if was_linked then
                        was_linked = false
                        rps.trip_timeout()
                    end
                else
                    -- would do elseif not networked but there is no reason to do that extra operation
                    was_linked = true
                end

                -- if we tried to SCRAM but failed, keep trying
                -- in that case, SCRAM won't be called until it reconnects (this is the expected use of this check)
---@diagnostic disable-next-line: need-check-nil
                if not plc_state.no_reactor and rps.is_tripped() and reactor.getStatus() then
                    rps.scram()
                end

                -- if we are in standalone mode, continuously reset RPS
                -- RPS will trip again if there are faults, but if it isn't cleared, the user can't re-enable
                if not networked then rps.reset() end

                -- check safety (SCRAM occurs if tripped)
                if not plc_state.no_reactor then
                    local rps_tripped, rps_status_string, rps_first = rps.check()

                    if rps_tripped and rps_first then
                        println_ts("[RPS] SCRAM! safety trip: " .. rps_status_string)
                        if networked and not plc_state.no_modem then
                            plc_comms.send_rps_alarm(rps_status_string)
                        end
                    end
                end
            end

            -- check for messages in the message queue
            while rps_queue.ready() and not plc_state.shutdown do
                local msg = rps_queue.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                        if plc_state.init_ok then
                            if msg.message == MQ__RPS_CMD.SCRAM then
                                -- SCRAM
                                rps.scram()
                            elseif msg.message == MQ__RPS_CMD.DEGRADED_SCRAM then
                                -- lost peripheral(s)
                                rps.trip_fault()
                            elseif msg.message == MQ__RPS_CMD.TRIP_TIMEOUT then
                                -- watchdog tripped
                                rps.trip_timeout()
                                println_ts("server timeout")
                                log.warning("server timeout")
                            end
                        end
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- received data
                    elseif msg.qtype == mqueue.TYPE.PACKET then
                        -- received a packet
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if plc_state.shutdown then
                -- safe exit
                log.info("rps thread shutdown initiated")
                if plc_state.init_ok then
                    if rps.scram() then
                        println_ts("reactor disabled")
                        log.info("rps thread reactor SCRAM OK")
                    else
                        println_ts("exiting, reactor failed to disable")
                        log.error("rps thread failed to SCRAM reactor on exit")
                    end
                end
                log.info("rps thread exiting")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(RPS_SLEEP, last_update)
        end
    end

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local plc_state = smem.plc_state

        while not plc_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(result)
            end

            if not plc_state.shutdown then
                if plc_state.init_ok then smem.plc_sys.rps.scram() end
                log.info("rps thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- communications sender thread
---@param smem plc_shared_memory
function threads.thread__comms_tx(smem)
    local public = {}   ---@class thread

    -- execute thread
    function public.exec()
        log.debug("comms tx thread start")

        -- load in from shared memory
        local plc_state   = smem.plc_state
        local comms_queue = smem.q.mq_comms_tx

        local last_update = util.time()

        -- thread loop
        while true do
            -- get plc_sys fields (may have been set late due to degraded boot)
            local plc_comms = smem.plc_sys.plc_comms

            -- check for messages in the message queue
            while comms_queue.ready() and not plc_state.shutdown do
                local msg = comms_queue.pop()

                if msg ~= nil and plc_state.init_ok then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                        if msg.message == MQ__COMM_CMD.SEND_STATUS then
                            -- send PLC/RPS status
                            plc_comms.send_status(plc_state.degraded)
                            plc_comms.send_rps_status()
                        end
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- received data
                    elseif msg.qtype == mqueue.TYPE.PACKET then
                        -- received a packet
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if plc_state.shutdown then
                log.info("comms tx thread exiting")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
        end
    end

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local plc_state = smem.plc_state

        while not plc_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(result)
            end

            if not plc_state.shutdown then
                log.info("comms tx thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- communications handler thread
---@param smem plc_shared_memory
function threads.thread__comms_rx(smem)
    local public = {}   ---@class thread

    -- execute thread
    function public.exec()
        log.debug("comms rx thread start")

        -- load in from shared memory
        local plc_state   = smem.plc_state
        local setpoints   = smem.setpoints

        local comms_queue = smem.q.mq_comms_rx

        local last_update = util.time()

        -- thread loop
        while true do
            -- get plc_sys fields (may have been set late due to degraded boot)
            local plc_comms = smem.plc_sys.plc_comms

            -- check for messages in the message queue
            while comms_queue.ready() and not plc_state.shutdown do
                local msg = comms_queue.pop()

                if msg ~= nil and plc_state.init_ok then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- received data
                    elseif msg.qtype == mqueue.TYPE.PACKET then
                        -- received a packet
                        -- handle the packet (setpoints passed to update burn rate setpoint)
                        --                   (plc_state passed to check if degraded)
                        plc_comms.handle_packet(msg.message, setpoints, plc_state)
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if plc_state.shutdown then
                log.info("comms rx thread exiting")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
        end
    end

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local plc_state = smem.plc_state

        while not plc_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(result)
            end

            if not plc_state.shutdown then
                log.info("comms rx thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- apply setpoints
---@param smem plc_shared_memory
function threads.thread__setpoint_control(smem)
    local public = {}   ---@class thread

    -- execute thread
    function public.exec()
        log.debug("setpoint control thread start")

        -- load in from shared memory
        local plc_state    = smem.plc_state
        local setpoints    = smem.setpoints
        local plc_dev      = smem.plc_dev

        local last_update  = util.time()
        local running      = false

        local last_sp_burn = 0.0

        -- do not use the actual elapsed time, it could spike
        -- we do not want to have big jumps as that is what we are trying to avoid in the first place
        local min_elapsed_s = SP_CTRL_SLEEP / 1000.0

        -- thread loop
        while true do
            -- get plc_sys fields (may have been set late due to degraded boot)
            local rps     = smem.plc_sys.rps
            -- get reactor, may have changed do to disconnect/reconnect
            local reactor = plc_dev.reactor

            if plc_state.init_ok and not plc_state.no_reactor then
                -- check if we should start ramping
                if setpoints.burn_rate_en and setpoints.burn_rate ~= last_sp_burn then
                    if rps.is_active() then
                        if math.abs(setpoints.burn_rate - last_sp_burn) <= 5 then
                            -- update without ramp if <= 5 mB/t change
                            log.debug("setting burn rate directly to " .. setpoints.burn_rate .. "mB/t")
---@diagnostic disable-next-line: need-check-nil
                            reactor.setBurnRate(setpoints.burn_rate)
                        else
                            log.debug("starting burn rate ramp from " .. last_sp_burn .. "mB/t to " .. setpoints.burn_rate .. "mB/t")
                            running = true
                        end

                        last_sp_burn = setpoints.burn_rate
                    else
                        last_sp_burn = 0.0
                    end
                end

                -- only check I/O if active to save on processing time
                if running then
                    -- clear so we can later evaluate if we should keep running
                    running = false

                    -- adjust burn rate (setpoints.burn_rate)
                    if setpoints.burn_rate_en then
                        if rps.is_active() then
---@diagnostic disable-next-line: need-check-nil
                            local current_burn_rate = reactor.getBurnRate()

                            -- we yielded, check enable again
                            if setpoints.burn_rate_en and (current_burn_rate ~= ppm.ACCESS_FAULT) and (current_burn_rate ~= setpoints.burn_rate) then
                                -- calculate new burn rate
                                local new_burn_rate = current_burn_rate

                                if setpoints.burn_rate > current_burn_rate then
                                    -- need to ramp up
                                    local new_burn_rate = current_burn_rate + (BURN_RATE_RAMP_mB_s * min_elapsed_s)
                                    if new_burn_rate > setpoints.burn_rate then
                                        new_burn_rate = setpoints.burn_rate
                                    end
                                else
                                    -- need to ramp down
                                    local new_burn_rate = current_burn_rate - (BURN_RATE_RAMP_mB_s * min_elapsed_s)
                                    if new_burn_rate < setpoints.burn_rate then
                                        new_burn_rate = setpoints.burn_rate
                                    end
                                end

                                -- set the burn rate
---@diagnostic disable-next-line: need-check-nil
                                reactor.setBurnRate(new_burn_rate)

                                running = running or (new_burn_rate ~= setpoints.burn_rate)
                            end
                        else
                            last_sp_burn = 0.0
                        end
                    end
                end
            end

            -- check for termination request
            if plc_state.shutdown then
                log.info("setpoint control thread exiting")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(SP_CTRL_SLEEP, last_update)
        end
    end

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local plc_state = smem.plc_state

        while not plc_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(result)
            end

            if not plc_state.shutdown then
                log.info("setpoint control thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

return threads

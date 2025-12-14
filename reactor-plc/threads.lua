local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local ppm       = require("scada-common.ppm")
local tcd       = require("scada-common.tcd")
local util      = require("scada-common.util")

local backplane = require("reactor-plc.backplane")
local databus   = require("reactor-plc.databus")
local renderer  = require("reactor-plc.renderer")

local core      = require("graphics.core")

local threads = {}

local MAIN_CLOCK    = 0.5 -- 2Hz,   10 ticks
local RPS_SLEEP     = 250 -- 250ms, 5 ticks
local COMMS_SLEEP   = 150 -- 150ms, 3 ticks
local SP_CTRL_SLEEP = 250 -- 250ms, 5 ticks

local BURN_RATE_RAMP_mB_s = 5.0

-- main thread
---@nodiscard
---@param smem plc_shared_memory
function threads.thread__main(smem)
    -- print a log message to the terminal as long as the UI isn't running
    local function println_ts(message) if not smem.plc_state.fp_ok then util.println_ts(message) end end

    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        databus.tx_rt_status("main", true)
        log.debug("OS: main thread start")

        local LINK_TICKS = 2
        local ticks_to_update = 0

        local loop_clock = util.new_clock(MAIN_CLOCK)

        -- load in from shared memory
        local networked     = smem.networked
        local plc_state     = smem.plc_state

        local rps           = smem.plc_sys.rps
        local plc_comms     = smem.plc_sys.plc_comms
        local conn_watchdog = smem.plc_sys.conn_watchdog

        local MQ__RPS_CMD   = smem.q_types.MQ__RPS_CMD
        local MQ__COMM_CMD  = smem.q_types.MQ__COMM_CMD

        -- start clock
        loop_clock.start()

        -- event loop
        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            -- handle event
            if event == "timer" and loop_clock.is_clock(param1) then
                -- blink heartbeat indicator
                databus.heartbeat()

                -- start next clock timer
                loop_clock.start()

                -- periodic hardware tasks
                backplane.periodic()

                -- send updated data or try to link
                if networked then
                    if plc_comms.is_linked() then
                        smem.q.mq_comms_tx.push_command(MQ__COMM_CMD.SEND_STATUS)

                        plc_comms.manage_failover(backplane.active_nic())
                    elseif ticks_to_update == 0 then
                        local a_nic, s_nic = backplane.active_nic(), backplane.standby_nic()

                        if a_nic.is_network_up() then
                            plc_comms.send_link_req(a_nic)
                        elseif s_nic and s_nic.is_network_up() then
                            plc_comms.send_link_req(s_nic)
                        end

                        ticks_to_update = LINK_TICKS
                    else
                        ticks_to_update = ticks_to_update - 1
                    end
                end

                -- check for formed state change
                if (not plc_state.reactor_formed) and rps.is_formed() then
                    -- reactor now formed
                    plc_state.reactor_formed = true

                    println_ts("reactor is now formed")
                    log.info("reactor is now formed")

                    -- SCRAM newly formed reactor
                    smem.q.mq_rps.push_command(MQ__RPS_CMD.SCRAM)

                    -- determine if we are still in a degraded state
                    if (not networked) or backplane.active_nic().is_connected() then
                        plc_state.degraded = false
                    end

                    -- partial reset of RPS, specific to becoming formed
                    -- without this, auto control can't resume on chunk load
                    smem.q.mq_rps.push_command(MQ__RPS_CMD.RESET_REATTACH)
                elseif plc_state.reactor_formed and (rps.is_formed() == false) then
                    -- reactor no longer formed
                    println_ts("reactor is no longer formed")
                    log.info("reactor is no longer formed")

                    plc_state.reactor_formed = false
                    plc_state.degraded = true
                end

                -- update indicators
                databus.tx_hw_status(plc_state)
            elseif event == "modem_message" and networked then
                -- got a packet
                local packet = plc_comms.parse_packet(param1, param2, param3, param4, param5)
                if packet ~= nil then
                    -- pass the packet onto the comms message queue
                    smem.q.mq_comms_rx.push_network(packet)
                end
            elseif event == "timer" and networked and conn_watchdog.is_timer(param1) then
                -- haven't heard from server recently? close connection and shutdown reactor
                plc_comms.close()
                smem.q.mq_rps.push_command(MQ__RPS_CMD.TRIP_TIMEOUT)
            elseif event == "timer" then
                -- notify timer callback dispatcher if no other timer case claimed this event
                tcd.handle(param1)
            elseif event == "peripheral_detach" then
                -- peripheral disconnect
                local type, device = ppm.handle_unmount(param1)
                if type ~= nil and device ~= nil then
                    backplane.detach(param1, type, device, println_ts)
                end

                -- update indicators
                databus.tx_hw_status(plc_state)
            elseif event == "peripheral" then
                -- peripheral connect
                local type, device = ppm.mount(param1)
                if type ~= nil and device ~= nil then
                    backplane.attach(param1, type, device, println_ts)
                end

                -- update indicators
                databus.tx_hw_status(plc_state)
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or
                   event == "double_click" then
                -- handle a mouse event
                renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                log.info("OS: terminate requested, main thread exiting")
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
                log.fatal(util.strval(result))
            end

            databus.tx_rt_status("main", false)

            -- if status is true, then we are probably exiting, so this won't matter
            -- if not, we need to restart the clock
            -- this thread cannot be slept because it will miss events (namely "terminate" otherwise)
            if not plc_state.shutdown then
                log.info("OS: main thread restarting now...")
            end
        end
    end

    return public
end

-- RPS operation thread
---@nodiscard
---@param smem plc_shared_memory
function threads.thread__rps(smem)
    -- print a log message to the terminal as long as the UI isn't running
    local function println_ts(message) if not smem.plc_state.fp_ok then util.println_ts(message) end end

    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        databus.tx_rt_status("rps", true)
        log.debug("OS: rps thread start")

        -- load in from shared memory
        local networked   = smem.networked
        local plc_state   = smem.plc_state
        local plc_dev     = smem.plc_dev

        local rps_queue   = smem.q.mq_rps

        local MQ__RPS_CMD = smem.q_types.MQ__RPS_CMD

        local was_linked  = false
        local last_update = util.time()

        -- thread loop
        while true do
            -- get plc_sys fields (may have been set late due to degraded boot)
            local rps       = smem.plc_sys.rps
            local plc_comms = smem.plc_sys.plc_comms
            -- get reactor, it may have changed due to a disconnect/reconnect
            local reactor   = plc_dev.reactor

            -- SCRAM if no open connection
            if networked and not plc_comms.is_linked() then
                if was_linked then
                    was_linked = false
                    rps.trip_timeout()
                end
            else was_linked = true end

            -- check reactor status
            if (not plc_state.no_reactor) and rps.is_formed() then
                local reactor_status = reactor.getStatus()
                databus.tx_reactor_state(reactor_status)

                -- if we tried to SCRAM but failed, keep trying
                -- in that case, SCRAM won't be called until it reconnects (this is the expected use of this check)
                if rps.is_tripped() and reactor_status then rps.scram() end
            end

            -- if we are in standalone mode and the front panel isn't working, continuously reset RPS
            -- RPS will trip again if there are faults, but if it isn't cleared, the user can't re-enable
            if not (networked or smem.plc_state.fp_ok) then rps.reset(true) end

            -- check safety (SCRAM occurs if tripped)
            local rps_tripped, rps_status_string, rps_first = rps.check(not plc_state.no_reactor)
            if rps_tripped and rps_first then
                println_ts("RPS: SCRAM on safety trip (" .. rps_status_string .. ")")
                if networked then plc_comms.send_rps_alarm(rps_status_string) end
            end

            -- check for messages in the message queue
            while rps_queue.ready() and not plc_state.shutdown do
                local msg = rps_queue.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                        if msg.message == MQ__RPS_CMD.SCRAM then
                            -- SCRAM
                            log.info("RPS: OS requested SCRAM")
                            rps.scram()
                        elseif msg.message == MQ__RPS_CMD.DEGRADED_SCRAM then
                            -- lost peripheral(s)
                            log.info("RPS: received PLC degraded alert")
                            rps.trip_fault()
                        elseif msg.message == MQ__RPS_CMD.TRIP_TIMEOUT then
                            -- watchdog tripped
                            println_ts("RPS: supervisor timeout")
                            log.warning("RPS: received supervisor timeout alert")
                            rps.trip_timeout()
                        elseif msg.message == MQ__RPS_CMD.RESET_REATTACH then
                            -- reset on reactor re-connect
                            rps.reset_reattach()
                        end
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if plc_state.shutdown then
                -- safe exit
                log.info("OS: rps thread shutdown initiated")

                if rps.scram() then
                    println_ts("exiting, reactor disabled")
                    log.info("OS: rps thread reactor SCRAM OK on exit")
                else
                    println_ts("exiting, reactor failed to disable")
                    log.error("OS: rps thread failed to SCRAM reactor on exit")
                end

                log.info("OS: rps thread exiting")
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
                log.fatal(util.strval(result))
            end

            databus.tx_rt_status("rps", false)

            if not plc_state.shutdown then
                smem.plc_sys.rps.scram()
                log.info("OS: rps thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- communications sender thread
---@nodiscard
---@param smem plc_shared_memory
function threads.thread__comms_tx(smem)
    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        databus.tx_rt_status("comms_tx", true)
        log.debug("OS: comms tx thread start")

        -- load in from shared memory
        local plc_state    = smem.plc_state
        local comms_queue  = smem.q.mq_comms_tx

        local MQ__COMM_CMD = smem.q_types.MQ__COMM_CMD

        local last_update = util.time()

        -- thread loop
        while true do
            -- get plc_sys fields (may have been set late due to degraded boot)
            local plc_comms = smem.plc_sys.plc_comms

            -- check for messages in the message queue
            while comms_queue.ready() and not plc_state.shutdown do
                local msg = comms_queue.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                        if msg.message == MQ__COMM_CMD.SEND_STATUS then
                            -- send PLC/RPS status
                            plc_comms.send_status(plc_state.no_reactor, plc_state.reactor_formed)
                            plc_comms.send_rps_status()
                        end
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if plc_state.shutdown then
                log.info("OS: comms tx thread exiting")
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
                log.fatal(util.strval(result))
            end

            databus.tx_rt_status("comms_tx", false)

            if not plc_state.shutdown then
                log.info("OS: comms tx thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- communications handler thread
---@nodiscard
---@param smem plc_shared_memory
function threads.thread__comms_rx(smem)
    -- print a log message to the terminal as long as the UI isn't running
    local function println_ts(message) if not smem.plc_state.fp_ok then util.println_ts(message) end end

    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        databus.tx_rt_status("comms_rx", true)
        log.debug("OS: comms rx thread start")

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

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.NETWORK then
                        -- received a packet
                        -- handle the packet (setpoints passed to update burn rate setpoint)
                        --                   (plc_state passed to check if degraded)
                        plc_comms.handle_packet(msg.message, plc_state, setpoints, println_ts)
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if plc_state.shutdown then
                log.info("OS: comms rx thread exiting")
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
                log.fatal(util.strval(result))
            end

            databus.tx_rt_status("comms_rx", false)

            if not plc_state.shutdown then
                log.info("OS: comms rx thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- ramp control outputs to desired setpoints
---@nodiscard
---@param smem plc_shared_memory
function threads.thread__setpoint_control(smem)
    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        databus.tx_rt_status("spctl", true)
        log.debug("OS: setpoint control thread start")

        -- load in from shared memory
        local plc_state    = smem.plc_state
        local setpoints    = smem.setpoints
        local plc_dev      = smem.plc_dev

        local last_update  = util.time()
        local running      = false

        local last_burn_sp = 0.0

        -- do not use the actual elapsed time, it could spike
        -- we do not want to have big jumps as that is what we are trying to avoid in the first place
        local min_elapsed_s = SP_CTRL_SLEEP / 1000.0

        -- thread loop
        while true do
            -- get plc_sys fields (may have been set late due to degraded boot)
            local rps     = smem.plc_sys.rps
            -- get reactor, may have changed do to disconnect/reconnect
            local reactor = plc_dev.reactor

            if not plc_state.no_reactor then
                -- check if we should start ramping
                if setpoints.burn_rate_en and (setpoints.burn_rate ~= last_burn_sp) then
                    local cur_burn_rate = reactor.getBurnRate()

                    if (type(cur_burn_rate) == "number") and (setpoints.burn_rate ~= cur_burn_rate) and rps.is_active() then
                        last_burn_sp = setpoints.burn_rate

                        -- update without ramp if <= 2.5 mB/t increase
                        -- no need to ramp down, as the ramp up poses the safety risks
                        running = (setpoints.burn_rate - cur_burn_rate) > 2.5

                        if running then
                            log.debug(util.c("SPCTL: starting burn rate ramp from ", cur_burn_rate, " mB/t to ", setpoints.burn_rate, " mB/t"))
                        else
                            log.debug(util.c("SPCTL: setting burn rate directly to ", setpoints.burn_rate, " mB/t"))
                            reactor.setBurnRate(setpoints.burn_rate)
                        end
                    end
                end

                -- only check I/O if active to save on processing time
                if running then
                    -- clear so we can later evaluate if we should keep running
                    running = false

                    -- adjust burn rate (setpoints.burn_rate)
                    if setpoints.burn_rate_en then
                        if rps.is_active() then
                            local current_burn_rate = reactor.getBurnRate()

                            -- we yielded, check enable again
                            if setpoints.burn_rate_en and (type(current_burn_rate) == "number") and (current_burn_rate ~= setpoints.burn_rate) then
                                -- calculate new burn rate
                                local new_burn_rate ---@type number

                                if setpoints.burn_rate > current_burn_rate then
                                    -- need to ramp up
                                    new_burn_rate = current_burn_rate + (BURN_RATE_RAMP_mB_s * min_elapsed_s)
                                    if new_burn_rate > setpoints.burn_rate then new_burn_rate = setpoints.burn_rate end
                                else
                                    -- need to ramp down
                                    new_burn_rate = current_burn_rate - (BURN_RATE_RAMP_mB_s * min_elapsed_s)
                                    if new_burn_rate < setpoints.burn_rate then new_burn_rate = setpoints.burn_rate end
                                end

                                running = running or (new_burn_rate ~= setpoints.burn_rate)

                                -- set the burn rate
                                reactor.setBurnRate(new_burn_rate)
                            end
                        else
                            log.debug("SPCTL: ramping aborted (reactor inactive)")
                            setpoints.burn_rate_en = false
                        end
                    end
                elseif setpoints.burn_rate_en then
                    log.debug(util.c("SPCTL: ramping completed (setpoint of ", setpoints.burn_rate, " mB/t)"))
                    setpoints.burn_rate_en = false
                end

                -- if ramping completed or was aborted, reset last burn setpoint so that if it is requested again it will be re-attempted
                if not setpoints.burn_rate_en then last_burn_sp = 0 end
            end

            -- check for termination request
            if plc_state.shutdown then
                log.info("OS: setpoint control thread exiting")
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
                log.fatal(util.strval(result))
            end

            databus.tx_rt_status("spctl", false)

            if not plc_state.shutdown then
                log.info("OS: setpoint control thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

return threads

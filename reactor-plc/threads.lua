-- #REQUIRES comms.lua
-- #REQUIRES ppm.lua
-- #REQUIRES util.lua

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local MAIN_CLOCK  = 1    -- (1Hz, 20 ticks)
local ISS_CLOCK   = 0.5  -- (2Hz, 10 ticks)
local COMMS_CLOCK = 0.25 -- (4Hz, 5 ticks)

local MQ__ISS_CMD = {
    SCRAM = 1,
    DEGRADED_SCRAM = 2,
    TRIP_TIMEOUT = 3
}

local MQ__COMM_CMD = {
    SEND_STATUS = 1
}

-- main thread
function thread__main(smem, init)
    -- execute thread
    local exec = function ()
        -- send status updates at 2Hz (every 10 server ticks) (every loop tick)
        -- send link requests at 0.5Hz (every 40 server ticks) (every 4 loop ticks)
        local LINK_TICKS = 4
        local ticks_to_update = 0
        local loop_clock = nil

        -- load in from shared memory
        local networked     = smem.networked
        local plc_state     = smem.plc_state
        local plc_dev       = smem.plc_dev
        local iss           = smem.plc_sys.iss
        local plc_comms     = smem.plc_sys.plc_comms
        local conn_watchdog = smem.plc_sys.conn_watchdog

        -- debug
        local last_update = util.time()

        -- event loop
        while true do
            local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

            -- handle event
            if event == "timer" and param1 == loop_clock then
                -- core clock tick
                if networked then
                    -- start next clock timer
                    loop_clock = os.startTimer(MAIN_CLOCK)

                    -- send updated data
                    if not plc_state.no_modem then
                        if plc_comms.is_linked() then
                            smem.q.mq_comms.push_command(MQ__COMM_CMD.SEND_STATUS)
                        else
                            if ticks_to_update == 0 then
                                plc_comms.send_link_req()
                                ticks_to_update = LINK_TICKS
                            else
                                ticks_to_update = ticks_to_update - 1
                            end
                        end
                    end

                    -- debug
                    print(util.time() - last_update)
                    println("ms")
                    last_update = util.time()
                end
            elseif event == "modem_message" and networked and not plc_state.no_modem then
                -- got a packet
                -- feed the watchdog first so it doesn't uhh...eat our packets
                conn_watchdog.feed()

                -- handle the packet
                local packet = plc_comms.parse_packet(param1, param2, param3, param4, param5)
                if packet ~= nil then
                    smem.q.mq_comms.puch_packet(packet)
                end
            elseif event == "timer" and networked and param1 == conn_watchdog.get_timer() then
                -- haven't heard from server recently? shutdown reactor
                plc_comms.unlink()
                smem.q.mq_iss.push_command(MQ__ISS_CMD.TRIP_TIMEOUT)
            elseif event == "peripheral_detach" then
                -- peripheral disconnect
                local device = ppm.handle_unmount(param1)

                if device.type == "fissionReactor" then
                    println_ts("reactor disconnected!")
                    log._error("reactor disconnected!")
                    plc_state.no_reactor = true
                    plc_state.degraded = true
                    -- send an alarm: plc_comms.send_alarm(ALARMS.PLC_PERI_DC) ?
                elseif networked and device.type == "modem" then
                    -- we only care if this is our wireless modem
                    if device.dev == modem then
                        println_ts("wireless modem disconnected!")
                        log._error("comms modem disconnected!")
                        plc_state.no_modem = true

                        if plc_state.init_ok then
                            -- try to scram reactor if it is still connected
                            smem.q.mq_iss.push_command(MQ__ISS_CMD.DEGRADED_SCRAM)
                        end

                        plc_state.degraded = true
                    else
                        log._warning("non-comms modem disconnected")
                    end
                end
            elseif event == "peripheral" then
                -- peripheral connect
                local type, device = ppm.mount(param1)

                if type == "fissionReactor" then
                    -- reconnected reactor
                    plc_dev.reactor = device

                    smem.q.mq_iss.push_command(MQ__ISS_CMD.SCRAM)

                    println_ts("reactor reconnected.")
                    log._info("reactor reconnected.")
                    plc_state.no_reactor = false

                    if plc_state.init_ok then
                        iss.reconnect_reactor(plc_dev.reactor)
                        if networked then
                            plc_comms.reconnect_reactor(plc_dev.reactor)
                        end
                    end

                    -- determine if we are still in a degraded state
                    if not networked or ppm.get_device("modem") ~= nil then
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
                        log._info("comms modem reconnected.")
                        plc_state.no_modem = false

                        -- determine if we are still in a degraded state
                        if ppm.get_device("fissionReactor") ~= nil then
                            plc_state.degraded = false
                        end
                    else
                        log._info("wired modem reconnected.")
                    end
                end

                if not plc_state.init_ok and not plc_state.degraded then
                    plc_state.init_ok = true
                    init()
                end
            elseif event == "clock_start" then
                -- start loop clock
                loop_clock = os.startTimer(MAIN_CLOCK)
                log._debug("main thread started")
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                -- iss handles reactor shutdown
                plc_state.shutdown = true
                log._warning("terminate requested, main thread exiting")
                break
            end
        end
    end

    return { exec = exec }
end

-- ISS monitor thread
function thread__iss(smem)
    -- execute thread
    local exec = function ()
        -- load in from shared memory
        local networked   = smem.networked
        local plc_state   = smem.plc_state
        local plc_dev     = smem.plc_dev
        local iss         = smem.plc_sys.iss
        local plc_comms   = smem.plc_sys.plc_comms

        local iss_queue   = smem.q.mq_iss

        local last_update = util.time()

        -- thread loop
        while true do
            local reactor = smem.plc_dev.reactor
            
            -- ISS checks
            if plc_state.init_ok then
                -- if we tried to SCRAM but failed, keep trying
                -- in that case, SCRAM won't be called until it reconnects (this is the expected use of this check)
                if not plc_state.no_reactor and plc_state.scram and reactor.getStatus() then
                    reactor.scram()
                end

                -- if we are in standalone mode, continuously reset ISS
                -- ISS will trip again if there are faults, but if it isn't cleared, the user can't re-enable
                if not networked then
                    plc_state.scram = false
                    iss.reset()
                end

                -- check safety (SCRAM occurs if tripped)
                if not plc_state.degraded then
                    local iss_tripped, iss_status_string, iss_first = iss.check()
                    plc_state.scram = plc_state.scram or iss_tripped

                    if iss_first then
                        println_ts("[ISS] SCRAM! safety trip: " .. iss_status_string)
                        if networked then
                            plc_comms.send_iss_alarm(iss_status_string)
                        end
                    end
                end
            end
        
            -- check for messages in the message queue
            while comms_queue.ready() do
                local msg = comms_queue.pop()

                if msg.qtype == mqueue.TYPE.COMMAND then
                    -- received a command
                    if msg.message == MQ__ISS_CMD.SCRAM then
                        -- basic SCRAM
                        plc_state.scram = true
                        reactor.scram()
                    elseif msg.message == MQ__ISS_CMD.DEGRADED_SCRAM then
                        -- SCRAM with print
                        plc_state.scram = true
                        if reactor.scram() then
                            println_ts("successful reactor SCRAM")
                            log._error("successful reactor SCRAM")
                        else
                            println_ts("failed reactor SCRAM")
                            log._error("failed reactor SCRAM")
                        end
                    elseif msg.message == MQ__ISS_CMD.TRIP_TIMEOUT then
                        -- watchdog tripped
                        plc_state.scram = true
                        iss.trip_timeout()
                        println_ts("server timeout")
                        log._warning("server timeout")
                    end
                elseif msg.qtype == mqueue.TYPE.DATA then
                    -- received data
                elseif msg.qtype == mqueue.TYPE.PACKET then
                    -- received a packet
                end

                -- quick yield
                if iss_queue.ready() then util.nop() end
            end

            -- check for termination request
            if plc_state.shutdown then
                -- safe exit
                log._warning("iss thread shutdown initiated")
                if plc_state.init_ok then
                    plc_state.scram = true
                    reactor.scram()
                    if reactor.__p_is_ok() then
                        println_ts("reactor disabled")
                        log._info("iss thread reactor SCRAM OK")
                    else
                        -- send an alarm: plc_comms.send_alarm(ALARMS.PLC_LOST_CONTROL) ?
                        println_ts("exiting, reactor failed to disable")
                        log._error("iss thread failed to SCRAM reactor on exit")
                    end
                end
                log._warning("iss thread exiting")
                return
            end

            -- debug
            -- print(util.time() - last_update)
            -- println("ms")
            -- last_update = util.time()

            -- delay before next check
            local sleep_for = ISS_CLOCK - (util.time() - last_update)
            if sleep_for > 0.05 then
                sleep(sleep_for)
            end
        end
    end

    return { exec = exec }
end

function thread__comms(smem)
    -- execute thread
    local exec = function ()
        -- load in from shared memory
        local plc_state   = smem.plc_state
        local plc_comms   = smem.plc_sys.plc_comms

        local comms_queue = smem.q.mq_comms

        -- thread loop
        while true do
            local last_update = util.time()
        
            -- check for messages in the message queue
            while comms_queue.ready() do
                local msg = comms_queue.pop()

                if msg.qtype == mqueue.TYPE.COMMAND then
                    -- received a command
                    if msg.message == MQ__COMM_CMD.SEND_STATUS then
                        -- send PLC/ISS status
                        plc_comms.send_status(plc_state.degraded)
                        plc_comms.send_iss_status()
                    end
                elseif msg.qtype == mqueue.TYPE.DATA then
                    -- received data
                elseif msg.qtype == mqueue.TYPE.PACKET then
                    -- received a packet
                    -- handle the packet (plc_state passed to allow clearing SCRAM flag)
                    plc_comms.handle_packet(msg.message, plc_state) 
                end

                -- quick yield
                if comms_queue.ready() then util.nop() end
            end

            -- check for termination request
            if plc_state.shutdown then
                log._warning("comms thread exiting")
                return
            end

            -- delay before next check
            local sleep_for = COMMS_CLOCK - (util.time() - last_update)
            if sleep_for > 0.05 then
                sleep(sleep_for)
            end
        end
    end
end

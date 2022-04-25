-- #REQUIRES comms.lua
-- #REQUIRES ppm.lua
-- #REQUIRES plc.lua
-- #REQUIRES util.lua

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local async_wait = util.async_wait

local MAIN_CLOCK = 0.5 -- (2Hz, 10 ticks)
local ISS_CLOCK  = 0.5 -- (2Hz, 10 ticks)

local ISS_EVENT = {
    SCRAM = 1,
    DEGRADED_SCRAM = 2,
    TRIP_TIMEOUT = 3
}

-- main thread
function thread__main(shared_memory, init)
    -- execute thread
    local exec = function ()
        -- send status updates at 2Hz (every 10 server ticks) (every loop tick)
        -- send link requests at 0.5Hz (every 40 server ticks) (every 4 loop ticks)
        local LINK_TICKS = 4
        
        local loop_clock = nil
        local ticks_to_update = LINK_TICKS  -- start by linking

        -- load in from shared memory
        local networked   = shared_memory.networked
        local plc_state   = shared_memory.plc_state
        local plc_devices = shared_memory.plc_devices

        local iss           = shared_memory.system.iss
        local plc_comms     = shared_memory.system.plc_comms
        local conn_watchdog = shared_memory.system.conn_watchdog

        -- debug
        -- local last_update = util.time()

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
                            async_wait(function () 
                                plc_comms.send_status(iss_tripped, plc_state.degraded)
                                plc_comms.send_iss_status()
                            end)
                        else
                            ticks_to_update = ticks_to_update - 1

                            if ticks_to_update <= 0 then
                                plc_comms.send_link_req()
                                ticks_to_update = LINK_TICKS
                            end
                        end
                    end

                    -- debug
                    -- print(util.time() - last_update)
                    -- println("ms")
                    -- last_update = util.time()
                end
            elseif event == "modem_message" and networked and not plc_state.no_modem then
                -- got a packet
                -- feed the watchdog first so it doesn't uhh...eat our packets
                conn_watchdog.feed()

                -- handle the packet (plc_state passed to allow clearing SCRAM flag)
                local packet = plc_comms.parse_packet(p1, p2, p3, p4, p5)
                async_wait(function () plc_comms.handle_packet(packet, plc_state) end)
            elseif event == "timer" and networked and param1 == conn_watchdog.get_timer() then
                -- haven't heard from server recently? shutdown reactor
                println("timed out, passing event")
                plc_comms.unlink()
                os.queueEvent("iss_command", ISS_EVENT.TRIP_TIMEOUT)
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
                            os.queueEvent("iss_command", ISS_EVENT.DEGRADED_SCRAM)
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
                    plc_devices.reactor = device

                    os.queueEvent("iss_command", ISS_EVENT.SCRAM)

                    println_ts("reactor reconnected.")
                    log._info("reactor reconnected.")
                    plc_state.no_reactor = false

                    if plc_state.init_ok then
                        iss.reconnect_reactor(plc_devices.reactor)
                        if networked then
                            plc_comms.reconnect_reactor(plc_devices.reactor)
                        end
                    end

                    -- determine if we are still in a degraded state
                    if not networked or ppm.get_device("modem") ~= nil then
                        plc_state.degraded = false
                    end
                elseif networked and type == "modem" then
                    if device.isWireless() then
                        -- reconnected modem
                        plc_devices.modem = device

                        if plc_state.init_ok then
                            plc_comms.reconnect_modem(plc_devices.modem)
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
                log._debug("loop clock started")
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                -- iss handles reactor shutdown
                log._warning("terminate requested, main thread exiting")
                break
            end
        end
    end

    return { exec = exec }
end

-- ISS monitor thread
function thread__iss(shared_memory)
    -- execute thread
    local exec = function ()
        local loop_clock = nil

        -- load in from shared memory
        local networked   = shared_memory.networked
        local plc_state   = shared_memory.plc_state
        local plc_devices = shared_memory.plc_devices

        local iss         = shared_memory.system.iss
        local plc_comms   = shared_memory.system.plc_comms

        -- debug
        -- local last_update = util.time()

        -- event loop
        while true do
            local event, param1, param2, param3, param4, param5 = os.pullEventRaw()
            
            local reactor = shared_memory.plc_devices.reactor
    
            if event == "timer" and param1 == loop_clock then
                -- start next clock timer
                loop_clock = os.startTimer(ISS_CLOCK)

                -- ISS checks
                if plc_state.init_ok then
                    -- if we tried to SCRAM but failed, keep trying
                    -- in that case, SCRAM won't be called until it reconnects (this is the expected use of this check)
                    async_wait(function ()
                        if not plc_state.no_reactor and plc_state.scram and reactor.getStatus() then
                            reactor.scram()
                        end
                    end)

                    -- if we are in standalone mode, continuously reset ISS
                    -- ISS will trip again if there are faults, but if it isn't cleared, the user can't re-enable
                    if not networked then
                        plc_state.scram = false
                        iss.reset()
                    end

                    -- check safety (SCRAM occurs if tripped)
                    async_wait(function () 
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
                    end)
                end

                -- debug
                -- print(util.time() - last_update)
                -- println("ms")
                -- last_update = util.time()
            elseif event == "iss_command" then
                -- handle ISS commands
                println("got iss command?")
                if param1 == ISS_EVENT.SCRAM then
                    -- basic SCRAM
                    plc_state.scram = true
                    async_wait(reactor.scram)
                elseif param1 == ISS_EVENT.DEGRADED_SCRAM then
                    -- SCRAM with print
                    plc_state.scram = true
                    async_wait(function () 
                        if reactor.scram() then
                            println_ts("successful reactor SCRAM")
                            log._error("successful reactor SCRAM")
                        else
                            println_ts("failed reactor SCRAM")
                            log._error("failed reactor SCRAM")
                        end
                    end)
                elseif param1 == ISS_EVENT.TRIP_TIMEOUT then
                    -- watchdog tripped
                    plc_state.scram = true
                    iss.trip_timeout()
                    println_ts("server timeout, reactor disabled")
                    log._warning("server timeout, reactor disabled")
                end
            elseif event == "clock_start" then
                -- start loop clock
                loop_clock = os.startTimer(ISS_CLOCK)
                log._debug("loop clock started")
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                -- safe exit
                log._warning("terminate requested, iss thread shutdown")
                if plc_state.init_ok then
                    plc_state.scram = true
                    async_wait(reactor.scram)
                    if reactor.__p_is_ok() then
                        println_ts("reactor disabled")
                    else
                        -- send an alarm: plc_comms.send_alarm(ALARMS.PLC_LOST_CONTROL) ?
                        println_ts("exiting, reactor failed to disable")
                    end
                end
                break
            end
        end
    end

    return { exec = exec }
end

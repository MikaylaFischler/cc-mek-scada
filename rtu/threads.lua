-- #REQUIRES comms.lua
-- #REQUIRES log.lua
-- #REQUIRES ppm.lua
-- #REQUIRES util.lua

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local psleep = util.psleep

local MAIN_CLOCK  = 2   -- (2Hz, 40 ticks)
local COMMS_SLEEP = 150 -- (150ms, 3 ticks)

-- main thread
function thread__main(smem)
    -- execute thread
    local exec = function ()
        log._debug("main thread start")

        -- advertisement/heartbeat clock
        local loop_clock = os.startTimer(MAIN_CLOCK)

        -- load in from shared memory
        local rtu_state     = smem.rtu_state
        local rtu_dev       = smem.rtu_dev
        local rtu_comms     = smem.rtu_sys.rtu_comms
        local conn_watchdog = smem.rtu_sys.conn_watchdog
        local units         = smem.rtu_sys.units

        -- event loop
        while true do
            local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

            if event == "timer" and param1 == loop_clock then
                -- start next clock timer
                loop_clock = os.startTimer(MAIN_CLOCK)

                -- period tick, if we are linked send heartbeat, if not send advertisement
                if rtu_state.linked then
                    rtu_comms.send_heartbeat()
                else
                    -- advertise units
                    rtu_comms.send_advertisement(units)
                end
            elseif event == "modem_message" then
                -- got a packet
                local packet = rtu_comms.parse_packet(param1, param2, param3, param4, param5)
                if packet ~= nil then
                    -- pass the packet onto the comms message queue
                    smem.q.mq_comms.push_packet(packet)
                end
            elseif event == "timer" and param1 == conn_watchdog.get_timer() then
                -- haven't heard from server recently? unlink
                rtu_comms.unlink(rtu_state)
            elseif event == "peripheral_detach" then
                -- handle loss of a device
                local device = ppm.handle_unmount(param1)

                if device.type == "modem" then
                    -- we only care if this is our wireless modem
                    if device.dev == rtu_dev.modem then
                        println_ts("wireless modem disconnected!")
                        log._warning("comms modem disconnected!")
                    else
                        log._warning("non-comms modem disconnected")
                    end
                else
                    for i = 1, #units do
                        -- find disconnected device
                        if units[i].device == device.dev then
                            -- we are going to let the PPM prevent crashes
                            -- return fault flags/codes to MODBUS queries
                            local unit = units[i]
                            println_ts("lost the " .. unit.type .. " on interface " .. unit.name)
                        end
                    end
                end
            elseif event == "peripheral" then
                -- peripheral connect
                local type, device = ppm.mount(param1)

                if type == "modem" then
                    if device.isWireless() then
                        -- reconnected modem
                        rtu_dev.modem = device
                        rtu_comms.reconnect_modem(rtu_dev.modem)

                        println_ts("wireless modem reconnected.")
                        log._info("comms modem reconnected.")
                    else
                        log._info("wired modem reconnected.")
                    end
                else
                    -- relink lost peripheral to correct unit entry
                    for i = 1, #units do
                        local unit = units[i]

                        -- find disconnected device to reconnect
                        if unit.name == param1 then
                            -- found, re-link
                            unit.device = device

                            if unit.type == "boiler" then
                                unit.rtu = boiler_rtu.new(device)
                            elseif unit.type == "turbine" then
                                unit.rtu = turbine_rtu.new(device)
                            elseif unit.type == "imatrix" then
                                unit.rtu = imatrix_rtu.new(device)
                            end

                            unit.modbus_io = modbus.new(unit.rtu)

                            println_ts("reconnected the " .. unit.type .. " on interface " .. unit.name)
                        end
                    end
                end
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                rtu_state.shutdown = true
                log._info("terminate requested, main thread exiting")
                break
            end
        end
    end

    return { exec = exec }
end

-- communications handler thread
function thread__comms(smem)
    -- execute thread
    local exec = function ()
        log._debug("comms thread start")

        -- load in from shared memory
        local rtu_state     = smem.rtu_state
        local rtu_comms     = smem.rtu_sys.rtu_comms
        local conn_watchdog = smem.rtu_sys.conn_watchdog
        local units         = smem.rtu_sys.units

        local comms_queue   = smem.q.mq_comms

        local last_update   = util.time()

        -- thread loop
        while true do
            -- check for messages in the message queue
            while comms_queue.ready() and not rtu_state.shutdown do
                local msg = comms_queue.pop()

                if msg.qtype == mqueue.TYPE.COMMAND then
                    -- received a command
                elseif msg.qtype == mqueue.TYPE.DATA then
                    -- received data
                elseif msg.qtype == mqueue.TYPE.PACKET then
                    -- received a packet
                    -- handle the packet (rtu_state passed to allow setting link flag)
                    --                   (conn_watchdog passed to allow feeding watchdog)
                    rtu_comms.handle_packet(msg.message, units, rtu_state, conn_watchdog)
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if rtu_state.shutdown then
                log._info("comms thread exiting")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
        end
    end

    return { exec = exec }
end

-- per-unit communications handler thread
function thread__unit_comms(smem, unit)
    -- execute thread
    local exec = function ()
        log._debug("rtu unit thread start -> " .. unit.name .. "(" .. unit.type .. ")")

        -- load in from shared memory
        local rtu_state    = smem.rtu_state

        local packet_queue = unit.pkt_queue

        local last_update  = util.time()

        -- thread loop
        while true do
            -- check for messages in the message queue
            while packet_queue.ready() and not rtu_state.shutdown do
                local msg = packet_queue.pop()

                if msg.qtype == mqueue.TYPE.COMMAND then
                    -- received a command
                elseif msg.qtype == mqueue.TYPE.DATA then
                    -- received data
                elseif msg.qtype == mqueue.TYPE.PACKET then
                    -- received a packet
                    unit.modbus_busy = true
                    local return_code, reply = unit.modbus_io.handle_packet(packet)
                    rtu.send_modbus(reply)
                    unit.modbus_busy = false
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if rtu_state.shutdown then
                log._info("rtu unit thread exiting -> " .. unit.name .. "(" .. unit.type .. ")")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
        end
    end

    return { exec = exec }
end

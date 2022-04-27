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
        local rtu_state = smem.rtu_state
        local rtu_dev   = smem.rtu_dev
        local rtu_comms = smem.rtu_sys.rtu_comms
        local units     = smem.rtu_sys.units

        -- event loop
        while true do
            local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

            if event == "peripheral_detach" then
                -- handle loss of a device
                local device = ppm.handle_unmount(param1)

                for i = 1, #units do
                    -- find disconnected device
                    if units[i].device == device.dev then
                        -- we are going to let the PPM prevent crashes
                        -- return fault flags/codes to MODBUS queries
                        local unit = units[i]
                        println_ts("lost the " .. unit.type .. " on interface " .. unit.name)
                    end
                end
            elseif event == "peripheral" then
                -- relink lost peripheral to correct unit entry
                local type, device = ppm.mount(param1)

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
            elseif event == "timer" and param1 == loop_clock then
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
                    smem.q.mq_comms.push_packet(packet)
                end

                rtu_comms.handle_packet(packet, units, link_ref)
            end

            -- check for termination request
            if event == "terminate" or ppm.should_terminate() then
                rtu_state.shutdown = true
                log._warning("terminate requested, main thread exiting")
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
        local rtu_state   = smem.rtu_state
        local rtu_comms   = smem.rtu_sys.rtu_comms
        local units       = smem.rtu_sys.units

        local comms_queue = smem.q.mq_comms

        local last_update = util.time()

        -- thread loop
        while true do
            -- check for messages in the message queue
            while comms_queue.ready() and not plc_state.shutdown do
                local msg = comms_queue.pop()

                if msg.qtype == mqueue.TYPE.COMMAND then
                    -- received a command
                elseif msg.qtype == mqueue.TYPE.DATA then
                    -- received data
                elseif msg.qtype == mqueue.TYPE.PACKET then
                    -- received a packet
                    -- handle the packet (rtu_state passed to allow setting link flag)
                    rtu_comms.handle_packet(msg.message, units, rtu_state) 
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if rtu_state.shutdown then
                log._warning("comms thread exiting")
                break
            end

            -- delay before next check, only if >50ms since we did already yield
            local sleep_for = COMMS_SLEEP - (util.time() - last_update)
            last_update = util.time()
            if sleep_for >= 50 then
                psleep(sleep_for / 1000.0)
            end
        end
    end

    return { exec = exec }
end

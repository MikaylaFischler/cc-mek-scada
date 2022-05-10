local comms = require("scada-common.comms")
local log = require("scada-common.log")
local mqueue = require("scada-common.mqueue")
local ppm = require("scada-common.ppm")
local types = require("scada-common.types")
local util = require("scada-common.util")

local redstone_rtu = require("dev.redstone_rtu")
local boiler_rtu = require("dev.boiler_rtu")
local boilerv_rtu = require("dev.boilerv_rtu")
local energymachine_rtu = require("dev.energymachine_rtu")
local imatrix_rtu = require("dev.imatrix_rtu")
local turbine_rtu = require("dev.turbine_rtu")
local turbinev_rtu = require("dev.turbinev_rtu")

local modbus = require("modbus")

local threads = {}

local rtu_t = types.rtu_t

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local psleep = util.psleep

local MAIN_CLOCK  = 2   -- (2Hz, 40 ticks)
local COMMS_SLEEP = 150 -- (150ms, 3 ticks)

-- main thread
threads.thread__main = function (smem)
    -- execute thread
    local exec = function ()
        log.debug("main thread start")

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
---@diagnostic disable-next-line: undefined-field
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
                        log.warning("comms modem disconnected!")
                    else
                        log.warning("non-comms modem disconnected")
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
                        log.info("comms modem reconnected.")
                    else
                        log.info("wired modem reconnected.")
                    end
                else
                    -- relink lost peripheral to correct unit entry
                    for i = 1, #units do
                        local unit = units[i]

                        -- find disconnected device to reconnect
                        if unit.name == param1 then
                            -- found, re-link
                            unit.device = device

                            if unit.type == rtu_t.boiler then
                                unit.rtu = boiler_rtu.new(device)
                            elseif unit.type == rtu_t.boiler_valve then
                                unit.rtu = boilerv_rtu.new(device)
                            elseif unit.type == rtu_t.turbine then
                                unit.rtu = turbine_rtu.new(device)
                            elseif unit.type == rtu_t.turbine_valve then
                                unit.rtu = turbinev_rtu.new(device)
                            elseif unit.type == rtu_t.energy_machine then
                                unit.rtu = energymachine_rtu.new(device)
                            elseif unit.type == rtu_t.induction_matrix then
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
                log.info("terminate requested, main thread exiting")
                break
            end
        end
    end

    return { exec = exec }
end

-- communications handler thread
threads.thread__comms = function (smem)
    -- execute thread
    local exec = function ()
        log.debug("comms thread start")

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
                    rtu_comms.handle_packet(msg.message, units, rtu_state)
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if rtu_state.shutdown then
                rtu_comms.close(rtu_state)
                log.info("comms thread exiting")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
        end
    end

    return { exec = exec }
end

-- per-unit communications handler thread
threads.thread__unit_comms = function (smem, unit)
    -- execute thread
    local exec = function ()
        log.debug("rtu unit thread start -> " .. unit.name .. "(" .. unit.type .. ")")

        -- load in from shared memory
        local rtu_state    = smem.rtu_state
        local rtu_comms    = smem.rtu_sys.rtu_comms
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
                    rtu_comms.send_modbus(reply)
                    unit.modbus_busy = false
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if rtu_state.shutdown then
                log.info("rtu unit thread exiting -> " .. unit.name .. "(" .. unit.type .. ")")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
        end
    end

    return { exec = exec }
end

return threads

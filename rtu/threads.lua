local log           = require("scada-common.log")
local mqueue        = require("scada-common.mqueue")
local ppm           = require("scada-common.ppm")
local types         = require("scada-common.types")
local util          = require("scada-common.util")

local boilerv_rtu   = require("rtu.dev.boilerv_rtu")
local envd_rtu      = require("rtu.dev.envd_rtu")
local imatrix_rtu   = require("rtu.dev.imatrix_rtu")
local sna_rtu       = require("rtu.dev.sna_rtu")
local sps_rtu       = require("rtu.dev.sps_rtu")
local turbinev_rtu  = require("rtu.dev.turbinev_rtu")

local modbus = require("rtu.modbus")

local threads = {}

local rtu_t = types.rtu_t

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

local MAIN_CLOCK  = 2   -- (2Hz, 40 ticks)
local COMMS_SLEEP = 100 -- (100ms, 2 ticks)

-- main thread
---@param smem rtu_shared_memory
function threads.thread__main(smem)
    local public = {}   ---@class thread

    -- execute thread
    function public.exec()
        log.debug("main thread start")

        -- main loop clock
        local loop_clock = util.new_clock(MAIN_CLOCK)

        -- load in from shared memory
        local rtu_state     = smem.rtu_state
        local rtu_dev       = smem.rtu_dev
        local rtu_comms     = smem.rtu_sys.rtu_comms
        local conn_watchdog = smem.rtu_sys.conn_watchdog
        local units         = smem.rtu_sys.units

        -- start unlinked (in case of restart)
        rtu_comms.unlink(rtu_state)

        -- start clock
        loop_clock.start()

        -- event loop
        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            if event == "timer" and loop_clock.is_clock(param1) then
                -- start next clock timer
                loop_clock.start()

                -- period tick, if we are not linked send advertisement
                if not rtu_state.linked then
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
            elseif event == "timer" and conn_watchdog.is_timer(param1) then
                -- haven't heard from server recently? unlink
                rtu_comms.unlink(rtu_state)
            elseif event == "peripheral_detach" then
                -- handle loss of a device
                local type, device = ppm.handle_unmount(param1)

                if type ~= nil and device ~= nil then
                    if type == "modem" then
                        -- we only care if this is our wireless modem
                        if device == rtu_dev.modem then
                            println_ts("wireless modem disconnected!")
                            log.warning("comms modem disconnected!")
                        else
                            log.warning("non-comms modem disconnected")
                        end
                    else
                        for i = 1, #units do
                            -- find disconnected device
                            if units[i].device == device then
                                -- we are going to let the PPM prevent crashes
                                -- return fault flags/codes to MODBUS queries
                                local unit = units[i]
                                println_ts("lost the " .. unit.type .. " on interface " .. unit.name)
                            end
                        end
                    end
                end
            elseif event == "peripheral" then
                -- peripheral connect
                local type, device = ppm.mount(param1)

                if type ~= nil and device ~= nil then
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
                            local unit = units[i]   ---@type rtu_unit_registry_entry

                            -- find disconnected device to reconnect
                            -- note: cannot check isFormed as that would yield this coroutine and consume events
                            if unit.name == param1 then
                                local resend_advert = false

                                -- found, re-link
                                unit.device = device

                                if unit.type == "virtual" then
                                    resend_advert = true
                                    if type == "boilerValve" then
                                        -- boiler multiblock
                                        unit.type = rtu_t.boiler_valve
                                    elseif type == "turbineValve" then
                                        -- turbine multiblock
                                        unit.type = rtu_t.turbine_valve
                                    elseif type == "inductionPort" then
                                        -- induction matrix multiblock
                                        unit.type = rtu_t.induction_matrix
                                    elseif type == "spsPort" then
                                        -- SPS multiblock
                                        unit.type = rtu_t.sps
                                    elseif type == "solarNeutronActivator" then
                                        -- SNA
                                        unit.type = rtu_t.sna
                                    elseif type == "environmentDetector" then
                                        -- advanced peripherals environment detector
                                        unit.type = rtu_t.env_detector
                                    else
                                        resend_advert = false
                                        log.error(util.c("virtual device '", unit.name, "' cannot init to an unknown type (", type, ")"))
                                    end
                                end

                                if unit.type == rtu_t.boiler_valve then
                                    unit.rtu = boilerv_rtu.new(device)
                                    unit.formed = true
                                elseif unit.type == rtu_t.turbine_valve then
                                    unit.rtu = turbinev_rtu.new(device)
                                    unit.formed = true
                                elseif unit.type == rtu_t.induction_matrix then
                                    unit.rtu = imatrix_rtu.new(device)
                                    unit.formed = true
                                elseif unit.type == rtu_t.sps then
                                    unit.rtu = sps_rtu.new(device)
                                    unit.formed = true
                                elseif unit.type == rtu_t.sna then
                                    unit.rtu = sna_rtu.new(device)
                                elseif unit.type == rtu_t.env_detector then
                                    unit.rtu = envd_rtu.new(device)
                                else
                                    log.error(util.c("failed to identify reconnected RTU unit type (", unit.name, ")"), true)
                                end

                                unit.modbus_io = modbus.new(unit.rtu, true)

                                println_ts("reconnected the " .. unit.type .. " on interface " .. unit.name)
                                log.info("reconnected the " .. unit.type .. " on interface " .. unit.name)

                                if resend_advert then
                                    rtu_comms.send_advertisement(units)
                                else
                                    rtu_comms.send_remounted(unit.index)
                                end
                            end
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

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local rtu_state = smem.rtu_state

        while not rtu_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(util.strval(result))
            end

            if not rtu_state.shutdown then
                log.info("main thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- communications handler thread
---@param smem rtu_shared_memory
function threads.thread__comms(smem)
    local public = {}   ---@class thread

    -- execute thread
    function public.exec()
        log.debug("comms thread start")

        -- load in from shared memory
        local rtu_state     = smem.rtu_state
        local rtu_comms     = smem.rtu_sys.rtu_comms
        local units         = smem.rtu_sys.units

        local comms_queue   = smem.q.mq_comms

        local last_update   = util.time()

        -- thread loop
        while true do
            -- check for messages in the message queue
            while comms_queue.ready() and not rtu_state.shutdown do
                local msg = comms_queue.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- received data
                    elseif msg.qtype == mqueue.TYPE.PACKET then
                        -- received a packet
                        -- handle the packet (rtu_state passed to allow setting link flag)
                        rtu_comms.handle_packet(msg.message, units, rtu_state)
                    end
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

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local rtu_state = smem.rtu_state

        while not rtu_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(util.strval(result))
            end

            if not rtu_state.shutdown then
                log.info("comms thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- per-unit communications handler thread
---@param smem rtu_shared_memory
---@param unit rtu_unit_registry_entry
function threads.thread__unit_comms(smem, unit)
    local public = {}   ---@class thread

    -- execute thread
    function public.exec()
        log.debug("rtu unit thread start -> " .. unit.type .. "(" .. unit.name .. ")")

        -- load in from shared memory
        local rtu_state    = smem.rtu_state
        local rtu_comms    = smem.rtu_sys.rtu_comms
        local packet_queue = unit.pkt_queue

        local last_update  = util.time()

        local last_f_check = 0

        local detail_name  = util.c(unit.type, " (", unit.name, ") [", unit.index, "] for reactor ", unit.reactor)
        local short_name   = util.c(unit.type, " (", unit.name, ")")

        if packet_queue == nil then
            log.error("rtu unit thread created without a message queue, exiting...", true)
            return
        end

        -- thread loop
        while true do
            -- check for messages in the message queue
            while packet_queue.ready() and not rtu_state.shutdown do
                local msg = packet_queue.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- received data
                    elseif msg.qtype == mqueue.TYPE.PACKET then
                        -- received a packet
                        local _, reply = unit.modbus_io.handle_packet(msg.message)
                        rtu_comms.send_modbus(reply)
                    end
                end

                -- quick yield
                util.nop()
            end


            -- check if multiblock is still formed if this is a multiblock
            if (type(unit.formed) == "boolean") and (util.time() - last_f_check > 1000) then
                if (not unit.formed) and unit.device.isFormed() then
                    -- newly re-formed
                    local iface = ppm.get_iface(unit.device)
                    if iface then
                        log.info(util.c("unmounting and remounting reformed RTU unit ", detail_name))

                        ppm.unmount(unit.device)

                        local type, device = ppm.mount(iface)

                        if device ~= nil then
                            if type == "boilerValve" and unit.type == rtu_t.boiler_valve then
                                -- boiler multiblock
                                unit.device = device
                                unit.rtu = boilerv_rtu.new(device)
                                unit.formed = device.isFormed()
                                unit.modbus_io = modbus.new(unit.rtu, true)
                            elseif type == "turbineValve" and unit.type == rtu_t.turbine_valve then
                                -- turbine multiblock
                                unit.device = device
                                unit.rtu = turbinev_rtu.new(device)
                                unit.formed = device.isFormed()
                                unit.modbus_io = modbus.new(unit.rtu, true)
                            elseif type == "inductionPort" and unit.type == rtu_t.induction_matrix then
                                -- induction matrix multiblock
                                unit.device = device
                                unit.rtu = imatrix_rtu.new(device)
                                unit.formed = device.isFormed()
                                unit.modbus_io = modbus.new(unit.rtu, true)
                            elseif type == "spsPort" and unit.type == rtu_t.sps then
                                -- SPS multiblock
                                unit.device = device
                                unit.rtu = sps_rtu.new(device)
                                unit.formed = device.isFormed()
                                unit.modbus_io = modbus.new(unit.rtu, true)
                            else
                                log.error("illegal remount of non-multiblock RTU attempted for " .. short_name, true)
                            end

                            rtu_comms.send_remounted(unit.index)
                        else
                            -- fully lost the peripheral now :(
                            log.error(util.c(unit.name, " lost (failed reconnect)"))
                        end

                        log.info("reconnected the " .. unit.type .. " on interface " .. unit.name)
                    else
                        log.error("failed to get interface of previously connected RTU unit " .. detail_name, true)
                    end
                end
            end

            -- check for termination request
            if rtu_state.shutdown then
                log.info("rtu unit thread exiting -> " .. short_name)
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(COMMS_SLEEP, last_update)
        end
    end

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local rtu_state = smem.rtu_state

        while not rtu_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(util.strval(result))
            end

            if not rtu_state.shutdown then
                log.info(util.c("rtu unit thread ", unit.type, "(", unit.name, " restarting in 5 seconds..."))
                util.psleep(5)
            end
        end
    end

    return public
end

return threads

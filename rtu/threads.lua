local log          = require("scada-common.log")
local mqueue       = require("scada-common.mqueue")
local ppm          = require("scada-common.ppm")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local databus      = require("rtu.databus")
local modbus       = require("rtu.modbus")
local renderer     = require("rtu.renderer")

local boilerv_rtu  = require("rtu.dev.boilerv_rtu")
local envd_rtu     = require("rtu.dev.envd_rtu")
local imatrix_rtu  = require("rtu.dev.imatrix_rtu")
local sna_rtu      = require("rtu.dev.sna_rtu")
local sps_rtu      = require("rtu.dev.sps_rtu")
local turbinev_rtu = require("rtu.dev.turbinev_rtu")

local core         = require("graphics.core")

local threads = {}

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local UNIT_HW_STATE = databus.RTU_UNIT_HW_STATE

local MAIN_CLOCK  = 2   -- (2Hz, 40 ticks)
local COMMS_SLEEP = 100 -- (100ms, 2 ticks)

-- main thread
---@nodiscard
---@param smem rtu_shared_memory
function threads.thread__main(smem)
    -- print a log message to the terminal as long as the UI isn't running
    local function println_ts(message) if not smem.rtu_state.fp_ok then util.println_ts(message) end end

    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        databus.tx_rt_status("main", true)
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
                -- blink heartbeat indicator
                databus.heartbeat()

                -- start next clock timer
                loop_clock.start()

                -- period tick, if we are not linked send establish request
                if not rtu_state.linked then
                    -- advertise units
                    rtu_comms.send_establish(units)
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

                            databus.tx_hw_modem(false)
                        else
                            log.warning("non-comms modem disconnected")
                        end
                    else
                        for i = 1, #units do
                            -- find disconnected device
                            if units[i].device == device then
                                -- we are going to let the PPM prevent crashes
                                -- return fault flags/codes to MODBUS queries
                                local unit = units[i]   ---@type rtu_unit_registry_entry
                                local type_name = types.rtu_type_to_string(unit.type)
                                println_ts(util.c("lost the ", type_name, " on interface ", unit.name))
                                log.warning(util.c("lost the ", type_name, " unit peripheral on interface ", unit.name))
                                databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.OFFLINE)
                                break
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
                            log.info("comms modem reconnected")

                            databus.tx_hw_modem(true)
                        else
                            log.info("wired modem reconnected")
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

                                if unit.type == RTU_UNIT_TYPE.VIRTUAL then
                                    resend_advert = true
                                    if type == "boilerValve" then
                                        -- boiler multiblock
                                        unit.type = RTU_UNIT_TYPE.BOILER_VALVE
                                    elseif type == "turbineValve" then
                                        -- turbine multiblock
                                        unit.type = RTU_UNIT_TYPE.TURBINE_VALVE
                                    elseif type == "inductionPort" then
                                        -- induction matrix multiblock
                                        unit.type = RTU_UNIT_TYPE.IMATRIX
                                    elseif type == "spsPort" then
                                        -- SPS multiblock
                                        unit.type = RTU_UNIT_TYPE.SPS
                                    elseif type == "solarNeutronActivator" then
                                        -- SNA
                                        unit.type = RTU_UNIT_TYPE.SNA
                                    elseif type == "environmentDetector" then
                                        -- advanced peripherals environment detector
                                        unit.type = RTU_UNIT_TYPE.ENV_DETECTOR
                                    else
                                        resend_advert = false
                                        log.error(util.c("virtual device '", unit.name, "' cannot init to an unknown type (", type, ")"))
                                    end

                                    databus.tx_unit_hw_type(unit.uid, unit.type)
                                end

                                if unit.type == RTU_UNIT_TYPE.BOILER_VALVE then
                                    unit.rtu = boilerv_rtu.new(device)
                                     -- if not formed, indexing the multiblock functions would have resulted in a PPM fault
                                    unit.formed = util.trinary(device.__p_is_faulted(), false, nil)
                                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.UNFORMED)
                                elseif unit.type == RTU_UNIT_TYPE.TURBINE_VALVE then
                                    unit.rtu = turbinev_rtu.new(device)
                                     -- if not formed, indexing the multiblock functions would have resulted in a PPM fault
                                    unit.formed = util.trinary(device.__p_is_faulted(), false, nil)
                                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.UNFORMED)
                                elseif unit.type == RTU_UNIT_TYPE.IMATRIX then
                                    unit.rtu = imatrix_rtu.new(device)
                                     -- if not formed, indexing the multiblock functions would have resulted in a PPM fault
                                    unit.formed = util.trinary(device.__p_is_faulted(), false, nil)
                                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.UNFORMED)
                                elseif unit.type == RTU_UNIT_TYPE.SPS then
                                    unit.rtu = sps_rtu.new(device)
                                     -- if not formed, indexing the multiblock functions would have resulted in a PPM fault
                                    unit.formed = util.trinary(device.__p_is_faulted(), false, nil)
                                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.UNFORMED)
                                elseif unit.type == RTU_UNIT_TYPE.SNA then
                                    unit.rtu = sna_rtu.new(device)
                                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.OK)
                                elseif unit.type == RTU_UNIT_TYPE.ENV_DETECTOR then
                                    unit.rtu = envd_rtu.new(device)
                                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.OK)
                                else
                                    log.error(util.c("failed to identify reconnected RTU unit type (", unit.name, ")"), true)
                                end

                                if unit.is_multiblock then
                                    if (unit.formed == false) then
                                        log.info(util.c("assuming ", unit.name, " is not formed due to PPM faults while initializing"))
                                        databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.UNFORMED)
                                    end
                                elseif device.__p_is_faulted() then
                                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.FAULTED)
                                else
                                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.OK)
                                end

                                unit.modbus_io = modbus.new(unit.rtu, true)

                                local type_name = types.rtu_type_to_string(unit.type)
                                local message = util.c("reconnected the ", type_name, " on interface ", unit.name)
                                println_ts(message)
                                log.info(message)

                                if resend_advert then
                                    rtu_comms.send_advertisement(units)
                                else
                                    rtu_comms.send_remounted(unit.uid)
                                end
                            end
                        end
                    end
                end
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" then
                -- handle a mouse event
                renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
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

            databus.tx_rt_status("main", false)

            if not rtu_state.shutdown then
                log.info("main thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- communications handler thread
---@nodiscard
---@param smem rtu_shared_memory
function threads.thread__comms(smem)
    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        databus.tx_rt_status("comms", true)
        log.debug("comms thread start")

        -- load in from shared memory
        local rtu_state   = smem.rtu_state
        local rtu_comms   = smem.rtu_sys.rtu_comms
        local units       = smem.rtu_sys.units

        local comms_queue = smem.q.mq_comms

        local last_update = util.time()

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

            databus.tx_rt_status("comms", false)

            if not rtu_state.shutdown then
                log.info("comms thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

-- per-unit communications handler thread
---@nodiscard
---@param smem rtu_shared_memory
---@param unit rtu_unit_registry_entry
function threads.thread__unit_comms(smem, unit)
    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        databus.tx_rt_status("unit_" .. unit.uid, true)
        log.debug(util.c("rtu unit thread start -> ", types.rtu_type_to_string(unit.type), " (", unit.name, ")"))

        -- load in from shared memory
        local rtu_state    = smem.rtu_state
        local rtu_comms    = smem.rtu_sys.rtu_comms
        local packet_queue = unit.pkt_queue

        local last_update  = util.time()

        local last_f_check = 0

        local detail_name  = util.c(types.rtu_type_to_string(unit.type), " (", unit.name, ") [", unit.index, "] for reactor ", unit.reactor)
        local short_name   = util.c(types.rtu_type_to_string(unit.type), " (", unit.name, ")")

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

                        -- check if there was a problem and update the hardware state if so
                        local frame = reply.get()
                        if unit.formed and (bit.band(frame.func_code, types.MODBUS_FCODE.ERROR_FLAG) ~= 0) and
                           (frame.data[1] == types.MODBUS_EXCODE.SERVER_DEVICE_FAIL) then
                            databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.FAULTED)
                        end
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check if multiblock is still formed if this is a multiblock
            if unit.is_multiblock and (util.time_ms() - last_f_check > 250) then
                local is_formed = unit.device.isFormed()

                last_f_check = util.time_ms()

                if unit.formed == nil then
                    unit.formed = is_formed
                    if is_formed then databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.OK) end
                end

                if not unit.formed then
                    databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.UNFORMED)
                end

                if (not unit.formed) and is_formed then
                    -- newly re-formed
                    local iface = ppm.get_iface(unit.device)
                    if iface then
                        log.info(util.c("unmounting and remounting reformed RTU unit ", detail_name))

                        ppm.unmount(unit.device)

                        local type, device = ppm.mount(iface)
                        local faulted = false

                        if device ~= nil then
                            if type == "boilerValve" and unit.type == RTU_UNIT_TYPE.BOILER_VALVE then
                                -- boiler multiblock
                                unit.device = device
                                unit.rtu, faulted = boilerv_rtu.new(device)
                                unit.formed = device.isFormed()
                                unit.modbus_io = modbus.new(unit.rtu, true)
                            elseif type == "turbineValve" and unit.type == RTU_UNIT_TYPE.TURBINE_VALVE then
                                -- turbine multiblock
                                unit.device = device
                                unit.rtu, faulted = turbinev_rtu.new(device)
                                unit.formed = device.isFormed()
                                unit.modbus_io = modbus.new(unit.rtu, true)
                            elseif type == "inductionPort" and unit.type == RTU_UNIT_TYPE.IMATRIX then
                                -- induction matrix multiblock
                                unit.device = device
                                unit.rtu, faulted = imatrix_rtu.new(device)
                                unit.formed = device.isFormed()
                                unit.modbus_io = modbus.new(unit.rtu, true)
                            elseif type == "spsPort" and unit.type == RTU_UNIT_TYPE.SPS then
                                -- SPS multiblock
                                unit.device = device
                                unit.rtu, faulted = sps_rtu.new(device)
                                unit.formed = device.isFormed()
                                unit.modbus_io = modbus.new(unit.rtu, true)
                            else
                                log.error("illegal remount of non-multiblock RTU or type change attempted for " .. short_name, true)
                            end

                            if unit.formed and faulted then
                                -- something is still wrong = can't mark as formed yet
                                unit.formed = false
                                log.info(util.c("assuming ", unit.name, " is not formed due to PPM faults while initializing"))
                                databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.UNFORMED)
                            else
                                rtu_comms.send_remounted(unit.uid)
                                databus.tx_unit_hw_status(unit.uid, UNIT_HW_STATE.OK)
                            end

                            local type_name = types.rtu_type_to_string(unit.type)
                            log.info(util.c("reconnected the ", type_name, " on interface ", unit.name))
                        else
                            -- fully lost the peripheral now :(
                            log.error(util.c(unit.name, " lost (failed reconnect)"))
                        end
                    else
                        log.error("failed to get interface of previously connected RTU unit " .. detail_name, true)
                    end
                end

                unit.formed = is_formed
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

            databus.tx_rt_status("unit_" .. unit.uid, false)

            if not rtu_state.shutdown then
                log.info(util.c("rtu unit thread ", types.rtu_type_to_string(unit.type), " (", unit.name, ") restarting in 5 seconds..."))
                util.psleep(5)
            end
        end
    end

    return public
end

return threads

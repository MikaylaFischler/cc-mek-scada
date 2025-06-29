local log          = require("scada-common.log")
local mqueue       = require("scada-common.mqueue")
local ppm          = require("scada-common.ppm")
local tcd          = require("scada-common.tcd")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local databus      = require("rtu.databus")
local modbus       = require("rtu.modbus")
local renderer     = require("rtu.renderer")
local rtu          = require("rtu.rtu")

local boilerv_rtu  = require("rtu.dev.boilerv_rtu")
local dynamicv_rtu = require("rtu.dev.dynamicv_rtu")
local envd_rtu     = require("rtu.dev.envd_rtu")
local imatrix_rtu  = require("rtu.dev.imatrix_rtu")
local sna_rtu      = require("rtu.dev.sna_rtu")
local sps_rtu      = require("rtu.dev.sps_rtu")
local turbinev_rtu = require("rtu.dev.turbinev_rtu")

local core         = require("graphics.core")

local threads = {}

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local RTU_HW_STATE = databus.RTU_HW_STATE

local MAIN_CLOCK  = 0.5 -- (2Hz,  10 ticks)
local COMMS_SLEEP = 100 -- (100ms, 2 ticks)

---@param smem rtu_shared_memory
---@param println_ts function
---@param iface string
---@param type string
---@param device table
---@param unit rtu_registry_entry
local function handle_unit_mount(smem, println_ts, iface, type, device, unit)
    local sys = smem.rtu_sys

    -- find disconnected device to reconnect
    -- note: cannot check isFormed as that would yield this coroutine and consume events
    if unit.name == iface then
        local resend_advert, faulted, unknown, invalid = false, false, false, false

        local function fail(msg)
            invalid = true
            log.error(msg .. " in config")
        end

        -- found, re-link
        unit.device = device

        if unit.type == RTU_UNIT_TYPE.VIRTUAL then
            resend_advert = true
            if type == "boilerValve" then
                -- boiler multiblock
                if unit.reactor < 1 or unit.reactor > 4 then fail(util.c("boiler '", unit.name, "' cannot init, not assigned to a valid unit")) end
                if (unit.index == false) or unit.index < 1 or unit.index > 2 then fail(util.c("boiler '", unit.name, "' cannot init, invalid index provided")) end

                unit.type = RTU_UNIT_TYPE.BOILER_VALVE
            elseif type == "turbineValve" then
                -- turbine multiblock
                if unit.reactor < 1 or unit.reactor > 4 then fail(util.c("turbine '", unit.name, "' cannot init, not assigned to a valid unit")) end
                if (unit.index == false) or unit.index < 1 or unit.index > 3 then fail(util.c("turbine '", unit.name, "' cannot init, invalid index provided")) end

                unit.type = RTU_UNIT_TYPE.TURBINE_VALVE
            elseif type == "dynamicValve" then
                -- dynamic tank multiblock
                if unit.reactor < 0 or unit.reactor > 4 then fail(util.c("dynamic tank '", unit.name, "' cannot init, no valid assignment provided")) end

                if (unit.reactor == 0 and ((unit.index == false) or unit.index < 1 or unit.index > 4)) or
                   (unit.reactor > 0 and unit.index ~= 1) then
                    fail(util.c("dynamic tank '", unit.name, "' cannot init, invalid index provided"))
                end

                unit.type = RTU_UNIT_TYPE.DYNAMIC_VALVE
            elseif type == "inductionPort" then
                -- induction matrix multiblock
                if unit.reactor ~= 0 then fail(util.c("induction matrix '", unit.name, "' cannot init, not assigned to facility")) end

                unit.type = RTU_UNIT_TYPE.IMATRIX
            elseif type == "spsPort" then
                -- SPS multiblock
                if unit.reactor ~= 0 then fail(util.c("SPS '", unit.name, "' cannot init, not assigned to facility")) end

                unit.type = RTU_UNIT_TYPE.SPS
            elseif type == "solarNeutronActivator" then
                -- SNA
                if unit.reactor < 1 or unit.reactor > 4 then fail(util.c("SNA '", unit.name, "' cannot init, not assigned to a valid unit")) end

                unit.type = RTU_UNIT_TYPE.SNA
            elseif type == "environmentDetector" or type == "environment_detector"  then
                -- advanced peripherals environment detector
                if unit.reactor < 0 or unit.reactor > 4 then fail(util.c("environment detector '", unit.name, "' cannot init, no valid assignment provided")) end
                if (unit.index == false) or unit.index < 1 then fail(util.c("environment detector '", unit.name, "' cannot init, invalid index provided")) end

                unit.type = RTU_UNIT_TYPE.ENV_DETECTOR
            else
                resend_advert = false
                log.error(util.c("virtual device '", unit.name, "' cannot init to an unknown type (", type, ")"))
            end

            databus.tx_unit_hw_type(unit.uid, unit.type)
        end

        -- if disconnected on startup, config wouldn't have been validated
        -- checking now that it has connected; the config isn't valid, so don't connect it
        if invalid then
            unit.hw_state = RTU_HW_STATE.OFFLINE
            databus.tx_unit_hw_status(unit.uid, unit.hw_state)
            return
        end

        -- note for multiblock structures: if not formed, indexing the multiblock functions results in a PPM fault

        if unit.type == RTU_UNIT_TYPE.BOILER_VALVE then
            unit.rtu, faulted = boilerv_rtu.new(device)
            unit.formed = util.trinary(faulted, false, nil)
        elseif unit.type == RTU_UNIT_TYPE.TURBINE_VALVE then
            unit.rtu, faulted = turbinev_rtu.new(device)
            unit.formed = util.trinary(faulted, false, nil)
        elseif unit.type == RTU_UNIT_TYPE.DYNAMIC_VALVE then
            unit.rtu, faulted = dynamicv_rtu.new(device)
            unit.formed = util.trinary(faulted, false, nil)
        elseif unit.type == RTU_UNIT_TYPE.IMATRIX then
            unit.rtu, faulted = imatrix_rtu.new(device)
            unit.formed = util.trinary(faulted, false, nil)
        elseif unit.type == RTU_UNIT_TYPE.SPS then
            unit.rtu, faulted = sps_rtu.new(device)
            unit.formed = util.trinary(faulted, false, nil)
        elseif unit.type == RTU_UNIT_TYPE.SNA then
            unit.rtu, faulted = sna_rtu.new(device)
        elseif unit.type == RTU_UNIT_TYPE.ENV_DETECTOR then
            unit.rtu, faulted = envd_rtu.new(device)
        elseif unit.type == RTU_UNIT_TYPE.REDSTONE then
            unit.rtu.remount_phy(device)
        else
            unknown = true
            log.error(util.c("failed to identify reconnected RTU unit type (", unit.name, ")"), true)
        end

        if unit.is_multiblock then
            unit.hw_state = RTU_HW_STATE.UNFORMED
            if unit.formed == false then
                log.info(util.c("assuming ", unit.name, " is not formed due to PPM faults while initializing"))
            end
        elseif faulted then
            unit.hw_state = RTU_HW_STATE.FAULTED
        elseif not unknown then
            unit.hw_state = RTU_HW_STATE.OK
        else
            unit.hw_state = RTU_HW_STATE.OFFLINE
        end

        databus.tx_unit_hw_status(unit.uid, unit.hw_state)

        if not unknown then
            unit.modbus_io = modbus.new(unit.rtu, true)

            local type_name = types.rtu_type_to_string(unit.type)
            local message = util.c("reconnected the ", type_name, " on interface ", unit.name)
            println_ts(message)
            log.info(message)

            if resend_advert then
                sys.rtu_comms.send_advertisement(sys.units)
            else
                sys.rtu_comms.send_remounted(unit.uid)
            end
        end
    end
end

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
        local sounders      = smem.rtu_dev.sounders
        local nic           = smem.rtu_sys.nic
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

                -- update speaker states
                for _, sounder in pairs(sounders) do
                    -- re-compute output if needed, then play audio if available
                    if sounder.stream.is_recompute_needed() then
                        sounder.stream.compute_buffer()
                        if sounder.stream.any_active() then sounder.play() else sounder.stop() end
                    end
                end

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
                -- haven't heard from server recently? close connection
                rtu_comms.close(rtu_state)
            elseif event == "timer" then
                -- notify timer callback dispatcher if no other timer case claimed this event
                tcd.handle(param1)
            elseif event == "peripheral_detach" then
                -- handle loss of a device
                local type, device = ppm.handle_unmount(param1)

                if type ~= nil and device ~= nil then
                    if type == "modem" then
                        ---@cast device Modem
                        -- we only care if this is our wireless modem
                        if nic.is_modem(device) then
                            nic.disconnect()

                            println_ts("wireless modem disconnected!")
                            log.warning("comms modem disconnected")

                            local other_modem = ppm.get_wireless_modem()
                            if other_modem then
                                log.info("found another wireless modem, using it for comms")
                                nic.connect(other_modem)
                            else
                                databus.tx_hw_modem(false)
                            end
                        else
                            log.warning("non-comms modem disconnected")
                        end
                    elseif type == "speaker" then
                        ---@cast device Speaker
                        for i = 1, #sounders do
                            if sounders[i].speaker == device then
                                table.remove(sounders, i)

                                log.warning(util.c("speaker ", param1, " disconnected"))
                                println_ts("speaker disconnected")

                                databus.tx_hw_spkr_count(#sounders)
                                break
                            end
                        end
                    else
                        for i = 1, #units do
                            -- find disconnected device
                            if units[i].device == device then
                                -- will let the PPM prevent crashes, which will indicate failures in MODBUS queries
                                local unit = units[i]
                                local type_name = types.rtu_type_to_string(unit.type)

                                println_ts(util.c("lost the ", type_name, " on interface ", unit.name))
                                log.warning(util.c("lost the ", type_name, " unit peripheral on interface ", unit.name))

                                unit.hw_state = RTU_HW_STATE.OFFLINE
                                databus.tx_unit_hw_status(unit.uid, unit.hw_state)
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
                        ---@cast device Modem
                        if device.isWireless() and not nic.is_connected() then
                            -- reconnected modem
                            nic.connect(device)

                            println_ts("wireless modem reconnected.")
                            log.info("comms modem reconnected")

                            databus.tx_hw_modem(true)
                        elseif device.isWireless() then
                            log.info("unused wireless modem reconnected")
                        else
                            log.info("wired modem reconnected")
                        end
                    elseif type == "speaker" then
                        ---@cast device Speaker
                        table.insert(sounders, rtu.init_sounder(device))

                        println_ts("speaker connected")
                        log.info(util.c("connected speaker ", param1))

                        databus.tx_hw_spkr_count(#sounders)
                    else
                        -- relink lost peripheral to correct unit entry
                        for i = 1, #units do
                            handle_unit_mount(smem, println_ts, param1, type, device, units[i])
                        end
                    end
                end
            elseif event == "mouse_click" or event == "mouse_up" or event == "mouse_drag" or event == "mouse_scroll" or
                   event == "double_click" then
                -- handle a mouse event
                renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
            elseif event == "speaker_audio_empty" then
                -- handle empty speaker audio buffer
                for i = 1, #sounders do
                    local sounder = sounders[i]
                    if sounder.name == param1 then
                        sounder.continue()
                        break
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
        local sounders    = smem.rtu_dev.sounders
        local rtu_comms   = smem.rtu_sys.rtu_comms
        local units       = smem.rtu_sys.units

        local comms_queue = smem.q.mq_comms

        local last_update = util.time()

        -- thread loop
        while true do
            local handle_start = util.time()

            -- check for messages in the message queue while not shut down
            while comms_queue.ready() and not rtu_state.shutdown do
                local msg = comms_queue.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- received data
                    elseif msg.qtype == mqueue.TYPE.PACKET then
                        -- received a packet
                        -- handle the packet (rtu_state passed to allow setting link flag, sounders passed to manage alarm audio)
                        rtu_comms.handle_packet(msg.message, units, rtu_state, sounders)
                    end
                end

                -- max 100ms spent processing queue
                if util.time() - handle_start > 100 then
                    log.warning("comms thread exceeded 100ms queue process limit")
                    break
                end
            end

            -- quick yield
            util.nop()

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
---@param unit rtu_registry_entry
function threads.thread__unit_comms(smem, unit)
    -- print a log message to the terminal as long as the UI isn't running
    local function println_ts(message) if not smem.rtu_state.fp_ok then util.println_ts(message) end end

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

        local detail_name  = util.c(types.rtu_type_to_string(unit.type), " (", unit.name, ") ",
                                util.trinary(unit.index == false, "", util.c("[", unit.index, "] ")), "for ",
                                util.trinary(unit.reactor == 0, "the facility", util.c("reactor ", unit.reactor)))
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
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if rtu_state.shutdown then
                log.info("rtu unit thread exiting -> " .. short_name)
                break
            end

            -- check if multiblock is still formed if this is a multiblock
            if unit.is_multiblock and (util.time_ms() - last_f_check > 250) then
                last_f_check = util.time_ms()

                local is_formed = unit.device.isFormed()

                if unit.formed == nil then
                    unit.formed = is_formed
                    if is_formed then unit.hw_state = RTU_HW_STATE.OK end
                elseif not unit.formed then
                    unit.hw_state = RTU_HW_STATE.UNFORMED
                end

                if (is_formed == true) and not unit.formed then
                    unit.hw_state = RTU_HW_STATE.OK
                    log.info(util.c(detail_name, " is now formed"))
                    rtu_comms.send_remounted(unit.uid)
                elseif (is_formed == false) and unit.formed then
                    log.warning(util.c(detail_name, " is no longer formed"))
                elseif (is_formed == nil) and (unit.hw_state ~= RTU_HW_STATE.OFFLINE) then
                    log.error(util.c(detail_name, " failed to check if formed, attempting remount..."))

                    local type, dev = ppm.remount(unit.name)
                    if type and dev then
                        handle_unit_mount(smem, println_ts, unit.name, type, dev, unit)
                    else
                        log.error(util.c(detail_name, " failed to remount"))
                    end
                end

                unit.formed = is_formed
            end

            -- check hardware status
            if unit.device.__p_is_healthy() then
                if unit.hw_state == RTU_HW_STATE.FAULTED then unit.hw_state = RTU_HW_STATE.OK end
            else
                if unit.hw_state == RTU_HW_STATE.OK then unit.hw_state = RTU_HW_STATE.FAULTED end
            end

            -- update hw status
            databus.tx_unit_hw_status(unit.uid, unit.hw_state)

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

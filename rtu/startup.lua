--
-- RTU: Remote Terminal Unit
--

require("/initenv").init_env()

local audio        = require("scada-common.audio")
local comms        = require("scada-common.comms")
local crash        = require("scada-common.crash")
local log          = require("scada-common.log")
local mqueue       = require("scada-common.mqueue")
local network      = require("scada-common.network")
local ppm          = require("scada-common.ppm")
local rsio         = require("scada-common.rsio")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local configure    = require("rtu.configure")
local databus      = require("rtu.databus")
local modbus       = require("rtu.modbus")
local renderer     = require("rtu.renderer")
local rtu          = require("rtu.rtu")
local threads      = require("rtu.threads")

local boilerv_rtu  = require("rtu.dev.boilerv_rtu")
local dynamicv_rtu = require("rtu.dev.dynamicv_rtu")
local envd_rtu     = require("rtu.dev.envd_rtu")
local imatrix_rtu  = require("rtu.dev.imatrix_rtu")
local redstone_rtu = require("rtu.dev.redstone_rtu")
local sna_rtu      = require("rtu.dev.sna_rtu")
local sps_rtu      = require("rtu.dev.sps_rtu")
local turbinev_rtu = require("rtu.dev.turbinev_rtu")

local RTU_VERSION = "v1.11.6"

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local RTU_HW_STATE = databus.RTU_HW_STATE

local println = util.println
local println_ts = util.println_ts

----------------------------------------
-- get configuration
----------------------------------------

if not rtu.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not rtu.load_config() then
            println("failed to load a valid configuration, please reconfigure")
            return
        end
    else
        println("configuration error: " .. error)
        return
    end
end

local config = rtu.config

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING rtu.startup " .. RTU_VERSION)
log.info("========================================")
println(">> RTU GATEWAY " .. RTU_VERSION .. " <<")

crash.set_env("rtu", RTU_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- startup
    ----------------------------------------

    -- record firmware versions and ID
    databus.tx_versions(RTU_VERSION, comms.version)

    -- mount connected devices
    ppm.mount_all()

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
    end

    -- generate alarm tones
    audio.generate_tones()

    ---@class rtu_shared_memory
    local __shared_memory = {
        -- RTU system state flags
        ---@class rtu_state
        rtu_state = {
            fp_ok = false,
            linked = false,
            shutdown = false
        },

        -- RTU gateway devices (not RTU units)
        rtu_dev = {
            modem = ppm.get_wireless_modem(),
            sounders = {}        ---@type rtu_speaker_sounder[]
        },

        -- system objects
        rtu_sys = {
            nic = nil,           ---@type nic
            rtu_comms = nil,     ---@type rtu_comms
            conn_watchdog = nil, ---@type watchdog
            units = {}           ---@type rtu_registry_entry[]
        },

        -- message queues
        q = {
            mq_comms = mqueue.new()
        }
    }

    local smem_sys = __shared_memory.rtu_sys
    local smem_dev = __shared_memory.rtu_dev

    local rtu_state = __shared_memory.rtu_state

    ----------------------------------------
    -- interpret config and init units
    ----------------------------------------

    local units = __shared_memory.rtu_sys.units

    local rtu_redstone = config.Redstone
    local rtu_devices = config.Peripherals

    -- configure RTU gateway based on settings file definitions
    local function sys_config()
        -- redstone interfaces
        local rs_rtus = {}  ---@type { rtu: rtu_rs_device, capabilities: IO_PORT[] }[]

        -- go through redstone definitions list
        for entry_idx = 1, #rtu_redstone do
            local entry = rtu_redstone[entry_idx]
            local assignment
            local for_reactor = entry.unit
            local iface_name = util.trinary(entry.color ~= nil, util.c(entry.side, "/", rsio.color_name(entry.color)), entry.side)

            if util.is_int(entry.unit) and entry.unit > 0 and entry.unit < 5 then
                ---@cast for_reactor integer
                assignment = "reactor unit " .. entry.unit
                if rs_rtus[for_reactor] == nil then
                    log.debug(util.c("sys_config> allocated redstone RTU for reactor unit ", entry.unit))
                    rs_rtus[for_reactor] = { rtu = redstone_rtu.new(), capabilities = {} }
                end
            elseif entry.unit == nil then
                assignment = "facility"
                for_reactor = 0
                if rs_rtus[for_reactor] == nil then
                    log.debug(util.c("sys_config> allocated redstone RTU for the facility"))
                    rs_rtus[for_reactor] = { rtu = redstone_rtu.new(), capabilities = {} }
                end
            else
                local message = util.c("sys_config> invalid unit assignment at block index #", entry_idx)
                println(message)
                log.fatal(message)
                return false
            end

            -- verify configuration
            local valid = false
            if rsio.is_valid_port(entry.port) and rsio.is_valid_side(entry.side) then
                valid = util.trinary(entry.color == nil, true, rsio.is_color(entry.color))
            end

            local rs_rtu = rs_rtus[for_reactor].rtu
            local capabilities = rs_rtus[for_reactor].capabilities

            if not valid then
                local message = util.c("sys_config> invalid redstone definition at block index #", entry_idx)
                println(message)
                log.fatal(message)
                return false
            else
                -- link redstone in RTU
                local mode = rsio.get_io_mode(entry.port)
                if mode == rsio.IO_MODE.DIGITAL_IN then
                    -- can't have duplicate inputs
                    if util.table_contains(capabilities, entry.port) then
                        local message = util.c("sys_config> skipping duplicate input for port ", rsio.to_string(entry.port), " on side ", iface_name)
                        println(message)
                        log.warning(message)
                    else
                        rs_rtu.link_di(entry.side, entry.color)
                    end
                elseif mode == rsio.IO_MODE.DIGITAL_OUT then
                    rs_rtu.link_do(entry.side, entry.color)
                elseif mode == rsio.IO_MODE.ANALOG_IN then
                    -- can't have duplicate inputs
                    if util.table_contains(capabilities, entry.port) then
                        local message = util.c("sys_config> skipping duplicate input for port ", rsio.to_string(entry.port), " on side ", iface_name)
                        println(message)
                        log.warning(message)
                    else
                        rs_rtu.link_ai(entry.side)
                    end
                elseif mode == rsio.IO_MODE.ANALOG_OUT then
                    rs_rtu.link_ao(entry.side)
                else
                    -- should be unreachable code, we already validated ports
                    log.error("sys_config> fell through if chain attempting to identify IO mode at block index #" .. entry_idx, true)
                    println("sys_config> encountered a software error, check logs")
                    return false
                end

                table.insert(capabilities, entry.port)

                log.debug(util.c("sys_config> linked redstone ", #capabilities, ": ", rsio.to_string(entry.port), " (", iface_name, ") for ", assignment))
            end
        end

        -- create unit entries for redstone RTUs
        for for_reactor, def in pairs(rs_rtus) do
            ---@class rtu_registry_entry
            local unit = {
                uid = 0,                        ---@type integer
                name = "redstone_io",           ---@type string
                type = RTU_UNIT_TYPE.REDSTONE,  ---@type RTU_UNIT_TYPE
                index = false,                  ---@type integer|false
                reactor = for_reactor,          ---@type integer
                device = def.capabilities,      ---@type IO_PORT[] use device field for redstone ports
                is_multiblock = false,          ---@type boolean
                formed = nil,                   ---@type boolean|nil
                hw_state = RTU_HW_STATE.OK,     ---@type RTU_HW_STATE
                rtu = def.rtu,                  ---@type rtu_device|rtu_rs_device
                modbus_io = modbus.new(def.rtu, false),
                pkt_queue = nil,                ---@type mqueue|nil
                thread = nil                    ---@type parallel_thread|nil
            }

            table.insert(units, unit)

            local for_message = "facility"
            if util.is_int(for_reactor) then
                for_message = util.c("reactor unit ", for_reactor)
            end

            log.info(util.c("sys_config> initialized RTU unit #", #units, ": redstone_io (redstone) [1] for ", for_message))

            unit.uid = #units

            databus.tx_unit_hw_status(unit.uid, unit.hw_state)
        end

        -- mounted peripherals
        for i = 1, #rtu_devices do
            local entry = rtu_devices[i]   ---@type rtu_peri_definition
            local name = entry.name
            local index = entry.index
            local for_reactor = util.trinary(entry.unit == nil, 0, entry.unit)

            -- CHECK: name is a string
            if type(name) ~= "string" then
                local message = util.c("sys_config> device entry #", i, ": device ", name, " isn't a string")
                println(message)
                log.fatal(message)
                return false
            end

            -- CHECK: index type
            if (index ~= nil) and (not util.is_int(index)) then
                local message = util.c("sys_config> device entry #", i, ": index ", index, " isn't valid")
                println(message)
                log.fatal(message)
                return false
            end

            -- CHECK: index range
            local function validate_index(min, max)
                if (not util.is_int(index)) or ((index < min) and (max ~= nil and index > max)) then
                    local message = util.c("sys_config> device entry #", i, ": index ", index, " isn't >= ", min)
                    if max ~= nil then message = util.c(message, " and <= ", max) end
                    println(message)
                    log.fatal(message)
                    return false
                else return true end
            end

            -- CHECK: reactor is an integer >= 0
            local function validate_assign(for_facility)
                if for_facility and for_reactor ~= 0 then
                    local message = util.c("sys_config> device entry #", i, ": must only be for the facility")
                    println(message)
                    log.fatal(message)
                    return false
                elseif (not for_facility) and ((not util.is_int(for_reactor)) or (for_reactor < 1) or (for_reactor > 4)) then
                    local message = util.c("sys_config> device entry #", i, ": unit assignment ", for_reactor, " isn't vaild")
                    println(message)
                    log.fatal(message)
                    return false
                else return true end
            end

            local device = ppm.get_periph(name)

            local type                  ---@type string|nil
            local rtu_iface             ---@type rtu_device
            local rtu_type              ---@type RTU_UNIT_TYPE
            local is_multiblock = false ---@type boolean
            local formed = nil          ---@type boolean|nil
            local faulted = nil         ---@type boolean|nil

            if device == nil then
                local message = util.c("sys_config> '", name, "' not found, using placeholder")
                println(message)
                log.warning(message)

                -- mount a virtual (placeholder) device
                type, device = ppm.mount_virtual()
            else
                type = ppm.get_type(name)
            end

            if type == "boilerValve" then
                -- boiler multiblock
                if not validate_index(1, 2) then return false end
                if not validate_assign() then return false end

                rtu_type = RTU_UNIT_TYPE.BOILER_VALVE
                rtu_iface, faulted = boilerv_rtu.new(device)
                is_multiblock = true
                formed = device.isFormed()

                if formed == ppm.ACCESS_FAULT then
                    println_ts(util.c("sys_config> failed to check if '", name, "' is formed"))
                    log.warning(util.c("sys_config> failed to check if '", name, "' is a formed boiler multiblock"))
                end
            elseif type == "turbineValve" then
                -- turbine multiblock
                if not validate_index(1, 3) then return false end
                if not validate_assign() then return false end

                rtu_type = RTU_UNIT_TYPE.TURBINE_VALVE
                rtu_iface, faulted = turbinev_rtu.new(device)
                is_multiblock = true
                formed = device.isFormed()

                if formed == ppm.ACCESS_FAULT then
                    println_ts(util.c("sys_config> failed to check if '", name, "' is formed"))
                    log.warning(util.c("sys_config> failed to check if '", name, "' is a formed turbine multiblock"))
                end
            elseif type == "dynamicValve" then
                -- dynamic tank multiblock
                if entry.unit == nil then
                    if not validate_index(1, 4) then return false end
                    if not validate_assign(true) then return false end
                else
                    if not validate_index(1, 1) then return false end
                    if not validate_assign() then return false end
                end

                rtu_type = RTU_UNIT_TYPE.DYNAMIC_VALVE
                rtu_iface, faulted = dynamicv_rtu.new(device)
                is_multiblock = true
                formed = device.isFormed()

                if formed == ppm.ACCESS_FAULT then
                    println_ts(util.c("sys_config> failed to check if '", name, "' is formed"))
                    log.warning(util.c("sys_config> failed to check if '", name, "' is a formed dynamic tank multiblock"))
                end
            elseif type == "inductionPort" then
                -- induction matrix multiblock
                if not validate_assign(true) then return false end

                rtu_type = RTU_UNIT_TYPE.IMATRIX
                rtu_iface, faulted = imatrix_rtu.new(device)
                is_multiblock = true
                formed = device.isFormed()

                if formed == ppm.ACCESS_FAULT then
                    println_ts(util.c("sys_config> failed to check if '", name, "' is formed"))
                    log.warning(util.c("sys_config> failed to check if '", name, "' is a formed induction matrix multiblock"))
                end
            elseif type == "spsPort" then
                -- SPS multiblock
                if not validate_assign(true) then return false end

                rtu_type = RTU_UNIT_TYPE.SPS
                rtu_iface, faulted = sps_rtu.new(device)
                is_multiblock = true
                formed = device.isFormed()

                if formed == ppm.ACCESS_FAULT then
                    println_ts(util.c("sys_config> failed to check if '", name, "' is formed"))
                    log.warning(util.c("sys_config> failed to check if '", name, "' is a formed SPS multiblock"))
                end
            elseif type == "solarNeutronActivator" then
                -- SNA
                if not validate_assign() then return false end

                rtu_type = RTU_UNIT_TYPE.SNA
                rtu_iface, faulted = sna_rtu.new(device)
            elseif type == "environmentDetector" then
                -- advanced peripherals environment detector
                if not validate_index(1) then return false end
                if not validate_assign(entry.unit == nil) then return false end

                rtu_type = RTU_UNIT_TYPE.ENV_DETECTOR
                rtu_iface, faulted = envd_rtu.new(device)
            elseif type == ppm.VIRTUAL_DEVICE_TYPE then
                -- placeholder device
                rtu_type = RTU_UNIT_TYPE.VIRTUAL
                rtu_iface = rtu.init_unit().interface()
            else
                local message = util.c("sys_config> device '", name, "' is not a known type (", type, ")")
                println_ts(message)
                log.fatal(message)
                return false
            end

            if is_multiblock then
                if not formed then
                    if formed == false then
                        log.info(util.c("sys_config> device '", name, "' is not formed"))
                    else formed = false end
                elseif faulted then
                    -- sometimes there is a race condition on server boot where it reports formed, but
                    -- the other functions are not yet defined (that's the theory at least). mark as unformed to attempt connection later
                    formed = false
                    log.warning(util.c("sys_config> device '", name, "' is formed, but initialization had one or more faults: marked as unformed"))
                end
            end

            ---@class rtu_registry_entry
            local rtu_unit = {
                uid = 0,                            ---@type integer
                name = name,                        ---@type string
                type = rtu_type,                    ---@type RTU_UNIT_TYPE
                index = index or false,             ---@type integer|false
                reactor = for_reactor,              ---@type integer
                device = device,                    ---@type table peripheral reference
                is_multiblock = is_multiblock,      ---@type boolean
                formed = formed,                    ---@type boolean|nil
                hw_state = RTU_HW_STATE.OFFLINE,    ---@type RTU_HW_STATE
                rtu = rtu_iface,                    ---@type rtu_device|rtu_rs_device
                modbus_io = modbus.new(rtu_iface, true),
                pkt_queue = mqueue.new(),           ---@type mqueue|nil
                thread = nil                        ---@type parallel_thread|nil
            }

            rtu_unit.thread = threads.thread__unit_comms(__shared_memory, rtu_unit)

            table.insert(units, rtu_unit)

            local for_message = "the facility"
            if for_reactor > 0 then
                for_message = util.c("reactor ", for_reactor)
            end

            local index_str = util.trinary(index ~= nil, util.c(" [", index, "]"), "")
            log.info(util.c("sys_config> initialized RTU unit #", #units, ": ", name, " (", types.rtu_type_to_string(rtu_type), ")", index_str, " for ", for_message))

            rtu_unit.uid = #units

            -- determine hardware status
            if rtu_unit.type == RTU_UNIT_TYPE.VIRTUAL then
                rtu_unit.hw_state = RTU_HW_STATE.OFFLINE
            else
                if rtu_unit.is_multiblock then
                    rtu_unit.hw_state = util.trinary(rtu_unit.formed == true, RTU_HW_STATE.OK, RTU_HW_STATE.UNFORMED)
                elseif faulted then
                    rtu_unit.hw_state = RTU_HW_STATE.FAULTED
                else
                    rtu_unit.hw_state = RTU_HW_STATE.OK
                end
            end

            -- report hardware status
            databus.tx_unit_hw_status(rtu_unit.uid, rtu_unit.hw_state)
        end

        return true
    end

    ----------------------------------------
    -- start system
    ----------------------------------------

    log.debug("boot> running sys_config()")

    if sys_config() then
        -- start UI
        local message
        rtu_state.fp_ok, message = renderer.try_start_ui(units, config.FrontPanelTheme, config.ColorMode)

        if not rtu_state.fp_ok then
            println_ts(util.c("UI error: ", message))
            println("startup> running without front panel")
            log.error(util.c("front panel GUI render failed with error ", message))
            log.info("startup> running in headless mode without front panel")
        end

        -- check modem
        if smem_dev.modem == nil then
            println("startup> wireless modem not found")
            log.fatal("no wireless modem on startup")
            return
        end

        databus.tx_hw_modem(true)

        -- find and setup all speakers
        local speakers = ppm.get_all_devices("speaker")
        for _, s in pairs(speakers) do
            local sounder = rtu.init_sounder(s)

            table.insert(smem_dev.sounders, sounder)

            log.debug(util.c("startup> added speaker, attached as ", sounder.name))
        end

        databus.tx_hw_spkr_count(#smem_dev.sounders)

        -- start connection watchdog
        smem_sys.conn_watchdog = util.new_watchdog(config.ConnTimeout)
        log.debug("startup> conn watchdog started")

        -- setup comms
        smem_sys.nic = network.nic(smem_dev.modem)
        smem_sys.rtu_comms = rtu.comms(RTU_VERSION, smem_sys.nic, smem_sys.conn_watchdog)
        log.debug("startup> comms init")

        -- init threads
        local main_thread  = threads.thread__main(__shared_memory)
        local comms_thread = threads.thread__comms(__shared_memory)

        -- assemble thread list
        local _threads = { main_thread.p_exec, comms_thread.p_exec }
        for i = 1, #units do
            if units[i].thread ~= nil then
                table.insert(_threads, units[i].thread.p_exec)
            end
        end

        log.info("startup> completed")

        -- run threads
        parallel.waitForAll(table.unpack(_threads))
    else
        println("configuration failed, exiting...")
    end

    renderer.close_ui()

    println_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_ui)
    crash.exit()
else
    log.close()
end

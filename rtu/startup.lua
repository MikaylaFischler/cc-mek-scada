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

local RTU_VERSION = "v1.12.2"

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

    -- get a string representation of a port interface
    ---@param entry rtu_rs_definition
    ---@return string
    local function entry_iface_name(entry)
        return util.trinary(entry.color ~= nil, util.c(entry.side, "/", rsio.color_name(entry.color)), entry.side)
    end

    -- configure RTU gateway based on settings file definitions
    local function sys_config()
        --#region Redstone Interfaces

        local rs_rtus   = {} ---@type { name: string, hw_state: RTU_HW_STATE, rtu: rtu_rs_device, phy: table, banks: rtu_rs_definition[][] }[]
        local all_conns = { [0] = {}, {}, {}, {}, {} }

        -- go through redstone definitions list
        for entry_idx = 1, #rtu_redstone do
            local entry = rtu_redstone[entry_idx]

            local assignment
            local for_reactor = entry.unit
            local phy         = entry.relay or 0
            local phy_name    = entry.relay or "local"
            local iface_name  = entry_iface_name(entry)

            if util.is_int(entry.unit) and entry.unit > 0 and entry.unit < 5 then
                ---@cast for_reactor integer
                assignment = "reactor unit " .. entry.unit
            elseif entry.unit == nil then
                assignment = "facility"
                for_reactor = 0
            else
                local message = util.c("sys_config> invalid unit assignment at block index #", entry_idx)
                println(message)
                log.fatal(message)
                return false
            end

            -- create the appropriate RTU if it doesn't exist and check relay name validity
            if entry.relay then
                if type(entry.relay) ~= "string" then
                    local message = util.c("sys_config> invalid redstone relay '", entry.relay, '"')
                    println(message)
                    log.fatal(message)
                    return false
                elseif not rs_rtus[entry.relay] then
                    log.debug(util.c("sys_config> allocated relay redstone RTU on interface ", entry.relay))

                    local hw_state = RTU_HW_STATE.OK
                    local relay    = ppm.get_periph(entry.relay)

                    if not relay then
                        hw_state = RTU_HW_STATE.OFFLINE
                        log.warning(util.c("sys_config> redstone relay ", entry.relay, " is not connected"))
                        local _, v_device = ppm.mount_virtual()
                        relay = v_device
                    elseif ppm.get_type(entry.relay) ~= "redstone_relay" then
                        hw_state = RTU_HW_STATE.FAULTED
                        log.warning(util.c("sys_config> redstone relay ", entry.relay, " is not a redstone relay"))
                    end

                    rs_rtus[entry.relay] = { name = entry.relay, hw_state = hw_state, rtu = redstone_rtu.new(relay), phy = relay, banks = { [0] = {}, {}, {}, {}, {} } }
                end
            elseif rs_rtus[0] == nil then
                log.debug(util.c("sys_config> allocated local redstone RTU"))
                rs_rtus[0] = { name = "redstone_local", hw_state = RTU_HW_STATE.OK, rtu = redstone_rtu.new(), phy = rs, banks = { [0] = {}, {}, {}, {}, {} } }
            end

            -- verify configuration
            local valid = false
            if rsio.is_valid_port(entry.port) and rsio.is_valid_side(entry.side) then
                valid = util.trinary(entry.color == nil, true, rsio.is_color(entry.color))
            end

            local bank  = rs_rtus[phy].banks[for_reactor]
            local conns = all_conns[for_reactor]

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
                    if util.table_contains(conns, entry.port) then
                        local message = util.c("sys_config> skipping duplicate input for port ", rsio.to_string(entry.port), " on side ", iface_name, " @ ", phy_name)
                        println(message)
                        log.warning(message)
                    else
                        table.insert(bank, entry)
                    end
                elseif mode == rsio.IO_MODE.ANALOG_IN then
                    -- can't have duplicate inputs
                    if util.table_contains(conns, entry.port) then
                        local message = util.c("sys_config> skipping duplicate input for port ", rsio.to_string(entry.port), " on side ", iface_name, " @ ", phy_name)
                        println(message)
                        log.warning(message)
                    else
                        table.insert(bank, entry)
                    end
                elseif (mode == rsio.IO_MODE.DIGITAL_OUT) or (mode == rsio.IO_MODE.ANALOG_OUT) then
                    table.insert(bank, entry)
                else
                    -- should be unreachable code, we already validated ports
                    log.fatal("sys_config> failed to identify IO mode at block index #" .. entry_idx)
                    println("sys_config> encountered a software error, check logs")
                    return false
                end

                table.insert(conns, entry.port)

                log.debug(util.c("sys_config> banked redstone ", #conns, ": ", rsio.to_string(entry.port), " (", iface_name, " @ ", phy_name, ") for ", assignment))
            end
        end

        -- create unit entries for redstone RTUs
        for _, def in pairs(rs_rtus) do
            local rtu_conns = { [0] = {}, {}, {}, {}, {} }

            -- connect the IO banks
            for for_reactor = 0, #def.banks do
                local bank   = def.banks[for_reactor]
                local conns  = rtu_conns[for_reactor]
                local assign = util.trinary(for_reactor > 0, "reactor unit " .. for_reactor, "the facility")

                -- link redstone to the RTU
                for i = 1, #bank do
                    local conn     = bank[i]
                    local phy_name = conn.relay or "local"

                    local mode = rsio.get_io_mode(conn.port)
                    if mode == rsio.IO_MODE.DIGITAL_IN then
                        def.rtu.link_di(conn.side, conn.color, conn.invert)
                    elseif mode == rsio.IO_MODE.DIGITAL_OUT then
                        def.rtu.link_do(conn.side, conn.color, conn.invert)
                    elseif mode == rsio.IO_MODE.ANALOG_IN then
                        def.rtu.link_ai(conn.side)
                    elseif mode == rsio.IO_MODE.ANALOG_OUT then
                        def.rtu.link_ao(conn.side)
                    else
                        log.fatal(util.c("sys_config> failed to identify IO mode of ", rsio.to_string(conn.port), " (", entry_iface_name(conn), " @ ", phy_name, ") for ", assign))
                        println("sys_config> encountered a software error, check logs")
                        return false
                    end

                    table.insert(conns, conn.port)

                    log.debug(util.c("sys_config> linked redstone ", for_reactor, ".", #conns, ": ", rsio.to_string(conn.port), " (", entry_iface_name(conn), ")", " @ ", phy_name, ") for ", assign))
                end
            end

            ---@type rtu_registry_entry
            local unit = {
                uid = 0,
                name = def.name,
                type = RTU_UNIT_TYPE.REDSTONE,
                index = false,
                reactor = nil,
                device = def.phy,
                rs_conns = rtu_conns,
                is_multiblock = false,
                formed = nil,
                hw_state = def.hw_state,
                rtu = def.rtu,
                modbus_io = modbus.new(def.rtu, false),
                pkt_queue = nil,
                thread = nil
            }

            table.insert(units, unit)

            local type = util.trinary(def.phy == rs, "redstone", "redstone_relay")

            log.info(util.c("sys_config> initialized RTU unit #", #units, ": ", unit.name, " (", type, ")"))

            unit.uid = #units

            databus.tx_unit_hw_status(unit.uid, unit.hw_state)
        end

        --#endregion
        --#region Mounted Peripherals

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
            elseif type == "environmentDetector" or type == "environment_detector" then
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
                uid = 0,                                 ---@type integer RTU unit ID
                name = name,                             ---@type string unit name
                type = rtu_type,                         ---@type RTU_UNIT_TYPE unit type
                index = index or false,                  ---@type integer|false device index
                reactor = for_reactor,                   ---@type integer|nil unit/facility assignment
                device = device,                         ---@type table peripheral reference
                rs_conns = nil,                          ---@type IO_PORT[][]|nil available redstone connections
                is_multiblock = is_multiblock,           ---@type boolean if this is for a multiblock peripheral
                formed = formed,                         ---@type boolean|nil if this peripheral is currently formed
                hw_state = RTU_HW_STATE.OFFLINE,         ---@type RTU_HW_STATE hardware device status
                rtu = rtu_iface,                         ---@type rtu_device|rtu_rs_device RTU hardware interface
                modbus_io = modbus.new(rtu_iface, true), ---@type modbus MODBUS interface
                pkt_queue = mqueue.new(),                ---@type mqueue|nil packet queue
                thread = nil                             ---@type parallel_thread|nil associated RTU thread
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

        --#endregion

        return true
    end

    ----------------------------------------
    -- start system
    ----------------------------------------

    log.debug("boot> running sys_config()")

    if sys_config() then
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

        -- start UI
        local message
        rtu_state.fp_ok, message = renderer.try_start_ui(units, config.FrontPanelTheme, config.ColorMode)

        if not rtu_state.fp_ok then
            println_ts(util.c("UI error: ", message))
            println("startup> running without front panel")
            log.error(util.c("front panel GUI render failed with error ", message))
            log.info("startup> running in headless mode without front panel")
        end

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
        println("system initialization failed, exiting...")
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

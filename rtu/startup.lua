--
-- RTU: Remote Terminal Unit
--

os.loadAPI("scada-common/log.lua") 
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/comms.lua")
os.loadAPI("scada-common/mqueue.lua")
os.loadAPI("scada-common/modbus.lua")
os.loadAPI("scada-common/rsio.lua")

os.loadAPI("config.lua")
os.loadAPI("rtu.lua")
os.loadAPI("threads.lua")

os.loadAPI("dev/redstone_rtu.lua")
os.loadAPI("dev/boiler_rtu.lua")
os.loadAPI("dev/imatrix_rtu.lua")
os.loadAPI("dev/turbine_rtu.lua")

local RTU_VERSION = "alpha-v0.4.9"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

log.init("/log.txt", log.MODE.APPEND)

log._info("========================================")
log._info("BOOTING rtu.startup " .. RTU_VERSION)
log._info("========================================")
println(">> RTU " .. RTU_VERSION .. " <<")

----------------------------------------
-- startup
----------------------------------------

-- mount connected devices
ppm.mount_all()

local __shared_memory = {
    -- RTU system state flags
    rtu_state = {
        linked = false,
        shutdown = false
    },

    -- core RTU devices
    rtu_dev = {
        modem = ppm.get_wireless_modem()
    },

    -- system objects
    rtu_sys = {
        rtu_comms = nil,
        conn_watchdog = nil,
        units = {}
    },

    -- message queues
    q = {
        mq_comms = mqueue.new()
    }
}

local smem_dev = __shared_memory.rtu_dev
local smem_sys = __shared_memory.rtu_sys

-- get modem
if smem_dev.modem == nil then
    println("boot> wireless modem not found")
    log._warning("no wireless modem on startup")
    return
end

smem_sys.rtu_comms = rtu.rtu_comms(smem_dev.modem, config.LISTEN_PORT, config.SERVER_PORT)

----------------------------------------
-- interpret config and init units
----------------------------------------

local units = __shared_memory.rtu_sys.units

local rtu_redstone = config.RTU_REDSTONE
local rtu_devices = config.RTU_DEVICES

-- redstone interfaces
for reactor_idx = 1, #rtu_redstone do
    local rs_rtu = redstone_rtu.new()
    local io_table = rtu_redstone[reactor_idx].io

    local capabilities = {}

    log._debug("init> starting redstone RTU I/O linking for reactor " .. rtu_redstone[reactor_idx].for_reactor .. "...")

    for i = 1, #io_table do
        local valid = false
        local conf = io_table[i]

        -- verify configuration
        if rsio.is_valid_channel(conf.channel) and rsio.is_valid_side(conf.side) then
            if conf.bundled_color then
                valid = rsio.is_color(conf.bundled_color)
            else
                valid = true
            end
        end

        if not valid then
            local message = "init> invalid redstone definition at index " .. i .. " in definition block #" .. reactor_idx ..
                " (for reactor " .. rtu_redstone[reactor_idx].for_reactor .. ")"
            println_ts(message)
            log._warning(message)
        else
            -- link redstone in RTU
            local mode = rsio.get_io_mode(conf.channel)
            if mode == rsio.IO_MODE.DIGITAL_IN then
                rs_rtu.link_di(conf.channel, conf.side, conf.bundled_color)
            elseif mode == rsio.IO_MODE.DIGITAL_OUT then
                rs_rtu.link_do(conf.channel, conf.side, conf.bundled_color)
            elseif mode == rsio.IO_MODE.ANALOG_IN then
                rs_rtu.link_ai(conf.channel, conf.side)
            elseif mode == rsio.IO_MODE.ANALOG_OUT then
                rs_rtu.link_ao(conf.channel, conf.side)
            else
                -- should be unreachable code, we already validated channels
                log._error("init> fell through if chain attempting to identify IO mode", true)
                break
            end

            table.insert(capabilities, conf.channel)

            log._debug("init> linked redstone " .. #capabilities .. ": " .. rsio.to_string(conf.channel) .. " (" .. conf.side ..
                ") for reactor " .. rtu_redstone[reactor_idx].for_reactor)
        end
    end

    table.insert(units, {
        name = "redstone_io",
        type = "redstone",
        index = 1,
        reactor = rtu_redstone[reactor_idx].for_reactor,
        device = capabilities,  -- use device field for redstone channels
        rtu = rs_rtu,
        modbus_io = modbus.new(rs_rtu),
        modbus_busy = false,
        pkt_queue = nil,
        thread = nil
    })

    log._debug("init> initialized RTU unit #" .. #units .. ": redstone_io (redstone) [1] for reactor " .. rtu_redstone[reactor_idx].for_reactor)
end

-- mounted peripherals
for i = 1, #rtu_devices do
    local device = ppm.get_periph(rtu_devices[i].name)

    if device == nil then
        local message = "init> '" .. rtu_devices[i].name .. "' not found"
        println_ts(message)
        log._warning(message)
    else
        local type = ppm.get_type(rtu_devices[i].name)
        local rtu_iface = nil
        local rtu_type = ""

        if type == "boiler" then
            -- boiler multiblock
            rtu_type = "boiler"
            rtu_iface = boiler_rtu.new(device)
        elseif type == "turbine" then
            -- turbine multiblock
            rtu_type = "turbine"
            rtu_iface = turbine_rtu.new(device)
        elseif type == "mekanismMachine" then
            -- assumed to be an induction matrix multiblock
            rtu_type = "imatrix"
            rtu_iface = imatrix_rtu.new(device)
        else
            local message = "init> device '" .. rtu_devices[i].name .. "' is not a known type (" .. type .. ")"
            println_ts(message)
            log._warning(message)
        end

        if rtu_iface ~= nil then
            local rtu_unit = {
                name = rtu_devices[i].name,
                type = rtu_type,
                index = rtu_devices[i].index,
                reactor = rtu_devices[i].for_reactor,
                device = device,
                rtu = rtu_iface,
                modbus_io = modbus.new(rtu_iface),
                modbus_busy = false,
                pkt_queue = mqueue.new(),
                thread = nil
            }

            rtu_unit.thread = threads.thread__unit_comms(__shared_memory, rtu_unit)

            table.insert(units, rtu_unit)

            log._debug("init> initialized RTU unit #" .. #units .. ": " .. rtu_devices[i].name .. " (" .. rtu_type .. ") [" ..
                rtu_devices[i].index .. "] for reactor " .. rtu_devices[i].for_reactor)
        end
    end
end

----------------------------------------
-- start system
----------------------------------------

-- init threads
local main_thread  = threads.thread__main(__shared_memory)
local comms_thread = threads.thread__comms(__shared_memory)

-- start connection watchdog
smem_sys.conn_watchdog = util.new_watchdog(5)
log._debug("init> conn watchdog started")

-- assemble thread list
local _threads = { main_thread.exec, comms_thread.exec }
for i = 1, #units do
    if units[i].thread ~= nil then
        table.insert(_threads, units[i].thread.exec)
    end
end

-- run threads
parallel.waitForAll(table.unpack(_threads))

println_ts("exited")
log._info("exited")

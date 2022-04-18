--
-- RTU: Remote Terminal Unit
--

os.loadAPI("scada-common/log.lua") 
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/comms.lua")
os.loadAPI("scada-common/modbus.lua")
os.loadAPI("scada-common/rsio.lua")

os.loadAPI("config.lua")
os.loadAPI("rtu.lua")

os.loadAPI("dev/redstone_rtu.lua")
os.loadAPI("dev/boiler_rtu.lua")
os.loadAPI("dev/imatrix_rtu.lua")
os.loadAPI("dev/turbine_rtu.lua")

local RTU_VERSION = "alpha-v0.2.0"

local print = util.print
local println = util.println
local print_ts = util.print_ts
local println_ts = util.println_ts

log._info("========================================")
log._info("BOOTING rtu.startup " .. RTU_VERSION)
log._info("========================================")
println(">> RTU " .. RTU_VERSION .. " <<")

----------------------------------------
-- startup
----------------------------------------

local units = {}
local linked = false

-- mount connected devices
ppm.mount_all()

-- get modem
local modem = ppm.get_wireless_modem()
if modem == nil then
    println("boot> wireless modem not found")
    log._warning("no wireless modem on startup")
    return
end

local rtu_comms = rtu.rtu_comms(modem, config.LISTEN_PORT, config.SERVER_PORT)

----------------------------------------
-- determine configuration
----------------------------------------

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
        local config = io_table[i]

        -- verify configuration
        if rsio.is_valid_channel(config.channel) and rsio.is_valid_side(config.side) then
            if config.bundled_color then
                valid = rsio.is_color(config.bundled_color)
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
            local mode = rsio.get_io_mode(config.channel)
            if mode == rsio.IO_MODE.DIGITAL_IN then
                rs_rtu.link_di(config.channel, config.side, config.bundled_color)
            elseif mode == rsio.IO_MODE.DIGITAL_OUT then
                rs_rtu.link_do(config.channel, config.side, config.bundled_color)
            elseif mode == rsio.IO_MODE.ANALOG_IN then
                rs_rtu.link_ai(config.channel, config.side)
            elseif mode == rsio.IO_MODE.ANALOG_OUT then
                rs_rtu.link_ao(config.channel, config.side)
            else
                -- should be unreachable code, we already validated channels
                log._error("init> fell through if chain attempting to identify IO mode", true)
                break
            end

            table.insert(capabilities, config.channel)

            log._debug("init> linked redstone " .. #capabilities .. ": " .. rsio.to_string(config.channel) .. " (" .. config.side ..
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
        modbus_io = modbus.new(rs_rtu)
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
            table.insert(units, {
                name = rtu_devices[i].name,
                type = rtu_type,
                index = rtu_devices[i].index,
                reactor = rtu_devices[i].for_reactor,
                device = device,
                rtu = rtu_iface,
                modbus_io = modbus.new(rtu_iface)
            })

            log._debug("init> initialized RTU unit #" .. #units .. ": " .. rtu_devices[i].name .. " (" .. rtu_type .. ") [" ..
                rtu_devices[i].index .. "] for reactor " .. rtu_devices[i].for_reactor)
        end
    end
end

----------------------------------------
-- main loop
----------------------------------------

-- advertisement/heartbeat clock (every 2 seconds)
local loop_clock = os.startTimer(2)

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

    if event == "peripheral_detach" then
        -- handle loss of a device
        local device = ppm.handle_unmount(param1)

        for i = 1, #units do
            -- find disconnected device
            if units[i].device == device then
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
        -- period tick, if we are linked send heartbeat, if not send advertisement
        if linked then
            rtu_comms.send_heartbeat()
        else
            -- advertise units
            rtu_comms.send_advertisement(units)
        end

        -- start next clock timer
        loop_clock = os.startTimer(2)
    elseif event == "modem_message" then
        -- got a packet
        local link_ref = { linked = linked }
        local packet = rtu_comms.parse_packet(p1, p2, p3, p4, p5)

        rtu_comms.handle_packet(packet, units, link_ref)

        -- if linked, stop sending advertisements
        linked = link_ref.linked
    end

    -- check for termination request
    if event == "terminate" or ppm.should_terminate() then
        log._warning("terminate requested, exiting...")
        break
    end
end

println_ts("exited")
log._info("exited")

--
-- RTU: Remote Terminal Unit
--

os.loadAPI("scada-common/log.lua") 
os.loadAPI("scada-common/util.lua")
os.loadAPI("scada-common/ppm.lua")
os.loadAPI("scada-common/modbus.lua")
os.loadAPI("scada-common/rsio.lua")

os.loadAPI("config.lua")
os.loadAPI("rtu.lua")

os.loadAPI("dev/boiler.lua")
os.loadAPI("dev/imatrix.lua")
os.loadAPI("dev/turbine.lua")

local RTU_VERSION = "alpha-v0.1.0"

local print_ts = util.print_ts

----------------------------------------
-- startup
----------------------------------------

local units = {}
local linked = false

-- mount connected devices
ppm.mount_all()

-- get modem
local modem = ppm.get_device("modem")
if modem == nil then
    print("No modem found, exiting...")
    return
end

-- start comms
if not modem.isOpen(config.LISTEN_PORT) then
    modem.open(config.LISTEN_PORT)
end

local rtu_comms = comms.rtu_comms(config.REACTOR_ID, modem, config.LISTEN_PORT, config.SERVER_PORT, reactor)

----------------------------------------
-- determine configuration
----------------------------------------

-- redstone interfaces
for reactor_idx = 1, #RTU_REDSTONE do
    local rs_rtu = redstone_rtu()
    local io_table = RTU_REDSTONE[reactor_idx].io

    local capabilities = {}

    for i = 1, #io_table do
        local valid = false
        local config = io_table[i]

        -- verify configuration
        if is_valid_channel(config.channel) and is_valid_side(config.side) then
            if config.bundled_color then
                valid = is_color(config.bundled_color)
            else
                valid = true
            end
        end

        if ~valid then
            local message = "invalid redstone configuration at index " .. i
            print_ts(message .. "\n")
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
                log._error("fell through if chain attempting to identify IO mode", true)
                break
            end

            table.insert(capabilities, config.channel)

            log._debug("startup> linked redstone " .. #capabilities .. ": " .. rsio.to_string(config.channel) .. " (" .. config.side ..
                ") for reactor " .. RTU_REDSTONE[reactor_idx].for_reactor)
        end
    end

    table.insert(units, {
        name = "redstone_io",
        type = "redstone",
        index = 1,
        reactor = RTU_REDSTONE[reactor_idx].for_reactor,
        device = capabilities,  -- use device field for redstone channels
        rtu = rs_rtu,
        modbus_io = modbus_init(rs_rtu)
    })
end

-- mounted peripherals
for i = 1, #RTU_DEVICES do
    local device = ppm.get_periph(RTU_DEVICES[i].name)

    if device == nil then
        local message = "'" .. RTU_DEVICES[i].name .. "' not found"
        print_ts(message .. "\n")
        log._warning(message)
    else
        local type = ppm.get_type(RTU_DEVICES[i].name)
        local rtu_iface = nil
        local rtu_type = ""

        if type == "boiler" then
            -- boiler multiblock
            rtu_type = "boiler"
            rtu_iface = boiler_rtu(device)
        elseif type == "turbine" then
            -- turbine multiblock
            rtu_type = "turbine"
            rtu_iface = turbine_rtu(device)
        elseif type == "mekanismMachine" then
            -- assumed to be an induction matrix multiblock
            rtu_type = "imatrix"
            rtu_iface = imatrix_rtu(device)
        else
            local message = "device '" .. RTU_DEVICES[i].name .. "' is not a known type (" .. type .. ")"
            print_ts(message .. "\n")
            log._warning(message)
        end

        if rtu_iface ~= nil then
            table.insert(units, {
                name = RTU_DEVICES[i].name,
                type = rtu_type,
                index = RTU_DEVICES[i].index,
                reactor = RTU_DEVICES[i].for_reactor,
                device = device,
                rtu = rtu_iface,
                modbus_io = modbus_init(rtu_iface)
            })

            log._debug("startup> initialized RTU unit #" .. #units .. ": " .. RTU_DEVICES[i].name .. " (" .. rtu_type .. ") [" ..
                RTU_DEVICES[i].index .. "] for reactor " .. RTU_DEVICES[i].for_reactor)
        end
    end
end

----------------------------------------
-- main loop
----------------------------------------

-- advertisement/heartbeat clock (every 2 seconds)
local loop_tick = os.startTimer(2)

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEventRaw()

    if event == "peripheral_detach" then
        ppm.handle_unmount(param1)

        -- todo: handle unit change
    elseif event == "timer" and param1 == loop_tick then
        -- period tick, if we are linked send heartbeat, if not send advertisement
        if linked then
            rtu_comms.send_heartbeat()
        else
            -- advertise units
            rtu_comms.send_advertisement(units)
        end
    elseif event == "modem_message" then
        -- got a packet

        local packet = rtu_comms.parse_packet(p1, p2, p3, p4, p5)
        rtu_comms.handle_packet(packet)

    elseif event == "terminate" then
        return
    end
end

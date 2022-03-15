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

-- determine configuration
local units = {}

-- mounted peripherals
for i = 1, #RTU_DEVICES do
    local device = ppm.get_periph(RTU_DEVICES[i].name)

    if device == nil then
        local message = "'" .. RTU_DEVICES[i].name .. "' not found"
        print_ts(message)
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
            print_ts(message)
            log._warning(message)
        end

        if rtu_iface ~= nil then
            table.insert(units, {
                name = RTU_DEVICES[i].name,
                type = rtu_type,
                index = RTU_DEVICES[i].index,
                reactor = RTU_DEVICES[i].for_reactor,
                device = device,
                rtu = rtu_iface
            })
        end
    end
end

-- redstone devices
for i = 1, #RTU_REDSTONE do
end

-- advertise units
rtu_comms.send_advertisement(units)


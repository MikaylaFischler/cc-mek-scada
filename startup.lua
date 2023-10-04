local util = require("scada-common.util")

local BOOTLOADER_VERSION = "0.3"

local println = util.println
local println_ts = util.println_ts

println("SCADA BOOTLOADER V" .. BOOTLOADER_VERSION)

local exit_code ---@type boolean

println_ts("BOOT> SCANNING FOR APPLICATIONS...")

if fs.exists("reactor-plc/startup.lua") then
    println("BOOT> FOUND REACTOR PLC CODE: EXEC STARTUP")
    exit_code = shell.execute("reactor-plc/startup")
elseif fs.exists("rtu/startup.lua") then
    println("BOOT> FOUND RTU CODE: EXEC STARTUP")
    exit_code = shell.execute("rtu/startup")
elseif fs.exists("supervisor/startup.lua") then
    println("BOOT> FOUND SUPERVISOR CODE: EXEC STARTUP")
    exit_code = shell.execute("supervisor/startup")
elseif fs.exists("coordinator/startup.lua") then
    println("BOOT> FOUND COORDINATOR CODE: EXEC STARTUP")
    exit_code = shell.execute("coordinator/startup")
elseif fs.exists("pocket/startup.lua") then
    println("BOOT> FOUND POCKET CODE: EXEC STARTUP")
    exit_code = shell.execute("pocket/startup")
else
    println("BOOT> NO SCADA STARTUP FOUND")
    println("BOOT> EXIT")
    return false
end

if not exit_code then println_ts("BOOT> APPLICATION CRASHED") end

return exit_code

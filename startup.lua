local util = require("scada-common.util")

local println = util.println

local BOOTLOADER_VERSION = "1.0"

println("SCADA BOOTLOADER V" .. BOOTLOADER_VERSION)
println("BOOT> SCANNING FOR APPLICATIONS...")

local exit_code

if fs.exists("reactor-plc/startup.lua") then
    println("BOOT> EXEC REACTOR PLC STARTUP")
    exit_code = shell.execute("reactor-plc/startup")
elseif fs.exists("rtu/startup.lua") then
    println("BOOT> EXEC RTU STARTUP")
    exit_code = shell.execute("rtu/startup")
elseif fs.exists("supervisor/startup.lua") then
    println("BOOT> EXEC SUPERVISOR STARTUP")
    exit_code = shell.execute("supervisor/startup")
elseif fs.exists("coordinator/startup.lua") then
    println("BOOT> EXEC COORDINATOR STARTUP")
    exit_code = shell.execute("coordinator/startup")
elseif fs.exists("pocket/startup.lua") then
    println("BOOT> EXEC POCKET STARTUP")
    exit_code = shell.execute("pocket/startup")
else
    println("BOOT> NO SCADA STARTUP FOUND")
    println("BOOT> EXIT")
    return false
end

if not exit_code then println("BOOT> APPLICATION CRASHED") end

return exit_code

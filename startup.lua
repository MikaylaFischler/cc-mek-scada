local util = require("scada-common.util")

local BOOTLOADER_VERSION = "0.2"

local println = util.println
local println_ts = util.println_ts

println("SCADA BOOTLOADER V" .. BOOTLOADER_VERSION)

local exit_code ---@type boolean

println_ts("BOOT> SCANNING FOR APPLICATIONS...")

if fs.exists("reactor-plc/startup.lua") then
    -- found reactor-plc application
    println("BOOT> FOUND REACTOR PLC APPLICATION")
    println("BOOT> EXEC STARTUP")
    exit_code = shell.execute("reactor-plc/startup")
elseif fs.exists("rtu/startup.lua") then
    -- found rtu application
    println("BOOT> FOUND RTU APPLICATION")
    println("BOOT> EXEC STARTUP")
    exit_code = shell.execute("rtu/startup")
elseif fs.exists("supervisor/startup.lua") then
    -- found supervisor application
    println("BOOT> FOUND SUPERVISOR APPLICATION")
    println("BOOT> EXEC STARTUP")
    exit_code = shell.execute("supervisor/startup")
elseif fs.exists("coordinator/startup.lua") then
    -- found coordinator application
    println("BOOT> FOUND COORDINATOR APPLICATION")
    println("BOOT> EXEC STARTUP")
    exit_code = shell.execute("coordinator/startup")
elseif fs.exists("pocket/startup.lua") then
    -- found pocket application
    println("BOOT> FOUND POCKET APPLICATION")
    println("BOOT> EXEC STARTUP")
    exit_code = shell.execute("pocket/startup")
else
    -- no known applications found
    println("BOOT> NO SCADA STARTUP APPLICATION FOUND")
    println("BOOT> EXIT")
    return false
end

if not exit_code then
    println_ts("BOOT> APPLICATION CRASHED")
end

return exit_code

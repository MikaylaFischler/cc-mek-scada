print("CONFIGURE> SCANNING FOR CONFIGURATOR...")

if fs.exists("reactor-plc/configure.lua") then
    require("reactor-plc.configure").configure()
elseif fs.exists("rtu/configure.lua") then
    require("rtu.configure").configure()
elseif fs.exists("supervisor/configure.lua") then
    require("supervisor.configure").configure()
elseif fs.exists("coordinator/startup.lua") then
    print("CONFIGURE> COORDINATOR CONFIGURATOR NOT YET IMPLEMENTED IN BETA")
elseif fs.exists("pocket/startup.lua") then
    print("CONFIGURE> POCKET CONFIGURATOR NOT YET IMPLEMENTED IN BETA")
else
    print("CONFIGURE> NO CONFIGURATOR FOUND")
    print("CONFIGURE> EXIT")
end

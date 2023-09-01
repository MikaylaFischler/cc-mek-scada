print("CONFIGURE> SCANNING FOR CONFIGURATOR...")

if fs.exists("reactor-plc/configure.lua") then
    require("reactor-plc/configure.lua").configure()
elseif fs.exists("rtu/startup.lua") then
    print("CONFIGURE> RTU CONFIGURATOR NOT YET IMPLEMENTED IN BETA")
elseif fs.exists("supervisor/startup.lua") then
    print("CONFIGURE> SUPERVISOR CONFIGURATOR NOT YET IMPLEMENTED IN BETA")
elseif fs.exists("coordinator/startup.lua") then
    print("CONFIGURE> COORDINATOR CONFIGURATOR NOT YET IMPLEMENTED IN BETA")
elseif fs.exists("pocket/startup.lua") then
    print("CONFIGURE> POCKET CONFIGURATOR NOT YET IMPLEMENTED IN BETA")
else
    print("CONFIGURE> NO CONFIGURATOR FOUND")
    print("CONFIGURE> EXIT")
end

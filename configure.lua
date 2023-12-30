print("CONFIGURE> SCANNING FOR CONFIGURATOR...")

if fs.exists("reactor-plc/configure.lua") then
    require("reactor-plc.configure").configure()
elseif fs.exists("rtu/configure.lua") then
    require("rtu.configure").configure()
elseif fs.exists("supervisor/configure.lua") then
    require("supervisor.configure").configure()
elseif fs.exists("coordinator/startup.lua") then
    print("CONFIGURE> coordinator configurator not yet implemented (use 'edit coordinator/config.lua' to configure)")
elseif fs.exists("pocket/startup.lua") then
    print("CONFIGURE> pocket configurator not yet implemented (use 'edit pocket/config.lua' to configure)")
else
    print("CONFIGURE> NO CONFIGURATOR FOUND")
    print("CONFIGURE> EXIT")
end

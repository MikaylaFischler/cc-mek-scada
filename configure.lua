print("CONFIGURE> SCANNING FOR CONFIGURATOR...")

if fs.exists("reactor-plc/configure.lua") then require("reactor-plc.configure").configure()
elseif fs.exists("rtu/configure.lua") then require("rtu.configure").configure()
elseif fs.exists("supervisor/configure.lua") then require("supervisor.configure").configure()
elseif fs.exists("coordinator/configure.lua") then require("coordinator.configure").configure()
elseif fs.exists("pocket/configure.lua") then require("pocket.configure").configure()
else
    print("CONFIGURE> NO CONFIGURATOR FOUND")
    print("CONFIGURE> EXIT")
end

print(">>RCASS LOADER START<<")
print(">>CHECKING SETTINGS...")
loaded = settings.load("rcass.settings")
if loaded then
    print(">>SETTINGS FOUND, VERIFIYING INTEGRITY...")
    settings.getNames()
else
    print(">>SETTINGS NOT FOUND")
    print(">>LAUNCHING CONFIGURATOR...")
    shell.run("config")
end
print(">>LAUNCHING RCASS...")
shell.run("rcass")

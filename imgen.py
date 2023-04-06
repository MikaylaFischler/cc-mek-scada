import json
import os

# list files in a directory
def list_files(path):
    list = []

    for (root, dirs, files) in os.walk(path):
        for f in files:
            list.append((root[2:] + "/" + f).replace('\\','/'))

    return list

# get size of all files in a directory
def dir_size(path):
    total = 0

    for (root, dirs, files) in os.walk(path):
        for f in files:
            total += os.path.getsize(root + "/" + f)

    return total

# get the version of an application at the provided path
def get_version(path, is_comms = False):
    ver = ""
    string = "comms.version = \""

    if not is_comms:
        string = "_VERSION = \""

    f = open(path, "r")

    for line in f:
        pos = line.find(string)
        if pos >= 0:
            ver = line[(pos + len(string)):(len(line) - 2)]
            break

    f.close()

    return ver

# generate installation manifest object
def make_manifest(size):
    manifest = {
        "versions" : {
            "installer" : get_version("./ccmsi.lua"),
            "bootloader" : get_version("./startup.lua"),
            "comms" : get_version("./scada-common/comms.lua", True),
            "reactor-plc" : get_version("./reactor-plc/startup.lua"),
            "rtu" : get_version("./rtu/startup.lua"),
            "supervisor" : get_version("./supervisor/startup.lua"),
            "coordinator" : get_version("./coordinator/startup.lua"),
            "pocket" : get_version("./pocket/startup.lua")
        },
        "files" : {
            # common files
            "system" : [ "initenv.lua", "startup.lua" ],
            "common" : list_files("./scada-common"),
            "graphics" : list_files("./graphics"),
            "lockbox" : list_files("./lockbox"),
            # platform files
            "reactor-plc" : list_files("./reactor-plc"),
            "rtu" : list_files("./rtu"),
            "supervisor" : list_files("./supervisor"),
            "coordinator" : list_files("./coordinator"),
            "pocket" : list_files("./pocket"),
        },
        "depends" : {
            "reactor-plc" : [ "system", "common" ],
            "rtu" : [ "system", "common" ],
            "supervisor" : [ "system", "common" ],
            "coordinator" : [ "system", "common", "graphics" ],
            "pocket" : [ "system", "common", "graphics" ]
        },
        "sizes" : {
            # manifest file estimate
            "manifest" : size,
            # common files
            "system" : os.path.getsize("initenv.lua") + os.path.getsize("startup.lua"),
            "common" : dir_size("./scada-common"),
            "graphics" : dir_size("./graphics"),
            "lockbox" : dir_size("./lockbox"),
            # platform files
            "reactor-plc" : dir_size("./reactor-plc"),
            "rtu" : dir_size("./rtu"),
            "supervisor" : dir_size("./supervisor"),
            "coordinator" : dir_size("./coordinator"),
            "pocket" : dir_size("./pocket"),
        }
    }

    return manifest

# write initial manifest with placeholder size
f = open("install_manifest.json", "w")
json.dump(make_manifest("-----"), f)
f.close()

manifest_size = os.path.getsize("install_manifest.json")

# calculate file size then regenerate with embedded size
f = open("install_manifest.json", "w")
json.dump(make_manifest(manifest_size), f)
f.close()

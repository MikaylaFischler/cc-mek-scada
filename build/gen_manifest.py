import json
import os
import sys

#
# functions
#

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
def get_version(path, is_lib = False):
    ver = ""
    string = ".version = \""

    if not is_lib:
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
            "common" : get_version("./scada-common/util.lua", True),
            "comms" : get_version("./scada-common/comms.lua", True),
            "graphics" : get_version("./graphics/core.lua", True),
            "lockbox" : get_version("./lockbox/init.lua", True),
            "reactor-plc" : get_version("./reactor-plc/startup.lua"),
            "rtu" : get_version("./rtu/startup.lua"),
            "supervisor" : get_version("./supervisor/startup.lua"),
            "coordinator" : get_version("./coordinator/startup.lua"),
            "pocket" : get_version("./pocket/startup.lua")
        },
        "files" : {
            # common files
            "system" : [ "initenv.lua", "startup.lua", "configure.lua", "LICENSE" ],
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
            "reactor-plc" : [ "system", "common", "graphics", "lockbox" ],
            "rtu" : [ "system", "common", "graphics", "lockbox" ],
            "supervisor" : [ "system", "common", "graphics", "lockbox" ],
            "coordinator" : [ "system", "common", "graphics", "lockbox" ],
            "pocket" : [ "system", "common", "graphics", "lockbox" ]
        },
        "sizes" : {
            # manifest file estimate
            "manifest" : size,
            # common files
            "system" : os.path.getsize("initenv.lua") + os.path.getsize("startup.lua") + os.path.getsize("configure.lua"),
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

#
#  main
#

if __name__ == "__main__":
    # parse arguments
    gen_shields = "--shields" in sys.argv

    # check if we were given a path to run in
    for arg in sys.argv[1:]:
        if not arg.startswith("-"):
            os.chdir(arg)
            break

    # write initial manifest with placeholder size
    manifest_file = open("install_manifest.json", "w")
    json.dump(make_manifest(9999), manifest_file)
    manifest_file.close()

    manifest = make_manifest(os.path.getsize("install_manifest.json"))

    # calculate file size then regenerate with embedded size
    manifest_file = open("install_manifest.json", "w")
    json.dump(manifest, manifest_file)
    manifest_file.close()

    # write all the JSON files for shields.io if requested
    if gen_shields:
        for key, version in manifest["versions"].items():
            shields_file = open("./deploy/" + key + ".json", "w")

            # color based on release type
            if version.find("alpha") >= 0:
                color = "yellow"
            elif version.find("beta") >= 0:
                color = "orange"
            else:
                color = "blue"

            # prepare shields data
            json.dump({
                "schemaVersion": 1,
                "label": key,
                "message": "" + version,
                "color": color
            }, shields_file)

            shields_file.close()


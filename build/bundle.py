import base64
import json
import os
import subprocess

path_prefix = "./_minified/"

# get git build info
build = subprocess.check_output(["git", "describe", "--tags"]).strip().decode('UTF-8')

# list files in a directory
def list_files(path):
    list = []

    for (root, dirs, files) in os.walk(path):
        for f in files:
            list.append((root[2:] + "/" + f).replace('\\','/'))

    return list

# recursively encode files with base64
def encode_recursive(path):
    list = {}

    for item in os.listdir(path):
        item_path = path + '/' + item

        if os.path.isfile(item_path):
            handle = open(item_path, 'r')
            list[item] = base64.b64encode(bytes(handle.read(), 'UTF-8')).decode('ASCII')
            handle.close()
        else:
            list[item] = encode_recursive(item_path)

    return list

# encode listed files with base64
def encode_files(files):
    list = {}

    for item in files:
        item_path = path_prefix + './' + item

        handle = open(item_path, 'r')
        list[item] = base64.b64encode(bytes(handle.read(), 'UTF-8')).decode('ASCII')
        handle.close()

    return list

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

# file manifest (reflects imgen.py)
manifest = {
    "common_versions" : {
        "bootloader" : get_version("./startup.lua"),
        "common" : get_version("./scada-common/util.lua", True),
        "comms" : get_version("./scada-common/comms.lua", True),
        "graphics" : get_version("./graphics/core.lua", True),
        "lockbox" : get_version("./lockbox/init.lua", True),
    },
    "app_versions" : {
        "reactor-plc" : get_version("./reactor-plc/startup.lua"),
        "rtu" : get_version("./rtu/startup.lua"),
        "supervisor" : get_version("./supervisor/startup.lua"),
        "coordinator" : get_version("./coordinator/startup.lua"),
        "pocket" : get_version("./pocket/startup.lua")
    },
    "files" : {
        # common files
        "system" : encode_files([ "initenv.lua", "startup.lua", "configure.lua", "LICENSE" ]),
        "scada-common" : encode_recursive(path_prefix + "./scada-common"),
        "graphics" : encode_recursive(path_prefix + "./graphics"),
        "lockbox" : encode_recursive(path_prefix + "./lockbox"),
        # platform files
        "reactor-plc" : encode_recursive(path_prefix + "./reactor-plc"),
        "rtu" : encode_recursive(path_prefix + "./rtu"),
        "supervisor" : encode_recursive(path_prefix + "./supervisor"),
        "coordinator" : encode_recursive(path_prefix + "./coordinator"),
        "pocket" : encode_recursive(path_prefix + "./pocket"),
    },
    "install_files" : {
        # common files
        "system" : [ "initenv.lua", "startup.lua", "configure.lua", "LICENSE" ],
        "scada-common" : list_files("./scada-common"),
        "graphics" : list_files("./graphics"),
        "lockbox" : list_files("./lockbox"),
        # platform files
        "reactor-plc" : list_files("./reactor-plc"),
        "rtu" : list_files("./rtu"),
        "supervisor" : list_files("./supervisor"),
        "coordinator" : list_files("./coordinator"),
        "pocket" : list_files("./pocket"),
    },
    "depends" : [ "system", "scada-common", "graphics", "lockbox" ]
}

# write the application installation items as Lua tables
def write_items(body, items, indent):
    indent_str = " " * indent
    for key, value in items.items():
        if isinstance(value, str):
            body = body + f"{indent_str}['{key}'] = \"{value}\",\n"
        else:
            body = body + f"{indent_str}['{key}'] = {{\n"
            body = write_items(body, value, indent + 4)
            body = body + f"{indent_str}}},\n"

    return body

# create output directory
if not os.path.exists("./BUNDLE"):
    os.makedirs("./BUNDLE")

# get offline installer
ccmsim_file = open("./build/ccmsim.lua", "r")
ccmsim_script = ccmsim_file.read()
ccmsim_file.close()

# create dependency bundled file
dep_file = "common_" + build + ".lua"
f_d = open("./BUNDLE/" + dep_file, "w")

body_b = "local dep_files = {\n"

for depend in manifest["depends"]:
    body_b = body_b + write_items("", { f"{depend}": manifest["files"][depend] }, 4)
body_b = body_b + "}\n"

body_b = body_b + f"""
if select("#", ...) == 0 then
    term.setTextColor(colors.red)
    print("You must run the other file you should have uploaded (it has the app in its name).")
    term.setTextColor(colors.white)
end

return dep_files
"""

f_d.write(body_b)
f_d.close()

# application bundled files
for app in [ "reactor-plc", "rtu", "supervisor", "coordinator", "pocket" ]:
    app_file = app + "_" + build + ".lua"

    f_script = open("./build/_offline.lua", "r")
    script = f_script.read()
    f_script.close()

    f_a = open("./BUNDLE/" + app_file, "w")

    body_a = "local app_files = {\n"

    body_a = body_a + write_items("", { f"{app}": manifest["files"][app] }, 4) + "}\n"

    versions = manifest["common_versions"].copy()
    versions[app] = manifest["app_versions"][app]

    depends = manifest["depends"].copy()
    depends.append(app)

    install_manifest = json.dumps({ "versions" : versions, "files" : manifest["install_files"], "depends" : depends })

    body_a = body_a + f"""
-- install manifest JSON and offline installer
local install_manifest = "{base64.b64encode(bytes(install_manifest, 'UTF-8')).decode('ASCII')}"
local ccmsi_offline = "{base64.b64encode(bytes(ccmsim_script, 'UTF-8')).decode('ASCII')}"

local function red() term.setTextColor(colors.red) end
local function green() term.setTextColor(colors.green) end
local function white() term.setTextColor(colors.white) end
local function lgray() term.setTextColor(colors.lightGray) end

if not fs.exists("{dep_file}") then
    red()
    print("Missing '{dep_file}'! Please upload it, then run this file again.")
    white()
    return
end

-- rename the dependency file
fs.move("{dep_file}", "install_depends.lua")

-- load the other file
local dep_files = require("install_depends")

-- delete the uploaded files to free up space to actually install
fs.delete("{app_file}")
fs.delete("install_depends.lua")

-- get started installing
{script}"""

    f_a.write(body_a)
    f_a.close()

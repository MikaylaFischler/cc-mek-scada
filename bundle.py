import base64
import json
import os
import sys

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

def encode_files(files):
    list = {}

    for item in files:
        item_path = './' + item

        handle = open(item_path, 'r')
        list[item] = base64.b64encode(bytes(handle.read(), 'UTF-8')).decode('ASCII')
        handle.close()

    return list

manifest = {
    "files" : {
        # common files
        "system" : encode_files([ "initenv.lua", "startup.lua", "configure.lua", "LICENSE" ]),
        "common" : encode_recursive("./scada-common"),
        "graphics" : encode_recursive("./graphics"),
        "lockbox" : encode_recursive("./lockbox"),
        # platform files
        "reactor-plc" : encode_recursive("./reactor-plc"),
        "rtu" : encode_recursive("./rtu"),
        "supervisor" : encode_recursive("./supervisor"),
        "coordinator" : encode_recursive("./coordinator"),
        "pocket" : encode_recursive("./pocket"),
    },
    "depends" : {
        "reactor-plc" : [ "reactor-plc", "system", "common", "graphics", "lockbox" ],
        "rtu" : [ "rtu", "system", "common", "graphics", "lockbox" ],
        "supervisor" : [ "supervisor", "system", "common", "graphics", "lockbox" ],
        "coordinator" : [ "coordinator", "system", "common", "graphics", "lockbox" ],
        "pocket" : [ "pocket", "system", "common", "graphics", "lockbox" ]
    }
}

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


for app in [ "reactor-plc", "rtu", "supervisor", "coordinator", "pocket" ]:
    f = open("_" + app + ".lua", "w")
    body = "local application = {\n"
    for depend in manifest["depends"][app]:
        body = body + write_items("", { f"{depend}": manifest["files"][depend] }, 4)
    body = body + "}\n\n"
    f.write(body)
    f.close()

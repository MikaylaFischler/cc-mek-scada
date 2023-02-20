--
-- ComputerCraft Mekanism SCADA System Installer Utility
--

--[[

Copyright © 2023 Mikayla Fischler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the “Software”), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

]]--

local function println(message) print(tostring(message)) end
local function print(message) term.write(tostring(message)) end

local VERSION = "v0.7"

local install_dir = "/.install-cache"
local repo_path = "http://raw.githubusercontent.com/MikaylaFischler/cc-mek-scada/devel/"
local install_manifest = repo_path .. "install_manifest.json"

local opts = { ... }
local mode = nil
local app = nil

local function write_install_manifest(manifest, dependencies)
    local versions = {}
    for key, value in pairs(manifest.versions) do
        local is_dependency = false
        for _, dependency in pairs(dependencies) do
            if key == "bootloader" and dependency == "system" then
                is_dependency = true
                break
            end
        end

        if key == app or is_dependency then
            versions[key] = value
        end
    end

    manifest.versions = versions

    local imfile = fs.open("install_manifest.json", "w")
    imfile.write(textutils.serializeJSON(manifest))
    imfile.close()
end

--
-- get and validate command line options
--

println("-- CC Mekanism SCADA Installer " .. VERSION .. " --")

if #opts == 0 or opts[1] == "help" or #opts ~= 2 then
    println("note: only modifies files that are part of the device application")
    println("usage: installer <mode> <app>")
    println("<mode>")
    println(" install     - fresh install, overwrites config")
    println(" update      - update files EXCEPT for config/logs")
    println(" remove      - delete files EXCEPT for config/logs")
    println(" purge       - delete files INCLUDING config/logs")
    println("<app>")
    println(" reactor-plc - reactor PLC firmware")
    println(" rtu         - RTU firmware")
    println(" supervisor  - supervisor server application")
    println(" coordinator - coordinator application")
    println(" pocket      - pocket application")
    return
else
    for _, v in pairs({ "install", "update", "remove", "purge" }) do
        if opts[1] == v then
            mode = v
            break
        end
    end

    if mode == nil then
        println("unrecognized mode")
        return
    end

    for _, v in pairs({ "reactor-plc", "rtu", "supervisor", "coordinator", "pocket" }) do
        if opts[2] == v then
            app = v
            break
        end
    end

    if app == nil then
        println("unrecognized application")
        return
    end
end

--
-- run selected mode
--

if mode == "install" or mode == "update" then
    -------------------------
    -- GET REMOTE MANIFEST --
    -------------------------

    local response, error = http.get(install_manifest)

    if response == nil then
        println("failed to get installation manifest from GitHub, cannot update or install")
        println("http error " .. error)
        return
    end

    local ok, manifest = pcall(function () return textutils.unserializeJSON(response.readAll()) end)

    if not ok then
        println("error parsing remote installation manifest")
        return
    end

    ------------------------
    -- GET LOCAL MANIFEST --
    ------------------------

    local imfile = fs.open("install_manifest.json", "r")
    local local_ok = false
    local local_manifest = {}

    if imfile ~= nil then
        local_ok, local_manifest = pcall(function () return textutils.unserializeJSON(imfile.readAll()) end)
        imfile.close()
    end

    local local_app_version = nil
    local local_comms_version = nil
    local local_boot_version = nil

    if not local_ok then
        if mode == "update" then
            term.setTextColor(colors.yellow)
            println("warning: failed to load local installation information")
            term.setTextColor(colors.white)
        end
    else
        local_app_version = local_manifest.versions[app]
        local_comms_version = local_manifest.versions.comms
        local_boot_version = local_manifest.versions.bootloader

        if local_manifest.versions[app] == nil then
            term.setTextColor(colors.red)
            println("another application is already installed, please purge it before installing a new application")
            term.setTextColor(colors.white)
            return
        end
    end

    local remote_app_version = manifest.versions[app]
    local remote_comms_version = manifest.versions.comms
    local remote_boot_version = manifest.versions.bootloader

    term.setTextColor(colors.green)
    if mode == "install" then
        println("installing " .. app .. " files...")
    elseif mode == "update" then
        println("updating " .. app .. " files... (keeping old config.lua)")
    end
    term.setTextColor(colors.white)

    if local_boot_version ~= nil then
        if local_boot_version ~= remote_boot_version then
            print("[bootldr] updating ")
            term.setTextColor(colors.blue)
            print(local_boot_version)
            term.setTextColor(colors.white)
            print(" \xbb ")
            term.setTextColor(colors.blue)
            println(remote_boot_version)
            term.setTextColor(colors.white)
        end
    else
        print("[bootldr] new install of ")
        term.setTextColor(colors.blue)
        println(remote_boot_version)
        term.setTextColor(colors.white)
    end

    if local_app_version ~= nil then
        if local_app_version ~= remote_app_version then
            print("[" .. app .. "] updating ")
            term.setTextColor(colors.blue)
            print(local_app_version)
            term.setTextColor(colors.white)
            print(" \xbb ")
            term.setTextColor(colors.blue)
            println(remote_app_version)
            term.setTextColor(colors.white)
        end
    else
        print("[" .. app .. "] new install of ")
        term.setTextColor(colors.blue)
        println(remote_app_version)
        term.setTextColor(colors.white)
    end

    if local_comms_version ~= nil then
        if local_comms_version ~= remote_comms_version then
            print("[comms] updating ")
            term.setTextColor(colors.blue)
            print(local_comms_version)
            term.setTextColor(colors.white)
            print(" \xbb ")
            term.setTextColor(colors.blue)
            println(remote_comms_version)
            term.setTextColor(colors.white)

            print("[comms] ")
            term.setTextColor(colors.yellow)
            println("other devices on the network will require an update")
            term.setTextColor(colors.white)
        end
    else
        print("[comms] new install of ")
        term.setTextColor(colors.blue)
        println(remote_comms_version)
        term.setTextColor(colors.white)
    end

    --------------------------
    -- START INSTALL/UPDATE --
    --------------------------

    local space_required = 0
    local space_available = fs.getFreeSpace("/")

    local single_file_mode = false
    local file_list = manifest.files
    local size_list = manifest.sizes
    local dependencies = manifest.depends[app]
    local config_file = app .. "/config.lua"

    table.insert(dependencies, app)

    for _, dependency in pairs(dependencies) do
        local size = size_list[dependency]
        space_required = space_required + size
    end

    if space_available < space_required then
        single_file_mode = true
        term.setTextColor(colors.red)
        println("WARNING: Insuffienct space available for a full download!")
        term.setTextColor(colors.white)
        println("Files will be downloaded one by one, so if you are replacing a current install this will not be a problem unless installation fails.")
        println("Do you wish to continue? (y/N)")

        local confirm = read()
        if confirm ~= "y" or confirm ~= "Y" then
            println("installation cancelled")
            return
        end
    end

---@diagnostic disable-next-line: undefined-field
    os.sleep(2)

    local success = true

    if not single_file_mode then
        if fs.exists(install_dir) then
            fs.delete(install_dir)
            fs.makeDir(install_dir)
        end

        for _, dependency in pairs(dependencies) do
            if mode == "update" and ((dependency == "system" and local_boot_version == remote_boot_version) or (local_app_version == remote_app_version)) then
                -- skip system package if unchanged, skip app package if not changed
                -- skip packages that have no version if app version didn't change
                term.setTextColor(colors.white)
                print("skipping download of unchanged package ")
                term.setTextColor(colors.blue)
                println(dependency)
            else
                term.setTextColor(colors.white)
                print("downloading package ")
                term.setTextColor(colors.blue)
                println(dependency)

                term.setTextColor(colors.lightGray)
                local files = file_list[dependency]
                for _, file in pairs(files) do
                    println("get: " .. file)
                    local dl, err_c = http.get(repo_path .. file)

                    if dl == nil then
                        term.setTextColor(colors.red)
                        println("get: error " .. err_c)
                        success = false
                        break
                    else
                        local handle = fs.open(install_dir .. "/" .. file, "w")
                        handle.write(dl.readAll())
                        handle.close()
                    end
                end
            end
        end

        if success then
            for _, dependency in pairs(dependencies) do
                if mode == "update" and ((dependency == "system" and local_boot_version == remote_boot_version) or (local_app_version == remote_app_version)) then
                    -- skip system package if unchanged, skip app package if not changed
                    -- skip packages that have no version if app version didn't change
                    term.setTextColor(colors.white)
                    print("skipping install of unchanged package ")
                    term.setTextColor(colors.blue)
                    println(dependency)
                else
                    term.setTextColor(colors.white)
                    print("installing package ")
                    term.setTextColor(colors.blue)
                    println(dependency)

                    term.setTextColor(colors.lightGray)
                    local files = file_list[dependency]
                    for _, file in pairs(files) do
                        if mode == "install" or file ~= config_file then
                            local temp_file = install_dir .. "/" .. file
                            if fs.exists(file) then fs.delete(file) end
                            fs.move(temp_file, file)
                        end
                    end
                end
            end
        end

        fs.delete(install_dir)

        if success then
            -- if we made it here, then none of the file system functions threw exceptions
            -- that means everything is OK
            write_install_manifest(manifest, dependencies)
            term.setTextColor(colors.green)
            if mode == "install" then
                println("installation completed successfully")
            else
                println("update completed successfully")
            end
        else
            if mode == "install" then
                term.setTextColor(colors.red)
                println("installation failed")
            else
                term.setTextColor(colors.orange)
                println("update failed, existing files unmodified")
            end
        end
    else
        for _, dependency in pairs(dependencies) do
            if mode == "update" and ((dependency == "system" and local_boot_version == remote_boot_version) or (local_app_version == remote_app_version)) then
                -- skip system package if unchanged, skip app package if not changed
                -- skip packages that have no version if app version didn't change
                term.setTextColor(colors.white)
                print("skipping install of unchanged package ")
                term.setTextColor(colors.blue)
                println(dependency)
            else
                term.setTextColor(colors.white)
                print("installing package ")
                term.setTextColor(colors.blue)
                println(dependency)

                term.setTextColor(colors.lightGray)
                local files = file_list[dependency]
                for _, file in pairs(files) do
                    println("get: " .. file)
                    local dl, err_c = http.get(repo_path .. file)

                    if dl == nil then
                        println("get: error " .. err_c)
                        success = false
                        break
                    else
                        local handle = fs.open("/" .. file, "w")
                        handle.write(dl.readAll())
                        handle.close()
                    end
                end
            end
        end

        if success then
            -- if we made it here, then none of the file system functions threw exceptions
            -- that means everything is OK
            write_install_manifest(manifest, dependencies)
            term.setTextColor(colors.green)
            if mode == "install" then
                println("installation completed successfully")
            else
                println("update completed successfully")
            end
        else
            term.setTextColor(colors.red)
            if mode == "install" then
                println("installation failed, files may have been skipped")
            else
                println("update failed, files may have been skipped")
            end
        end
    end
elseif mode == "remove" or mode == "purge" then
    local imfile = fs.open("install_manifest.json", "r")
    local ok = false
    local manifest = {}

    if imfile ~= nil then
        ok, manifest = pcall(function () return textutils.unserializeJSON(imfile.readAll()) end)
        imfile.close()
    end

    if not ok then
        term.setTextColor(colors.red)
        println("error parsing local installation manifest")
        term.setTextColor(colors.white)
        return
    elseif manifest.versions[app] == nil then
        term.setTextColor(colors.red)
        println(app .. " is not installed")
        term.setTextColor(colors.white)
        return
    end

    term.setTextColor(colors.orange)
    if mode == "remove" then
        println("removing all " .. app .. " files except for config.lua and log.txt...")
    elseif mode == "purge" then
        println("purging all " .. app .. " files including config.lua and log.txt...")
    end

---@diagnostic disable-next-line: undefined-field
    os.sleep(2)

    local file_list = manifest.files
    local dependencies = manifest.depends[app]
    local config_file = app .. "/config.lua"

    table.insert(dependencies, app)

    term.setTextColor(colors.lightGray)

    -- delete log file if purging
    if mode == "purge" then
        local config = require(config_file)
        if fs.exists(config.LOG_PATH) then
            fs.delete(config.LOG_PATH)
            println("deleted log file " .. config.LOG_PATH)
        end
    end

    -- delete all files except config unless purging
    for _, dependency in pairs(dependencies) do
        local files = file_list[dependency]
        for _, file in pairs(files) do
            if mode == "purge" or file ~= config_file then
                if fs.exists(file) then
                    fs.delete(file)
                    println("deleted " .. file)
                end
            end
        end
    end

    if mode == "purge" then
        fs.delete("install_manifest.json")
        println("deleted install_manifest.json")
    end

    term.setTextColor(colors.green)
    println("done!")
end

term.setTextColor(colors.white)

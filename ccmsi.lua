--
-- ComputerCraft Mekanism SCADA System Installer Utility
--

--[[
Copyright (c) 2023 Mikayla Fischler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
]]--

local function println(message) print(tostring(message)) end
local function print(message) term.write(tostring(message)) end

local CCMSI_VERSION = "v1.0"

local install_dir = "/.install-cache"
local repo_path = "http://raw.githubusercontent.com/MikaylaFischler/cc-mek-scada/"

local opts = { ... }
local mode = nil
local app = nil

-- record the local installation manifest
---@param manifest table
---@param dependencies table
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

        if key == app or key == "comms" or is_dependency then versions[key] = value end
    end

    manifest.versions = versions

    local imfile = fs.open("install_manifest.json", "w")
    imfile.write(textutils.serializeJSON(manifest))
    imfile.close()
end

--
-- get and validate command line options
--

println("-- CC Mekanism SCADA Installer " .. CCMSI_VERSION .. " --")

if #opts == 0 or opts[1] == "help" then
    println("usage: ccmsi <mode> <app> <tag/branch>")
    println("<mode>")
    term.setTextColor(colors.lightGray)
    println(" check       - check latest versions avilable")
    term.setTextColor(colors.yellow)
    println("               ccmsi check <tag/branch> for target")
    term.setTextColor(colors.lightGray)
    println(" install     - fresh install, overwrites config")
    println(" update      - update files EXCEPT for config/logs")
    println(" remove      - delete files EXCEPT for config/logs")
    println(" purge       - delete files INCLUDING config/logs")
    term.setTextColor(colors.white)
    println("<app>")
    term.setTextColor(colors.lightGray)
    println(" reactor-plc - reactor PLC firmware")
    println(" rtu         - RTU firmware")
    println(" supervisor  - supervisor server application")
    println(" coordinator - coordinator application")
    println(" pocket      - pocket application")
    term.setTextColor(colors.white)
    println("<tag/branch>")
    term.setTextColor(colors.yellow)
    println(" second parameter when used with check")
    term.setTextColor(colors.lightGray)
    println(" note: defaults to main")
    println(" target GitHub tag or branch name")
    return
else
    for _, v in pairs({ "check", "install", "update", "remove", "purge" }) do
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

    if app == nil and mode ~= "check" then
        println("unrecognized application")
        return
    end
end

--
-- run selected mode
--

if mode == "check" then
    -------------------------
    -- GET REMOTE MANIFEST --
    -------------------------

    if opts[2] then repo_path = repo_path .. opts[2] .. "/" else repo_path = repo_path .. "main/" end
    local install_manifest = repo_path .. "install_manifest.json"

    local response, error = http.get(install_manifest)

    if response == nil then
        term.setTextColor(colors.orange)
        println("failed to get installation manifest from GitHub, cannot update or install")
        term.setTextColor(colors.red)
        println("HTTP error: " .. error)
        term.setTextColor(colors.white)
        return
    end

    local ok, manifest = pcall(function () return textutils.unserializeJSON(response.readAll()) end)

    if not ok then
        term.setTextColor(colors.red)
        println("error parsing remote installation manifest")
        term.setTextColor(colors.white)
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

    if not local_ok then
        term.setTextColor(colors.yellow)
        println("failed to load local installation information")
        term.setTextColor(colors.white)

        local_manifest = { versions = { installer = CCMSI_VERSION } }
    else
        local_manifest.versions.installer = CCMSI_VERSION
    end

    -- list all versions
    for key, value in pairs(manifest.versions) do
        term.setTextColor(colors.purple)
        print(string.format("%-14s", "[" .. key .. "]"))
        if key == "installer" or (local_ok and (local_manifest.versions[key] ~= nil)) then
            term.setTextColor(colors.blue)
            print(local_manifest.versions[key])
            if value ~= local_manifest.versions[key] then
                term.setTextColor(colors.white)
                print(" (")
                term.setTextColor(colors.cyan)
                print(value)
                term.setTextColor(colors.white)
                println(" available)")
            else
                term.setTextColor(colors.green)
                println(" (up to date)")
            end
        else
            term.setTextColor(colors.lightGray)
            print("not installed")
            term.setTextColor(colors.white)
            print(" (latest ")
            term.setTextColor(colors.cyan)
            print(value)
            term.setTextColor(colors.white)
            println(")")
        end
    end
elseif mode == "install" or mode == "update" then
    -------------------------
    -- GET REMOTE MANIFEST --
    -------------------------

    if opts[3] then repo_path = repo_path .. opts[3] .. "/" else repo_path = repo_path .. "main/" end
    local install_manifest = repo_path .. "install_manifest.json"

    local response, error = http.get(install_manifest)

    if response == nil then
        term.setTextColor(colors.orange)
        println("failed to get installation manifest from GitHub, cannot update or install")
        term.setTextColor(colors.red)
        println("HTTP error: " .. error)
        term.setTextColor(colors.white)
        return
    end

    local ok, manifest = pcall(function () return textutils.unserializeJSON(response.readAll()) end)

    if not ok then
        term.setTextColor(colors.red)
        println("error parsing remote installation manifest")
        term.setTextColor(colors.white)
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

    -- try to find local versions
    if not local_ok then
        if mode == "update" then
            term.setTextColor(colors.red)
            println("failed to load local installation information, cannot update")
            term.setTextColor(colors.white)
            return
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

        local_manifest.versions.installer = CCMSI_VERSION
        if manifest.versions.installer ~= CCMSI_VERSION then
            term.setTextColor(colors.yellow)
            println("a newer version of the installer is available, consider downloading it")
            term.setTextColor(colors.white)
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

    -- display bootloader version change information
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
        elseif mode == "install" then
            print("[bootldr] reinstalling ")
            term.setTextColor(colors.blue)
            println(local_boot_version)
            term.setTextColor(colors.white)
        end
    else
        print("[bootldr] new install of ")
        term.setTextColor(colors.blue)
        println(remote_boot_version)
        term.setTextColor(colors.white)
    end

    -- display app version change information
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
        elseif mode == "install" then
            print("[" .. app .. "] reinstalling ")
            term.setTextColor(colors.blue)
            println(local_app_version)
            term.setTextColor(colors.white)
        end
    else
        print("[" .. app .. "] new install of ")
        term.setTextColor(colors.blue)
        println(remote_app_version)
        term.setTextColor(colors.white)
    end

    -- display comms version change information
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
        elseif mode == "install" then
            print("[comms] reinstalling ")
            term.setTextColor(colors.blue)
            println(local_comms_version)
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

    local space_required = manifest.sizes.manifest
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

    -- check space constraints
    if space_available < space_required then
        single_file_mode = true
        term.setTextColor(colors.yellow)
        println("WARNING: Insufficient space available for a full download!")
        term.setTextColor(colors.white)
        println("Files can be downloaded one by one, so if you are replacing a current install this will not be a problem unless installation fails.")
        println("Do you wish to continue? (y/N)")

        local confirm = read()
        if confirm ~= "y" and confirm ~= "Y" then
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

        -- download all dependencies
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
                    println("GET " .. file)
                    local dl, err = http.get(repo_path .. file)

                    if dl == nil then
                        term.setTextColor(colors.red)
                        println("GET HTTP Error " .. err)
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

        -- copy in downloaded files (installation)
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
        -- go through all files and replace one by one
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
                        println("GET " .. file)
                        local dl, err = http.get(repo_path .. file)

                        if dl == nil then
                            println("GET HTTP Error " .. err)
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
    elseif mode == "remove" and manifest.versions[app] == nil then
        term.setTextColor(colors.red)
        println(app .. " is not installed")
        term.setTextColor(colors.white)
        return
    end

    term.setTextColor(colors.orange)
    if mode == "remove" then
        println("removing all " .. app .. " files except for config.lua and log.txt...")
    elseif mode == "purge" then
        println("purging all " .. app .. " files...")
    end

---@diagnostic disable-next-line: undefined-field
    os.sleep(2)

    local file_list = manifest.files
    local dependencies = manifest.depends[app]
    local config_file = app .. "/config.lua"

    table.insert(dependencies, app)

    term.setTextColor(colors.lightGray)

    -- delete log file if purging
    if mode == "purge" and fs.exists(config_file) then
        local log_deleted = pcall(function ()
            local config = require(app .. ".config")
            if fs.exists(config.LOG_PATH) then
                fs.delete(config.LOG_PATH)
                println("deleted log file " .. config.LOG_PATH)
            end
        end)

        if not log_deleted then
            term.setTextColor(colors.red)
            println("failed to delete log file")
            term.setTextColor(colors.lightGray)
---@diagnostic disable-next-line: undefined-field
            os.sleep(1)
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

        -- delete folders that we should be deleteing
        if mode == "purge" or dependency ~= app then
            local folder = files[1]
            while true do
                local dir = fs.getDir(folder)
                if dir == "" or dir == ".." then
                    break
                else
                    folder = dir
                end
            end

            if fs.isDir(folder) then
                fs.delete(folder)
                println("deleted directory " .. folder)
            end
        elseif dependency == app then
            for _, folder in pairs(files) do
                while true do
                    local dir = fs.getDir(folder)
                    if dir == "" or dir == ".." or dir == app then
                        break
                    else
                        folder = dir
                    end
                end

                if folder ~= app and fs.isDir(folder) then
                    fs.delete(folder)
                    println("deleted app subdirectory " .. folder)
                end
            end
        end
    end

    -- only delete manifest if purging
    if mode == "purge" then
        fs.delete("install_manifest.json")
        println("deleted install_manifest.json")
    else
        -- remove all data from versions list to show nothing is installed
        manifest.versions = {}
        imfile = fs.open("install_manifest.json", "w")
        imfile.write(textutils.serializeJSON(manifest))
        imfile.close()
    end

    term.setTextColor(colors.green)
    println("done!")
end

term.setTextColor(colors.white)

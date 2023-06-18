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

local CCMSI_VERSION = "v1.4a"

local install_dir = "/.install-cache"
local manifest_path = "https://mikaylafischler.github.io/cc-mek-scada/manifests/"
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
            if (key == "bootloader" and dependency == "system") or key == dependency then
                is_dependency = true
                break
            end
        end

        if key == app or is_dependency then versions[key] = value end
    end

    manifest.versions = versions

    local imfile = fs.open("install_manifest.json", "w")
    imfile.write(textutils.serializeJSON(manifest))
    imfile.close()
end

-- ask the user yes or no
---@nodiscard
---@param question string
---@param default boolean
---@return boolean|nil
local function ask_y_n(question, default)
    print(question)

    if default == true then
        print(" (Y/n)? ")
    else
        print(" (y/N)? ")
    end

    local response = read(nil, nil)

    if response == "" then
        return default
    elseif response == "Y" or response == "y" then
        return true
    elseif response == "N" or response == "n" then
        return false
    else
        return nil
    end
end

-- print out a white + blue text message<br>
-- automatically adds a space
---@param message string message
---@param package string dependency/package/version
local function pkg_message(message, package)
    term.setTextColor(colors.white)
    print(message .. " ")
    term.setTextColor(colors.blue)
    println(package)
    term.setTextColor(colors.white)
end

-- indicate actions to be taken based on package differences for installs/updates
---@param name string package name
---@param v_local string|nil local version
---@param v_remote string remote version
local function show_pkg_change(name, v_local, v_remote)
    if v_local ~= nil then
        if v_local ~= v_remote then
            print("[" .. name .. "] updating ")
            term.setTextColor(colors.blue)
            print(v_local)
            term.setTextColor(colors.white)
            print(" \xbb ")
            term.setTextColor(colors.blue)
            println(v_local)
            term.setTextColor(colors.white)
        elseif mode == "install" then
            pkg_message("[" .. name .. "] reinstalling", v_local)
        end
    else
        pkg_message("[" .. name .. "] new install of", v_remote)
    end
end

--
-- get and validate command line options
--

println("-- CC Mekanism SCADA Installer " .. CCMSI_VERSION .. " --")

if #opts == 0 or opts[1] == "help" then
    println("usage: ccmsi <mode> <app> <branch>")
    println("<mode>")
    term.setTextColor(colors.lightGray)
    println(" check       - check latest versions avilable")
    term.setTextColor(colors.yellow)
    println("               ccmsi check <branch> for target")
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
    println("<branch>")
    term.setTextColor(colors.yellow)
    println(" second parameter when used with check")
    term.setTextColor(colors.lightGray)
    println(" main (default) | latest | devel")
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

    if opts[2] then manifest_path = manifest_path .. opts[2] .. "/" else manifest_path = manifest_path .. "main/" end
    local install_manifest = manifest_path .. "install_manifest.json"

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
    if opts[3] then manifest_path = manifest_path .. opts[3] .. "/" else manifest_path = manifest_path .. "main/" end
    local install_manifest = manifest_path .. "install_manifest.json"

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

    local ver = {
        app = { v_local = nil, v_remote = nil, changed = false },
        boot = { v_local = nil, v_remote = nil, changed = false },
        comms = { v_local = nil, v_remote = nil, changed = false },
        graphics = { v_local = nil, v_remote = nil, changed = false }
    }

    local imfile = fs.open("install_manifest.json", "r")
    local local_ok = false
    local local_manifest = {}

    if imfile ~= nil then
        local_ok, local_manifest = pcall(function () return textutils.unserializeJSON(imfile.readAll()) end)
        imfile.close()
    end

    -- try to find local versions
    if not local_ok then
        if mode == "update" then
            term.setTextColor(colors.red)
            println("failed to load local installation information, cannot update")
            term.setTextColor(colors.white)
            return
        end
    else
        ver.boot.v_local = local_manifest.versions.bootloader
        ver.app.v_local = local_manifest.versions[app]
        ver.comms.v_local = local_manifest.versions.comms
        ver.graphics.v_local = local_manifest.versions.graphics

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

    ver.boot.v_remote = manifest.versions.bootloader
    ver.app.v_remote = manifest.versions[app]
    ver.comms.v_remote = manifest.versions.comms
    ver.graphics.v_remote = manifest.versions.graphics

    term.setTextColor(colors.green)
    if mode == "install" then
        println("Installing " .. app .. " files...")
    elseif mode == "update" then
        println("Updating " .. app .. " files... (keeping old config.lua)")
    end
    term.setTextColor(colors.white)

    -- display bootloader version change information
    show_pkg_change("bootldr", ver.boot.v_local, ver.boot.v_remote)
    ver.boot.changed = ver.boot.v_local ~= ver.boot.v_remote

    -- display app version change information
    show_pkg_change(app, ver.app.v_local, ver.app.v_remote)
    ver.app.changed = ver.app.v_local ~= ver.app.v_remote

    -- display comms version change information
    show_pkg_change("comms", ver.comms.v_local, ver.comms.v_remote)
    ver.comms.changed = ver.comms.v_local ~= ver.comms.v_remote
    if ver.comms.changed and mode == "update" then
        print("[comms] ")
        term.setTextColor(colors.yellow)
        println("other devices on the network will require an update")
        term.setTextColor(colors.white)
    end

    -- display graphics version change information
    show_pkg_change("graphics", ver.graphics.v_local, ver.graphics.v_remote)
    ver.graphics.changed = ver.graphics.v_local ~= ver.graphics.v_remote

    -- ask for confirmation
    if not ask_y_n("Continue?", false) then return end

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
        if mode == "update" then println("If installation still fails, delete this device's log file and try again.") end
        if not ask_y_n("Do you wish to continue?", false) then
            println("Operation cancelled.")
            return
        end
    end

    local success = true

    if not single_file_mode then
        if fs.exists(install_dir) then
            fs.delete(install_dir)
            fs.makeDir(install_dir)
        end

        -- download all dependencies
        for _, dependency in pairs(dependencies) do
            if mode == "update" and ((dependency == "system" and ver.boot.changed) or
                                     (dependency == "graphics" and ver.graphics.changed) or
                                     (ver.app.changed)) then
                pkg_message("skipping download of unchanged package", dependency)
            else
                pkg_message("downloading package", dependency)
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
                if mode == "update" and ((dependency == "system" and ver.boot.changed) or
                                         (dependency == "graphics" and ver.graphics.changed) or
                                         (ver.app.changed)) then
                    pkg_message("skipping install of unchanged package", dependency)
                else
                    pkg_message("installing package", dependency)
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
                println("Installation completed successfully.")
            else
                println("Update completed successfully.")
            end
        else
            if mode == "install" then
                term.setTextColor(colors.red)
                println("Installation failed.")
            else
                term.setTextColor(colors.orange)
                println("Update failed, existing files unmodified.")
            end
        end
    else
        -- go through all files and replace one by one
        for _, dependency in pairs(dependencies) do
            if mode == "update" and ((dependency == "system" and ver.boot.changed) or
                                     (dependency == "graphics" and ver.graphics.changed) or
                                     (ver.app.changed)) then
                pkg_message("skipping install of unchanged package", dependency)
            else
                pkg_message("installing package", dependency)
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
                println("Installation completed successfully.")
            else
                println("Update completed successfully.")
            end
        else
            term.setTextColor(colors.red)
            if mode == "install" then
                println("Installation failed, files may have been skipped.")
            else
                println("Update failed, files may have been skipped.")
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

    -- ask for confirmation
    if not ask_y_n("Continue?", false) then return end

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
    println("Done!")
end

term.setTextColor(colors.white)

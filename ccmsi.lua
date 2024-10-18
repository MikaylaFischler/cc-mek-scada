--[[
CC-MEK-SCADA Installer Utility

Copyright (c) 2023 - 2024 Mikayla Fischler

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

local CCMSI_VERSION = "v1.18b"

local install_dir = "/.install-cache"
local manifest_path = "https://mikaylafischler.github.io/cc-mek-scada/manifests/"
local repo_path = "http://raw.githubusercontent.com/MikaylaFischler/cc-mek-scada/"

---@diagnostic disable-next-line: undefined-global
local _is_pkt_env = pocket -- luacheck: ignore pocket

local function println(msg) print(tostring(msg)) end

-- stripped down & modified copy of log.dmesg
local function print(msg)
    msg = tostring(msg)

    local cur_x, cur_y = term.getCursorPos()
    local out_w, out_h = term.getSize()

    -- jump to next line if needed
    if cur_x == out_w then
        cur_x = 1
        if cur_y == out_h then
            term.scroll(1)
            term.setCursorPos(1, cur_y)
        else
            term.setCursorPos(1, cur_y + 1)
        end
    end

    -- wrap
    local lines, remaining, s_start, s_end, ln = {}, true, 1, out_w + 1 - cur_x, 1
    while remaining do
        local line = string.sub(msg, s_start, s_end)

        if line == "" then
            remaining = false
        else
            lines[ln] = line
            s_start = s_end + 1
            s_end = s_end + out_w
            ln = ln + 1
        end
    end

    -- print
    for i = 1, #lines do
        cur_x, cur_y = term.getCursorPos()
        if i > 1 and cur_x > 1 then
            if cur_y == out_h then
                term.scroll(1)
                term.setCursorPos(1, cur_y)
            else term.setCursorPos(1, cur_y + 1) end
        end
        term.write(lines[i])
    end
end

local opts = { ... }
local mode, app, target
local install_manifest = manifest_path.."main/install_manifest.json"

local function red() term.setTextColor(colors.red) end
local function orange() term.setTextColor(colors.orange) end
local function yellow() term.setTextColor(colors.yellow) end
local function green() term.setTextColor(colors.green) end
local function cyan() term.setTextColor(colors.cyan) end
local function blue() term.setTextColor(colors.blue) end
local function white() term.setTextColor(colors.white) end
local function lgray() term.setTextColor(colors.lightGray) end

-- get command line option in list
local function get_opt(opt, options)
    for _, v in pairs(options) do if opt == v then return v end end
    return nil
end

-- wait for any key to be pressed
---@diagnostic disable-next-line: undefined-field
local function any_key() os.pullEvent("key_up") end

-- ask the user yes or no
local function ask_y_n(question, default)
    print(question)
    if default == true then print(" (Y/n)? ") else print(" (y/N)? ") end
    local response = read();any_key()
    if response == "" then return default
    elseif response == "Y" or response == "y" then return true
    elseif response == "N" or response == "n" then return false
    else return nil end
end

-- print out a white + blue text message
local function pkg_message(message, package) white();print(message.." ");blue();println(package);white() end

-- indicate actions to be taken based on package differences for installs/updates
local function show_pkg_change(name, v)
    if v.v_local ~= nil then
        if v.v_local ~= v.v_remote then
            print("["..name.."] updating ");blue();print(v.v_local);white();print(" \xbb ");blue();println(v.v_remote);white()
        elseif mode == "install" then
            pkg_message("["..name.."] reinstalling", v.v_local)
        end
    else pkg_message("["..name.."] new install of", v.v_remote) end
    return v.v_local ~= v.v_remote
end

-- read the local manifest file
local function read_local_manifest()
    local local_ok = false
    local local_manifest = {}
    local imfile = fs.open("install_manifest.json", "r")
    if imfile ~= nil then
        local_ok, local_manifest = pcall(function () return textutils.unserializeJSON(imfile.readAll()) end)
        imfile.close()
    end
    return local_ok, local_manifest
end

-- get the manifest from GitHub
local function get_remote_manifest()
    local response, error = http.get(install_manifest)
    if response == nil then
        orange();println("Failed to get installation manifest from GitHub, cannot update or install.")
        red();println("HTTP error: "..error);white()
        return false, {}
    end

    local ok, manifest = pcall(function () return textutils.unserializeJSON(response.readAll()) end)
    if not ok then red();println("error parsing remote installation manifest");white() end

    return ok, manifest
end

-- record the local installation manifest
local function write_install_manifest(manifest, dependencies)
    local versions = {}
    for key, value in pairs(manifest.versions) do
        local is_dependency = false
        for _, dependency in pairs(dependencies) do
            if (key == "bootloader" and dependency == "system") or key == dependency then
                is_dependency = true;break
            end
        end
        if key == app or key == "comms" or is_dependency then versions[key] = value end
    end

    manifest.versions = versions

    local imfile = fs.open("install_manifest.json", "w")
    imfile.write(textutils.serializeJSON(manifest))
    imfile.close()
end

-- try at most 3 times to download a file from the repository and write into w_path base directory
---@return 0|1|2|3 success 0: ok, 1: download fail, 2: file open fail, 3: out of space
local function http_get_file(file, w_path)
    local dl, err
    for i = 1, 3 do
        dl, err = http.get(repo_path..file)
        if dl then
            if i > 1 then green();println("success!");lgray() end
            local f = fs.open(w_path..file, "w")
            if not f then return 2 end
            local ok, msg = pcall(function() f.write(dl.readAll()) end)
            f.close()
            if not ok then
                if string.find(msg or "", "Out of space") ~= nil then
                    red();println("[out of space]");lgray()
                    return 3
                else return 2 end
            end
            break
        else
            red();println("HTTP Error: "..err)
            if i < 3 then
                lgray();print("> retrying...")
                ---@diagnostic disable-next-line: undefined-field
                os.sleep(i/3.0)
            else
                return 1
            end
        end
    end
    return 0
end

-- recursively build a tree out of the file manifest
local function gen_tree(manifest, log)
    local function _tree_add(tree, split)
        if #split > 1 then
            local name = table.remove(split, 1)
            if tree[name] == nil then tree[name] = {} end
            table.insert(tree[name], _tree_add(tree[name], split))
        else return split[1] end
        return nil
    end

    local list, tree = { log }, {}

    -- make a list of each and every file
    for _, files in pairs(manifest.files) do for i = 1, #files do table.insert(list, files[i]) end end

    for i = 1, #list do
        local split = {}
---@diagnostic disable-next-line: discard-returns
        string.gsub(list[i], "([^/]+)", function(c) split[#split + 1] = c end)
        if #split == 1 then table.insert(tree, list[i])
        else table.insert(tree, _tree_add(tree, split)) end
    end

    return tree
end

local function _in_array(val, array)
    for _, v in pairs(array) do if v == val then return true end end
    return false
end

local function _clean_dir(dir, tree)
    if tree == nil then tree = {} end
    local ls = fs.list(dir)
    for _, val in pairs(ls) do
        local path = dir.."/"..val
        if fs.isDir(path) then
            _clean_dir(path, tree[val])
            if #fs.list(path) == 0 then fs.delete(path);println("deleted "..path) end
        elseif (not _in_array(val, tree)) and (val ~= "config.lua" ) then ---@todo remove config.lua on full release
            fs.delete(path)
            println("deleted "..path)
        end
    end
end

-- go through app/common directories to delete unused files
local function clean(manifest)
    local log = nil
    if fs.exists(app..".settings") and settings.load(app..".settings") then
        log = settings.get("LogPath")
        if log:sub(1, 1) == "/" then log = log:sub(2) end
    end

    local tree = gen_tree(manifest, log)

    table.insert(tree, "install_manifest.json")
    table.insert(tree, "ccmsi.lua")

    local ls = fs.list("/")
    for _, val in pairs(ls) do
        if fs.isDriveRoot(val) then
            yellow();println("skipped mount '"..val.."'")
        elseif fs.isDir(val) then
            if tree[val] ~= nil then lgray();_clean_dir("/"..val, tree[val])
            else white(); if ask_y_n("delete the unused directory '"..val.."'") then lgray();_clean_dir("/"..val) end end
            if #fs.list(val) == 0 then fs.delete(val);lgray();println("deleted empty directory '"..val.."'") end
        elseif not _in_array(val, tree) and (string.find(val, ".settings") == nil) then
            white();if ask_y_n("delete the unused file '"..val.."'") then fs.delete(val);lgray();println("deleted "..val) end
        end
    end

    white()
end

-- get and validate command line options

if _is_pkt_env then println("- SCADA Installer "..CCMSI_VERSION.." -")
else println("-- CC Mekanism SCADA Installer "..CCMSI_VERSION.." --") end

if #opts == 0 or opts[1] == "help" then
    println("usage: ccmsi <mode> <app> <branch>")
    if _is_pkt_env then
    yellow();println("<mode>");lgray()
    println(" check - check latest")
    println(" install - fresh install")
    println(" update - update app")
    println(" uninstall - remove app")
    yellow();println("<app>");lgray()
    println(" reactor-plc")
    println(" rtu")
    println(" supervisor")
    println(" coordinator")
    println(" pocket")
    println(" installer (update only)")
    yellow();println("<branch>");lgray();
    println(" main (default) | devel");white()
    else
    println("<mode>")
    lgray()
    println(" check       - check latest versions available")
    yellow()
    println("               ccmsi check <branch> for target")
    lgray()
    println(" install     - fresh install")
    println(" update      - update files")
    println(" uninstall   - delete files INCLUDING config/logs")
    white();println("<app>");lgray()
    println(" reactor-plc - reactor PLC firmware")
    println(" rtu         - RTU firmware")
    println(" supervisor  - supervisor server application")
    println(" coordinator - coordinator application")
    println(" pocket      - pocket application")
    println(" installer   - ccmsi installer (update only)")
    white();println("<branch>")
    lgray();println(" main (default) | devel");white()
    end
    return
else
    mode = get_opt(opts[1], { "check", "install", "update", "uninstall" })
    if mode == nil then
        red();println("Unrecognized mode.");white()
        return
    end

    app = get_opt(opts[2], { "reactor-plc", "rtu", "supervisor", "coordinator", "pocket", "installer" })
    if app == nil and mode ~= "check" then
        red();println("Unrecognized application.");white()
        return
    elseif app == "installer" and mode ~= "update" then
        red();println("Installer app only supports 'update' option.");white()
        return
    end

    -- determine target
    if mode == "check" then target = opts[2] else target = opts[3] end
    if (target ~= "main") and (target ~= "devel") then
        if (target and target ~= "") then yellow();println("Unknown target, defaulting to 'main'");white() end
        target = "main"
    end

    -- set paths
    install_manifest = manifest_path..target.."/install_manifest.json"
    repo_path = repo_path..target.."/"
end

-- run selected mode
if mode == "check" then
    local ok, manifest = get_remote_manifest()
    if not ok then return end

    local local_ok, local_manifest = read_local_manifest()
    if not local_ok then
        yellow();println("failed to load local installation information");white()
        local_manifest = { versions = { installer = CCMSI_VERSION } }
    else
        local_manifest.versions.installer = CCMSI_VERSION
    end

    -- list all versions
    for key, value in pairs(manifest.versions) do
        term.setTextColor(colors.purple)
        local tag = string.format("%-14s", "["..key.."]")
        if not _is_pkt_env then print(tag) end
        if key == "installer" or (local_ok and (local_manifest.versions[key] ~= nil)) then
            if _is_pkt_env then println(tag) end
            blue();print(local_manifest.versions[key])
            if value ~= local_manifest.versions[key] then
                white();print(" (")
                cyan();print(value);white();println(" available)")
            else green();println(" (up to date)") end
        elseif not _is_pkt_env then
            lgray();print("not installed");white();print(" (latest ")
            cyan();print(value);white();println(")")
        end
    end

    if manifest.versions.installer ~= local_manifest.versions.installer and not _is_pkt_env then
        yellow();println("\nA different version of the installer is available, it is recommended to update (use 'ccmsi update installer').");white()
    end
elseif mode == "install" or mode == "update" then
    local update_installer = app == "installer"
    local ok, manifest = get_remote_manifest()
    if not ok then return end

    local ver = {
        app = { v_local = nil, v_remote = nil, changed = false },
        boot = { v_local = nil, v_remote = nil, changed = false },
        comms = { v_local = nil, v_remote = nil, changed = false },
        common = { v_local = nil, v_remote = nil, changed = false },
        graphics = { v_local = nil, v_remote = nil, changed = false },
        lockbox = { v_local = nil, v_remote = nil, changed = false }
    }

    -- try to find local versions
    local local_ok, lmnf = read_local_manifest()
    if not local_ok then
        if mode == "update" then
            red();println("Failed to load local installation information, cannot update.");white()
            return
        end
    elseif not update_installer then
        ver.boot.v_local = lmnf.versions.bootloader
        ver.app.v_local = lmnf.versions[app]
        ver.comms.v_local = lmnf.versions.comms
        ver.common.v_local = lmnf.versions.common
        ver.graphics.v_local = lmnf.versions.graphics
        ver.lockbox.v_local = lmnf.versions.lockbox

        if lmnf.versions[app] == nil then
            red();println("Another application is already installed, please uninstall it before installing a new application.");white()
            return
        end
    end

    if manifest.versions.installer ~= CCMSI_VERSION then
        if not update_installer then yellow();println("A different version of the installer is available, it is recommended to update to it.");white() end
        if update_installer or ask_y_n("Would you like to update now", true) then
            lgray();println("GET ccmsi.lua")
            local dl, err = http.get(repo_path.."ccmsi.lua")

            if dl == nil then
                red();println("HTTP Error: "..err)
                println("Installer download failed.");white()
            else
                local handle = fs.open(debug.getinfo(1, "S").source:sub(2), "w") -- this file, regardless of name or location
                handle.write(dl.readAll())
                handle.close()
                green();println("Installer updated successfully.");white()
            end

            return
        end
    elseif update_installer then
        green();println("Installer already up-to-date.");white()
        return
    end

    ver.boot.v_remote = manifest.versions.bootloader
    ver.app.v_remote = manifest.versions[app]
    ver.comms.v_remote = manifest.versions.comms
    ver.common.v_remote = manifest.versions.common
    ver.graphics.v_remote = manifest.versions.graphics
    ver.lockbox.v_remote = manifest.versions.lockbox

    green()
    if mode == "install" then print("Installing ") else print("Updating ") end
    println(app.." files...");white()

    ver.boot.changed = show_pkg_change("bootldr", ver.boot)
    ver.common.changed = show_pkg_change("common", ver.common)
    ver.comms.changed = show_pkg_change("comms", ver.comms)
    if ver.comms.changed and ver.comms.v_local ~= nil then
        print("[comms] ");yellow();println("other devices on the network will require an update");white()
    end
    ver.app.changed = show_pkg_change(app, ver.app)
    ver.graphics.changed = show_pkg_change("graphics", ver.graphics)
    ver.lockbox.changed = show_pkg_change("lockbox", ver.lockbox)

    --------------------------
    -- START INSTALL/UPDATE --
    --------------------------

    local space_required = manifest.sizes.manifest
    local space_available = fs.getFreeSpace("/")

    local single_file_mode = false
    local file_list = manifest.files
    local size_list = manifest.sizes
    local dependencies = manifest.depends[app]

    table.insert(dependencies, app)

    -- helper function to check if a dependency is unchanged
    local function unchanged(dependency)
        if dependency == "system" then return not ver.boot.changed
        elseif dependency == "graphics" then return not ver.graphics.changed
        elseif dependency == "lockbox" then return not ver.lockbox.changed
        elseif dependency == "common" then return not (ver.common.changed or ver.comms.changed)
        elseif dependency == app then return not ver.app.changed
        else return true end
    end

    local any_change = false

    for _, dependency in pairs(dependencies) do
        local size = size_list[dependency]
        space_required = space_required + size
        any_change = any_change or not unchanged(dependency)
    end

    if mode == "update" and not any_change then
        yellow();println("Nothing to do, everything is already up-to-date!");white()
        return
    end

    -- ask for confirmation
    if not ask_y_n("Continue", false) then return end

    -- check space constraints
    if space_available < space_required then
        single_file_mode = true
    end

    local success = true

    -- delete a file if the capitalization changes so that things work on Windows
    ---@param path string
    local function mitigate_case(path)
        local dir, file = fs.getDir(path), fs.getName(path)
        if not fs.isDir(dir) then return end
        for _, p in ipairs(fs.list(dir)) do
            if string.lower(p) == string.lower(file) then
                if p ~= file then fs.delete(path) end
                return
            end
        end
    end

    ---@param dl_stat 1|2|3 download status
    ---@param file string file name
    ---@param attempt integer recursive attempt #
    ---@param sf_install function installer function for recursion
    local function handle_dl_fail(dl_stat, file, attempt, sf_install)
        red()
        if dl_stat == 1 then
            println("failed to download "..file)
        elseif dl_stat > 1 then
            if dl_stat == 2 then println("filesystem error with "..file) else println("no space for "..file) end
            if attempt == 1 then
                orange();println("re-attempting operation...");white()
                sf_install(2)
            elseif attempt == 2 then
                yellow()
                if dl_stat == 2 then println("There was an error writing to a file.") else println("Insufficient space available.") end
                lgray()
                if dl_stat == 2 then
                    println("This may be due to insufficent space available or file permission issues. The installer can now attempt to delete files not used by the SCADA system.")
                else
                    println("The installer can now attempt to delete files not used by the SCADA system.")
                end
                white()
                if not ask_y_n("Continue", false) then
                    success = false
                    return
                end
                clean(manifest)
                sf_install(3)
            elseif attempt == 3 then
                yellow()
                if dl_stat == 2 then println("There again was an error writing to a file.") else println("Insufficient space available.") end
                lgray()
                if dl_stat == 2 then
                    println("This may be due to insufficent space available or file permission issues. Please delete any unused files you have on this computer then try again. Do not delete the "..app..".settings file unless you want to re-configure.")
                else
                    println("Please delete any unused files you have on this computer then try again. Do not delete the "..app..".settings file unless you want to re-configure.")
                end
                white()
                success = false
            end
        end
    end

    -- single file update routine: go through all files and replace one by one
    ---@param attempt integer recursive attempt #
    local function sf_install(attempt)
---@diagnostic disable-next-line: undefined-field
        if attempt > 1 then os.sleep(2.0) end

        local abort_attempt = false
        success = true

        for _, dependency in pairs(dependencies) do
            if mode == "update" and unchanged(dependency) then
                pkg_message("skipping install of unchanged package", dependency)
            else
                pkg_message("installing package", dependency)
                lgray()

                -- beginning on the second try, delete the directory before starting
                if attempt >= 2 then
                    if dependency == "system" then
                    elseif dependency == "common" then
                        if fs.exists("/scada-common") then
                            fs.delete("/scada-common")
                            println("deleted /scada-common")
                        end
                    else
                        if fs.exists("/"..dependency) then
                            fs.delete("/"..dependency)
                            println("deleted /"..dependency)
                        end
                    end
                end

                local files = file_list[dependency]
                for _, file in pairs(files) do
                    println("GET "..file)
                    mitigate_case(file)
                    local dl_stat = http_get_file(file, "/")
                    if dl_stat ~= 0 then
                        abort_attempt = true
---@diagnostic disable-next-line: param-type-mismatch
                        handle_dl_fail(dl_stat, file, attempt, sf_install)
                        break
                    end
                end
            end
            if abort_attempt or not success then break end
        end
    end

    -- handle update/install
    if single_file_mode then sf_install(1)
    else
        if fs.exists(install_dir) then fs.delete(install_dir);fs.makeDir(install_dir) end

        -- download all dependencies
        for _, dependency in pairs(dependencies) do
            if mode == "update" and unchanged(dependency) then
                pkg_message("skipping download of unchanged package", dependency)
            else
                pkg_message("downloading package", dependency)
                lgray()

                local files = file_list[dependency]
                for _, file in pairs(files) do
                    println("GET "..file)
                    local dl_stat = http_get_file(file, install_dir.."/")
                    success = dl_stat == 0
                    if dl_stat == 1 then
                        red();println("failed to download "..file)
                        break
                    elseif dl_stat == 2 then
                        red();println("filesystem error with "..file)
                        break
                    elseif dl_stat == 3 then
                        -- this shouldn't occur in this mode
                        red();println("no space for "..file)
                        break
                    end
                end
            end
            if not success then break end
        end

        -- copy in downloaded files (installation)
        if success then
            for _, dependency in pairs(dependencies) do
                if mode == "update" and unchanged(dependency) then
                    pkg_message("skipping install of unchanged package", dependency)
                else
                    pkg_message("installing package", dependency)
                    lgray()

                    local files = file_list[dependency]
                    for _, file in pairs(files) do
                        local temp_file = install_dir.."/"..file
                        if fs.exists(file) then fs.delete(file) end
                        fs.move(temp_file, file)
                    end
                end
            end
        end

        fs.delete(install_dir)
    end

    if success then
        write_install_manifest(manifest, dependencies)
        green()
        if mode == "install" then
            println("Installation completed successfully.")
        else println("Update completed successfully.") end
        white();println("Ready to clean up unused files, press any key to continue...")
        any_key();clean(manifest)
        white();println("Done.")
    else
        red()
        if single_file_mode then
            if mode == "install" then
                println("Installation failed, files may have been skipped.")
            else println("Update failed, files may have been skipped.") end
        else
            if mode == "install" then
                println("Installation failed.")
            else orange();println("Update failed, existing files unmodified.") end
        end
    end
elseif mode == "uninstall" then
    local ok, manifest = read_local_manifest()
    if not ok then
        red();println("Error parsing local installation manifest.");white()
        return
    end

    if manifest.versions[app] == nil then
        red();println("Error: '"..app.."' is not installed.")
        return
    end

    orange();println("Uninstalling all "..app.." files...")

    -- ask for confirmation
    if not ask_y_n("Continue", false) then return end

    -- delete unused files first
    clean(manifest)

    local file_list = manifest.files
    local dependencies = manifest.depends[app]

    table.insert(dependencies, app)

    -- delete all installed files
    lgray()
    for _, dependency in pairs(dependencies) do
        local files = file_list[dependency]
        for _, file in pairs(files) do
            if fs.exists(file) then fs.delete(file);println("deleted "..file) end
        end

        local folder = files[1]
        while true do
            local dir = fs.getDir(folder)
            if dir == "" or dir == ".." then break else folder = dir end
        end

        if fs.isDir(folder) then
            fs.delete(folder)
            println("deleted directory "..folder)
        end
    end

    -- delete log file
    local log_deleted = false
    local settings_file = app..".settings"

    if fs.exists(settings_file) and settings.load(settings_file) then
        local log = settings.get("LogPath")
        if log ~= nil then
            log_deleted = true
            if fs.exists(log) then
                fs.delete(log)
                println("deleted log file "..log)
            end
        end
    end

    if not log_deleted then
        red();println("Failed to delete log file (it may not exist).");lgray()
    end

    if fs.exists(settings_file) then
        fs.delete(settings_file);println("deleted "..settings_file)
    end

    fs.delete("install_manifest.json")
    println("deleted install_manifest.json")

    green();println("Done!")
end

white()

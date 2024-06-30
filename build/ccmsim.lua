local function println(message) print(tostring(message)) end
local function print(message) term.write(tostring(message)) end

local opts = { ... }
local mode, app

local function red() term.setTextColor(colors.red) end
local function orange() term.setTextColor(colors.orange) end
local function yellow() term.setTextColor(colors.yellow) end
local function green() term.setTextColor(colors.green) end
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
        elseif (not _in_array(val, tree)) and (val ~= "config.lua" ) then
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
    table.insert(tree, "ccmsim.lua")

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

println("-- CC Mekanism SCADA Install Manager (Off-Line) --")

if #opts == 0 or opts[1] == "help" then
    println("usage: ccmsim <mode>")
    println("<mode>")
    lgray()
    println(" check     - check your installed versions")
    println(" update-rm - delete everything except the config,")
    println("             so that you can upload files for a")
    println("             new two-file off-line update")
    println(" uninstall - delete all app files and config")
    return
else
    mode = get_opt(opts[1], { "check", "update-rm", "uninstall" })
    if mode == nil then
        red();println("Unrecognized mode.");white()
        return
    end
end

-- run selected mode
if mode == "check" then
    local local_ok, manifest = read_local_manifest()
    if not local_ok then
        yellow();println("failed to load local installation information");white()
    end

    -- list all versions
    for key, value in pairs(manifest.versions) do
        term.setTextColor(colors.purple)
        print(string.format("%-14s", "["..key.."]"))
        blue();println(value);white()
    end
elseif mode == "update-rm" or mode == "uninstall" then
    local ok, manifest = read_local_manifest()
    if not ok then
        red();println("Error parsing local installation manifest.");white()
        return
    end

    app = manifest.depends[#manifest.depends]

    if mode == "uninstall" then
        orange();println("Uninstalling all app files...")
    else
        orange();println("Deleting all app files except for configuration...")
    end

    -- ask for confirmation
    if not ask_y_n("Continue", false) then return end

    -- delete unused files first
    clean(manifest)

    local file_list = manifest.files
    local dependencies = manifest.depends

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

    if mode == "uninstall" then
        if fs.exists(settings_file) then
            fs.delete(settings_file);println("deleted "..settings_file)
        end

        fs.delete("install_manifest.json")
        println("deleted install_manifest.json")

        fs.delete("ccmsim.lua")
        println("deleted ccmsim.lua")
    end

    green();println("Done!")
end

white()

--[[
CC-MEK-SCADA Installer Utility

Copyright (c) 2023 - 2026 Mikayla Fischler

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

local CCMSI_VERSION = "v1.22"

local IS_PKT = pocket ~= nil -- luacheck: ignore pocket

local INSTALL_DIR = "/.install-cache"
local MANIFEST_DIR = "https://mikaylafischler.github.io/cc-mek-scada/manifests/"
local REPO_BASE = "http://raw.githubusercontent.com/MikaylaFischler/cc-mek-scada/"

local OPTS = { ... }

local mode, app, target, repo_url, manifest_url

local function tsc(c) term.setTextColor(c) end

local function red() tsc(colors.red) end
local function orange() tsc(colors.orange) end
local function yellow() tsc(colors.yellow) end
local function green() tsc(colors.green) end
local function cyan() tsc(colors.cyan) end
local function blue() tsc(colors.blue) end
local function white() tsc(colors.white) end
local function lgray() tsc(colors.lightGray) end

local function pln(msg) print(tostring(msg)) end

-- stripped down & modified copy of log.dmesg
local function print(msg)
	msg = tostring(msg)

	local cur_x, cur_y = term.getCursorPos()
	local out_w, out_h = term.getSize()

	if cur_x == out_w then
		-- jump to next line
		cur_x = 1
		if cur_y == out_h then
			term.scroll(1)
			term.setCursorPos(1, cur_y)
		else
			term.setCursorPos(1, cur_y + 1)
		end
	end

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

-- get command line option in list
local function get_opt(opt, options)
	for _, v in pairs(options) do if opt == v then return v end end
	return nil
end

-- wait for any key press
local function any_key() os.pullEvent("key_up") end

-- ask the user yes or no
local function ask_y_n(question, default)
	print(question)
	if default == true then print(" (Y/n)? ") else print(" (y/N)? ") end
	local r = read();any_key()
	if r == "" then return default
	elseif r == "Y" or r == "y" then return true
	elseif r == "N" or r == "n" then return false
	else return nil end
end

local function pkg_msg(m, p) white();print(m.." ");blue();pln(p);white() end

-- indicate actions to be taken based on package differences for installs/updates
local function show_pkg_change(name, v)
	if v.v_local ~= nil then
		if v.v_local ~= v.v_remote then
			print("["..name.."] updating ");blue();print(v.v_local);white();print(" \xbb ");blue();pln(v.v_remote);white()
		elseif mode == "install" then
			pkg_msg("["..name.."] reinstalling", v.v_local)
		end
	else pkg_msg("["..name.."] new install of", v.v_remote) end
	return v.v_local ~= v.v_remote
end

-- read the local manifest file
local function read_local_manifest()
	local ok, manifest, imfile = false, {}, fs.open("install_manifest.json", "r")
	if imfile ~= nil then
		ok, manifest = pcall(function () return textutils.unserializeJSON(imfile.readAll()) end)
		imfile.close()
	end
	return ok, manifest
end

-- read the manifest from GitHub
local function read_remote_manifest()
	local resp, err = http.get(manifest_url)
	if resp == nil then
		orange();pln("Failed to read installation manifest from GitHub, cannot update or install.")
		red();pln("HTTP error: "..err);white()
		return false, {}
	end

	local ok, manifest = pcall(function () return textutils.unserializeJSON(resp.readAll()) end)
	if not ok then red();pln("error parsing remote installation manifest");white() end

	return ok, manifest
end

-- record the local installation manifest
local function write_install_manifest(manifest, deps)
	local versions = {}
	for k, v in pairs(manifest.versions) do
		local is_dep = false
		for _, dep in pairs(deps) do
			if (k == "bootloader" and dep == "system") or k == dep then
				is_dep = true;break
			end
		end
		if k == app or k == "comms" or is_dep then versions[k] = v end
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
		dl, err = http.get(repo_url..file)
		if dl then
			if i > 1 then green();pln("success!");lgray() end

			local f = fs.open(w_path..file, "w")
			if not f then return 2 end

			local ok, msg = pcall(function() f.write(dl.readAll()) end)
			f.close()
			if not ok then
				if string.find(msg or "", "Out of space") ~= nil then
					red();pln("[out of space]");lgray()
					return 3
				else return 2 end
			end
			break
		else
			red();pln("HTTP Error: "..err)
			if i < 3 then
				lgray();print("> retrying...")
				os.sleep(i/3.0)
			else return 1 end
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

	-- make a list of every file
	for _, files in pairs(manifest.files) do for i = 1, #files do table.insert(list, files[i]) end end

	for i = 1, #list do
		local split = {}
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
			if #fs.list(path) == 0 then fs.delete(path);pln("deleted "..path) end
		elseif (not _in_array(val, tree)) and (val ~= "config.lua" ) then ---@todo remove config.lua on full release
			fs.delete(path)
			pln("deleted "..path)
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
			yellow();pln("skipped mount '"..val.."'")
		elseif fs.isDir(val) then
			if tree[val] ~= nil then lgray();_clean_dir("/"..val, tree[val])
			else white(); if ask_y_n("delete the unused directory '"..val.."'") then lgray();_clean_dir("/"..val) end end
			if #fs.list(val) == 0 then fs.delete(val);lgray();pln("deleted empty directory '"..val.."'") end
		elseif not _in_array(val, tree) and (string.find(val, ".settings") == nil) then
			white();if ask_y_n("delete the unused file '"..val.."'") then fs.delete(val);lgray();pln("deleted "..val) end
		end
	end

	white()
end

-- handle command line options

if IS_PKT then pln("- SCADA Installer "..CCMSI_VERSION.." -")
else pln("-- CC Mekanism SCADA Installer "..CCMSI_VERSION.." --") end

if #OPTS == 0 or OPTS[1] == "help" then
	pln("usage: ccmsi <mode> <app> <branch>")

	if IS_PKT then
		blue();pln("<mode>")
		lgray();pln(" check - check latest\n install - fresh install\n update - update app\n uninstall - remove app")
		blue();pln("<app>")
		lgray();pln(" reactor-plc\n rtu\n supervisor\n coordinator\n pocket\n installer (update only)")
		blue();pln("<branch>")
		lgray();pln(" main (default) | devel");white()
	else
		blue();pln("<mode>")
		lgray();pln(" check       - check latest versions available")
		yellow();pln("               ccmsi check <branch> (skip <app>)")
		lgray();pln(" install     - fresh install\n update      - update files\n uninstall   - delete files INCLUDING config/logs")
		blue();print("<app>");cyan();pln(" omit to auto-detect installed app")
		lgray();pln(" reactor-plc - reactor PLC firmware\n rtu         - RTU firmware\n supervisor  - supervisor server application\n coordinator - coordinator application\n pocket      - pocket application\n installer   - ccmsi installer (update only)")
		blue();print("<branch>");cyan();pln(" omit for 'main'")
		lgray();pln(" main (default) | devel");white()
	end

	return
else
	mode = get_opt(OPTS[1], { "check", "install", "update", "uninstall" })
	if mode == nil then
		red();pln("Invalid mode.");white()
		return
	end

	local next_opt = 3
	local apps = { "reactor-plc", "rtu", "supervisor", "coordinator", "pocket", "installer" }
	app = get_opt(OPTS[2], apps)
	if app == nil then
		for _, a in pairs(apps) do
			if fs.isDir(a) then app, next_opt = a, 2 end
		end
	end

	if app == nil and mode ~= "check" then
		red();pln("Invalid application.");white()
		return
	elseif mode == "check" then
		next_opt = 2
	elseif app == "installer" and mode ~= "update" then
		red();pln("Installer only supports 'update'.");white()
		return
	end

	target = OPTS[next_opt] or "main"
	if target ~= "main" and target ~= "devel" then
		red();pln("Invalid branch target.");white()
		return
	end

	manifest_url = MANIFEST_DIR..target.."/install_manifest.json"
	repo_url = REPO_BASE..target.."/"
end

-- main operation

local ok, r_manifest, l_manifest

if mode == "check" then
	ok, r_manifest = read_remote_manifest()
	if not ok then return end

	ok, l_manifest = read_local_manifest()
	if not ok then
		yellow();pln("failed to load local installation information");white()
		l_manifest = { versions = { installer = CCMSI_VERSION } }
	else
		l_manifest.versions.installer = CCMSI_VERSION
	end

	-- list all versions
	for k, v in pairs(r_manifest.versions) do
		tsc(colors.purple)
		local tag = string.format("%-14s", "["..k.."]")
		if not IS_PKT then print(tag) end
		if k == "installer" or (ok and (l_manifest.versions[k] ~= nil)) then
			if IS_PKT then pln(tag) end
			blue();print(l_manifest.versions[k])
			if v ~= l_manifest.versions[k] then
				white();print(" (");cyan();print(v);white();pln(" available)")
			else green();pln(" (up to date)") end
		elseif not IS_PKT then
			lgray();print("not installed");white();print(" (latest ");cyan();print(v);white();pln(")")
		end
	end

	if r_manifest.versions.installer ~= l_manifest.versions.installer and not IS_PKT then
		yellow();pln("\nA different version of the installer is available, it is recommended to update (use 'ccmsi update installer').");white()
	end
elseif mode == "install" or mode == "update" then
	local update_installer = app == "installer"

	ok, r_manifest = read_remote_manifest()
	if not ok then return end

	local ver = {
		app = { v_local = nil, v_remote = nil, changed = false },
		boot = { v_local = nil, v_remote = nil, changed = false },
		comms = { v_local = nil, v_remote = nil, changed = false },
		common = { v_local = nil, v_remote = nil, changed = false },
		graphics = { v_local = nil, v_remote = nil, changed = false },
		lockbox = { v_local = nil, v_remote = nil, changed = false }
	}

	-- try to load local versions
	ok, l_manifest = read_local_manifest()
	if mode == "update" and not update_installer then
		if not ok then
			red();pln("Failed to load local installation information, cannot update.");white()
			return
		else
			ver.boot.v_local = l_manifest.versions.bootloader
			ver.app.v_local = l_manifest.versions[app]
			ver.comms.v_local = l_manifest.versions.comms
			ver.common.v_local = l_manifest.versions.common
			ver.graphics.v_local = l_manifest.versions.graphics
			ver.lockbox.v_local = l_manifest.versions.lockbox

			if l_manifest.versions[app] == nil then
				red();pln("Another application is already installed, please uninstall it before installing a new application.");white()
				return
			end
		end
	end

	-- installer update handling
	if r_manifest.versions.installer ~= CCMSI_VERSION then
		if not update_installer then yellow();pln("A different version of the installer is available, it is recommended to update to it.");white() end
		if update_installer or ask_y_n("Would you like to update now", true) then
			lgray();pln("GET ccmsi.lua")
			local dl, err = http.get(repo_url.."ccmsi.lua")

			if dl == nil then
				red();pln("HTTP Error: "..err)
				pln("Installer download failed.")
			else
				local handle = fs.open(debug.getinfo(1, "S").source:sub(2), "w") -- this file
				handle.write(dl.readAll())
				handle.close()
				green();pln("Installer updated successfully.")
			end

			white()
			return
		end
	elseif update_installer then
		green();pln("Installer already up-to-date.");white()
		return
	end

	ver.boot.v_remote = r_manifest.versions.bootloader
	ver.app.v_remote = r_manifest.versions[app]
	ver.comms.v_remote = r_manifest.versions.comms
	ver.common.v_remote = r_manifest.versions.common
	ver.graphics.v_remote = r_manifest.versions.graphics
	ver.lockbox.v_remote = r_manifest.versions.lockbox

	green()
	if mode == "install" then print("Installing ") else print("Updating ") end
	pln(app.." files...");white()

	ver.boot.changed = show_pkg_change("bootldr", ver.boot)
	ver.common.changed = show_pkg_change("common", ver.common)
	ver.comms.changed = show_pkg_change("comms", ver.comms)
	if ver.comms.changed and ver.comms.v_local ~= nil then
		print("[comms] ");yellow();pln("other devices on the network will require an update");white()
	end
	ver.app.changed = show_pkg_change(app, ver.app)
	ver.graphics.changed = show_pkg_change("graphics", ver.graphics)
	ver.lockbox.changed = show_pkg_change("lockbox", ver.lockbox)

	-- start install/update

	local space_req = r_manifest.sizes.manifest
	local space_avail = fs.getFreeSpace("/")

	local file_list = r_manifest.files
	local size_list = r_manifest.sizes
	local deps = r_manifest.depends[app]

	table.insert(deps, app)

	-- helper function to check if a dependency is unchanged
	local function unchanged(dep)
		if dep == "system" then return not ver.boot.changed
		elseif dep == "graphics" then return not ver.graphics.changed
		elseif dep == "lockbox" then return not ver.lockbox.changed
		elseif dep == "common" then return not (ver.common.changed or ver.comms.changed)
		elseif dep == app then return not ver.app.changed
		else return true end
	end

	local any_change = false

	for _, dep in pairs(deps) do
		local size = size_list[dep]
		space_req = space_req + size
		any_change = any_change or not unchanged(dep)
	end

	if mode == "update" and not any_change then
		yellow();pln("Nothing to do, everything is already up-to-date!");white()
		return
	end

	-- ask for confirmation
	if not ask_y_n("Continue", false) then return end

	local single_file_mode = space_avail < space_req

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
			pln("failed to download "..file)
		elseif dl_stat > 1 then
			if dl_stat == 2 then pln("filesystem error with "..file) else pln("no space for "..file) end
			if attempt == 1 then
				orange();pln("re-attempting operation...");white()
				sf_install(2)
			elseif attempt == 2 then
				yellow()
				if dl_stat == 2 then pln("There was an error writing to a file.") else pln("Insufficient space available.") end
				lgray()
				if dl_stat == 2 then
					pln("This may be due to insufficent space available or file permission issues. The installer can now attempt to delete files not used by the SCADA system.")
				else
					pln("The installer can now attempt to delete files not used by the SCADA system.")
				end
				white()
				if not ask_y_n("Continue", false) then
					success = false
					return
				end
				clean(r_manifest)
				sf_install(3)
			elseif attempt == 3 then
				yellow()
				if dl_stat == 2 then pln("There again was an error writing to a file.") else pln("Insufficient space available.") end
				lgray()
				if dl_stat == 2 then
					pln("This may be due to insufficent space available or file permission issues. Please delete any unused files you have on this computer then try again. Do not delete the "..app..".settings file unless you want to re-configure.")
				else
					pln("Please delete any unused files you have on this computer then try again. Do not delete the "..app..".settings file unless you want to re-configure.")
				end
				white()
				success = false
			end
		end
	end

	-- single file update routine: go through all files and replace one by one
	---@param attempt integer recursive attempt #
	local function sf_install(attempt)
		if attempt > 1 then os.sleep(2.0) end

		local abort_attempt = false
		success = true

		for _, dep in pairs(deps) do
			if mode == "update" and unchanged(dep) then
				pkg_msg("skipping install of unchanged package", dep)
			else
				pkg_msg("installing package", dep)
				lgray()

				-- beginning on the second try, delete the directory before starting
				if attempt >= 2 then
					if dep == "system" then
					elseif dep == "common" then
						if fs.exists("/scada-common") then
							fs.delete("/scada-common")
							pln("deleted /scada-common")
						end
					else
						if fs.exists("/"..dep) then
							fs.delete("/"..dep)
							pln("deleted /"..dep)
						end
					end
				end

				local files = file_list[dep]
				for _, file in pairs(files) do
					pln("GET "..file)
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
		if fs.exists(INSTALL_DIR) then fs.delete(INSTALL_DIR);fs.makeDir(INSTALL_DIR) end

		-- download all dependencies
		for _, dep in pairs(deps) do
			if mode == "update" and unchanged(dep) then
				pkg_msg("skipping download of unchanged package", dep)
			else
				pkg_msg("downloading package", dep)
				lgray()

				local files = file_list[dep]
				for _, file in pairs(files) do
					pln("GET "..file)
					local dl_stat = http_get_file(file, INSTALL_DIR.."/")
					success = dl_stat == 0
					if dl_stat == 1 then
						red();pln("failed to download "..file)
						break
					elseif dl_stat == 2 then
						red();pln("filesystem error with "..file)
						break
					elseif dl_stat == 3 then
						-- this shouldn't occur in this mode
						red();pln("no space for "..file)
						break
					end
				end
			end
			if not success then break end
		end

		-- copy in downloaded files (installation)
		if success then
			for _, dep in pairs(deps) do
				if mode == "update" and unchanged(dep) then
					pkg_msg("skipping install of unchanged package", dep)
				else
					pkg_msg("installing package", dep)
					lgray()

					local files = file_list[dep]
					for _, file in pairs(files) do
						local temp_file = INSTALL_DIR.."/"..file
						if fs.exists(file) then fs.delete(file) end
						fs.move(temp_file, file)
					end
				end
			end
		end

		fs.delete(INSTALL_DIR)
	end

	if success then
		write_install_manifest(r_manifest, deps)
		green()
		if mode == "install" then
			pln("Installation completed successfully.")
		else pln("Update completed successfully.") end
		white();pln("Ready to clean up unused files, press any key to continue...")
		any_key();clean(r_manifest)
		white();pln("Done.")
	else
		red()
		if single_file_mode then
			if mode == "install" then
				pln("Installation failed, files may have been skipped.")
			else pln("Update failed, files may have been skipped.") end
		else
			if mode == "install" then
				pln("Installation failed.")
			else orange();pln("Update failed, existing files unmodified.") end
		end
	end
elseif mode == "uninstall" then
	ok, l_manifest = read_local_manifest()
	if not ok then
		red();pln("Error parsing local installation manifest.");white()
		return
	end

	if l_manifest.versions[app] == nil then
		red();pln("Error: '"..app.."' is not installed.")
		return
	end

	orange();pln("Uninstalling all "..app.." files...")

	-- ask for confirmation
	if not ask_y_n("Continue", false) then return end

	-- delete unused files first
	clean(l_manifest)

	local file_list = l_manifest.files
	local deps = l_manifest.depends[app]

	table.insert(deps, app)

	-- delete all installed files
	lgray()
	for _, dep in pairs(deps) do
		local files = file_list[dep]
		for _, file in pairs(files) do
			if fs.exists(file) then fs.delete(file);pln("deleted "..file) end
		end

		local folder = files[1]
		while true do
			local dir = fs.getDir(folder)
			if dir == "" or dir == ".." then break else folder = dir end
		end

		if fs.isDir(folder) then
			fs.delete(folder)
			pln("deleted directory "..folder)
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
				pln("deleted log file "..log)
			end
		end
	end

	if not log_deleted then
		red();pln("Failed to delete log file (it may not exist).");lgray()
	end

	if fs.exists(settings_file) then
		fs.delete(settings_file);pln("deleted "..settings_file)
	end

	fs.delete("install_manifest.json")
	pln("deleted install_manifest.json")

	green();pln("Done!")
end

white()

--
-- Protected Graphics Interface
--

local log  = require("scada-common.log")
local util = require("scada-common.util")

local pgi = {}

local data = {
    rtu_list = nil,  ---@type ListBox|nil
    pdg_list = nil,  ---@type ListBox|nil
    chk_list = nil,  ---@type ListBox|nil
    rtu_entry = nil, ---@type function
    pdg_entry = nil, ---@type function
    chk_entry = nil, ---@type function
    -- list entries
    entries = {
        rtu = {},    ---@type Div[]
        pdg = {},    ---@type Div[]
        chk = {},    ---@type Div[][]
        missing = {} ---@type Div[]
    }
}

-- link list boxes
---@param rtu_list ListBox RTU list element
---@param rtu_entry fun(parent: ListBox, id: integer) : Div RTU entry constructor
---@param pdg_list ListBox pocket diagnostics list element
---@param pdg_entry fun(parent: ListBox, id: integer) : Div pocket diagnostics entry constructor
---@param chk_list ListBox CHK list element
---@param chk_entry fun(parent: ListBox, msg: string, fail_code: integer) : Div CHK entry constructor
function pgi.link_elements(rtu_list, rtu_entry, pdg_list, pdg_entry, chk_list, chk_entry)
    data.rtu_list = rtu_list
    data.pdg_list = pdg_list
    data.chk_list = chk_list
    data.rtu_entry = rtu_entry
    data.pdg_entry = pdg_entry
    data.chk_entry = chk_entry
end

-- unlink all fields, disabling the PGI
function pgi.unlink()
    data.rtu_list = nil
    data.pdg_list = nil
    data.chk_list = nil
    data.rtu_entry = nil
    data.pdg_entry = nil
    data.chk_entry = nil
end

-- add an RTU entry to the RTU list
---@param session_id integer RTU session
function pgi.create_rtu_entry(session_id)
    if data.rtu_list ~= nil and data.rtu_entry ~= nil then
        local success, result = pcall(data.rtu_entry, data.rtu_list, session_id)

        if success then
            data.entries.rtu[session_id] = result
            log.debug(util.c("PGI: created RTU entry (", session_id, ")"))
        else
            log.error(util.c("PGI: failed to create RTU entry (", result, ")"), true)
        end
    end
end

-- delete an RTU entry from the RTU list
---@param session_id integer RTU session
function pgi.delete_rtu_entry(session_id)
    if data.entries.rtu[session_id] ~= nil then
        local success, result = pcall(data.entries.rtu[session_id].delete)
        data.entries.rtu[session_id] = nil

        if success then
            log.debug(util.c("PGI: deleted RTU entry (", session_id, ")"))
        else
            log.error(util.c("PGI: failed to delete RTU entry (", result, ")"), true)
        end
    else
        log.warning(util.c("PGI: tried to delete unknown RTU entry ", session_id))
    end
end

-- add a PDG entry to the PDG list
---@param session_id integer pocket diagnostics session
function pgi.create_pdg_entry(session_id)
    if data.pdg_list ~= nil and data.pdg_entry ~= nil then
        local success, result = pcall(data.pdg_entry, data.pdg_list, session_id)

        if success then
            data.entries.pdg[session_id] = result
            log.debug(util.c("PGI: created PDG entry (", session_id, ")"))
        else
            log.error(util.c("PGI: failed to create PDG entry (", result, ")"), true)
        end
    end
end

-- delete a PDG entry from the PDG list
---@param session_id integer pocket diagnostics session
function pgi.delete_pdg_entry(session_id)
    if data.entries.pdg[session_id] ~= nil then
        local success, result = pcall(data.entries.pdg[session_id].delete)
        data.entries.pdg[session_id] = nil

        if success then
            log.debug(util.c("PGI: deleted PDG entry (", session_id, ")"))
        else
            log.error(util.c("PGI: failed to delete PDG entry (", result, ")"), true)
        end
    else
        log.warning(util.c("PGI: tried to delete unknown PDG entry ", session_id))
    end
end

-- add a device ID check failure entry to the CHK list
---@note this assumes only one type of failure can occur per each RTU gateway session's RTU, which is the case
---@param unit unit_session RTU session
---@param fail_code integer failure code
---@param msg string description to show the user
function pgi.create_chk_entry(unit, fail_code, msg)
    local gw_session = unit.get_session_id()

    if data.chk_list ~= nil and data.chk_entry ~= nil then
        if not data.entries.chk[gw_session] then data.entries.chk[gw_session] = {} end

        local success, result = pcall(data.chk_entry, data.chk_list, msg, fail_code)

        if success then
            data.entries.chk[gw_session][unit.get_unit_id()] = result
            log.debug(util.c("PGI: created CHK entry (", gw_session, ":", unit.get_unit_id(), ")"))
        else
            log.error(util.c("PGI: failed to create CHK entry (", result, ")"), true)
        end
    end
end

-- delete a device ID check failure entry from the CHK list<br>
-- this assumes only one type of failure can occur per each RTU gateway session's RTU, which is the case
---@param unit unit_session RTU session
function pgi.delete_chk_entry(unit)
    local gw_session = unit.get_session_id()
    local ent_chk = data.entries.chk

    if ent_chk[gw_session] ~= nil and ent_chk[gw_session][unit.get_unit_id()] ~= nil then
        local success, result = pcall(ent_chk[gw_session][unit.get_unit_id()].delete)
        ent_chk[gw_session][unit.get_unit_id()] = nil

        if success then
            log.debug(util.c("PGI: deleted CHK entry ", gw_session, ":", unit.get_unit_id()))
        else
            log.error(util.c("PGI: failed to delete CHK entry (", result, ")"), true)
        end
    else
        log.warning(util.c("PGI: tried to delete unknown CHK entry with session of ", gw_session, " and unit ID of ", unit.get_unit_id()))
    end
end

-- add a device ID missing entry to the CHK list
---@param message string missing device message
function pgi.create_missing_entry(message)
    if data.chk_list ~= nil and data.chk_entry ~= nil then
        local success, result = pcall(data.chk_entry, data.chk_list, message, 4)

        if success then
            data.entries.missing[message] = result
            log.debug(util.c("PGI: created missing CHK entry (", message, ")"))
        else
            log.error(util.c("PGI: failed to create missing CHK entry (", result, ")"), true)
        end
    end
end

-- delete a device ID missing entry from the CHK list
---@param message string missing device message
function pgi.delete_missing_entry(message)
    if data.entries.missing[message] ~= nil then
        local success, result = pcall(data.entries.missing[message].delete)
        data.entries.missing[message] = nil

        if success then
            log.debug(util.c("PGI: deleted missing CHK entry \"", message, "\""))
        else
            log.error(util.c("PGI: failed to delete missing CHK entry (", result, ")"), true)
        end
    else
        log.warning(util.c("PGI: tried to delete unknown missing CHK entry \"", message, "\""))
    end
end

return pgi

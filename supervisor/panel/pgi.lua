--
-- Protected Graphics Interface
--

local log  = require("scada-common.log")
local util = require("scada-common.util")

local pgi = {}

local data = {
    rtu_list = nil,     ---@type nil|graphics_element
    pdg_list = nil,     ---@type nil|graphics_element
    rtu_entry = nil,    ---@type function
    pdg_entry = nil,    ---@type function
    -- session entries
    s_entries = { rtu = {}, pdg = {} }
}

-- link list boxes
---@param rtu_list graphics_element RTU list element
---@param rtu_entry function RTU entry constructor
---@param pdg_list graphics_element pocket diagnostics list element
---@param pdg_entry function pocket diagnostics entry constructor
function pgi.link_elements(rtu_list, rtu_entry, pdg_list, pdg_entry)
    data.rtu_list = rtu_list
    data.pdg_list = pdg_list
    data.rtu_entry = rtu_entry
    data.pdg_entry = pdg_entry
end

-- unlink all fields, disabling the PGI
function pgi.unlink()
    data.rtu_list = nil
    data.pdg_list = nil
    data.rtu_entry = nil
    data.pdg_entry = nil
end

-- add an RTU entry to the RTU list
---@param session_id integer RTU session
function pgi.create_rtu_entry(session_id)
    if data.rtu_list ~= nil and data.rtu_entry ~= nil then
        local success, result = pcall(data.rtu_entry, data.rtu_list, session_id)

        if success then
            data.s_entries.rtu[session_id] = result
        else
            log.error(util.c("PGI: failed to create RTU entry (", result, ")"), true)
        end
    end
end

-- delete an RTU entry from the RTU list
---@param session_id integer RTU session
function pgi.delete_rtu_entry(session_id)
    if data.s_entries.rtu[session_id] ~= nil then
        local success, result = pcall(data.s_entries.rtu[session_id].delete)
        data.s_entries.rtu[session_id] = nil

        if not success then
            log.error(util.c("PGI: failed to delete RTU entry (", result, ")"), true)
        end
    else
        log.debug(util.c("PGI: tried to delete unknown RTU entry ", session_id))
    end
end

-- add a PDG entry to the PDG list
---@param session_id integer pocket diagnostics session
function pgi.create_pdg_entry(session_id)
    if data.pdg_list ~= nil and data.pdg_entry ~= nil then
        local success, result = pcall(data.pdg_entry, data.pdg_list, session_id)

        if success then
            data.s_entries.pdg[session_id] = result
        else
            log.error(util.c("PGI: failed to create PDG entry (", result, ")"), true)
        end
    end
end

-- delete a PDG entry from the PDG list
---@param session_id integer pocket diagnostics session
function pgi.delete_pdg_entry(session_id)
    if data.s_entries.pdg[session_id] ~= nil then
        local success, result = pcall(data.s_entries.pdg[session_id].delete)
        data.s_entries.pdg[session_id] = nil

        if not success then
            log.error(util.c("PGI: failed to delete PDG entry (", result, ")"), true)
        end
    else
        log.debug(util.c("PGI: tried to delete unknown PDG entry ", session_id))
    end
end

return pgi

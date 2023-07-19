--
-- Protected Graphics Interface
--

local log  = require("scada-common.log")
local util = require("scada-common.util")

local pgi = {}

local data = {
    pkt_list = nil,     ---@type nil|graphics_element
    pkt_entry = nil,    ---@type function
    -- session entries
    s_entries = { pkt = {} }
}

-- link list boxes
---@param pkt_list graphics_element pocket list element
---@param pkt_entry function pocket entry constructor
function pgi.link_elements(pkt_list, pkt_entry)
    data.pkt_list = pkt_list
    data.pkt_entry = pkt_entry
end

-- unlink all fields, disabling the PGI
function pgi.unlink()
    data.pkt_list = nil
    data.pkt_entry = nil
end

-- add a PKT entry to the PKT list
---@param session_id integer pocket session
function pgi.create_pkt_entry(session_id)
    if data.pkt_list ~= nil and data.pkt_entry ~= nil then
        local success, result = pcall(data.pkt_entry, data.pkt_list, session_id)

        if success then
            data.s_entries.pkt[session_id] = result
        else
            log.error(util.c("PGI: failed to create PKT entry (", result, ")"), true)
        end
    end
end

-- delete a PKT entry from the PKT list
---@param session_id integer pocket session
function pgi.delete_pkt_entry(session_id)
    if data.s_entries.pkt[session_id] ~= nil then
        local success, result = pcall(data.s_entries.pkt[session_id].delete)
        data.s_entries.pkt[session_id] = nil

        if not success then
            log.error(util.c("PGI: failed to delete PKT entry (", result, ")"), true)
        end
    else
        log.debug(util.c("PGI: tried to delete unknown PKT entry ", session_id))
    end
end

return pgi

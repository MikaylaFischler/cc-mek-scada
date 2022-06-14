--
-- Graphics View Layout
--

local core = require("graphics.core")
local util = require("scada-common.util")

local displaybox = require("graphics.elements.displaybox")

local layout = {}

---@class stem
---@field element graphics_element
---@field children table

function layout.create(window, default_fg_bg)
    local self = {
        root = displaybox{window=window,fg_bg=default_fg_bg},
        tree = {}
    }

    -- recursive function to search layout tree for an element
    ---@param id string element ID to look for
    ---@param tree table tree to search in
    ---@return stem|nil
    local function lookup(id, tree)
        for key, stem in pairs(tree) do
            if key == id then
                return stem
            else
                stem = lookup(id, stem.children)
                if stem ~= nil then return stem end
            end
        end

        return nil
    end

    ---@class layout
    local public = {}

    -- insert a new element
    ---@param parent_id string|nil parent or nil for root
    ---@param id string element ID
    ---@param element graphics_element
    function public.insert_at(parent_id, id, element)
        if parent_id == nil then
            self.tree[id] = { element = element, children = {} }
        else
            local parent = lookup(parent_id, self.tree)
            if parent ~= nil then
                parent.children[id] = { element = element, children = {} }
            end
        end
    end

    -- get an element by ID
    ---@param id string element ID
    ---@return graphics_element|nil
    function public.get_element_by_id(id)
        local elem = lookup(id, self.tree)
---@diagnostic disable-next-line: need-check-nil
        return util.trinary(elem == nil, nil, elem.element)
    end

    -- get the root element
    ---@return graphics_element
    function public.get_root()
        return self.root
    end

    return public
end

return layout

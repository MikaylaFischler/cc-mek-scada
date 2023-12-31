--
-- I/O Control for Pocket Integration with Supervisor & Coordinator
--

local psil = require("scada-common.psil")

local types = require("scada-common.types")

local ALARM = types.ALARM

local iocontrol = {}

---@class pocket_ioctl
local io = {
    nav_root = nil, ---@type nav_tree_node
    ps = psil.create()
}

---@enum POCKET_LINK_STATE
local LINK_STATE = {
    UNLINKED = 0,
    SV_LINK_ONLY = 1,
    API_LINK_ONLY = 2,
    LINKED = 3
}

iocontrol.LINK_STATE = LINK_STATE

---@class nav_tree_node
---@field _p nav_tree_node|nil page's parent
---@field _c table page's children
---@field pane_elem graphics_element|nil multipane for this branch
---@field pane_id integer this page's ID in it's contained pane
---@field switcher function|nil function to switch this page's active multipane
---@field nav_to function function to navigate to this page
---@field tasks table tasks to run on this page

-- allocate the page navigation tree system<br>
-- navigation is not ready until init_nav has been called
function iocontrol.alloc_nav()
    local self = {
        root = { _p = nil, _c = {}, pane_id = 0, pane_elem = nil, nav_to = function () end, tasks = {} }, ---@type nav_tree_node
        cur_page = nil ---@type nav_tree_node
    }

    function self.root.switcher(pane_id)
        if self.root._c[pane_id] then self.root._c[pane_id].nav_to() end
    end

    -- find the pane this element belongs to
    ---@param parent nav_tree_node
    local function _find_pane(parent)
        if parent == nil then
            return nil
        elseif parent.pane_elem then
            return parent.pane_elem
        else
            return _find_pane(parent._p)
        end
    end

    self.cur_page = self.root

    ---@class pocket_nav
    io.nav = {}

    -- create a new page entry in the page navigation tree
    ---@param parent nav_tree_node? a parent page or nil to use the root
    ---@param pane_id integer the pane number for this page in it's parent's multipane
    ---@param pane graphics_element? this page's multipane, if it has children
    ---@return nav_tree_node new_page this new page
    function io.nav.new_page(parent, pane_id, pane)
        local page = { _p = parent or self.root, _c = {}, pane_id = pane_id, pane_elem = pane, tasks = {} }
        page._p._c[pane_id] = page

        function page.nav_to()
            local p_pane = _find_pane(page._p)
            if p_pane then p_pane.set_value(page.pane_id) end
            self.cur_page = page
        end

        if pane then
            function page.switcher() if page._c[pane_id] then page._c[pane_id].nav_to() end end
        end

        return page
    end

    -- get the currently active page
    function io.nav.get_current_page() return self.cur_page end

    -- attempt to navigate up the tree
    function io.nav.nav_up()
        local parent = self.cur_page._p
        -- if a parent is defined and this element is not root
        if parent then parent.nav_to() end
    end

    io.nav_root = self.root
end

-- complete initialization of navigation by providing the root muiltipane
---@param root_pane graphics_element navigation root multipane
---@param default_page integer? page to nagivate to if nav_up is called on a base node
function iocontrol.init_nav(root_pane, default_page)
    io.nav_root.pane_elem = root_pane

    ---@todo keep this?
    -- if default_page ~= nil then
    --     io.nav_root.nav_to = function() io.nav_root.switcher(default_page) end
    -- end

    return io.nav_root
end

-- initialize facility-independent components of pocket iocontrol
---@param comms pocket_comms
function iocontrol.init_core(comms)
    iocontrol.alloc_nav()

    ---@class pocket_ioctl_diag
    io.diag = {}

    -- alarm testing
    io.diag.tone_test = {
        test_1 = function (state) comms.diag__set_alarm_tone(1, state) end,
        test_2 = function (state) comms.diag__set_alarm_tone(2, state) end,
        test_3 = function (state) comms.diag__set_alarm_tone(3, state) end,
        test_4 = function (state) comms.diag__set_alarm_tone(4, state) end,
        test_5 = function (state) comms.diag__set_alarm_tone(5, state) end,
        test_6 = function (state) comms.diag__set_alarm_tone(6, state) end,
        test_7 = function (state) comms.diag__set_alarm_tone(7, state) end,
        test_8 = function (state) comms.diag__set_alarm_tone(8, state) end,
        stop_tones = function () comms.diag__set_alarm_tone(0, false) end,

        test_breach = function (state) comms.diag__set_alarm(ALARM.ContainmentBreach, state) end,
        test_rad = function (state) comms.diag__set_alarm(ALARM.ContainmentRadiation, state) end,
        test_lost = function (state) comms.diag__set_alarm(ALARM.ReactorLost, state) end,
        test_crit = function (state) comms.diag__set_alarm(ALARM.CriticalDamage, state) end,
        test_dmg = function (state) comms.diag__set_alarm(ALARM.ReactorDamage, state) end,
        test_overtemp = function (state) comms.diag__set_alarm(ALARM.ReactorOverTemp, state) end,
        test_hightemp = function (state) comms.diag__set_alarm(ALARM.ReactorHighTemp, state) end,
        test_wasteleak = function (state) comms.diag__set_alarm(ALARM.ReactorWasteLeak, state) end,
        test_highwaste = function (state) comms.diag__set_alarm(ALARM.ReactorHighWaste, state) end,
        test_rps = function (state) comms.diag__set_alarm(ALARM.RPSTransient, state) end,
        test_rcs = function (state) comms.diag__set_alarm(ALARM.RCSTransient, state) end,
        test_turbinet = function (state) comms.diag__set_alarm(ALARM.TurbineTrip, state) end,
        stop_alarms = function () comms.diag__set_alarm(0, false) end,

        get_tone_states = function () comms.diag__get_alarm_tones() end,

        ready_warn = nil,       ---@type graphics_element
        tone_buttons = {},
        alarm_buttons = {},
        tone_indicators = {}    -- indicators to update from supervisor tone states
    }
end

-- initialize facility-dependent components of pocket iocontrol
function iocontrol.init_fac() end

-- set network link state
---@param state POCKET_LINK_STATE
function iocontrol.report_link_state(state) io.ps.publish("link_state", state) end

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol

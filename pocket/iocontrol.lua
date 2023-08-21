--
-- I/O Control for Pocket Integration with Supervisor & Coordinator
--

local psil = require("scada-common.psil")

local types = require("scada-common.types")

local ALARM = types.ALARM

local iocontrol = {}

---@class pocket_ioctl
local io = {
    ps = psil.create()
}

---@enum POCKET_LINK_STATE
local LINK_STATE = {
    UNLINKED = 0,
    SV_LINK_ONLY = 1,
    API_LINK_ONLY = 2,
    LINKED = 3
}

---@enum NAV_PAGE
local NAV_PAGE = {
    HOME = 1,
    UNITS = 2,
    REACTORS = 3,
    BOILERS = 4,
    TURBINES = 5,
    DIAG = 6,
    D_ALARMS = 7
}

iocontrol.LINK_STATE = LINK_STATE
iocontrol.NAV_PAGE = NAV_PAGE

-- initialize facility-independent components of pocket iocontrol
---@param comms pocket_comms
function iocontrol.init_core(comms)
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

    ---@class pocket_nav
    io.nav = {
        page = NAV_PAGE.HOME,   ---@type NAV_PAGE
        sub_pages = { NAV_PAGE.HOME, NAV_PAGE.UNITS, NAV_PAGE.REACTORS, NAV_PAGE.BOILERS, NAV_PAGE.TURBINES, NAV_PAGE.DIAG },
        tasks = {}
    }

    -- add a task to be performed periodically while on a given page
    ---@param page NAV_PAGE page to add task to
    ---@param task function function to execute
    function io.nav.register_task(page, task)
        if io.nav.tasks[page] == nil then io.nav.tasks[page] = {} end
        table.insert(io.nav.tasks[page], task)
    end
end

-- initialize facility-dependent components of pocket iocontrol
function iocontrol.init_fac() end

-- set network link state
---@param state POCKET_LINK_STATE
function iocontrol.report_link_state(state) io.ps.publish("link_state", state) end

-- get the IO controller database
function iocontrol.get_db() return io end

return iocontrol

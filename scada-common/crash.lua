--
-- Crash Handler
--

---@diagnostic disable-next-line: undefined-global
local _is_pocket_env = pocket   -- luacheck: ignore pocket

local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local util  = require("scada-common.util")

local has_graphics, core   = pcall(require, "graphics.core")
local has_lockbox, lockbox = pcall(require, "lockbox")

---@class crash_handler
local crash = {}

local app = "unknown"
local ver = "v0.0.0"
local err = ""

-- set crash environment
---@param application string app name
---@param version string version
function crash.set_env(application, version)
    app = application
    ver = version
end

-- log environment versions
---@param log_msg function log function to use
local function log_versions(log_msg)
    log_msg(util.c("RUNTIME:          ", _HOST))
    log_msg(util.c("LUA VERSION:      ", _VERSION))
    log_msg(util.c("APPLICATION:      ", app))
    log_msg(util.c("FIRMWARE VERSION: ", ver))
    log_msg(util.c("COMMS VERSION:    ", comms.version))
    if has_graphics then log_msg(util.c("GRAPHICS VERSION: ", core.version)) end
    if has_lockbox  then log_msg(util.c("LOCKBOX VERSION:  ", lockbox.version)) end
end

-- render the standard computer crash screen
---@param exit function callback on exit button press
---@return DisplayBox display
local function draw_computer_crash(exit)
    local DisplayBox = require("graphics.elements.DisplayBox")
    local Div        = require("graphics.elements.Div")
    local Rectangle  = require("graphics.elements.Rectangle")
    local TextBox    = require("graphics.elements.TextBox")
    local PushButton = require("graphics.elements.controls.PushButton")

    local display = DisplayBox{window=term.current(),fg_bg=core.cpair(colors.white,colors.lightGray)}

    local warning = Div{parent=display,x=2,y=2}
    TextBox{parent=warning,x=7,text="\x90\n \x90\n  \x90\n   \x90\n    \x90",fg_bg=core.cpair(colors.yellow,colors.lightGray)}
    TextBox{parent=warning,x=5,y=1,text="\x9f ",width=2,fg_bg=core.cpair(colors.lightGray,colors.yellow)}
    TextBox{parent=warning,x=4,text="\x9f   ",width=4,fg_bg=core.cpair(colors.lightGray,colors.yellow)}
    TextBox{parent=warning,x=3,text="\x9f      ",width=6,fg_bg=core.cpair(colors.lightGray,colors.yellow)}
    TextBox{parent=warning,x=2,text="\x9f        ",width=8,fg_bg=core.cpair(colors.lightGray,colors.yellow)}
    TextBox{parent=warning,text="\x9f          ",width=10,fg_bg=core.cpair(colors.lightGray,colors.yellow)}
    TextBox{parent=warning,text="\x8f\x8f\x8f\x8f\x8f\x8f\x8f\x8f\x8f\x8f\x8f",width=11,fg_bg=core.cpair(colors.yellow,colors.lightGray)}
    TextBox{parent=warning,x=6,y=3,text=" \n \x83",width=1,fg_bg=core.cpair(colors.yellow,colors.white)}

    TextBox{parent=display,x=13,y=2,text="Critical Software Fault Encountered",alignment=core.ALIGN.CENTER,fg_bg=core.cpair(colors.yellow,colors._INHERIT)}
    TextBox{parent=display,x=15,y=4,text="Please consider reporting this on the cc-mek-scada Discord or GitHub.",width=36,alignment=core.ALIGN.CENTER}
    TextBox{parent=display,x=14,y=7,text="refer to the log file for more info",alignment=core.ALIGN.CENTER,fg_bg=core.cpair(colors.gray,colors._INHERIT)}

    local box = Rectangle{parent=display,x=2,y=9,width=display.get_width()-2,height=8,border=core.border(1,colors.gray,true),thin=true,fg_bg=core.cpair(colors.black,colors.white)}
    TextBox{parent=box,text=err}

    PushButton{parent=display,x=23,y=18,text=" Exit ",callback=exit,active_fg_bg=core.cpair(colors.white,colors.gray),fg_bg=core.cpair(colors.black,colors.red)}

    return display
end

-- render the pocket crash screen
---@param exit function callback on exit button press
---@return DisplayBox display
local function draw_pocket_crash(exit)
    local DisplayBox = require("graphics.elements.DisplayBox")
    local Div        = require("graphics.elements.Div")
    local Rectangle  = require("graphics.elements.Rectangle")
    local TextBox    = require("graphics.elements.TextBox")
    local PushButton = require("graphics.elements.controls.PushButton")

    local display = DisplayBox{window=term.current(),fg_bg=core.cpair(colors.white,colors.lightGray)}

    local warning = Div{parent=display,x=2,y=1}
    TextBox{parent=warning,x=4,y=1,text="\x90",width=1,fg_bg=core.cpair(colors.yellow,colors.lightGray)}
    TextBox{parent=warning,x=3,text="\x81 ",width=2,fg_bg=core.cpair(colors.lightGray,colors.yellow)}
    TextBox{parent=warning,x=5,y=2,text="\x94",width=1,fg_bg=core.cpair(colors.yellow,colors.lightGray)}
    TextBox{parent=warning,x=2,text="\x81   ",width=4,fg_bg=core.cpair(colors.lightGray,colors.yellow)}
    TextBox{parent=warning,x=6,y=3,text="\x94",width=1,fg_bg=core.cpair(colors.yellow,colors.lightGray)}
    TextBox{parent=warning,text="\x8e\x8f\x8f\x8e\x8f\x8f\x84",width=7,fg_bg=core.cpair(colors.yellow,colors.lightGray)}
    TextBox{parent=warning,x=4,y=2,text="\x90",width=1,fg_bg=core.cpair(colors.lightGray,colors.yellow)}
    TextBox{parent=warning,x=4,y=3,text="\x85",width=1,fg_bg=core.cpair(colors.lightGray,colors.yellow)}

    TextBox{parent=display,x=10,y=2,text=" Critical Software Fault",width=16,alignment=core.ALIGN.CENTER,fg_bg=core.cpair(colors.yellow,colors._INHERIT)}
    TextBox{parent=display,x=2,y=5,text="Consider reporting this on the cc-mek-scada Discord or GitHub.",width=36,alignment=core.ALIGN.CENTER}

    local box = Rectangle{parent=display,y=9,width=display.get_width(),height=8,fg_bg=core.cpair(colors.black,colors.white)}
    TextBox{parent=box,text=err}

    PushButton{parent=display,x=11,y=18,text=" Exit ",callback=exit,active_fg_bg=core.cpair(colors.white,colors.gray),fg_bg=core.cpair(colors.black,colors.red)}
    TextBox{parent=display,x=2,y=20,text="see logs for details",width=24,alignment=core.ALIGN.CENTER,fg_bg=core.cpair(colors.gray,colors._INHERIT)}

    return display
end

-- when running with debug logs, log the useful information that the crash handler knows
function crash.dbg_log_env() log_versions(log.debug) end

-- handle a crash error
---@param error string error message
function crash.handler(error)
    err = error
    log.info("=====> FATAL SOFTWARE FAULT <=====")
    log.fatal(error)
    log.info("----------------------------------")
    log_versions(log.info)
    log.info("----------------------------------")
    log.info(debug.traceback("--- begin debug trace ---", 1))
    log.info("--- end debug trace ---")
end

-- final error print on failed xpcall, app exits here
function crash.exit()
    local handled, run = false, true
    local display   ---@type DisplayBox

    -- special graphical crash screen
    if has_graphics then
        handled, display = pcall(util.trinary(_is_pocket_env, draw_pocket_crash, draw_computer_crash), function () run = false end)

        -- event loop
        while display and run do
            local event, param1, param2, param3 = util.pull_event()

            -- handle event
            if event == "mouse_click" or event == "mouse_up" or event == "double_click" then
                local mouse = core.events.new_mouse_event(event, param1, param2, param3)
                if mouse then display.handle_mouse(mouse) end
            elseif event == "terminate" then
                break
            end
        end

        display.delete()

        term.setCursorPos(1, 1)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        term.clear()
    end

    log.close()

    -- default text failure message
    if not handled then
        util.println("fatal error occured in main application:")
        error(err, 0)
    end
end

return crash

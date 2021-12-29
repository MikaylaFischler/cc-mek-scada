os.loadAPI("defs.lua")

local out, out_w, out_h
local output_full = false

-- initialize the logger to the given monitor
-- monitor: monitor to write to (in addition to calling print())
function init(monitor)
    out = monitor
    out_w, out_h = out.getSize()

    out.clear()
    out.setTextColor(colors.white)
    out.setBackgroundColor(colors.black)
    
    out.setCursorPos(1, 1)
    out.write("version " .. defs.CTRL_VERSION)
    out.setCursorPos(1, 2)
    out.write("system startup at " .. os.date("%Y/%m/%d %H:%M:%S"))

    print("server v" .. defs.CTRL_VERSION .. " started at " .. os.date("%Y/%m/%d %H:%M:%S"))
end

-- write a log message to the log screen and console
-- msg: message to write
-- color: (optional) color to print in, defaults to white
function write(msg, color)
    color = color or colors.white
    local _x, _y = out.getCursorPos()

    if output_full then
        out.scroll(1)
        out.setCursorPos(1, _y)
    else
        if _y == out_h then
            output_full = true
            out.scroll(1)
            out.setCursorPos(1, _y)
        else
            out.setCursorPos(1, _y + 1)
        end
    end

    -- output to screen
    out.setTextColor(colors.lightGray)
    out.write(os.date("[%H:%M:%S] "))
    out.setTextColor(color)
    out.write(msg)

    -- output to console
    print(os.date("[%H:%M:%S] ") .. msg)
end

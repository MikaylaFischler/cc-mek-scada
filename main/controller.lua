-- mekanism reactor controller
-- monitors and regulates mekanism reactors

os.loadAPI("reactor.lua")
os.loadAPI("defs.lua")
os.loadAPI("log.lua")
os.loadAPI("render.lua")
os.loadAPI("server.lua")
os.loadAPI("regulator.lua")

-- constants, aliases, properties
local header = "MEKANISM REACTOR CONTROLLER - v" .. defs.CTRL_VERSION
local monitor_0 = peripheral.wrap(defs.MONITOR_0)
local monitor_1 = peripheral.wrap(defs.MONITOR_1)
local monitor_2 = peripheral.wrap(defs.MONITOR_2)
local monitor_3 = peripheral.wrap(defs.MONITOR_3)

monitor_0.setBackgroundColor(colors.black)
monitor_0.setTextColor(colors.white)
monitor_0.clear()

monitor_1.setBackgroundColor(colors.black)
monitor_1.setTextColor(colors.white)
monitor_1.clear()

monitor_2.setBackgroundColor(colors.black)
monitor_2.setTextColor(colors.white)
monitor_2.clear()

log.init(monitor_3)

local main_w, main_h = monitor_0.getSize()
local view = window.create(monitor_0, 1, 1, main_w, main_h)
view.setBackgroundColor(colors.black)
view.clear()

local stat_w, stat_h = monitor_1.getSize()
local stat_view = window.create(monitor_1, 1, 1, stat_w, stat_h)
stat_view.setBackgroundColor(colors.black)
stat_view.clear()

local reactors = {
    reactor.create(1, view, stat_view, 62, 3, 63, 2), 
    reactor.create(2, view, stat_view, 42, 3, 43, 2), 
    reactor.create(3, view, stat_view, 22, 3, 23, 2),
    reactor.create(4, view, stat_view, 2,  3,  3, 2)
}
print("[debug] reactor tables created")

server.init(reactors)
print("[debug] modem server started")

regulator.init(reactors)
print("[debug] regulator started")

-- header
view.setBackgroundColor(colors.white)
view.setTextColor(colors.black)
view.setCursorPos(1, 1)
local header_pad_x = (main_w - string.len(header)) / 2
view.write(string.rep(" ", header_pad_x) .. header .. string.rep(" ", header_pad_x))

-- inital draw of each reactor
for key, rctr in pairs(reactors) do
    render.draw_reactor_system(rctr)
    render.draw_reactor_status(rctr)
end

-- inital draw of clock
monitor_2.setTextScale(2)
monitor_2.setCursorPos(1, 1)
monitor_2.write(os.date("%Y/%m/%d  %H:%M:%S"))

local clock_update_timer = os.startTimer(1)

while true do
    event, param1, param2, param3, param4, param5 = os.pullEvent()

    if event == "redstone" then
        -- redstone state change
        regulator.handle_redstone()
    elseif event == "modem_message" then
        -- received signal router packet
        packet = { 
            side = param1, 
            sender = param2, 
            reply = param3, 
            message = param4, 
            distance = param5 
        }

        server.handle_message(packet, reactors)
    elseif event == "monitor_touch" then
        if param1 == "monitor_5" then
            local tap_x = param2
            local tap_y = param3

            for key, rctr in pairs(reactors) do
                if tap_x >= rctr.render.stat_x and tap_x <= (rctr.render.stat_x + 15) then
                    local old_val = rctr.waste_production
                    -- width in range
                    if tap_y == (rctr.render.stat_y + 12) then
                        rctr.waste_production = "plutonium"
                    elseif tap_y == (rctr.render.stat_y + 14) then
                        rctr.waste_production = "polonium"
                    elseif tap_y == (rctr.render.stat_y + 16) then
                        rctr.waste_production = "antimatter"
                    end

                    -- notify reactor of changes
                    if old_val ~= rctr.waste_production then
                        server.send(rctr.id, rctr.waste_production)
                    end
                end
            end
        end
    elseif event == "timer" then
        -- update the clock about every second
        monitor_2.setCursorPos(1, 1)
        monitor_2.write(os.date("%Y/%m/%d  %H:%M:%S"))
        clock_update_timer = os.startTimer(1)

        -- send keep-alive
        server.broadcast(1)
    end

    -- update reactor display
    for key, rctr in pairs(reactors) do
        render.draw_reactor_system(rctr)
        render.draw_reactor_status(rctr)
    end

    -- update system status monitor
    render.update_system_monitor(monitor_2, regulator.is_scrammed(), reactors)
end

-- reactor signal router
-- transmits status information and controls enable state

-- bundeled redstone key
-- top:
-- black   (in): insufficent fuel
-- brown   (in): excess waste
-- orange  (in): overheat
-- red     (in): damage critical
-- right:
-- cyan    (out): plutonium/plutonium pellet pipe
-- green   (out): polonium pipe
-- magenta (out): polonium pellet pipe
-- purple  (out): antimatter pipe
-- white   (out): reactor enable

-- constants
REACTOR_ID = 1
DEST_PORT = 1000

local state = {
    id = REACTOR_ID,
    run = false,
    no_fuel = false,
    full_waste = false,
    high_temp = false,
    damage_crit = false
}

local waste_production = "antimatter"

local listen_port = 1000 + REACTOR_ID
local modem = peripheral.wrap("left")

print("Reactor Signal Router v1.0")
print("Configured for Reactor #" .. REACTOR_ID)

if not modem.isOpen(listen_port) then
    modem.open(listen_port)
end

-- greeting
modem.transmit(DEST_PORT, listen_port, REACTOR_ID)

-- queue event to read initial state and make sure reactor starts off
os.queueEvent("redstone")
rs.setBundledOutput("right", colors.white)
rs.setBundledOutput("right", 0)
re_eval_output = true

local connection_timeout = os.startTimer(3)

-- event loop
while true do
    local event, param1, param2, param3, param4, param5 = os.pullEvent()

    if event == "redstone" then
        -- redstone state change
        input = rs.getBundledInput("top")

        if state.no_fuel ~= colors.test(input, colors.black) then
            state.no_fuel = colors.test(input, colors.black)
            if state.no_fuel then
                print("insufficient fuel")
            end
        end

        if state.full_waste ~= colors.test(input, colors.brown) then
            state.full_waste = colors.test(input, colors.brown)
            if state.full_waste then
                print("waste tank full")
            end
        end

        if state.high_temp ~= colors.test(input, colors.orange) then
            state.high_temp = colors.test(input, colors.orange)
            if state.high_temp then
                print("high temperature")
            end
        end

        if state.damage_crit ~= colors.test(input, colors.red) then
            state.damage_crit = colors.test(input, colors.red)
            if state.damage_crit then
                print("damage critical")
            end
        end
    elseif event == "modem_message" then
        -- got data, reset timer
        if connection_timeout ~= nil then
            os.cancelTimer(connection_timeout)
        end
        connection_timeout = os.startTimer(3)

        if type(param4) == "number" and param4 == 0 then
            print("[info] controller server startup detected")
            modem.transmit(DEST_PORT, listen_port, REACTOR_ID)
        elseif type(param4) == "number" and param4 == 1 then
            -- keep-alive, do nothing, just had to reset timer
        elseif type(param4) == "boolean" then
            state.run = param4

            if state.run then
                print("[alert] reactor enabled")
            else
                print("[alert] reactor disabled")
            end

            re_eval_output = true
        elseif type(param4) == "string" then
            if param4 == "plutonium" then
                print("[alert] switching to plutonium production")
                waste_production = param4
                re_eval_output = true
            elseif param4 == "polonium" then
                print("[alert] switching to polonium production")
                waste_production = param4
                re_eval_output = true
            elseif param4 == "antimatter" then
                print("[alert] switching to antimatter production")
                waste_production = param4
                re_eval_output = true
            end
        else
            print("[error] got unknown packet (" .. param4 .. ")")
        end
    elseif event == "timer" and param1 == connection_timeout then
        -- haven't heard from server in 3 seconds? shutdown
        -- timer won't be restarted until next packet, so no need to do anything with it
        print("[alert] server timeout, reactor disabled")
        state.run = false
        re_eval_output = true
    end

    -- check for control state changes
    if re_eval_output then
        re_eval_output = false

        local run_color = 0
        if state.run then
            run_color = colors.white
        end

        -- values are swapped, as on disables and off enables
        local waste_color
        if waste_production == "plutonium" then
            waste_color = colors.green
        elseif waste_production == "polonium" then
            waste_color = colors.cyan + colors.purple
        else
            -- antimatter (default)
            waste_color = colors.cyan + colors.magenta
        end

        rs.setBundledOutput("right", run_color + waste_color)
    end
    
    modem.transmit(DEST_PORT, listen_port, state)
end

os.loadAPI("defs.lua")
os.loadAPI("log.lua")
os.loadAPI("regulator.lua")

local modem
local reactors

-- initalize the listener running on the wireless modem
-- _reactors: reactor table
function init(_reactors)
    modem = peripheral.wrap("top")
    reactors = _reactors

    -- open listening port
    if not modem.isOpen(defs.LISTEN_PORT) then
        modem.open(defs.LISTEN_PORT)
    end

    -- send out a greeting to solicit responses for clients that are already running
    broadcast(0, reactors)
end

-- handle an incoming message from the modem
-- packet: table containing message fields
function handle_message(packet)
    if type(packet.message) == "number" then
        -- this is a greeting
        log.write("reactor " .. packet.message .. " connected", colors.green)

        -- send current control command
        for key, rctr in pairs(reactors) do
            if rctr.id == packet.message then
                send(rctr.id, rctr.control_state)
                break
            end
        end
    else
        -- got reactor status
        local eval_safety = false

        for key, value in pairs(reactors) do
            if value.id == packet.message.id then
                local tag = "RCT-" .. value.id .. ": "

                if value.state.run ~= packet.message.run then
                    value.state.run = packet.message.run
                    if value.state.run then
                        eval_safety = true
                        log.write(tag .. "running", colors.green)
                    end
                end

                if value.state.no_fuel ~= packet.message.no_fuel then
                    value.state.no_fuel = packet.message.no_fuel
                    if value.state.no_fuel then
                        eval_safety = true
                        log.write(tag .. "insufficient fuel", colors.gray)
                    end
                end

                if value.state.full_waste ~= packet.message.full_waste then
                    value.state.full_waste = packet.message.full_waste
                    if value.state.full_waste then
                        eval_safety = true
                        log.write(tag .. "waste tank full", colors.brown)
                    end
                end

                if value.state.high_temp ~= packet.message.high_temp then
                    value.state.high_temp = packet.message.high_temp
                    if value.state.high_temp then
                        eval_safety = true
                        log.write(tag .. "high temperature", colors.orange)
                    end
                end

                if value.state.damage_crit ~= packet.message.damage_crit then
                    value.state.damage_crit = packet.message.damage_crit
                    if value.state.damage_crit then
                        eval_safety = true
                        log.write(tag .. "critical damage", colors.red)
                    end
                end

                break
            end
        end

        -- check to ensure safe operation
        if eval_safety then
            regulator.enforce_safeties()
        end
    end
end

-- send a message to a given reactor
-- dest: reactor ID
-- message: true or false for enable control or another value for other functionality, like 0 for greeting
function send(dest, message)
    modem.transmit(dest + defs.LISTEN_PORT, defs.LISTEN_PORT, message)
end

-- broadcast a message to all reactors
-- message: true or false for enable control or another value for other functionality, like 0 for greeting
function broadcast(message)
    for key, value in pairs(reactors) do
        modem.transmit(value.id + defs.LISTEN_PORT, defs.LISTEN_PORT, message)
    end
end

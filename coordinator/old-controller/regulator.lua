os.loadAPI("defs.lua")
os.loadAPI("log.lua")
os.loadAPI("server.lua")

local reactors
local scrammed
local auto_scram

-- initialize the system regulator which provides safety measures, SCRAM functionality, and handles redstone
-- _reactors: reactor table
function init(_reactors)
    reactors = _reactors
    scrammed = false
    auto_scram = false

    -- scram all reactors
    server.broadcast(false, reactors)

    -- check initial states
    regulator.handle_redstone()
end

-- check if the system is scrammed
function is_scrammed()
    return scrammed
end

-- handle redstone state changes
function handle_redstone()
    -- check scram button
    if not rs.getInput("right") then
        if not scrammed then
            log.write("user SCRAM", colors.red)
            scram()
        end

        -- toggling scram will release auto scram state
        auto_scram = false
    else
        scrammed = false
    end

    -- check individual control buttons
    local input = rs.getBundledInput("left")
    for key, rctr in pairs(reactors) do
        if colors.test(input, defs.BUNDLE_DEF[key]) ~= rctr.control_state then
            -- state changed
            rctr.control_state = colors.test(input, defs.BUNDLE_DEF[key])
            if not scrammed then
                local safe = true

                if rctr.control_state then
                    safe = check_enable_safety(reactors[key])
                    if safe then
                        log.write("reactor " .. reactors[key].id .. " enabled", colors.lime)
                    end
                else
                    log.write("reactor " .. reactors[key].id .. " disabled", colors.cyan)
                end

                -- start/stop reactor
                if safe then
                    server.send(rctr.id, rctr.control_state)
                end
            elseif colors.test(input, defs.BUNDLE_DEF[key]) then
                log.write("scrammed: state locked off", colors.yellow)
            end
        end
    end
end

-- make sure enabling the provided reactor is safe
-- reactor: reactor to check
function check_enable_safety(reactor)
    if reactor.state.no_fuel or reactor.state.full_waste or reactor.state.high_temp or reactor.state.damage_crit then
        log.write("RCT-" .. reactor.id .. ": unsafe enable denied", colors.yellow)
        return false
    else
        return true
    end
end

-- make sure no running reactors are in a bad state
function enforce_safeties()
    for key, reactor in pairs(reactors) do
        local overridden = false
        local state = reactor.state

        -- check for problems
        if state.damage_crit and state.run then
            reactor.control_state = false
            log.write("RCT-" .. reactor.id .. ": shut down (damage)", colors.yellow)

            -- scram all, so ignore setting overridden
            log.write("auto SCRAM all reactors", colors.red)
            auto_scram = true
            scram()
        elseif state.high_temp and state.run then
            reactor.control_state = false
            overridden = true
            log.write("RCT-" .. reactor.id .. ": shut down (temp)", colors.yellow)
        elseif state.full_waste and state.run then
            reactor.control_state = false
            overridden = true
            log.write("RCT-" .. reactor.id .. ": shut down (waste)", colors.yellow)
        elseif state.no_fuel and state.run then
            reactor.control_state = false
            overridden = true
            log.write("RCT-" .. reactor.id .. ": shut down (fuel)", colors.yellow)
        end

        if overridden then
            server.send(reactor.id, false)
        end
    end
end

-- shut down all reactors and prevent enabling them until the scram button is toggled/released
function scram()
    scrammed = true
    server.broadcast(false, reactors)

    for key, rctr in pairs(reactors) do
        if rctr.control_state then
            log.write("reactor " .. reactors[key].id .. " disabled", colors.cyan)
        end
    end
end

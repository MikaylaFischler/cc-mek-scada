os.loadAPI("defs.lua")

-- draw pipes between machines
-- win: window to render in
-- x: starting x coord
-- y: starting y coord
-- spacing: spacing between the pipes
-- color_out: output pipe contents color
-- color_ret: return pipe contents color
-- tick: tick the pipes for an animation
function draw_pipe(win, x, y, spacing, color_out, color_ret, tick)
    local _color
    local _off
    tick = tick or 0

    for i = 0, 4, 1
    do
        _off = (i + tick) % 2 == 0 or (tick == 1 and i == 0) or (tick == 3 and i == 4)

        if _off then
            _color = colors.lightGray
        else
            _color = color_out
        end

        win.setBackgroundColor(_color)
        win.setCursorPos(x, y + i)
        win.write(" ")

        if not _off then
            _color = color_ret
        end

        win.setBackgroundColor(_color)
        win.setCursorPos(x + spacing, y + i)
        win.write(" ")
    end
end

-- draw a reactor view consisting of the reactor, boiler, turbine, and pipes
-- data: reactor table
function draw_reactor_system(data)
    local win = data.render.win_main
    local win_w, win_h = win.getSize()

    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.black)
    win.clear()
    win.setCursorPos(1, 1)

    -- draw header --

    local header = "REACTOR  " .. data.id
    local header_pad_x = (win_w - string.len(header) - 2) / 2
    local header_color
    if data.state.no_fuel then
        if data.state.run then
            header_color = colors.purple
        else
            header_color = colors.brown
        end
    elseif data.state.full_waste then
        header_color = colors.yellow
    elseif data.state.high_temp then
        header_color = colors.orange
    elseif data.state.damage_crit then
        header_color = colors.red
    elseif data.state.run then
        header_color = colors.green
    else
        header_color = colors.lightGray
    end

    local running = data.state.run and not data.state.no_fuel

    win.write(" ")
    win.setBackgroundColor(header_color)
    win.write(string.rep(" ", win_w - 2))
    win.setBackgroundColor(colors.black)
    win.write(" ")
    win.setCursorPos(1, 2)
    win.write(" ")
    win.setBackgroundColor(header_color)
    win.write(string.rep(" ", header_pad_x) .. header .. string.rep(" ", header_pad_x))
    win.setBackgroundColor(colors.black)
    win.write(" ")

    -- create strings for use in blit
    local line_text = string.rep(" ", 14)
    local line_text_color = string.rep("0", 14)

    -- draw components --

    -- draw reactor
    local rod = "88"
    if data.state.high_temp then
        rod = "11"
    elseif running then
        rod = "99"
    end

    win.setCursorPos(4, 4)
    win.setBackgroundColor(colors.gray)
    win.write(line_text)
    win.setCursorPos(4, 5)
    win.blit(line_text, line_text_color, "77" .. rod .. "77" .. rod .. "77" .. rod .. "77")
    win.setCursorPos(4, 6)
    win.blit(line_text, line_text_color, "7777" .. rod .. "77" .. rod .. "7777")
    win.setCursorPos(4, 7)
    win.blit(line_text, line_text_color, "77" .. rod .. "77" .. rod .. "77" .. rod .. "77")
    win.setCursorPos(4, 8)
    win.blit(line_text, line_text_color, "7777" .. rod .. "77" .. rod .. "7777")
    win.setCursorPos(4, 9)
    win.blit(line_text, line_text_color, "77" .. rod .. "77" .. rod .. "77" .. rod .. "77")
    win.setCursorPos(4, 10)
    win.write(line_text)

    -- boiler
    local steam = "ffffffffff"
    if running then
        steam = "0000000000"
    end

    win.setCursorPos(4, 16)
    win.setBackgroundColor(colors.gray)
    win.write(line_text)
    win.setCursorPos(4, 17)
    win.blit(line_text, line_text_color, "77" .. steam .. "77")
    win.setCursorPos(4, 18)
    win.blit(line_text, line_text_color, "77" .. steam .. "77")
    win.setCursorPos(4, 19)
    win.blit(line_text, line_text_color, "77888888888877")
    win.setCursorPos(4, 20)
    win.blit(line_text, line_text_color, "77bbbbbbbbbb77")
    win.setCursorPos(4, 21)
    win.blit(line_text, line_text_color, "77bbbbbbbbbb77")
    win.setCursorPos(4, 22)
    win.blit(line_text, line_text_color, "77bbbbbbbbbb77")
    win.setCursorPos(4, 23)
    win.setBackgroundColor(colors.gray)
    win.write(line_text)

    -- turbine
    win.setCursorPos(4, 29)
    win.setBackgroundColor(colors.gray)
    win.write(line_text)
    win.setCursorPos(4, 30)
    if running then
        win.blit(line_text, line_text_color, "77000000000077")
    else
        win.blit(line_text, line_text_color, "77ffffffffff77")
    end
    win.setCursorPos(4, 31)
    if running then
        win.blit(line_text, line_text_color, "77008000080077")
    else
        win.blit(line_text, line_text_color, "77ff8ffff8ff77")
    end
    win.setCursorPos(4, 32)
    if running then
        win.blit(line_text, line_text_color, "77000800800077")
    else
        win.blit(line_text, line_text_color, "77fff8ff8fff77")
    end
    win.setCursorPos(4, 33)
    if running then
        win.blit(line_text, line_text_color, "77000088000077")
    else
        win.blit(line_text, line_text_color, "77ffff88ffff77")
    end
    win.setCursorPos(4, 34)
    if running then
        win.blit(line_text, line_text_color, "77000800800077")
    else
        win.blit(line_text, line_text_color, "77fff8ff8fff77")
    end
    win.setCursorPos(4, 35)
    if running then
        win.blit(line_text, line_text_color, "77008000080077")
    else
        win.blit(line_text, line_text_color, "77ff8ffff8ff77")
    end
    win.setCursorPos(4, 36)
    if running then
        win.blit(line_text, line_text_color, "77000000000077")
    else
        win.blit(line_text, line_text_color, "77ffffffffff77")
    end
    win.setCursorPos(4, 37)
    win.setBackgroundColor(colors.gray)
    win.write(line_text)

    -- draw reactor coolant pipes
    draw_pipe(win, 7, 11, 6, colors.orange, colors.lightBlue)

    -- draw turbine pipes
    draw_pipe(win, 7, 24, 6, colors.white, colors.blue)
end

-- draw the reactor statuses on the status screen
-- data: reactor table
function draw_reactor_status(data)
    local win = data.render.win_stat

    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.white)
    win.clear()

    -- show control state
    win.setCursorPos(1, 1)
    if data.control_state then
        win.blit(" +  ENABLED", "00000000000", "dddffffffff")
    else
        win.blit(" -  DISABLED", "000000000000", "eeefffffffff")
    end

    -- show run state
    win.setCursorPos(1, 2)
    if data.state.run then
        win.blit(" +  RUNNING", "00000000000", "dddffffffff")
    else
        win.blit(" -  STOPPED", "00000000000", "888ffffffff")
    end

    -- show fuel state
    win.setCursorPos(1, 4)
    if data.state.no_fuel then
        win.blit(" -  NO FUEL", "00000000000", "eeeffffffff")
    else
        win.blit(" +  FUEL OK", "00000000000", "999ffffffff")
    end

    -- show waste state
    win.setCursorPos(1, 5)
    if data.state.full_waste then
        win.blit(" -  WASTE FULL", "00000000000000", "eeefffffffffff")
    else
        win.blit(" +  WASTE OK", "000000000000", "999fffffffff")
    end

    -- show high temp state
    win.setCursorPos(1, 6)
    if data.state.high_temp then
        win.blit(" -  HIGH TEMP", "0000000000000", "eeeffffffffff")
    else
        win.blit(" +  TEMP OK", "00000000000", "999ffffffff")
    end

    -- show damage state
    win.setCursorPos(1, 7)
    if data.state.damage_crit then
        win.blit(" -  CRITICAL DAMAGE", "0000000000000000000", "eeeffffffffffffffff")
    else
        win.blit(" +  CASING INTACT", "00000000000000000", "999ffffffffffffff")
    end

    -- waste processing options --
    win.setTextColor(colors.black)
    win.setBackgroundColor(colors.white)

    win.setCursorPos(1, 10)
    win.write("                ")
    win.setCursorPos(1, 11)
    win.write("  WASTE OUTPUT  ")

    win.setCursorPos(1, 13)
    win.setBackgroundColor(colors.cyan)
    if data.waste_production == "plutonium" then
        win.write(" > plutonium    ")
    else
        win.write("   plutonium    ")
    end

    win.setCursorPos(1, 15)
    win.setBackgroundColor(colors.green)
    if data.waste_production == "polonium" then
        win.write(" > polonium     ")
    else
        win.write("   polonium     ")
    end

    win.setCursorPos(1, 17)
    win.setBackgroundColor(colors.purple)
    if data.waste_production == "antimatter" then
        win.write(" > antimatter   ")
    else
        win.write("   antimatter   ")
    end
end

-- update the system monitor screen
-- mon: monitor to update
-- is_scrammed: 
function update_system_monitor(mon, is_scrammed, reactors)
    if is_scrammed then
        -- display scram banner
        mon.setTextColor(colors.white)
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(1, 2)
        mon.clearLine()
        mon.setBackgroundColor(colors.red)
        mon.setCursorPos(1, 3)
        mon.write("                     ")
        mon.setCursorPos(1, 4)
        mon.write("        SCRAM        ")
        mon.setCursorPos(1, 5)
        mon.write("                     ")
        mon.setBackgroundColor(colors.black)
        mon.setCursorPos(1, 6)
        mon.clearLine()
        mon.setTextColor(colors.white)
    else
        -- clear where scram banner would be
        mon.setCursorPos(1, 3)
        mon.clearLine()
        mon.setCursorPos(1, 4)
        mon.clearLine()
        mon.setCursorPos(1, 5)
        mon.clearLine()

        -- show production statistics--

        local mrf_t = 0
        local mb_t = 0
        local plutonium = 0
        local polonium = 0
        local spent_waste = 0
        local antimatter = 0

        -- determine production values
        for key, rctr in pairs(reactors) do
            if rctr.state.run then
                mrf_t = mrf_t + defs.TURBINE_MRF_T
                mb_t = mb_t + defs.REACTOR_MB_T

                if rctr.waste_production == "plutonium" then
                    plutonium = plutonium + (defs.REACTOR_MB_T * defs.PLUTONIUM_PER_WASTE)
                    spent_waste = spent_waste + (defs.REACTOR_MB_T * defs.PLUTONIUM_PER_WASTE * defs.SPENT_PER_BYPRODUCT)
                elseif rctr.waste_production == "polonium" then
                    polonium = polonium + (defs.REACTOR_MB_T * defs.POLONIUM_PER_WASTE)
                    spent_waste = spent_waste + (defs.REACTOR_MB_T * defs.POLONIUM_PER_WASTE * defs.SPENT_PER_BYPRODUCT)
                elseif rctr.waste_production == "antimatter" then
                    antimatter = antimatter + (defs.REACTOR_MB_T * defs.POLONIUM_PER_WASTE * defs.ANTIMATTER_PER_POLONIUM)
                end
            end
        end

        -- draw stats
        mon.setTextColor(colors.lightGray)
        mon.setCursorPos(1, 2)
        mon.clearLine()
        mon.write("ENERGY: " .. string.format("%0.2f", mrf_t) .. " MRF/t")
        -- mon.setCursorPos(1, 3)
        -- mon.clearLine()
        -- mon.write("FUEL: " .. mb_t .. " mB/t")
        mon.setCursorPos(1, 3)
        mon.clearLine()
        mon.write("Pu:     " .. string.format("%0.2f", plutonium) .. " mB/t")
        mon.setCursorPos(1, 4)
        mon.clearLine()
        mon.write("Po:     " .. string.format("%0.2f", polonium) .. " mB/t")
        mon.setCursorPos(1, 5)
        mon.clearLine()
        mon.write("SPENT:  " .. string.format("%0.2f", spent_waste) .. " mB/t")
        mon.setCursorPos(1, 6)
        mon.clearLine()
        mon.write("ANTI-M: " .. string.format("%0.2f", antimatter * 1000) .. " uB/t")
        mon.setTextColor(colors.white)
    end
end

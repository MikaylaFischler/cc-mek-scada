-- create a new reactor 'object'
-- reactor_id: the ID for this reactor
-- main_view: the parent window/monitor for the main display (components)
-- status_view: the parent window/monitor for the status display
-- main_x: where to create the main window, x coordinate
-- main_y: where to create the main window, y coordinate
-- status_x: where to create the status window, x coordinate
-- status_y: where to create the status window, y coordinate
function create(reactor_id, main_view, status_view, main_x, main_y, status_x, status_y)
    return {
        id = reactor_id,
        render = {
            win_main = window.create(main_view, main_x, main_y, 20, 60, true),
            win_stat = window.create(status_view, status_x, status_y, 20, 20, true),
            stat_x = status_x,
            stat_y = status_y 
        },
        control_state = false,
        waste_production = "antimatter", -- "plutonium", "polonium", "antimatter"
        state = {
            run = false,
            no_fuel = false,
            full_waste = false,
            high_temp = false,
            damage_crit = false
        }
    }
end

local log         = require("scada-common.log")
local mqueue      = require("scada-common.mqueue")
local ppm         = require("scada-common.ppm")
local tcd         = require("scada-common.tcd")
local util        = require("scada-common.util")

local backplane   = require("coordinator.backplane")
local coordinator = require("coordinator.coordinator")
local iocontrol   = require("coordinator.iocontrol")
local process     = require("coordinator.process")
local renderer    = require("coordinator.renderer")
local sounder     = require("coordinator.sounder")

local apisessions = require("coordinator.session.apisessions")

local core        = require("graphics.core")

local log_render = coordinator.log_render
local log_sys    = coordinator.log_sys
local log_comms  = coordinator.log_comms

local threads = {}

local MAIN_CLOCK   = 0.5 -- 2Hz,   10 ticks
local RENDER_SLEEP = 100 -- 100ms, 2 ticks

-- main thread
---@nodiscard
---@param smem crd_shared_memory
function threads.thread__main(smem)
    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        iocontrol.fp_rt_status("main", true)
        log.debug("OS: main thread start")

        local loop_clock = util.new_clock(MAIN_CLOCK)

        -- start clock
        loop_clock.start()

        log_sys("system started successfully")

        -- load in from shared memory
        local crd_state       = smem.crd_state
        local coord_comms     = smem.crd_sys.coord_comms
        local conn_watchdog   = smem.crd_sys.conn_watchdog

        local MQ__RENDER_CMD  = smem.q_types.MQ__RENDER_CMD
        local MQ__RENDER_DATA = smem.q_types.MQ__RENDER_DATA

        -- event loop
        while true do
            local event, param1, param2, param3, param4, param5 = util.pull_event()

            -- handle event
            if event == "peripheral_detach" then
                local type, device = ppm.handle_unmount(param1)
                if type ~= nil and device ~= nil then
                    backplane.detach(type, device, param1)
                end
            elseif event == "peripheral" then
                local type, device = ppm.mount(param1)
                if type ~= nil and device ~= nil then
                    backplane.attach(type, device, param1)
                end
            elseif event == "monitor_resize" then
                smem.q.mq_render.push_data(MQ__RENDER_DATA.MON_RESIZE, param1)
            elseif event == "timer" then
                if loop_clock.is_clock(param1) then
                    -- main loop tick

                    -- toggle heartbeat
                    iocontrol.heartbeat()

                    -- periodic hardware tasks
                    backplane.periodic()

                    -- maintain connection
                    local ok, start_ui = coord_comms.manage_link()
                    if not ok then
                        crd_state.link_fail = true
                        crd_state.shutdown = true
                        log_sys("supervisor connection failed, shutting down...")
                        log.fatal("failed to connect to supervisor")
                        break
                    elseif start_ui then
                        log_sys("supervisor connected, dispatching main UI start")
                        smem.q.mq_render.push_command(MQ__RENDER_CMD.START_MAIN_UI)
                    end

                    -- iterate sessions and free any closed ones
                    apisessions.iterate_all()
                    apisessions.free_all_closed()

                    -- clear timed out process commands
                    process.clear_timed_out()

                    if renderer.ui_ready() then
                        -- update clock used on main and flow monitors
                        iocontrol.get_db().facility.ps.publish("date_time", os.date(smem.date_format))
                    end

                    -- start next clock timer
                    loop_clock.start()
                elseif conn_watchdog.is_timer(param1) then
                    -- supervisor watchdog timeout
                    log_comms("supervisor server timeout")

                    -- close main UI, connection, and stop sounder
                    smem.q.mq_render.push_command(MQ__RENDER_CMD.CLOSE_MAIN_UI)
                    coord_comms.close()
                    sounder.stop()
                else
                    -- a non-clock/main watchdog timer event

                    -- check API watchdogs
                    apisessions.check_all_watchdogs(param1)

                    -- notify timer callback dispatcher
                    tcd.handle(param1)
                end
            elseif event == "modem_message" then
                -- got a packet
                local packet = coord_comms.parse_packet(param1, param2, param3, param4, param5)

                -- handle then check if it was a disconnect
                if coord_comms.handle_packet(packet) then
                    log_comms("supervisor closed connection")

                    -- close main UI, connection, and stop sounder
                    smem.q.mq_render.push_command(MQ__RENDER_CMD.CLOSE_MAIN_UI)
                    coord_comms.close()
                    sounder.stop()
                end
            elseif event == "monitor_touch" or event == "mouse_click" or event == "mouse_up" or
                   event == "mouse_drag" or event == "mouse_scroll" or event == "double_click" then
                -- handle a mouse event
                renderer.handle_mouse(core.events.new_mouse_event(event, param1, param2, param3))
            elseif event == "speaker_audio_empty" then
                -- handle speaker buffer emptied
                sounder.continue()
            end

            -- check for termination request or UI crash
            if event == "terminate" or ppm.should_terminate() then
                crd_state.shutdown = true
                log.info("OS: terminate requested, main thread exiting")
            elseif not crd_state.ui_ok then
                crd_state.shutdown = true
                log.info("OS: terminating due to fatal UI error")
            end

            if crd_state.shutdown then
                -- handle closing supervisor connection
                coord_comms.manage_link(true)

                if coord_comms.is_linked() then
                    log_comms("closing supervisor connection...")
                else crd_state.link_fail = true end

                coord_comms.close()
                log_comms("supervisor connection closed")

                -- handle API sessions
                log_comms("closing api sessions...")
                apisessions.close_all()
                log_comms("api sessions closed")
                break
            end
        end
    end

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local crd_state = smem.crd_state

        while not crd_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(util.strval(result))
            end

            iocontrol.fp_rt_status("main", false)

            -- if status is true, then we are probably exiting, so this won't matter
            -- this thread cannot be slept because it will miss events (namely "terminate")
            if not crd_state.shutdown then
                log.info("OS: main thread restarting now...")
            end
        end
    end

    return public
end

-- coordinator renderer thread, tasked with long duration draws
---@nodiscard
---@param smem crd_shared_memory
function threads.thread__render(smem)
    ---@class parallel_thread
    local public = {}

    -- execute thread
    function public.exec()
        iocontrol.fp_rt_status("render", true)
        log.debug("OS: render thread start")

        -- load in from shared memory
        local crd_state       = smem.crd_state
        local render_queue    = smem.q.mq_render

        local MQ__RENDER_CMD  = smem.q_types.MQ__RENDER_CMD
        local MQ__RENDER_DATA = smem.q_types.MQ__RENDER_DATA

        local last_update = util.time()

        -- thread loop
        while true do
            -- check for messages in the message queue
            while render_queue.ready() and not crd_state.shutdown do
                local msg = render_queue.pop()

                if msg ~= nil then
                    if msg.qtype == mqueue.TYPE.COMMAND then
                        -- received a command
                        if msg.message == MQ__RENDER_CMD.START_MAIN_UI then
                            -- stop the UI if it was already started
                            -- this may occur on a quick supervisor disconnect -> connect
                            if renderer.ui_ready() then
                                log_render("closing main UI before executing new request to start")
                                renderer.close_ui()
                            end

                            -- start up the main UI
                            log_render("starting main UI...")

                            local draw_start = util.time_ms()

                            local ui_message
                            crd_state.ui_ok, ui_message = renderer.try_start_ui()
                            if not crd_state.ui_ok then
                                log_render(util.c("main UI error: ", ui_message))
                                log.fatal(util.c("main GUI render failed with error ", ui_message))
                            else
                                log_render("main UI draw took " .. (util.time_ms() - draw_start) .. "ms")
                            end
                        elseif msg.message == MQ__RENDER_CMD.CLOSE_MAIN_UI then
                            -- close the main UI if it has been drawn
                            if renderer.ui_ready() then
                                log_render("closing main UI...")
                                renderer.close_ui()
                                log_render("main UI closed")
                            end
                        end
                    elseif msg.qtype == mqueue.TYPE.DATA then
                        -- received data
                        local cmd = msg.message ---@type queue_data

                        if cmd.key == MQ__RENDER_DATA.MON_CONNECT then
                            -- monitor connected
                            renderer.handle_reconnect(cmd.val)
                        elseif cmd.key == MQ__RENDER_DATA.MON_DISCONNECT then
                            -- monitor disconnected
                            renderer.handle_disconnect(cmd.val)
                        elseif cmd.key == MQ__RENDER_DATA.MON_RESIZE then
                            -- monitor resized
                            local is_used, is_ok = renderer.handle_resize(cmd.val)
                            if is_used then
                                log_sys(util.c("configured monitor ", cmd.val, " resized, ", util.trinary(is_ok, "display fits", "display does not fit")))
                            end
                        end
                    end
                end

                -- quick yield
                util.nop()
            end

            -- check for termination request
            if crd_state.shutdown then
                log.info("OS: render thread exiting")
                break
            end

            -- delay before next check
            last_update = util.adaptive_delay(RENDER_SLEEP, last_update)
        end
    end

    -- execute the thread in a protected mode, retrying it on return if not shutting down
    function public.p_exec()
        local crd_state = smem.crd_state

        while not crd_state.shutdown do
            local status, result = pcall(public.exec)
            if status == false then
                log.fatal(util.strval(result))
            end

            iocontrol.fp_rt_status("render", false)

            if not crd_state.shutdown then
                log.info("OS: render thread restarting in 5 seconds...")
                util.psleep(5)
            end
        end
    end

    return public
end

return threads

--
-- SCADA System Access on a Pocket Computer
--

---@diagnostic disable-next-line: lowercase-global
pocket = pocket or periphemu    -- luacheck: ignore pocket

local _is_pocket_env = pocket   -- luacheck: ignore pocket

require("/initenv").init_env()

local crash     = require("scada-common.crash")
local log       = require("scada-common.log")
local mqueue    = require("scada-common.mqueue")
local network   = require("scada-common.network")
local ppm       = require("scada-common.ppm")
local util      = require("scada-common.util")

local configure = require("pocket.configure")
local iocontrol = require("pocket.iocontrol")
local pocket    = require("pocket.pocket")
local renderer  = require("pocket.renderer")
local threads   = require("pocket.threads")

local POCKET_VERSION = "v0.13.5-beta"

local println = util.println
local println_ts = util.println_ts

-- check environment (allows Pocket or CraftOS-PC)
if not _is_pocket_env then
    println("You can only use this application on a pocket computer.")
    return
end

----------------------------------------
-- get configuration
----------------------------------------

if not pocket.load_config() then
    -- try to reconfigure (user action)
    local success, error = configure.configure(true)
    if success then
        if not pocket.load_config() then
            println("failed to load a valid configuration, please reconfigure")
            return
        end
    else
        println("configuration error: " .. error)
        return
    end
end

local config = pocket.config

----------------------------------------
-- log init
----------------------------------------

log.init(config.LogPath, config.LogMode, config.LogDebug)

log.info("========================================")
log.info("BOOTING pocket.startup " .. POCKET_VERSION)
log.info("========================================")

crash.set_env("pocket", POCKET_VERSION)
crash.dbg_log_env()

----------------------------------------
-- main application
----------------------------------------

local function main()
    ----------------------------------------
    -- system startup
    ----------------------------------------

    -- mount connected devices
    ppm.mount_all()

    -- record version for GUI
    iocontrol.get_db().version = POCKET_VERSION

    ----------------------------------------
    -- memory allocation
    ----------------------------------------

    -- shared memory across threads
    ---@class pkt_shared_memory
    local __shared_memory = {
        -- pocket system state flags
        ---@class pkt_state
        pkt_state = {
            ui_ok = false,
            ui_error = nil,
            shutdown = false
        },

        -- core pocket devices
        pkt_dev = {
            modem = ppm.get_wireless_modem()
        },

        -- system objects
        pkt_sys = {
            nic = nil,          ---@type nic
            pocket_comms = nil, ---@type pocket_comms
            sv_wd = nil,        ---@type watchdog
            api_wd = nil,       ---@type watchdog
            nav = nil           ---@type pocket_nav
        },

        -- message queues
        q = {
            mq_render = mqueue.new()
        }
    }

    local smem_dev = __shared_memory.pkt_dev
    local smem_sys = __shared_memory.pkt_sys

    local pkt_state = __shared_memory.pkt_state

    ----------------------------------------
    -- setup system
    ----------------------------------------

    smem_sys.nav = pocket.init_nav(__shared_memory)

    -- message authentication init
    if type(config.AuthKey) == "string" and string.len(config.AuthKey) > 0 then
        network.init_mac(config.AuthKey)
    end

    iocontrol.report_link_state(iocontrol.LINK_STATE.UNLINKED)

    -- get the communications modem
    if smem_dev.modem == nil then
        println("startup> wireless modem not found: please craft the pocket computer with a wireless modem")
        log.fatal("startup> no wireless modem on startup")
        return
    end

    -- create connection watchdogs
    smem_sys.sv_wd = util.new_watchdog(config.ConnTimeout)
    smem_sys.sv_wd.cancel()
    smem_sys.api_wd = util.new_watchdog(config.ConnTimeout)
    smem_sys.api_wd.cancel()
    log.debug("startup> conn watchdogs created")

    -- create network interface then setup comms
    smem_sys.nic = network.nic(smem_dev.modem)
    smem_sys.pocket_comms = pocket.comms(POCKET_VERSION, smem_sys.nic, smem_sys.sv_wd, smem_sys.api_wd, smem_sys.nav)
    log.debug("startup> comms init")

    -- init I/O control
    iocontrol.init_core(smem_sys.pocket_comms, smem_sys.nav, config)

    ----------------------------------------
    -- start the UI
    ----------------------------------------

    local ui_message
    pkt_state.ui_ok, ui_message = renderer.try_start_ui()
    if not pkt_state.ui_ok then
        println(util.c("UI error: ", ui_message))
        log.error(util.c("startup> GUI render failed with error ", ui_message))
    end

    ----------------------------------------
    -- start system
    ----------------------------------------

    if pkt_state.ui_ok then
        -- init threads
        local main_thread   = threads.thread__main(__shared_memory)
        local render_thread = threads.thread__render(__shared_memory)

        log.info("startup> completed")

        -- run threads
        parallel.waitForAll(main_thread.p_exec, render_thread.p_exec)

        renderer.close_ui()

        if not pkt_state.ui_ok then
            println(util.c("UI crashed with error: ", pkt_state.ui_error))
        end
    else
        println_ts("UI creation failed")
    end

    println_ts("exited")
    log.info("exited")
end

if not xpcall(main, crash.handler) then
    pcall(renderer.close_ui)
    crash.exit()
else
    log.close()
end

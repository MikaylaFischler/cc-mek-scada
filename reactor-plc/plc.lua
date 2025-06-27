local comms   = require("scada-common.comms")
local const   = require("scada-common.constants")
local log     = require("scada-common.log")
local ppm     = require("scada-common.ppm")
local rsio    = require("scada-common.rsio")
local types   = require("scada-common.types")
local util    = require("scada-common.util")

local themes  = require("graphics.themes")

local databus = require("reactor-plc.databus")

local plc = {}

local RPS_TRIP_CAUSE = types.RPS_TRIP_CAUSE

local PROTOCOL = comms.PROTOCOL
local DEVICE_TYPE = comms.DEVICE_TYPE
local ESTABLISH_ACK = comms.ESTABLISH_ACK
local RPLC_TYPE = comms.RPLC_TYPE
local MGMT_TYPE = comms.MGMT_TYPE
local AUTO_ACK = comms.PLC_AUTO_ACK

local RPS_LIMITS = const.RPS_LIMITS

-- specific errors thrown when scram/start is used that still count as success
local PCALL_SCRAM_MSG = "Scram requires the reactor to be active."
local PCALL_START_MSG = "Reactor is already active."

---@type plc_config
---@diagnostic disable-next-line: missing-fields
local config = {}

plc.config = config

-- load the PLC configuration
function plc.load_config()
    if not settings.load("/reactor-plc.settings") then return false end

    config.Networked = settings.get("Networked")
    config.UnitID = settings.get("UnitID")

    config.EmerCoolEnable = settings.get("EmerCoolEnable")
    config.EmerCoolSide = settings.get("EmerCoolSide")
    config.EmerCoolColor = settings.get("EmerCoolColor")
    config.EmerCoolInvert = settings.get("EmerCoolInvert")

    config.SVR_Channel = settings.get("SVR_Channel")
    config.PLC_Channel = settings.get("PLC_Channel")
    config.ConnTimeout = settings.get("ConnTimeout")
    config.TrustedRange = settings.get("TrustedRange")
    config.AuthKey = settings.get("AuthKey")

    config.LogMode = settings.get("LogMode")
    config.LogPath = settings.get("LogPath")
    config.LogDebug = settings.get("LogDebug")

    config.FrontPanelTheme = settings.get("FrontPanelTheme")
    config.ColorMode = settings.get("ColorMode")

    return plc.validate_config(config)
end

-- validate a PLC configuration
---@param cfg plc_config
function plc.validate_config(cfg)
    local cfv = util.new_validator()

    cfv.assert_type_bool(cfg.Networked)
    cfv.assert_type_int(cfg.UnitID)
    cfv.assert_type_bool(cfg.EmerCoolEnable)

    if cfg.Networked == true then
        cfv.assert_channel(cfg.SVR_Channel)
        cfv.assert_channel(cfg.PLC_Channel)
        cfv.assert_type_num(cfg.ConnTimeout)
        cfv.assert_min(cfg.ConnTimeout, 2)
        cfv.assert_type_num(cfg.TrustedRange)
        cfv.assert_min(cfg.TrustedRange, 0)
        cfv.assert_type_str(cfg.AuthKey)

        if type(cfg.AuthKey) == "string" then
            local len = string.len(cfg.AuthKey)
            cfv.assert(len == 0 or len >= 8)
        end
    end

    cfv.assert_type_int(cfg.LogMode)
    cfv.assert_range(cfg.LogMode, 0, 1)
    cfv.assert_type_str(cfg.LogPath)
    cfv.assert_type_bool(cfg.LogDebug)

    cfv.assert_type_int(cfg.FrontPanelTheme)
    cfv.assert_range(cfg.FrontPanelTheme, 1, 2)
    cfv.assert_type_int(cfg.ColorMode)
    cfv.assert_range(cfg.ColorMode, 1, themes.COLOR_MODE.NUM_MODES)

    -- check emergency coolant configuration if enabled
    if cfg.EmerCoolEnable then
        cfv.assert_eq(rsio.is_valid_side(cfg.EmerCoolSide), true)
        cfv.assert_eq(cfg.EmerCoolColor == nil or rsio.is_color(cfg.EmerCoolColor), true)
        cfv.assert_type_bool(cfg.EmerCoolInvert)
    end

    return cfv.valid()
end

-- RPS: Reactor Protection System<br>
-- identifies dangerous states and SCRAMs reactor if warranted<br>
-- autonomous from main SCADA supervisor/coordinator control
---@nodiscard
---@param reactor table
---@param is_formed boolean
function plc.rps_init(reactor, is_formed)
    local self = {
        ---@type boolean[] check states
        state = { false, false, false, false, false, false, false, false, false, false, false, false },
        reactor_enabled = false,
        enabled_at = 0,
        emer_cool_active = nil, ---@type boolean
        formed = is_formed,
        force_disabled = false,
        tripped = false,
        trip_cause = "ok"       ---@type rps_trip_cause
    }

    local CHK = {
        HIGH_DMG = 1,
        HIGH_TEMP = 2,
        LOW_COOLANT = 3,
        EX_WASTE = 4,
        EX_HCOOLANT = 5,
        NO_FUEL = 6,
        FAULT = 7,
        TIMEOUT = 8,
        MANUAL = 9,
        AUTOMATIC = 10,
        SYS_FAIL = 11,
        FORCE_DISABLED = 12
    }

    -- PRIVATE FUNCTIONS --

    -- set reactor access fault flag
    local function _set_fault()
        if reactor.__p_last_fault() ~= "Terminated" then
            self.state[CHK.FAULT] = true
        end
    end

    -- check if the result of a peripheral call was OK, handle the failure if not
    ---@nodiscard
    ---@param result any PPM function call result
    ---@return boolean succeeded if the result is OK, false if it was a PPM failure
    local function _check_and_handle_ppm_call(result)
        if result == ppm.ACCESS_FAULT then
            _set_fault()

            -- if undefined, then the reactor isn't formed
            if reactor.__p_last_fault() == ppm.UNDEFINED_FIELD then self.formed = false end
        else return true end

        return false
    end

    -- set emergency coolant control (if configured)
    ---@param state boolean true to enable emergency coolant, false to disable
    local function _set_emer_cool(state)
        -- check if this was configured: if it's a table, fields have already been validated.
        if config.EmerCoolEnable then
            -- use ~= as XOR for simple inversion
            local level = rsio.digital_write_active(rsio.IO.U_EMER_COOL, config.EmerCoolInvert ~= state)

            if level ~= false then
                if rsio.is_color(config.EmerCoolColor) then
                    local output = rs.getBundledOutput(config.EmerCoolSide)

                    if rsio.digital_write(level) then
                        output = colors.combine(output, config.EmerCoolColor)
                    else
                        output = colors.subtract(output, config.EmerCoolColor)
                    end

                    rs.setBundledOutput(config.EmerCoolSide, output)
                else
                    rs.setOutput(config.EmerCoolSide, rsio.digital_write(level))
                end

                if state ~= self.emer_cool_active then
                    if state then
                        log.info("RPS: emergency coolant valve OPENED")
                    else
                        log.info("RPS: emergency coolant valve CLOSED")
                    end

                    self.emer_cool_active = state
                end
            end
        end
    end

    -- check if the reactor is formed
    local function _is_formed()
        local formed = reactor.isFormed()
        if _check_and_handle_ppm_call(formed) then
            self.formed = formed
        end

        -- always update, since some ppm failures constitute not being formed
        if not self.state[CHK.SYS_FAIL] then
            self.state[CHK.SYS_FAIL] = not self.formed
        end
    end

    -- check if the reactor is force disabled
    local function _is_force_disabled()
        local disabled = reactor.isForceDisabled()
        if _check_and_handle_ppm_call(disabled) then
            self.force_disabled = disabled

            if not self.state[CHK.FORCE_DISABLED] then
                self.state[CHK.FORCE_DISABLED] = disabled
            end
        end
    end

    -- check for high damage
    local function _high_damage()
        local damage_percent = reactor.getDamagePercent()
        if _check_and_handle_ppm_call(damage_percent) and not self.state[CHK.HIGH_DMG] then
            self.state[CHK.HIGH_DMG] = damage_percent >= RPS_LIMITS.MAX_DAMAGE_PERCENT
        end
    end

    -- check if the reactor is at a critically high temperature
    local function _high_temp()
        -- mekanism: MAX_DAMAGE_TEMPERATURE = 1200K
        local temp = reactor.getTemperature()
        if _check_and_handle_ppm_call(temp) and not self.state[CHK.HIGH_TEMP] then
            self.state[CHK.HIGH_TEMP] = temp >= RPS_LIMITS.MAX_DAMAGE_TEMPERATURE
        end
    end

    -- check if there is very low coolant
    local function _low_coolant()
        local coolant_filled = reactor.getCoolantFilledPercentage()
        if _check_and_handle_ppm_call(coolant_filled) and not self.state[CHK.LOW_COOLANT] then
            self.state[CHK.LOW_COOLANT] = coolant_filled < RPS_LIMITS.MIN_COOLANT_FILL
        end
    end

    -- check for excess waste (>80% filled)
    local function _excess_waste()
        local w_filled = reactor.getWasteFilledPercentage()
        if _check_and_handle_ppm_call(w_filled) and not self.state[CHK.EX_WASTE] then
            self.state[CHK.EX_WASTE] = w_filled > RPS_LIMITS.MAX_WASTE_FILL
        end
    end

    -- check for heated coolant backup (>95% filled)
    local function _excess_heated_coolant()
        local hc_filled = reactor.getHeatedCoolantFilledPercentage()
        if _check_and_handle_ppm_call(hc_filled) and not self.state[CHK.EX_HCOOLANT] then
            self.state[CHK.EX_HCOOLANT] = hc_filled > RPS_LIMITS.MAX_HEATED_COLLANT_FILL
        end
    end

    -- check if there is no fuel
    local function _insufficient_fuel()
        local fuel = reactor.getFuelFilledPercentage()
        if _check_and_handle_ppm_call(fuel) and not self.state[CHK.NO_FUEL] then
            self.state[CHK.NO_FUEL] = fuel <= RPS_LIMITS.NO_FUEL_FILL
        end
    end

    -- PUBLIC FUNCTIONS --

    ---@class rps
    local public = {}

    -- re-link a reactor after a peripheral re-connect
    ---@param new_reactor table reconnected reactor
    function public.reconnect_reactor(new_reactor)
        reactor = new_reactor
    end

    -- trip for lost peripheral
    function public.trip_fault()
        _set_fault()
    end

    -- trip for a PLC comms timeout
    function public.trip_timeout()
        self.state[CHK.TIMEOUT] = true
    end

    -- manually SCRAM the reactor
    function public.trip_manual()
        self.state[CHK.MANUAL] = true
    end

    -- automatic SCRAM commanded by supervisor
    function public.trip_auto()
        self.state[CHK.AUTOMATIC] = true
    end

    -- trip for unformed reactor
    function public.trip_sys_fail()
        self.state[CHK.FAULT] = true
        self.state[CHK.SYS_FAIL] = true
    end

    -- SCRAM the reactor now<br>
    ---@return boolean success
    --- EVENT_CONSUMER: this function consumes events
    function public.scram()
        log.info("RPS: reactor SCRAM")

        reactor.scram()
        if reactor.__p_is_faulted() and not string.find(reactor.__p_last_fault(), PCALL_SCRAM_MSG) then
            log.error("RPS: failed reactor SCRAM")
            return false
        else
            self.reactor_enabled = false
            self.last_runtime = util.time_ms() - self.enabled_at
            return true
        end
    end

    -- start the reactor now<br>
    ---@return boolean success
    --- EVENT_CONSUMER: this function consumes events
    function public.activate()
        if not self.tripped then
            log.info("RPS: reactor start")

            reactor.activate()
            if reactor.__p_is_faulted() and not string.find(reactor.__p_last_fault(), PCALL_START_MSG) then
                log.error("RPS: failed reactor start")
            else
                self.reactor_enabled = true
                self.enabled_at = util.time_ms()
                return true
            end
        else
            log.debug(util.c("RPS: failed start, RPS tripped: ", self.trip_cause))
        end

        return false
    end

    -- automatic control activate/re-activate
    ---@return boolean success
    function public.auto_activate()
        -- clear automatic SCRAM if it was the cause
        if self.tripped and self.trip_cause == "automatic" then
            self.state[CHK.AUTOMATIC] = true
            self.trip_cause = RPS_TRIP_CAUSE.OK
            self.tripped = false

            log.debug("RPS: cleared automatic SCRAM for re-activation")
        end

        return public.activate()
    end

    -- check all safety conditions
    ---@nodiscard
    ---@return boolean tripped, rps_trip_cause trip_status, boolean first_trip
    function public.check()
        local status = RPS_TRIP_CAUSE.OK
        local was_tripped = self.tripped
        local first_trip = false

        if self.formed then
            -- update state
            parallel.waitForAll(
                _is_formed,
                _is_force_disabled,
                _high_damage,
                _high_temp,
                _low_coolant,
                _excess_waste,
                _excess_heated_coolant,
                _insufficient_fuel
            )
        else
            -- check to see if its now formed
            _is_formed()
        end

        -- check system states in order of severity
        if self.tripped then
            status = self.trip_cause
        elseif self.state[CHK.SYS_FAIL] then
            log.warning("RPS: system failure, reactor not formed")
            status = RPS_TRIP_CAUSE.SYS_FAIL
        elseif self.state[CHK.FORCE_DISABLED] then
            log.warning("RPS: reactor was force disabled")
            status = RPS_TRIP_CAUSE.FORCE_DISABLED
        elseif self.state[CHK.HIGH_DMG] then
            log.warning("RPS: high damage")
            status = RPS_TRIP_CAUSE.HIGH_DMG
        elseif self.state[CHK.HIGH_TEMP] then
            log.warning("RPS: high temperature")
            status = RPS_TRIP_CAUSE.HIGH_TEMP
        elseif self.state[CHK.LOW_COOLANT] then
            log.warning("RPS: low coolant")
            status = RPS_TRIP_CAUSE.LOW_COOLANT
        elseif self.state[CHK.EX_WASTE] then
            log.warning("RPS: full waste")
            status = RPS_TRIP_CAUSE.EX_WASTE
        elseif self.state[CHK.EX_HCOOLANT] then
            log.warning("RPS: heated coolant backup")
            status = RPS_TRIP_CAUSE.EX_HCOOLANT
        elseif self.state[CHK.NO_FUEL] then
            log.warning("RPS: no fuel")
            status = RPS_TRIP_CAUSE.NO_FUEL
        elseif self.state[CHK.FAULT] then
            log.warning("RPS: reactor access fault")
            status = RPS_TRIP_CAUSE.FAULT
        elseif self.state[CHK.TIMEOUT] then
            log.warning("RPS: supervisor connection timeout")
            status = RPS_TRIP_CAUSE.TIMEOUT
        elseif self.state[CHK.MANUAL] then
            log.warning("RPS: manual SCRAM requested")
            status = RPS_TRIP_CAUSE.MANUAL
        elseif self.state[CHK.AUTOMATIC] then
            log.warning("RPS: automatic SCRAM requested")
            status = RPS_TRIP_CAUSE.AUTOMATIC
        else
            self.tripped = false
            self.trip_cause = RPS_TRIP_CAUSE.OK
        end

        -- if a new trip occured...
        if (not was_tripped) and (status ~= RPS_TRIP_CAUSE.OK) then
            first_trip = true
            self.tripped = true
            self.trip_cause = status

            -- in the case that the reactor is detected to be active,
            -- it will be scrammed shortly after this in the main RPS loop if we don't here
            if self.formed then
                if not self.force_disabled then
                    public.scram()
                else
                    log.warning("RPS: skipping SCRAM due to reactor being force disabled")
                end
            else
                log.warning("RPS: skipping SCRAM due to not being formed")
            end
        end

        -- update emergency coolant control if configured
        _set_emer_cool(self.state[CHK.LOW_COOLANT])

        -- report RPS status
        databus.tx_rps(self.tripped, self.state, self.emer_cool_active)

        return self.tripped, status, first_trip
    end

    ---@nodiscard
    function public.status() return self.state end

    ---@nodiscard
    function public.is_tripped() return self.tripped end
    ---@nodiscard
    function public.get_trip_cause() return self.trip_cause end
    ---@nodiscard
    function public.is_low_coolant() return self.states[CHK.LOW_COOLANT] end

    ---@nodiscard
    function public.is_active() return self.reactor_enabled end
    ---@nodiscard
    function public.is_formed() return self.formed end
    ---@nodiscard
    function public.is_force_disabled() return self.force_disabled end

    -- get the runtime of the reactor if active, or the last runtime if disabled
    ---@nodiscard
    ---@return integer runtime time since last enable
    function public.get_runtime() return util.trinary(self.reactor_enabled, util.time_ms() - self.enabled_at, self.last_runtime) end

    -- reset the RPS
    ---@param quiet? boolean true to suppress the info log message
    function public.reset(quiet)
        self.tripped = false
        self.trip_cause = RPS_TRIP_CAUSE.OK

        for i = 1, #self.state do self.state[i] = false end

        if not quiet then log.info("RPS: reset") end
    end

    -- partial RPS reset that only clears fault and sys_fail
    function public.reset_formed()
        self.tripped = false
        self.trip_cause = RPS_TRIP_CAUSE.OK

        self.state[CHK.FAULT] = false
        self.state[CHK.SYS_FAIL] = false

        log.info("RPS: partial reset on formed")
    end

    -- reset the automatic and timeout trip flags, then clear trip if that was the trip cause
    function public.auto_reset()
        self.state[CHK.AUTOMATIC] = false
        self.state[CHK.TIMEOUT] = false

        if self.trip_cause == RPS_TRIP_CAUSE.AUTOMATIC or self.trip_cause == RPS_TRIP_CAUSE.TIMEOUT then
            self.trip_cause = RPS_TRIP_CAUSE.OK
            self.tripped = false

            log.info("RPS: auto reset")
        end
    end

    -- link functions with databus
    databus.link_rps(public.trip_manual, public.reset)

    return public
end

-- Reactor PLC Communications
---@nodiscard
---@param version string PLC version
---@param nic nic network interface device
---@param reactor table reactor device
---@param rps rps RPS reference
---@param conn_watchdog watchdog watchdog reference
function plc.comms(version, nic, reactor, rps, conn_watchdog)
    local self = {
        sv_addr = comms.BROADCAST,
        seq_num = util.time_ms() * 10, -- unique per peer, restarting will not re-use seq nums due to message rate
        r_seq_num = nil,               ---@type nil|integer
        scrammed = false,
        linked = false,
        last_est_ack = ESTABLISH_ACK.ALLOW,
        resend_build = false,
        auto_ack_token = 0,
        status_cache = nil,
        max_burn_rate = nil
    }

    comms.set_trusted_range(config.TrustedRange)

    -- PRIVATE FUNCTIONS --

    -- configure network channels
    nic.closeAll()
    nic.open(config.PLC_Channel)

    -- send an RPLC packet
    ---@param msg_type RPLC_TYPE
    ---@param msg table
    local function _send(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local r_pkt = comms.rplc_packet()

        r_pkt.make(config.UnitID, msg_type, msg)
        s_pkt.make(self.sv_addr, self.seq_num, PROTOCOL.RPLC, r_pkt.raw_sendable())

        nic.transmit(config.SVR_Channel, config.PLC_Channel, s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- send a SCADA management packet
    ---@param msg_type MGMT_TYPE
    ---@param msg table
    local function _send_mgmt(msg_type, msg)
        local s_pkt = comms.scada_packet()
        local m_pkt = comms.mgmt_packet()

        m_pkt.make(msg_type, msg)
        s_pkt.make(self.sv_addr, self.seq_num, PROTOCOL.SCADA_MGMT, m_pkt.raw_sendable())

        nic.transmit(config.SVR_Channel, config.PLC_Channel, s_pkt)
        self.seq_num = self.seq_num + 1
    end

    -- dynamic reactor status information, excluding heating rate
    ---@return table data_table, boolean faulted
    local function _get_reactor_status()
        local fuel = nil
        local waste = nil
        local coolant = nil
        local hcoolant = nil

        local data_table = {}

        reactor.__p_disable_afc()

        local tasks = {
            function () data_table[1]  = reactor.getStatus() end,
            function () data_table[2]  = reactor.getBurnRate() end,
            function () data_table[3]  = reactor.getActualBurnRate() end,
            function () data_table[4]  = reactor.getTemperature() end,
            function () data_table[5]  = reactor.getDamagePercent() end,
            function () data_table[6]  = reactor.getBoilEfficiency() end,
            function () data_table[7]  = reactor.getEnvironmentalLoss() end,
            function () fuel           = reactor.getFuel() end,
            function () data_table[9]  = reactor.getFuelFilledPercentage() end,
            function () waste          = reactor.getWaste() end,
            function () data_table[11] = reactor.getWasteFilledPercentage() end,
            function () coolant        = reactor.getCoolant() end,
            function () data_table[14] = reactor.getCoolantFilledPercentage() end,
            function () hcoolant       = reactor.getHeatedCoolant() end,
            function () data_table[17] = reactor.getHeatedCoolantFilledPercentage() end
        }

        parallel.waitForAll(table.unpack(tasks))

        if fuel ~= nil then
            data_table[8] = fuel.amount
        end

        if waste ~= nil then
            data_table[10] = waste.amount
        end

        if coolant ~= nil then
            data_table[12] = coolant.name
            data_table[13] = coolant.amount
        end

        if hcoolant ~= nil then
            data_table[15] = hcoolant.name
            data_table[16] = hcoolant.amount
        end

        reactor.__p_enable_afc()

        return data_table, reactor.__p_is_faulted()
    end

    -- update the status cache if changed
    ---@return boolean changed
    local function _update_status_cache()
        local status, faulted = _get_reactor_status()
        local changed = false

        if not faulted then
            if self.status_cache ~= nil then
                for i = 1, #status do
                    if status[i] ~= self.status_cache[i] then
                        changed = true
                        break
                    end
                end
            else
                changed = true
            end

            if changed then
                self.status_cache = status
            end
        end

        return changed
    end

    -- keep alive ack
    ---@param srv_time integer
    local function _send_keep_alive_ack(srv_time)
        _send_mgmt(MGMT_TYPE.KEEP_ALIVE, { srv_time, util.time() })
    end

    -- general ack
    ---@param msg_type RPLC_TYPE
    ---@param status boolean|integer
    local function _send_ack(msg_type, status)
        _send(msg_type, { status })
    end

    -- send static structure properties, cached by server
    local function _send_struct()
        local mek_data = {}

        reactor.__p_disable_afc()

        local tasks = {
            function () mek_data[1]  = reactor.getLength() end,
            function () mek_data[2]  = reactor.getWidth() end,
            function () mek_data[3]  = reactor.getHeight() end,
            function () mek_data[4]  = reactor.getMinPos() end,
            function () mek_data[5]  = reactor.getMaxPos() end,
            function () mek_data[6]  = reactor.getHeatCapacity() end,
            function () mek_data[7]  = reactor.getFuelAssemblies() end,
            function () mek_data[8]  = reactor.getFuelSurfaceArea() end,
            function () mek_data[9]  = reactor.getFuelCapacity() end,
            function () mek_data[10] = reactor.getWasteCapacity() end,
            function () mek_data[11] = reactor.getCoolantCapacity() end,
            function () mek_data[12] = reactor.getHeatedCoolantCapacity() end,
            function () mek_data[13] = reactor.getMaxBurnRate() end
        }

        parallel.waitForAll(table.unpack(tasks))

        if reactor.__p_is_ok() then
            _send(RPLC_TYPE.MEK_STRUCT, mek_data)
            self.resend_build = false
        end

        reactor.__p_enable_afc()
    end

    -- PUBLIC FUNCTIONS --

    ---@class plc_comms
    local public = {}

    -- reconnect a newly connected reactor
    ---@param new_reactor table
    function public.reconnect_reactor(new_reactor)
        reactor = new_reactor
        self.status_cache = nil
        self.resend_build = true
        self.max_burn_rate = nil
    end

    -- unlink from the server
    function public.unlink()
        self.sv_addr = comms.BROADCAST
        self.linked = false
        self.r_seq_num = nil
        self.status_cache = nil
        databus.tx_link_state(types.PANEL_LINK_STATE.DISCONNECTED)
    end

    -- close the connection to the server
    function public.close()
        conn_watchdog.cancel()
        public.unlink()
        _send_mgmt(MGMT_TYPE.CLOSE, {})
    end

    -- attempt to establish link with supervisor
    function public.send_link_req()
        self.r_seq_num = nil
        _send_mgmt(MGMT_TYPE.ESTABLISH, { comms.version, version, DEVICE_TYPE.PLC, config.UnitID })
    end

    -- send live status information
    ---@param no_reactor boolean PLC lost reactor connection
    ---@param formed boolean reactor formed (from PLC state)
    function public.send_status(no_reactor, formed)
        if self.linked then
            local mek_data = nil        ---@type table
            local heating_rate = 0.0    ---@type number

            if (not no_reactor) and rps.is_formed() then
                if _update_status_cache() then mek_data = self.status_cache end
                heating_rate = reactor.getHeatingRate()
            end

            local sys_status = {
                util.time(),         -- timestamp
                (not self.scrammed), -- requested control state
                no_reactor,          -- no reactor peripheral connected
                formed,              -- reactor formed
                self.auto_ack_token, -- indicate auto command received prior to this status update
                heating_rate,        -- heating rate
                mek_data             -- mekanism status data
            }

            _send(RPLC_TYPE.STATUS, sys_status)

            if self.resend_build then _send_struct() end
        end
    end

    -- send reactor protection system status
    function public.send_rps_status()
        if self.linked then
            _send(RPLC_TYPE.RPS_STATUS, { rps.is_tripped(), rps.get_trip_cause(), table.unpack(rps.status()) })
        end
    end

    -- send reactor protection system alarm
    ---@param cause rps_trip_cause reactor protection system status
    function public.send_rps_alarm(cause)
        if self.linked then
            _send(RPLC_TYPE.RPS_ALARM, { cause, table.unpack(rps.status()) })
        end
    end

    -- parse a packet
    ---@nodiscard
    ---@param side string
    ---@param sender integer
    ---@param reply_to integer
    ---@param message any
    ---@param distance integer
    ---@return rplc_frame|mgmt_frame|nil packet
    function public.parse_packet(side, sender, reply_to, message, distance)
        local s_pkt = nic.receive(side, sender, reply_to, message, distance)
        local pkt = nil

        if s_pkt then
            -- get as RPLC packet
            if s_pkt.protocol() == PROTOCOL.RPLC then
                local rplc_pkt = comms.rplc_packet()
                if rplc_pkt.decode(s_pkt) then
                    pkt = rplc_pkt.get()
                end
            -- get as SCADA management packet
            elseif s_pkt.protocol() == PROTOCOL.SCADA_MGMT then
                local mgmt_pkt = comms.mgmt_packet()
                if mgmt_pkt.decode(s_pkt) then
                    pkt = mgmt_pkt.get()
                end
            else
                log.debug("unsupported packet type " .. s_pkt.protocol(), true)
            end
        end

        return pkt
    end

    -- handle RPLC and MGMT packets
    ---@param packet rplc_frame|mgmt_frame packet frame
    ---@param plc_state plc_state PLC state
    ---@param setpoints setpoints setpoint control table
    function public.handle_packet(packet, plc_state, setpoints)
        -- print a log message to the terminal as long as the UI isn't running
        local function println_ts(message) if not plc_state.fp_ok then util.println_ts(message) end end

        local protocol = packet.scada_frame.protocol()
        local l_chan   = packet.scada_frame.local_channel()
        local src_addr = packet.scada_frame.src_addr()

        -- handle packets now that we have prints setup
        if l_chan == config.PLC_Channel then
            -- check sequence number
            if self.r_seq_num == nil then
                self.r_seq_num = packet.scada_frame.seq_num() + 1
            elseif self.r_seq_num ~= packet.scada_frame.seq_num() then
                log.warning("sequence out-of-order: next = " .. self.r_seq_num .. ", new = " .. packet.scada_frame.seq_num())
                return
            elseif self.linked and (src_addr ~= self.sv_addr) then
                log.debug("received packet from unknown computer " .. src_addr .. " while linked (expected " .. self.sv_addr ..
                            "); channel in use by another system?")
                return
            else
                self.r_seq_num = packet.scada_frame.seq_num() + 1
            end

            -- feed the watchdog first so it doesn't uhh...eat our packets :)
            conn_watchdog.feed()

            -- handle packet
            if protocol == PROTOCOL.RPLC then
                ---@cast packet rplc_frame
                -- if linked, only accept packets from configured supervisor
                if self.linked then
                    if packet.type == RPLC_TYPE.STATUS then
                        -- request of full status, clear cache first
                        self.status_cache = nil
                        public.send_status(plc_state.no_reactor, plc_state.reactor_formed)
                        log.debug("sent out status cache again, did supervisor miss it?")
                    elseif packet.type == RPLC_TYPE.MEK_STRUCT then
                        -- request for physical structure
                        _send_struct()
                        log.debug("sent out structure again, did supervisor miss it?")
                    elseif packet.type == RPLC_TYPE.MEK_BURN_RATE then
                        -- set the burn rate
                        if (packet.length == 2) and (type(packet.data[1]) == "number") then
                            local success = false
                            local burn_rate = math.floor(packet.data[1] * 10) / 10
                            local ramp = packet.data[2]

                            -- if no known max burn rate, check again
                            if self.max_burn_rate == nil then
                                self.max_burn_rate = reactor.getMaxBurnRate()
                            end

                            -- if we know our max burn rate, update current burn rate setpoint if in range
                            if self.max_burn_rate ~= ppm.ACCESS_FAULT then
                                if burn_rate > 0 and burn_rate <= self.max_burn_rate then
                                    if ramp then
                                        setpoints.burn_rate_en = true
                                        setpoints.burn_rate = burn_rate
                                        success = true
                                    else
                                        reactor.setBurnRate(burn_rate)
                                        success = reactor.__p_is_ok()
                                    end
                                else
                                    log.debug(burn_rate .. " rate outside of 0 < x <= " .. self.max_burn_rate)
                                end
                            end

                            _send_ack(packet.type, success)
                        else
                            log.debug("RPLC set burn rate packet length mismatch or non-numeric burn rate")
                        end
                    elseif packet.type == RPLC_TYPE.RPS_ENABLE then
                        -- enable the reactor
                        self.scrammed = false
                        _send_ack(packet.type, rps.activate())
                    elseif packet.type == RPLC_TYPE.RPS_DISABLE then
                        -- disable the reactor, but do not trip
                        self.scrammed = true
                        _send_ack(packet.type, rps.scram())
                    elseif packet.type == RPLC_TYPE.RPS_SCRAM then
                        -- disable the reactor per manual request
                        self.scrammed = true
                        rps.trip_manual()
                        _send_ack(packet.type, true)
                    elseif packet.type == RPLC_TYPE.RPS_ASCRAM then
                        -- disable the reactor per automatic request
                        self.scrammed = true
                        rps.trip_auto()
                        _send_ack(packet.type, true)
                    elseif packet.type == RPLC_TYPE.RPS_RESET then
                        -- reset the RPS status
                        rps.reset()
                        _send_ack(packet.type, true)
                    elseif packet.type == RPLC_TYPE.RPS_AUTO_RESET then
                        -- reset automatic SCRAM and timeout trips
                        rps.auto_reset()
                        _send_ack(packet.type, true)
                    elseif packet.type == RPLC_TYPE.AUTO_BURN_RATE then
                        -- automatic control requested a new burn rate
                        if (packet.length == 3) and (type(packet.data[1]) == "number") and (type(packet.data[3]) == "number") then
                            local ack = AUTO_ACK.FAIL
                            local burn_rate = math.floor(packet.data[1] * 100) / 100
                            local ramp = packet.data[2]
                            self.auto_ack_token = packet.data[3]

                            -- if no known max burn rate, check again
                            if self.max_burn_rate == nil then
                                self.max_burn_rate = reactor.getMaxBurnRate()
                            end

                            -- if we know our max burn rate, update current burn rate setpoint if in range
                            if self.max_burn_rate ~= ppm.ACCESS_FAULT then
                                if burn_rate < 0.01 then
                                    if rps.is_active() then
                                        -- auto scram to disable
                                        log.debug("AUTO: stopping the reactor to meet 0.0 burn rate")
                                        if rps.scram() then
                                            ack = AUTO_ACK.ZERO_DIS_OK
                                        else
                                            log.warning("AUTO: automatic reactor stop failed")
                                        end
                                    else
                                        ack = AUTO_ACK.ZERO_DIS_OK
                                    end
                                elseif burn_rate <= self.max_burn_rate then
                                    if not rps.is_active() then
                                        -- activate the reactor
                                        log.debug("AUTO: activating the reactor")

                                        reactor.setBurnRate(0.01)
                                        if reactor.__p_is_faulted() then
                                            log.warning("AUTO: failed to reset burn rate for auto activation")
                                        else
                                            if not rps.auto_activate() then
                                                log.warning("AUTO: automatic reactor activation failed")
                                            end
                                        end
                                    end

                                    -- if active, set/ramp burn rate
                                    if rps.is_active() then
                                        if ramp then
                                            log.debug(util.c("AUTO: setting burn rate ramp to ", burn_rate))
                                            setpoints.burn_rate_en = true
                                            setpoints.burn_rate = burn_rate
                                            ack = AUTO_ACK.RAMP_SET_OK
                                        else
                                            log.debug(util.c("AUTO: setting burn rate directly to ", burn_rate))
                                            reactor.setBurnRate(burn_rate)
                                            ack = util.trinary(reactor.__p_is_faulted(), AUTO_ACK.FAIL, AUTO_ACK.DIRECT_SET_OK)
                                        end
                                    end
                                else
                                    log.debug(util.c(burn_rate, " rate outside of 0 < x <= ", self.max_burn_rate))
                                end
                            end

                            _send_ack(packet.type, ack)
                        else
                            log.debug("RPLC set automatic burn rate packet length mismatch or non-numeric burn rate")
                        end
                    else
                        log.debug("received unknown RPLC packet type " .. packet.type)
                    end
                else
                    log.debug("discarding RPLC packet before linked")
                end
            elseif protocol == PROTOCOL.SCADA_MGMT then
                ---@cast packet mgmt_frame
                -- if linked, only accept packets from configured supervisor
                if self.linked then
                    if packet.type == MGMT_TYPE.KEEP_ALIVE then
                        -- keep alive request received, echo back
                        if packet.length == 1 and type(packet.data[1]) == "number" then
                            local timestamp = packet.data[1]
                            local trip_time = util.time() - timestamp

                            if trip_time > 750 then
                                log.warning("PLC KEEP_ALIVE trip time > 750ms (" .. trip_time .. "ms)")
                            end

                            -- log.debug("PLC RTT = " .. trip_time .. "ms")

                            _send_keep_alive_ack(timestamp)
                        else
                            log.debug("SCADA_MGMT keep alive packet length/type mismatch")
                        end
                    elseif packet.type == MGMT_TYPE.CLOSE then
                        -- handle session close
                        conn_watchdog.cancel()
                        public.unlink()
                        println_ts("server connection closed by remote host")
                        log.warning("server connection closed by remote host")
                    else
                        log.debug("received unsupported SCADA_MGMT packet type " .. packet.type)
                    end
                elseif packet.type == MGMT_TYPE.ESTABLISH then
                    -- link request confirmation
                    if packet.length == 1 then
                        local est_ack = packet.data[1]

                        if est_ack == ESTABLISH_ACK.ALLOW then
                            println_ts("linked!")
                            log.info("supervisor establish request approved, linked to SV (CID#" .. src_addr .. ")")

                            -- link + reset cache
                            self.sv_addr = src_addr
                            self.linked = true
                            self.status_cache = nil

                            if plc_state.reactor_formed then _send_struct() end
                            public.send_status(plc_state.no_reactor, plc_state.reactor_formed)

                            log.debug("sent initial status data")
                        else
                            if self.last_est_ack ~= est_ack then
                                if est_ack == ESTABLISH_ACK.DENY then
                                    println_ts("link request denied, retrying...")
                                    log.info("supervisor establish request denied, retrying")
                                elseif est_ack == ESTABLISH_ACK.COLLISION then
                                    println_ts("reactor PLC ID collision (check config), retrying...")
                                    log.warning("establish request collision, retrying")
                                elseif est_ack == ESTABLISH_ACK.BAD_VERSION then
                                    println_ts("supervisor version mismatch (try updating), retrying...")
                                    log.warning("establish request version mismatch, retrying")
                                else
                                    println_ts("invalid link response, bad channel? retrying...")
                                    log.error("unknown establish request response, retrying")
                                end
                            end

                            -- unlink
                            self.sv_addr = comms.BROADCAST
                            self.linked = false
                        end

                        self.last_est_ack = est_ack

                        -- report link state
                        databus.tx_link_state(est_ack + 1)
                    else
                        log.debug("SCADA_MGMT establish packet length mismatch")
                    end
                else
                    log.debug("discarding non-link SCADA_MGMT packet before linked")
                end
            else
                -- should be unreachable assuming packet is from parse_packet()
                log.error("illegal packet type " .. protocol, true)
            end
        else
            log.debug("received packet on unconfigured channel " .. l_chan, true)
        end
    end

    ---@nodiscard
    function public.is_scrammed() return self.scrammed end
    ---@nodiscard
    function public.is_linked() return self.linked end

    return public
end

return plc

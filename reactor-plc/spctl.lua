local log     = require("scada-common.log")
local util    = require("scada-common.util")

local databus = require("reactor-plc.databus")
local plc     = require("reactor-plc.plc")

local SLOW_RAMP_mB_s     = 5.0
local FAST_SWITCH_mB_s   = 40.0
local FAST_MAX_PERCENT_s = 0.02

local FUEL_LIMIT_INIT    = 0.4  -- start high speed monitoring at 40%
local FUEL_LIMIT_START   = 0.3  -- start limiting at 30%
local FUEL_LIMIT_RELEASE = 0.4  -- stop limiting once we reach 40%
local FUEL_LIMIT_EMA_A   = 0.05 -- EMA filter alpha

local spctl = {}

---@enum RAMP_STATES
local STATES = {
    STOPPED = 1,
    INIT = 2,
    SLOW_RAMP_UP = 3,
    SLOW_RAMP_DOWN = 4,
    STABLE_WAIT = 5,
    CCOOL_MON = 6,
    FAST_RAMP_UP = 7,
    FAST_RAMP_DOWN = 8
}

local STATE_NAMES = {
    "STOPPED",
    "INIT",
    "SLOW_RAMP_UP",
    "SLOW_RAMP_DOWN",
    "STABLE_WAIT",
    "CCOOL_MON",
    "FAST_RAMP_UP",
    "FAST_RAMP_DOWN"
}

local _spctl = {
    -- reactor readings and other stats
    ---@class _spctl_data
    data = {
        tps = 0.0,
        tick_time = 0,
        max_br = 0.0,
        burn_rate = 0.0,
        act_rate = 0.0,
        fuel = 0.0,
        fuel_fill = 0.0,
        ccool_fill = 0.0,
    },

    -- ramp control

    fast_ramp_en = false,

    last_sp = 0.0,
    last_ccool = 0.0,

    last_change = 0,
    next_state = STATES.STOPPED, ---@type RAMP_STATES
    last_state = STATES.STOPPED, ---@type RAMP_STATES

    -- fuel-based burn rate limiting

    fuel_limit_en = false,

    fuel_monitoring = false,
    fuel_limiting = false,

    last_mon_check = 0,
    last_fuel_filt = 0.0,

    fuel_filt = util.ema_filter(FUEL_LIMIT_EMA_A),
    rate_filt = util.ema_filter(FUEL_LIMIT_EMA_A),
    tick_filt = util.ema_filter(FUEL_LIMIT_EMA_A)
}

local rps       = nil ---@type rps
local plc_state = nil ---@type plc_state
local setpoints = nil ---@type plc_setpoints
local limits    = nil ---@type plc_limits

-- initialize with shared memory data
---@param smem plc_shared_memory
function spctl.init(smem)
    rps       = smem.plc_sys.rps
    plc_state = smem.plc_state
    setpoints = smem.setpoints
    limits    = smem.limits

    _spctl.fast_ramp_en  = plc.config.FastRamp
    _spctl.fuel_limit_en = plc.config.FuelAutoLimiting
end

--#region Ramp Control

-- initialize ramping, or set right away if acceptable
---@param cur_br number requested burn rate
local function ramp_init(cur_br)
    _spctl.last_sp = setpoints.burn_rate

    -- update without ramp if <= 2.5 mB/t change
    if math.abs(setpoints.burn_rate - cur_br) > 2.5 then
        log.debug(util.c("SPCTL: starting burn rate ramp from ", cur_br, " mB/t to ", setpoints.burn_rate, " mB/t"))

        _spctl.last_change = os.clock()
        _spctl.next_state  = STATES.INIT
    elseif _spctl.fuel_limiting then
        local lim_br = math.min(setpoints.burn_rate, limits.fuel_max_burn)
        plc_state.limit_force_ramp = false

        log.debug(util.c("SPCTL: setting burn rate directly to ", lim_br, " mB/t (limiting active, setpoint is ", setpoints.burn_rate, ")"))
        _spctl.new_br = lim_br
    else
        plc_state.limit_force_ramp = false

        log.debug(util.c("SPCTL: setting burn rate directly to ", setpoints.burn_rate, " mB/t"))
        _spctl.new_br = setpoints.burn_rate
    end
end

-- reset states and last value tracking
local function ramp_reset()
    _spctl.last_sp    = 0
    _spctl.last_ccool = 0
    _spctl.next_state = STATES.STOPPED
    _spctl.last_state = STATES.STOPPED
end

-- run the setpoint ramp controller loop
---@param cur_br number current burn rate
---@param cur_ccool number coolant filled percentage (0 to 1)
---@param elapsed_s number seconds elapsed in the ramp
local function ramp_run(cur_br, cur_ccool, elapsed_s)
    local now        = os.clock()
    local state_time = now - _spctl.last_change
    local state      = _spctl.next_state
    local new_state  = _spctl.next_state
    local new_br     = cur_br

    if state == STATES.INIT then
        log.debug(util.c("SPCTL: initializing for ", util.trinary(_spctl.fast_ramp_en, "fast", "slow"), " burn rate ramping mode"))

        -- transition to the appropriate direction and phase
        if setpoints.burn_rate > cur_br then
            -- need to ramp up
            if _spctl.fast_ramp_en and (cur_br >= FAST_SWITCH_mB_s) then
                new_state = STATES.STABLE_WAIT
            else
                new_state = STATES.SLOW_RAMP_UP
            end
        else
            -- need to ramp down
            if _spctl.fast_ramp_en and (cur_br >= FAST_SWITCH_mB_s) then
                new_state = STATES.FAST_RAMP_DOWN
            else
                new_state = STATES.SLOW_RAMP_DOWN
            end
        end
    elseif state == STATES.SLOW_RAMP_UP then
        -- slowly ramp up
        new_br = cur_br + (SLOW_RAMP_mB_s * elapsed_s)
        if new_br > setpoints.burn_rate then new_br = setpoints.burn_rate end

        -- transition out of slow ramp after hitting the limit
        if _spctl.fast_ramp_en and (new_br >= FAST_SWITCH_mB_s) then
            new_br = FAST_SWITCH_mB_s

            new_state = STATES.STABLE_WAIT
        end
    elseif state == STATES.SLOW_RAMP_DOWN then
        -- slowly ramp down
        new_br = cur_br - (SLOW_RAMP_mB_s * elapsed_s)
        if new_br < setpoints.burn_rate then new_br = setpoints.burn_rate end
    elseif state == STATES.STABLE_WAIT then
        -- wait a minimum of 2 seconds to help with flow stability
        -- this helps detect broken things before getting too high
        if state_time >= 2 then
            new_state = STATES.CCOOL_MON
        end
    elseif state == STATES.CCOOL_MON then
        -- don't move on until coolant is not decreasing
        if cur_ccool >= _spctl.last_ccool then
            new_state = STATES.FAST_RAMP_UP
        end
    elseif state == STATES.FAST_RAMP_UP then
        -- step by a percent of the max burn rate
        local scaler = math.min(FAST_MAX_PERCENT_s, FAST_MAX_PERCENT_s * (state_time / 5.0)) * elapsed_s
        local step   = scaler * _spctl.data.max_br

        -- slow the step if we are losing coolant
        if cur_ccool < 0.8 then
            -- map 0.4-0.8 to 0-1
            local a = (cur_ccool - 0.4) * 2.5

            -- slow as we approach low coolant condition
            step = step * a
        end

        -- minimum is the slow rate, maintain old behavior
        -- if we overheat, it will be gentle and recoverable, then the user can solve the coolant issue rather than see the reactor not ramping
        step = math.max(SLOW_RAMP_mB_s * elapsed_s, step)

        -- don't exceed the setpoint
        new_br = math.min(cur_br + step, setpoints.burn_rate)

        -- log.debug(util.sprintf("SPCTL: scaler[%f] cur_ccool[%f] step[%f] new_br[%f]", scaler, cur_ccool, step, new_br))
    elseif state == STATES.FAST_RAMP_DOWN then
        -- step by a percent of the max burn rate
        local scaler = math.min(FAST_MAX_PERCENT_s, FAST_MAX_PERCENT_s * (state_time / 5.0)) * elapsed_s
        local step   = scaler * _spctl.data.max_br

        -- minimum is the slow rate, maintain old behavior
        step = math.max(SLOW_RAMP_mB_s * elapsed_s, step)

        -- don't fall below the setpoint
        new_br = math.max(cur_br - step, setpoints.burn_rate)

        -- log.debug(util.sprintf("SPCTL: scaler[%f] cur_ccool[%f] step[%f] new_br[%f]", scaler, cur_ccool, step, new_br))
    end

    -- set the burn rate
    _spctl.new_br = math.min(new_br, limits.fuel_max_burn)

    -- release forced ramping if the target is lower than the actual
    if plc_state.limit_force_ramp and (new_br < cur_br) then
        log.info("SPCTL: released ramped fuel burn limiting recovery")
        plc_state.limit_force_ramp = false
    end

    -- note: check desired br not the limited one so that we keep going if we can't achieve it yet
    if new_br ~= setpoints.burn_rate then
        -- update tracked values and continue
        _spctl.last_ccool = cur_ccool
    else
        new_state = STATES.STOPPED

        -- release forced ramping
        if plc_state.limit_force_ramp then
            log.info("SPCTL: completed ramped fuel burn limiting recovery")
            plc_state.limit_force_ramp = false
        end
    end

    -- state change management
    if new_state ~= state then
        log.debug("SPCTL: state changed to " .. (STATE_NAMES[new_state] or "UNKNOWN"))

        _spctl.next_state  = new_state
        _spctl.last_change = now
    end
end

---@param reactor FissionReactor
---@param elapsed_s number nominal iteration elapsed time reference
local function ramp_update(reactor, elapsed_s)
    -- check if we should start ramping
    if setpoints.burn_rate_en and (setpoints.burn_rate ~= _spctl.last_sp) and rps.is_active() then
        parallel.waitForAll(
            function () _spctl.data.burn_rate = reactor.getBurnRate() end,
            function () _spctl.data.max_br    = reactor.getMaxBurnRate() end
        )

        local cur_br = _spctl.data.burn_rate

        if (type(cur_br) == "number") and (type(_spctl.data.max_br) == "number") and (setpoints.burn_rate ~= cur_br) then
            ramp_init(cur_br)
        end
    end

    -- minimize operations when not running
    if _spctl.next_state ~= STATES.STOPPED then
        -- adjust burn rate (setpoints.burn_rate)
        if setpoints.burn_rate_en then
            local cur_br, ccool = _spctl.data.burn_rate, _spctl.data.ccool_fill

            if not rps.is_active() then
                log.info("SPCTL: ramping aborted (reactor inactive)")
                setpoints.burn_rate_en = false
                ramp_reset()
            else
                if (type(cur_br) == "number") and (type(ccool) == "number") then
                    ramp_run(cur_br, ccool, elapsed_s)
                else
                    log.error(util.c("SPCTL: skipped running loop due to bad data (cur_br = ", cur_br, ",cur_ccool = ", ccool, ")"))
                end
            end
        else
            log.info("SPCTL: ramping cancelled")
            ramp_reset()
        end
    elseif setpoints.burn_rate_en then
        log.info(util.c("SPCTL: ramping completed (setpoint of ", setpoints.burn_rate, " mB/t)"))
        setpoints.burn_rate_en = false
        ramp_reset()
    end
end

--#endregion

--#region Fuel Burn Rate Limiting

---@param tick integer
---@param reactor FissionReactor
local function update_fuel_rate_limiting(tick, reactor)
    local fuel_fill = nil ---@type number|nil
    local data      = _spctl.data

    if _spctl.fuel_monitoring and (type(data.fuel) == "number") and (type(data.act_rate) == "number") then
        fuel_fill = data.fuel_fill

        local elapsed_s = (util.time_s() - _spctl.last_mon_check)
        _spctl.last_mon_check = util.time_s()

        -- more likely to get a full tick by checking in two ways, so average our checks
        local tps_avg = (data.tps + (1000 / data.tick_time)) / 2

        -- update EMA filters
        _spctl.fuel_filt.update(data.fuel)
        _spctl.rate_filt.update(data.act_rate)
        _spctl.tick_filt.update(elapsed_s * tps_avg)

        -- figure out the change in fuel as mB/t
        local d_fuel     = _spctl.fuel_filt.get() - _spctl.last_fuel_filt
        local d_fuel_mBt = d_fuel / _spctl.tick_filt.get()
        local limit      = math.max(0.01, _spctl.rate_filt.get() + d_fuel_mBt)

        if _spctl.fuel_limiting then
            limits.reportable_max_burn = limit
            limits.fuel_max_burn = limit
        else
            limits.reportable_max_burn = false
            limits.fuel_max_burn = math.huge
        end

        -- log.debug(util.sprintf("SPCTL: elapsed[%f] tps[%f] tps_avg[%f] divisor[%f] fuel[%f] fuel_f[%f] d_fuel[%f] d_fuel_mBt[%f] act_rate[%f] act_rate_f[%f] limit[%f]",
        --     elapsed_s, data.tps, tps_avg, elapsed_s * tps_avg, data.fuel, _spctl.fuel_filt.get(), d_fuel, d_fuel_mBt, data.act_rate, _spctl.rate_filt.get(), limit))

        _spctl.last_fuel_filt = _spctl.fuel_filt.get()
    elseif plc_state.auto_ctl and _spctl.fuel_limit_en then
        if tick % 5 == 0 then
            fuel_fill = reactor.getFuelFilledPercentage()
        end
    end

    -- change state per fuel fill
    if fuel_fill then
        if (fuel_fill > FUEL_LIMIT_RELEASE) and (_spctl.fuel_monitoring or _spctl.fuel_limiting) then
            if _spctl.fuel_limiting and not plc_state.limit_force_ramp then
                log.info("SPCTL: forcing auto commands to be ramped for burn limit recovery (limit released)")
                plc_state.limit_force_ramp = true
            end

            _spctl.fuel_monitoring = false
            _spctl.fuel_limiting = false

            limits.reportable_max_burn = false
            limits.fuel_max_burn = math.huge

            log.info("SPCTL: monitoring fuel terminated / limit released")
        elseif _spctl.fuel_monitoring and (not _spctl.fuel_limiting) and (fuel_fill < FUEL_LIMIT_START) then
            _spctl.fuel_limiting = true

            log.info("SPCTL: fuel limit engaged")
        elseif (not _spctl.fuel_monitoring) and (fuel_fill < FUEL_LIMIT_INIT) then
            _spctl.fuel_monitoring = true

            _spctl.last_mon_check = util.time_s()

            _spctl.fuel_filt.reset()
            _spctl.rate_filt.reset()
            _spctl.tick_filt.reset()

            log.info("SPCTL: started monitoring fuel statistics, approaching limiting threshold")
        end
    end
end

--#endregion

-- update setpoint controller
---@param reactor FissionReactor
---@param tick integer tick counter
---@param nom_elapsed_s number nominal iteration elapsed time reference
function spctl.update(reactor, tick, nom_elapsed_s)
    _spctl.new_br = nil

    local update_5Hz = tick % 2 == 0

    -- grab all data in one tick rather than 2+ times
    if _spctl.fuel_monitoring or (_spctl.next_state ~= STATES.STOPPED) or (databus.en_diag and update_5Hz) then
        local t_start, t_end = util.time_ms(), 0

        parallel.waitForAll(
            function () _spctl.data.tps        = util.get_tps() end,
            function () _spctl.data.burn_rate  = reactor.getBurnRate() end,
            function () _spctl.data.ccool_fill = reactor.getCoolantFilledPercentage() end,
            function () _spctl.data.fuel_fill  = reactor.getFuelFilledPercentage() end,
            function () _spctl.data.act_rate   = reactor.getActualBurnRate() end,
            function ()
                _spctl.data.fuel = (reactor.getFuel() or { amount = nil }).amount
                t_end            = util.time_ms()
            end
        )

        _spctl.data.tick_time = t_end - t_start
    end

    -- ramping control
    if update_5Hz then
        ramp_update(reactor, nom_elapsed_s)
    end

    -- fuel rate limiting
    if plc_state.auto_ctl and _spctl.fuel_limit_en then
        update_fuel_rate_limiting(tick, reactor)
    elseif _spctl.fuel_monitoring then
        limits.reportable_max_burn = false
        limits.fuel_max_burn       = math.huge

        _spctl.fuel_monitoring = false
        _spctl.fuel_limiting   = false
    end

    -- apply new rate if set, otherwise limit periodically if needed
    if _spctl.new_br then
        reactor.setBurnRate(math.min(_spctl.new_br, limits.fuel_max_burn))
    elseif plc_state.auto_ctl and _spctl.fuel_limiting and update_5Hz and (_spctl.next_state == STATES.STOPPED) then
        local cur_br = _spctl.data.burn_rate

        if cur_br > limits.fuel_max_burn then
            reactor.setBurnRate(math.min(setpoints.burn_rate, limits.fuel_max_burn))
        elseif cur_br < setpoints.burn_rate then
            -- we need to bring the rate back up but don't want it to jump agressively
            -- use the ramping controller for this instead
            if not (plc_state.limit_force_ramp and setpoints.burn_rate_en) then
                log.info("SPCTL: initiating ramped fuel burn limiting recovery")
                plc_state.limit_force_ramp = true
                setpoints.burn_rate_en = true
            end
        end
    end

    -- record diagnostics shown on the front panel, only when that page is active
    if update_5Hz and databus.en_diag then
        local publish = databus.ps.publish

        publish("spctl_ramp_active", setpoints.burn_rate_en)

        publish("spctl_ramp_sp", setpoints.burn_rate)

        publish("spctl_ramp_init", _spctl.next_state == STATES.INIT)
        publish("spctl_ramp_sru", _spctl.next_state == STATES.SLOW_RAMP_UP)
        publish("spctl_ramp_srd", _spctl.next_state == STATES.SLOW_RAMP_DOWN)
        publish("spctl_ramp_sw", _spctl.next_state == STATES.STABLE_WAIT)
        publish("spctl_ramp_cm", _spctl.next_state == STATES.CCOOL_MON)
        publish("spctl_ramp_fru", _spctl.next_state == STATES.FAST_RAMP_UP)
        publish("spctl_ramp_frd", _spctl.next_state == STATES.FAST_RAMP_DOWN)

        publish("spctl_limit_mon", _spctl.fuel_monitoring)
        publish("spctl_limit_lim", _spctl.fuel_limiting)
        publish("spctl_limit_fr", plc_state.limit_force_ramp)

        publish("spctl_limit_limit", limits.fuel_max_burn)

        publish("spctl_limit_fuel_filt", _spctl.fuel_filt.get())
        publish("spctl_limit_rate_filt", _spctl.rate_filt.get())
        publish("spctl_limit_tick_filt", _spctl.tick_filt.get())

        publish("spctl_data_tps", _spctl.data.tps)
        publish("spctl_data_tick", _spctl.data.tick_time)
    end
end

return spctl

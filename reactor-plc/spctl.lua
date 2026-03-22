local log  = require("scada-common.log")
local util = require("scada-common.util")

local plc  = require("reactor-plc.plc")

local SLOW_RAMP_mB_s     = 5.0
local FAST_SWITCH_mB_s   = 40.0
local FAST_MAX_PERCENT_s = 0.02

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
    fast_ramp_en = false,

    max_br = 0.0,
    last_sp = 0.0,
    last_ccool = 0.0,

    last_change = 0,
    next_state = STATES.STOPPED, ---@type RAMP_STATES
    last_state = STATES.STOPPED  ---@type RAMP_STATES
}

local rps       = nil ---@type rps
local setpoints = nil ---@type plc_setpoints

-- initialize with shared memory data
---@param smem plc_shared_memory
function spctl.init(smem)
    rps       = smem.plc_sys.rps
    setpoints = smem.setpoints

    _spctl.fast_ramp_en = plc.config.FastRamp
end

-- initialize ramping, or set right away if acceptable
---@param reactor FissionReactor reactor
---@param cur_br number requested burn rate
local function ramp_init(reactor, cur_br)
    _spctl.last_sp = setpoints.burn_rate

    -- update without ramp if <= 2.5 mB/t change
    if math.abs(setpoints.burn_rate - cur_br) > 2.5 then
        log.debug(util.c("SPCTL: starting burn rate ramp from ", cur_br, " mB/t to ", setpoints.burn_rate, " mB/t"))

        _spctl.last_change = os.clock()
        _spctl.next_state  = STATES.INIT
    else
        log.debug(util.c("SPCTL: setting burn rate directly to ", setpoints.burn_rate, " mB/t"))
        reactor.setBurnRate(setpoints.burn_rate)
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
---@param reactor FissionReactor reactor
---@param cur_br number current burn rate
---@param cur_ccool number coolant filled percentage (0 to 1)
---@param elapsed_s number seconds elapsed in the ramp
local function ramp_run(reactor, cur_br, cur_ccool, elapsed_s)
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
        local step   = scaler * _spctl.max_br

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
        local step   = scaler * _spctl.max_br

        -- minimum is the slow rate, maintain old behavior
        step = math.max(SLOW_RAMP_mB_s * elapsed_s, step)

        -- don't fall below the setpoint
        new_br = math.max(cur_br - step, setpoints.burn_rate)

        -- log.debug(util.sprintf("SPCTL: scaler[%f] cur_ccool[%f] step[%f] new_br[%f]", scaler, cur_ccool, step, new_br))
    end

    -- set the burn rate
    reactor.setBurnRate(new_br)

    if new_br ~= setpoints.burn_rate then
        -- update tracked values and continue
        _spctl.last_ccool = cur_ccool
    else
        new_state = STATES.STOPPED
    end

    -- state change management
    if new_state ~= state then
        log.debug("SPCTL: state changed to " .. (STATE_NAMES[new_state] or "UNKNOWN"))

        _spctl.next_state  = new_state
        _spctl.last_change = now
    end
end

-- update setpoint controller
---@param reactor FissionReactor
---@param elapsed_s integer iteration elapsed time reference
function spctl.update(reactor, elapsed_s)
    -- check if we should start ramping
    if setpoints.burn_rate_en and (setpoints.burn_rate ~= _spctl.last_sp) and rps.is_active() then
        local cur_br = reactor.getBurnRate()
        _spctl.max_br = reactor.getMaxBurnRate()

        if (type(cur_br) == "number") and (type(_spctl.max_br) == "number") and (setpoints.burn_rate ~= cur_br) then
            ramp_init(reactor, cur_br)
        end
    end

    -- minimize operations when not running
    if _spctl.next_state ~= STATES.STOPPED then
        -- adjust burn rate (setpoints.burn_rate)
        if setpoints.burn_rate_en then
            local cur_br, cur_ccool = 0, 0

            parallel.waitForAll(
                function () cur_br = reactor.getBurnRate() end,
                function () cur_ccool = reactor.getCoolantFilledPercentage() end
            )

            if not rps.is_active() then
                log.info("SPCTL: ramping aborted (reactor inactive)")
                setpoints.burn_rate_en = false
                ramp_reset()
            -- we yielded, check enable again
            elseif setpoints.burn_rate_en then
                if (type(cur_br) == "number") and (type(cur_ccool) == "number") then
                    ramp_run(reactor, cur_br, cur_ccool, elapsed_s)
                else
                    log.error(util.c("SPCTL: skipped running loop due to bad data (cur_br=", cur_br, ",cur_ccool=", cur_ccool, ")"))
                end
            else
                log.info("SPCTL: ramping cancelled")
                ramp_reset()
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

return spctl

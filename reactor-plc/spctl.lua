local log  = require("scada-common.log")
local util = require("scada-common.util")


local SLOW_RAMP_mB_s   = 5.0
local FAST_SWITCH_mB_s = 40.0
local FAST_MAX_PERCENT_s = 0.02

local spctl = {}

---@enum RAMP_STATES
local STATES = {
    STOPPED = 0,
    SLOW_RAMP = 1,
    STABLE_WAIT = 2,
    CCOOL_MON = 3,
    FAST_RAMP = 4,
    RUNNING = 5
}

local _spctl = {
    run = false,

    max_br = 0.0,
    last_sp = 0.0,
    last_ccool = 0.0,

    last_change = 0,
    next_state = STATES.STOPPED, ---@type RAMP_STATES
    last_state = STATES.STOPPED  ---@type RAMP_STATES
}

local rps       = nil   ---@type rps
local setpoints = nil   ---@type plc_setpoints

-- initialize with shared memory data
---@param smem plc_shared_memory
function spctl.init(smem)
    rps       = smem.plc_sys.rps
    setpoints = smem.setpoints
end

-- initialize ramping, or set right away if acceptable
---@param reactor table
---@param cur_br number
local function ramp_init(reactor, cur_br)
    _spctl.last_sp = setpoints.burn_rate

    -- update without ramp if <= 2.5 mB/t increase
    -- no need to ramp down, as the ramp up poses the safety risks
    _spctl.run = (setpoints.burn_rate - cur_br) > 2.5

    if _spctl.run then
        log.debug(util.c("SPCTL: starting burn rate ramp from ", cur_br, " mB/t to ", setpoints.burn_rate, " mB/t"))

        _spctl.last_change = os.clock()
        _spctl.next_state = util.trinary(cur_br >= FAST_SWITCH_mB_s, STATES.STABLE_WAIT, STATES.SLOW_RAMP)
    else
        log.debug(util.c("SPCTL: setting burn rate directly to ", setpoints.burn_rate, " mB/t"))
        reactor.setBurnRate(setpoints.burn_rate)
    end
end

-- reset states and last value tracking
local function ramp_reset()
    _spctl.last_sp = 0
    _spctl.last_ccool = 0

    _spctl.next_state = STATES.STOPPED
    _spctl.last_state = STATES.STOPPED
end

local function ramp_run(reactor, cur_br, cur_ccool, elapsed_s)
    local new_br = cur_br

    local now = os.clock()

    local state     = _spctl.next_state
    local new_state = _spctl.next_state
    local time      = now - _spctl.last_change

    if state == STATES.SLOW_RAMP then
        if setpoints.burn_rate > cur_br then
            -- need to ramp up
            new_br = cur_br + (SLOW_RAMP_mB_s * elapsed_s)
            if new_br > setpoints.burn_rate then new_br = setpoints.burn_rate end
        else
            -- need to ramp down
            new_br = cur_br - (SLOW_RAMP_mB_s * elapsed_s)
            if new_br < setpoints.burn_rate then new_br = setpoints.burn_rate end
        end

        -- transition out of slow ramp after hitting the limit
        if new_br >= FAST_SWITCH_mB_s then
            new_br = FAST_SWITCH_mB_s

            new_state = STATES.CCOOL_MON
        end
    elseif state == STATES.STABLE_WAIT then
        -- wait 2 seconds for stability
        if time >= 2 then
            new_state = STATES.CCOOL_MON
        end
    elseif state == STATES.CCOOL_MON then
        -- don't move on until coolant is okay
        if cur_ccool >= _spctl.last_ccool then
            new_state = STATES.FAST_RAMP
        end
    elseif state == STATES.FAST_RAMP then
        local scaler  = math.min(FAST_MAX_PERCENT_s, FAST_MAX_PERCENT_s * (time / 5.0))
        local ccool_d = cur_ccool - _spctl.last_ccool

        local step = math.max(0, (scaler * _spctl.max_br) + (ccool_d / 100000.0))

        new_br = math.min(cur_br + step, setpoints.burn_rate)

        log.debug(util.sprintf("SPCTL: scaler[%f] ccool_d[%f] cur_ccool[%f] step[%f] new_br[%f]", scaler, ccool_d / 100000, cur_ccool, step, new_br))
    end

    -- set the burn rate
    reactor.setBurnRate(new_br)

    -- state change and other status management

    _spctl.run = new_br ~= setpoints.burn_rate

    if _spctl.run then
        -- update tracked values
        _spctl.last_ccool = cur_ccool
    else
        new_state = STATES.STOPPED
    end

    if new_state ~= state then
        log.debug("SPCTL: state changed to " .. new_state)
        _spctl.next_state  = new_state
        _spctl.last_change = now
    end
end

-- update setpoint controller
---@param reactor table
---@param elapsed_s integer iteration elapsed time reference
function spctl.update(reactor, elapsed_s)
    -- check if we should start ramping
    if setpoints.burn_rate_en and (setpoints.burn_rate ~= _spctl.last_sp) then
        local cur_br = reactor.getBurnRate()
        _spctl.max_br = reactor.getMaxBurnRate()

        if (type(cur_br) == "number") and (setpoints.burn_rate ~= cur_br) and rps.is_active() then
            ramp_init(reactor, cur_br)
        end
    end

    -- minimize operations when not running
    if _spctl.run then
        -- clear, evaluate later if we should keep running
        _spctl.run = false

        -- adjust burn rate (setpoints.burn_rate)
        if setpoints.burn_rate_en then
            if rps.is_active() then
                local cur_br, cur_ccool = 0, 0

                parallel.waitForAll(
                    function () cur_br = reactor.getBurnRate() end,
                    function () cur_ccool = reactor.getCoolantFilledPercentage() end
                )

                -- we yielded, check enable again
                if setpoints.burn_rate_en and (type(cur_br) == "number") and (cur_br ~= setpoints.burn_rate) then
                    ramp_run(reactor, cur_br, cur_ccool, elapsed_s)
                end
            else
                log.debug("SPCTL: ramping aborted (reactor inactive)")
                setpoints.burn_rate_en = false
            end
        end
    elseif setpoints.burn_rate_en then
        log.debug(util.c("SPCTL: ramping completed (setpoint of ", setpoints.burn_rate, " mB/t)"))
        setpoints.burn_rate_en = false
    end

    -- if ramping completed or was aborted, reset ramp states
    if not setpoints.burn_rate_en then ramp_reset() end
end

return spctl

local log  = require("scada-common.log")
local util = require("scada-common.util")


local BURN_RATE_RAMP_mB_s = 5.0

local spctl = {}

local _spctl = {
    run = false,
    last_sp = 0.0
}

local rps       = nil   ---@type rps
local setpoints = nil   ---@type plc_setpoints

-- initialize with shared memory data
---@param smem plc_shared_memory
function spctl.init(smem)
    rps       = smem.plc_sys.rps
    setpoints = smem.setpoints
end

-- update setpoint controller
---@param reactor table
---@param elapsed_s integer iteration elapsed time reference
function spctl.update(reactor, elapsed_s)
    -- check if we should start ramping
    if setpoints.burn_rate_en and (setpoints.burn_rate ~= _spctl.last_sp) then
        local cur_burn_rate = reactor.getBurnRate()

        if (type(cur_burn_rate) == "number") and (setpoints.burn_rate ~= cur_burn_rate) and rps.is_active() then
            _spctl.last_sp = setpoints.burn_rate

            -- update without ramp if <= 2.5 mB/t increase
            -- no need to ramp down, as the ramp up poses the safety risks
            _spctl.run = (setpoints.burn_rate - cur_burn_rate) > 2.5

            if _spctl.run then
                log.debug(util.c("SPCTL: starting burn rate ramp from ", cur_burn_rate, " mB/t to ", setpoints.burn_rate, " mB/t"))
            else
                log.debug(util.c("SPCTL: setting burn rate directly to ", setpoints.burn_rate, " mB/t"))
                reactor.setBurnRate(setpoints.burn_rate)
            end
        end
    end

    -- only check I/O if active to save on processing time
    if _spctl.run then
        -- clear so we can later evaluate if we should keep _spctl.run
        _spctl.run = false

        -- adjust burn rate (setpoints.burn_rate)
        if setpoints.burn_rate_en then
            if rps.is_active() then
                local current_burn_rate = reactor.getBurnRate()

                -- we yielded, check enable again
                if setpoints.burn_rate_en and (type(current_burn_rate) == "number") and (current_burn_rate ~= setpoints.burn_rate) then
                    -- calculate new burn rate
                    local new_burn_rate ---@type number

                    if setpoints.burn_rate > current_burn_rate then
                        -- need to ramp up
                        new_burn_rate = current_burn_rate + (BURN_RATE_RAMP_mB_s * elapsed_s)
                        if new_burn_rate > setpoints.burn_rate then new_burn_rate = setpoints.burn_rate end
                    else
                        -- need to ramp down
                        new_burn_rate = current_burn_rate - (BURN_RATE_RAMP_mB_s * elapsed_s)
                        if new_burn_rate < setpoints.burn_rate then new_burn_rate = setpoints.burn_rate end
                    end

                    _spctl.run = _spctl.run or (new_burn_rate ~= setpoints.burn_rate)

                    -- set the burn rate
                    reactor.setBurnRate(new_burn_rate)
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

    -- if ramping completed or was aborted, reset last burn setpoint so that if it is requested again it will be re-attempted
    if not setpoints.burn_rate_en then _spctl.last_sp = 0 end

end

return spctl

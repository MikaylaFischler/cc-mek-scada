-- add this to psil:

--[[
    -- count the number of subscribers in this PSIL instance
    ---@return integer count
    function public.count()
        local c = 0
        for _, val in pairs(ic) do
            for _ = 1, #val.subscribers do c = c + 1 end
        end
        return c
    end
]]--


-- add this to coordinator iocontrol front panel heartbeat function:

--[[
if io.facility then
    local count = io.facility.ps.count()

    count = count + io.facility.env_d_ps.count()

    for x = 1, #io.facility.induction_ps_tbl do
        count = count + io.facility.induction_ps_tbl[x].count()
    end

    for x = 1, #io.facility.sps_ps_tbl do
        count = count + io.facility.sps_ps_tbl[x].count()
    end

    for x = 1, #io.facility.tank_ps_tbl do
        count = count + io.facility.tank_ps_tbl[x].count()
    end

    for i = 1, #io.units do
        local entry = io.units[i] ---@type ioctl_unit

        count = count + entry.unit_ps.count()

        for x = 1, #entry.boiler_ps_tbl do
            count = count + entry.boiler_ps_tbl[x].count()
        end

        for x = 1, #entry.turbine_ps_tbl do
            count = count + entry.turbine_ps_tbl[x].count()
        end

        for x = 1, #entry.tank_ps_tbl do
            count = count + entry.tank_ps_tbl[x].count()
        end
    end

    log.debug(count)
end
]]--

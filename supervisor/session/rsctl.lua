--
-- Redstone RTU Session I/O Controller
--

local rsio = require("scada-common.rsio")

local rsctl = {}

-- create a new redstone RTU I/O controller
---@nodiscard
---@param redstone_rtus table redstone RTU sessions
function rsctl.new(redstone_rtus)
    ---@class rs_controller
    local public = {}

    -- check if a redstone port has available connections
    ---@param port IO_PORT
    ---@return boolean
    function public.is_connected(port)
        for i = 1, #redstone_rtus do
            local db = redstone_rtus[i].get_db() ---@type redstone_session_db
            if db.io[port] ~= nil then return true end
        end

        return false
    end

    -- write to a digital redstone port (applies to all RTUs)
    ---@param port IO_PORT
    ---@param value boolean
    function public.digital_write(port, value)
        for i = 1, #redstone_rtus do
            local db = redstone_rtus[i].get_db() ---@type redstone_session_db
            local io = db.io[port]               ---@type rs_db_dig_io|nil
            if io ~= nil then io.write(value) end
        end
    end

    -- read a digital redstone port<br>
    -- this will read from the first one encountered if there are multiple, because there should not be multiple
    ---@param port IO_PORT
    ---@return boolean|nil
    function public.digital_read(port)
        for i = 1, #redstone_rtus do
            local db = redstone_rtus[i].get_db() ---@type redstone_session_db
            local io = db.io[port]               ---@type rs_db_dig_io|nil
            if io ~= nil then return io.read() end
        end
    end

    -- write to an analog redstone port (applies to all RTUs)
    ---@param port IO_PORT
    ---@param value number value
    ---@param min number minimum value for scaling 0 to 15
    ---@param max number maximum value for scaling 0 to 15
    function public.analog_write(port, value, min, max)
        for i = 1, #redstone_rtus do
            local db = redstone_rtus[i].get_db() ---@type redstone_session_db
            local io = db.io[port]               ---@type rs_db_ana_io|nil
            if io ~= nil then io.write(rsio.analog_write(value, min, max)) end
        end
    end

    return public
end

return rsctl

local rtu = require("rtu.rtu")
local rsio = require("scada-common.rsio")

local redstone_rtu = {}

local digital_read = rsio.digital_read
local digital_is_active = rsio.digital_is_active

-- create new redstone device
redstone_rtu.new = function ()
    local self = {
        rtu = rtu.init_unit()
    }

    -- get RTU interface
    local interface = self.rtu.interface()

    ---@class rtu_rs_device
    --- extends rtu_device; fields added manually to please Lua diagnostics
    local public = {
        io_count = interface.io_count,
        read_coil = interface.read_coil,
        read_di = interface.read_di,
        read_holding_reg = interface.read_holding_reg,
        read_input_reg = interface.read_input_reg,
        write_coil = interface.write_coil,
        write_holding_reg = interface.write_holding_reg
    }

    -- link digital input
    ---@param side string
    ---@param color integer
    public.link_di = function (side, color)
        local f_read = nil

        if color then
            f_read = function ()
                return digital_read(rs.testBundledInput(side, color))
            end
        else
            f_read = function ()
                return digital_read(rs.getInput(side))
            end
        end

        self.rtu.connect_di(f_read)
    end

    -- link digital output
    ---@param channel RS_IO
    ---@param side string
    ---@param color integer
    public.link_do = function (channel, side, color)
        local f_read = nil
        local f_write = nil

        if color then
            f_read = function ()
                return digital_read(colors.test(rs.getBundledOutput(side), color))
            end

            f_write = function (level)
                local output = rs.getBundledOutput(side)
                local active = digital_is_active(channel, level)

                if active then
                    colors.combine(output, color)
                else
                    colors.subtract(output, color)
                end

                rs.setBundledOutput(side, output)
            end
        else
            f_read = function ()
                return digital_read(rs.getOutput(side))
            end

            f_write = function (level)
                rs.setOutput(side, digital_is_active(channel, level))
            end
        end

        self.rtu.connect_coil(f_read, f_write)
    end

    -- link analog input
    ---@param side string
    public.link_ai = function (side)
        self.rtu.connect_input_reg(
            function ()
                return rs.getAnalogInput(side)
            end
        )
    end

    -- link analog output
    ---@param side string
    public.link_ao = function (side)
        self.rtu.connect_holding_reg(
            function ()
                return rs.getAnalogOutput(side)
            end,
            function (value)
                rs.setAnalogOutput(side, value)
            end
        )
    end

    return public
end

return redstone_rtu

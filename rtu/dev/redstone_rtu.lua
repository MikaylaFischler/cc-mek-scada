local rsio = require("scada-common.rsio")

local rtu  = require("rtu.rtu")

local redstone_rtu = {}

local IO_LVL = rsio.IO_LVL

local digital_read = rsio.digital_read
local digital_write = rsio.digital_write

-- create new redstone device
---@nodiscard
---@return rtu_rs_device interface, boolean faulted
function redstone_rtu.new()
    local unit = rtu.init_unit()

    -- get RTU interface
    local interface = unit.interface()

    -- extends rtu_device; fields added manually to please Lua diagnostics
    ---@class rtu_rs_device
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
    function public.link_di(side, color)
        local f_read    ---@type function

        if color then
            f_read = function ()
                return digital_read(rs.testBundledInput(side, color))
            end
        else
            f_read = function ()
                return digital_read(rs.getInput(side))
            end
        end

        unit.connect_di(f_read)
    end

    -- link digital output
    ---@param side string
    ---@param color integer
    function public.link_do(side, color)
        local f_read    ---@type function
        local f_write   ---@type function

        if color then
            f_read = function ()
                return digital_read(colors.test(rs.getBundledOutput(side), color))
            end

            f_write = function (level)
                if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
                    local output = rs.getBundledOutput(side)

                    if digital_write(level) then
                        output = colors.combine(output, color)
                    else
                        output = colors.subtract(output, color)
                    end

                    rs.setBundledOutput(side, output)
                end
            end
        else
            f_read = function ()
                return digital_read(rs.getOutput(side))
            end

            f_write = function (level)
                if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
                    rs.setOutput(side, digital_write(level))
                end
            end
        end

        unit.connect_coil(f_read, f_write)
    end

    -- link analog input
    ---@param side string
    function public.link_ai(side)
        unit.connect_input_reg(
            function ()
                return rs.getAnalogInput(side)
            end
        )
    end

    -- link analog output
    ---@param side string
    function public.link_ao(side)
        unit.connect_holding_reg(
            function ()
                return rs.getAnalogOutput(side)
            end,
            function (value)
                rs.setAnalogOutput(side, value)
            end
        )
    end

    return public, false
end

return redstone_rtu

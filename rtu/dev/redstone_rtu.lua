local rsio = require("scada-common.rsio")

local rtu  = require("rtu.rtu")

local redstone_rtu = {}

local IO_LVL = rsio.IO_LVL

local digital_read = rsio.digital_read
local digital_write = rsio.digital_write

-- create new redstone device
---@nodiscard
---@param relay? table optional redstone relay to use instead of the computer's redstone interface
---@return rtu_rs_device interface, boolean faulted
function redstone_rtu.new(relay)
    local unit = rtu.init_unit()

    -- physical interface to use
    local phy = relay or rs

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

    -- change the phy in use (a relay or rs)
    ---@param new_phy table
    function public.remount_phy(new_phy) phy = new_phy end

    -- NOTE: for runtime speed, inversion logic results in extra code here but less code when functions are called

    -- link digital input
    ---@param side string
    ---@param color integer
    ---@param invert boolean|nil
    ---@return integer count count of digital inputs
    function public.link_di(side, color, invert)
        local f_read ---@type function

        if color then
            if invert then
                f_read = function () return digital_read(not phy.testBundledInput(side, color)) end
            else
                f_read = function () return digital_read(phy.testBundledInput(side, color)) end
            end
        else
            if invert then
                f_read = function () return digital_read(not phy.getInput(side)) end
            else
                f_read = function () return digital_read(phy.getInput(side)) end
            end
        end

        return unit.connect_di(f_read)
    end

    -- link digital output
    ---@param side string
    ---@param color integer
    ---@param invert boolean|nil
    ---@return integer count count of digital outputs
    function public.link_do(side, color, invert)
        local f_read  ---@type function
        local f_write ---@type function

        if color then
            if invert then
                f_read = function () return digital_read(not colors.test(phy.getBundledOutput(side), color)) end

                f_write = function (level)
                    if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
                        local output = phy.getBundledOutput(side)

                        -- inverted conditions
                        if digital_write(level) then
                            output = colors.subtract(output, color)
                        else output = colors.combine(output, color) end

                        phy.setBundledOutput(side, output)
                    end
                end
            else
                f_read = function () return digital_read(colors.test(phy.getBundledOutput(side), color)) end

                f_write = function (level)
                    if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
                        local output = phy.getBundledOutput(side)

                        if digital_write(level) then
                            output = colors.combine(output, color)
                        else output = colors.subtract(output, color) end

                        phy.setBundledOutput(side, output)
                    end
                end
            end
        else
            if invert then
                f_read = function () return digital_read(not phy.getOutput(side)) end

                f_write = function (level)
                    if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
                        phy.setOutput(side, not digital_write(level))
                    end
                end
            else
                f_read = function () return digital_read(phy.getOutput(side)) end

                f_write = function (level)
                    if level ~= IO_LVL.FLOATING and level ~= IO_LVL.DISCONNECT then
                        phy.setOutput(side, digital_write(level))
                    end
                end
            end
        end

        return unit.connect_coil(f_read, f_write)
    end

    -- link analog input
    ---@param side string
    ---@return integer count count of analog inputs
    function public.link_ai(side)
        return unit.connect_input_reg(function () return phy.getAnalogInput(side) end)
    end

    -- link analog output
    ---@param side string
    ---@return integer count count of analog outputs
    function public.link_ao(side)
        return unit.connect_holding_reg(
            function () return phy.getAnalogOutput(side) end,
            function (value) phy.setAnalogOutput(side, value) end
        )
    end

    return public, false
end

return redstone_rtu

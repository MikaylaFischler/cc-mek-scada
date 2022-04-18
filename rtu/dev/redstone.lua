-- #REQUIRES rtu.lua
-- #REQUIRES rsio.lua
-- note: this RTU makes extensive use of the programming concept of closures

local digital_read = rsio.digital_read
local digital_is_active = rsio.digital_is_active

function redstone_rtu()
    local self = {
        rtu = rtu.rtu_init()
    }

    local rtu_interface = function ()
        return self.rtu
    end

    local link_di = function (channel, side, color)
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

    local link_do = function (channel, side, color)
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

    local link_ai = function (channel, side)
        self.rtu.connect_input_reg(
            function ()
                return rs.getAnalogInput(side)
            end
        )
    end

    local link_ao = function (channel, side)
        self.rtu.connect_holding_reg(
            function ()
                return rs.getAnalogOutput(side)
            end,
            function (value)
                rs.setAnalogOutput(side, value)
            end
        )
    end

    return {
        rtu_interface = rtu_interface,
        link_di = link_di,
        link_do = link_do,
        link_ai = link_ai,
        link_ao = link_ao
    }
end

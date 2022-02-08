-- #REQUIRES rtu.lua
-- note: this RTU makes extensive use of the programming concept of closures

function redstone_rtu()
    local self = {
        rtu = rtu_init()
    }

    local rtu_interface = function ()
        return self.rtu
    end

    local link_di = function (side, color)
        local f_read = nil

        if color then
            f_read = function ()
                return rs.testBundledInput(side, color)
            end
        else
            f_read = function ()
                return rs.getInput(side)
            end
        end
            
        self.rtu.connect_di(f_read)
    end

    local link_do = function (side, color)
        local f_read = nil
        local f_write = nil

        if color then
            f_read = function ()
                return colors.test(rs.getBundledOutput(side), color)
            end

            f_write = function (value)
                local output = rs.getBundledOutput(side)

                if value then
                    colors.combine(output, value)
                else
                    colors.subtract(output, value)
                end

                rs.setBundledOutput(side, output)
            end
        else
            f_read = function ()
                return rs.getOutput(side)
            end

            f_write = function (value)
                rs.setOutput(side, color)
            end
        end
            
        self.rtu.connect_coil(f_read, f_write)
    end

    local link_ai = function (side)
        self.rtu.connect_input_reg(
            function ()
                return rs.getAnalogInput(side)
            end
        )
    end

    local link_ao = function (side)
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

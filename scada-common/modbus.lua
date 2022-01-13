function modbus_init(rtu_dev)
    local self = {
        rtu = rtu_dev
    }

    function _1_read_coils(c_channel_start, count)
    end

    function _2_read_discrete_inputs(di_channel_start, count)
    end

    function _3_read_multiple_holding_registers(hr_channel_start, count)
    end
end

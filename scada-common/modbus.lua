-- modbus function codes
local MODBUS_FCODE = {
    READ_COILS = 0x01,
    READ_DISCRETE_INPUTS = 0x02,
    READ_MUL_HOLD_REGS = 0x03,
    READ_INPUT_REGS = 0x04,
    WRITE_SINGLE_COIL = 0x05,
    WRITE_SINGLE_HOLD_REG = 0x06,
    WRITE_MUL_COILS = 0x0F,
    WRITE_MUL_HOLD_REGS = 0x10,
    ERROR_FLAG = 0x80
}

-- modbus exception codes
local MODBUS_EXCODE = {
    ILLEGAL_FUNCTION = 0x01,
    ILLEGAL_DATA_ADDR = 0x02,
    ILLEGAL_DATA_VALUE = 0x03,
    SERVER_DEVICE_FAIL = 0x04,
    ACKNOWLEDGE = 0x05,
    SERVER_DEVICE_BUSY = 0x06,
    NEG_ACKNOWLEDGE = 0x07,
    MEMORY_PARITY_ERROR = 0x08,
    GATEWAY_PATH_UNAVAILABLE = 0x0A,
    GATEWAY_TARGET_TIMEOUT = 0x0B
}

-- new modbus comms handler object
function new(rtu_dev)
    local self = {
        rtu = rtu_dev
    }

    local _1_read_coils = function (c_addr_start, count)
        local readings = {}
        local access_fault = false
        local _, coils, _, _ = self.rtu.io_count()
        local return_ok = (c_addr_start + count) <= coils

        if return_ok then
            for i = 0, (count - 1) do
                readings[i], access_fault = self.rtu.read_coil(c_addr_start + i)

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                    break
                end
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    local _2_read_discrete_inputs = function (di_addr_start, count)
        local readings = {}
        local access_fault = false
        local discrete_inputs, _, _, _ = self.rtu.io_count()
        local return_ok = (di_addr_start + count) <= discrete_inputs
        
        if return_ok then
            for i = 0, (count - 1) do
                readings[i], access_fault = self.rtu.read_di(di_addr_start + i)

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                    break
                end
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    local _3_read_multiple_holding_registers = function (hr_addr_start, count)
        local readings = {}
        local access_fault = false
        local _, _, _, hold_regs = self.rtu.io_count()
        local return_ok = (hr_addr_start + count) <= hold_regs

        if return_ok then
            for i = 0, (count - 1) do
                readings[i], access_fault = self.rtu.read_holding_reg(hr_addr_start + i)

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                    break
                end
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    local _4_read_input_registers = function (ir_addr_start, count)
        local readings = {}
        local access_fault = false
        local _, _, input_regs, _ = self.rtu.io_count()
        local return_ok = (ir_addr_start + count) <= input_regs

        if return_ok then
            for i = 0, (count - 1) do
                readings[i], access_fault = self.rtu.read_input_reg(ir_addr_start + i)

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                    break
                end
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    local _5_write_single_coil = function (c_addr, value)
        local response = nil
        local _, coils, _, _ = self.rtu.io_count()
        local return_ok = c_addr <= coils

        if return_ok then
            local access_fault = self.rtu.write_coil(c_addr, value)

            if access_fault then
                return_ok = false
                readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        else
            response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, response
    end

    local _6_write_single_holding_register = function (hr_addr, value)
        local response = nil
        local _, _, _, hold_regs = self.rtu.io_count()
        local return_ok = hr_addr <= hold_regs
 
        if return_ok then
            local access_fault = self.rtu.write_holding_reg(hr_addr, value)

            if access_fault then
                return_ok = false
                readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        end

        return return_ok
    end

    local _15_write_multiple_coils = function (c_addr_start, values)
        local response = nil
        local _, coils, _, _ = self.rtu.io_count()
        local count = #values
        local return_ok = (c_addr_start + count) <= coils

        if return_ok then
            for i = 0, (count - 1) do
                local access_fault = self.rtu.write_coil(c_addr_start + i, values[i + 1])

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                    break
                end
            end
        end

        return return_ok, response
    end

    local _16_write_multiple_holding_registers = function (hr_addr_start, values)
        local response = nil
        local _, _, _, hold_regs = self.rtu.io_count()
        local count = #values
        local return_ok = (hr_addr_start + count) <= hold_regs

        if return_ok then
            for i = 0, (count - 1) do
                local access_fault = self.rtu.write_coil(hr_addr_start + i, values[i + 1])

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                    break
                end
            end
        end

        return return_ok, response
    end

    local handle_packet = function (packet)
        local return_code = true
        local response = nil
        local reply = packet

        if #packet.data == 2 then
            -- handle  by function code
            if packet.func_code == MODBUS_FCODE.READ_COILS then
                return_code, response = _1_read_coils(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
                return_code, response = _2_read_discrete_inputs(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
                return_code, response = _3_read_multiple_holding_registers(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_INPUT_REGISTERS then
                return_code, response = _4_read_input_registers(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_SINGLE_COIL then
                return_code, response = _5_write_single_coil(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_SINGLE_HOLD_REG then
                return_code, response = _6_write_single_holding_register(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_MUL_COILS then
                return_code, response = _15_write_multiple_coils(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_MUL_HOLD_REGS then
                return_code, response = _16_write_multiple_holding_registers(packet.data[1], packet.data[2])
            else
                -- unknown function
                return_code = false
                response = MODBUS_EXCODE.ILLEGAL_FUNCTION
            end
        else
            -- invalid length
            return_code = false
        end

        if return_code then
            -- default is to echo back
            if type(response) == "table" then
                reply.length = #response
                reply.data = response
            end
        else
            -- echo back with error flag
            reply.func_code = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)

            if type(response) == "nil" then
                reply.length = 0
                reply.data = {}
            elseif type(response) == "number" then
                reply.length = 1
                reply.data = { response }
            elseif type(response) == "table" then
                reply.length = #response
                reply.data = response
            end
        end

        return return_code, reply
    end

    return {
        handle_packet = handle_packet
    }
end

function modbus_packet()
    local self = {
        frame = nil,
        txn_id = txn_id,
        protocol = protocol,
        length = length,
        unit_id = unit_id,
        func_code = func_code,
        data = data
    }

    -- make a MODBUS packet
    local make = function (txn_id, protocol, length, unit_id, func_code, data)
        self.txn_id = txn_id
        self.protocol = protocol
        self.length = length
        self.unit_id = unit_id
        self.func_code = func_code
        self.data = data
    end

    -- decode a MODBUS packet from a SCADA frame
    local decode = function (frame)
        if frame then
            self.frame = frame
            
            local data = frame.data()
            local size_ok = #data ~= 6

            if size_ok then
                make(data[1], data[2], data[3], data[4], data[5], data[6])
            end

            return size_ok and self.protocol == comms.PROTOCOLS.MODBUS_TCP
        else
            log._debug("nil frame encountered", true)
            return false
        end
    end

    -- get this packet
    local get = function ()
        return {
            scada_frame = self.frame,
            txn_id = self.txn_id,
            protocol = self.protocol,
            length = self.length,
            unit_id = self.unit_id,
            func_code = self.func_code,
            data = self.data
        }
    end

    return {
        make = make,
        decode = decode,
        get = get
    }
end

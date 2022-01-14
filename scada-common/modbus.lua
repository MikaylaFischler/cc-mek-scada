-- #REQUIRES comms.lua

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

-- new modbus comms handler object
function modbus_init(rtu_dev)
    local self = {
        rtu = rtu_dev
    }

    local _1_read_coils = function (c_addr_start, count)
        local readings = {}
        local _, coils, _, _ = self.rtu.io_count()
        local return_ok = (c_addr_start + count) <= coils

        if return_ok then
            for i = 0, (count - 1) do
                readings[i] = self.rtu.read_coil(c_addr_start + i)
            end
        end

        return return_ok, readings
    end

    local _2_read_discrete_inputs = function (di_addr_start, count)
        local readings = {}
        local discrete_inputs, _, _, _ = self.rtu.io_count()
        local return_ok = (di_addr_start + count) <= discrete_inputs
        
        if return_ok then
            for i = 0, (count - 1) do
                readings[i] = self.rtu.read_di(di_addr_start + i)
            end
        end

        return return_ok, readings
    end

    local _3_read_multiple_holding_registers = function (hr_addr_start, count)
        local readings = {}
        local _, _, _, hold_regs = self.rtu.io_count()
        local return_ok = (hr_addr_start + count) <= hold_regs

        if return_ok then
            for i = 0, (count - 1) do
                readings[i] = self.rtu.read_holding_reg(hr_addr_start + i)
            end
        end

        return return_ok, readings
    end

    local _4_read_input_registers = function (ir_addr_start, count)
        local readings = {}
        local _, _, input_regs, _ = self.rtu.io_count()
        local return_ok = (ir_addr_start + count) <= input_regs

        if return_ok then
            for i = 0, (count - 1) do
                readings[i] = self.rtu.read_input_reg(ir_addr_start + i)
            end
        end

        return return_ok, readings
    end

    local _5_write_single_coil = function (c_addr, value)
        local _, coils, _, _ = self.rtu.io_count()
        local return_ok = c_addr <= coils
 
        if return_ok then
            self.rtu.write_coil(c_addr, value)
        end

        return return_ok
    end

    local _6_write_single_holding_register = function (hr_addr, value)
        local _, _, _, hold_regs = self.rtu.io_count()
        local return_ok = hr_addr <= hold_regs
 
        if return_ok then
            self.rtu.write_holding_reg(hr_addr, value)
        end

        return return_ok
    end

    local _15_write_multiple_coils = function (c_addr_start, values)
        local _, coils, _, _ = self.rtu.io_count()
        local count = #values
        local return_ok = (c_addr_start + count) <= coils

        if return_ok then
            for i = 0, (count - 1) do
                self.rtu.write_coil(c_addr_start + i, values[i + 1])
            end
        end

        return return_ok
    end

    local _16_write_multiple_holding_registers = function (hr_addr_start, values)
        local _, _, _, hold_regs = self.rtu.io_count()
        local count = #values
        local return_ok = (hr_addr_start + count) <= hold_regs

        if return_ok then
            for i = 0, (count - 1) do
                self.rtu.write_coil(hr_addr_start + i, values[i + 1])
            end
        end

        return return_ok
    end

    local handle_packet = function (packet)
        local return_code = true
        local readings = nil

        if #packet.data == 2 then
            -- handle  by function code
            if packet.func_code == MODBUS_FCODE.READ_COILS then
                return_code, readings = _1_read_coils(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
                return_code, readings = _2_read_discrete_inputs(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
                return_code, readings = _3_read_multiple_holding_registers(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_INPUT_REGISTERS then
                return_code, readings = _4_read_input_registers(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_SINGLE_COIL then
                return_code = _5_write_single_coil(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_SINGLE_HOLD_REG then
                return_code = _6_write_single_holding_register(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_MUL_COILS then
                return_code = _15_write_multiple_coils(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_MUL_HOLD_REGS then
                return_code = _16_write_multiple_holding_registers(packet.data[1], packet.data[2])
            else
                -- unknown function
                return_code = false
            end
        else
            -- invalid length
            return_code = false
        end

        if return_code then
            -- response (default is to echo back)
            response = packet
            if readings ~= nil then
                response.length = #readings
                response.data = readings
            end
        else
            -- echo back with error flag
            response = packet
            response.func_code = bit.bor(packet.func_code, ERROR_FLAG)
        end

        return return_code, response
    end

    return {
        handle_packet = handle_packet
    }
end

function modbus_packet()
    local self = {
        txn_id = txn_id,
        protocol = protocol,
        length = length,
        unit_id = unit_id,
        func_code = func_code,
        data = data
    }

    local receive = function (raw)
        local size_ok = #raw ~= 6

        if size_ok then
            set(raw[1], raw[2], raw[3], raw[4], raw[5], raw[6])
        end

        return size_ok and self.protocol == comms.PROTOCOLS.MODBUS_TCP
    end

    local set = function (txn_id, protocol, length, unit_id, func_code, data)
        self.txn_id = txn_id
        self.protocol = protocol
        self.length = length
        self.unit_id = unit_id
        self.func_code = func_code
        self.data = data
    end

    local get = function ()
        return {
            txn_id = self.txn_id,
            protocol = self.protocol,
            length = self.length,
            unit_id = self.unit_id,
            func_code = self.func_code,
            data = self.data
        }
    end
end

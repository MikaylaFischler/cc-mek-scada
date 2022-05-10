local comms = require("scada-common.comms")
local types = require("scada-common.types")

local modbus = {}

local MODBUS_FCODE = types.MODBUS_FCODE
local MODBUS_EXCODE = types.MODBUS_EXCODE

-- new modbus comms handler object
modbus.new = function (rtu_dev, use_parallel_read)
    local self = {
        rtu = rtu_dev,
        use_parallel = use_parallel_read
    }

    local insert = table.insert

    local _1_read_coils = function (c_addr_start, count)
        local tasks = {}
        local readings = {}
        local access_fault = false
        local _, coils, _, _ = self.rtu.io_count()
        local return_ok = ((c_addr_start + count) <= coils) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = c_addr_start + i - 1

                if self.use_parallel then
                    insert(tasks, function ()
                        local reading, fault = self.rtu.read_coil(addr)
                        if fault then access_fault = true else readings[i] = reading end
                    end)
                else
                    readings[i], access_fault = self.rtu.read_coil(addr)

                    if access_fault then
                        return_ok = false
                        readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                        break
                    end
                end
            end

            -- run parallel tasks if configured
            if self.use_parallel then
                parallel.waitForAll(table.unpack(tasks))

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                end
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    local _2_read_discrete_inputs = function (di_addr_start, count)
        local tasks = {}
        local readings = {}
        local access_fault = false
        local discrete_inputs, _, _, _ = self.rtu.io_count()
        local return_ok = ((di_addr_start + count) <= discrete_inputs) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = di_addr_start + i - 1

                if self.use_parallel then
                    insert(tasks, function ()
                        local reading, fault = self.rtu.read_di(addr)
                        if fault then access_fault = true else readings[i] = reading end
                    end)
                else
                    readings[i], access_fault = self.rtu.read_di(addr)

                    if access_fault then
                        return_ok = false
                        readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                        break
                    end
                end
            end

            -- run parallel tasks if configured
            if self.use_parallel then
                parallel.waitForAll(table.unpack(tasks))

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                end
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    local _3_read_multiple_holding_registers = function (hr_addr_start, count)
        local tasks = {}
        local readings = {}
        local access_fault = false
        local _, _, _, hold_regs = self.rtu.io_count()
        local return_ok = ((hr_addr_start + count) <= hold_regs) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = hr_addr_start + i - 1

                if self.use_parallel then
                    insert(tasks, function ()
                        local reading, fault = self.rtu.read_holding_reg(addr)
                        if fault then access_fault = true else readings[i] = reading end
                    end)
                else
                    readings[i], access_fault = self.rtu.read_holding_reg(addr)

                    if access_fault then
                        return_ok = false
                        readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                        break
                    end
                end
            end

            -- run parallel tasks if configured
            if self.use_parallel then
                parallel.waitForAll(table.unpack(tasks))

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                end
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    local _4_read_input_registers = function (ir_addr_start, count)
        local tasks = {}
        local readings = {}
        local access_fault = false
        local _, _, input_regs, _ = self.rtu.io_count()
        local return_ok = ((ir_addr_start + count) <= input_regs) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = ir_addr_start + i - 1

                if self.use_parallel then
                    insert(tasks, function ()
                        local reading, fault = self.rtu.read_input_reg(addr)
                        if fault then access_fault = true else readings[i] = reading end
                    end)
                else
                    readings[i], access_fault = self.rtu.read_input_reg(addr)

                    if access_fault then
                        return_ok = false
                        readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                        break
                    end
                end
            end

            -- run parallel tasks if configured
            if self.use_parallel then
                parallel.waitForAll(table.unpack(tasks))

                if access_fault then
                    return_ok = false
                    readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
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
                response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
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
                response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        else
            response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok
    end

    local _15_write_multiple_coils = function (c_addr_start, values)
        local response = nil
        local _, coils, _, _ = self.rtu.io_count()
        local count = #values
        local return_ok = ((c_addr_start + count) <= coils) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = c_addr_start + i - 1
                local access_fault = self.rtu.write_coil(addr, values[i])

                if access_fault then
                    return_ok = false
                    response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                    break
                end
            end
        else
            response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, response
    end

    local _16_write_multiple_holding_registers = function (hr_addr_start, values)
        local response = nil
        local _, _, _, hold_regs = self.rtu.io_count()
        local count = #values
        local return_ok = ((hr_addr_start + count) <= hold_regs) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = hr_addr_start + i - 1
                local access_fault = self.rtu.write_coil(addr, values[i])

                if access_fault then
                    return_ok = false
                    response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
                    break
                end
            end
        else
            response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, response
    end

    -- validate a request without actually executing it
    local check_request = function (packet)
        local return_code = true
        local response = { MODBUS_EXCODE.ACKNOWLEDGE }

        if #packet.data == 2 then
            -- handle  by function code
            if packet.func_code == MODBUS_FCODE.READ_COILS then
            elseif packet.func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
            elseif packet.func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
            elseif packet.func_code == MODBUS_FCODE.READ_INPUT_REGISTERS then
            elseif packet.func_code == MODBUS_FCODE.WRITE_SINGLE_COIL then
            elseif packet.func_code == MODBUS_FCODE.WRITE_SINGLE_HOLD_REG then
            elseif packet.func_code == MODBUS_FCODE.WRITE_MUL_COILS then
            elseif packet.func_code == MODBUS_FCODE.WRITE_MUL_HOLD_REGS then
            else
                -- unknown function
                return_code = false
                response = { MODBUS_EXCODE.ILLEGAL_FUNCTION }
            end
        else
            -- invalid length
            return_code = false
            response = { MODBUS_EXCODE.NEG_ACKNOWLEDGE }
        end

        -- default is to echo back
        local func_code = packet.func_code
        if not return_code then
            -- echo back with error flag
            func_code = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)
        end

        -- create reply
        local reply = comms.modbus_packet()
        reply.make(packet.txn_id, packet.unit_id, func_code, response)

        return return_code, reply
    end

    -- handle a MODBUS TCP packet and generate a reply
    local handle_packet = function (packet)
        local return_code = true
        local response = nil

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

        -- default is to echo back
        local func_code = packet.func_code
        if not return_code then
            -- echo back with error flag
            func_code = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)

            if type(response) == "nil" then
                response = { }
            elseif type(response) == "number" then
                response = { response }
            elseif type(response) == "table" then
                response = response
            end
        end

        -- create reply
        local reply = comms.modbus_packet()
        reply.make(packet.txn_id, packet.unit_id, func_code, response)

        return return_code, reply
    end

    -- return a SERVER_DEVICE_BUSY error reply
    local reply__srv_device_busy = function (packet)
        -- reply back with error flag and exception code
        local reply = comms.modbus_packet()
        local fcode = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)
        local data = { MODBUS_EXCODE.SERVER_DEVICE_BUSY }
        reply.make(packet.txn_id, packet.unit_id, fcode, data)
        return reply
    end

    -- return a NEG_ACKNOWLEDGE error reply
    local reply__neg_ack = function (packet)
        -- reply back with error flag and exception code
        local reply = comms.modbus_packet()
        local fcode = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)
        local data = { MODBUS_EXCODE.NEG_ACKNOWLEDGE }
        reply.make(packet.txn_id, packet.unit_id, fcode, data)
        return reply
    end

    -- return a GATEWAY_PATH_UNAVAILABLE error reply
    local reply__gw_unavailable = function (packet)
        -- reply back with error flag and exception code
        local reply = comms.modbus_packet()
        local fcode = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)
        local data = { MODBUS_EXCODE.GATEWAY_PATH_UNAVAILABLE }
        reply.make(packet.txn_id, packet.unit_id, fcode, data)
        return reply
    end

    return {
        check_request = check_request,
        handle_packet = handle_packet,
        reply__srv_device_busy = reply__srv_device_busy,
        reply__neg_ack = reply__neg_ack,
        reply__gw_unavailable = reply__gw_unavailable
    }
end

return modbus

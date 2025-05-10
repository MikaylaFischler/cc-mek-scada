local comms = require("scada-common.comms")
local types = require("scada-common.types")

local modbus = {}

local MODBUS_FCODE = types.MODBUS_FCODE
local MODBUS_EXCODE = types.MODBUS_EXCODE

-- new modbus comms handler object
---@nodiscard
---@param rtu_dev rtu_device|rtu_rs_device RTU device
---@param use_parallel_read boolean whether or not to use parallel calls when reading
function modbus.new(rtu_dev, use_parallel_read)
    local insert = table.insert

    -- read a span of coils (digital outputs)<br>
    -- returns a table of readings or a MODBUS_EXCODE error code
    ---@nodiscard
    ---@param c_addr_start integer
    ---@param count integer
    ---@return boolean ok, table|MODBUS_EXCODE readings
    local function _1_read_coils(c_addr_start, count)
        local tasks = {}
        local readings = {} ---@type table|MODBUS_EXCODE
        local access_fault = false
        local _, coils, _, _ = rtu_dev.io_count()
        local return_ok = ((c_addr_start + count) <= (coils + 1)) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = c_addr_start + i - 1

                if use_parallel_read then
                    insert(tasks, function ()
                        local reading, fault = rtu_dev.read_coil(addr)
                        if fault then access_fault = true else readings[i] = reading end
                    end)
                else
                    readings[i], access_fault = rtu_dev.read_coil(addr)
                    if access_fault then break end
                end
            end

            -- run parallel tasks if configured
            if use_parallel_read then
                parallel.waitForAll(table.unpack(tasks))
            end

            if access_fault or #readings ~= count then
                return_ok = false
                readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    -- read a span of discrete inputs (digital inputs)<br>
    -- returns a table of readings or a MODBUS_EXCODE error code
    ---@nodiscard
    ---@param di_addr_start integer
    ---@param count integer
    ---@return boolean ok, table|MODBUS_EXCODE readings
    local function _2_read_discrete_inputs(di_addr_start, count)
        local tasks = {}
        local readings = {} ---@type table|MODBUS_EXCODE
        local access_fault = false
        local discrete_inputs, _, _, _ = rtu_dev.io_count()
        local return_ok = ((di_addr_start + count) <= (discrete_inputs + 1)) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = di_addr_start + i - 1

                if use_parallel_read then
                    insert(tasks, function ()
                        local reading, fault = rtu_dev.read_di(addr)
                        if fault then access_fault = true else readings[i] = reading end
                    end)
                else
                    readings[i], access_fault = rtu_dev.read_di(addr)
                    if access_fault then break end
                end
            end

            -- run parallel tasks if configured
            if use_parallel_read then
                parallel.waitForAll(table.unpack(tasks))
            end

            if access_fault or #readings ~= count then
                return_ok = false
                readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    -- read a span of holding registers (analog outputs)<br>
    -- returns a table of readings or a MODBUS_EXCODE error code
    ---@nodiscard
    ---@param hr_addr_start integer
    ---@param count integer
    ---@return boolean ok, table|MODBUS_EXCODE readings
    local function _3_read_multiple_holding_registers(hr_addr_start, count)
        local tasks = {}
        local readings = {} ---@type table|MODBUS_EXCODE
        local access_fault = false
        local _, _, _, hold_regs = rtu_dev.io_count()
        local return_ok = ((hr_addr_start + count) <= (hold_regs + 1)) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = hr_addr_start + i - 1

                if use_parallel_read then
                    insert(tasks, function ()
                        local reading, fault = rtu_dev.read_holding_reg(addr)
                        if fault then access_fault = true else readings[i] = reading end
                    end)
                else
                    readings[i], access_fault = rtu_dev.read_holding_reg(addr)
                    if access_fault then break end
                end
            end

            -- run parallel tasks if configured
            if use_parallel_read then
                parallel.waitForAll(table.unpack(tasks))
            end

            if access_fault or #readings ~= count then
                return_ok = false
                readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    -- read a span of input registers (analog inputs)<br>
    -- returns a table of readings or a MODBUS_EXCODE error code
    ---@nodiscard
    ---@param ir_addr_start integer
    ---@param count integer
    ---@return boolean ok, table|MODBUS_EXCODE readings
    local function _4_read_input_registers(ir_addr_start, count)
        local tasks = {}
        local readings = {} ---@type table|MODBUS_EXCODE
        local access_fault = false
        local _, _, input_regs, _ = rtu_dev.io_count()
        local return_ok = ((ir_addr_start + count) <= (input_regs + 1)) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = ir_addr_start + i - 1

                if use_parallel_read then
                    insert(tasks, function ()
                        local reading, fault = rtu_dev.read_input_reg(addr)
                        if fault then access_fault = true else readings[i] = reading end
                    end)
                else
                    readings[i], access_fault = rtu_dev.read_input_reg(addr)
                    if access_fault then break end
                end
            end

            -- run parallel tasks if configured
            if use_parallel_read then
                parallel.waitForAll(table.unpack(tasks))
            end

            if access_fault or #readings ~= count then
                return_ok = false
                readings = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        else
            readings = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, readings
    end

    -- write a single coil (digital output)
    ---@nodiscard
    ---@param c_addr integer
    ---@param value any
    ---@return boolean ok, MODBUS_EXCODE
    local function _5_write_single_coil(c_addr, value)
        local response = MODBUS_EXCODE.OK
        local _, coils, _, _ = rtu_dev.io_count()
        local return_ok = c_addr <= coils

        if return_ok then
            local access_fault = rtu_dev.write_coil(c_addr, value)

            if access_fault then
                return_ok = false
                response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        else
            response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, response
    end

    -- write a single holding register (analog output)
    ---@nodiscard
    ---@param hr_addr integer
    ---@param value any
    ---@return boolean ok, MODBUS_EXCODE
    local function _6_write_single_holding_register(hr_addr, value)
        local response = MODBUS_EXCODE.OK
        local _, _, _, hold_regs = rtu_dev.io_count()
        local return_ok = hr_addr <= hold_regs

        if return_ok then
            local access_fault = rtu_dev.write_holding_reg(hr_addr, value)

            if access_fault then
                return_ok = false
                response = MODBUS_EXCODE.SERVER_DEVICE_FAIL
            end
        else
            response = MODBUS_EXCODE.ILLEGAL_DATA_ADDR
        end

        return return_ok, response
    end

    -- write multiple coils (digital outputs)
    ---@nodiscard
    ---@param c_addr_start integer
    ---@param values any
    ---@return boolean ok, MODBUS_EXCODE
    local function _15_write_multiple_coils(c_addr_start, values)
        local response = MODBUS_EXCODE.OK
        local _, coils, _, _ = rtu_dev.io_count()
        local count = #values
        local return_ok = ((c_addr_start + count) <= (coils + 1)) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = c_addr_start + i - 1
                local access_fault = rtu_dev.write_coil(addr, values[i])

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

    -- write multiple holding registers (analog outputs)
    ---@nodiscard
    ---@param hr_addr_start integer
    ---@param values any
    ---@return boolean ok, MODBUS_EXCODE
    local function _16_write_multiple_holding_registers(hr_addr_start, values)
        local response = MODBUS_EXCODE.OK
        local _, _, _, hold_regs = rtu_dev.io_count()
        local count = #values
        local return_ok = ((hr_addr_start + count) <= (hold_regs + 1)) and (count > 0)

        if return_ok then
            for i = 1, count do
                local addr = hr_addr_start + i - 1
                local access_fault = rtu_dev.write_holding_reg(addr, values[i])

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

    ---@class modbus
    local public = {}

    -- validate a request without actually executing it
    ---@nodiscard
    ---@param packet modbus_frame
    ---@return boolean return_code, modbus_packet reply
    function public.check_request(packet)
        local return_code = true
        local response = { MODBUS_EXCODE.ACKNOWLEDGE }

        if packet.length == 2 then
            -- handle  by function code
            if packet.func_code == MODBUS_FCODE.READ_COILS then
            elseif packet.func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
            elseif packet.func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
            elseif packet.func_code == MODBUS_FCODE.READ_INPUT_REGS then
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

        -- default is to echo back<br>
        -- but here we echo back with error flag, on success the "error" will be acknowledgement
        local func_code = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)

        -- create reply
        local reply = comms.modbus_packet()
        reply.make(packet.txn_id, packet.unit_id, func_code, response)

        return return_code, reply
    end

    -- handle a MODBUS TCP packet and generate a reply
    ---@nodiscard
    ---@param packet modbus_frame
    ---@return boolean return_code, modbus_packet reply
    function public.handle_packet(packet)
        local return_code   ---@type boolean
        local response      ---@type table|MODBUS_EXCODE

        if packet.length >= 2 then
            -- handle  by function code
            if packet.func_code == MODBUS_FCODE.READ_COILS then
                return_code, response = _1_read_coils(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_DISCRETE_INPUTS then
                return_code, response = _2_read_discrete_inputs(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_MUL_HOLD_REGS then
                return_code, response = _3_read_multiple_holding_registers(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.READ_INPUT_REGS then
                return_code, response = _4_read_input_registers(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_SINGLE_COIL then
                return_code, response = _5_write_single_coil(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_SINGLE_HOLD_REG then
                return_code, response = _6_write_single_holding_register(packet.data[1], packet.data[2])
            elseif packet.func_code == MODBUS_FCODE.WRITE_MUL_COILS then
                return_code, response = _15_write_multiple_coils(packet.data[1], { table.unpack(packet.data, 2, packet.length) })
            elseif packet.func_code == MODBUS_FCODE.WRITE_MUL_HOLD_REGS then
                return_code, response = _16_write_multiple_holding_registers(packet.data[1], { table.unpack(packet.data, 2, packet.length) })
            else
                -- unknown function
                return_code = false
                response = MODBUS_EXCODE.ILLEGAL_FUNCTION
            end
        else
            -- invalid length
            return_code = false
            response = MODBUS_EXCODE.NEG_ACKNOWLEDGE
        end

        -- default is to echo back
        local func_code = packet.func_code
        if not return_code then
            -- echo back with error flag
            func_code = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)
        end

        if type(response) == "table" then
        elseif response == MODBUS_EXCODE.OK then
            response = {}
        else
            response = { response }
        end

        -- create reply
        local reply = comms.modbus_packet()
        reply.make(packet.txn_id, packet.unit_id, func_code, response)

        return return_code, reply
    end

    return public
end

-- create an error reply
---@nodiscard
---@param packet modbus_frame MODBUS packet frame
---@param code MODBUS_EXCODE exception code
---@return modbus_packet reply
local function excode_reply(packet, code)
    -- reply back with error flag and exception code
    local reply = comms.modbus_packet()
    local fcode = bit.bor(packet.func_code, MODBUS_FCODE.ERROR_FLAG)
    reply.make(packet.txn_id, packet.unit_id, fcode, { code })
    return reply
end

-- return a SERVER_DEVICE_FAIL error reply
---@nodiscard
---@param packet modbus_frame MODBUS packet frame
---@return modbus_packet reply
function modbus.reply__srv_device_fail(packet) return excode_reply(packet, MODBUS_EXCODE.SERVER_DEVICE_FAIL) end

-- return a SERVER_DEVICE_BUSY error reply
---@nodiscard
---@param packet modbus_frame MODBUS packet frame
---@return modbus_packet reply
function modbus.reply__srv_device_busy(packet) return excode_reply(packet, MODBUS_EXCODE.SERVER_DEVICE_BUSY) end

-- return a NEG_ACKNOWLEDGE error reply
---@nodiscard
---@param packet modbus_frame MODBUS packet frame
---@return modbus_packet reply
function modbus.reply__neg_ack(packet) return excode_reply(packet, MODBUS_EXCODE.NEG_ACKNOWLEDGE) end

-- return a GATEWAY_PATH_UNAVAILABLE error reply
---@nodiscard
---@param packet modbus_frame MODBUS packet frame
---@return modbus_packet reply
function modbus.reply__gw_unavailable(packet) return excode_reply(packet, MODBUS_EXCODE.GATEWAY_PATH_UNAVAILABLE) end

return modbus

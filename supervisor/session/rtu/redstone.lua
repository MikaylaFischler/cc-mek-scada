local log          = require("scada-common.log")
local rsio         = require("scada-common.rsio")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local unit_session = require("supervisor.session.rtu.unit_session")

local redstone = {}

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local MODBUS_FCODE = types.MODBUS_FCODE

local IO_LVL = rsio.IO_LVL
local IO_MODE = rsio.IO_MODE

local TXN_READY = -1

local TXN_TYPES = {
    DI_READ = 1,
    COIL_WRITE = 2,
    COIL_READ = 3,
    INPUT_REG_READ = 4,
    HOLD_REG_WRITE = 5,
    HOLD_REG_READ = 6
}

local TXN_TAGS = {
    "redstone.di_read",
    "redstone.coil_write",
    "redstone.coil_read",
    "redstone.input_reg_read",
    "redstone.hold_reg_write",
    "redstone.hold_reg_read"
}

local PERIODICS = {
    INPUT_READ = 200,
    OUTPUT_SYNC = 200
}

-- create a new block of IO banks (facility, then each unit)
local function new_io_block() return { [0] = {}, {}, {}, {}, {} } end

---@class dig_phy_entry
---@field phy IO_LVL actual value
---@field req IO_LVL commanded value

---@class ana_phy_entry
---@field phy number actual value
---@field req number commanded value

-- create a new redstone rtu session runner
---@nodiscard
---@param session_id integer RTU gateway session ID
---@param unit_id integer RTU ID
---@param advert rtu_advertisement RTU advertisement table
---@param out_queue mqueue RTU message out queue
function redstone.new(session_id, unit_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPE.REDSTONE then
        log.error("attempt to instantiate redstone RTU for type " .. types.rtu_type_to_string(advert.type))
        return nil
    end

    local log_tag = util.c("session.rtu(", session_id, ").redstone[@", unit_id, "]: ")

    local self = {
        session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
        has_di = false,
        has_do = false,
        has_ai = false,
        has_ao = false,
        periodics = {
            next_di_req  = 0,
            next_cl_sync = 0,
            next_ir_req  = 0,
            next_hr_sync = 0
        },
        ---@class rs_io_map
        io_map = {
            digital_in = {},    ---@type { bank: integer, port: IO_PORT }[] discrete inputs
            digital_out = {},   ---@type { bank: integer, port: IO_PORT }[] coils
            analog_in = {},     ---@type { bank: integer, port: IO_PORT }[] input registers
            analog_out = {}     ---@type { bank: integer, port: IO_PORT }[] holding registers
        },
        phy_trans = { coils = -1, hold_regs = -1 },
        -- last set/read ports (reflecting the current state of the RTU)
        ---@class rs_io_states
        phy_io = {
            digital_in = new_io_block(),    ---@type dig_phy_entry[][] discrete inputs
            digital_out = new_io_block(),   ---@type dig_phy_entry[][] coils
            analog_in = new_io_block(),     ---@type ana_phy_entry[][] input registers
            analog_out = new_io_block()     ---@type ana_phy_entry[][] holding registers
        },
        ---@class redstone_session_db
        db = {
            -- read/write functions for connected I/O
            ---@type (rs_db_dig_io|rs_db_ana_io)[][]
            io = new_io_block()
        }
    }

    ---@class redstone_session:unit_session
    local public = self.session.get()

    -- INITIALIZE --

    -- setup I/O
    for bank = 0, 4 do
        for i = 1, #advert.rs_conns[bank] do
            local port = advert.rs_conns[bank][i]

            if rsio.is_valid_port(port) then
                local mode     = rsio.get_io_mode(port)
                local io_entry = { bank = bank, port = port }

                if mode == IO_MODE.DIGITAL_IN then
                    self.has_di = true
                    table.insert(self.io_map.digital_in, io_entry)

                    self.phy_io.digital_in[bank][port] = { phy = IO_LVL.FLOATING, req = IO_LVL.FLOATING }

                    ---@class rs_db_dig_io
                    local io_f = {
                        ---@nodiscard
                        read = function () return rsio.digital_is_active(port, self.phy_io.digital_in[bank][port].phy) end,
                        write = function () end
                    }

                    self.db.io[bank][port] = io_f
                elseif mode == IO_MODE.DIGITAL_OUT then
                    self.has_do = true
                    table.insert(self.io_map.digital_out, io_entry)

                    self.phy_io.digital_out[bank][port] = { phy = IO_LVL.FLOATING, req = IO_LVL.FLOATING }

                    ---@class rs_db_dig_io
                    local io_f = {
                        ---@nodiscard
                        read = function () return rsio.digital_is_active(port, self.phy_io.digital_out[bank][port].phy) end,
                        ---@param active boolean
                        write = function (active)
                            local level = rsio.digital_write_active(port, active)
                            if level ~= nil then self.phy_io.digital_out[bank][port].req = level end
                        end
                    }

                    self.db.io[bank][port] = io_f
                elseif mode == IO_MODE.ANALOG_IN then
                    self.has_ai = true
                    table.insert(self.io_map.analog_in, io_entry)

                    self.phy_io.analog_in[bank][port] = { phy = 0, req = 0 }

                    ---@class rs_db_ana_io
                    local io_f = {
                        ---@nodiscard
                        ---@return integer
                        read = function () return self.phy_io.analog_in[bank][port].phy end,
                        write = function () end
                    }

                    self.db.io[bank][port] = io_f
                elseif mode == IO_MODE.ANALOG_OUT then
                    self.has_ao = true
                    table.insert(self.io_map.analog_out, io_entry)

                    self.phy_io.analog_out[bank][port] = { phy = 0, req = 0 }

                    ---@class rs_db_ana_io
                    local io_f = {
                        ---@nodiscard
                        ---@return integer
                        read = function () return self.phy_io.analog_out[bank][port].phy end,
                        ---@param value integer
                        write = function (value)
                            if value >= 0 and value <= 15 then
                                self.phy_io.analog_out[bank][port].req = value
                            end
                        end
                    }

                    self.db.io[bank][port] = io_f
                else
                    -- should be unreachable code, we already validated ports
                    log.error(util.c(log_tag, "failed to identify advertisement port IO mode (", bank, ":", port, ")"), true)
                    return nil
                end
            else
                log.error(util.c(log_tag, "invalid advertisement port (", bank, ":", port, ")"), true)
                return nil
            end
        end
    end

    -- PRIVATE FUNCTIONS --

    -- query discrete inputs
    local function _request_discrete_inputs()
        self.session.send_request(TXN_TYPES.DI_READ, MODBUS_FCODE.READ_DISCRETE_INPUTS, { 1, #self.io_map.digital_in })
    end

    -- query input registers
    local function _request_input_registers()
        self.session.send_request(TXN_TYPES.INPUT_REG_READ, MODBUS_FCODE.READ_INPUT_REGS, { 1, #self.io_map.analog_in })
    end

    -- write all coil outputs
    local function _write_coils()
        local params = { 1 }

        local outputs = self.phy_io.digital_out
        for i = 1, #self.io_map.digital_out do
            local entry = self.io_map.digital_out[i]
            table.insert(params, outputs[entry.bank][entry.port].req)
        end

        self.phy_trans.coils = self.session.send_request(TXN_TYPES.COIL_WRITE, MODBUS_FCODE.WRITE_MUL_COILS, params)
    end

    -- read all coil outputs
    local function _read_coils()
        self.session.send_request(TXN_TYPES.COIL_READ, MODBUS_FCODE.READ_COILS, { 1, #self.io_map.digital_out })
    end

    -- write all holding register outputs
    local function _write_holding_registers()
        local params = { 1 }

        local outputs = self.phy_io.analog_out
        for i = 1, #self.io_map.analog_out do
            local entry = self.io_map.analog_out[i]
            table.insert(params, outputs[entry.bank][entry.port].req)
        end

        self.phy_trans.hold_regs = self.session.send_request(TXN_TYPES.HOLD_REG_WRITE, MODBUS_FCODE.WRITE_MUL_HOLD_REGS, params)
    end

    -- read all holding register outputs
    local function _read_holding_registers()
        self.session.send_request(TXN_TYPES.HOLD_REG_READ, MODBUS_FCODE.READ_MUL_HOLD_REGS, { 1, #self.io_map.analog_out })
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    function public.handle_packet(m_pkt)
        local txn_type = self.session.try_resolve(m_pkt)
        if txn_type == false then
            -- check if this is a failed write request
            -- redstone operations are always immediately executed, so this would not be from an ACK or BUSY
            if m_pkt.txn_id == self.phy_trans.coils then
                self.phy_trans.coils = TXN_READY
                log.debug(log_tag .. "failed to write coils, retrying soon")
            elseif m_pkt.txn_id == self.phy_trans.hold_regs then
                self.phy_trans.hold_regs = TXN_READY
                log.debug(log_tag .. "failed to write holding registers, retrying soon")
            end
        elseif txn_type == TXN_TYPES.DI_READ then
            -- discrete input read response
            if m_pkt.length == #self.io_map.digital_in then
                for i = 1, m_pkt.length do
                    local entry = self.io_map.digital_in[i]
                    local value = m_pkt.data[i]

                    self.phy_io.digital_in[entry.bank][entry.port].phy = value
                end
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.INPUT_REG_READ then
            -- input register read response
            if m_pkt.length == #self.io_map.analog_in then
                for i = 1, m_pkt.length do
                    local entry = self.io_map.analog_in[i]
                    local value = m_pkt.data[i]

                    self.phy_io.analog_in[entry.bank][entry.port].phy = value
                end
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.COIL_WRITE then
            -- successful acknowledgement, read back
            _read_coils()
        elseif txn_type == TXN_TYPES.COIL_READ then
            -- update phy I/O table
            -- if there are multiple outputs for the same port, they will overwrite eachother (but *should* be identical)
            -- given these are redstone outputs, if one worked they all should have, so no additional verification will be done
            if m_pkt.length == #self.io_map.digital_out then
                for i = 1, m_pkt.length do
                    local entry = self.io_map.digital_out[i]
                    local state = self.phy_io.digital_out[entry.bank][entry.port]
                    local value = m_pkt.data[i]

                    state.phy = value
                    if state.req == IO_LVL.FLOATING then state.req = value end
                end

                self.phy_trans.coils = TXN_READY
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.HOLD_REG_WRITE then
            -- successful acknowledgement, read back
            _read_holding_registers()
        elseif txn_type == TXN_TYPES.HOLD_REG_READ then
            -- update phy I/O table
            -- if there are multiple outputs for the same port, they will overwrite eachother (but *should* be identical)
            -- given these are redstone outputs, if one worked they all should have, so no additional verification will be done
            if m_pkt.length == #self.io_map.analog_out then
                for i = 1, m_pkt.length do
                    local entry = self.io_map.analog_out[i]
                    local value = m_pkt.data[i]

                    self.phy_io.analog_out[entry.bank][entry.port].phy = value
                end
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end

            self.phy_trans.hold_regs = TXN_READY
        elseif txn_type == nil then
            log.error(log_tag .. "unknown transaction reply")
        else
            log.error(log_tag .. "unknown transaction type " .. txn_type)
        end
    end

    -- update this runner
    ---@param time_now integer milliseconds
    function public.update(time_now)
        -- poll digital inputs
        if self.has_di then
            if self.periodics.next_di_req <= time_now then
                _request_discrete_inputs()
                self.periodics.next_di_req = time_now + PERIODICS.INPUT_READ
            end
        end

        -- sync digital outputs
        if self.has_do then
            if (self.periodics.next_cl_sync <= time_now) and (self.phy_trans.coils == TXN_READY) then
                for bank = 0, 4 do
                    local changed = false

                    for _, entry in pairs(self.phy_io.digital_out[bank]) do
                        if entry.phy ~= entry.req then
                            changed = true
                            break
                        end
                    end

                    if changed then
                        _write_coils()
                        break
                    end
                end

                self.periodics.next_cl_sync = time_now + PERIODICS.OUTPUT_SYNC
            end
        end

        -- poll analog inputs
        if self.has_ai then
            if self.periodics.next_ir_req <= time_now then
                _request_input_registers()
                self.periodics.next_ir_req = time_now + PERIODICS.INPUT_READ
            end
        end

        -- sync analog outputs
        if self.has_ao then
            if (self.periodics.next_hr_sync <= time_now) and (self.phy_trans.hold_regs == TXN_READY) then
                for bank = 0, 4 do
                    local changed = false

                    for _, entry in pairs(self.phy_io.analog_out[bank]) do
                        if entry.phy ~= entry.req then
                            changed = true
                            break
                        end
                    end

                    if changed then
                        _write_holding_registers()
                        break
                    end
                end

                self.periodics.next_hr_sync = time_now + PERIODICS.OUTPUT_SYNC
            end
        end

        self.session.post_update()
    end

    -- force a re-read of cached outputs
    function public.invalidate_cache()
        _read_coils()
        _read_holding_registers()
    end

    -- get the unit session database
    ---@nodiscard
    function public.get_db() return self.db end

    return public
end

return redstone

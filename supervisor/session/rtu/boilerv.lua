local log          = require("scada-common.log")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local unit_session = require("supervisor.session.rtu.unit_session")

local boilerv = {}

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local MODBUS_FCODE = types.MODBUS_FCODE

local TXN_TYPES = {
    FORMED = 1,
    BUILD = 2,
    STATE = 3,
    TANKS = 4
}

local TXN_TAGS = {
    "boilerv.formed",
    "boilerv.build",
    "boilerv.state",
    "boilerv.tanks"
}

local PERIODICS = {
    FORMED = 2000,
    BUILD = 1000,
    STATE = 500,
    TANKS = 1000
}

-- create a new boilerv rtu session runner
---@nodiscard
---@param session_id integer RTU gateway session ID
---@param unit_id integer RTU ID
---@param advert rtu_advertisement RTU advertisement table
---@param out_queue mqueue RTU message out queue
function boilerv.new(session_id, unit_id, advert, out_queue)
    -- checks
    if advert.type ~= RTU_UNIT_TYPE.BOILER_VALVE then
        log.error("attempt to instantiate boilerv RTU for type " .. types.rtu_type_to_string(advert.type))
        return nil
    elseif not util.is_int(advert.index) then
        log.error("attempt to instantiate boilerv RTU without index")
        return nil
    end

    local log_tag = util.c("session.rtu(", session_id, ").boilerv(", advert.index, ")[@", unit_id, "]: ")

    local self = {
        session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
        has_build = false,
        periodics = {
            next_formed_req = 0,
            next_build_req = 0,
            next_state_req = 0,
            next_tanks_req = 0
        },
        ---@class boilerv_session_db
        db = {
            formed = false,
            build = {
                last_update = 0,
                length = 0,
                width = 0,
                height = 0,
                min_pos = types.new_zero_coordinate(),
                max_pos = types.new_zero_coordinate(),
                boil_cap = 0.0,
                steam_cap = 0,
                water_cap = 0,
                hcoolant_cap = 0,
                ccoolant_cap = 0,
                superheaters = 0,
                max_boil_rate = 0.0,
            },
            state = {
                last_update = 0,
                temperature = 0.0,
                boil_rate = 0.0,
                env_loss = 0.0
            },
            tanks = {
                last_update = 0,
                steam = types.new_empty_gas(),
                steam_need = 0,
                steam_fill = 0.0,
                water = types.new_empty_gas(),
                water_need = 0,
                water_fill = 0.0,
                hcool = types.new_empty_gas(),
                hcool_need = 0,
                hcool_fill = 0.0,
                ccool = types.new_empty_gas(),
                ccool_need = 0,
                ccool_fill = 0.0
            }
        }
    }

    ---@class boilerv_session:unit_session
    local public = self.session.get()

    -- PRIVATE FUNCTIONS --

    -- query if the multiblock is formed
    ---@param time_now integer
    local function _request_formed(time_now)
        -- read discrete input 1 (start = 1, count = 1)
        if self.session.send_request(TXN_TYPES.FORMED, MODBUS_FCODE.READ_DISCRETE_INPUTS, { 1, 1 }) ~= false then
            self.periodics.next_formed_req = time_now + PERIODICS.FORMED
        end
    end

    -- query the build of the device
    ---@param time_now integer
    local function _request_build(time_now)
        -- read input registers 1 through 12 (start = 1, count = 12)
        if self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 12 }) ~= false then
            self.periodics.next_build_req = time_now + PERIODICS.BUILD
        end
    end

    -- query the state of the device
    ---@param time_now integer
    local function _request_state(time_now)
        -- read input registers 13 through 15 (start = 13, count = 3)
        if self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 13, 3 }) ~= false then
            self.periodics.next_state_req = time_now + PERIODICS.STATE
        end
    end

    -- query the tanks of the device
    ---@param time_now integer
    local function _request_tanks(time_now)
        -- read input registers 16 through 27 (start = 16, count = 12)
        if self.session.send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 16, 12 }) ~= false then
            self.periodics.next_tanks_req = time_now + PERIODICS.TANKS
        end
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    function public.handle_packet(m_pkt)
        local txn_type = self.session.try_resolve(m_pkt)
        if txn_type == false then
            -- nothing to do
        elseif txn_type == TXN_TYPES.FORMED then
            -- formed response
            -- load in data if correct length
            if m_pkt.length == 1 then
                self.db.formed = m_pkt.data[1]

                if not self.db.formed then self.has_build = false end
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.BUILD then
            -- build response
            -- load in data if correct length
            if m_pkt.length == 12 then
                self.db.build.last_update   = util.time_ms()
                self.db.build.length        = m_pkt.data[1]
                self.db.build.width         = m_pkt.data[2]
                self.db.build.height        = m_pkt.data[3]
                self.db.build.min_pos       = m_pkt.data[4]
                self.db.build.max_pos       = m_pkt.data[5]
                self.db.build.boil_cap      = m_pkt.data[6]
                self.db.build.steam_cap     = m_pkt.data[7]
                self.db.build.water_cap     = m_pkt.data[8]
                self.db.build.hcoolant_cap  = m_pkt.data[9]
                self.db.build.ccoolant_cap  = m_pkt.data[10]
                self.db.build.superheaters  = m_pkt.data[11]
                self.db.build.max_boil_rate = m_pkt.data[12]
                self.has_build = true

                out_queue.push_data(unit_session.RTU_US_DATA.BUILD_CHANGED, { unit = advert.reactor, type = advert.type })
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.STATE then
            -- state response
            -- load in data if correct length
            if m_pkt.length == 3 then
                self.db.state.last_update = util.time_ms()
                self.db.state.temperature = m_pkt.data[1]
                self.db.state.boil_rate   = m_pkt.data[2]
                self.db.state.env_loss    = m_pkt.data[3]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.TANKS then
            -- tanks response
            -- load in data if correct length
            if m_pkt.length == 12 then
                self.db.tanks.last_update = util.time_ms()
                self.db.tanks.steam       = m_pkt.data[1]
                self.db.tanks.steam_need  = m_pkt.data[2]
                self.db.tanks.steam_fill  = m_pkt.data[3]
                self.db.tanks.water       = m_pkt.data[4]
                self.db.tanks.water_need  = m_pkt.data[5]
                self.db.tanks.water_fill  = m_pkt.data[6]
                self.db.tanks.hcool       = m_pkt.data[7]
                self.db.tanks.hcool_need  = m_pkt.data[8]
                self.db.tanks.hcool_fill  = m_pkt.data[9]
                self.db.tanks.ccool       = m_pkt.data[10]
                self.db.tanks.ccool_need  = m_pkt.data[11]
                self.db.tanks.ccool_fill  = m_pkt.data[12]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == nil then
            log.error(log_tag .. "unknown transaction reply")
        else
            log.error(log_tag .. "unknown transaction type " .. txn_type)
        end
    end

    -- update this runner
    ---@param time_now integer milliseconds
    function public.update(time_now)
        if self.periodics.next_formed_req <= time_now then _request_formed(time_now) end

        if self.db.formed then
            if not self.has_build and self.periodics.next_build_req <= time_now then _request_build(time_now) end
            if self.periodics.next_state_req <= time_now then _request_state(time_now) end
            if self.periodics.next_tanks_req <= time_now then _request_tanks(time_now) end
        end

        self.session.post_update()
    end

    -- invalidate build cache
    function public.invalidate_cache()
        self.periodics.next_formed_req = 0
        self.periodics.next_build_req = 0
        self.has_build = false
    end

    -- get the unit session database
    ---@nodiscard
    function public.get_db() return self.db end

    return public
end

return boilerv

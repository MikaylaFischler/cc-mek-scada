local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local types = require("scada-common.types")

local unit_session = require("supervisor.session.rtu.unit_session")

local boiler = {}

local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
local MODBUS_FCODE = types.MODBUS_FCODE

local TXN_TYPES = {
    BUILD = 1,
    STATE = 2,
    TANKS = 3
}

local TXN_TAGS = {
    "boiler.build",
    "boiler.state",
    "boiler.tanks",
}

local PERIODICS = {
    BUILD = 1000,
    STATE = 500,
    TANKS = 1000
}

-- create a new boiler rtu session runner
---@param session_id integer
---@param unit_id integer
---@param advert rtu_advertisement
---@param out_queue mqueue
function boiler.new(session_id, unit_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPES.BOILER then
        log.error("attempt to instantiate boiler RTU for type '" .. advert.type .. "'. this is a bug.")
        return nil
    end

    local log_tag = "session.rtu(" .. session_id .. ").boiler(" .. advert.index .. "): "

    local self = {
        session = unit_session.new(unit_id, advert, out_queue, log_tag, TXN_TAGS),
        has_build = false,
        periodics = {
            next_build_req = 0,
            next_state_req = 0,
            next_tanks_req = 0,
        },
        ---@class boiler_session_db
        db = {
            build = {
                boil_cap = 0.0,
                steam_cap = 0,
                water_cap = 0,
                hcoolant_cap = 0,
                ccoolant_cap = 0,
                superheaters = 0,
                max_boil_rate = 0.0
            },
            state = {
                temperature = 0.0,
                boil_rate = 0.0
            },
            tanks = {
                steam = 0,
                steam_need = 0,
                steam_fill = 0.0,
                water = 0,
                water_need = 0,
                water_fill = 0.0,
                hcool = {},         ---@type tank_fluid
                hcool_need = 0,
                hcool_fill = 0.0,
                ccool = {},         ---@type tank_fluid
                ccool_need = 0,
                ccool_fill = 0.0
            }
        }
    }

    local public = self.session.get()

    -- PRIVATE FUNCTIONS --

    -- query the build of the device
    local function _request_build()
        -- read input registers 1 through 7 (start = 1, count = 7)
        self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 7 })
    end

    -- query the state of the device
    local function _request_state()
        -- read input registers 8 through 9 (start = 8, count = 2)
        self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 8, 2 })
    end

    -- query the tanks of the device
    local function _request_tanks()
        -- read input registers 10 through 21 (start = 10, count = 12)
        self.session.send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 10, 12 })
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    function public.handle_packet(m_pkt)
        local txn_type = self.session.try_resolve(m_pkt.txn_id)
        if txn_type == false then
            -- nothing to do
        elseif txn_type == TXN_TYPES.BUILD then
            -- build response
            -- load in data if correct length
            if m_pkt.length == 7 then
                self.db.build.boil_cap = m_pkt.data[1]
                self.db.build.steam_cap = m_pkt.data[2]
                self.db.build.water_cap = m_pkt.data[3]
                self.db.build.hcoolant_cap = m_pkt.data[4]
                self.db.build.ccoolant_cap = m_pkt.data[5]
                self.db.build.superheaters = m_pkt.data[6]
                self.db.build.max_boil_rate = m_pkt.data[7]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.STATE then
            -- state response
            -- load in data if correct length
            if m_pkt.length == 2 then
                self.db.state.temperature = m_pkt.data[1]
                self.db.state.boil_rate = m_pkt.data[2]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.TANKS then
            -- tanks response
            -- load in data if correct length
            if m_pkt.length == 12 then
                self.db.tanks.steam = m_pkt.data[1]
                self.db.tanks.steam_need = m_pkt.data[2]
                self.db.tanks.steam_fill = m_pkt.data[3]
                self.db.tanks.water = m_pkt.data[4]
                self.db.tanks.water_need = m_pkt.data[5]
                self.db.tanks.water_fill = m_pkt.data[6]
                self.db.tanks.hcool = m_pkt.data[7]
                self.db.tanks.hcool_need = m_pkt.data[8]
                self.db.tanks.hcool_fill = m_pkt.data[9]
                self.db.tanks.ccool = m_pkt.data[10]
                self.db.tanks.ccool_need = m_pkt.data[11]
                self.db.tanks.ccool_fill = m_pkt.data[12]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (boiler.tanks)")
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
        if not self.periodics.has_build and self.periodics.next_build_req <= time_now then
            _request_build()
            self.periodics.next_build_req = time_now + PERIODICS.BUILD
        end

        if self.periodics.next_state_req <= time_now then
            _request_state()
            self.periodics.next_state_req = time_now + PERIODICS.STATE
        end

        if self.periodics.next_tanks_req <= time_now then
            _request_tanks()
            self.periodics.next_tanks_req = time_now + PERIODICS.TANKS
        end

        self.session.post_update()
    end

    -- get the unit session database
    function public.get_db() return self.db end

    return public
end

return boiler

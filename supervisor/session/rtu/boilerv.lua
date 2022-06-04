local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local types = require("scada-common.types")

local unit_session = require("supervisor.session.rtu.unit_session")

local boilerv = {}

local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
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
---@param session_id integer
---@param unit_id integer
---@param advert rtu_advertisement
---@param out_queue mqueue
function boilerv.new(session_id, unit_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPES.BOILER_VALVE then
        log.error("attempt to instantiate boilerv RTU for type '" .. advert.type .. "'. this is a bug.")
        return nil
    end

    local log_tag = "session.rtu(" .. session_id .. ").boilerv(" .. advert.index .. "): "

    local self = {
        session = unit_session.new(unit_id, advert, out_queue, log_tag, TXN_TAGS),
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
                length = 0,
                width = 0,
                height = 0,
                min_pos = 0,
                max_pos = 0,
                boil_cap = 0.0,
                steam_cap = 0,
                water_cap = 0,
                hcoolant_cap = 0,
                ccoolant_cap = 0,
                superheaters = 0,
                max_boil_rate = 0.0,
                env_loss = 0.0
            },
            state = {
                temperature = 0.0,
                boil_rate = 0.0
            },
            tanks = {
                steam = {},         ---@type tank_fluid
                steam_need = 0,
                steam_fill = 0.0,
                water = {},         ---@type tank_fluid
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

    -- query if the multiblock is formed
    local function _request_formed()
        -- read discrete input 1 (start = 1, count = 1)
        self.session.send_request(TXN_TYPES.FORMED, MODBUS_FCODE.READ_DISCRETE_INPUTS, { 1, 1 })
    end

    -- query the build of the device
    local function _request_build()
        -- read input registers 1 through 13 (start = 1, count = 13)
        self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 7 })
    end

    -- query the state of the device
    local function _request_state()
        -- read input registers 14 through 16 (start = 14, count = 2)
        self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 14, 2 })
    end

    -- query the tanks of the device
    local function _request_tanks()
        -- read input registers 17 through 29 (start = 17, count = 12)
        self.session.send_request(TXN_TYPES.TANKS, MODBUS_FCODE.READ_INPUT_REGS, { 17, 12 })
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    function public.handle_packet(m_pkt)
        local txn_type = self.session.try_resolve(m_pkt.txn_id)
        if txn_type == false then
            -- nothing to do
        elseif txn_type == TXN_TYPES.FORMED then
            -- formed response
            -- load in data if correct length
            if m_pkt.length == 1 then
                self.db.formed = m_pkt.data[1]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.BUILD then
            -- build response
            -- load in data if correct length
            if m_pkt.length == 13 then
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
                self.db.build.env_loss      = m_pkt.data[13]
                self.has_build = true
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.STATE then
            -- state response
            -- load in data if correct length
            if m_pkt.length == 2 then
                self.db.state.temperature = m_pkt.data[1]
                self.db.state.boil_rate   = m_pkt.data[2]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.TANKS then
            -- tanks response
            -- load in data if correct length
            if m_pkt.length == 12 then
                self.db.tanks.steam      = m_pkt.data[1]
                self.db.tanks.steam_need = m_pkt.data[2]
                self.db.tanks.steam_fill = m_pkt.data[3]
                self.db.tanks.water      = m_pkt.data[4]
                self.db.tanks.water_need = m_pkt.data[5]
                self.db.tanks.water_fill = m_pkt.data[6]
                self.db.tanks.hcool      = m_pkt.data[7]
                self.db.tanks.hcool_need = m_pkt.data[8]
                self.db.tanks.hcool_fill = m_pkt.data[9]
                self.db.tanks.ccool      = m_pkt.data[10]
                self.db.tanks.ccool_need = m_pkt.data[11]
                self.db.tanks.ccool_fill = m_pkt.data[12]
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
        if self.periodics.next_formed_req <= time_now then
            _request_formed()
            self.periodics.next_formed_req = time_now + PERIODICS.FORMED
        end

        if self.db.formed then
            if not self.has_build and self.periodics.next_build_req <= time_now then
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
        end

        self.session.post_update()
    end

    -- get the unit session database
    function public.get_db() return self.db end

    return public
end

return boilerv

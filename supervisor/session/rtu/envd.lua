local log          = require("scada-common.log")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local unit_session = require("supervisor.session.rtu.unit_session")

local envd = {}

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local MODBUS_FCODE = types.MODBUS_FCODE

local TXN_TYPES = {
    RAD = 1
}

local TXN_TAGS = {
    "envd.radiation"
}

local PERIODICS = {
    RAD = 500
}

-- create a new environment detector rtu session runner
---@nodiscard
---@param session_id integer RTU gateway session ID
---@param unit_id integer RTU ID
---@param advert rtu_advertisement RTU advertisement table
---@param out_queue mqueue RTU message out queue
function envd.new(session_id, unit_id, advert, out_queue)
    -- checks
    if advert.type ~= RTU_UNIT_TYPE.ENV_DETECTOR then
        log.error("attempt to instantiate envd RTU for type " .. types.rtu_type_to_string(advert.type))
        return nil
    elseif not util.is_int(advert.index) then
        log.error("attempt to instantiate envd RTU without index")
        return nil
    end

    local log_tag = util.c("session.rtu(", session_id, ").envd(", advert.index, ")[@", unit_id, "]: ")

    local self = {
        session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
        periodics = {
            next_rad_req = 0
        },
        ---@class envd_session_db
        db = {
            last_update = 0,
            radiation = types.new_zero_radiation_reading(),
            radiation_raw = 0
        }
    }

    ---@class envd_session:unit_session
    local public = self.session.get()

    -- PRIVATE FUNCTIONS --

    -- query the radiation readings of the device
    ---@param time_now integer
    local function _request_radiation(time_now)
        -- read input registers 1 and 2 (start = 1, count = 2)
        if self.session.send_request(TXN_TYPES.RAD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 2 }) ~= false then
            self.periodics.next_rad_req = time_now + PERIODICS.RAD
        end
    end

    -- PUBLIC FUNCTIONS --

    -- handle a packet
    ---@param m_pkt modbus_frame
    function public.handle_packet(m_pkt)
        local txn_type = self.session.try_resolve(m_pkt)
        if txn_type == false then
            -- nothing to do
        elseif txn_type == TXN_TYPES.RAD then
            -- radiation status response
            if m_pkt.length == 2 then
                self.db.last_update   = util.time_ms()
                self.db.radiation     = m_pkt.data[1]
                self.db.radiation_raw = m_pkt.data[2]
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
        if self.periodics.next_rad_req <= time_now then _request_radiation(time_now) end

        self.session.post_update()
    end

    -- invalidate build cache
    function public.invalidate_cache()
        -- no build cache for this device
    end

    -- get the unit session database
    ---@nodiscard
    function public.get_db() return self.db end

    return public
end

return envd

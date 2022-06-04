local comms = require("scada-common.comms")
local log   = require("scada-common.log")
local types = require("scada-common.types")

local unit_session = require("supervisor.session.rtu.unit_session")

local emachine = {}

local RTU_UNIT_TYPES = comms.RTU_UNIT_TYPES
local MODBUS_FCODE = types.MODBUS_FCODE

local TXN_TYPES = {
    BUILD = 1,
    STORAGE = 2
}

local TXN_TAGS = {
    "emachine.build",
    "emachine.storage"
}

local PERIODICS = {
    BUILD = 1000,
    STORAGE = 500
}

-- create a new energy machine rtu session runner
---@param session_id integer
---@param unit_id integer
---@param advert rtu_advertisement
---@param out_queue mqueue
function emachine.new(session_id, unit_id, advert, out_queue)
    -- type check
    if advert.type ~= RTU_UNIT_TYPES.EMACHINE then
        log.error("attempt to instantiate emachine RTU for type '" .. advert.type .. "'. this is a bug.")
        return nil
    end

    local log_tag = "session.rtu(" .. session_id .. ").emachine(" .. advert.index .. "): "

    local self = {
        session = unit_session.new(unit_id, advert, out_queue, log_tag, TXN_TAGS),
        has_build = false,
        periodics = {
            next_build_req = 0,
            next_storage_req = 0,
        },
        ---@class emachine_session_db
        db = {
            build = {
                max_energy = 0
            },
            storage = {
                energy = 0,
                energy_need = 0,
                energy_fill = 0.0
            }
        }
    }

    local public = self.session.get()

    -- PRIVATE FUNCTIONS --

    -- query the build of the device
    local function _request_build()
        -- read input register 1 (start = 1, count = 1)
        self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 1 })
    end

    -- query the state of the energy storage
    local function _request_storage()
        -- read input registers 2 through 4 (start = 2, count = 3)
        self.session.send_request(TXN_TYPES.STORAGE, MODBUS_FCODE.READ_INPUT_REGS, { 2, 3 })
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
            if m_pkt.length == 1 then
                self.db.build.max_energy = m_pkt.data[1]
            else
                log.debug(log_tag .. "MODBUS transaction reply length mismatch (" .. TXN_TAGS[txn_type] .. ")")
            end
        elseif txn_type == TXN_TYPES.STORAGE then
            -- storage response
            if m_pkt.length == 3 then
                self.db.storage.energy = m_pkt.data[1]
                self.db.storage.energy_need = m_pkt.data[2]
                self.db.storage.energy_fill = m_pkt.data[3]
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
        if not self.has_build and self.periodics.next_build_req <= time_now then
            _request_build()
            self.periodics.next_build_req = time_now + PERIODICS.BUILD
        end

        if self.periodics.next_storage_req <= time_now then
            _request_storage()
            self.periodics.next_storage_req = time_now + PERIODICS.STORAGE
        end

        self.session.post_update()
    end

    -- get the unit session database
    function public.get_db() return self.db end

    return public
end

return emachine

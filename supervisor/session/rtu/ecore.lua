local log          = require("scada-common.log")
local types        = require("scada-common.types")
local util         = require("scada-common.util")

local unit_session = require("supervisor.session.rtu.unit_session")

local ecore = {}

local RTU_UNIT_TYPE = types.RTU_UNIT_TYPE
local MODBUS_FCODE = types.MODBUS_FCODE

local TXN_TYPES = {
    BUILD = 1,
    STATE = 2
}

local TXN_TAGS = {
    "ecore.build",
    "ecore.state"
}

local PERIODICS = {
    BUILD = 2000,
    STATE = 500
}

-- create a new ecore rtu session runner
---@nodiscard
---@param session_id integer RTU gateway session ID
---@param unit_id integer RTU ID
---@param advert rtu_advertisement RTU advertisement table
---@param out_queue mqueue RTU message out queue
function ecore.new(session_id, unit_id, advert, out_queue)
    -- checks
    if advert.type ~= RTU_UNIT_TYPE.ENERGY_CORE then
        log.error("attempt to instantiate ecore RTU for type " .. types.rtu_type_to_string(advert.type))
        return nil
    end

    local log_tag = util.c("session.rtu(", session_id, ").ecore[@", unit_id, "]: ")

    local self = {
        session = unit_session.new(session_id, unit_id, advert, out_queue, log_tag, TXN_TAGS),
        has_build = false,
        periodics = {
            next_build_req = 0,
            next_state_req = 0
        },
        ---@class ecore_session_db
        db = {
            build = {
                last_update = 0,
                max_energy = 0
            },
            state = {
                last_update = 0,
                input = 0,
                output = 0,
                transfer = 0,
                energy = 0
            },
            virtual = {
                last_update = 0,
                energy_fill = 0,
                tier = 0
            }
        }
    }

    ---@class ecore_session:unit_session
    local public = self.session.get()

    -- PRIVATE FUNCTIONS --

    -- query the build of the device
    ---@param time_now integer
    local function _request_build(time_now)
        -- read input registers 1 through 1 (start = 1, count = 1)
        if self.session.send_request(TXN_TYPES.BUILD, MODBUS_FCODE.READ_INPUT_REGS, { 1, 1 }) ~= false then
            self.periodics.next_build_req = time_now + PERIODICS.BUILD
        end
    end

    -- query the state of the device
    ---@param time_now integer
    local function _request_state(time_now)
        -- read input register 2 through 5 (start = 2, count = 4)
        if self.session.send_request(TXN_TYPES.STATE, MODBUS_FCODE.READ_INPUT_REGS, { 2, 4 }) ~= false then
            self.periodics.next_state_req = time_now + PERIODICS.STATE
        end
    end

    -- PUBLIC FUNCTIONS --

    -- handle an ADU
    ---@param adu modbus_adu
    function public.handle_adu(adu)
        local txn_type = self.session.try_resolve(adu)
        if txn_type == false then
            -- nothing to do
        elseif txn_type == TXN_TYPES.BUILD then
            -- build response
            -- load in data if correct length
            if adu.length == 1 then
                self.db.build.last_update = util.time_ms()
                self.db.build.max_energy  = adu.data[1]
                self.has_build = true

                if self.db.build.max_energy > 0 then
                    self.db.virtual.last_update = self.db.state.last_update -- intentionally using state
                    self.db.virtual.energy_fill = self.db.state.energy / self.db.build.max_energy
                else self.db.virtual.energy_fill = 0 end

                local max = self.db.build.max_energy

                -- if max == 9223372036854775807 then
                if max > 2140000000000 then
                    self.db.virtual.tier = "Tier 8"
                elseif max > 356000000000 then
                    self.db.virtual.tier = "Tier 7"
                elseif max > 59300000000 then
                    self.db.virtual.tier = "Tier 6"
                elseif max > 9880000000  then
                    self.db.virtual.tier = "Tier 5"
                elseif max > 1640000000 then
                    self.db.virtual.tier = "Tier 4"
                elseif max > 273000000 then
                    self.db.virtual.tier = "Tier 3"
                elseif max > 45500000 then
                    self.db.virtual.tier = "Tier 2"
                else
                    self.db.virtual.tier = "Tier 1"
                end

                out_queue.push_data(unit_session.RTU_US_DATA.BUILD_CHANGED, { unit = advert.reactor, type = advert.type })
            else self.session.log_length_mismatch(txn_type) end
        elseif txn_type == TXN_TYPES.STATE then
            -- state response
            -- load in data if correct length
            if adu.length == 4 then
                self.db.state.last_update = util.time_ms()
                self.db.state.input       = adu.data[1]
                self.db.state.output      = adu.data[2]
                self.db.state.transfer    = adu.data[3]
                self.db.state.energy      = adu.data[4]

                if self.has_build and self.db.build.max_energy > 0 then
                    self.db.virtual.last_update = self.db.state.last_update
                    self.db.virtual.energy_fill = self.db.state.energy / self.db.build.max_energy
                else self.db.virtual.energy_fill = 0 end
            else self.session.log_length_mismatch(txn_type) end
        else self.session.log_resolve_fail(txn_type) end
    end

    -- update this runner
    ---@param time_now integer milliseconds
    function public.update(time_now)
        if self.periodics.next_build_req <= time_now then _request_build(time_now) end
        if self.periodics.next_state_req <= time_now then _request_state(time_now) end

        self.session.post_update()
    end

    -- invalidate build cache
    function public.invalidate_cache()
        self.periodics.next_build_req = 0
        self.has_build = false
    end

    -- get the unit session database
    ---@nodiscard
    function public.get_db() return self.db end

    return public
end

return ecore

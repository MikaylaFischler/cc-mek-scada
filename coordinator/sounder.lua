--
-- Alarm Sounder
--

local types = require("scada-common.types")
local util  = require("scada-common.util")
local log   = require("scada-common.log")

local ALARM = types.ALARM
local ALARM_STATE = types.ALARM_STATE

---@class sounder
local sounder = {}

local _2_PI        = 2 * math.pi    -- 2 whole pies, hope you're hungry
local _DRATE       = 48000          -- 48kHz audio
local _MAX_VAL     = 127/2            -- max signed integer in this 8-bit audio
local _MAX_SAMPLES = 0x20000        -- 128 * 1024 samples
local _05s_SAMPLES = 24000          -- half a second worth of samples

local test_alarms = { false, false, false, false, false, false, false, false, false, false, false, false }

local alarm_ctl = {
    speaker = nil,
    volume = 0.5,
    playing = false,
    num_active = 0,
    next_block = 1,
    quad_buffer = { {}, {}, {}, {} }    -- split audio up into 0.5s samples so specific components can be ended quicker
}

-- sounds modeled after https://www.e2s.com/references-and-guidelines/listen-and-download-alarm-tones

local T_340Hz_Int_2Hz = 1
local T_544Hz_440Hz_Alt = 2
local T_660Hz_Int_125ms = 3
local T_745Hz_Int_1Hz = 4
local T_800Hz_Int = 5
local T_800Hz_1000Hz_Alt = 6
local T_1000Hz_Int = 7
local T_1800Hz_Int_4Hz = 8

local TONES = {
    { active = false, component = { {}, {}, {}, {} } }, -- 340Hz @ 2Hz Intermittent
    { active = false, component = { {}, {}, {}, {} } }, -- 544Hz 100mS / 440Hz 400mS Alternating
    { active = false, component = { {}, {}, {}, {} } }, -- 660Hz @ 125ms On 125ms Off
    { active = false, component = { {}, {}, {}, {} } }, -- 745Hz @ 1Hz Intermittent
    { active = false, component = { {}, {}, {}, {} } }, -- 800Hz @ 0.25s On 1.75s Off
    { active = false, component = { {}, {}, {}, {} } }, -- 800/1000Hz @ 0.25s Alternating
    { active = false, component = { {}, {}, {}, {} } }, -- 1KHz 1s on, 1s off Intermittent
    { active = false, component = { {}, {}, {}, {} } }  -- 1.8KHz @ 4Hz Intermittent
}

-- calculate how many samples are in the given number of milliseconds
---@param ms integer milliseconds
---@return integer samples
local function ms_to_samples(ms) return math.floor(ms * 48) end

--#region Tone Generation (the Maths)

-- 340Hz @ 2Hz Intermittent
local function gen_tone_1()
    local t, dt = 0, _2_PI * 340 / _DRATE

    for i = 1, _05s_SAMPLES do
        local val = math.floor(math.sin(t) * _MAX_VAL)
        TONES[1].component[1][i] = val
        TONES[1].component[3][i] = val
        TONES[1].component[2][i] = 0
        TONES[1].component[4][i] = 0
        t = (t + dt) % _2_PI
    end
end

-- 544Hz 100mS / 440Hz 400mS Alternating
local function gen_tone_2()
    local t1, dt1 = 0, _2_PI * 544 / _DRATE
    local t2, dt2 = 0, _2_PI * 440 / _DRATE
    local alternate_at = ms_to_samples(100)

    for i = 1, _05s_SAMPLES do
        local value

        if i <= alternate_at then
            value = math.floor(math.sin(t1) * _MAX_VAL)
            t1 = (t1 + dt1) % _2_PI
        else
            value = math.floor(math.sin(t2) * _MAX_VAL)
            t2 = (t2 + dt2) % _2_PI
        end

        TONES[2].component[1][i] = value
        TONES[2].component[2][i] = value
        TONES[2].component[3][i] = value
        TONES[2].component[4][i] = value
    end
end

-- 660Hz @ 125ms On 125ms Off
local function gen_tone_3()
    local elapsed_samples = 0
    local alternate_after = ms_to_samples(125)
    local alternate_at = alternate_after
    local mode = true

    local t, dt = 0, _2_PI * 660 / _DRATE

    for set = 1, 4 do
        for i = 1, _05s_SAMPLES do
            if mode then
                local val = math.floor(math.sin(t) * _MAX_VAL)
                TONES[3].component[set][i] = val
                t = (t + dt) % _2_PI
            else
                t = 0
                TONES[3].component[set][i] = 0
            end

            if elapsed_samples == alternate_at then
                mode = not mode
                alternate_at = elapsed_samples + alternate_after
            end

            elapsed_samples = elapsed_samples + 1
        end
    end
end

-- 745Hz @ 1Hz Intermittent
local function gen_tone_4()
    local t, dt = 0, _2_PI * 745 / _DRATE

    for i = 1, _05s_SAMPLES do
        local val = math.floor(math.sin(t) * _MAX_VAL)
        TONES[4].component[1][i] = val
        TONES[4].component[3][i] = val
        TONES[4].component[2][i] = 0
        TONES[4].component[4][i] = 0
        t = (t + dt) % _2_PI
    end
end

-- 800Hz @ 0.25s On 1.75s Off
local function gen_tone_5()
    local t, dt = 0, _2_PI * 800 / _DRATE
    local stop_at = ms_to_samples(250)

    for i = 1, _05s_SAMPLES do
        local val = math.floor(math.sin(t) * _MAX_VAL)

        if i > stop_at then
            TONES[5].component[1][i] = val
        else
            TONES[5].component[1][i] = 0
        end

        TONES[5].component[2][i] = 0
        TONES[5].component[3][i] = 0
        TONES[5].component[4][i] = 0

        t = (t + dt) % _2_PI
    end
end

-- 1000/800Hz @ 0.25s Alternating
local function gen_tone_6()
    local t1, dt1 = 0, _2_PI * 1000 / _DRATE
    local t2, dt2 = 0, _2_PI * 800 / _DRATE

    local alternate_at = ms_to_samples(250)

    for i = 1, _05s_SAMPLES do
        local val
        if i <= alternate_at then
            val = math.floor(math.sin(t1) * _MAX_VAL)
            t1 = (t1 + dt1) % _2_PI
        else
            val = math.floor(math.sin(t2) * _MAX_VAL)
            t2 = (t2 + dt2) % _2_PI
        end

        TONES[6].component[1][i] = val
        TONES[6].component[2][i] = val
        TONES[6].component[3][i] = val
        TONES[6].component[4][i] = val
    end
end

-- 1KHz 1s on, 1s off Intermittent
local function gen_tone_7()
    local t, dt = 0, _2_PI * 1000 / _DRATE

    for i = 1, _05s_SAMPLES do
        local val = math.floor(math.sin(t) * _MAX_VAL)
        TONES[7].component[1][i] = val
        TONES[7].component[2][i] = val
        TONES[7].component[3][i] = 0
        TONES[7].component[4][i] = 0
        t = (t + dt) % _2_PI
    end
end

-- 1800Hz @ 4Hz Intermittent
local function gen_tone_8()
    local t, dt = 0, _2_PI * 1800 / _DRATE

    local off_at = ms_to_samples(250)

    for i = 1, _05s_SAMPLES do
        local val = 0

        if i <= off_at then
            val = math.floor(math.sin(t) * _MAX_VAL)
            t = (t + dt) % _2_PI
        end

        TONES[8].component[1][i] = val
        TONES[8].component[2][i] = val
        TONES[8].component[3][i] = val
        TONES[8].component[4][i] = val
    end
end

--#endregion

-- hard audio limiter
---@param output number output level
---@return number limited -128.0 to 127.0
local function limit(output)
    return math.max(-128, math.min(127, output))
end

-- zero the alarm audio buffer
local function zero()
    for i = 1, 4 do
        for s = 1, _05s_SAMPLES do alarm_ctl.quad_buffer[i][s] = 0 end
    end
end

-- add an alarm to the output buffer
---@param alarm_idx integer tone ID
local function add(alarm_idx)
    alarm_ctl.num_active = alarm_ctl.num_active + 1
    TONES[alarm_idx].active = true

    for i = 1, 4 do
        for s = 1, _05s_SAMPLES do
            alarm_ctl.quad_buffer[i][s] = limit(alarm_ctl.quad_buffer[i][s] + TONES[alarm_idx].component[i][s])
        end
    end
end

-- start audio or continue audio on buffer empty
---@return boolean success successfully added buffer to audio output
local function play()
    if not alarm_ctl.playing then
        alarm_ctl.playing = true
        alarm_ctl.next_block = 1

        return sounder.continue()
    else
        return true
    end
end

-- initialize the annunciator alarm system
---@param speaker table speaker peripheral
---@param volume number speaker volume
function sounder.init(speaker, volume)
    alarm_ctl.speaker = speaker
    alarm_ctl.speaker.stop()

    alarm_ctl.volume = volume
    alarm_ctl.playing = false
    alarm_ctl.num_active = 0
    alarm_ctl.next_block = 1

    zero()

    -- generate tones
    gen_tone_1()
    gen_tone_2()
    gen_tone_3()
    gen_tone_4()
    gen_tone_5()
    gen_tone_6()
    gen_tone_7()
    gen_tone_8()
end

-- reconnect the speaker peripheral
---@param speaker table speaker peripheral
function sounder.reconnect(speaker)
    alarm_ctl.speaker = speaker
    alarm_ctl.playing = false
end

-- check alarm state to enable/disable alarms
---@param units table|nil unit list or nil to use test mode
function sounder.eval(units)
    local changed = false
    local any_active = false
    local new_states = { false, false, false, false, false, false, false, false }
    local alarms = { false, false, false, false, false, false, false, false, false, false, false, false }

    if units ~= nil then
        -- check all alarms for all units
        for i = 1, #units do
            local unit = units[i]   ---@type ioctl_unit
            for id = 1, #unit.alarms do
                alarms[id] = alarms[id] or (unit.alarms[id] == ALARM_STATE.TRIPPED)
            end
        end
    else
        alarms = test_alarms
    end

    -- containment breach is worst case CRITICAL alarm, this takes priority
    if alarms[ALARM.ContainmentBreach] then
        new_states[T_1800Hz_Int_4Hz] = true
    else
        -- critical damage is highest priority CRITICAL level alarm
        if alarms[ALARM.CriticalDamage] then
            new_states[T_660Hz_Int_125ms] = true
        else
            -- EMERGENCY level alarms
            if alarms[ALARM.ReactorDamage] or alarms[ALARM.ReactorOverTemp] or alarms[ALARM.ReactorWasteLeak] then
                new_states[T_544Hz_440Hz_Alt] = true
            -- URGENT level turbine trip
            elseif alarms[ALARM.TurbineTrip] then
                new_states[T_745Hz_Int_1Hz] = true
            -- URGENT level reactor lost
            elseif alarms[ALARM.ReactorLost] then
                new_states[T_340Hz_Int_2Hz] = true
            -- TIMELY level alarms
            elseif alarms[ALARM.ReactorHighTemp] or alarms[ALARM.ReactorHighWaste] or alarms[ALARM.RCSTransient] then
                new_states[T_800Hz_Int] = true
            end
        end

        -- check RPS transient URGENT level alarm
        if alarms[ALARM.RPSTransient] then
            new_states[T_1000Hz_Int] = true
            -- disable really painful audio combination
            new_states[T_340Hz_Int_2Hz] = false
        end
    end

    -- radiation is a big concern, always play this CRITICAL level alarm if active
    if alarms[ALARM.ContainmentRadiation] then
        new_states[T_800Hz_1000Hz_Alt] = true
        -- we are going to disable the RPS trip alarm audio due to conflict, and if it was enabled
        -- then we can re-enable the reactor lost alarm audio since it doesn't painfully combine with this one
        if new_states[T_1000Hz_Int] and alarms[ALARM.ReactorLost] then new_states[T_340Hz_Int_2Hz] = true end
        -- it sounds *really* bad if this is in conjunction with these other tones, so disable them
        new_states[T_745Hz_Int_1Hz] = false
        new_states[T_800Hz_Int] = false
        new_states[T_1000Hz_Int] = false
    end

    -- check if any changed, check if any active, update active flags
    for id = 1, #TONES do
        if new_states[id] ~= TONES[id].active then
            TONES[id].active = new_states[id]
            changed = true
        end

        if TONES[id].active then any_active = true end
    end

    -- zero and re-add tones if changed
    if changed then
        zero()

        for id = 1, #TONES do
            if TONES[id].active then add(id) end
        end
    end

    if any_active then play() else sounder.stop() end
end

-- stop all audio and clear output buffer
function sounder.stop()
    alarm_ctl.playing = false
    alarm_ctl.speaker.stop()
    alarm_ctl.next_block = 1
    alarm_ctl.num_active = 0
    for id = 1, #TONES do TONES[id].active = false end
    zero()
end

-- continue audio on buffer empty
---@return boolean success successfully added buffer to audio output
function sounder.continue()
    if alarm_ctl.playing then
        if alarm_ctl.speaker ~= nil and #alarm_ctl.quad_buffer[alarm_ctl.next_block] > 0 then
            local success = alarm_ctl.speaker.playAudio(alarm_ctl.quad_buffer[alarm_ctl.next_block], alarm_ctl.volume)

            alarm_ctl.next_block = alarm_ctl.next_block + 1
            if alarm_ctl.next_block > 4 then alarm_ctl.next_block = 1 end

            if not success then
                log.debug("SOUNDER: error playing audio")
            end

            return success
        else
            return false
        end
    else
        return false
    end
end

--#region Test Functions

function sounder.test_1() add(1) play() end -- play tone T_340Hz_Int_2Hz
function sounder.test_2() add(2) play() end -- play tone T_544Hz_440Hz_Alt
function sounder.test_3() add(3) play() end -- play tone T_660Hz_Int_125ms
function sounder.test_4() add(4) play() end -- play tone T_745Hz_Int_1Hz
function sounder.test_5() add(5) play() end -- play tone T_800Hz_Int
function sounder.test_6() add(6) play() end -- play tone T_800Hz_1000Hz_Alt
function sounder.test_7() add(7) play() end -- play tone T_1000Hz_Int
function sounder.test_8() add(8) play() end -- play tone T_1800Hz_Int_4Hz

function sounder.test_breach(active)    test_alarms[ALARM.ContainmentBreach]    = active end    ---@param active boolean
function sounder.test_rad(active)       test_alarms[ALARM.ContainmentRadiation] = active end    ---@param active boolean
function sounder.test_lost(active)      test_alarms[ALARM.ReactorLost]          = active end    ---@param active boolean
function sounder.test_crit(active)      test_alarms[ALARM.CriticalDamage]       = active end    ---@param active boolean
function sounder.test_dmg(active)       test_alarms[ALARM.ReactorDamage]        = active end    ---@param active boolean
function sounder.test_overtemp(active)  test_alarms[ALARM.ReactorOverTemp]      = active end    ---@param active boolean
function sounder.test_hightemp(active)  test_alarms[ALARM.ReactorHighTemp]      = active end    ---@param active boolean
function sounder.test_wasteleak(active) test_alarms[ALARM.ReactorWasteLeak]     = active end    ---@param active boolean
function sounder.test_highwaste(active) test_alarms[ALARM.ReactorHighWaste]     = active end    ---@param active boolean
function sounder.test_rps(active)       test_alarms[ALARM.RPSTransient]         = active end    ---@param active boolean
function sounder.test_rcs(active)       test_alarms[ALARM.RCSTransient]         = active end    ---@param active boolean
function sounder.test_turbinet(active)  test_alarms[ALARM.TurbineTrip]          = active end    ---@param active boolean

-- power rescaling limiter test
function sounder.test_power_scale()
    local start = util.time_ms()

    zero()

    for id = 1, #TONES do
        if TONES[id].active then
            for i = 1, 4 do
                for s = 1, _05s_SAMPLES do
                    alarm_ctl.quad_buffer[i][s] = limit(alarm_ctl.quad_buffer[i][s] +
                        (TONES[id].component[i][s] / math.sqrt(alarm_ctl.num_active)))
                end
            end
        end
    end

    log.debug("power rescale test took " .. (util.time_ms() - start) .. "ms")
end

--#endregion

return sounder

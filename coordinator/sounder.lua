--
-- Alarm Sounder
--

local audio = require("scada-common.audio")
local log   = require("scada-common.log")

---@class sounder
local sounder = {}

local alarm_ctl = {
    speaker = nil,
    volume = 0.5,
    stream = audio.new_stream()
}

-- start audio or continue audio on buffer empty
---@return boolean success successfully added buffer to audio output
local function play()
    if not alarm_ctl.playing then
        alarm_ctl.playing = true
        return sounder.continue()
    else return true end
end

-- initialize the annunciator alarm system
---@param speaker table speaker peripheral
---@param volume number speaker volume
function sounder.init(speaker, volume)
    alarm_ctl.speaker = speaker
    alarm_ctl.speaker.stop()
    alarm_ctl.volume = volume
    alarm_ctl.stream.stop()

    audio.generate_tones()
end

-- reconnect the speaker peripheral
---@param speaker table speaker peripheral
function sounder.reconnect(speaker)
    alarm_ctl.speaker = speaker
    alarm_ctl.playing = false
    alarm_ctl.stream.stop()
end

-- set alarm tones
---@param states table alarm tone commands from supervisor
function sounder.set(states)
    -- set tone states
    for id = 1, #states do alarm_ctl.stream.set_active(id, states[id]) end

    -- re-compute output if needed, then play audio if available
    if alarm_ctl.stream.is_recompute_needed() then alarm_ctl.stream.compute_buffer() end
    if alarm_ctl.stream.has_next_block() then play() else sounder.stop() end
end

-- stop all audio and clear output buffer
function sounder.stop()
    alarm_ctl.playing = false
    alarm_ctl.speaker.stop()
    alarm_ctl.stream.stop()
end

-- continue audio on buffer empty
---@return boolean success successfully added buffer to audio output
function sounder.continue()
    local success = false

    if alarm_ctl.playing then
        if alarm_ctl.speaker ~= nil and alarm_ctl.stream.has_next_block() then
            success = alarm_ctl.speaker.playAudio(alarm_ctl.stream.get_next_block(), alarm_ctl.volume)
            if not success then log.error("SOUNDER: error playing audio") end
        end
    end

    return success
end

--#region Test Functions

-- function sounder.test_1() add(1) play() end -- play tone T_340Hz_Int_2Hz
-- function sounder.test_2() add(2) play() end -- play tone T_544Hz_440Hz_Alt
-- function sounder.test_3() add(3) play() end -- play tone T_660Hz_Int_125ms
-- function sounder.test_4() add(4) play() end -- play tone T_745Hz_Int_1Hz
-- function sounder.test_5() add(5) play() end -- play tone T_800Hz_Int
-- function sounder.test_6() add(6) play() end -- play tone T_800Hz_1000Hz_Alt
-- function sounder.test_7() add(7) play() end -- play tone T_1000Hz_Int
-- function sounder.test_8() add(8) play() end -- play tone T_1800Hz_Int_4Hz

-- function sounder.test_breach(active)    test_alarms[ALARM.ContainmentBreach]    = active end    ---@param active boolean
-- function sounder.test_rad(active)       test_alarms[ALARM.ContainmentRadiation] = active end    ---@param active boolean
-- function sounder.test_lost(active)      test_alarms[ALARM.ReactorLost]          = active end    ---@param active boolean
-- function sounder.test_crit(active)      test_alarms[ALARM.CriticalDamage]       = active end    ---@param active boolean
-- function sounder.test_dmg(active)       test_alarms[ALARM.ReactorDamage]        = active end    ---@param active boolean
-- function sounder.test_overtemp(active)  test_alarms[ALARM.ReactorOverTemp]      = active end    ---@param active boolean
-- function sounder.test_hightemp(active)  test_alarms[ALARM.ReactorHighTemp]      = active end    ---@param active boolean
-- function sounder.test_wasteleak(active) test_alarms[ALARM.ReactorWasteLeak]     = active end    ---@param active boolean
-- function sounder.test_highwaste(active) test_alarms[ALARM.ReactorHighWaste]     = active end    ---@param active boolean
-- function sounder.test_rps(active)       test_alarms[ALARM.RPSTransient]         = active end    ---@param active boolean
-- function sounder.test_rcs(active)       test_alarms[ALARM.RCSTransient]         = active end    ---@param active boolean
-- function sounder.test_turbinet(active)  test_alarms[ALARM.TurbineTrip]          = active end    ---@param active boolean

--#endregion

return sounder

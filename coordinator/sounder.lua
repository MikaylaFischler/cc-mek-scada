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
    if alarm_ctl.stream.any_active() then play() else sounder.stop() end
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

return sounder

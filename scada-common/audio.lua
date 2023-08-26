--
-- Audio & Tone Control for Alarms
--

-- sounds modeled after https://www.e2s.com/references-and-guidelines/listen-and-download-alarm-tones

-- note: max samples = 0x20000 (128 * 1024 samples)

local _2_PI        = 2 * math.pi    -- 2 whole pies, hope you're hungry
local _DRATE       = 48000          -- 48kHz audio
local _MAX_VAL     = 127 / 2        -- max signed integer in this 8-bit audio
local _05s_SAMPLES = 24000          -- half a second worth of samples

---@class audio
local audio = {}

---@enum TONE
local TONE = {
    T_340Hz_Int_2Hz = 1,
    T_544Hz_440Hz_Alt = 2,
    T_660Hz_Int_125ms = 3,
    T_745Hz_Int_1Hz = 4,
    T_800Hz_Int = 5,
    T_800Hz_1000Hz_Alt = 6,
    T_1000Hz_Int = 7,
    T_1800Hz_Int_4Hz = 8
}

audio.TONE = TONE

local tone_data = {
    { {}, {}, {}, {} }, -- 340Hz @ 2Hz Intermittent
    { {}, {}, {}, {} }, -- 544Hz 100mS / 440Hz 400mS Alternating
    { {}, {}, {}, {} }, -- 660Hz @ 125ms On 125ms Off
    { {}, {}, {}, {} }, -- 745Hz @ 1Hz Intermittent
    { {}, {}, {}, {} }, -- 800Hz @ 0.25s On 1.75s Off
    { {}, {}, {}, {} }, -- 800/1000Hz @ 0.25s Alternating
    { {}, {}, {}, {} }, -- 1KHz 1s on, 1s off Intermittent
    { {}, {}, {}, {} }  -- 1.8KHz @ 4Hz Intermittent
}

-- calculate how many samples are in the given number of milliseconds
---@nodiscard
---@param ms integer milliseconds
---@return integer samples
local function ms_to_samples(ms) return math.floor(ms * 48) end

--#region Tone Generation (the Maths)

-- 340Hz @ 2Hz Intermittent
local function gen_tone_1()
    local t, dt = 0, _2_PI * 340 / _DRATE

    for i = 1, _05s_SAMPLES do
        local val = math.floor(math.sin(t) * _MAX_VAL)
        tone_data[1][1][i] = val
        tone_data[1][3][i] = val
        tone_data[1][2][i] = 0
        tone_data[1][4][i] = 0
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

        tone_data[2][1][i] = value
        tone_data[2][2][i] = value
        tone_data[2][3][i] = value
        tone_data[2][4][i] = value
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
                tone_data[3][set][i] = val
                t = (t + dt) % _2_PI
            else
                t = 0
                tone_data[3][set][i] = 0
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
        tone_data[4][1][i] = val
        tone_data[4][3][i] = val
        tone_data[4][2][i] = 0
        tone_data[4][4][i] = 0
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
            tone_data[5][1][i] = val
        else
            tone_data[5][1][i] = 0
        end

        tone_data[5][2][i] = 0
        tone_data[5][3][i] = 0
        tone_data[5][4][i] = 0

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

        tone_data[6][1][i] = val
        tone_data[6][2][i] = val
        tone_data[6][3][i] = val
        tone_data[6][4][i] = val
    end
end

-- 1KHz 1s on, 1s off Intermittent
local function gen_tone_7()
    local t, dt = 0, _2_PI * 1000 / _DRATE

    for i = 1, _05s_SAMPLES do
        local val = math.floor(math.sin(t) * _MAX_VAL)
        tone_data[7][1][i] = val
        tone_data[7][2][i] = val
        tone_data[7][3][i] = 0
        tone_data[7][4][i] = 0
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

        tone_data[8][1][i] = val
        tone_data[8][2][i] = val
        tone_data[8][3][i] = val
        tone_data[8][4][i] = val
    end
end

--#endregion

-- generate all 8 tone sequences
function audio.generate_tones()
    gen_tone_1(); gen_tone_2(); gen_tone_3(); gen_tone_4(); gen_tone_5(); gen_tone_6(); gen_tone_7(); gen_tone_8()
end

-- hard audio limiter
---@nodiscard
---@param output number output level
---@return number limited -128.0 to 127.0
local function limit(output)
    return math.max(-128, math.min(127, output))
end

-- clear output buffer
---@param buffer table quad buffer
local function clear(buffer)
    for i = 1, 4 do
        for s = 1, _05s_SAMPLES do buffer[i][s] = 0 end
    end
end

-- create a new audio tone stream controller
function audio.new_stream()
    local self = {
        any_active = false,
        need_recompute = false,
        next_block = 1,
        -- split audio up into 0.5s samples, so specific components can be ended quicker
        quad_buffer = { {}, {}, {}, {} },
        -- all tone enable states
        tone_active = { false, false, false, false, false, false, false, false }
    }

    clear(self.quad_buffer)

    ---@class tone_stream
    local public = {}

    -- add a tone to the output buffer
    ---@param index TONE tone ID
    ---@param active boolean active state
    function public.set_active(index, active)
        if self.tone_active[index] ~= nil then
            if self.tone_active[index] ~= active then self.need_recompute = true end
            self.tone_active[index] = active
        end
    end

    -- check if a tone is active
    ---@param index TONE tone index
    function public.is_active(index)
        if self.tone_active[index] then return self.tone_active[index] end
        return false
    end

    -- set all tones inactive, reset next block, and clear output buffer
    function public.stop()
        for i = 1, #self.tone_active do self.tone_active[i] = false end
        self.next_block = 1
        clear(self.quad_buffer)
    end

    -- check if the output buffer needs to be recomputed due to changes
    function public.is_recompute_needed() return self.need_recompute end

    -- re-compute the output buffer
    function public.compute_buffer()
        clear(self.quad_buffer)

        self.need_recompute = false
        self.any_active = false

        for id = 1, #tone_data do
            if self.tone_active[id] then
                self.any_active = true
                for i = 1, 4 do
                    local buffer = self.quad_buffer[i]
                    local values = tone_data[id][i]
                    for s = 1, _05s_SAMPLES do self.quad_buffer[i][s] = limit(buffer[s] + values[s]) end
                end
            end
        end
    end

    -- check if any alarms are active
    function public.any_active() return self.any_active end

    -- check if the next audio block has data
    function public.has_next_block() return #self.quad_buffer[self.next_block] > 0 end

    -- get the next audio block
    function public.get_next_block()
        local block = self.quad_buffer[self.next_block]
        self.next_block = self.next_block + 1
        if self.next_block > 4 then self.next_block = 1 end
        return block
    end

    return public
end

return audio

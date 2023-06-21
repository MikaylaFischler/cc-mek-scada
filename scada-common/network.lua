--
-- Network Communications
--

local md5    = require("lockbox.digest.md5")
local sha256 = require("lockbox.digest.sha2_256")
local pbkdf2 = require("lockbox.kdf.pbkdf2")
local hmac   = require("lockbox.mac.hmac")
local stream = require("lockbox.util.stream")
local array  = require("lockbox.util.array")
local comms  = require("scada-common.comms")

local log    = require("scada-common.log")
local util   = require("scada-common.util")

local network = {}

local c_eng = {
    key = nil,
    hmac = nil
}

-- initialize message authentication system
---@param passkey string facility passkey
---@return integer init_time milliseconds init took
function network.init_mac(passkey)
    local start = util.time_ms()

    local key_deriv = pbkdf2()

    -- setup PBKDF2
    key_deriv.setPassword(passkey)
    key_deriv.setSalt("pepper")
    key_deriv.setIterations(32)
    key_deriv.setBlockLen(8)
    key_deriv.setDKeyLen(16)
    key_deriv.setPRF(hmac().setBlockSize(64).setDigest(sha256))
    key_deriv.finish()

    c_eng.key = array.fromHex(key_deriv.asHex())

    -- initialize HMAC
    c_eng.hmac = hmac()
    c_eng.hmac.setBlockSize(64)
    c_eng.hmac.setDigest(md5)
    c_eng.hmac.setKey(c_eng.key)

    local init_time = util.time_ms() - start
    log.info("network.init_mac completed in " .. init_time .. "ms")

    return init_time
end

-- generate HMAC of message
---@nodiscard
---@param message string initial value concatenated with ciphertext
local function compute_hmac(message)
    local start = util.time_ms()

    c_eng.hmac.init()
    c_eng.hmac.update(stream.fromString(message))
    c_eng.hmac.finish()

    local hash = c_eng.hmac.asHex()

    log.debug("compute_hmac(): hmac-md5 = " .. util.strval(hash) ..  " (took " .. (util.time_ms() - start) .. "ms)")

    return hash
end

-- NIC: Network Interface Controller<br>
-- utilizes HMAC-MD5 for message authentication, if enabled
---@param modem table modem to use
function network.nic(modem)
    local self = {
        connected = (modem ~= nil),
        channels = {}
    }

    ---@class nic
    ---@field open function
    ---@field isOpen function
    ---@field close function
    ---@field closeAll function
    ---@field isWireless function
    ---@field getNameLocal function
    ---@field getNamesRemote function
    ---@field isPresentRemote function
    ---@field getTypeRemote function
    ---@field hasTypeRemote function
    ---@field getMethodsRemote function
    ---@field callRemote function
    local public = {}

    -- connect to a modem peripheral
    ---@param reconnected_modem table
    function public.connect(reconnected_modem)
        modem = reconnected_modem
        self.connected = true

        -- open previously opened channels
        for _, channel in ipairs(self.channels) do
            modem.open(channel)
        end

        -- link all public functions except for transmit
        for key, func in pairs(modem) do
            if key ~= "transmit" and key ~= "open" and key ~= "close" and key ~= "closeAll" then public[key] = func end
        end
    end

    -- flag this NIC as no longer having a connected modem (usually do to peripheral disconnect)
    function public.disconnect() self.connected = false end

    -- check if this NIC has a connected modem
    ---@nodiscard
    function public.connected() return self.connected end

    -- check if a peripheral is this modem
    ---@nodiscard
    ---@param device table
    function public.is_modem(device) return device == modem end

    -- wrap modem functions, then create custom transmit
    public.connect(modem)

    function public.open(channel)
        if self.connected then
            modem.open(channel)

            local already_open = false
            for i = 1, #self.channels do
                if self.channels[i] == channel then
                    already_open = true
                    break
                end
            end

            if not already_open then
                table.insert(self.channels, channel)
            end
        end
    end

    function public.close(channel)
        if self.connected then
            modem.close(channel)
            for i = 1, #self.channels do
                if self.channels[i] == channel then
                    table.remove(self.channels, i)
                    return
                end
            end
        end
    end

    function public.closeAll()
        if self.connected then
            modem.closeAll()
            self.channels = {}
        end
    end

    -- send a packet, with message authentication if configured
    ---@param dest_channel integer destination channel
    ---@param local_channel integer local channel
    ---@param packet scada_packet packet raw_sendable
    function public.transmit(dest_channel, local_channel, packet)
        if self.connected then
            if c_eng.hmac ~= nil then
                local start = util.time_ms()
                local message = textutils.serialize(packet.raw_verifiable(), { allow_repetitions = true, compact = true })
                local computed_hmac = compute_hmac(message)

                packet.set_mac(computed_hmac)

                log.debug("crypto.modem.transmit: data processing took " .. (util.time_ms() - start) .. "ms")
            end

            modem.transmit(dest_channel, local_channel, packet.raw_sendable())
        end
    end

    -- parse in a modem message as a network packet
    ---@nodiscard
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any packet sent with or without message authentication
    ---@param distance integer transmission distance
    ---@return scada_packet|nil packet received packet if valid and passed authentication check
    function public.receive(side, sender, reply_to, message, distance)
        local packet = nil

        if self.connected then
            local s_packet = comms.scada_packet()

            -- parse packet as generic SCADA packet
            s_packet.receive(side, sender, reply_to, message, distance)

            if s_packet.is_valid() then
                if c_eng.hmac ~= nil then
                    local start = util.time_ms()
                    local packet_hmac = s_packet.mac()
                    local computed_hmac = compute_hmac(textutils.serialize(s_packet.raw_verifiable(), { allow_repetitions = true, compact = true }))

                    if packet_hmac == computed_hmac then
                        log.debug("crypto.modem.receive: HMAC verified in " .. (util.time_ms() - start) .. "ms")
                        packet = s_packet
                    else
                        log.debug("crypto.modem.receive: HMAC failed verification in " .. (util.time_ms() - start) .. "ms")
                    end
                else
                    packet = s_packet
                end
            end
        end

        return packet
    end

    return public
end

return network

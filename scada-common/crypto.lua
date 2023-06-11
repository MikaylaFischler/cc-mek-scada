--
-- Cryptographic Communications Engine
--

local md5      = require("lockbox.digest.md5")
local sha2_256 = require("lockbox.digest.sha2_256")
local pbkdf2   = require("lockbox.kdf.pbkdf2")
local hmac     = require("lockbox.mac.hmac")
local stream   = require("lockbox.util.stream")
local array    = require("lockbox.util.array")
local comms    = require("scada-common.comms")

local log      = require("scada-common.log")
local util     = require("scada-common.util")

local crypto = {}

local c_eng = {
    key = nil,
    hmac = nil
}

-- initialize cryptographic system
function crypto.init(password)
    local key_deriv = pbkdf2()

    -- setup PBKDF2
    key_deriv.setPassword(password)
    key_deriv.setSalt("pepper")
    key_deriv.setIterations(32)
    key_deriv.setBlockLen(8)
    key_deriv.setDKeyLen(16)

    local start = util.time_ms()

    key_deriv.setPRF(hmac().setBlockSize(64).setDigest(sha2_256))
    key_deriv.finish()

    local message = "pbkdf2 key derivation took " .. (util.time_ms() - start) .. "ms"
    log.dmesg(message, "CRYPTO", colors.yellow)
    log.info("crypto.init: " .. message)

    c_eng.key = array.fromHex(key_deriv.asHex())

    -- initialize HMAC
    c_eng.hmac = hmac()
    c_eng.hmac.setBlockSize(64)
    c_eng.hmac.setDigest(md5)
    c_eng.hmac.setKey(c_eng.key)

    message = "init: completed in " .. (util.time_ms() - start) .. "ms"
    log.dmesg(message, "CRYPTO", colors.yellow)
    log.info("crypto." .. message)
end

-- generate HMAC of message
---@nodiscard
---@param message string initial value concatenated with ciphertext
function crypto.hmac(message)
    local start = util.time_ms()

    c_eng.hmac.init()
    c_eng.hmac.update(stream.fromString(message))
    c_eng.hmac.finish()

    local hash = c_eng.hmac.asHex()

    log.debug("crypto.hmac: hmac-md5 took " .. (util.time_ms() - start) .. "ms")
    log.debug("crypto.hmac: hmac = " .. util.strval(hash))

    return hash
end

-- wrap a modem as a secure modem to send encrypted traffic
---@param modem table modem to wrap
function crypto.secure_modem(modem)
    ---@class secure_modem
    ---@field open function
    ---@field isOpen function
    ---@field close function
    ---@field closeAll function
    ---@field isWireless function
    ---@field getNamesRemote function
    ---@field isPresentRemote function
    ---@field getTypeRemote function
    ---@field hasTypeRemote function
    ---@field getMethodsRemote function
    ---@field callRemote function
    ---@field getNameLocal function
    local public = {}

    -- wrap a modem
    ---@param reconnected_modem table
    function public.wrap(reconnected_modem)
        modem = reconnected_modem
        for key, func in pairs(modem) do
            public[key] = func
        end
    end

    -- wrap modem functions, then we replace transmit
    public.wrap(modem)

    -- send a packet with message authentication
    ---@param packet scada_packet packet raw_sendable
    function public.transmit(packet)
        local start = util.time_ms()
        local message = textutils.serialize(packet.raw_verifiable(), { allow_repetitions = true, compact = true })
        local computed_hmac = crypto.hmac(message)

        packet.set_mac(computed_hmac)

        log.debug("crypto.transmit: data processing took " .. (util.time_ms() - start) .. "ms")

        modem.transmit(packet.remote_channel(), packet.local_channel(), packet.raw_sendable())
    end

    -- parse in a modem message as a network packet
    ---@nodiscard
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any packet sent with message authentication
    ---@param distance integer transmission distance
    ---@return scada_packet|nil packet received packet if valid and passed authentication check
    function public.receive(side, sender, reply_to, message, distance)
        local packet = nil
        local s_packet = comms.scada_packet()

        -- parse packet as generic SCADA packet
        s_packet.receive(side, sender, reply_to, message, distance)

        if s_packet.is_valid() then
            local start = util.time_ms()
            local packet_hmac = s_packet.mac()
            local computed_hmac = crypto.hmac(textutils.serialize(s_packet.raw_verifiable(), { allow_repetitions = true, compact = true }))

            if packet_hmac == computed_hmac then
                log.debug("crypto.secure_modem.receive: HMAC verified in " .. (util.time_ms() - start) .. "ms")
                packet = s_packet
            else
                log.debug("crypto.secure_modem.receive: HMAC failed verification in " .. (util.time_ms() - start) .. "ms")
            end
        end

        return packet
    end

    return public
end

return crypto

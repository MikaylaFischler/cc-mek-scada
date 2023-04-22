--
-- Cryptographic Communications Engine
--

local aes128   = require("lockbox.cipher.aes128")
local ctr_mode = require("lockbox.cipher.mode.ctr")
local sha1     = require("lockbox.digest.sha1")
local sha2_256 = require("lockbox.digest.sha2_256")
local pbkdf2   = require("lockbox.kdf.pbkdf2")
local hmac     = require("lockbox.mac.hmac")
local zero_pad = require("lockbox.padding.zero")
local stream   = require("lockbox.util.stream")
local array    = require("lockbox.util.array")

local log      = require("scada-common.log")
local util     = require("scada-common.util")

local crypto = {}

local c_eng = {
    key = nil,
    cipher = nil,
    decipher = nil,
    hmac = nil
}

---@alias hex string

-- initialize cryptographic system
function crypto.init(password, server_port)
    local key_deriv = pbkdf2()

    -- setup PBKDF2
    -- the primary goal is to just turn our password into a 16 byte key
    key_deriv.setPassword(password)
    key_deriv.setSalt("salty_salt_at_" .. server_port)
    key_deriv.setIterations(32)
    key_deriv.setBlockLen(8)
    key_deriv.setDKeyLen(16)

    local start = util.time()

    key_deriv.setPRF(hmac().setBlockSize(64).setDigest(sha2_256))
    key_deriv.finish()

    log.dmesg("pbkdf2: key derivation took " .. (util.time() - start) .. "ms", "CRYPTO", colors.yellow)

    c_eng.key = array.fromHex(key_deriv.asHex())

    -- initialize cipher
    c_eng.cipher = ctr_mode.Cipher()
    c_eng.cipher.setKey(c_eng.key)
    c_eng.cipher.setBlockCipher(aes128)
    c_eng.cipher.setPadding(zero_pad)

    -- initialize decipher
    c_eng.decipher = ctr_mode.Decipher()
    c_eng.decipher.setKey(c_eng.key)
    c_eng.decipher.setBlockCipher(aes128)
    c_eng.decipher.setPadding(zero_pad)

    -- initialize HMAC
    c_eng.hmac = hmac()
    c_eng.hmac.setBlockSize(64)
    c_eng.hmac.setDigest(sha1)
    c_eng.hmac.setKey(c_eng.key)

    log.dmesg("init: completed in " .. (util.time() - start) .. "ms", "CRYPTO", colors.yellow)
end

-- encrypt plaintext
---@nodiscard
---@param plaintext string
---@return table initial_value, string ciphertext
function crypto.encrypt(plaintext)
    local start = util.time()

    -- initial value
    local iv = {
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255),
        math.random(0, 255)
    }

    log.debug("crypto.random: iv random took " .. (util.time() - start) .. "ms")

    start = util.time()

    c_eng.cipher.init()
    c_eng.cipher.update(stream.fromArray(iv))
    c_eng.cipher.update(stream.fromString(plaintext))
    c_eng.cipher.finish()

    local ciphertext = c_eng.cipher.asHex()    ---@type hex

    log.debug("crypto.encrypt: aes128-ctr-mode took " .. (util.time() - start) .. "ms")
    log.debug("ciphertext: " .. util.strval(ciphertext))

    return iv, ciphertext
end

-- decrypt ciphertext
---@nodiscard
---@param iv string CTR initial value
---@param ciphertext string ciphertext hex
---@return string plaintext
function crypto.decrypt(iv, ciphertext)
    local start = util.time()

    c_eng.decipher.init()
    c_eng.decipher.update(stream.fromArray(iv))
    c_eng.decipher.update(stream.fromHex(ciphertext))
    c_eng.decipher.finish()

    local plaintext_hex = c_eng.decipher.asHex()   ---@type hex

    local plaintext = stream.toString(stream.fromHex(plaintext_hex))

    log.debug("crypto.decrypt: aes128-ctr-mode took " .. (util.time() - start) .. "ms")
    log.debug("plaintext: " .. util.strval(plaintext))

    return plaintext
end

-- generate HMAC of message
---@nodiscard
---@param message_hex string initial value concatenated with ciphertext
function crypto.hmac(message_hex)
    local start = util.time()

    c_eng.hmac.init()
    c_eng.hmac.update(stream.fromHex(message_hex))
    c_eng.hmac.finish()

    local hash = c_eng.hmac.asHex()    ---@type hex

    log.debug("crypto.hmac: hmac-sha1 took " .. (util.time() - start) .. "ms")
    log.debug("hmac: " .. util.strval(hash))

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
---@diagnostic disable-next-line: redefined-local
    function public.wrap(reconnected_modem)
        modem = reconnected_modem
        for key, func in pairs(modem) do
            public[key] = func
        end
    end

    -- wrap modem functions, then we replace transmit
    public.wrap(modem)

    -- send a packet with encryption
    ---@param channel integer
    ---@param reply_channel integer
    ---@param payload table packet raw_sendable
    function public.transmit(channel, reply_channel, payload)
        local plaintext = textutils.serialize(payload, { allow_repetitions = true, compact = true })

        local iv, ciphertext = crypto.encrypt(plaintext)
---@diagnostic disable-next-line: redefined-local
        local computed_hmac = crypto.hmac(iv .. ciphertext)

        modem.transmit(channel, reply_channel, { computed_hmac, iv, ciphertext })
    end

    -- parse in a modem message as a network packet
    ---@nodiscard
    ---@param side string modem side
    ---@param sender integer sender port
    ---@param reply_to integer reply port
    ---@param message any encrypted packet sent with secure_modem.transmit
    ---@param distance integer transmission distance
    ---@return string side, integer sender, integer reply_to, any plaintext_message, integer distance
    function public.receive(side, sender, reply_to, message, distance)
        local body = ""

        if type(message) == "table" then
            if #message == 3 then
---@diagnostic disable-next-line: redefined-local
                local rx_hmac = message[1]
                local iv = message[2]
                local ciphertext = message[3]

                local computed_hmac = crypto.hmac(iv .. ciphertext)

                if rx_hmac == computed_hmac then
                    -- message intact
                    local plaintext = crypto.decrypt(iv, ciphertext)
                    body = textutils.unserialize(plaintext)

                    if body == nil then
                        -- failed decryption
                        log.debug("crypto.secure_modem: decryption failed")
                        body = ""
                    end
                else
                    -- something went wrong
                    log.debug("crypto.secure_modem: hmac mismatch violation")
                end
            end
        end

        return side, sender, reply_to, body, distance
    end

    return public
end

return crypto

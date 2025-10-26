--
-- Network Communications and Message Authentication
--

local comms  = require("scada-common.comms")
local log    = require("scada-common.log")
local ppm    = require("scada-common.ppm")
local util   = require("scada-common.util")

local md5    = require("lockbox.digest.md5")
local sha1   = require("lockbox.digest.sha1")
local pbkdf2 = require("lockbox.kdf.pbkdf2")
local hmac   = require("lockbox.mac.hmac")
local stream = require("lockbox.util.stream")
local array  = require("lockbox.util.array")

---@class scada_net_interface
local network = {}

-- cryptography engine
local _crypt = {
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
    key_deriv.setPRF(hmac().setBlockSize(64).setDigest(sha1))
    key_deriv.setBlockLen(20)
    key_deriv.setDKeyLen(20)
    key_deriv.setIterations(256)
    key_deriv.setSalt("pepper")
    key_deriv.setPassword(passkey)
    key_deriv.finish()

    _crypt.key = array.fromHex(key_deriv.asHex())

    -- initialize HMAC
    _crypt.hmac = hmac()
    _crypt.hmac.setBlockSize(64)
    _crypt.hmac.setDigest(md5)
    _crypt.hmac.setKey(_crypt.key)

    local init_time = util.time_ms() - start
    log.info("NET: network.init_mac completed in " .. init_time .. "ms")

    return init_time
end

-- de-initialize message authentication system
function network.deinit_mac()
    _crypt.key, _crypt.hmac = nil, nil
end

-- generate HMAC of message
---@nodiscard
---@param message string initial value concatenated with ciphertext
local function compute_hmac(message)
    -- local start = util.time_ms()

    _crypt.hmac.init()
    _crypt.hmac.update(stream.fromString(message))
    _crypt.hmac.finish()

    local hash = _crypt.hmac.asHex()

    -- log.debug("NET: compute_hmac(): hmac-md5 = " .. util.strval(hash) ..  " (took " .. (util.time_ms() - start) .. "ms)")

    return hash
end

-- NIC: Network Interface Controller<br>
-- utilizes HMAC-MD5 for message authentication, if enabled and this is wireless
---@param modem Modem|nil modem to use
function network.nic(modem)
    local self = {
        -- modem interface name
        iface = "?",
        -- phy name
        name = "?",
        -- used to quickly return out of tx/rx functions if there is nothing to do
        connected = false,
        -- used to avoid costly MAC calculations if not required
        use_hash = false,
        -- open channels
        channels = {}
    }

    ---@class nic:Modem
    local public = {}

    -- get the phy name
    ---@nodiscard
    function public.phy_name() return self.name end

    -- check if this NIC has a connected modem
    ---@nodiscard
    function public.is_connected() return self.connected end

    -- connect to a modem peripheral
    ---@param reconnected_modem Modem
    function public.connect(reconnected_modem)
        modem = reconnected_modem

        self.iface     = ppm.get_iface(modem)
        self.name      = util.c(util.trinary(modem.isWireless(), "WLAN_PHY", "ETH_PHY"), "{", self.iface, "}")
        self.connected = true
        self.use_hash  = _crypt.hmac and modem.isWireless()

        -- open only previously opened channels
        modem.closeAll()
        for _, channel in ipairs(self.channels) do
            modem.open(channel)
        end

        -- link all public functions except for transmit, open, and close
        for key, func in pairs(modem) do
            if key ~= "transmit" and key ~= "open" and key ~= "close" and key ~= "closeAll" then public[key] = func end
        end
    end

    -- flag this NIC as no longer having a connected modem (usually do to peripheral disconnect)
    function public.disconnect() self.connected = false end

    -- check if a peripheral is this modem
    ---@nodiscard
    ---@param device table
    function public.is_modem(device) return device == modem end

    -- wrap modem functions, then create custom functions
    if modem then public.connect(modem) end

    -- open a channel on the modem<br>
    -- if disconnected *after* opening, previousy opened channels will be re-opened on reconnection
    ---@param channel integer
    function public.open(channel)
        if modem then modem.open(channel) end

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

    -- close a channel on the modem
    ---@param channel integer
    function public.close(channel)
        if modem then modem.close(channel) end

        for i = 1, #self.channels do
            if self.channels[i] == channel then
                table.remove(self.channels, i)
                return
            end
        end
    end

    -- close all channels on the modem
    function public.closeAll()
        if modem then modem.closeAll() end
        self.channels = {}
    end

    -- send a packet, with message authentication if configured
    ---@param dest_channel integer destination channel
    ---@param local_channel integer local channel
    ---@param packet scada_packet packet
    function public.transmit(dest_channel, local_channel, packet)
        if self.connected then
            local tx_packet = packet ---@type authd_packet|scada_packet

            if self.use_hash then
                -- local start = util.time_ms()
                tx_packet = comms.authd_packet()

                ---@cast tx_packet authd_packet
                tx_packet.make(packet, compute_hmac)

                -- log.debug("NET: network.modem.transmit: data processing took " .. (util.time_ms() - start) .. "ms")
            end

---@diagnostic disable-next-line: need-check-nil
            modem.transmit(dest_channel, local_channel, tx_packet.raw_sendable())
        else
            log.debug("NET: network.transmit tx dropped, link is down")
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

        if self.connected and side == self.iface then
            local s_packet = comms.scada_packet()

            if self.use_hash then
                -- parse packet as an authenticated SCADA packet
                local a_packet = comms.authd_packet()
                a_packet.receive(side, sender, reply_to, message, distance)

                if a_packet.is_valid() then
                    s_packet.receive(side, sender, reply_to, a_packet.data(), distance)

                    if s_packet.is_valid() then
                        -- local start         = util.time_ms()
                        local computed_hmac = compute_hmac(textutils.serialize(s_packet.raw_header(), { allow_repetitions = true, compact = true }))

                        if a_packet.mac() == computed_hmac then
                            -- log.debug("NET: network.modem.receive: HMAC verified in " .. (util.time_ms() - start) .. "ms")
                            s_packet.stamp_authenticated()
                        else
                            -- log.debug("NET: network.modem.receive: HMAC failed verification in " .. (util.time_ms() - start) .. "ms")
                        end
                    end
                end
            else
                -- parse packet as a generic SCADA packet
                s_packet.receive(side, sender, reply_to, message, distance)
            end

            if s_packet.is_valid() then packet = s_packet end
        end

        return packet
    end

    return public
end

return network

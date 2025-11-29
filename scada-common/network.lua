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

local LINK_TIMEOUT_MS          = 5000
local DISCOVERY_PERIOD_UP_MS   = 5000
local DISCOVERY_PERIOD_DOWN_MS = 1000

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
    log.info("NET: network.init_mac() completed in " .. init_time .. "ms")

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

-- Network Interface Controller (NIC)<br>
-- sends and receives network frames using a modem<br>
-- utilizes HMAC-MD5 for message authentication, if enabled and using a wireless modem
---@param modem Modem|nil modem to use
---@param lld_tx_chan integer? link layer discovery transmit channel, or nil to disable probing (will still reply)
function network.nic(modem, lld_tx_chan)
    local self = {
        -- modem interface name
        iface = "?",
        -- phy name
        name = "?",
        -- used to avoid costly MAC calculations if not required
        use_hash = false,
        -- used to quickly return out of tx/rx functions if there is nothing to do
        phy_up = false,
        -- monitor if this NIC appears to have network access
        link_up = false,
        -- last time a discovery reply or other traffic was received
        last_lld_rx = 0,
        -- last time of discovery transmit
        last_lld_tx = 0,
        -- open channels
        channels = {}
    }

    -- send a link-layer discovery frame
    ---@param dest_addr integer destination address
    ---@param r_chan integer remote channel
    ---@param l_chan integer local channel
    local function _send_ll_discovery_frame(dest_addr, r_chan, l_chan)
        if not self.phy_up then return end

        local reply = comms.lld_frame()

        reply.make(dest_addr, util.time_ms() + 5000)

---@diagnostic disable-next-line: need-check-nil
        modem.transmit(r_chan, l_chan, reply.raw_frame())
    end

    ---@class nic:Modem
    local public = {}

    -- get the phy name
    ---@nodiscard
    function public.phy_name() return self.name end

    -- check if this NIC has a connected modem
    ---@nodiscard
    function public.is_connected() return self.phy_up end

    -- check if this NIC detected a network link
    ---@nodiscard
    function public.is_network_up() return self.link_up end

    -- connect to a modem peripheral
    ---@param reconnected_modem Modem
    function public.connect(reconnected_modem)
        modem = reconnected_modem

        self.iface    = ppm.get_iface(modem)
        self.name     = util.c(util.trinary(modem.isWireless(), "WLAN_PHY", "ETH_PHY"), "{", self.iface, "}")
        self.use_hash = _crypt.hmac and modem.isWireless()
        self.phy_up   = true
        self.link_up  = false

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
    function public.disconnect()
        self.phy_up  = false
        self.link_up = false
    end

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

    -- send a frame, with message authentication if configured
    ---@param dest_channel integer destination channel
    ---@param local_channel integer local channel
    ---@param frame scada_frame frame
    function public.transmit(dest_channel, local_channel, frame)
        if self.phy_up then
            local tx_frame = frame ---@type authd_frame|scada_frame

            if self.use_hash then
                -- local start = util.time_ms()
                tx_frame = comms.authd_frame()
                tx_frame.make(frame, compute_hmac)
                -- log.debug("NET: network.nic.transmit(): data processing took " .. (util.time_ms() - start) .. "ms")
            end

---@diagnostic disable-next-line: need-check-nil
            modem.transmit(dest_channel, local_channel, tx_frame.raw_frame())
        else
            log.debug("NET: network.transmit() tx dropped, phy is down")
        end
    end

    -- parse in modem frame components as a SCADA network frame
    ---@nodiscard
    ---@param side string modem side
    ---@param sender integer sender channel
    ---@param reply_to integer reply channel
    ---@param message any SCADA frame sent with or without message authentication
    ---@param distance integer transmission distance
    ---@return scada_frame|nil frame received frame if valid and passed authentication check
    function public.receive(side, sender, reply_to, message, distance)
        local frame = nil

        if self.phy_up and side == self.iface then
            local s_frame = comms.scada_frame()

            if self.use_hash then
                -- parse frame as an authenticated SCADA frame
                local a_frame = comms.authd_frame()

                if a_frame.receive(side, sender, reply_to, message, distance) then
                    if s_frame.receive(side, sender, reply_to, a_frame.data(), distance) then
                        -- local start         = util.time_ms()
                        local computed_hmac = compute_hmac(textutils.serialize(s_frame.raw_header(), { allow_repetitions = true, compact = true }))

                        if a_frame.mac() == computed_hmac then
                            -- log.debug("NET: network.nic.receive(): HMAC verified in " .. (util.time_ms() - start) .. "ms")
                            s_frame.stamp_authenticated()
                        else
                            -- log.debug("NET: network.nic.receive(): HMAC failed verification in " .. (util.time_ms() - start) .. "ms")
                        end
                    end
                end
            else
                -- parse frame as a generic SCADA frame
                s_frame.receive(side, sender, reply_to, message, distance)
            end

            -- if valid, return it, otherwise try to handle it as a link-layer transaction
            if s_frame.is_valid() then
                self.link_up     = true
                self.last_lld_rx = util.time_ms()

                frame = s_frame
            else
                local l_frame = comms.lld_frame()

                -- try instead to receive this as a link-layer discovery frame, then respond if valid
                -- keep the returned value as nil; this is internal layer 2 logic to hide from the application
                if l_frame.receive(side, sender, reply_to, message, distance) then
                    self.link_up     = true
                    self.last_lld_rx = util.time_ms()

                    _send_ll_discovery_frame(l_frame.src_addr(), l_frame.remote_channel(), l_frame.local_channel())
                end
            end
        end

        return frame
    end

    -- periodic NIC task to maintain network link detection
    function public.periodic()
        local now = util.time_ms()

        if now >= (self.last_lld_rx + LINK_TIMEOUT_MS) then
            self.link_up = false
        end

        if lld_tx_chan and self.phy_up then
            if (now - self.last_lld_tx) > util.trinary(self.link_up, DISCOVERY_PERIOD_UP_MS, DISCOVERY_PERIOD_DOWN_MS) then
                for _, channel in ipairs(self.channels) do
                    _send_ll_discovery_frame(comms.BROADCAST, channel, lld_tx_chan)
                end
            end
        end
    end

    return public
end

return network

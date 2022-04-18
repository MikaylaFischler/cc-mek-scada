-- #REQUIRES comms.lua

-- supervisory controller communications
function superv_comms(mode, num_reactors, modem, dev_listen, fo_channel, sv_channel)
    local self = {
        mode = mode,
        seq_num = 0,
        num_reactors = num_reactors,
        modem = modem,
        dev_listen = dev_listen,
        fo_channel = fo_channel,
        sv_channel = sv_channel,
        reactor_struct_cache = nil
    }

    -- PRIVATE FUNCTIONS --

    -- open all channels
    local _open_channels = function ()
        if not self.modem.isOpen(self.dev_listen) then
            self.modem.open(self.dev_listen)
        end
        if not self.modem.isOpen(self.fo_channel) then
            self.modem.open(self.fo_channel)
        end
        if not self.modem.isOpen(self.sv_channel) then
            self.modem.open(self.sv_channel)
        end
    end

    -- PUBLIC FUNCTIONS --

    -- reconnect a newly connected modem
    local reconnect_modem = function (modem)
        self.modem = modem
        _open_channels()
    end

    return {
        reconnect_modem = reconnect_modem
    }
end

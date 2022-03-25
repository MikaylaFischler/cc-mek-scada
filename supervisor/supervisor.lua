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
end

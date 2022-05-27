local comms = require("scada-common.comms")

local coordinator = {}

-- coordinator communications
coordinator.coord_comms = function ()
    local self = {
        reactor_struct_cache = nil
    }
end

return coordinator

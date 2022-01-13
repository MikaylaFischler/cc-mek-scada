
function server_comms()
    local self = {
        reactor_struct_cache = nil
    }

    local record_struct = function (id, mek_data)
    end

    -- send the structure data by request to pocket computers
    local send_struct = function ()
    end

    local command_waste = function ()
    end
end

function rplc_comms(id, modem, local_port, server_port, reactor)
    local self = {
        _id = id,
        _modem = modem,
        _server = server_port,
        _local = local_port,
        _reactor = reactor,
        _status_cache = nil,
        
        _send = function (msg)
            self._modem.transmit(self._server, self._local, msg)
        end
    }

    local _send = function (msg)
        self._modem.transmit(self._server, self._local, msg)
    end

    -- variable reactor status information, excluding heating rate
    local _reactor_status = function ()
        return {
            status     = self._reactor.getStatus(),
            burn_rate  = self._reactor.getBurnRate(),
            act_burn_r = self._reactor.getActualBurnRate(),
            temp       = self._reactor.getTemperature(),
            damage     = self._reactor.getDamagePercent(),
            boil_eff   = self._reactor.getBoilEfficiency(),
            env_loss   = self._reactor.getEnvironmentalLoss(),

            fuel       = self._reactor.getFuel(),
            fuel_need  = self._reactor.getFuelNeeded(),
            fuel_fill  = self._reactor.getFuelFilledPercentage(),
            waste      = self._reactor.getWaste(),
            waste_need = self._reactor.getWasteNeeded(),
            waste_fill = self._reactor.getWasteFilledPercentage(),
            cool_type  = self._reactor.getCoolant()['name'],
            cool_amnt  = self._reactor.getCoolant()['amount'],
            cool_need  = self._reactor.getCoolantNeeded(),
            cool_fill  = self._reactor.getCoolantFilledPercentage(),
            hcool_type = self._reactor.getHeatedCoolant()['name'],
            hcool_amnt = self._reactor.getHeatedCoolant()['amount'],
            hcool_need = self._reactor.getHeatedCoolantNeeded(),
            hcool_fill = self._reactor.getHeatedCoolantFilledPercentage()
        }
    end

    local _status_changed = function ()
        local status = self._reactor_status()
        local changed = false

        for key, value in pairs() do
            if value ~= _status_cache[key] then
                changed = true
                break
            end
        end

        return changed
    end

    -- attempt to establish link with
    local send_link_req = function ()
        local linking_data = {
            id = self._id,
            type = "link_req"
        }

        _send(linking_data)
    end

    -- send structure properties (these should not change)
    -- server will cache these
    local send_struct = function ()
        local mek_data = {
            heat_cap  = self._reactor.getHeatCapacity(),
            fuel_asm  = self._reactor.getFuelAssemblies(),
            fuel_sa   = self._reactor.getFuelSurfaceArea(),
            fuel_cap  = self._reactor.getFuelCapacity(),
            waste_cap = self._reactor.getWasteCapacity(),
            cool_cap  = self._reactor.getCoolantCapacity(),
            hcool_cap = self._reactor.getHeatedCoolantCapacity(),
            max_burn  = self._reactor.getMaxBurnRate()
        }

        local struct_packet = {
            id = self._id,
            type = "struct_data",
            mek_data = mek_data
        }

        _send(struct_packet)
    end

    -- send live status information
    local send_status = function ()
        local mek_data = self._reactor_status()

        local sys_data = {
            timestamp = os.time(),
            control_state = false,
            overridden = false,
            faults = {},
            waste_production = "antimatter" -- "plutonium", "polonium", "antimatter"
        }
    end

    local send_keep_alive = function ()
        -- heating rate is volatile, so it is skipped in status
        -- send it with keep alive packets
        local mek_data = {
            heating_rate  = self._reactor.getHeatingRate()
        }

        -- basic keep alive packet to server
        local keep_alive_packet = {
            id = self._id,
            type = "keep_alive",
            timestamp = os.time(),
            mek_data = mek_data
        }

        _send(keep_alive_packet)
    end

    local handle_link = function (packet)
        if packet.type == "link_response" then
            return packet.accepted
        else
            return "wrong_type"
        end
    end

    return {
        send_link_req = send_link_req,
        send_struct = send_struct,
        send_status = send_status,
        send_keep_alive = send_keep_alive,
        handle_link = handle_link
    }
end
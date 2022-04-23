SEVERITY = {
    INFO = 0,       -- basic info message
    WARNING = 1,    -- warning about some abnormal state
    ALERT = 2,      -- important device state changes
    FACILITY = 3,   -- facility-wide alert
    SAFETY = 4,     -- safety alerts
    EMERGENCY = 5   -- critical safety alarm
}

function scada_alarm(severity, device, message)
    local self = {
        time = os.epoch(),
        ts_string = os.date("[%H:%M:%S]"),
        severity = severity,
        device = device,
        message = message
    }

    local format = function ()
        return self.ts_string .. " [" .. severity_to_string(self.severity) .. "] (" .. self.device ") >> " .. self.message
    end

    local properties = function ()
        return {
            time = self.time,
            severity = self.severity,
            device = self.device,
            message = self.message
        }
    end

    return {
        format = format,
        properties = properties
    }
end

function severity_to_string(severity)
    if severity == SEVERITY.INFO then
        return "INFO"
    elseif severity == SEVERITY.WARNING then
        return "WARNING"
    elseif severity == SEVERITY.ALERT then
        return "ALERT"
    elseif severity == SEVERITY.FACILITY then
        return "FACILITY"
    elseif severity == SEVERITY.SAFETY then
        return "SAFETY"
    elseif severity == SEVERITY.EMERGENCY then
        return "EMERGENCY"
    else
        return "UNKNOWN"
    end
end

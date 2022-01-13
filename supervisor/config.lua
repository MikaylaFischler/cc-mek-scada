-- type ('active','backup')
-- 'active' system carries through instructions and control
-- 'backup' system serves as a hot backup, still recieving data 
--      from all PLCs and coordinator(s) while in backup to allow 
--      instant failover if active goes offline without re-sync
SYSTEM_TYPE = 'active'

-- scada network
SCADA_NET_PFX = 16000
-- failover synchronization
SCADA_FO_CHANNEL = 16001
-- listen port for SCADA supervisor access
SCADA_SV_CHANNEL = 16002
-- listen port for PLC's
SCADA_PLC_LISTEN = 16003

-- expected number of reactors
NUM_REACTORS = 4

-- Global Aliases

--#region General Aliases

---@alias ppm_generic PPMDevice | { [string]: function }

---@alias color integer

---@alias auto_ctl_cfg [ PROCESS, number, integer, integer, number, number, number[] ]
---@alias auto_start_ack [ boolean, PROCESS, number, integer, integer, number, number, number[] ]

-- the PLC status message consists of the following:
-- - timestamp
-- - requested control state
-- - no reactor flag
-- - formed flag
-- - auto command acknowledgement token (indicates auto command received prior to this status update)
-- - reportable fuel-based burn limit, or false if unlimited (allowing up to max_burn)
-- - reactor heating rate
-- - reactor data, if changed
---@alias plc_status_msg [ integer, boolean, boolean, boolean, integer, number|false, number, table|nil ]

---@alias rtu_advert_msg [ RTU_UNIT_TYPE, integer|false, integer, IO_PORT[][]|nil ][]

--#endregion

--#region Pocket Aliases

---@alias pkt__sect_construct_data { [1]: pocket_app, [2]: Div, [3]: Div[], [4]: { [string]: function }, [5]: [ string, string, string, function ][], [6]: cpair, [7]: cpair }
---@alias pkt__doc_item pocket_doc_sect|pocket_doc_subsect|pocket_doc_text|pocket_doc_note|pocket_doc_tip|pocket_doc_list

--#endregion

--#region String Aliases

---@alias side
---|"top"
---|"bottom"
---|"left"
---|"right"
---|"front"
---|"back"

---@alias os_event
---| "alarm"
---| "char"
---| "computer_command"
---| "disk"
---| "disk_eject"
---| "http_check"
---| "http_failure"
---| "http_success"
---| "key"
---| "key_up"
---| "modem_message"
---| "monitor_resize"
---| "monitor_touch"
---| "mouse_click"
---| "mouse_drag"
---| "mouse_scroll"
---| "mouse_up"
---| "double_click" (custom)
---| "paste"
---| "peripheral"
---| "peripheral_detach"
---| "rednet_message"
---| "redstone"
---| "speaker_audio_empty"
---| "task_complete"
---| "term_resize"
---| "terminate"
---| "timer"
---| "turtle_inventory"
---| "websocket_closed"
---| "websocket_failure"
---| "websocket_message"
---| "websocket_success"
---| "conn_test_complete" (custom)

---@alias fluid
---| "mekanism:empty_gas"
---| "minecraft:water"
---| "mekanism:sodium"
---| "mekanism:superheated_sodium"

---@alias rps_trip_cause
---| "ok"
---| "high_dmg"
---| "high_temp"
---| "low_coolant"
---| "ex_waste"
---| "ex_heated_coolant"
---| "no_fuel"
---| "fault"
---| "timeout"
---| "manual"
---| "automatic"
---| "sys_fail"
---| "force_disabled"

---@alias container_mode
---| "BOTH"
---| "FILL"
---| "EMPTY"

---@alias dumping_mode
---| "IDLE"
---| "DUMPING"
---| "DUMPING_EXCESS"

--#endregion

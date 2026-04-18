-- Global Classes

-- Note: uses of generic `table` type can be found by searching the following regex: @(param \w+|type|return) table

---@class tank_fluid
---@field name fluid liquid/gas tag name
---@field amount integer amount in mB

---@class item_stack
---@field name string liquid/gas tag name
---@field count integer amount in mB
---@field nbt string JSON NBT string

---@class radiation_reading
---@field radiation number reading value
---@field unit string reading unit

---@class coordinate_2d
---@field x integer x position
---@field y integer y position

---@class coordinate
---@field x integer x position
---@field y integer y position
---@field z integer z position

---@class rtu_advertisement
---@field type RTU_UNIT_TYPE unit type
---@field index integer|false unit device index
---@field reactor integer reactor assignment, 0 for facility
---@field rs_conns IO_PORT[][]|nil redstone connections (only for redstone units)

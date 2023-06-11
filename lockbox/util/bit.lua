-- modified (simplified) for ComputerCraft

local ok, e = nil, nil

if not ok then
    ok, e = pcall(require, "bit32") -- Lua 5.2
end

if not ok then
    ok, e = pcall(require, "bit")
end

if not ok then
    error("no bitwise support found", 2)
end

assert(type(e) == "table", "invalid bit module")

return e

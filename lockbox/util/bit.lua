local ok, e
ok = nil
if not ok then
    ok, e = pcall(require, "bit") -- the LuaJIT one ?
end
if not ok then
    ok, e = pcall(require, "bit32") -- Lua 5.2
end
if not ok then
    ok, e = pcall(require, "bit.numberlua") -- for Lua 5.1, https://github.com/tst2005/lua-bit-numberlua/
end
if not ok then
    error("no bitwise support found", 2)
end
assert(type(e) == "table", "invalid bit module")

-- Workaround to support Lua 5.2 bit32 API with the LuaJIT bit one
if e.rol and not e.lrotate then
    e.lrotate = e.rol
end
if e.ror and not e.rrotate then
    e.rrotate = e.ror
end

return e

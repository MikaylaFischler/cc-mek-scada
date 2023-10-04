return {
-- initialize booted environment
init_env = function ()
    local _require, _env = require("cc.require"), setmetatable({}, { __index = _ENV })
    -- overwrite require/package globals
    require, package = _require.make(_env, "/")
    -- reset terminal
    term.clear(); term.setCursorPos(1, 1)
end
}

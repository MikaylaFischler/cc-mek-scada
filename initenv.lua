--
-- Initialize the Post-Boot Module Environment
--

return {
    -- initialize booted environment
    init_env = function ()
        local _require = require("cc.require")
        local _env = setmetatable({}, { __index = _ENV })

        -- overwrite require/package globals
        require, package = _require.make(_env, "/")

        -- reset terminal
        term.clear()
        term.setCursorPos(1, 1)
    end
}

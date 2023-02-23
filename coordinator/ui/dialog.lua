local completion = require("cc.completion")

local util       = require("scada-common.util")

local print = util.print

local dialog = {}

-- ask the user yes or no
---@nodiscard
---@param question string
---@param default boolean
---@return boolean|nil
function dialog.ask_y_n(question, default)
    print(question)

    if default == true then
        print(" (Y/n)? ")
    else
        print(" (y/N)? ")
    end

    local response = read(nil, nil)

    if response == "" then
        return default
    elseif response == "Y" or response == "y" then
        return true
    elseif response == "N" or response == "n" then
        return false
    else
        return nil
    end
end

-- ask the user for an input within a set of options
---@nodiscard
---@param options table
---@param cancel string
---@return boolean|string|nil
function dialog.ask_options(options, cancel)
    print("> ")
    local response = read(nil, nil, function(text) return completion.choice(text, options) end)

    if response == cancel then return false end

    if util.table_contains(options, response) then
        return response
    else return nil end
end

return dialog

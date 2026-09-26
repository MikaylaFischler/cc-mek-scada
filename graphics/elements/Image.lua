-- Image Graphics Element

local element = require("graphics.element")

---@class image_args
---@field data? string CC paintutils comptaible string
---@field nfp? string CC NFP format image file path
---@field parent graphics_element
---@field id? string element id
---@field x? integer 1 if omitted
---@field y? integer auto incremented if omitted
---@field width? integer parent width if omitted
---@field height? integer minimum necessary height for wrapped text if omitted
---@field gframe? graphics_frame frame instead of x/y/width/height
---@field fg_bg? cpair foreground/background colors
---@field hidden? boolean true to hide on initial draw

-- Create a new image element.
---@param args image_args
---@return Image element, element_id id
return function (args)
    element.assert(type(args.data) == "string" or type(args.nfp) == "string", "data or nfp is required")

    -- create new graphics element base object
    local e = element.new(args --[[@as graphics_args]])

    -- draw image
    function e.redraw()
        e.window.clear()

        local image

        if args.data then
            image = paintutils.parseImage(args.data)
        else
            image = paintutils.loadImage(args.nfp)
        end

        if image then
            local old_term = term.redirect(e.window)

            paintutils.drawImage(image, 1, 1)
            term.redirect(old_term)
        end
    end

    ---@class Image:graphics_element
    local Image, id = e.complete(true)

    return Image, id
end

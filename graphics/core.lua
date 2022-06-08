local core = {}

local events = {}

---@class monitor_touch
---@field monitor string
---@field x integer
---@field y integer

-- create a new touch event definition
---@param monitor string
---@param x integer
---@param y integer
---@return monitor_touch
function events.touch(monitor, x, y)
    return {
        monitor = monitor,
        x = x,
        y = y
    }
end

core.events = events

local graphics = {}

---@alias TEXT_ALIGN integer
graphics.TEXT_ALIGN = {
    LEFT = 1,
    CENTER = 2,
    RIGHT = 3
}

---@class graphics_border
---@field width integer
---@field color color
---@field even boolean

-- create a new border definition
---@param width integer border width
---@param color color border color
---@param even boolean whether to pad width extra to account for rectangular pixels
---@return graphics_border
function graphics.border(width, color, even)
    return {
        width = width,
        color = color,
        even = even
    }
end

---@class graphics_frame
---@field x integer
---@field y integer
---@field w integer
---@field h integer

-- create a new graphics frame definition
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@return graphics_frame
function graphics.gframe(x, y, w, h)
    return {
        x = x,
        y = y,
        w = w,
        h = h
    }
end

---@class cpair
---@field color_a color
---@field color_b color
---@field blit_a string
---@field blit_b string
---@field fgd color
---@field bkg color
---@field blit_fgd string
---@field blit_bkg string

-- create a new color pair definition
---@param a color
---@param b color
---@return cpair
function graphics.cpair(a, b)
    return {
        -- color pairs
        color_a = a,
        color_b = b,
        blit_a = a,
        blit_b = b,
        -- aliases
        fgd = a,
        bkg = b,
        blit_fgd = colors.toBlit(a),
        blit_bkg = colors.toBlit(b)
    }
end

core.graphics = graphics

return core

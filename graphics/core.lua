local core = {}

local events = {}

---@class monitor_touch
---@field monitor string
---@field x integer
---@field y integer

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

---@param width integer
---@param color color
---@return graphics_border
function graphics.border(width, color)
    return {
        width = width,
        color = color
    }
end

---@class graphics_frame
---@field x integer
---@field y integer
---@field w integer
---@field h integer

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
---@field fgd color
---@field bkg color
---@field blit_fgd string
---@field blit_bkg string

---@param foreground color
---@param background color
---@return cpair
function graphics.cpair(foreground, background)
    return {
        fgd = foreground,
        bkg = background,
        blit_fgd = colors.toBlit(foreground),
        blit_bkg = colors.toBlit(background)
    }
end

core.graphics = graphics

return core

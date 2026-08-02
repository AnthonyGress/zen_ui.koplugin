local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")

local M = {}
local cache = {}

function M.paint(bb, cover_left, cover_right, cover_top, cover_h,
                 span, band_thick, label, font_size, fill_color, border_color)
    local c = 0.70711
    local width = math.ceil((span + band_thick * 2) * 1.41422)
    local height = band_thick
    if width <= 0 or height <= 0 then return end

    local fill = fill_color:getColorRGB32()
    local cache_key = string.format("%d|%d|%d|%s|%d|%d|%d|%d|%d",
        width, height, bb:getType(), label, font_size,
        fill.r, fill.g, fill.b, border_color:getColor8().a)
    local banner = cache[cache_key]

    if not banner then
        banner = Blitbuffer.new(width, height, bb:getType())
        if not banner then return end
        banner:paintRectRGB32(0, 0, width, height, border_color)
        if height > 2 then
            banner:paintRectRGB32(0, 1, width, height - 2, fill_color)
        end

        local max_width = math.floor(width * 0.82)
        local max_height = math.max(1, height - 2)
        local text
        local text_size
        local size = font_size
        repeat
            if text and text.free then text:free() end
            text = TextWidget:new{
                text = label,
                face = Font:getFace("cfont", size),
                bold = true,
                fgcolor = border_color,
                padding = 0,
            }
            text_size = text:getSize()
            if text_size.w <= max_width and text_size.h <= max_height then break end
            size = size - 1
        until size < 6
        text:paintTo(
            banner,
            math.max(0, math.floor((width - text_size.w) / 2)),
            math.max(0, math.floor((height - text_size.h) / 2))
        )
        if text.free then text:free() end
        cache[cache_key] = banner
    end

    local center_x = cover_right - math.floor(span / 2)
    local center_y = cover_top + math.floor(span / 2)
    local half_box = math.ceil((width + height) * c / 2) + 1
    local bb_width = bb:getWidth()
    local bb_height = bb:getHeight()
    local half_width = width / 2
    local half_height = height / 2
    for dy = center_y - half_box, center_y + half_box do
        if dy >= cover_top and dy < cover_top + cover_h and dy >= 0 and dy < bb_height then
            local relative_y = dy - center_y
            for dx = center_x - half_box, center_x + half_box do
                if dx >= cover_left and dx < cover_right and dx >= 0 and dx < bb_width then
                    local relative_x = dx - center_x
                    local source_x = math.floor(half_width + (relative_x + relative_y) * c)
                    local source_y = math.floor(half_height + (relative_y - relative_x) * c)
                    if source_x >= 0 and source_x < width
                            and source_y >= 0 and source_y < height then
                        bb:setPixel(dx, dy, banner:getPixel(source_x, source_y))
                    end
                end
            end
        end
    end
end

return M

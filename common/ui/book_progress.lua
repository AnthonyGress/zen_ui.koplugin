local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextWidget = require("ui/widget/textwidget")
local utils = require("common/utils")

local M = {}

local function clamp_ratio(value)
    value = tonumber(value)
    if not value then return nil end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function paint_pill(bb, x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    if h <= 1 then
        bb:paintRect(x, y, w, h, color)
        return
    end
    local radius = math.floor(h / 2)
    if w <= h then
        local center_x = x + math.floor(w / 2)
        for row = 0, h - 1 do
            local dy = row - radius + 0.5
            local half = math.floor(math.sqrt(math.max(0,
                radius * radius - dy * dy)) + 0.5)
            local row_x = math.max(x, center_x - half)
            local row_w = math.min(w, half * 2)
            if row_w > 0 then bb:paintRect(row_x, y + row, row_w, 1, color) end
        end
        return
    end
    for row = 0, h - 1 do
        local dy = row - radius + 0.5
        local inset = math.floor(radius - math.sqrt(math.max(0,
            radius * radius - dy * dy)) + 0.5)
        local row_w = w - inset * 2
        if row_w > 0 then bb:paintRect(x + inset, y + row, row_w, 1, color) end
    end
end

function M.bar(ratio, width, height)
    ratio = clamp_ratio(ratio) or 0
    width = math.max(1, math.floor(tonumber(width) or 1))
    height = math.max(1, math.floor(tonumber(height) or 1))
    local fill_w = math.floor(width * ratio)
    return {
        dimen = Geom:new{ w = width, h = height },
        getSize = function(self) return self.dimen end,
        handleEvent = function() return false end,
        free = function() end,
        paintTo = function(_self, bb, x, y)
            paint_pill(bb, x, y, width, height, Blitbuffer.COLOR_LIGHT_GRAY)
            if fill_w > 0 then
                paint_pill(bb, x, y, math.min(width, math.max(fill_w, height)),
                    height, Blitbuffer.COLOR_GRAY_5)
            end
        end,
    }
end

function M.build(opts)
    opts = opts or {}
    local ratio = clamp_ratio(opts.ratio)
    if ratio == nil then return nil end

    local width = math.max(1, math.floor(tonumber(opts.width) or 1))
    local bar_h = math.max(1, math.floor(tonumber(opts.bar_height) or 1))
    local left_text = opts.left_text
        or string.format("%d%%", math.floor(ratio * 100 + 0.5))
    local pages = tonumber(opts.pages)
    local right_text = opts.right_text
        or (pages and pages > 0 and utils.formatPageCount(pages, true) or "")
    local left = TextWidget:new{
        text = left_text,
        face = opts.face,
        bold = opts.bold == true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    local right = TextWidget:new{
        text = right_text,
        face = opts.face,
        bold = opts.bold == true,
        fgcolor = Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
    local gap = math.max(2, math.floor(tonumber(opts.gap) or width * 0.02))
    local bar_w = math.max(20,
        width - left:getSize().w - right:getSize().w - gap * 2)
    return HorizontalGroup:new{
        align = "center",
        left,
        HorizontalSpan:new{ width = gap },
        M.bar(ratio, bar_w, bar_h),
        HorizontalSpan:new{ width = gap },
        right,
    }
end

return M

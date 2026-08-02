local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local Screen = require("device").screen
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local Widget = require("ui/widget/widget")
local CoverUtils = require("common/cover_utils")

local M = {}

local function get_uniform_ratio()
    local g = rawget(_G, "G_reader_settings")
    local ratio_str = g and g:readSetting("uniform_cover_ratio") or "2:3"
    local n, d = tostring(ratio_str):match("(%d+):(%d+)")
    return (tonumber(n) or 2) / (tonumber(d) or 3)
end

local function calc_uniform_dims(max_w, max_h)
    local ratio = get_uniform_ratio()
    if max_h * ratio <= max_w then
        return math.floor(max_h * ratio), max_h
    end
    return max_w, math.floor(max_w / ratio)
end

local function rounded_enabled()
    local plug = rawget(_G, "__ZEN_UI_PLUGIN")
    if plug and type(plug.config) == "table"
       and type(plug.config.features) == "table"
    then
        return plug.config.features.browser_cover_rounded_corners == true
    end
    local cfg = require("config/manager").get()
    return type(cfg) == "table"
        and type(cfg.features) == "table"
        and cfg.features.browser_cover_rounded_corners == true
end

-- Restore the corner pixels from a pre-paint snapshot of the background so the
-- rounded corners reveal whatever was behind the cover (page or library bg
-- image) instead of an opaque white square. snap origin is (ox, oy) absolute.
local function paint_corner_masks(bb, tx, ty, tw, th, r, snap, ox, oy)
    for j = 0, r - 1 do
        local inner = math.sqrt(r * r - (r - j) * (r - j))
        local cut = math.ceil(r - inner)
        if cut > 0 then
            bb:blitFrom(snap, tx, ty + j, tx - ox, ty + j - oy, cut, 1)
            bb:blitFrom(snap, tx + tw - cut, ty + j, tx + tw - cut - ox, ty + j - oy, cut, 1)
            bb:blitFrom(snap, tx, ty + th - 1 - j, tx - ox, ty + th - 1 - j - oy, cut, 1)
            bb:blitFrom(snap, tx + tw - cut, ty + th - 1 - j, tx + tw - cut - ox, ty + th - 1 - j - oy, cut, 1)
        end
    end
end

local function paint_corner_border_arcs(bb, tx, ty, tw, th, r, bsz)
    local color = Blitbuffer.COLOR_BLACK
    local r_outer = r
    local r_inner = r - bsz
    for j = 0, r - 1 do
        for c = 0, r - 1 do
            local dx = r - c - 0.5
            local dy = r - j - 0.5
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist >= r_inner and dist <= r_outer then
                bb:paintRect(tx + c, ty + j, 1, 1, color)
                bb:paintRect(tx + tw - 1 - c, ty + j, 1, 1, color)
                bb:paintRect(tx + c, ty + th - 1 - j, 1, 1, color)
                bb:paintRect(tx + tw - 1 - c, ty + th - 1 - j, 1, 1, color)
            end
        end
    end
end

local function paint_rect_border(bb, tx, ty, tw, th, bsz)
    local color = Blitbuffer.COLOR_BLACK
    for i = 0, bsz - 1 do
        bb:paintRect(tx + i, ty, 1, th, color)
        bb:paintRect(tx + tw - 1 - i, ty, 1, th, color)
        bb:paintRect(tx, ty + i, tw, 1, color)
        bb:paintRect(tx, ty + th - 1 - i, tw, 1, color)
    end
end

local function paint_rounded_border_edges(bb, tx, ty, tw, th, r, bsz)
    local color = Blitbuffer.COLOR_BLACK
    local x1 = tx + r
    local x2 = tx + tw - r
    local y1 = ty + r
    local y2 = ty + th - r
    if x2 > x1 then
        for i = 0, bsz - 1 do
            bb:paintRect(x1, ty + i, x2 - x1, 1, color)
            bb:paintRect(x1, ty + th - 1 - i, x2 - x1, 1, color)
        end
    end
    if y2 > y1 then
        for i = 0, bsz - 1 do
            bb:paintRect(tx + i, y1, 1, y2 - y1, color)
            bb:paintRect(tx + tw - 1 - i, y1, 1, y2 - y1, color)
        end
    end
end

local function apply_cover_border(frame, rounded)
    local orig_paintTo = frame.paintTo
    if type(orig_paintTo) ~= "function" then return end
    local base_radius = Screen:scaleBySize(8)
    frame.paintTo = function(self, bb, x, y)
        -- For rounded corners we need the background that sits *behind* the
        -- cover so the corner cut-outs can reveal it. Snapshot the target rect
        -- before the cover paints over it.
        local snap
        if rounded then
            local w, h = self:getSize().w, self:getSize().h
            if w and h and w > 0 and h > 0 then
                snap = Blitbuffer.new(w, h, bb:getType())
                snap:blitFrom(bb, 0, 0, x, y, w, h)
            end
        end
        orig_paintTo(self, bb, x, y)
        local d = self.dimen
        if not (d and d.w and d.h and d.w > 0 and d.h > 0) then
            if snap then snap:free() end
            return
        end
        local tx, ty, tw, th = d.x, d.y, d.w, d.h
        local bsz = math.max(1, self.bordersize or 0)
        if not rounded then
            paint_rect_border(bb, tx, ty, tw, th, bsz)
            return
        end
        local max_r = math.floor((math.min(tw, th) - 1) / 2)
        local r = math.min(base_radius, max_r)
        if r < 2 or not snap then
            paint_rect_border(bb, tx, ty, tw, th, bsz)
            if snap then snap:free() end
            return
        end
        paint_corner_masks(bb, tx, ty, tw, th, r, snap, x, y)
        paint_rounded_border_edges(bb, tx, ty, tw, th, r, bsz)
        paint_corner_border_arcs(bb, tx, ty, tw, th, r, bsz)
        snap:free()
    end
end

function M.make_cover_widget(book, max_w, max_h, opts)
    opts = opts or {}
    local border = tonumber(opts.border) or 1
    local bg = opts.background or Blitbuffer.COLOR_LIGHT_GRAY
    local target_w, target_h = calc_uniform_dims(max_w, max_h)
    if target_w < 18 then target_w = 18 end
    if target_h < 28 then target_h = 28 end

    local child
    if book and book.cover_bb then
        local cover_bb = book.cover_bb
        book.cover_bb = nil
        child = ImageWidget:new{
            image = cover_bb,
            image_disposable = true,
            width = target_w,
            height = target_h,
        }
    elseif book and type(book.path) == "string" and book.path ~= "" then
        local fake_cover = CoverUtils.genCover(book.path, target_w, target_h)
        if fake_cover then
            child = ImageWidget:new{
                image = fake_cover,
                image_disposable = true,
                width = target_w,
                height = target_h,
                scale_factor = 1,
            }
        end
    end
    if not child then
        child = Widget:new{
            dimen = Geom:new{ w = target_w, h = target_h },
        }
    end

    local frame = FrameContainer:new{
        width = target_w,
        height = target_h,
        padding = 0,
        bordersize = border,
        background = bg,
        CenterContainer:new{
            dimen = Geom:new{ w = target_w, h = target_h },
            child,
        },
    }

    if type(opts.decorate) == "function" then
        opts.decorate(frame)
    end
    if border > 0 then
        apply_cover_border(frame, rounded_enabled())
    end

    return frame, target_w, target_h
end

return M

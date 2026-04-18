local function apply_zen_pagination_bar()
    -- Replaces the pagination footer with a pill-shaped horizontal scroll bar
    -- showing current page position in the file browser.
    --
    -- The bar is purely visual – no touch handling is installed on it.
    local Blitbuffer = require("ffi/blitbuffer")
    local Device     = require("device")
    local Geom       = require("ui/geometry")
    local Menu       = require("ui/widget/menu")
    local Screen     = Device.screen
    local target_menus = {
        filemanager = true,
        history = true,
        collections = true,
    }

    -- Visual dimensions (scaled to device DPI).
    local BAR_H      = Screen:scaleBySize(5)   -- pill height (track and thumb share this)
    local BAR_W_PCT  = 0.92                     -- track width as fraction of screen width
    local BAR_PAD    = Screen:scaleBySize(5)    -- vertical padding above and below the pill
    local FOOTER_H   = BAR_H + BAR_PAD * 2     -- total height reserved at the bottom

    local TRACK_COLOR = Blitbuffer.COLOR_LIGHT_GRAY
    local THUMB_COLOR = Blitbuffer.COLOR_BLACK

    -- Draw a filled pill (stadium) shape using scanlines.
    -- Uses only bb:paintRect – the sole safe Blitbuffer primitive.
    -- r  = min(w, h) / 2  →  each end cap is a perfect semicircle.
    local function paintPill(bb, px, py, pw, ph, color)
        if pw <= 0 or ph <= 0 then return end
        local r = math.min(pw, ph) / 2.0
        for row = 0, ph - 1 do
            local dy    = (row + 0.5) - (ph * 0.5)   -- signed dist from centre row
            local inset = 0
            if math.abs(dy) < r then
                -- Horizontal inset imposed by the circular end-cap at this row.
                inset = math.ceil(r - math.sqrt(r * r - dy * dy))
            end
            local rw = pw - 2 * inset
            if rw > 0 then
                bb:paintRect(px + inset, py + row, rw, 1, color)
            end
        end
    end

    local orig_menu_init = Menu.init

    function Menu:init()
        orig_menu_init(self)

        if not target_menus[self.name]
           and not (self.covers_fullscreen and self.is_borderless and self.title_bar_fm_style) then
            return
        end

        if not self.page_info or not self.page_info_text or not self.page_return_arrow then
            return
        end

        local menu   = self
        local scr_w  = Screen:getWidth()
        local bar_w  = math.floor(scr_w * BAR_W_PCT)
        local bar_x  = math.floor((scr_w - bar_w) / 2)   -- centred offset from left edge
        local foot   = Geom:new{ w = scr_w, h = FOOTER_H }

        -- _recalculateDimen uses getSize().h on these two widgets to compute
        -- bottom_height.  Returning FOOTER_H reserves exactly that strip.
        self.page_info_text.getSize    = function() return foot end
        self.page_return_arrow.getSize = function() return foot end

        -- BottomContainer positions page_info at y = inner_dimen.h - h.
        self.page_info.getSize = function() return foot end

        -- Replace the chevron rendering with a pill scroll bar.
        -- x, y: absolute screen position supplied by BottomContainer.
        self.page_info.paintTo = function(_, bb, x, y)
            local nb   = menu.page_num or 1
            local page = menu.page     or 1

            -- Track (full bar width, lighter colour).
            paintPill(bb, x + bar_x, y + BAR_PAD, bar_w, BAR_H, TRACK_COLOR)

            -- Thumb (darker, positioned to reflect the current page).
            if nb <= 1 then
                -- Single page: thumb fills the whole track.
                paintPill(bb, x + bar_x, y + BAR_PAD, bar_w, BAR_H, THUMB_COLOR)
            else
                -- Thumb width is proportional to 1/nb, floored at BAR_H*2 so it
                -- remains recognisably pill-shaped even with many pages.
                local thumb_w = math.max(BAR_H * 2, math.floor(bar_w / nb))
                thumb_w       = math.min(thumb_w, bar_w)
                local travel  = bar_w - thumb_w
                local pct     = (page - 1) / (nb - 1)
                local thumb_x = bar_x + math.floor(pct * travel)
                paintPill(bb, x + thumb_x, y + BAR_PAD, thumb_w, BAR_H, THUMB_COLOR)
            end
        end

        -- Re-run layout so the new sizes take effect before the first paint.
        self:_recalculateDimen()
    end
end

return apply_zen_pagination_bar

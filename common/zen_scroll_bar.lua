local function apply_zen_scroll_bar()
    -- Replaces the pagination footer with a pill-bar or dot-style scroll indicator.
    -- Style ("bar" / "dots") is read live from config; no restart needed to toggle.
    local Blitbuffer = require("ffi/blitbuffer")
    local Device     = require("device")
    local Geom       = require("ui/geometry")
    local Menu       = require("ui/widget/menu")
    local Screen     = Device.screen
    local target_menus = {
        filemanager = true,
        history = true,
        collections = true,
        library_view = true, -- Rakuyomi
    }

    -- Visual dimensions (scaled to device DPI).
    local BAR_H      = Screen:scaleBySize(5)    -- bar track / thumb height
    local DOT_DIAM   = Screen:scaleBySize(10)   -- dot diameter (dots style)
    local DOT_GAP    = Screen:scaleBySize(12)   -- gap between dots
    local BAR_W_PCT  = 0.92                     -- track width as fraction of screen width
    local BAR_PAD    = Screen:scaleBySize(5)    -- vertical padding above and below the indicator
    -- Footer must be tall enough for the larger of bar or dots.
    local FOOTER_H   = math.max(BAR_H, DOT_DIAM) + BAR_PAD * 2

    local TRACK_COLOR    = Blitbuffer.COLOR_LIGHT_GRAY
    local THUMB_COLOR    = Blitbuffer.COLOR_BLACK
    local DOT_INACT_COLOR = Blitbuffer.COLOR_DARK_GRAY

    -- Capture plugin reference while __ZEN_UI_PLUGIN is still set.
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    -- Draw a filled pill (stadium) shape using scanline paintRect.
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

    -- Read style from config at paint time; toggle takes effect on next repaint.
    local function get_style()
        local p = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        if p
            and type(p.config) == "table"
            and type(p.config.zen_scroll_bar) == "table"
            and p.config.zen_scroll_bar.style == "dots"
        then
            return "dots"
        end
        return "bar"
    end

    local orig_menu_init = Menu.init

    function Menu:init()
        orig_menu_init(self)

        -- Check if this is a target menu:
        -- 1. Named menus (filemanager, history, collections)
        -- 2. File browser style menus (covers_fullscreen + is_borderless + title_bar_fm_style)
        -- 3. Bookmarks menu (is_borderless + title_bar_fm_style + title_bar_left_icon == "appbar.menu")
        local is_bookmarks_menu = self.is_borderless
            and self.title_bar_fm_style
            and self.title_bar_left_icon == "appbar.menu"

        if not target_menus[self.name]
           and not (self.covers_fullscreen and self.is_borderless and self.title_bar_fm_style)
           and not is_bookmarks_menu then
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

        -- Replace the chevron rendering with the configured scroll indicator.
        -- x, y: absolute screen position supplied by BottomContainer.
        self.page_info.paintTo = function(_, bb, x, y)
            local nb   = menu.page_num or 1
            local page = menu.page     or 1

            -- Nothing to show if the list fits on one page.
            if nb <= 1 then return end

            if get_style() == "dots" and nb <= 75 then
                -- Dots style
                -- One circle per page; the active page is filled black.
                local diam = DOT_DIAM
                local gap  = DOT_GAP
                local step = diam + gap

                -- If dots overflow the available width, shrink to fit.
                if step * nb - gap > bar_w then
                    step = math.max(2, math.floor(bar_w / nb))
                    diam = math.max(1, step - 1)
                end

                local total_w = step * (nb - 1) + diam
                local start_x = x + bar_x + math.floor((bar_w - total_w) / 2)
                -- Centre dots vertically within the footer strip.
                local dot_y   = y + math.floor((FOOTER_H - diam) / 2)

                for i = 1, nb do
                    local dot_x = start_x + (i - 1) * step
                    local color = (i == page) and THUMB_COLOR or DOT_INACT_COLOR
                    paintPill(bb, dot_x, dot_y, diam, diam, color)
                end
            else
                -- Bar style (default)
                -- Track (full bar width, lighter colour).
                paintPill(bb, x + bar_x, y + BAR_PAD, bar_w, BAR_H, TRACK_COLOR)

                -- Thumb (darker, positioned to reflect the current page).
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

return apply_zen_scroll_bar

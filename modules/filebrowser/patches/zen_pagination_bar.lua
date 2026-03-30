local function apply_zen_pagination_bar()
    -- Replaces the pagination footer with a thin horizontal progress bar
    -- showing current page / total pages in the file browser.
    --
    -- Approach: override getSize on page_info_text, page_return_arrow, and
    -- page_info itself to return BAR_H, so _recalculateDimen naturally reserves
    -- BAR_H at the bottom and BottomContainer positions page_info there.
    -- Then override page_info.paintTo to draw the bar instead of chevrons.
    -- No OverlapGroup surgery or _recalculateDimen override needed.

    local Blitbuffer = require("ffi/blitbuffer")
    local Device     = require("device")
    local Geom       = require("ui/geometry")
    local Menu       = require("ui/widget/menu")
    local Screen     = Device.screen
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local features = zen_plugin and zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.zen_pagination_bar == true
    end

    local target_menus = {
        filemanager = true,
        history = true,
        collections = true,
    }

    local BAR_H       = Screen:scaleBySize(3)
    local BAR_COLOR   = Blitbuffer.COLOR_BLACK
    local TRACK_COLOR = Blitbuffer.COLOR_LIGHT_GRAY

    local orig_menu_init = Menu.init

    function Menu:init()
        orig_menu_init(self)

        if not is_enabled() then return end

        if not target_menus[self.name]
           and not (self.covers_fullscreen and self.is_borderless and self.title_bar_fm_style) then
            return
        end

        if not self.page_info or not self.page_info_text or not self.page_return_arrow then
            return
        end

        local menu     = self
        local screen_w = Screen:getWidth()
        local bar_size = Geom:new{ w = screen_w, h = BAR_H }

        -- _recalculateDimen computes:
        --   bottom_height = max(page_return_arrow.h, page_info_text.h) + Size.padding.button
        -- Override both to BAR_H so only that strip is reserved at the bottom.
        self.page_info_text.getSize    = function() return bar_size end
        self.page_return_arrow.getSize = function() return bar_size end

        -- BottomContainer (footer) positions page_info at:
        --   y = inner_dimen.h - page_info:getSize().h
        -- Override to BAR_H so it lands flush at the bottom.
        self.page_info.getSize = function() return bar_size end

        -- Draw a progress bar instead of the chevron/text children.
        -- x,y are set by BottomContainer from our overridden getSize above.
        -- page_num is set by _recalculateDimen on every updateItems call.
        self.page_info.paintTo = function(_, bb, x, y)
            local nb   = menu.page_num or 1
            local page = menu.page     or 1
            local pct  = math.max(0, math.min(1, page / nb))
            local fill_w = math.max(1, math.floor(screen_w * pct))
            bb:paintRect(x, y, screen_w, BAR_H, TRACK_COLOR)
            bb:paintRect(x, y, fill_w,   BAR_H, BAR_COLOR)
        end

        -- Re-run layout with the new sizes in place.
        self:_recalculateDimen()
    end
end

return apply_zen_pagination_bar

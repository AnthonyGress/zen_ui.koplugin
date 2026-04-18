-- touch_menu_close_footer.lua
-- Redesigns the TouchMenu footer for all menu tabs:
--   LEFT slot   ← pagination (page_info: chevrons + page text).
--                 Previously held the "back/up" chevron button.
--   CENTER slot ← wide close button using icons/large_chevron_up.svg
--                 (2× icon width, same height). Always calls closeMenu().
--   RIGHT slot  ← cleared (time/battery shown in the panel status row instead).
-- Applies to every TouchMenu instance (reader, file manager, all tabs).

local function apply_touch_menu_close_footer()
    local Device         = require("device")
    local Geom           = require("ui/geometry")
    local GestureRange   = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local IconWidget     = require("ui/widget/iconwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Screen         = Device.screen

    local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

    -- Resolve this file's plugin root to locate icons/large_chevron_up.svg
    local _icon_file
    do
        local src = debug.getinfo(1, "S").source or ""
        if src:sub(1, 1) == "@" then
            local root = src:sub(2):match("^(.*)/modules/")
            if root then
                _icon_file = root .. "/icons/large_chevron_up.svg"
            end
        end
    end

    -- Minimal tappable icon widget.
    -- Uses file= so we can point at the plugin's own icons/ dir.
    -- GestureRange references self.dimen, which KOReader updates in-place
    -- after painting, so hit-testing works correctly at runtime.
    local TappableIcon = InputContainer:extend{}

    function TappableIcon:init()
        self.dimen = Geom:new{ w = self.width, h = self.height }
        self.image = IconWidget:new{
            file   = self.file,
            icon   = self.file and nil or self.icon_name,
            width  = self.width,
            height = self.height,
        }
        self[1] = self.image
        self.ges_events.TapSelect = {
            GestureRange:new{
                ges   = "tap",
                range = self.dimen,
            }
        }
    end

    function TappableIcon:onTapSelect()
        if self.callback then self.callback() end
        return true
    end

    local TouchMenu = require("ui/widget/touchmenu")
    local orig_init = TouchMenu.init

    function TouchMenu:init()
        orig_init(self)

        -- footer layout after orig_init:
        --   footer[1] = LeftContainer  { up_button (backToUpperMenu) }
        --   footer[2] = CenterContainer{ self.page_info              }
        --   footer[3] = RightContainer { self.device_info            }

        local icon_width  = Screen:scaleBySize(DGENERIC_ICON_SIZE)
        local icon_height = icon_width

        local close_btn = TappableIcon:new{
            file      = _icon_file,
            icon_name = "chevron.up",   -- fallback if file not found
            width     = icon_width * 2,
            height    = icon_height,
            callback  = function() self:closeMenu() end,
        }

        -- Move page_info (pagination) to the LEFT slot.
        -- updateItems() still updates self.page_info_text / showHide() directly,
        -- so pagination display continues to work correctly.
        if self.footer and self.footer[1] then
            self.footer[1][1] = self.page_info
        end

        -- Place the wide close button in the CENTER slot.
        if self.footer and self.footer[2] then
            self.footer[2][1] = close_btn
        end

        -- Remove the right-slot time/battery widget; the panel status row shows it.
        if self.footer and self.footer[3] then
            self.footer[3][1] = HorizontalGroup:new{}
        end
    end
end

return apply_touch_menu_close_footer

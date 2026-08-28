-- touch_menu_footer.lua
-- Redesigns the TouchMenu footer for all menu tabs:
--   LEFT slot   ← Settings on the Controls tab when configured; cleared otherwise.
--   CENTER slot ← wide button using icons/large_chevron_up.svg
--                 (2× icon width, same height). Goes up a level when
--                 in a sub-menu, or closes when at the top level.
--   RIGHT slot  ← pagination (page_info: chevrons + page text).
-- Applies to every TouchMenu instance (reader, file manager, all tabs).

local function apply_touch_menu_footer()
    local Device         = require("device")
    local Button         = require("ui/widget/button")
    local Geom           = require("ui/geometry")
    local GestureRange   = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget     = require("ui/widget/iconwidget")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local UIManager      = require("ui/uimanager")
    local inline_icons   = require("common/inline_icon_map")
    local Screen         = Device.screen
    local zen_plugin     = rawget(_G, "__ZEN_UI_PLUGIN")

    local DGENERIC_ICON_SIZE = G_defaults:readSetting("DGENERIC_ICON_SIZE")

    -- Resolve this file's plugin root to locate icons/large_chevron_up.svg
    local _icon_file
    do
        local root = require("common/plugin_root")
        if root then
            _icon_file = root .. "/icons/large_chevron_up.svg"
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

    local function show_settings_button(menu)
        local config = zen_plugin and zen_plugin.config
        local quick_settings = config and config.quick_settings
        local features = config and config.features
        local lockdown = config and config.lockdown
        local tab = menu.tab_item_table and menu.tab_item_table[menu.cur_tab]
        return tab and tab.id == "quicksettings"
            and type(quick_settings) == "table"
            and quick_settings.settings_button_in_footer == true
            and type(features) == "table" and features.quick_settings == true
            and not (type(lockdown) == "table" and lockdown.disable_settings_panel == true
                and features.lockdown_mode == true)
    end

    local function update_settings_button(menu)
        if menu.footer and menu.footer[1] then
            menu.footer[1][1] = show_settings_button(menu)
                and menu._zen_settings_footer_widget or menu._zen_empty_footer_widget
        end
    end

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
            callback  = function() self:backToUpperMenu() end,
        }
        self._zen_settings_footer_button = Button:new{
            text = inline_icons.settings,
            text_font_face = "smallinfofont",
            text_font_size = Screen:scaleBySize(16),
            text_font_bold = false,
            width = Screen:scaleBySize(56),
            height = icon_height,
            bordersize = 0,
            callback = function()
                self:closeMenu()
                UIManager:nextTick(function()
                    require("modules/settings/zen_settings_page").show(zen_plugin)
                end)
            end,
        }
        self._zen_settings_footer_widget = HorizontalGroup:new{
            HorizontalSpan:new{ width = Screen:scaleBySize(7) },
            self._zen_settings_footer_button,
        }
        self._zen_empty_footer_widget = HorizontalGroup:new{}

        -- Clear the LEFT slot.
        if self.footer and self.footer[1] then
            self.footer[1][1] = self._zen_empty_footer_widget
        end

        -- Place the wide close button in the CENTER slot.
        if self.footer and self.footer[2] then
            self.footer[2][1] = close_btn
        end

        -- Move page_info (pagination) to the RIGHT slot.
        -- updateItems() still updates self.page_info_text / showHide() directly,
        -- so pagination display continues to work correctly.
        if self.footer and self.footer[3] then
            self.footer[3][1] = self.page_info
        end
        update_settings_button(self)
    end

    local orig_switch_menu_tab = TouchMenu.switchMenuTab
    function TouchMenu:switchMenuTab(...)
        local result = orig_switch_menu_tab(self, ...)
        update_settings_button(self)
        return result
    end
end

return apply_touch_menu_footer

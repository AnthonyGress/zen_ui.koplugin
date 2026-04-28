-- Global patch: gesture handling for all Menu-based views.
--
-- South swipe, top 14% → opens the KOReader menu.
-- South swipe elsewhere → swallowed so views are never accidentally closed.
-- Tap, top 5%          → opens the KOReader menu (when tap-activation is enabled).
--
-- Patched once at the *class* level so every Menu instance inherits the
-- behaviour automatically — no per-view wiring required.
--
-- The tap GestureRange mirrors how the swipe zone is registered: in Menu:init()
-- for all non-filemanager menus (History, Favorites, Collections, etc.).
-- onTap returns nil outside the top zone so normal item-selection taps
-- propagate to MenuItem children.
local function apply_menu_top_swipe()
    local Device = require("device")
    local Menu   = require("ui/widget/menu")

    -- Swipe handler (south swipe from top opens menu, elsewhere swallowed).
    local orig_onSwipe = Menu.onSwipe

    Menu.onSwipe = function(self, arg, ges_ev)
        if ges_ev.direction == "south" then
            if ges_ev.pos.y < Device.screen:getHeight() * 0.14 then
                -- Try FileManager menu first (library / filebrowser context)
                local fm = require("apps/filemanager/filemanager").instance
                if fm and fm.menu then
                    local fm_menu = fm.menu
                    if fm_menu.activation_menu ~= "tap" then
                        fm_menu:onShowMenu(fm_menu:_getTabIndexFromLocation(ges_ev))
                        return true
                    end
                end
                -- Fall back to Reader menu (bookmarks, etc.)
                local ok_rui, RUI = pcall(require, "apps/reader/readerui")
                if ok_rui and RUI and RUI.instance then
                    local reader_menu = RUI.instance.menu
                    if reader_menu and reader_menu.activation_menu ~= "tap" then
                        reader_menu:onShowMenu(reader_menu:_getTabIndexFromLocation(ges_ev))
                        return true
                    end
                end
            end
            -- Swallow all other south swipes so views are never closed by accident.
            return true
        end
        return orig_onSwipe(self, arg, ges_ev)
    end

    -- Tap handler: register a tap GestureRange (same condition as the swipe zone)
    -- and intercept top-zone taps to open the KOReader menu.
    local GestureRange = require("ui/gesturerange")
    local orig_init = Menu.init

    Menu.init = function(self, ...)
        orig_init(self, ...)
        -- Only for menus that also register a swipe zone (non-filemanager views).
        if self.ges_events and self.ges_events.Swipe then
            self.ges_events.Tap = {
                GestureRange:new{
                    ges = "tap",
                    range = self.dimen,
                }
            }
        end
    end

    Menu.onTap = function(self, arg, ges_ev)
        if ges_ev.pos.y < Device.screen:getHeight() * 0.05 then
            local fm = require("apps/filemanager/filemanager").instance
            if fm and fm.menu then
                local fm_menu = fm.menu
                if fm_menu.activation_menu ~= "swipe" then
                    fm_menu:onShowMenu(fm_menu:_getTabIndexFromLocation(ges_ev))
                    return true
                end
            end
            local ok_rui, RUI = pcall(require, "apps/reader/readerui")
            if ok_rui and RUI and RUI.instance then
                local reader_menu = RUI.instance.menu
                if reader_menu and reader_menu.activation_menu ~= "swipe" then
                    reader_menu:onShowMenu(reader_menu:_getTabIndexFromLocation(ges_ev))
                    return true
                end
            end
        end
        -- return nil: let the tap propagate to MenuItem children for normal selection
    end
end

return apply_menu_top_swipe

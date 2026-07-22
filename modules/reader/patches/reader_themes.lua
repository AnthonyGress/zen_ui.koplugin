local function apply_reader_themes()
    local CreDocument = require("document/credocument")
    local Device = require("device")
    local DeviceListener = require("device/devicelistener")
    local UIManager = require("ui/uimanager")
    local ReaderFooter = require("apps/reader/modules/readerfooter")
    local ReaderMenu = require("apps/reader/modules/readermenu")
    local ReaderTypeset = require("apps/reader/modules/readertypeset")
    local ReaderUI = require("apps/reader/readerui")
    local ReaderThemes = require("common/reader_themes")
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    if CreDocument._zen_reader_themes then return true end
    CreDocument._zen_reader_themes = true

    local orig_setStyleSheet = CreDocument.setStyleSheet
    CreDocument.setStyleSheet = function(self, css_file, appended_css)
        return orig_setStyleSheet(self, css_file, ReaderThemes.appendCss(plugin, appended_css))
    end

    local reader_refresh_depth = 0
    local orig_setDirty = UIManager.setDirty
    UIManager.setDirty = function(self, widget, refresh_type, ...)
        local reader = ReaderUI.instance
        if refresh_type == "partial" and reader and (widget == reader or widget == reader.dialog)
                and ReaderThemes.isActive(plugin) then
            reader_refresh_depth = reader_refresh_depth + 1
            local result = orig_setDirty(self, widget, refresh_type, ...)
            reader_refresh_depth = reader_refresh_depth - 1
            return result
        end
        return orig_setDirty(self, widget, refresh_type, ...)
    end

    local orig_refresh = UIManager._refresh
    UIManager._refresh = function(self, refresh_type, ...)
        local refresh_count = #self._refresh_stack
        local result = orig_refresh(self, refresh_type, ...)
        if reader_refresh_depth > 0 and refresh_type == "partial" then
            for _i = refresh_count + 1, #self._refresh_stack do
                local refresh = self._refresh_stack[_i]
                if refresh.mode == "partial" then refresh.mode = "ui" end
            end
        end
        return result
    end

    local orig_onReadSettings = ReaderTypeset.onReadSettings
    ReaderTypeset.onReadSettings = function(self, ...)
        ReaderThemes.syncNightModeInversion(plugin)
        local result = orig_onReadSettings(self, ...)
        ReaderThemes.applyBackground(self.ui, plugin)
        ReaderThemes.applyFont(self.ui, plugin)
        return result
    end

    local orig_updateFooterContainer = ReaderFooter.updateFooterContainer
    ReaderFooter.updateFooterContainer = function(self, ...)
        local result = orig_updateFooterContainer(self, ...)
        ReaderThemes.applyFooterColors(self, plugin)
        return result
    end

    local orig_updateFooterFont = ReaderFooter.updateFooterFont
    ReaderFooter.updateFooterFont = function(self, ...)
        local result = orig_updateFooterFont(self, ...)
        ReaderThemes.applyFooterColors(self, plugin)
        return result
    end

    local orig_onToggleNightMode = DeviceListener.onToggleNightMode
    DeviceListener.onToggleNightMode = function(self, ...)
        local dark_mode = ReaderThemes.isDarkMode()
        if self.ui and self.ui.document and (ReaderThemes.isActiveForMode(plugin, dark_mode)
                or ReaderThemes.isActiveForMode(plugin, not dark_mode)) then
            G_reader_settings:saveSetting("night_mode", not dark_mode)
            if self.ui.document.provider == "crengine" then
                self.ui.document:resetCallCache()
            end
            ReaderThemes.applyCurrent(plugin)
            return true
        end
        return orig_onToggleNightMode(self, ...)
    end

    local Screen = Device.screen
    local orig_toggleNightMode = Screen.toggleNightMode
    Screen.toggleNightMode = function(self, ...)
        local reader = ReaderUI.instance
        local dark_mode = ReaderThemes.isDarkMode()
        local next_dark_mode = not dark_mode
        if not ReaderThemes.isSyncingNightMode() and reader and reader.document
                and (ReaderThemes.isActiveForMode(plugin, dark_mode)
                    or ReaderThemes.isActiveForMode(plugin, next_dark_mode)) then
            local should_invert = next_dark_mode
                and not ReaderThemes.isActiveForMode(plugin, next_dark_mode)
            if self.night_mode ~= should_invert then
                orig_toggleNightMode(self, ...)
            end
            UIManager:nextTick(function()
                ReaderThemes.applyCurrent(plugin)
            end)
            return
        end
        return orig_toggleNightMode(self, ...)
    end

    local orig_onShowMenu = ReaderMenu.onShowMenu
    ReaderMenu.onShowMenu = function(self, ...)
        local result = orig_onShowMenu(self, ...)
        local menu = self.menu_container and self.menu_container[1]
        if menu and not menu._zen_reader_themes then
            menu._zen_reader_themes = true
            local orig_paintTo = menu.paintTo
            menu.paintTo = function(this, bb, x, y)
                local paint_result = orig_paintTo(this, bb, x, y)
                if ReaderThemes.isDarkMode() and ReaderThemes.isActive(plugin) then
                    local size = this:getSize()
                    bb:invertRect(x, y, size.w, size.h)
                end
                return paint_result
            end
        end
        return result
    end

    local orig_onClose = ReaderUI.onClose
    ReaderUI.onClose = function(self, ...)
        if ReaderThemes.isActive(plugin) then
            ReaderThemes.restoreNightModeInversion()
        end
        return orig_onClose(self, ...)
    end
    return true
end

return apply_reader_themes

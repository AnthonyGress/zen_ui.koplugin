local function apply_browser_hide_underline()
    local Blitbuffer = require("ffi/blitbuffer")

    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then
            return nil
        end
        for i = 1, 64 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then
                break
            end
            if upname == name then
                return value
            end
        end
    end

    local function patchCoverBrowser(plugin)
        -- Patch MosaicMenuItem (mosaic display modes)
        local MosaicMenu = require("mosaicmenu")
        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if MosaicMenuItem and not MosaicMenuItem._zen_hide_underline_patched then
            MosaicMenuItem._zen_hide_underline_patched = true

            local BookInfoManager = get_upvalue(MosaicMenuItem.update, "BookInfoManager")
            if BookInfoManager and BookInfoManager.getSetting and BookInfoManager.toggleSetting then
                local setting = BookInfoManager:getSetting("folder_hide_underline")
                if setting == true then
                    BookInfoManager:toggleSetting("folder_hide_underline")
                end
            end

            local orig_mosaic_update = MosaicMenuItem.update
            function MosaicMenuItem:update(...)
                orig_mosaic_update(self, ...)
                if self._underline_container then
                    self._underline_container.color = Blitbuffer.COLOR_WHITE
                end
            end

            function MosaicMenuItem:onFocus()
                if self._underline_container then
                    self._underline_container.color = Blitbuffer.COLOR_WHITE
                end
                return true
            end
        end

        -- Patch ListMenuItem (list display modes)
        local ok_lm, ListMenu = pcall(require, "listmenu")
        if ok_lm then
            local ListMenuItem = get_upvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
            if ListMenuItem and not ListMenuItem._zen_hide_underline_patched then
                ListMenuItem._zen_hide_underline_patched = true

                local orig_list_update = ListMenuItem.update
                function ListMenuItem:update(...)
                    orig_list_update(self, ...)
                    if self._underline_container then
                        self._underline_container.color = Blitbuffer.COLOR_WHITE
                    end
                end

                function ListMenuItem:onFocus()
                    if self._underline_container then
                        self._underline_container.color = Blitbuffer.COLOR_WHITE
                    end
                    return true
                end
            end
        end

        -- Patch CoverMenu.updateItems so ALL coverbrowser-enabled views
        -- (including collections) get underlines hidden after items are built.
        local ok_cm, CoverMenu = pcall(require, "covermenu")
        if ok_cm and CoverMenu and not CoverMenu._zen_hide_underline_patched then
            CoverMenu._zen_hide_underline_patched = true
            local orig_cover_updateItems = CoverMenu.updateItems
            function CoverMenu:updateItems(...)
                orig_cover_updateItems(self, ...)
                if self.layout then
                    for _, row in ipairs(self.layout) do
                        for _, item in ipairs(row) do
                            if item._underline_container then
                                item._underline_container.color = Blitbuffer.COLOR_WHITE
                            end
                        end
                    end
                end
            end
        end
    end

    -- Export shared utilities for other patches (e.g. collections classic mode)
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if zen_plugin then
        if not zen_plugin._zen_shared then zen_plugin._zen_shared = {} end
        zen_plugin._zen_shared.hide_underline_active = true
    end

    -- Patch Menu.updateItems at the class level so ALL menu views
    -- (classic mode, collections, history, favorites, etc.) get underlines hidden.
    -- CoverMenu.updateItems (mosaic/list) is a separate override and is patched
    -- inside patchCoverBrowser above; this catches everything else.
    -- Exception: classic file browser (name=="filemanager", no display_mode_type)
    -- keeps its natural separators so items are visually distinct.
    local Menu = require("ui/widget/menu")
    if not Menu._zen_hide_underline_patched then
        Menu._zen_hide_underline_patched = true
        local orig_menu_updateItems = Menu.updateItems
        function Menu:updateItems(...)
            orig_menu_updateItems(self, ...)
            -- Classic file browser: leave underlines visible as row separators.
            if self.name == "filemanager" then return end
            if self.layout then
                for _, row in ipairs(self.layout) do
                    for _, item in ipairs(row) do
                        if item._underline_container then
                            item._underline_container.color = Blitbuffer.COLOR_WHITE
                        end
                    end
                end
            end
        end
    end

    -- Primary path: register with userpatch so coverbrowser patch timing is correct.
    local ok_userpatch, userpatch = pcall(require, "userpatch")
    if ok_userpatch and userpatch and type(userpatch.registerPatchPluginFunc) == "function" then
        userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
    else
        -- Fallback for environments without userpatch.
        local ok_coverbrowser, coverbrowser = pcall(require, "coverbrowser")
        if ok_coverbrowser and coverbrowser then
            patchCoverBrowser(coverbrowser)
        end
    end
end

return apply_browser_hide_underline

local function apply_browser_hide_underline()
    local Blitbuffer = require("ffi/blitbuffer")

    local function hide_menu_underlines(menu)
        if not (menu and menu.layout) then return end
        for _i, row in ipairs(menu.layout) do
            for _j, item in ipairs(row) do
                if item._underline_container then
                    item._underline_container.color = Blitbuffer.COLOR_WHITE
                end
            end
        end
    end

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
                        self._underline_container.color = Blitbuffer.COLOR_BLACK
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
                hide_menu_underlines(self)
            end
        end
    end

    -- Export shared utilities for other patches (e.g. collections classic mode)
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if zen_plugin then
        require("common/shared_state").register(zen_plugin, {
            hide_underline_active = true,
            hideMenuUnderlines = hide_menu_underlines,
        })
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
            -- Classic mode menus (file browser or group view): leave underlines visible.
            if self.name == "filemanager" or self.display_mode_type == "classic" then return end
            hide_menu_underlines(self)
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

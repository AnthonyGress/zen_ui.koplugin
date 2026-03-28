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
        local MosaicMenu = require("mosaicmenu")
        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then
            return
        end
        if MosaicMenuItem._zen_hide_underline_patched then
            return
        end
        MosaicMenuItem._zen_hide_underline_patched = true

        local BookInfoManager = get_upvalue(MosaicMenuItem.update, "BookInfoManager")

        -- Ensure hidden-by-default behavior in coverbrowser persisted settings.
        -- In coverbrowser, default true means: nil/false => hidden, true => visible.
        if BookInfoManager and BookInfoManager.getSetting and BookInfoManager.toggleSetting then
            local setting = BookInfoManager:getSetting("folder_hide_underline")
            if setting == true then
                BookInfoManager:toggleSetting("folder_hide_underline")
            end
        end

        local orig_update = MosaicMenuItem.update

        function MosaicMenuItem:update(...)
            orig_update(self, ...)
            if self._underline_container then
                self._underline_container.color = Blitbuffer.COLOR_WHITE
            end
        end

        -- Match known-working behavior: force hide on focus and don't delegate.
        function MosaicMenuItem:onFocus()
            if self._underline_container then
                self._underline_container.color = Blitbuffer.COLOR_WHITE
            end
            return true
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

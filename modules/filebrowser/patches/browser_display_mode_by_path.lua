-- Auto-switch to classic display mode when browsing outside home_dir.
-- Restores the user's preferred mode instantly when returning to home_dir so
-- there is no classic-mode flash.
--
-- changeToPath() calls refreshPath() (which renders items) BEFORE it fires
-- the PathChanged event.  That means hooking onPathChanged is too late.
-- Instead we wrap FileChooser.changeToPath: when entering home_dir with a
-- saved preferred mode we silently restore the CoverBrowser state on the
-- class-level FileChooser (no intermediate rebuild), then let changeToPath
-- call refreshPath() which immediately renders in the preferred mode.
local function apply_browser_display_mode_by_path()
    local FileManager = require("apps/filemanager/filemanager")
    local FileChooser  = require("ui/widget/filechooser")

    local function is_in_home(path)
        local home_dir = G_reader_settings and G_reader_settings:readSetting("home_dir")
        if not home_dir or not path then return false end
        return path == home_dir or path:sub(1, #home_dir + 1) == home_dir .. "/"
    end

    -- ── Entering home_dir: restore mode BEFORE refreshPath() renders items ──
    local orig_changeToPath = FileChooser.changeToPath
    local _restoring = false

    FileChooser.changeToPath = function(self, path, ...)
        if not _restoring and self.name == "filemanager" then
            local saved = rawget(_G, "__ZEN_PREFERRED_DISPLAY_MODE")
            if saved and is_in_home(path) then
                _G.__ZEN_PREFERRED_DISPLAY_MODE = nil
                local fm = FileManager.instance
                local cb = fm and fm.coverbrowser
                if cb and type(cb.setDisplayMode) == "function" then
                    -- Suppress refreshFileManagerInstance: refreshPath() is
                    -- about to render the correct path in the restored mode.
                    local orig_refresh = cb.refreshFileManagerInstance
                    cb.refreshFileManagerInstance = function() end
                    _restoring = true
                    pcall(cb.setDisplayMode, cb, saved)
                    _restoring = false
                    cb.refreshFileManagerInstance = orig_refresh
                end
            end
        end
        return orig_changeToPath(self, path, ...)
    end

    -- ── Leaving home_dir: switch to classic in onPathChanged ────────────────
    local orig_onPathChanged = FileManager.onPathChanged
    local _switching = false

    function FileManager:onPathChanged(path)
        if orig_onPathChanged then
            orig_onPathChanged(self, path)
        end
        if _switching then return end
        if is_in_home(path) then return end  -- handled by changeToPath hook

        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if not ok_bim then return end

        local current_mode = BookInfoManager:getSetting("filemanager_display_mode")
        if current_mode == nil then return end  -- already classic

        -- Persist preferred mode for when we return to home_dir.
        if not rawget(_G, "__ZEN_PREFERRED_DISPLAY_MODE") then
            _G.__ZEN_PREFERRED_DISPLAY_MODE = current_mode
        end

        local cb = self.coverbrowser
        if cb and type(cb.setDisplayMode) == "function" then
            _switching = true
            pcall(cb.setDisplayMode, cb, nil)  -- nil = classic
            _switching = false
            -- setDisplayMode(nil) saved nil to DB; restore the preferred value
            -- so CoverBrowser reads the right mode on next restart.
            pcall(BookInfoManager.saveSetting, BookInfoManager,
                "filemanager_display_mode", current_mode)
        end
    end
end

return apply_browser_display_mode_by_path

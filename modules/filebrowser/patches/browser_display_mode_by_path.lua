-- Auto-switch to classic display mode when browsing outside home_dir.
-- Restores the user's preferred mode instantly when returning to home_dir so
-- there is no classic-mode flash.
--
-- changeToPath() calls refreshPath() (which renders items) BEFORE it fires
-- the PathChanged event.  Both the enter-home and leave-home mode switches are
-- handled inside the changeToPath wrapper so the mode is correct BEFORE
-- refreshPath() renders anything, avoiding a double-render flash/lag.
local function apply_browser_display_mode_by_path()
    local FileManager = require("apps/filemanager/filemanager")
    local FileChooser  = require("ui/widget/filechooser")

    local function is_in_home(path)
        local home_dir = G_reader_settings and G_reader_settings:readSetting("home_dir")
        if not home_dir or not path then return false end
        return path == home_dir or path:sub(1, #home_dir + 1) == home_dir .. "/"
    end

    local orig_changeToPath = FileChooser.changeToPath
    local _switching = false

    -- ── Suppress refreshFileManagerInstance, call setDisplayMode, restore ──
    local function apply_mode(cb, mode)
        local orig_refresh = cb.refreshFileManagerInstance
        cb.refreshFileManagerInstance = function() end
        _switching = true
        pcall(cb.setDisplayMode, cb, mode)
        _switching = false
        cb.refreshFileManagerInstance = orig_refresh
    end

    FileChooser.changeToPath = function(self, path, ...)
        if not _switching and self.name == "filemanager" then
            local in_home = is_in_home(path)
            local saved = rawget(_G, "__ZEN_PREFERRED_DISPLAY_MODE")
            local fm = FileManager.instance
            local cb = fm and fm.coverbrowser

            if saved and in_home then
                -- ── Entering home_dir: restore preferred mode BEFORE refreshPath ──
                _G.__ZEN_PREFERRED_DISPLAY_MODE = nil
                if cb and type(cb.setDisplayMode) == "function" then
                    apply_mode(cb, saved)
                end

            elseif not in_home then
                -- ── Leaving home_dir: switch to classic BEFORE refreshPath ──
                local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
                if ok_bim then
                    local current_mode = BookInfoManager:getSetting("filemanager_display_mode")
                    if current_mode ~= nil then  -- non-nil means a cover mode is active
                        if not saved then
                            _G.__ZEN_PREFERRED_DISPLAY_MODE = current_mode
                        end
                        if cb and type(cb.setDisplayMode) == "function" then
                            apply_mode(cb, nil)  -- nil = classic
                            -- setDisplayMode(nil) persisted nil; write back preferred so
                            -- CoverBrowser reads the correct mode on next restart.
                            pcall(BookInfoManager.saveSetting, BookInfoManager,
                                "filemanager_display_mode", current_mode)
                        end
                    end
                end
            end
        end
        return orig_changeToPath(self, path, ...)
    end

    -- ── onPathChanged: only needed for the title-bar update (no mode logic) ──
    local orig_onPathChanged = FileManager.onPathChanged

    function FileManager:onPathChanged(path)
        if orig_onPathChanged then
            orig_onPathChanged(self, path)
        end
    end
end

return apply_browser_display_mode_by_path

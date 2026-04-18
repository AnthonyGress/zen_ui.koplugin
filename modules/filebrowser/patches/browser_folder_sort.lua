local function apply_browser_folder_sort()
    --[[
        Per-folder sort overrides for the file browser.

        Stores a path → collate-id map in G_reader_settings under the key
        "zen_ui_folder_sort".  On every genItemTableFromPath call the patch checks
        whether the current path has an override and, if so, temporarily swaps
        self.collate (and self.reverse_collate / self.collate_mixed when present)
        before calling the original function, then restores them immediately after.

        Because KOReader's Lua runtime is single-threaded there is no race risk from
        the temporary swap.

        Public API (required by context_menu.lua)
        ─────────────────────────────────────────
          local FolderSort = require("modules/filebrowser/patches/browser_folder_sort")
          FolderSort.get(path)            → collate_id string or nil
          FolderSort.set(path, collate)   → persists the override for path
          FolderSort.clear(path)          → removes the override for path
    ]]

    local FileChooser = require("ui/widget/filechooser")

    local SETTINGS_KEY = "zen_ui_folder_sort"

    -- ── Storage helpers ──────────────────────────────────────────────────────

    local function read_map()
        local g = rawget(_G, "G_reader_settings")
        if not g then return {} end
        local m = g:readSetting(SETTINGS_KEY)
        return type(m) == "table" and m or {}
    end

    local function write_map(m)
        local g = rawget(_G, "G_reader_settings")
        if g then g:saveSetting(SETTINGS_KEY, m) end
    end

    local M = {}

    function M.get(path)
        if not path then return nil end
        return read_map()[path]
    end

    function M.set(path, collate_id)
        if not path or not collate_id then return end
        local m = read_map()
        m[path] = collate_id
        write_map(m)
    end

    function M.clear(path)
        if not path then return end
        local m = read_map()
        if m[path] == nil then return end
        m[path] = nil
        write_map(m)
    end

    -- Expose the API on a well-known global so context_menu.lua can reach it
    -- without a cross-module require cycle.
    _G.__ZEN_FOLDER_SORT = M

    -- ── FileChooser patch ────────────────────────────────────────────────────
    --
    -- getCollate() reads G_reader_settings:readSetting("collate") directly and
    -- ignores any instance field.  The only reliable intercept point is to wrap
    -- getCollate() itself, guarded by an instance-level flag that the
    -- genItemTableFromPath wrapper sets for the duration of the call.
    -- Both internal getCollate() calls (one in genItemTableFromPath, one in
    -- genItemTable) will see the override this way.

    local orig_getCollate = FileChooser.getCollate

    FileChooser.getCollate = function(self)
        local override = self._zen_sort_override
        if override then
            local collate_obj = self.collates and self.collates[override]
            if collate_obj then
                return collate_obj, override
            end
        end
        return orig_getCollate(self)
    end

    local orig_genItemTableFromPath = FileChooser.genItemTableFromPath

    FileChooser.genItemTableFromPath = function(self, path, ...)
        local ffiUtil = require("ffi/util")
        local real_path = ffiUtil and ffiUtil.realpath and ffiUtil.realpath(path) or path

        -- Never apply a per-folder sort override to the home directory.
        local g = rawget(_G, "G_reader_settings")
        local home_dir = g and g:readSetting("home_dir")
        if home_dir then
            local home_real = ffiUtil and ffiUtil.realpath and ffiUtil.realpath(home_dir) or home_dir
            if real_path == home_real or path == home_dir then
                return orig_genItemTableFromPath(self, path, ...)
            end
        end

        local override = (real_path and M.get(real_path))
            or (path ~= real_path and M.get(path))

        if not override then
            return orig_genItemTableFromPath(self, path, ...)
        end

        -- Set the instance flag so both getCollate() calls inside
        -- genItemTableFromPath  and  genItemTable see the override.
        self._zen_sort_override = override
        local ok, result_or_err = pcall(orig_genItemTableFromPath, self, path, ...)
        self._zen_sort_override = nil

        if ok then
            return result_or_err
        else
            -- Fallback: run without override so the browser stays functional.
            return orig_genItemTableFromPath(self, path, ...)
        end
    end

end

return apply_browser_folder_sort

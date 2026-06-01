local function apply_browser_folder_sort()
    --[[
        Per-folder sort overrides stored in G_reader_settings under "zen_ui_folder_sort".
        Temporarily swaps self.collate and reverse_collate for the overridden path.

        Public API (used by context_menu.lua via __ZEN_FOLDER_SORT global):
          FolderSort.get(path)                  → { collate = "title", reverse = false } or nil
          FolderSort.set(path, collate, reverse) → save override
          FolderSort.clear(path)                → remove override
    ]]

    local FileChooser = require("ui/widget/filechooser")
    local paths       = require("common/paths")

    local SETTINGS_KEY = "zen_ui_folder_sort"


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
        local entry = read_map()[path]
        -- Backward compat: if entry is a string, convert to table format
        if type(entry) == "string" then
            return { collate = entry, reverse = false }
        end
        return entry
    end

    function M.set(path, collate_id, reverse)
        if not path or not collate_id then return end
        local m = read_map()
        m[path] = { collate = collate_id, reverse = reverse or false }
        write_map(m)
    end

    function M.clear(path)
        if not path then return end
        local m = read_map()
        if m[path] == nil then return end
        m[path] = nil
        write_map(m)
    end

    -- Expose API on a well-known global to avoid a cross-module require cycle.
    _G.__ZEN_FOLDER_SORT = M

    -- Wrap getCollate() and getSortingFunction() to inject per-folder overrides.
    -- genItemTable() calls getCollate() for the collate object and reads
    -- reverse_collate from G_reader_settings directly (not self.reverse_collate),
    -- so we must intercept getSortingFunction to substitute the override's reverse.

    local orig_getCollate = FileChooser.getCollate

    FileChooser.getCollate = function(self)
        local override = self._zen_sort_override
        if override and type(override) == "table" then
            local collate_obj = self.collates and self.collates[override.collate]
            if collate_obj then
                return collate_obj, override.collate
            end
        end
        return orig_getCollate(self)
    end

    -- genItemTable() reads reverse_collate from G_reader_settings, bypassing
    -- self.reverse_collate entirely. Intercept getSortingFunction to inject
    -- the override's reverse when it is set. The nil-reverse_collate case is
    -- the internal folder-name fallback sort; don't touch that.
    local orig_getSortingFunction = FileChooser.getSortingFunction

    FileChooser.getSortingFunction = function(self, collate, reverse_collate)
        local override = self._zen_sort_override
        if override and type(override) == "table" and type(override.reverse) == "boolean"
                and reverse_collate ~= nil then
            reverse_collate = override.reverse
        end
        return orig_getSortingFunction(self, collate, reverse_collate)
    end

    local orig_genItemTableFromPath = FileChooser.genItemTableFromPath

    FileChooser.genItemTableFromPath = function(self, path, ...)
        local ffiUtil = require("ffi/util")
        local real_path = ffiUtil and ffiUtil.realpath and ffiUtil.realpath(path) or path

        -- Never apply a per-folder sort override to the home directory.
        local home_dir = paths.getHomeDir()
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

        -- Set the instance flag so getCollate() and getSortingFunction() see the override.
        self._zen_sort_override = override
        local saved_reverse = self.reverse_collate

        local ok, result_or_err = pcall(orig_genItemTableFromPath, self, path, ...)

        self._zen_sort_override = nil
        self.reverse_collate = saved_reverse

        if ok then
            return result_or_err
        else
            -- Fallback: run without override so the browser stays functional.
            return orig_genItemTableFromPath(self, path, ...)
        end
    end

end

return apply_browser_folder_sort

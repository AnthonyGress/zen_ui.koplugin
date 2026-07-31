-- Caches file-browser item tables and keeps access sorting tied to read history.
local function apply_browser_item_table_cache()
    local FileChooser = require("ui/widget/filechooser")
    if FileChooser._zen_item_table_cache_patched then return end
    FileChooser._zen_item_table_cache_patched = true

    local HistoryIndex = require("common/history_index")
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local paths = require("common/paths")
    local zen_logger = require("common/zen_logger")
    local logger = zen_logger.new("browser_item_table_cache")
    local now = zen_logger.now
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local ITEM_TABLE_CACHE_MAX = 32
    local FOLDER_AGGREGATE_CACHE_MAX = 128
    local shared_cache = { values = {}, order = {} }

    local function stable_table_key(value)
        if type(value) ~= "table" then return tostring(value) end
        local fields = {}
        for key, field_value in pairs(value) do
            local kind = type(field_value)
            if kind == "string" or kind == "number" or kind == "boolean" or field_value == nil then
                fields[#fields + 1] = tostring(key) .. "=" .. tostring(field_value)
            end
        end
        table.sort(fields)
        return table.concat(fields, "\31")
    end

    local function list_item_key(dirpath, filename, fullpath, attributes, collate, filter_status)
        return table.concat({
            tostring(dirpath), tostring(filename), tostring(fullpath),
            stable_table_key(attributes), tostring(collate), tostring(filter_status),
        }, "\30")
    end

    local function list_cache(self)
        if not self._zen_list_item_cache then self._zen_list_item_cache = {} end
        return self._zen_list_item_cache
    end

    local function folder_aggregate_cache(self)
        if not self._zen_folder_aggregate_cache then
            self._zen_folder_aggregate_cache = { values = {}, order = {} }
        end
        return self._zen_folder_aggregate_cache
    end

    local function cache_folder_aggregate(self, path, mtime, access, modification)
        local cache = folder_aggregate_cache(self)
        if not cache.values[path] then cache.order[#cache.order + 1] = path end
        cache.values[path] = { mtime = mtime, access = access, modification = modification }
        while #cache.order > FOLDER_AGGREGATE_CACHE_MAX do
            cache.values[table.remove(cache.order, 1)] = nil
        end
    end

    local function folder_sort_override(path)
        local api = rawget(_G, "__ZEN_FOLDER_SORT")
        if not (api and type(api.get) == "function") then return nil end
        local real_path = ffiUtil.realpath(path) or path
        return (real_path and api.get(real_path))
            or (path ~= real_path and api.get(path))
    end

    local function folder_sort_key(path)
        local override = folder_sort_override(path)
        if type(override) ~= "table" then return "" end
        return tostring(override.collate or "") .. ":" .. tostring(override.reverse == true)
    end

    local function automatic_series_enabled()
        local features = plugin and plugin.config and plugin.config.features
        return type(features) ~= "table" or features.automatic_series_grouping ~= false
    end

    local function dim_finished_enabled()
        local config = plugin and plugin.config and plugin.config.browser_cover_badges
        return type(config) == "table" and config.dim_finished_books == true
    end

    local function canonical_path(path)
        if not path then return nil end
        return paths.normPath((ffiUtil.realpath(path) or path):gsub("/$", ""))
    end

    local function history_time_map()
        return HistoryIndex.load(canonical_path)
    end

    local function history_time(map, item)
        if not (map and item and item.path) then return nil end
        return HistoryIndex.fileTime(map, item.path, canonical_path)
    end

    local function is_special_item(item)
        return item.is_go_up or (item.path and item.path:sub(-2) == "/.")
    end

    local function apply_history_order(chooser, item_table, collate, reverse_collate)
        if type(item_table) ~= "table" then return item_table end
        local map = history_time_map()
        local reverse = type(reverse_collate) == "boolean"
            and reverse_collate or G_reader_settings:isTrue("reverse_collate")
        local mixed = collate.can_collate_mixed and G_reader_settings:isTrue("collate_mixed")

        for _i, item in ipairs(item_table) do
            if not is_special_item(item) then
                local is_directory = item.attr and item.attr.mode == "directory"
                local read_time = not is_directory and history_time(map, item) or nil
                if read_time then
                    item.attr = item.attr or {}
                    item.attr.access = read_time
                    if collate.mandatory_func ~= nil then
                        item.mandatory = chooser:getMenuItemMandatory(item, collate)
                    end
                end
                item._zen_sort_key = read_time or (item.attr and item.attr.modification) or 0
            end
        end

        local function compare(a, b)
            local a_key, b_key = a._zen_sort_key or 0, b._zen_sort_key or 0
            if a_key == b_key then
                return tostring(a.text or ""):lower() < tostring(b.text or ""):lower()
            end
            return reverse and a_key < b_key or a_key > b_key
        end

        local head, directories, files = {}, {}, {}
        for _i, item in ipairs(item_table) do
            if is_special_item(item) then
                head[#head + 1] = item
            elseif item.attr and item.attr.mode == "directory" then
                directories[#directories + 1] = item
            else
                files[#files + 1] = item
            end
        end

        local result = {}
        for _i, item in ipairs(head) do result[#result + 1] = item end
        if mixed then
            local body = {}
            for _i, item in ipairs(directories) do body[#body + 1] = item end
            for _i, item in ipairs(files) do body[#body + 1] = item end
            table.sort(body, compare)
            for _i, item in ipairs(body) do result[#result + 1] = item end
        else
            table.sort(files, compare)
            for _i, item in ipairs(directories) do result[#result + 1] = item end
            for _i, item in ipairs(files) do result[#result + 1] = item end
        end
        return result
    end

    local original_getListItem = FileChooser.getListItem
    function FileChooser:getListItem(dirpath, filename, fullpath, attributes, collate)
        if self._dummy or self.name ~= "filemanager" then
            return original_getListItem(self, dirpath, filename, fullpath, attributes, collate)
        end
        if attributes.mode == "directory" and collate
                and collate.can_collate_mixed and collate.mandatory_func and not collate.item_func then
            local item = original_getListItem(self, dirpath, filename, fullpath, attributes, collate)
            local mtime = attributes.modification or 0
            local aggregate = folder_aggregate_cache(self).values[fullpath]
            local cached = aggregate and aggregate.mtime == mtime
            local max_access = cached and aggregate.access or attributes.access or 0
            local max_modification = cached and aggregate.modification or mtime
            if not cached then
                local ok, iterator, directory = pcall(lfs.dir, fullpath)
                if ok then
                    for child in iterator, directory do
                        if child ~= "." and child ~= ".." then
                            local child_attr = lfs.attributes(fullpath .. "/" .. child)
                            if child_attr and child_attr.mode == "file" then
                                max_access = math.max(max_access, child_attr.access or 0)
                                max_modification = math.max(max_modification, child_attr.modification or 0)
                            end
                        end
                    end
                end
                cache_folder_aggregate(self, fullpath, mtime, max_access, max_modification)
            end
            local copied = {}
            for key, value in pairs(attributes) do copied[key] = value end
            copied.access, copied.modification = max_access, max_modification
            item.attr = copied
            return item
        end

        local filter = self.show_filter and self.show_filter.status
        local key = list_item_key(dirpath, filename, fullpath, attributes, collate, filter)
        local cache = list_cache(self)
        if not cache[key] then
            cache[key] = original_getListItem(self, dirpath, filename, fullpath, attributes, collate)
        end
        return cache[key]
    end

    local function stable_key(path)
        local filter = FileChooser.show_filter and FileChooser.show_filter.status
        return string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s",
            path,
            G_reader_settings:readSetting("collate", "strcoll"),
            tostring(G_reader_settings:isTrue("collate_mixed")),
            tostring(G_reader_settings:isTrue("reverse_collate")),
            tostring(FileChooser.show_hidden), tostring(filter), folder_sort_key(path),
            tostring(automatic_series_enabled()), tostring(dim_finished_enabled()))
    end

    local function cache_key(path)
        return string.format("%s|%d", stable_key(path), lfs.attributes(path, "modification") or 0)
    end

    local function get_cached(path, key)
        local value = shared_cache.values[path]
        return value and value.key == key and value or nil
    end

    local function put_cached(path, value)
        if not shared_cache.values[path] then shared_cache.order[#shared_cache.order + 1] = path end
        shared_cache.values[path] = value
        while #shared_cache.order > ITEM_TABLE_CACHE_MAX do
            shared_cache.values[table.remove(shared_cache.order, 1)] = nil
        end
    end

    function FileChooser:_zen_clear_item_table_cache()
        shared_cache = { values = {}, order = {} }
        self._zen_list_item_cache = {}
        self._zen_folder_aggregate_cache = nil
    end

    local original_genItemTableFromPath = FileChooser.genItemTableFromPath
    function FileChooser:genItemTableFromPath(path)
        if self._dummy or self.name ~= "filemanager" then
            return original_genItemTableFromPath(self, path)
        end

        local started_at = now()
        local override = folder_sort_override(path)
        local collate_mode = type(override) == "table" and override.collate
            or G_reader_settings:readSetting("collate", "strcoll")
        local collate = (self.collates and self.collates[collate_mode]) or self:getCollate()
        local reverse = type(override) == "table"
            and override.reverse or G_reader_settings:isTrue("reverse_collate")
        local key, stable = cache_key(path), stable_key(path)
        local cached = get_cached(path, key)
        if cached then
            if collate_mode == "access" then
                cached.table = apply_history_order(self, cached.table, collate, reverse)
            end
            logger.measure("File list generated", (now() - started_at) * 1000,
                "cache=hit", "path=", tostring(path), "items=", #cached.table)
            return cached.table
        end

        local stale = shared_cache.values[path]
        if collate_mode == "access" and rawget(_G, "__ZEN_UI_LAST_READ_FILE")
                and stale and stale.stable_key == stable then
            _G.__ZEN_UI_LAST_READ_FILE = nil
            stale.table = apply_history_order(self, stale.table, collate, reverse)
            stale.key = key
            put_cached(path, stale)
            return stale.table
        end

        self._zen_list_item_cache = {}
        local result = original_genItemTableFromPath(self, path)
        if collate_mode == "access" then
            result = apply_history_order(self, result, collate, reverse)
        end
        put_cached(path, { key = key, stable_key = stable, table = result })
        logger.measure("File list generated", (now() - started_at) * 1000,
            "cache=miss", "path=", tostring(path), "items=", #result)
        return result
    end

    local function patch_coverbrowser(coverbrowser)
        if not coverbrowser or coverbrowser._zen_item_table_cache_invalidation
                or type(coverbrowser.onBookInfoUpdated) ~= "function" then return end
        coverbrowser._zen_item_table_cache_invalidation = true
        local original = coverbrowser.onBookInfoUpdated
        function coverbrowser:onBookInfoUpdated(...)
            local result = original(self, ...)
            if G_reader_settings:readSetting("collate", "strcoll") ~= "access" then
                shared_cache = { values = {}, order = {} }
                local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
                local chooser = ok and FileManager.instance and FileManager.instance.file_chooser
                if chooser then chooser._zen_list_item_cache = {} end
            end
            return result
        end
    end

    local ok_userpatch, userpatch = pcall(require, "userpatch")
    if ok_userpatch and userpatch and type(userpatch.registerPatchPluginFunc) == "function" then
        userpatch.registerPatchPluginFunc("coverbrowser", patch_coverbrowser)
    else
        local ok_coverbrowser, coverbrowser = pcall(require, "coverbrowser")
        if ok_coverbrowser then patch_coverbrowser(coverbrowser) end
    end
end

return apply_browser_item_table_cache

local M = {}

M.LEGACY_PLUGIN_DIR = "zen_ui.koplugin"
M.PLUGIN_DIR = "zenos.koplugin"
M.LEGACY_PLUGIN_ID = "zen_ui"
M.PLUGIN_ID = "zenos"
M.LEGACY_SETTINGS_DIR = "Zen UI"
M.SETTINGS_DIR = "ZenOS"

local SETTINGS_FILES = {
    "config.lua",
    "home.lua",
    "stats.lua",
    "reader.lua",
    "screensaver.lua",
    "app_launcher.lua",
    "quote_state.lua",
    "library_item_cache.lua",
}
local BRAND_MIGRATION_MARKER = "zenos_brand_migration_v1"
local ROOT_GUARD_KEY = "__ZENOS_PLUGIN_ROOT_GUARD"

local READER_BRAND_VALUES = {
    ["(Zen UI) Chapter Time + %"] = "(ZenOS) Chapter Time + %",
    ["(Zen UI) Pages and %"] = "(ZenOS) Pages and %",
    ["(Zen UI) Pages + Time + %"] = "(ZenOS) Pages + Time + %",
    ["(Zen UI) Centered Pages"] = "(ZenOS) Centered Pages",
    ["(Zen UI) L/C/R: Chapter Time | Page | %"] =
        "(ZenOS) L/C/R: Chapter Time | Page | %",
    ["(Zen UI) Pages | Bar | %"] = "(ZenOS) Pages | Bar | %",
}
local READER_BUILTIN_NAMES = {}
for legacy_name, current_name in pairs(READER_BRAND_VALUES) do
    READER_BUILTIN_NAMES[legacy_name] = true
    READER_BUILTIN_NAMES[current_name] = true
end

local function trim_trailing_slashes(path)
    if type(path) ~= "string" then return nil end
    if path == "/" then return path end
    return (path:gsub("/+$", ""))
end

local function join(parent, child)
    parent = trim_trailing_slashes(parent)
    if not parent or parent == "" then return child end
    return parent .. "/" .. child
end

local function dirname(path)
    return type(path) == "string" and path:match("^(.*)/[^/]+$") or nil
end

local function basename(path)
    return type(path) == "string" and path:match("([^/]+)$") or nil
end

local function get_lfs(options)
    if options and options.lfs then return options.lfs end
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    return ok and lfs or nil
end

local function get_mode(lfs, path)
    if not lfs or type(lfs.attributes) ~= "function" then return nil end
    local ok, mode = pcall(lfs.attributes, path, "mode")
    return ok and mode or nil
end

local function get_entry_mode(lfs, path)
    if lfs and type(lfs.symlinkattributes) == "function" then
        local ok, mode = pcall(lfs.symlinkattributes, path, "mode")
        if ok then return mode end
    end
    return get_mode(lfs, path)
end

local function is_empty_directory(lfs, path)
    if get_entry_mode(lfs, path) ~= "directory" then return false end
    local ok, iterator, state = pcall(lfs.dir, path)
    if not ok or type(iterator) ~= "function" then return false end
    for entry in iterator, state do
        if entry ~= "." and entry ~= ".." then return false end
    end
    return true
end

local function rename_path(from_path, to_path, options)
    local rename = options and options.rename or os.rename
    local ok, result, err = pcall(rename, from_path, to_path)
    if not ok then return false, result end
    if result then return true end
    return false, err
end

local function log(level, ...)
    local ok, logger = pcall(require, "logger")
    local writer = ok and logger and logger[level]
    if type(writer) == "function" then
        writer("ZenOS: [migration]", ...)
    end
end

local function settings_parent_path(options)
    options = options or {}
    if options.settings_dir then return trim_trailing_slashes(options.settings_dir) end
    local data_storage = options.data_storage
    if not data_storage then
        local ok, loaded = pcall(require, "datastorage")
        if ok then data_storage = loaded end
    end
    if not data_storage then return nil end
    local ok_settings, settings_dir = pcall(data_storage.getSettingsDir, data_storage)
    if not ok_settings then return nil end
    return trim_trailing_slashes(settings_dir)
end

local function source_root(main_source, lfs)
    local source = main_source
    if type(source) ~= "string" or source == "" then
        source = debug.getinfo(2, "S").source or ""
    end
    if source:sub(1, 1) == "@" then source = source:sub(2) end
    local root = source:match("^(.*)/main%.lua$")
    if not root then return nil end
    if root:sub(1, 1) ~= "/" and lfs and type(lfs.currentdir) == "function" then
        local ok, cwd = pcall(lfs.currentdir)
        if ok and type(cwd) == "string" and cwd ~= "" then
            root = join(cwd, root)
        end
    end
    return trim_trailing_slashes(root)
end

-- Rename the complete settings tree before any LuaSettings file is opened.
-- On failure the legacy tree remains authoritative, so callers never create a
-- fresh configuration over an existing installation.
function M.prepareSettings(settings_parent, options)
    options = options or {}
    local lfs = get_lfs(options)
    settings_parent = trim_trailing_slashes(settings_parent)
    local legacy_root = join(settings_parent, M.LEGACY_SETTINGS_DIR)
    local root = join(settings_parent, M.SETTINGS_DIR)
    local legacy_mode = get_entry_mode(lfs, legacy_root)
    local root_mode = get_entry_mode(lfs, root)

    if legacy_mode and legacy_mode ~= "directory" then
        return {
            ok = false,
            status = "legacy_settings_invalid",
            root = root,
            legacy_root = legacy_root,
        }
    end
    if root_mode and root_mode ~= "directory" then
        return {
            ok = false,
            status = "settings_destination_invalid",
            root = legacy_mode == "directory" and legacy_root or root,
            legacy_root = legacy_root,
        }
    end
    if legacy_mode == "directory" and root_mode == "directory" then
        if is_empty_directory(lfs, root) then
            local removed = pcall(lfs.rmdir, root)
            root_mode = get_entry_mode(lfs, root)
            if not removed or root_mode ~= nil then
                return {
                    ok = false,
                    status = "settings_destination_remove_failed",
                    root = legacy_root,
                    legacy_root = legacy_root,
                }
            end
        elseif is_empty_directory(lfs, legacy_root) then
            pcall(lfs.rmdir, legacy_root)
            if get_entry_mode(lfs, legacy_root) == nil then
                return {
                    ok = true,
                    status = "current",
                    root = root,
                    legacy_root = legacy_root,
                }
            end
        end
        if root_mode == "directory" then
            return {
                ok = false,
                status = "settings_conflict",
                root = root,
                legacy_root = legacy_root,
            }
        end
    end
    if legacy_mode ~= "directory" then
        return {
            ok = true,
            status = root_mode == "directory" and "current" or "absent",
            root = root,
            legacy_root = legacy_root,
        }
    end

    local renamed, err = rename_path(legacy_root, root, options)
    if renamed then
        return {
            ok = true,
            status = "migrated",
            root = root,
            legacy_root = legacy_root,
            renamed = true,
        }
    end

    -- A concurrent or interrupted attempt may have completed the same rename.
    legacy_mode = get_entry_mode(lfs, legacy_root)
    root_mode = get_entry_mode(lfs, root)
    if not legacy_mode and root_mode == "directory" then
        return {
            ok = true,
            status = "current",
            root = root,
            legacy_root = legacy_root,
        }
    end
    return {
        ok = false,
        status = "settings_rename_failed",
        root = legacy_root,
        legacy_root = legacy_root,
        error = err,
    }
end

local function remove_tree(path, lfs)
    local mode = get_entry_mode(lfs, path)
    if mode == "file" or mode == "link" then
        pcall(os.remove, path)
        return
    end
    if mode ~= "directory" then return end
    local ok_dir, iterator, state = pcall(lfs.dir, path)
    if ok_dir and type(iterator) == "function" then
        for entry in iterator, state do
            if entry ~= "." and entry ~= ".." then
                remove_tree(join(path, entry), lfs)
            end
        end
    end
    pcall(lfs.rmdir, path)
end

function M.removeSettings(options)
    options = options or {}
    local lfs = get_lfs(options)
    local settings_parent = settings_parent_path(options)
    if not lfs or not settings_parent then return false end
    remove_tree(join(settings_parent, M.SETTINGS_DIR), lfs)
    remove_tree(join(settings_parent, M.LEGACY_SETTINGS_DIR), lfs)
    return true
end

local function rewrite_string(value, old_root, new_root, replacements)
    if replacements and replacements[value] then return replacements[value], true end
    if type(old_root) == "string" and old_root ~= "" then
        if value == old_root then return new_root, true end
        local prefix = old_root .. "/"
        if value:sub(1, #prefix) == prefix then
            return new_root .. value:sub(#old_root + 1), true
        end
    end
    return value, false
end

local function rewrite_table(value, old_root, new_root, replacements, seen)
    if type(value) ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true

    local changed = false
    local key_moves = {}
    for key, item in pairs(value) do
        if type(item) == "string" then
            local rewritten, item_changed = rewrite_string(
                item, old_root, new_root, replacements)
            if item_changed then
                value[key] = rewritten
                changed = true
            end
        elseif type(item) == "table"
                and rewrite_table(item, old_root, new_root, replacements, seen) then
            changed = true
        end

        if type(key) == "string" then
            local rewritten_key, key_changed = rewrite_string(
                key, old_root, new_root, replacements)
            if key_changed and rewritten_key ~= key then
                key_moves[#key_moves + 1] = { old = key, new = rewritten_key }
            end
        end
    end
    for _i, move in ipairs(key_moves) do
        if value[move.new] == nil then
            value[move.new] = value[move.old]
            value[move.old] = nil
            changed = true
        end
    end
    return changed
end

function M.rewriteTablePaths(value, old_root, new_root, replacements)
    if type(old_root) ~= "string" or old_root == ""
            or type(new_root) ~= "string" or new_root == ""
            or old_root == new_root then return false end
    return rewrite_table(value, old_root, new_root, replacements)
end

function M.markConfigMigrationComplete(config)
    if type(config) ~= "table" then return false end
    if type(config._meta) ~= "table" then config._meta = {} end
    if config._meta[BRAND_MIGRATION_MARKER] == true then return false end
    config._meta[BRAND_MIGRATION_MARKER] = true
    return true
end

local function migrate_disabled_data(data)
    local disabled = type(data) == "table" and data.plugins_disabled or nil
    if type(disabled) ~= "table" or disabled[M.LEGACY_PLUGIN_ID] == nil then
        return false, false
    end
    if disabled[M.PLUGIN_ID] == nil then
        disabled[M.PLUGIN_ID] = disabled[M.LEGACY_PLUGIN_ID]
    end
    disabled[M.LEGACY_PLUGIN_ID] = nil
    return true, disabled[M.PLUGIN_ID] == true
end

local function flush_settings(settings, prevent_backup)
    if type(settings) ~= "table" or type(settings.flush) ~= "function" then
        return false
    end
    if prevent_backup then settings.backup = function() return false end end
    return pcall(settings.flush, settings)
end

local function rewrite_global_settings(g_settings, old_root, new_root,
        migrate_builtin_custom_text, prevent_backup)
    if type(g_settings) ~= "table" then return false, true end
    local changed = false
    if type(g_settings.data) == "table" then
        changed = M.rewriteTablePaths(g_settings.data, old_root, new_root) or changed
        local migrated_disabled = migrate_disabled_data(g_settings.data)
        changed = migrated_disabled or changed
    else
        for _i, key in ipairs({ "footer", "screensaver_document_cover" }) do
            if type(g_settings.readSetting) == "function" then
                local ok_read, value = pcall(g_settings.readSetting, g_settings, key)
                if ok_read then
                    if type(value) == "table" then
                        if M.rewriteTablePaths(value, old_root, new_root) then
                            if type(g_settings.saveSetting) == "function" then
                                pcall(g_settings.saveSetting, g_settings, key, value)
                            end
                            changed = true
                        end
                    elseif type(value) == "string" then
                        local rewritten, value_changed = rewrite_string(
                            value, old_root, new_root)
                        if value_changed and type(g_settings.saveSetting) == "function" then
                            pcall(g_settings.saveSetting, g_settings, key, rewritten)
                            changed = true
                        end
                    end
                end
            end
        end
    end

    if migrate_builtin_custom_text
            and type(g_settings.readSetting) == "function"
            and type(g_settings.saveSetting) == "function" then
        local ok_read, custom_text = pcall(
            g_settings.readSetting, g_settings, "reader_footer_custom_text")
        if ok_read and custom_text == "Zen UI" then
            pcall(g_settings.saveSetting, g_settings,
                "reader_footer_custom_text", "ZenOS")
            changed = true
        end
    end
    local saved = true
    if changed then saved = flush_settings(g_settings, prevent_backup) end
    return changed, saved
end

local function rewrite_reader_builtins(data)
    if type(data) ~= "table" then return false, false end
    local active_preset = data.active_preset
    if type(data.settings) == "table" and data.settings.active_preset then
        active_preset = data.settings.active_preset
    end
    local builtin_active = READER_BUILTIN_NAMES[active_preset] == true
    local changed = false

    if type(data.presets) == "table" then
        for name, preset in pairs(data.presets) do
            local is_builtin = READER_BUILTIN_NAMES[name] == true
                or (type(preset) == "table"
                    and READER_BUILTIN_NAMES[preset.name] == true)
            if is_builtin and type(preset) == "table"
                    and preset.reader_footer_custom_text == "Zen UI" then
                preset.reader_footer_custom_text = "ZenOS"
                changed = true
            end
        end
    end
    if builtin_active and type(data.settings) == "table"
            and data.settings.reader_footer_custom_text == "Zen UI" then
        data.settings.reader_footer_custom_text = "ZenOS"
        changed = true
    end
    if rewrite_table(data, nil, nil, READER_BRAND_VALUES) then
        changed = true
    end
    return changed, builtin_active
end

local function rewrite_settings_files(settings_root, old_root, new_root, options)
    local lfs = get_lfs(options)
    local LuaSettings = options and options.lua_settings
    if not LuaSettings then
        local ok, loaded = pcall(require, "luasettings")
        if ok then LuaSettings = loaded end
    end
    if not LuaSettings or type(LuaSettings.open) ~= "function" then
        return 0, false, false, false
    end

    local changed_count = 0
    local reader_builtin_active = false
    local reader_backup_builtin_active = false
    local saved = true
    for _i, filename in ipairs(SETTINGS_FILES) do
        local path = join(settings_root, filename)
        for backup_index = 0, 1 do
            local is_backup = backup_index == 1
            local candidate = is_backup and path .. ".old" or path
            if get_mode(lfs, candidate) == "file" then
                local ok_open, settings = pcall(
                    LuaSettings.open, LuaSettings, candidate)
                local changed = ok_open and type(settings) == "table"
                    and type(settings.data) == "table"
                    and M.rewriteTablePaths(
                        settings.data, old_root, new_root) or false
                if filename == "reader.lua" and ok_open
                        and type(settings) == "table" then
                    local reader_changed, is_builtin_active =
                        rewrite_reader_builtins(settings.data)
                    changed = reader_changed or changed
                    if is_backup then
                        reader_backup_builtin_active = is_builtin_active
                    else
                        reader_builtin_active = is_builtin_active
                    end
                end
                if changed then
                    local ok_flush = flush_settings(settings, is_backup)
                    if ok_flush then
                        changed_count = changed_count + 1
                    else
                        saved = false
                        log("warn", "could not save migrated paths in", candidate)
                    end
                elseif not ok_open then
                    saved = false
                end
            end
            -- The live flush above may have created a new legacy .old file;
            -- inspect the backup only after processing the live file.
        end
    end
    return changed_count, reader_builtin_active,
        reader_backup_builtin_active, saved
end

local function rewrite_global_backup(g_settings, old_root, new_root,
        migrate_builtin_custom_text, options)
    local path = type(g_settings) == "table" and g_settings.file or nil
    local lfs = get_lfs(options)
    if type(path) ~= "string" or get_mode(lfs, path .. ".old") ~= "file" then
        return false, true
    end
    local LuaSettings = options and options.lua_settings
    if not LuaSettings then
        local ok, loaded = pcall(require, "luasettings")
        if ok then LuaSettings = loaded end
    end
    if not LuaSettings or type(LuaSettings.open) ~= "function" then
        return false, false
    end
    local ok, backup = pcall(LuaSettings.open, LuaSettings, path .. ".old")
    if not ok then return false, false end
    return rewrite_global_settings(backup, old_root, new_root,
        migrate_builtin_custom_text, true)
end

local function config_store(settings_root, options)
    local lfs = get_lfs(options)
    local path = join(settings_root, "config.lua")
    if get_mode(lfs, path) ~= "file" then return nil end
    local LuaSettings = options and options.lua_settings
    if not LuaSettings then
        local ok, loaded = pcall(require, "luasettings")
        if ok then LuaSettings = loaded end
    end
    if not LuaSettings or type(LuaSettings.open) ~= "function" then return nil end
    local ok, settings = pcall(LuaSettings.open, LuaSettings, path)
    return ok and settings or nil
end

local function migration_marked(settings_root, options)
    local settings = config_store(settings_root, options)
    local meta = settings and type(settings.data) == "table"
        and settings.data._meta or nil
    return type(meta) == "table" and meta[BRAND_MIGRATION_MARKER] == true
end

local function mark_migration_complete(settings_root, options)
    local settings = config_store(settings_root, options)
    if not settings or type(settings.data) ~= "table"
            or type(settings.flush) ~= "function" then return false end
    M.markConfigMigrationComplete(settings.data)
    return pcall(settings.flush, settings)
end

function M.rewritePersistedPaths(settings_root, old_root, new_root, options)
    options = options or {}
    if not options.force and migration_marked(settings_root, options) then
        return false, 0
    end
    local g_settings = options.g_settings
    if g_settings == nil then g_settings = rawget(_G, "G_reader_settings") end
    local files_changed, reader_builtin_active,
        reader_backup_builtin_active, files_saved = rewrite_settings_files(
            settings_root, old_root, new_root, options)
    local global_changed, global_saved = rewrite_global_settings(
        g_settings, old_root, new_root, reader_builtin_active)
    local global_backup_changed, global_backup_saved = rewrite_global_backup(
        g_settings, old_root, new_root, reader_backup_builtin_active, options)
    if files_saved and global_saved and global_backup_saved then
        mark_migration_complete(settings_root, options)
    end
    return global_changed or global_backup_changed, files_changed
end

local function transfer_disabled_key(g_settings)
    if type(g_settings) ~= "table" or type(g_settings.readSetting) ~= "function" then
        return false, false
    end
    local ok_read, disabled = pcall(
        g_settings.readSetting, g_settings, "plugins_disabled")
    if not ok_read or type(disabled) ~= "table" then return false, false end
    local changed, disabled_value = migrate_disabled_data({
        plugins_disabled = disabled,
    })
    if not changed then return false, false end
    if type(g_settings.saveSetting) == "function" then
        pcall(g_settings.saveSetting, g_settings, "plugins_disabled", disabled)
    end
    if type(g_settings.flush) == "function" then pcall(g_settings.flush, g_settings) end
    return true, disabled_value
end

local function registered_root_conflict(plugin_root, plugin_dir)
    local roots = rawget(_G, ROOT_GUARD_KEY)
    if type(roots) ~= "table" then
        roots = {}
        rawset(_G, ROOT_GUARD_KEY, roots)
    end
    if plugin_root then roots[plugin_root] = plugin_dir or true end

    local conflict_paths = {}
    for root in pairs(roots) do
        conflict_paths[#conflict_paths + 1] = root
    end
    if #conflict_paths < 2 then return nil end
    table.sort(conflict_paths)
    return conflict_paths
end

local function as_plugin_conflict(result, conflict_paths)
    local conflict = {}
    for key, value in pairs(result or {}) do conflict[key] = value end
    conflict.proceed = false
    conflict.inert = true
    conflict.pending = nil
    conflict.restart = nil
    conflict.status = "plugin_conflict"
    conflict.conflict_paths = conflict_paths
    return conflict
end

function M.checkRootConflict(result)
    if type(result) ~= "table" or not result.source_plugin_root then return result end
    local paths = registered_root_conflict(
        result.source_plugin_root, result.plugin_dir)
    return paths and as_plugin_conflict(result, paths) or result
end

function M.startup(main_source, options)
    options = options or {}
    local lfs = get_lfs(options)
    local root = options.plugin_root or source_root(main_source, lfs)
    local settings_parent = settings_parent_path(options)
    local result = {
        proceed = true,
        status = "unmanaged",
        plugin_root = root,
    }
    if not root or not settings_parent then return result end

    local development_root = os.getenv and os.getenv("ZEN_UI_ROOT") or nil
    if development_root and trim_trailing_slashes(development_root) == root then
        result.status = "development"
        return result
    end

    local plugin_dir = basename(root)
    if plugin_dir ~= M.LEGACY_PLUGIN_DIR and plugin_dir ~= M.PLUGIN_DIR then
        return result
    end
    local plugin_parent = dirname(root)

    if not lfs then
        result.proceed = false
        result.inert = true
        result.status = "filesystem_unavailable"
        return result
    end
    local guarded_paths = registered_root_conflict(root, plugin_dir)
    if guarded_paths then
        log("warn", "multiple plugin roots detected; startup is disabled")
        return as_plugin_conflict(result, guarded_paths)
    end

    local legacy_root = join(plugin_parent, M.LEGACY_PLUGIN_DIR)
    local new_root = join(plugin_parent, M.PLUGIN_DIR)
    result.legacy_plugin_root = legacy_root
    result.plugin_root = new_root
    result.source_plugin_root = root
    result.settings_parent = settings_parent
    result.plugin_dir = plugin_dir

    local sibling_root = plugin_dir == M.LEGACY_PLUGIN_DIR and new_root or legacy_root
    if get_entry_mode(lfs, sibling_root) ~= nil then
        result.proceed = false
        result.inert = true
        result.status = "plugin_conflict"
        result.conflict_path = sibling_root
        log("warn", "both plugin directories exist; startup is disabled")
        return result
    end

    if plugin_dir == M.LEGACY_PLUGIN_DIR and options.defer_legacy then
        result.proceed = false
        result.inert = true
        result.pending = true
        result.status = "legacy_pending"
        result.options = options
        return result
    end

    local settings = M.prepareSettings(settings_parent, options)
    result.settings = settings
    if not settings.ok then
        result.proceed = false
        result.inert = true
        result.status = settings.status
        log("warn", "settings migration stopped:", settings.status,
            settings.error or "")
        return result
    end

    local g_settings = options.g_settings
    if g_settings == nil then g_settings = rawget(_G, "G_reader_settings") end

    if plugin_dir == M.LEGACY_PLUGIN_DIR then
        local renamed, err = rename_path(legacy_root, new_root, options)
        if not renamed then
            local rename_completed = get_entry_mode(lfs, legacy_root) == nil
                and get_entry_mode(lfs, new_root) == "directory"
            if not rename_completed then
                local rollback_error
                if settings.renamed then
                    local rolled_back, rollback_err = rename_path(
                        settings.root, settings.legacy_root, options)
                    if not rolled_back then rollback_error = rollback_err end
                end
                result.proceed = false
                result.inert = true
                result.status = rollback_error
                    and "plugin_rename_failed_settings_rollback_failed"
                    or "plugin_rename_failed"
                result.error = err
                result.rollback_error = rollback_error
                log("warn", "plugin directory migration failed:", err or "")
                return result
            end
        end
        transfer_disabled_key(g_settings)
        M.rewritePersistedPaths(settings.root, legacy_root, new_root, {
            force = true,
            g_settings = g_settings,
            lfs = lfs,
            lua_settings = options.lua_settings,
        })
        result.proceed = false
        result.inert = true
        result.restart = true
        result.status = "migrated"
        log("info", "plugin and settings migrated; restart requested")
        return result
    end

    local disabled_transferred, disabled = transfer_disabled_key(g_settings)
    result.disabled_state_transferred = disabled_transferred
    M.rewritePersistedPaths(settings.root, legacy_root, new_root, {
        force = settings.status == "migrated",
        g_settings = g_settings,
        lfs = lfs,
        lua_settings = options.lua_settings,
    })
    result.status = settings.status == "migrated"
        and "settings_migrated" or "current"
    if disabled then
        result.proceed = false
        result.inert = true
        result.restart = true
        result.status = "disabled_state_migrated"
    end
    return result
end

local function copy_options(options)
    local copy = {}
    for key, value in pairs(options or {}) do copy[key] = value end
    return copy
end

function M.detectStartup(main_source, options)
    local detection_options = copy_options(options)
    detection_options.defer_legacy = true
    return M.startup(main_source, detection_options)
end

function M.performPending(result, options)
    if type(result) ~= "table" or not result.pending then return result end
    local perform_options = copy_options(result.options)
    for key, value in pairs(options or {}) do perform_options[key] = value end
    perform_options.defer_legacy = false
    perform_options.plugin_root = result.source_plugin_root
    perform_options.settings_dir = result.settings_parent
    return M.startup(nil, perform_options)
end

local function notice_text(result)
    if result.restart then
        if result.status == "disabled_state_migrated" then
            return "ZenOS preserved the disabled plugin setting. Restarting..."
        end
        return "ZenOS upgrade complete. Restarting..."
    end
    if result.status == "plugin_conflict" then
        return "ZenOS found more than one plugin copy. Close KOReader, keep "
            .. "one zenos.koplugin folder, move or remove every duplicate "
            .. "and zen_ui.koplugin folder, then restart. No files were changed."
    end
    if result.status == "settings_conflict" then
        return "ZenOS found both Zen UI and ZenOS settings. Close KOReader, "
            .. "back up both folders, move one aside, then restart. Neither "
            .. "folder was overwritten."
    end
    return "ZenOS could not finish migrating. Check available storage and "
        .. "folder permissions, then restart KOReader to retry. Existing files "
        .. "were kept."
end

function M.notify(result)
    if type(result) ~= "table" or not result.inert then return end
    if rawget(_G, "__ZENOS_BRAND_MIGRATION_NOTICE") then return end
    _G.__ZENOS_BRAND_MIGRATION_NOTICE = true

    local ok_ui, UIManager = pcall(require, "ui/uimanager")
    local ok_info, InfoMessage = pcall(require, "ui/widget/infomessage")
    if ok_ui and ok_info then
        UIManager:show(InfoMessage:new{ text = notice_text(result) })
    end
    if not result.restart or not ok_ui then return end

    local ok_event, Event = pcall(require, "ui/event")
    if not ok_event then return end
    local restart = function()
        UIManager:broadcastEvent(Event:new("Restart"))
    end
    if type(UIManager.tickAfterNext) == "function" then
        UIManager:tickAfterNext(restart)
    elseif type(UIManager.nextTick) == "function" then
        UIManager:nextTick(restart)
    else
        restart()
    end
end

return M

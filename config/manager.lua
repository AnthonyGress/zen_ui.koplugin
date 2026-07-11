local defaults = require("config/defaults")
local HomePresets = require("modules/filebrowser/patches/home/home_presets")
local PresetStore = require("config/preset_store")
local HomeQuotes = require("modules/filebrowser/patches/home/home_quotes")
local utils = require("common/utils")

local LEGACY_KEY = "zen_ui_config"  -- legacy G_reader_settings key; cleanup only

local _zen_settings_file = nil  -- cached LuaSettings instance
local _current_config    = nil  -- in-memory cache for M.get()

local M = {}

local function get_settings_path()
    return PresetStore.rootDir() .. "/config.lua"
end

local function open_zen_file()
    if not _zen_settings_file then
        local LuaSettings = require("luasettings")
        _zen_settings_file = LuaSettings:open(get_settings_path())
    end
    return _zen_settings_file
end

-- Returns the stored config table and whether it came from settings.reader.lua.
local function load_raw_config()
    local f = open_zen_file()
    if type(f.data) == "table" and next(f.data) ~= nil then
        return f.data, false
    end
    local g = rawget(_G, "G_reader_settings")
    local legacy = g and g:readSetting(LEGACY_KEY)
    if type(legacy) == "table" then
        return legacy, true
    end
    return {}, false
end

local function merged_with_defaults(stored)
    local cfg = utils.deepcopy(defaults)
    if type(stored) == "table" then
        utils.deepmerge(stored, cfg)
        cfg = stored
    end
    utils.deepmerge(cfg, defaults)
    return cfg
end

local function normalize_renamed_keys(cfg)
    if type(cfg) ~= "table" then
        return cfg, false
    end

    cfg.features = cfg.features or {}
    local changed = false

    if cfg.features.disable_top_menu_swipe_zones == nil
       and cfg.features.disable_top_menu_zones ~= nil then
        cfg.features.disable_top_menu_swipe_zones = cfg.features.disable_top_menu_zones
        changed = true
    end

    if cfg.features.browser_hide_up_folder == nil
       and cfg.features.browser_up_folder ~= nil then
        cfg.features.browser_hide_up_folder = cfg.features.browser_up_folder
        changed = true
    end

    if cfg.browser_hide_up_folder == nil and cfg.browser_up_folder ~= nil then
        cfg.browser_hide_up_folder = cfg.browser_up_folder
        changed = true
    end
    if type(cfg.browser_hide_up_folder) ~= "table" then
        cfg.browser_hide_up_folder = {}
        changed = true
    end
    local lock_mode = cfg.browser_hide_up_folder.lock_home_folder
    if lock_mode == true then
        cfg.browser_hide_up_folder.lock_home_folder = "on"
        changed = true
    elseif lock_mode == false then
        cfg.browser_hide_up_folder.lock_home_folder = "off"
        changed = true
    elseif lock_mode ~= "off" and lock_mode ~= "zen" and lock_mode ~= "on" then
        cfg.browser_hide_up_folder.lock_home_folder = "zen"
        changed = true
    end

    -- Always-on features: no user toggle in Zen settings.
    cfg.features.browser_folder_cover = true

    if type(cfg.navbar) == "table" and cfg.navbar.active_tab_bold ~= nil then
        cfg.navbar.active_tab_bold = nil
        changed = true
    end
    if type(cfg.navbar) == "table" and cfg.navbar.active_tab_styling ~= nil then
        cfg.navbar.active_tab_styling = nil
        changed = true
    end

    if type(cfg.group_view) == "table"
            and cfg.group_view.mark_new_as_tbr ~= nil then
        cfg.group_view.include_new_in_tbr = cfg.group_view.mark_new_as_tbr == true
        cfg.group_view.mark_new_as_tbr = nil
        changed = true
    end

    return cfg, changed
end

local function migrate_legacy_rakuyomi_keys(cfg)
    local rakuyomi = type(cfg) == "table" and cfg.rakuyomi
    if type(rakuyomi) ~= "table" then
        return false
    end

    local changed = false
    if rakuyomi.return_to_chapter_list_on_exit == nil
            and rakuyomi.return_to_chapter_list_on_reader_exit ~= nil then
        rakuyomi.return_to_chapter_list_on_exit =
            rakuyomi.return_to_chapter_list_on_reader_exit
        changed = true
    end
    if rakuyomi.return_to_chapter_list_on_reader_exit ~= nil then
        rakuyomi.return_to_chapter_list_on_reader_exit = nil
        changed = true
    end
    if rakuyomi.return_to_chapter_on_reader_exit ~= nil then
        rakuyomi.return_to_chapter_on_reader_exit = nil
        changed = true
    end

    return changed
end

local function collect_setting_keys(g_settings)
    local keys = {}

    if type(g_settings.pairs) == "function" then
        local ok_pairs, iterator, state, first_key = pcall(g_settings.pairs, g_settings)
        if ok_pairs and type(iterator) == "function" then
            local key_name = first_key
            while true do
                local next_key = iterator(state, key_name)
                if next_key == nil then break end
                if type(next_key) == "string" then
                    keys[next_key] = true
                end
                key_name = next_key
            end
        end
    end

    local tables_to_scan = {
        rawget(g_settings, "data"),
        rawget(g_settings, "settings"),
        rawget(g_settings, "_data"),
    }

    for i = 1, #tables_to_scan do
        local tbl = tables_to_scan[i]
        if type(tbl) == "table" then
            for key_name in pairs(tbl) do
                if type(key_name) == "string" then
                    keys[key_name] = true
                end
            end
        end
    end

    if type(g_settings) == "table" then
        for key_name in pairs(g_settings) do
            if type(key_name) == "string" then
                keys[key_name] = true
            end
        end
    end

    return keys
end

local function migrate_legacy_group_view_keys(cfg)
    local g = rawget(_G, "G_reader_settings")
    if not g or type(cfg) ~= "table" then
        return cfg, false
    end

    local changed = false
    local removed_legacy = false

    local function ensure_group_view()
        if type(cfg.group_view) ~= "table" then
            cfg.group_view = {}
            changed = true
        end
        return cfg.group_view
    end

    local function ensure_display_mode()
        local group_view = ensure_group_view()
        if type(group_view.display_mode) ~= "table" then
            group_view.display_mode = {}
            changed = true
        end
        return group_view.display_mode
    end

    local function ensure_detail_collate(tab_id)
        local group_view = ensure_group_view()
        if type(group_view.detail_collate) ~= "table" then
            group_view.detail_collate = {}
            changed = true
        end
        local detail_collate = group_view.detail_collate
        if type(detail_collate[tab_id]) ~= "table" then
            detail_collate[tab_id] = {}
            changed = true
        end
        return detail_collate[tab_id]
    end

    local function ensure_group_reverse()
        local group_view = ensure_group_view()
        if type(group_view.group_reverse) ~= "table" then
            group_view.group_reverse = {}
            changed = true
        end
        return group_view.group_reverse
    end

    local function ensure_detail_reverse(tab_id)
        local group_view = ensure_group_view()
        if type(group_view.detail_reverse) ~= "table" then
            group_view.detail_reverse = {}
            changed = true
        end
        local detail_reverse = group_view.detail_reverse
        if type(detail_reverse[tab_id]) ~= "table" then
            detail_reverse[tab_id] = {}
            changed = true
        end
        return detail_reverse[tab_id]
    end

    local function ensure_tags_global()
        local group_view = ensure_group_view()
        if type(group_view.tags_global) ~= "table" then
            group_view.tags_global = {}
            changed = true
        end
        return group_view.tags_global
    end

    local setting_keys = collect_setting_keys(g)

    for key_name in pairs(setting_keys) do
        local display_tab = key_name:match("^zen_(.+)_display_mode$")
        if display_tab then
            local legacy_value = g:readSetting(key_name)
            if legacy_value ~= nil then
                local display_mode = ensure_display_mode()
                if display_mode[display_tab] == nil then
                    display_mode[display_tab] = legacy_value
                    changed = true
                end
                g:delSetting(key_name)
                removed_legacy = true
            end
        else
            local detail_tab, group_name = key_name:match("^zen_(.+)_detail_collate_(.+)$")
            if detail_tab and group_name then
                local legacy_value = g:readSetting(key_name)
                if legacy_value ~= nil then
                    local detail_collate = ensure_detail_collate(detail_tab)
                    if detail_collate[group_name] == nil then
                        detail_collate[group_name] = legacy_value
                        changed = true
                    end
                    g:delSetting(key_name)
                    removed_legacy = true
                end
            else
                local reverse_tab, reverse_group = key_name:match("^zen_(.+)_detail_reverse_(.+)$")
                if reverse_tab and reverse_group then
                    local legacy_value = g:readSetting(key_name)
                    if legacy_value ~= nil then
                        local detail_reverse = ensure_detail_reverse(reverse_tab)
                        if detail_reverse[reverse_group] == nil then
                            if legacy_value == true then
                                detail_reverse[reverse_group] = true
                            end
                            changed = true
                        end
                        g:delSetting(key_name)
                        removed_legacy = true
                    end
                end
            end
        end
    end

    local tags_global_collate = g:readSetting("zen_tags_global_collate")
    if tags_global_collate ~= nil then
        local tags_global = ensure_tags_global()
        if type(tags_global.collate) ~= "string" or tags_global.collate == "" then
            tags_global.collate = type(tags_global_collate) == "string"
                and tags_global_collate or "title"
            changed = true
        end
        g:delSetting("zen_tags_global_collate")
        removed_legacy = true
    end

    local tags_global_reverse = g:readSetting("zen_tags_global_reverse")
    if tags_global_reverse ~= nil then
        local tags_global = ensure_tags_global()
        if tags_global.reverse == nil then
            tags_global.reverse = tags_global_reverse == true
            changed = true
        end
        g:delSetting("zen_tags_global_reverse")
        removed_legacy = true
    end

    local authors_reverse = g:readSetting("zen_authors_reverse")
    if authors_reverse ~= nil then
        local group_reverse = ensure_group_reverse()
        if group_reverse.authors == nil then
            group_reverse.authors = authors_reverse == true
            changed = true
        end
        g:delSetting("zen_authors_reverse")
        removed_legacy = true
    end

    local series_reverse = g:readSetting("zen_series_reverse")
    if series_reverse ~= nil then
        local group_reverse = ensure_group_reverse()
        if group_reverse.series == nil then
            group_reverse.series = series_reverse == true
            changed = true
        end
        g:delSetting("zen_series_reverse")
        removed_legacy = true
    end

    local legacy_layout = g:readSetting("zen_page_browser_layout")
    if legacy_layout ~= nil then
        if type(cfg.reader_page_browser) ~= "table" then
            cfg.reader_page_browser = {}
            changed = true
        end
        if cfg.reader_page_browser.layout == nil then
            cfg.reader_page_browser.layout = legacy_layout
            changed = true
        end
        g:delSetting("zen_page_browser_layout")
        removed_legacy = true
    end

    if removed_legacy then
        pcall(g.flush, g)
    end

    return cfg, (changed or removed_legacy)
end

local function migrate_legacy_updater_keys(cfg)
    local g = rawget(_G, "G_reader_settings")
    if not g or type(cfg) ~= "table" then
        return cfg, false
    end

    if type(cfg.updater) ~= "table" then
        cfg.updater = {}
    end
    local updater = cfg.updater
    local changed = false
    local removed_legacy = false

    for _i, key_name in ipairs({
        "latest_version",
        "update_dl_url",
        "update_sha256",
    }) do
        if updater[key_name] ~= nil then
            updater[key_name] = nil
            changed = true
        end
    end

    local function del_legacy(key_name)
        g:delSetting(key_name)
        removed_legacy = true
    end

    local just_updated = g:readSetting("zen_ui_just_updated")
    if just_updated ~= nil then
        if type(just_updated) == "string" and updater.just_updated_version ~= just_updated then
            updater.just_updated_version = just_updated
            changed = true
        end
        del_legacy("zen_ui_just_updated")
    end

    local last_check = g:readSetting("zen_ui_last_update_check")
    if last_check ~= nil then
        local normalized = type(last_check) == "number" and last_check or 0
        if updater.last_update_check ~= normalized then
            updater.last_update_check = normalized
            changed = true
        end
        del_legacy("zen_ui_last_update_check")
    end

    local update_available = g:readSetting("zen_ui_update_available")
    if update_available ~= nil then
        local normalized = update_available == true
        if updater.update_available ~= normalized then
            updater.update_available = normalized
            changed = true
        end
        del_legacy("zen_ui_update_available")
    end

    local latest_version = g:readSetting("zen_ui_latest_version")
    if latest_version ~= nil then
        del_legacy("zen_ui_latest_version")
    end

    local update_dl_url = g:readSetting("zen_ui_update_dl_url")
    if update_dl_url ~= nil then
        del_legacy("zen_ui_update_dl_url")
    end

    local update_sha256 = g:readSetting("zen_ui_update_sha256")
    if update_sha256 ~= nil then
        del_legacy("zen_ui_update_sha256")
    end

    local update_channel = g:readSetting("zen_ui_update_channel")
    if update_channel ~= nil then
        local normalized = update_channel == "beta" and "beta" or "stable"
        if updater.update_channel ~= normalized then
            updater.update_channel = normalized
            changed = true
        end
        del_legacy("zen_ui_update_channel")
    end

    local update_auto_check = g:readSetting("zen_ui_update_auto_check")
    if update_auto_check ~= nil then
        local normalized = update_auto_check ~= false
        if updater.update_auto_check ~= normalized then
            updater.update_auto_check = normalized
            changed = true
        end
        del_legacy("zen_ui_update_auto_check")
    end

    if removed_legacy then
        pcall(g.flush, g)
    end

    return cfg, changed
end

local function migrate_folder_path_settings(cfg)
    if type(cfg) ~= "table" then return cfg, false end

    local changed = false
    if type(cfg.folder_sort) ~= "table" then
        cfg.folder_sort = {}
        changed = true
    end
    if type(cfg.folder_display_mode) ~= "table" then
        cfg.folder_display_mode = {}
        changed = true
    end

    local g = rawget(_G, "G_reader_settings")
    if not g then return cfg, changed end

    local removed_legacy = false
    local valid_display_modes = {
        mosaic_image = true,
        list_image_meta = true,
        list_image_filename = true,
    }

    local legacy_sort = g:readSetting("zen_ui_folder_sort")
    if type(legacy_sort) == "table" then
        for path, entry in pairs(legacy_sort) do
            if type(path) == "string" and cfg.folder_sort[path] == nil then
                if type(entry) == "string" then
                    cfg.folder_sort[path] = { collate = entry, reverse = false }
                    changed = true
                elseif type(entry) == "table" and type(entry.collate) == "string" then
                    cfg.folder_sort[path] = {
                        collate = entry.collate,
                        reverse = entry.reverse == true,
                    }
                    changed = true
                end
            end
        end
        g:delSetting("zen_ui_folder_sort")
        removed_legacy = true
    end

    local legacy_display = g:readSetting("zen_ui_folder_display_mode")
    if type(legacy_display) == "table" then
        for path, mode in pairs(legacy_display) do
            if type(path) == "string" and cfg.folder_display_mode[path] == nil
                    and valid_display_modes[mode] then
                cfg.folder_display_mode[path] = mode
                changed = true
            end
        end
        g:delSetting("zen_ui_folder_display_mode")
        removed_legacy = true
    end

    if removed_legacy then
        pcall(g.flush, g)
    end

    return cfg, (changed or removed_legacy)
end

local function migrate_folder_cover_keys(cfg)
    local g = rawget(_G, "G_reader_settings")
    if not g or type(cfg) ~= "table" then return cfg, false end

    if type(cfg.browser_folder_cover) ~= "table" then
        cfg.browser_folder_cover = {}
    end
    local fbc = cfg.browser_folder_cover
    local changed = false
    local removed_legacy = false

    -- Read legacy keys before deleting them.
    local gallery_val = g:readSetting("folder_gallery_mode")
    local stack_val   = g:isTrue("folder_stack_mode")
    local none_val    = g:isTrue("folder_none_mode")
    local has_legacy  = gallery_val ~= nil or stack_val or none_val

    if has_legacy then
        -- Existing user: override cover_mode from their legacy selection.
        -- merged_with_defaults already ran so fbc.cover_mode is "gallery"; we must overwrite.
        -- New installs never have these keys so defaults.lua applies cleanly.
        if none_val then
            fbc.cover_mode = "none"
        elseif stack_val then
            fbc.cover_mode = "stack"
        elseif gallery_val == false then
            fbc.cover_mode = "normal"
        else
            fbc.cover_mode = "gallery"
        end
        changed = true
    end

    for _i, key in ipairs({ "folder_gallery_mode", "folder_stack_mode", "folder_none_mode" }) do
        if g:readSetting(key) ~= nil then
            g:delSetting(key)
            removed_legacy = true
        end
    end

    if removed_legacy then pcall(g.flush, g) end
    return cfg, (changed or removed_legacy)
end

local function migrate_bim_folder_cover_keys(cfg)
    if type(cfg._meta) == "table" and cfg._meta.bim_fbc_migrated then
        return cfg, false
    end

    local ok, bim = pcall(require, "bookinfomanager")
    if not ok or not bim then return cfg, false end

    if type(cfg.browser_folder_cover) ~= "table" then
        cfg.browser_folder_cover = {}
    end
    local fbc = cfg.browser_folder_cover
    -- All BIM folder cover keys used BooleanSetting(default=true): get() = not BIM_value.
    -- Zen config stores the direct value, so: zen_value = BIM_value ~= true.
    local mappings = {
        { bim = "folder_crop_custom_image", cfg = "crop_to_fit"      },
        { bim = "folder_name_centered",     cfg = "name_centered"     },
        { bim = "folder_name_show",         cfg = "show_folder_name"  },
        { bim = "folder_item_count_show",   cfg = "show_item_count"   },
        { bim = "folder_name_opaque",       cfg = "name_opaque"       },
        { bim = "folder_spine_lines_show",  cfg = "show_spine_lines"  },
    }
    for _i, m in ipairs(mappings) do
        local bim_val = bim:getSetting(m.bim)
        if bim_val ~= nil then
            fbc[m.cfg] = bim_val ~= true
            pcall(bim.saveSetting, bim, m.bim, nil)
        end
    end

    -- Migrate display modes (plain strings, no inversion)
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    local gv = cfg.group_view
    if type(gv.display_mode) ~= "table" then gv.display_mode = {} end
    local dm = gv.display_mode
    local dm_mappings = {
        { bim = "collection_display_mode", key = "collections" },
        { bim = "history_display_mode",    key = "history"     },
    }
    for _i, m in ipairs(dm_mappings) do
        local bim_val = bim:getSetting(m.bim)
        if bim_val ~= nil then
            dm[m.key] = bim_val
            pcall(bim.saveSetting, bim, m.bim, nil)
        end
    end

    if type(cfg._meta) == "table" then
        cfg._meta.bim_fbc_migrated = true
    end
    return cfg, true  -- always save: marks migration as attempted
end

local function capture_screensaver_settings()
    local g = rawget(_G, "G_reader_settings")
    if not g then return {} end
    return {
        screensaver_type = g:readSetting("screensaver_type"),
        screensaver_message = g:readSetting("screensaver_message"),
        screensaver_show_message = g:isTrue("screensaver_show_message"),
        screensaver_img_background = g:readSetting("screensaver_img_background"),
        screensaver_document_cover = g:readSetting("screensaver_document_cover"),
        screensaver_stretch_images = g:isTrue("screensaver_stretch_images"),
        screensaver_stretch_limit_percentage = g:readSetting("screensaver_stretch_limit_percentage"),
    }
end

local function capture_reader_footer_settings()
    local g = rawget(_G, "G_reader_settings")
    if not g then return {} end
    local util = require("util")
    local footer = g:readSetting("footer")
    return {
        footer = type(footer) == "table" and util.tableDeepCopy(footer) or {},
        reader_footer_mode = g:readSetting("reader_footer_mode") or 1,
        reader_footer_custom_text = g:readSetting("reader_footer_custom_text") or "KOReader",
        reader_footer_custom_text_repetitions = g:readSetting("reader_footer_custom_text_repetitions") or 1,
    }
end

local function migrate_reader_footer_backup(cfg)
    if type(cfg) ~= "table" or type(cfg.reader_footer) ~= "table" then
        return false
    end
    local backup = cfg.reader_footer.backup_preset
    if type(backup) ~= "table" then return false end
    if type(backup.name) ~= "string" or backup.name == "" then
        backup.name = "Backup of Original"
    end
    backup.builtin = true
    PresetStore.save("reader", backup.name, backup)
    PresetStore.saveSettings("reader", capture_reader_footer_settings())
    cfg.reader_footer.backup_preset = nil
    return true
end

local function migrate_settings_files()
    local changed = PresetStore.migrateStores({
        home = HomePresets.defaultHomePage(),
        reader = capture_reader_footer_settings(),
        screensaver = capture_screensaver_settings(),
    })
    if HomeQuotes.ensureFile() then
        changed = true
    end
    return changed
end

local function migrate_changed_defaults(cfg)
    if type(cfg) ~= "table" then
        return cfg, false
    end

    local changed = false
    if type(cfg._meta) ~= "table" then
        cfg._meta = {}
        changed = true
    end

    if cfg._meta.reader_footer_hide_cbz_default_migrated ~= true then
        if type(cfg.reader_footer) ~= "table" then
            cfg.reader_footer = {}
        end
        if cfg.reader_footer.hide_in_cbz ~= true then
            cfg.reader_footer.hide_in_cbz = true
        end
        cfg._meta.reader_footer_hide_cbz_default_migrated = true
        changed = true
    end

    if cfg._meta.context_menu_allow_delete_default_migrated ~= true then
        if type(cfg.context_menu) ~= "table" then
            cfg.context_menu = {}
        end
        if cfg.context_menu.allow_delete ~= true then
            cfg.context_menu.allow_delete = true
        end
        cfg._meta.context_menu_allow_delete_default_migrated = true
        changed = true
    end

    -- One-time seed of home strip book titles from the mosaic "Show title below
    -- cover" setting. After this runs once, strip titles are user-owned and the
    -- mosaic setting no longer overrides them.
    if cfg._meta.home_strip_titles_seeded ~= true then
        local show = type(cfg.mosaic_title_strip) == "table"
            and cfg.mosaic_title_strip.show_title == true
        if show then
            local dcfg = PresetStore.getSettings("home")
            if type(dcfg) == "table" and next(dcfg) ~= nil then
                HomePresets.applyMosaicTitlesToStrips(dcfg, true)
                PresetStore.saveSettings("home", dcfg)
            end
        end
        cfg._meta.home_strip_titles_seeded = true
        changed = true
    end

    return cfg, changed
end

function M.get()
    return _current_config
end

function M.settingsPath()
    return get_settings_path()
end

function M.load()
    local stored, migrated_file_config = load_raw_config()
    local migrated_home_lock = false
    local stored_hide_up = type(stored) == "table" and rawget(stored, "browser_hide_up_folder")
    if type(stored_hide_up) ~= "table" or stored_hide_up.lock_home_folder == nil then
        local g = rawget(_G, "G_reader_settings")
        if g and g.isTrue and g:isTrue("lock_home_folder") then
            if type(stored_hide_up) ~= "table" then
                stored.browser_hide_up_folder = {}
                stored_hide_up = stored.browser_hide_up_folder
            end
            stored_hide_up.lock_home_folder = "on"
            migrated_home_lock = true
        end
    end

    -- Existing install that predates the quickstart feature: stored config is
    -- non-empty but lacks quickstart_shown_for_version. deepmerge would fill
    -- it with false (new-install trigger), so set a sentinel before merging.
    local migrated_qs = false
    if type(stored) == "table" and next(stored) ~= nil then
        local m = rawget(stored, "_meta")
        if type(m) ~= "table" or m.quickstart_shown_for_version == nil then
            stored._meta = (type(m) == "table" and m) or {}
            stored._meta.quickstart_shown_for_version = "pre-quickstart"
            migrated_qs = true
        end
    end

    local migrated_rakuyomi = migrate_legacy_rakuyomi_keys(stored)
    local cfg = merged_with_defaults(stored)
    local migrated_renamed
    cfg, migrated_renamed = normalize_renamed_keys(cfg)
    local migrated_group, migrated_updater, migrated_folder_paths, migrated_fbc, migrated_bim
    cfg, migrated_group   = migrate_legacy_group_view_keys(cfg)
    cfg, migrated_updater = migrate_legacy_updater_keys(cfg)
    cfg, migrated_folder_paths = migrate_folder_path_settings(cfg)
    cfg, migrated_fbc     = migrate_folder_cover_keys(cfg)
    cfg, migrated_bim     = migrate_bim_folder_cover_keys(cfg)
    local migrated_reader_backup = migrate_reader_footer_backup(cfg)
    local migrated_settings_files = migrate_settings_files()
    local migrated_changed_defaults
    cfg, migrated_changed_defaults = migrate_changed_defaults(cfg)
    if migrated_renamed or migrated_group or migrated_updater or migrated_fbc or migrated_bim
            or migrated_reader_backup or migrated_qs or migrated_file_config
            or migrated_settings_files or migrated_changed_defaults or migrated_home_lock
            or migrated_folder_paths or migrated_rakuyomi then
        M.save(cfg)
    end
    if migrated_file_config then
        local g = rawget(_G, "G_reader_settings")
        if g and type(g.delSetting) == "function" then -- luacheck: ignore 542
            -- TODO: re-enable to delete legacy zen_ui_config key from settings.reader.lua
            -- pcall(g.delSetting, g, LEGACY_KEY)
            -- pcall(g.flush, g)
        end
    end
    _current_config = cfg
    return cfg
end

function M.save(config)
    local f = open_zen_file()
    f.data = config
    f:flush()
    _current_config = config
end

function M.moveFolderPathSettings(from_path, to_path)
    if type(from_path) ~= "string" or type(to_path) ~= "string" then return false end

    local paths = require("common/paths")
    local function normalize(path)
        path = paths.normPath(path:gsub("/+$", ""))
        return path ~= "" and path or "/"
    end

    local source = normalize(from_path)
    local destination = normalize(to_path)
    if source == destination then return false end

    local cfg = M.get()
    if type(cfg) ~= "table" then cfg = M.load() end
    local changed = false

    for _i, map_name in ipairs({ "folder_sort", "folder_display_mode" }) do
        local settings = cfg[map_name]
        if type(settings) == "table" then
            local moves = {}
            for key, value in pairs(settings) do
                if type(key) == "string" then
                    local normalized_key = normalize(key)
                    if normalized_key == source
                            or normalized_key:sub(1, #source + 1) == source .. "/" then
                        moves[#moves + 1] = {
                            from = key,
                            to = destination .. normalized_key:sub(#source + 1),
                            value = value,
                        }
                    end
                end
            end
            for _j, move in ipairs(moves) do
                settings[move.from] = nil
                if settings[move.to] == nil then
                    settings[move.to] = move.value
                end
                changed = true
            end
        end
    end

    if changed then M.save(cfg) end
    return changed
end

-- Kept for deletePluginSettings: identifies the legacy G_reader_settings key
-- so it can be cleaned up alongside the dedicated file.
function M.key()
    return LEGACY_KEY
end

return M

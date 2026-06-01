local defaults = require("config/defaults")
local utils = require("common/utils")

local KEY = "zen_ui_config"
local M = {}

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
        return cfg
    end

    cfg.features = cfg.features or {}

    if cfg.features.disable_top_menu_swipe_zones == nil
       and cfg.features.disable_top_menu_zones ~= nil then
        cfg.features.disable_top_menu_swipe_zones = cfg.features.disable_top_menu_zones
    end

    if cfg.features.browser_hide_up_folder == nil
       and cfg.features.browser_up_folder ~= nil then
        cfg.features.browser_hide_up_folder = cfg.features.browser_up_folder
    end

    if cfg.browser_hide_up_folder == nil and cfg.browser_up_folder ~= nil then
        cfg.browser_hide_up_folder = cfg.browser_up_folder
    end

    -- Always-on features: no user toggle in Zen settings.
    cfg.features.browser_folder_cover = true

    return cfg
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
        local normalized = type(latest_version) == "string" and latest_version or ""
        if updater.latest_version ~= normalized then
            updater.latest_version = normalized
            changed = true
        end
        del_legacy("zen_ui_latest_version")
    end

    local update_dl_url = g:readSetting("zen_ui_update_dl_url")
    if update_dl_url ~= nil then
        local normalized = type(update_dl_url) == "string" and update_dl_url or ""
        if updater.update_dl_url ~= normalized then
            updater.update_dl_url = normalized
            changed = true
        end
        del_legacy("zen_ui_update_dl_url")
    end

    local update_sha256 = g:readSetting("zen_ui_update_sha256")
    if update_sha256 ~= nil then
        local normalized = type(update_sha256) == "string" and update_sha256 or ""
        if updater.update_sha256 ~= normalized then
            updater.update_sha256 = normalized
            changed = true
        end
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

function M.load()
    local stored = G_reader_settings:readSetting(KEY, {})
    local cfg = merged_with_defaults(stored)
    cfg = normalize_renamed_keys(cfg)
    local migrated_group
    local migrated_updater
    local migrated_fbc
    cfg, migrated_group   = migrate_legacy_group_view_keys(cfg)
    cfg, migrated_updater = migrate_legacy_updater_keys(cfg)
    cfg, migrated_fbc     = migrate_folder_cover_keys(cfg)
    local migrated_bim
    cfg, migrated_bim     = migrate_bim_folder_cover_keys(cfg)
    if migrated_group or migrated_updater or migrated_fbc or migrated_bim then
        M.save(cfg)
    end
    return cfg
end

function M.save(config)
    G_reader_settings:saveSetting(KEY, config)
end

function M.key()
    return KEY
end

return M

-- settings/sections/library_settings.lua
-- Library (filebrowser) settings items for Zen UI.
-- Receives ctx: { plugin, config, save_and_apply, apply_feature }

local _ = require("gettext")
local UIManager = require("ui/uimanager")

local status_bar_section = require("settings/sections/library_settings/status_bar_settings")
local settings_apply     = require("settings/zen_settings_apply")

local M = {}

function M.build(ctx)
    local config        = ctx.config
    local plugin        = ctx.plugin
    local save_and_apply = ctx.save_and_apply

    local items = {}

    table.insert(items, status_bar_section.build(ctx))

    -- -------------------------------------------------------------------------
    -- Folders
    -- -------------------------------------------------------------------------

    table.insert(items, {
        text = _("Folders"),
        sub_item_table = {
            {
                text = _("Hide up folder"),
                checked_func = function() return config.browser_hide_up_folder.hide_up_folder == true end,
                callback = function()
                    config.browser_hide_up_folder.hide_up_folder =
                        not (config.browser_hide_up_folder.hide_up_folder == true)
                    save_and_apply("browser_hide_up_folder")
                end,
            },
            {
                text = _("Show folder covers as gallery"),
                checked_func = function()
                    local ok, bim = pcall(require, "bookinfomanager")
                    if not ok then return false end
                    return bim:getSetting("folder_gallery_mode") ~= nil
                end,
                callback = function()
                    local ok, bim = pcall(require, "bookinfomanager")
                    if not ok then return end
                    bim:toggleSetting("folder_gallery_mode")
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Show folder name on cover"),
                checked_func = function()
                    local ok, bim = pcall(require, "bookinfomanager")
                    if not ok then return true end
                    return not bim:getSetting("folder_name_show")
                end,
                callback = function()
                    local ok, bim = pcall(require, "bookinfomanager")
                    if not ok then return end
                    bim:toggleSetting("folder_name_show")
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Show item count on folder covers"),
                checked_func = function()
                    local ok, bim = pcall(require, "bookinfomanager")
                    if not ok then return true end
                    return not bim:getSetting("folder_item_count_show")
                end,
                callback = function()
                    local ok, bim = pcall(require, "bookinfomanager")
                    if not ok then return end
                    bim:toggleSetting("folder_item_count_show")
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Folder name opaque background"),
                checked_func = function()
                    local ok, bim = pcall(require, "bookinfomanager")
                    if not ok then return true end
                    return not bim:getSetting("folder_name_opaque")
                end,
                callback = function()
                    local ok, bim = pcall(require, "bookinfomanager")
                    if not ok then return end
                    bim:toggleSetting("folder_name_opaque")
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Folder name position"),
                sub_item_table = {
                    {
                        text = _("Center"),
                        radio = true,
                        checked_func = function()
                            local ok, bim = pcall(require, "bookinfomanager")
                            if not ok then return true end
                            return not bim:getSetting("folder_name_centered")
                        end,
                        callback = function()
                            local ok, bim = pcall(require, "bookinfomanager")
                            if not ok then return end
                            if bim:getSetting("folder_name_centered") then
                                bim:toggleSetting("folder_name_centered")
                            end
                            UIManager:setDirty(nil, "full")
                        end,
                    },
                    {
                        text = _("Bottom"),
                        radio = true,
                        checked_func = function()
                            local ok, bim = pcall(require, "bookinfomanager")
                            if not ok then return false end
                            return bim:getSetting("folder_name_centered") ~= nil
                        end,
                        callback = function()
                            local ok, bim = pcall(require, "bookinfomanager")
                            if not ok then return end
                            if not bim:getSetting("folder_name_centered") then
                                bim:toggleSetting("folder_name_centered")
                            end
                            UIManager:setDirty(nil, "full")
                        end,
                    },
                },
            },
        },
    })

    -- -------------------------------------------------------------------------
    -- Covers
    -- -------------------------------------------------------------------------

    table.insert(items, {
        text = _("Covers"),
        sub_item_table = {
            {
                text = _("Rounded cover corners"),
                checked_func = function()
                    return type(config.features) == "table"
                        and config.features.browser_cover_rounded_corners == true
                end,
                callback = function()
                    if type(config.features) ~= "table" then config.features = {} end
                    config.features.browser_cover_rounded_corners =
                        not (config.features.browser_cover_rounded_corners == true)
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Uniform covers"),
                checked_func = function()
                    return type(config.features) == "table"
                        and config.features.browser_cover_mosaic_uniform == true
                end,
                callback = function()
                    if type(config.features) ~= "table" then config.features = {} end
                    config.features.browser_cover_mosaic_uniform =
                        not (config.features.browser_cover_mosaic_uniform == true)
                    plugin:saveConfig()
                    settings_apply.prompt_restart()
                end,
            },
            {
                text = _("Show progress % on mosaic covers"),
                checked_func = function()
                    return type(config.browser_cover_badges) == "table"
                        and config.browser_cover_badges.show_mosaic_progress == true
                end,
                callback = function()
                    if type(config.browser_cover_badges) ~= "table" then
                        config.browser_cover_badges = {}
                    end
                    config.browser_cover_badges.show_mosaic_progress =
                        not (config.browser_cover_badges.show_mosaic_progress == true)
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Show KOReader progress bar"),
                checked_func = function()
                    return type(config.browser_cover_badges) == "table"
                        and config.browser_cover_badges.show_native_progress_bar == true
                end,
                callback = function()
                    if type(config.browser_cover_badges) ~= "table" then
                        config.browser_cover_badges = {}
                    end
                    config.browser_cover_badges.show_native_progress_bar =
                        not (config.browser_cover_badges.show_native_progress_bar == true)
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Show page count"),
                checked_func = function()
                    return type(config.browser_page_count) == "table"
                        and config.browser_page_count.show_page_count == true
                end,
                callback = function()
                    if type(config.browser_page_count) ~= "table" then
                        config.browser_page_count = {}
                    end
                    config.browser_page_count.show_page_count =
                        not (config.browser_page_count.show_page_count == true)
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Show series number on covers"),
                checked_func = function()
                    return type(config.browser_series_badge) == "table"
                        and config.browser_series_badge.show_series_badge == true
                end,
                callback = function()
                    if type(config.browser_series_badge) ~= "table" then
                        config.browser_series_badge = {}
                    end
                    config.browser_series_badge.show_series_badge =
                        not (config.browser_series_badge.show_series_badge == true)
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Show favorite badge"),
                checked_func = function()
                    return type(config.browser_cover_badges) == "table"
                        and config.browser_cover_badges.show_favorite_badge == true
                end,
                callback = function()
                    if type(config.browser_cover_badges) ~= "table" then
                        config.browser_cover_badges = {}
                    end
                    config.browser_cover_badges.show_favorite_badge =
                        not (config.browser_cover_badges.show_favorite_badge == true)
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Show new banner"),
                checked_func = function()
                    return type(config.browser_cover_badges) == "table"
                        and config.browser_cover_badges.show_new_banner == true
                end,
                callback = function()
                    if type(config.browser_cover_badges) ~= "table" then
                        config.browser_cover_badges = {}
                    end
                    config.browser_cover_badges.show_new_banner =
                        not (config.browser_cover_badges.show_new_banner == true)
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
        },
    })

    -- -------------------------------------------------------------------------
    -- Display mode
    -- -------------------------------------------------------------------------

    local display_modes = {
        { text = _("Classic (filename only)"),                          mode = "classic"             },
        { text = _("Mosaic with cover images"),                         mode = "mosaic_image"        },
        { text = _("Mosaic with text"),                                 mode = "mosaic_text"         },
        { text = _("Detailed list with cover images and metadata"),     mode = "list_image_meta"     },
        { text = _("Detailed list with metadata, no images"),           mode = "list_only_meta"      },
        { text = _("Detailed list with cover images and filenames"),    mode = "list_image_filename" },
    }

    local function get_display_mode()
        local ok, BookInfoManager = pcall(require, "bookinfomanager")
        if not ok then return "classic" end
        local ok2, mode = pcall(function() return BookInfoManager:getSetting("filemanager_display_mode") end)
        return (ok2 and mode) or "classic"
    end

    local function apply_display_mode(mode)
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and FileManager and FileManager.instance
        if fm and type(fm.onSetDisplayMode) == "function" then
            pcall(fm.onSetDisplayMode, fm, mode ~= "classic" and mode or nil)
        else
            local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
            if ok_bim then
                pcall(BookInfoManager.saveSetting, BookInfoManager,
                    "filemanager_display_mode", mode ~= "classic" and mode or nil)
            end
        end
    end

    local display_mode_sub_items = {}
    for _, entry in ipairs(display_modes) do
        table.insert(display_mode_sub_items, {
            text = entry.text,
            checked_func = function() return get_display_mode() == entry.mode end,
            radio = true,
            callback = function() apply_display_mode(entry.mode) end,
        })
    end

    table.insert(items, {
        text = _("Display mode"),
        sub_item_table = display_mode_sub_items,
    })

    -- -------------------------------------------------------------------------
    -- Items per page
    -- -------------------------------------------------------------------------

    do
        local function get_bim()
            local ok, bim = pcall(require, "bookinfomanager")
            return ok and bim or nil
        end
        local function get_fc_class()
            local ok, fc_cls = pcall(require, "ui/widget/filechooser")
            return ok and fc_cls or nil
        end
        local function get_fc()
            local ok, FM = pcall(require, "apps/filemanager/filemanager")
            local fm = ok and FM and FM.instance
            return fm and fm.file_chooser or nil
        end

        table.insert(items, {
            text = _("Items per page"),
            sub_item_table = {
                {
                    text_func = function()
                        local bim = get_bim()
                        local fc = get_fc()
                        local c = (fc and fc.nb_cols_portrait) or (bim and bim:getSetting("nb_cols_portrait")) or 3
                        local r = (fc and fc.nb_rows_portrait) or (bim and bim:getSetting("nb_rows_portrait")) or 3
                        return _("Portrait mosaic: ") .. c .. "x" .. r
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local bim = get_bim()
                        if not bim then return end
                        local fc = get_fc()
                        local c = (fc and fc.nb_cols_portrait) or bim:getSetting("nb_cols_portrait") or 3
                        local r = (fc and fc.nb_rows_portrait) or bim:getSetting("nb_rows_portrait") or 3
                        UIManager:show(require("ui/widget/doublespinwidget"):new{
                            title_text = _("Portrait mosaic mode"),
                            width_factor = 0.6,
                            left_text = _("Columns"),
                            left_value = c,
                            left_min = 2, left_max = 8, left_default = 3, left_precision = "%01d",
                            right_text = _("Rows"),
                            right_value = r,
                            right_min = 2, right_max = 8, right_default = 3, right_precision = "%01d",
                            keep_shown_on_apply = true,
                            callback = function(left_value, right_value)
                                if fc then
                                    fc.nb_cols_portrait = left_value
                                    fc.nb_rows_portrait = right_value
                                    if fc.display_mode_type == "mosaic" and fc.portrait_mode then
                                        fc.no_refresh_covers = true
                                        pcall(fc.updateItems, fc)
                                    end
                                end
                            end,
                            close_callback = function()
                                if fc then
                                    bim:saveSetting("nb_cols_portrait", fc.nb_cols_portrait)
                                    bim:saveSetting("nb_rows_portrait", fc.nb_rows_portrait)
                                    local fc_class = get_fc_class()
                                    if fc_class then
                                        fc_class.nb_cols_portrait = fc.nb_cols_portrait
                                        fc_class.nb_rows_portrait = fc.nb_rows_portrait
                                    end
                                    if fc.display_mode_type == "mosaic" and fc.portrait_mode then
                                        fc.no_refresh_covers = nil
                                        pcall(fc.updateItems, fc)
                                    end
                                end
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        })
                    end,
                },
                {
                    text_func = function()
                        local bim = get_bim()
                        local fc = get_fc()
                        local c = (fc and fc.nb_cols_landscape) or (bim and bim:getSetting("nb_cols_landscape")) or 4
                        local r = (fc and fc.nb_rows_landscape) or (bim and bim:getSetting("nb_rows_landscape")) or 2
                        return _("Landscape mosaic: ") .. c .. "x" .. r
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local bim = get_bim()
                        if not bim then return end
                        local fc = get_fc()
                        local c = (fc and fc.nb_cols_landscape) or bim:getSetting("nb_cols_landscape") or 4
                        local r = (fc and fc.nb_rows_landscape) or bim:getSetting("nb_rows_landscape") or 2
                        UIManager:show(require("ui/widget/doublespinwidget"):new{
                            title_text = _("Landscape mosaic mode"),
                            width_factor = 0.6,
                            left_text = _("Columns"),
                            left_value = c,
                            left_min = 2, left_max = 8, left_default = 4, left_precision = "%01d",
                            right_text = _("Rows"),
                            right_value = r,
                            right_min = 2, right_max = 8, right_default = 2, right_precision = "%01d",
                            keep_shown_on_apply = true,
                            callback = function(left_value, right_value)
                                if fc then
                                    fc.nb_cols_landscape = left_value
                                    fc.nb_rows_landscape = right_value
                                    if fc.display_mode_type == "mosaic" and not fc.portrait_mode then
                                        fc.no_refresh_covers = true
                                        pcall(fc.updateItems, fc)
                                    end
                                end
                            end,
                            close_callback = function()
                                if fc then
                                    bim:saveSetting("nb_cols_landscape", fc.nb_cols_landscape)
                                    bim:saveSetting("nb_rows_landscape", fc.nb_rows_landscape)
                                    local fc_class = get_fc_class()
                                    if fc_class then
                                        fc_class.nb_cols_landscape = fc.nb_cols_landscape
                                        fc_class.nb_rows_landscape = fc.nb_rows_landscape
                                    end
                                    if fc.display_mode_type == "mosaic" and not fc.portrait_mode then
                                        fc.no_refresh_covers = nil
                                        pcall(fc.updateItems, fc)
                                    end
                                end
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        })
                    end,
                },
                {
                    text_func = function()
                        local bim = get_bim()
                        local fc = get_fc()
                        local fpp = (fc and fc.files_per_page) or (bim and bim:getSetting("files_per_page")) or 10
                        return _("List: ") .. tostring(fpp) .. " " .. _("items per page")
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
                        local bim = get_bim()
                        if not bim then return end
                        local fc = get_fc()
                        local fpp = (fc and fc.files_per_page) or bim:getSetting("files_per_page") or 10
                        UIManager:show(require("ui/widget/spinwidget"):new{
                            title_text = _("Portrait list mode"),
                            value = fpp,
                            value_min = 4,
                            value_max = 20,
                            default_value = 10,
                            keep_shown_on_apply = true,
                            callback = function(spin)
                                if fc then
                                    fc.files_per_page = spin.value
                                    if fc.display_mode_type == "list" then
                                        fc.no_refresh_covers = true
                                        pcall(fc.updateItems, fc)
                                    end
                                end
                            end,
                            close_callback = function()
                                if fc then
                                    bim:saveSetting("files_per_page", fc.files_per_page)
                                    local fc_class = get_fc_class()
                                    if fc_class then
                                        fc_class.files_per_page = fc.files_per_page
                                    end
                                    if fc.display_mode_type == "list" then
                                        fc.no_refresh_covers = nil
                                        pcall(fc.updateItems, fc)
                                    end
                                end
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        })
                    end,
                },
            },
        })
    end

    -- -------------------------------------------------------------------------
    -- Sort by
    -- -------------------------------------------------------------------------

    local collate_options = {
        { key = "strcoll",                text = _("name")                                          },
        { key = "natural",                text = _("name (natural sorting)")                        },
        { key = "access",                 text = _("last read date")                                },
        { key = "date",                   text = _("date modified")                                 },
        { key = "size",                   text = _("size")                                          },
        { key = "type",                   text = _("type")                                          },
        { key = "percent_unopened_first", text = _("percent - unopened first")                      },
        { key = "percent_unopened_last",  text = _("percent - unopened last")                       },
        { key = "percent_natural",        text = _("percent - unopened - finished last")            },
        { key = "title",                  text = _("Title")                                         },
        { key = "authors",                text = _("Authors")                                       },
        { key = "series",                 text = _("Series")                                        },
        { key = "keywords",               text = _("Keywords"),        separator = true             },
    }

    local function get_current_collate()
        return G_reader_settings:readSetting("collate") or "strcoll"
    end

    local function apply_sort_by(collate_id)
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and FileManager and FileManager.instance
        if fm then
            if type(fm.onSetSortBy) == "function" then
                pcall(fm.onSetSortBy, fm, collate_id)
            elseif fm.file_chooser and type(fm.file_chooser.refreshPath) == "function" then
                G_reader_settings:saveSetting("collate", collate_id)
                pcall(fm.file_chooser.refreshPath, fm.file_chooser)
            else
                G_reader_settings:saveSetting("collate", collate_id)
            end
        else
            G_reader_settings:saveSetting("collate", collate_id)
        end
    end

    local function refresh_filechooser()
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and FileManager and FileManager.instance
        if fm and fm.file_chooser and type(fm.file_chooser.refreshPath) == "function" then
            pcall(fm.file_chooser.refreshPath, fm.file_chooser)
        end
    end

    local collate_sub_items = {}
    for _, option in ipairs(collate_options) do
        table.insert(collate_sub_items, {
            text = option.text,
            checked_func = function() return get_current_collate() == option.key end,
            radio = true,
            callback = function() apply_sort_by(option.key) end,
        })
    end
    table.insert(collate_sub_items, {
        text = _("Reverse sorting"),
        checked_func = function() return G_reader_settings:isTrue("reverse_collate") end,
        callback = function()
            G_reader_settings:flipNilOrFalse("reverse_collate")
            refresh_filechooser()
        end,
    })
    table.insert(collate_sub_items, {
        text = _("Folders and files mixed"),
        checked_func = function() return G_reader_settings:isTrue("collate_mixed") end,
        callback = function()
            G_reader_settings:flipNilOrFalse("collate_mixed")
            refresh_filechooser()
        end,
    })

    table.insert(items, {
        text = _("Sort by"),
        text_func = function()
            local collate = get_current_collate()
            for _i, option in ipairs(collate_options) do
                if option.key == collate then
                    return _("Sort by: ") .. option.text
                end
            end
            return _("Sort by")
        end,
        sub_item_table = collate_sub_items,
    })

    -- -------------------------------------------------------------------------
    -- Scroll bar style
    -- -------------------------------------------------------------------------

    local scroll_bar_styles = {
        { text = _("Bar"),  style = "bar"  },
        { text = _("Dots"), style = "dots" },
    }

    local function get_scroll_bar_style()
        return (type(config.zen_scroll_bar) == "table" and config.zen_scroll_bar.style) or "bar"
    end

    local scroll_bar_sub_items = {}
    for _, entry in ipairs(scroll_bar_styles) do
        table.insert(scroll_bar_sub_items, {
            text = entry.text,
            checked_func = function() return get_scroll_bar_style() == entry.style end,
            radio = true,
            callback = function()
                if type(config.zen_scroll_bar) ~= "table" then config.zen_scroll_bar = {} end
                config.zen_scroll_bar.style = entry.style
                plugin:saveConfig()
                UIManager:setDirty(nil, "ui")
            end,
        })
    end

    table.insert(items, {
        text = _("Scroll bar style"),
        sub_item_table = scroll_bar_sub_items,
    })

    table.insert(items, {
        text = _("Hide finished books"),
        checked_func = function()
            return type(config.browser_hide_finished) == "table"
                and config.browser_hide_finished.hide_finished == true
        end,
        callback = function()
            if type(config.browser_hide_finished) ~= "table" then
                config.browser_hide_finished = {}
            end
            config.browser_hide_finished.hide_finished =
                not (config.browser_hide_finished.hide_finished == true)
            plugin:saveConfig()
            local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
            local fm = ok and FileManager and FileManager.instance
            if fm and fm.file_chooser and type(fm.file_chooser.refreshPath) == "function" then
                pcall(fm.file_chooser.refreshPath, fm.file_chooser)
            end
        end,
    })

    -- -------------------------------------------------------------------------
    -- Misc toggles
    -- -------------------------------------------------------------------------

    table.insert(items, {
        text = _("Show item underline"),
        checked_func = function()
            return config.features.browser_hide_underline ~= true
        end,
        callback = function()
            config.features.browser_hide_underline = not (config.features.browser_hide_underline == true)
            save_and_apply("browser_hide_underline")
        end,
    })

    table.insert(items, {
        text = _("Hide list borders"),
        checked_func = function()
            return type(config.browser_list_item_layout) == "table"
                and config.browser_list_item_layout.hide_list_borders == true
        end,
        callback = function()
            if type(config.browser_list_item_layout) ~= "table" then
                config.browser_list_item_layout = {}
            end
            config.browser_list_item_layout.hide_list_borders =
                not (config.browser_list_item_layout.hide_list_borders == true)
            plugin:saveConfig()
            UIManager:setDirty(nil, "full")
        end,
    })

    table.insert(items, {
        text = _("Home folder"),
        sub_item_table = {
            {
                text = _("Set home folder"),
                callback = function()
                    local filemanagerutil = require("apps/filemanager/filemanagerutil")
                    local title_header = _("Current home folder:")
                    local current_path = G_reader_settings:readSetting("home_dir")
                    local default_path = filemanagerutil.getDefaultDir()
                    filemanagerutil.showChooseDialog(title_header, function(path)
                        G_reader_settings:saveSetting("home_dir", path)
                        local ok, FM = pcall(require, "apps/filemanager/filemanager")
                        local fm = ok and FM and FM.instance
                        if fm and type(fm.updateTitleBarPath) == "function" then
                            pcall(fm.updateTitleBarPath, fm)
                        end
                    end, current_path, default_path)
                end,
            },
            {
                text = _("Lock home folder"),
                enabled_func = function()
                    return G_reader_settings:has("home_dir")
                end,
                checked_func = function()
                    return G_reader_settings:isTrue("lock_home_folder")
                end,
                callback = function()
                    G_reader_settings:flipNilOrFalse("lock_home_folder")
                    refresh_filechooser()
                end,
            },
        },
    })

    table.insert(items, {
        text = _("Allow delete in context menu"),
        checked_func = function()
            return type(config.context_menu) == "table"
                and config.context_menu.allow_delete == true
        end,
        callback = function()
            if type(config.context_menu) ~= "table" then config.context_menu = {} end
            config.context_menu.allow_delete = not (config.context_menu.allow_delete == true)
            plugin:saveConfig()
        end,
    })

    return items
end

return M

-- settings/sections/library_settings.lua
-- Library (filebrowser) settings items for Zen UI.
-- Receives ctx: { plugin, config, save_and_apply, apply_feature }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local paths = require("common/paths")

local status_bar_section  = require("modules/settings/sections/library_settings/status_bar_settings")
local settings_apply      = require("modules/settings/zen_settings_apply")
local zen_settings_utils  = require("modules/settings/zen_settings_utils")

local M = {}

local function ensure_library_font_cfg(config)
    if type(config.library_font) ~= "table" then
        config.library_font = {}
    end
    if type(config.library_font.font_face) ~= "string" or config.library_font.font_face == "" then
        config.library_font.font_face = "default"
    end
    local font_size = tonumber(config.library_font.font_size)
    if not font_size then
        config.library_font.font_size = 18
    else
        config.library_font.font_size = math.max(10, math.min(40, math.floor(font_size + 0.5)))
    end
    return config.library_font
end

local function save_library_font(config, plugin, touchmenu_instance)
    _G.__ZEN_UI_LIBRARY_FONT_CFG = config.library_font
    plugin:saveConfig()
    settings_apply.reinit_filemanager()
    local strip_cfg = type(config.mosaic_title_strip) == "table" and config.mosaic_title_strip or nil
    if strip_cfg and (strip_cfg.show_title == true or strip_cfg.show_author == true) then
        settings_apply.prompt_restart()
    end
    if touchmenu_instance then
        touchmenu_instance:updateItems()
    end
end

function M.build(ctx)
    local config        = ctx.config
    local plugin        = ctx.plugin
    local save_and_apply = ctx.save_and_apply

    local function fbc()
        if type(config.browser_folder_cover) ~= "table" then
            config.browser_folder_cover = {}
        end
        return config.browser_folder_cover
    end
    local function save_fbc()
        plugin:saveConfig()
        UIManager:setDirty(nil, "full")
    end
    local function save_fbc_and_update()
        plugin:saveConfig()
        local ui = require("apps/filemanager/filemanager").instance
        if ui and ui.file_chooser then ui.file_chooser:updateItems() end
    end

    local items = {}

    table.insert(items, status_bar_section.build(ctx))

    table.insert(items, {
        text_func = function()
            local cfg = ensure_library_font_cfg(config)
            local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
            local face_text = (cfg.font_face == "default") and _("default")
                or (ok_fc and FontChooser.getFontNameText(cfg.font_face) or cfg.font_face)
            return string.format("%s %s, %s", _("Font:"), face_text, tostring(cfg.font_size))
        end,
        sub_item_table = {
            {
                text_func = function()
                    local cfg = ensure_library_font_cfg(config)
                    return string.format("%s %s", _("Font size:"), tostring(cfg.font_size))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local cfg = ensure_library_font_cfg(config)
                    UIManager:show(SpinWidget:new{
                        title_text = _("Library font size"),
                        value = cfg.font_size,
                        value_min = 10,
                        value_max = 40,
                        default_value = 18,
                        callback = function(spin)
                            cfg.font_size = math.max(10, math.min(40, spin.value))
                            save_library_font(config, plugin, touchmenu_instance)
                        end,
                    })
                end,
            },
            {
                text_func = function()
                    local cfg = ensure_library_font_cfg(config)
                    local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
                    local face_text = (cfg.font_face == "default") and _("default")
                        or (ok_fc and FontChooser.getFontNameText(cfg.font_face) or cfg.font_face)
                    return string.format("%s %s", _("Font:"), face_text)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
                    if not ok_fc then return end
                    local cfg = ensure_library_font_cfg(config)
                    local footer_settings = G_reader_settings:readSetting("footer") or {}
                    local fallback_face = footer_settings.text_font_face or "NotoSans-Regular.ttf"
                    local display_face = cfg.font_face == "default" and fallback_face or cfg.font_face
                    UIManager:show(FontChooser:new{
                        title = _("Library font"),
                        font_file = display_face,
                        default_font_file = fallback_face,
                        callback = function(file)
                            if cfg.font_face ~= file then
                                cfg.font_face = file
                                save_library_font(config, plugin, touchmenu_instance)
                            end
                        end,
                    })
                end,
                hold_callback = function(touchmenu_instance)
                    local cfg = ensure_library_font_cfg(config)
                    if cfg.font_face ~= "default" then
                        cfg.font_face = "default"
                        save_library_font(config, plugin, touchmenu_instance)
                    end
                end,
            },
            {
                text = _("Use default font"),
                callback = function(touchmenu_instance)
                    local cfg = ensure_library_font_cfg(config)
                    cfg.font_face = "default"
                    save_library_font(config, plugin, touchmenu_instance)
                end,
            },
        },
    })

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
                        config.browser_hide_up_folder.hide_up_folder ~= true
                    save_and_apply("browser_hide_up_folder")
                end,
            },
            -- Cover mode subsection
            {
                text = _("Covers"),
                sub_item_table = {
                    {
                        text = _("Gallery"),
                        radio = true,
                        checked_func = function() return fbc().cover_mode == "gallery" end,
                        callback = function()
                            fbc().cover_mode = "gallery"
                            save_fbc_and_update()
                        end,
                    },
                    {
                        text = _("First cover image"),
                        radio = true,
                        checked_func = function() return fbc().cover_mode == "normal" end,
                        callback = function()
                            fbc().cover_mode = "normal"
                            save_fbc_and_update()
                        end,
                    },
                    {
                        text = _("Stack"),
                        radio = true,
                        checked_func = function() return fbc().cover_mode == "stack" end,
                        callback = function()
                            fbc().cover_mode = "stack"
                            save_fbc_and_update()
                        end,
                    },
                    {
                        text = _("None (folder name only)"),
                        radio = true,
                        checked_func = function() return fbc().cover_mode == "none" end,
                        callback = function()
                            fbc().cover_mode = "none"
                            save_fbc_and_update()
                        end,
                    },
                    {
                        text = _("Show spine lines"),
                        checked_func = function() return fbc().show_spine_lines ~= false end,
                        callback = function()
                            fbc().show_spine_lines = fbc().show_spine_lines == false
                            save_fbc()
                        end,
                    },
                    {
                        text = _("Show item count"),
                        checked_func = function() return fbc().show_item_count ~= false end,
                        callback = function()
                            fbc().show_item_count = fbc().show_item_count == false
                            save_fbc()
                        end,
                    },
                },
            },
            -- Folder name subsection
            {
                text = _("Folder name"),
                sub_item_table = {
                    {
                        text = _("Opaque background"),
                        checked_func = function() return fbc().name_opaque == true end,
                        callback = function()
                            fbc().name_opaque = fbc().name_opaque ~= true
                            save_fbc()
                        end,
                    },
                    {
                        text = _("Folder name position"),
                        sub_item_table = {
                            {
                                text = _("Center"),
                                radio = true,
                                checked_func = function() return fbc().name_centered == true end,
                                callback = function()
                                    fbc().name_centered = true
                                    save_fbc()
                                end,
                            },
                            {
                                text = _("Bottom"),
                                radio = true,
                                checked_func = function() return fbc().name_centered ~= true end,
                                callback = function()
                                    fbc().name_centered = false
                                    save_fbc()
                                end,
                            },
                        },
                    },
                    {
                        text = _("Show folder name"),
                        checked_func = function() return fbc().show_folder_name ~= false end,
                        callback = function()
                            fbc().show_folder_name = fbc().show_folder_name == false
                            save_fbc()
                        end,
                    },
                },
            },
        },
    })

    table.insert(items, {
        text = _("Covers"),
        sub_item_table = {
            {
                text = _("Badges"),
                sub_item_table = {
                    {
                        text = _("Badge size"),
                        sub_item_table = (function()
                            local sizes = {
                                { label = _("Compact"),     value = "compact"     },
                                { label = _("Normal"),      value = "normal"      },
                                { label = _("Large"),       value = "large"       },
                                { label = _("Extra large"), value = "extra_large" },
                            }
                            local badge_size_items = {}
                            for _i, sz in ipairs(sizes) do
                                local v = sz.value
                                table.insert(badge_size_items, {
                                    text = sz.label,
                                    radio = true,
                                    checked_func = function()
                                        local cur = type(config.browser_cover_badges) == "table"
                                            and config.browser_cover_badges.badge_size
                                        return (cur or "compact") == v
                                    end,
                                    callback = function()
                                        if type(config.browser_cover_badges) ~= "table" then
                                            config.browser_cover_badges = {}
                                        end
                                        config.browser_cover_badges.badge_size = v
                                        plugin:saveConfig()
                                        UIManager:setDirty(nil, "full")
                                    end,
                                })
                            end
                            return badge_size_items
                        end)(),
                    },
                    zen_settings_utils.buildColorSubMenu({
                        label        = _("Badge color: "),
                        get          = function()
                            local c = type(config.browser_cover_badges) == "table"
                                and config.browser_cover_badges.badge_color
                            return type(c) == "table" and c or nil
                        end,
                        set          = function(r, g, b)
                            if type(config.browser_cover_badges) ~= "table" then
                                config.browser_cover_badges = {}
                            end
                            config.browser_cover_badges.badge_color = { r, g, b }
                            plugin:saveConfig()
                            UIManager:setDirty(nil, "full")
                        end,
                        reset        = function()
                            if type(config.browser_cover_badges) == "table" then
                                config.browser_cover_badges.badge_color = nil
                            end
                            plugin:saveConfig()
                            UIManager:setDirty(nil, "full")
                        end,
                        default_text = _("Default"),
                        reset_text   = _("Default (black)"),
                        dialog_title = _("Badge color RGB"),
                        presets = {
                            { text = _("Black"), r = 0,    g = 0,    b = 0    },
                            { text = _("White"), r = 255,  g = 255,  b = 255  },
                            { text = _("Gray"),  r = 204,  g = 204,  b = 204  },
                            { text = _("Blue"),  r = 0x99, g = 0xBB, b = 0xF0 },
                            { text = _("Green"), r = 0x99, g = 0xCC, b = 0x99 },
                            { text = _("Amber"), r = 0xF0, g = 0xD0, b = 0x80 },
                            { text = _("Red"),   r = 0xDD, g = 0x99, b = 0x99 },
                        },
                    }),
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
                                config.browser_page_count.show_page_count ~= true
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
                                config.browser_series_badge.show_series_badge ~= true
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
                                config.browser_cover_badges.show_favorite_badge ~= true
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
                                config.browser_cover_badges.show_new_banner ~= true
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
                                config.browser_cover_badges.show_native_progress_bar ~= true
                            plugin:saveConfig()
                            UIManager:setDirty(nil, "full")
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
                                config.browser_cover_badges.show_mosaic_progress ~= true
                            plugin:saveConfig()
                            UIManager:setDirty(nil, "full")
                        end,
                    },
                },
            },
            {
                text = _("Uniform covers"),
                sub_item_table = {
                    {
                        text = _("Uniform covers"),
                        checked_func = function()
                            return type(config.features) == "table"
                                and config.features.browser_cover_mosaic_uniform == true
                        end,
                        callback = function()
                            if type(config.features) ~= "table" then config.features = {} end
                            config.features.browser_cover_mosaic_uniform =
                                config.features.browser_cover_mosaic_uniform ~= true
                            plugin:saveConfig()
                            settings_apply.prompt_restart()
                        end,
                    },
                    {
                        text = "2:3 " .. _("(standard)"),
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting("uniform_cover_ratio") ~= "3:4"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("uniform_cover_ratio", "2:3")
                            local ui = require("apps/filemanager/filemanager").instance
                            if ui and ui.file_chooser then ui.file_chooser:updateItems() end
                        end,
                    },
                    {
                        text = "3:4 " .. _("(Kindle)"),
                        radio = true,
                        checked_func = function()
                            return G_reader_settings:readSetting("uniform_cover_ratio") == "3:4"
                        end,
                        callback = function()
                            G_reader_settings:saveSetting("uniform_cover_ratio", "3:4")
                            local ui = require("apps/filemanager/filemanager").instance
                            if ui and ui.file_chooser then ui.file_chooser:updateItems() end
                        end,
                    },
                },
            },
            {
                text = _("Dim finished books"),
                checked_func = function()
                    return type(config.browser_cover_badges) == "table"
                        and config.browser_cover_badges.dim_finished_books == true
                end,
                callback = function()
                    if type(config.browser_cover_badges) ~= "table" then
                        config.browser_cover_badges = {}
                    end
                    config.browser_cover_badges.dim_finished_books =
                        config.browser_cover_badges.dim_finished_books ~= true
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Rounded cover corners"),
                checked_func = function()
                    return type(config.features) == "table"
                        and config.features.browser_cover_rounded_corners == true
                end,
                callback = function()
                    if type(config.features) ~= "table" then config.features = {} end
                    config.features.browser_cover_rounded_corners =
                        config.features.browser_cover_rounded_corners ~= true
                    plugin:saveConfig()
                    UIManager:setDirty(nil, "full")
                end,
            },
            {
                text = _("Show title below cover (mosaic)"),
                checked_func = function()
                    return type(config.mosaic_title_strip) == "table"
                        and config.mosaic_title_strip.show_title == true
                end,
                callback = function()
                    if type(config.mosaic_title_strip) ~= "table" then
                        config.mosaic_title_strip = {}
                    end
                    config.mosaic_title_strip.show_title =
                        config.mosaic_title_strip.show_title ~= true
                    plugin:saveConfig()
                    settings_apply.prompt_restart()
                end,
            },
            {
                text = _("Show author below cover (mosaic)"),
                checked_func = function()
                    return type(config.mosaic_title_strip) == "table"
                        and config.mosaic_title_strip.show_author == true
                end,
                callback = function()
                    if type(config.mosaic_title_strip) ~= "table" then
                        config.mosaic_title_strip = {}
                    end
                    config.mosaic_title_strip.show_author =
                        config.mosaic_title_strip.show_author ~= true
                    plugin:saveConfig()
                    settings_apply.prompt_restart()
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
        { text = _("Bar"),         style = "bar"         },
        { text = _("Dots"),        style = "dots"        },
        { text = _("Page number"), style = "page_number" },
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
                -- Footer height differs between page_number and other styles;
                -- reinit rebuilds the menu with the correct height and touch zones.
                settings_apply.reinit_filemanager()
            end,
        })
    end

    -- Page number format sub-menu (nested inside scroll bar style, greyed out unless page_number)
    local pn_formats = {
        { text = _("Current only"), fmt = "current" },
        { text = _("Page x / y"),   fmt = "total"   },
    }
    local function get_pn_format()
        return (type(config.zen_scroll_bar) == "table"
            and config.zen_scroll_bar.page_number_format) or "current"
    end
    local pn_format_sub_items = {}
    for _, entry in ipairs(pn_formats) do
        table.insert(pn_format_sub_items, {
            text = entry.text,
            checked_func = function() return get_pn_format() == entry.fmt end,
            radio = true,
            callback = function()
                if type(config.zen_scroll_bar) ~= "table" then config.zen_scroll_bar = {} end
                config.zen_scroll_bar.page_number_format = entry.fmt
                plugin:saveConfig()
                UIManager:setDirty(nil, "ui")
            end,
        })
    end
    table.insert(scroll_bar_sub_items, {
        text           = _("Page number format"),
        enabled_func   = function() return get_scroll_bar_style() == "page_number" end,
        sub_item_table = pn_format_sub_items,
        separator      = true,  -- visual break after the radio style entries
    })

    -- Hold-to-skip sub-menu (nested inside scroll bar style, greyed out unless page_number)
    local hold_skip_opts = {
        { text = _("Skip 10 pages"),   skip = "10"   },
        { text = _("Skip 20 pages"),   skip = "20"   },
        { text = _("Beginning / End"), skip = "ends" },
    }
    local function get_hold_skip()
        return (type(config.zen_scroll_bar) == "table"
            and config.zen_scroll_bar.hold_skip) or "10"
    end
    local hold_skip_sub_items = {}
    for _, entry in ipairs(hold_skip_opts) do
        table.insert(hold_skip_sub_items, {
            text = entry.text,
            checked_func = function() return get_hold_skip() == entry.skip end,
            radio = true,
            callback = function()
                if type(config.zen_scroll_bar) ~= "table" then config.zen_scroll_bar = {} end
                config.zen_scroll_bar.hold_skip = entry.skip
                plugin:saveConfig()
                UIManager:setDirty(nil, "ui")
            end,
        })
    end
    table.insert(scroll_bar_sub_items, {
        text           = _("Hold to skip"),
        enabled_func   = function() return get_scroll_bar_style() == "page_number" end,
        sub_item_table = hold_skip_sub_items,
    })

    table.insert(items, {
        text = _("Scroll bar style"),
        sub_item_table = scroll_bar_sub_items,
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
            config.features.browser_hide_underline = config.features.browser_hide_underline ~= true
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
                config.browser_list_item_layout.hide_list_borders ~= true
            plugin:saveConfig()
            -- updateItems rebuilds item_group so stripListBorders takes effect immediately.
            local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
            local fm = ok_fm and FM and FM.instance
            if fm and fm.file_chooser and fm.file_chooser.updateItems then
                fm.file_chooser:updateItems()
                UIManager:setDirty(fm, "ui")
            else
                UIManager:setDirty(nil, "full")
            end
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
                    local current_path = paths.getHomeDir()
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
            {
                text = _("Additional home folders"),
                sub_item_table_func = function()
                    local dirs = type(config.additional_home_dirs) == "table"
                        and config.additional_home_dirs or {}
                    local sub = {}
                    table.insert(sub, {
                        text = _("Add folder…"),
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local PathChooser = require("ui/widget/pathchooser")
                            local start_path = paths.getHomeDir()
                                or G_reader_settings:readSetting("lastdir") or "/"
                            UIManager:show(PathChooser:new{
                                select_file = false,
                                show_files  = false,
                                path        = start_path,
                                onConfirm   = function(dir_path)
                                    if type(config.additional_home_dirs) ~= "table" then
                                        config.additional_home_dirs = {}
                                    end
                                    for _, existing in ipairs(config.additional_home_dirs) do
                                        if existing == dir_path then return end
                                    end
                                    table.insert(config.additional_home_dirs, dir_path)
                                    plugin:saveConfig()
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            })
                        end,
                    })
                    for i, dir in ipairs(dirs) do
                        local util = require("util")
                        local name = select(2, util.splitFilePathName(dir))
                        table.insert(sub, {
                            text = name ~= "" and name or dir,
                            keep_menu_open = true,
                            callback = function(touchmenu_instance)
                                local ConfirmBox = require("ui/widget/confirmbox")
                                UIManager:show(ConfirmBox:new{
                                    text = _("Remove this folder from additional home folders?") .. "\n" .. dir,
                                    ok_text = _("Remove"),
                                    ok_callback = function()
                                        table.remove(config.additional_home_dirs, i)
                                        plugin:saveConfig()
                                        if touchmenu_instance then
                                            touchmenu_instance:updateItems()
                                        end
                                    end,
                                })
                            end,
                        })
                    end
                    return sub
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
            config.context_menu.allow_delete = config.context_menu.allow_delete ~= true
            plugin:saveConfig()
        end,
    })

    return items
end

return M

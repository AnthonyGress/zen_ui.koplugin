-- settings/sections/reader.lua
-- Reader settings items for Zen UI (clock, presets, fonts, footer).
-- Receives ctx: { plugin, config, save_and_apply }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local utils = require("settings/zen_settings_utils")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local plugin = ctx.plugin
    local save_and_apply = ctx.save_and_apply

    local function make_enable_feature_item(feature, text)
        return utils.make_enable_feature_item(feature, text, config, save_and_apply)
    end

    local items = {}

    -- -------------------------------------------------------------------------
    -- Reader clock
    -- -------------------------------------------------------------------------

    table.insert(items, {
        text = _("Reader clock"),
        sub_item_table = {
            make_enable_feature_item("reader_clock", _("Enable reader clock")),
            {
                text = _("Position"),
                sub_item_table = {
                    {
                        text = _("Left"),
                        checked_func = function()
                            local pos = config.reader_clock and config.reader_clock.position
                            return pos == "left"
                        end,
                        callback = function()
                            if type(config.reader_clock) ~= "table" then config.reader_clock = {} end
                            config.reader_clock.position = "left"
                            save_and_apply("reader_clock")
                        end,
                    },
                    {
                        text = _("Center"),
                        checked_func = function()
                            local pos = config.reader_clock and config.reader_clock.position
                            return pos == nil or pos == "center"
                        end,
                        callback = function()
                            if type(config.reader_clock) ~= "table" then config.reader_clock = {} end
                            config.reader_clock.position = "center"
                            save_and_apply("reader_clock")
                        end,
                    },
                    {
                        text = _("Right"),
                        checked_func = function()
                            local pos = config.reader_clock and config.reader_clock.position
                            return pos == "right"
                        end,
                        callback = function()
                            if type(config.reader_clock) ~= "table" then config.reader_clock = {} end
                            config.reader_clock.position = "right"
                            save_and_apply("reader_clock")
                        end,
                    },
                },
            },
            {
                text_func = function()
                    local FontChooser = require("ui/widget/fontchooser")
                    local face = config.reader_clock and config.reader_clock.font_face
                    local text = (not face or face == "default")
                        and _("default") or FontChooser.getFontNameText(face)
                    local size = config.reader_clock and config.reader_clock.font_size or 14
                    return string.format("%s %s, %s", _("Font:"), text, size)
                end,
                sub_item_table = {
                    {
                        text_func = function()
                            local size = config.reader_clock and config.reader_clock.font_size or 14
                            return string.format("%s %s", _("Font size:"), size)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            UIManager:show(SpinWidget:new{
                                title_text = _("Font size"),
                                value = config.reader_clock and config.reader_clock.font_size or 14,
                                value_min = 8,
                                value_max = 36,
                                default_value = 14,
                                callback = function(spin)
                                    if type(config.reader_clock) ~= "table" then config.reader_clock = {} end
                                    config.reader_clock.font_size = spin.value
                                    save_and_apply("reader_clock")
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            })
                        end,
                    },
                    {
                        text_func = function()
                            local FontChooser = require("ui/widget/fontchooser")
                            local face = config.reader_clock and config.reader_clock.font_face
                            local text = (not face or face == "default")
                                and _("default") or FontChooser.getFontNameText(face)
                            return string.format("%s %s", _("Font:"), text)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local FontChooser = require("ui/widget/fontchooser")
                            local footer_settings = G_reader_settings:readSetting("footer") or {}
                            local footer_font = footer_settings.text_font_face or "NotoSans-Regular.ttf"
                            local current_face = config.reader_clock and config.reader_clock.font_face
                            local display_face = (not current_face or current_face == "default")
                                and footer_font or current_face
                            UIManager:show(FontChooser:new{
                                title = _("Reader clock font"),
                                font_file = display_face,
                                default_font_file = footer_font,
                                callback = function(file)
                                    if type(config.reader_clock) ~= "table" then config.reader_clock = {} end
                                    if config.reader_clock.font_face ~= file then
                                        config.reader_clock.font_face = file
                                        save_and_apply("reader_clock")
                                        if touchmenu_instance then touchmenu_instance:updateItems() end
                                    end
                                end,
                            })
                        end,
                        hold_callback = function(touchmenu_instance)
                            if type(config.reader_clock) ~= "table" then config.reader_clock = {} end
                            if config.reader_clock.font_face ~= "default" then
                                config.reader_clock.font_face = "default"
                                save_and_apply("reader_clock")
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end
                        end,
                    },
                    {
                        text = _("Use default font"),
                        callback = function(touchmenu_instance)
                            if type(config.reader_clock) ~= "table" then config.reader_clock = {} end
                            config.reader_clock.font_face = "default"
                            save_and_apply("reader_clock")
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    },
                },
            },
        },
    })

    -- -------------------------------------------------------------------------
    -- Footer presets
    -- -------------------------------------------------------------------------

    table.insert(items, {
        text = _("Presets"),
        enabled_func = function()
            local ReaderUI = require("apps/reader/readerui")
            return ReaderUI.instance ~= nil
        end,
        sub_item_table_func = function()
            local ReaderUI = require("apps/reader/readerui")
            local ui = ReaderUI.instance
            if not (ui and ui.view and ui.view.footer) then
                return {}
            end
            local function apply_footer_preset(preset)
                local saved_face = ui.view.footer.settings.text_font_face
                local saved_size = ui.view.footer.settings.text_font_size
                local saved_bold = ui.view.footer.settings.text_font_bold
                ui.view.footer:loadPreset(preset)
                ui.view.footer.settings.text_font_face = saved_face
                ui.view.footer.settings.text_font_size = saved_size
                ui.view.footer.settings.text_font_bold = saved_bold
                ui.view.footer:updateFooterFont()
                ui.view.footer:refreshFooter(true, true)
                config.features["reader_clock"] = true
                save_and_apply("reader_clock")
                if ui.rolling then
                    ui.document.configurable.status_line = 1
                    ui:handleEvent(Event:new("SetStatusLine", 1))
                end
                if preset.zen then
                    if type(config.reader_footer) ~= "table" then config.reader_footer = {} end
                    if preset.zen.verbose_chapter_time ~= nil then
                        config.reader_footer.verbose_chapter_time = preset.zen.verbose_chapter_time
                    end
                    plugin:saveConfig()
                end
            end
            local presets_items = {}
            if type(config.reader_footer) == "table" and config.reader_footer.backup_preset then
                local backup = config.reader_footer.backup_preset
                table.insert(presets_items, {
                    text = _(backup.name),
                    callback = function() apply_footer_preset(backup) end,
                    separator = true,
                })
            end
            local footer_presets = require("modules/reader/patches/reader-footer-presets")
            for _i, preset in ipairs(footer_presets) do
                table.insert(presets_items, {
                    text = _(preset.name),
                    callback = function() apply_footer_preset(preset) end,
                })
            end
            return presets_items
        end,
    })

    -- -------------------------------------------------------------------------
    -- Font (passthrough to KOReader's font menu)
    -- -------------------------------------------------------------------------

    table.insert(items, {
        text = _("Font"),
        enabled_func = function()
            local ReaderUI = require("apps/reader/readerui")
            return ReaderUI.instance ~= nil
        end,
        sub_item_table_func = function()
            local ReaderUI = require("apps/reader/readerui")
            local ui = ReaderUI.instance
            if not (ui and ui.font) then return {} end
            local mock = {}
            ui.font:addToMainMenu(mock)
            if not mock.change_font then return {} end
            local entry = mock.change_font
            if entry.sub_item_table_func then
                return entry.sub_item_table_func()
            end
            return entry.sub_item_table or {}
        end,
    })

    -- -------------------------------------------------------------------------
    -- Highlight / Lookup
    -- -------------------------------------------------------------------------

    table.insert(items, {
        text = _("Highlight / Lookup"),
        sub_item_table = {
            make_enable_feature_item("dict_quick_lookup", _("Zen quick lookup")),
            make_enable_feature_item("highlight_lookup", _("Zen highlight menu")),
               {
                text = _("Show Wikipedia"),
                checked_func = function()
                    return type(config.highlight_lookup) == "table"
                        and config.highlight_lookup.show_wikipedia == true
                end,
                callback = function()
                    if type(config.highlight_lookup) ~= "table" then
                        config.highlight_lookup = {}
                    end
                    config.highlight_lookup.show_wikipedia =
                        not (config.highlight_lookup.show_wikipedia == true)
                    plugin:saveConfig()
                end,
            },
            {
                text = _("Show other items"),
                help_text = _("Show other KOReader quick lookup options alongside Zen buttons."),
                checked_func = function()
                    return type(config.highlight_lookup) == "table"
                        and config.highlight_lookup.allow_unknown_items == true
                end,
                callback = function()
                    if type(config.highlight_lookup) ~= "table" then
                        config.highlight_lookup = {}
                    end
                    config.highlight_lookup.allow_unknown_items =
                        not (config.highlight_lookup.allow_unknown_items == true)
                    plugin:saveConfig()
                end,
            },
        },
    })

    table.insert(items, {
        text = _("Verbose time to chapter end"),
        checked_func = function()
            return type(config.reader_footer) == "table"
                and config.reader_footer.verbose_chapter_time == true
        end,
        callback = function()
            if type(config.reader_footer) ~= "table" then
                config.reader_footer = {}
            end
            config.reader_footer.verbose_chapter_time =
                not (config.reader_footer.verbose_chapter_time == true)
            plugin:saveConfig()
        end,
    })

    -- -------------------------------------------------------------------------
    -- Feature toggles
    -- -------------------------------------------------------------------------

    table.insert(items, make_enable_feature_item("reader_bottom_menu", _("Enable bottom menu")))
    table.insert(items, make_enable_feature_item("page_browser", _("Enable page browser")))

    -- -------------------------------------------------------------------------
    -- Bottom status bar (passthrough to KOReader's footer menu)
    -- -------------------------------------------------------------------------

    table.insert(items, {
        text = _("Bottom status bar"),
        enabled_func = function()
            local ReaderUI = require("apps/reader/readerui")
            return ReaderUI.instance ~= nil
        end,
        sub_item_table_func = function()
            local ReaderUI = require("apps/reader/readerui")
            local ui = ReaderUI.instance
            if not (ui and ui.view and ui.view.footer) then
                return {}
            end

            local font_submenu = {
                text = _("Font"),
                sub_item_table = {
                    {
                        text_func = function()
                            local footer_settings = G_reader_settings:readSetting("footer") or {}
                            local size = footer_settings.text_font_size or 14
                            return string.format("%s %s", _("Font size:"), size)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            local footer_settings = G_reader_settings:readSetting("footer") or {}
                            UIManager:show(SpinWidget:new{
                                title_text = _("Font size"),
                                value = footer_settings.text_font_size or 14,
                                value_min = 8,
                                value_max = 36,
                                default_value = 14,
                                callback = function(spin)
                                    ui.view.footer.settings.text_font_size = spin.value
                                    ui.view.footer:updateFooterFont()
                                    ui.view.footer:refreshFooter(true, true)
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            })
                        end,
                    },
                    {
                        text_func = function()
                            local FontChooser = require("ui/widget/fontchooser")
                            local footer_settings = G_reader_settings:readSetting("footer") or {}
                            local face = footer_settings.text_font_face
                            local text = (not face or face == "NotoSans-Regular.ttf")
                                and _("default") or FontChooser.getFontNameText(face)
                            return string.format("%s %s", _("Font:"), text)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local FontChooser = require("ui/widget/fontchooser")
                            local footer_settings = G_reader_settings:readSetting("footer") or {}
                            UIManager:show(FontChooser:new{
                                title = _("Font"),
                                font_file = footer_settings.text_font_face or "NotoSans-Regular.ttf",
                                default_font_file = "NotoSans-Regular.ttf",
                                callback = function(file)
                                    ui.view.footer.settings.text_font_face = file
                                    ui.view.footer:updateFooterFont()
                                    ui.view.footer:refreshFooter(true, true)
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Bold"),
                        checked_func = function()
                            local footer_settings = G_reader_settings:readSetting("footer") or {}
                            return footer_settings.text_font_bold == true
                        end,
                        callback = function()
                            ui.view.footer.settings.text_font_bold = not ui.view.footer.settings.text_font_bold
                            ui.view.footer:updateFooterFont()
                            ui.view.footer:refreshFooter(true, true)
                        end,
                    },
                    {
                        text = _("Use default font"),
                        callback = function(touchmenu_instance)
                            ui.view.footer.settings.text_font_face = "NotoSans-Regular.ttf"
                            ui.view.footer.settings.text_font_size = 14
                            ui.view.footer.settings.text_font_bold = false
                            ui.view.footer:updateFooterFont()
                            ui.view.footer:refreshFooter(true, true)
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    },
                },
            }

            local mock = {}
            ui.view.footer:addToMainMenu(mock)
            local result = {}
            table.insert(result, font_submenu)
            if mock.status_bar and mock.status_bar.sub_item_table then
                for _, item in ipairs(mock.status_bar.sub_item_table) do
                    table.insert(result, item)
                end
            end
            return result
        end,
    })

    return items
end

return M

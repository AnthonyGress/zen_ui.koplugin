-- settings/sections/reader.lua
-- Reader settings items for Zen UI (clock, presets, fonts, footer).
-- Receives ctx: { plugin, config, save_and_apply }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local utils = require("modules/settings/zen_settings_utils")
local constants = require("common/constants")

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
    -- Top status bar
    -- -------------------------------------------------------------------------

    -- Items available in each slot (excludes dynamic fillers / external content)
    local header_all_items = {
        { key = "time",        text = _("Time")          },
        { key = "battery",     text = _("Battery")       },
        { key = "wifi",        text = _("Wi-Fi")         },
        { key = "frontlight",  text = _("Brightness")    },
        { key = "ram",         text = _("RAM usage")     },
        { key = "disk",        text = _("Disk space")    },
        { key = "custom_text", text = _("Custom text")   },
        { key = "book_title",  text = _("Book title")    },
        { key = "author",      text = _("Author")        },
        { key = "chapter",     text = _("Chapter")       },
    }

    local HEADER_CANONICAL = {
        left   = { "time", "custom_text" },
        center = { "time" },
        right  = { "custom_text", "frontlight", "wifi", "battery" },
    }

    local function save_clock() save_and_apply("reader_top_status_bar") end

    local function make_header_slot_items(slot_name, arrange_title)
        local order_key = slot_name .. "_order"
        local canonical = HEADER_CANONICAL[slot_name] or {}
        local canon_pos = {}
        for idx, k in ipairs(canonical) do canon_pos[k] = idx end
        local other_slots = {}
        for _i, s in ipairs({ "left", "center", "right" }) do
            if s ~= slot_name then table.insert(other_slots, s .. "_order") end
        end

        local t = {
            {
                text = _("Show separator"),
                keep_menu_open = true,
                checked_func = function()
                    if type(config.reader_top_status_bar) ~= "table" then return false end
                    return config.reader_top_status_bar[slot_name .. "_show_separator"] == true
                end,
                callback = function(touchmenu_instance)
                    if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                    local key = slot_name .. "_show_separator"
                    config.reader_top_status_bar[key] = config.reader_top_status_bar[key] ~= true
                    save_clock()
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end,
            },
            {
                text = _("Arrange"),
                keep_menu_open = true,
                separator = true,
                callback = function()
                    local SortWidget = require("ui/widget/sortwidget")
                    local lbl = {}
                    for _i, d in ipairs(header_all_items) do lbl[d.key] = d.text end
                    if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                    local cur = config.reader_top_status_bar[order_key] or {}
                    local sort_items = {}
                    for _i, key in ipairs(cur) do
                        if lbl[key] then table.insert(sort_items, { text = lbl[key], orig_item = key }) end
                    end
                    UIManager:show(SortWidget:new{
                        title = arrange_title,
                        item_table = sort_items,
                        callback = function()
                            local new_order = {}
                            for _i, item in ipairs(sort_items) do
                                table.insert(new_order, item.orig_item)
                            end
                            config.reader_top_status_bar[order_key] = new_order
                            save_clock()
                        end,
                    })
                end,
            },
        }

        for _i, def in ipairs(header_all_items) do
            local key = def.key
            table.insert(t, {
                text = def.text,
                keep_menu_open = true,
                enabled_func = function()
                    -- Disable if the key is active in another slot.
                    if type(config.reader_top_status_bar) ~= "table" then return true end
                    for _j, other in ipairs(other_slots) do
                        for _k, k in ipairs(config.reader_top_status_bar[other] or {}) do
                            if k == key then return false end
                        end
                    end
                    return true
                end,
                checked_func = function()
                    if type(config.reader_top_status_bar) ~= "table" then return false end
                    for _j, k in ipairs(config.reader_top_status_bar[order_key] or {}) do
                        if k == key then return true end
                    end
                    return false
                end,
                callback = function(touchmenu_instance)
                    if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                    local this_order = config.reader_top_status_bar[order_key] or {}
                    local found = false
                    local new_this = {}
                    for _j, k in ipairs(this_order) do
                        if k == key then found = true else table.insert(new_this, k) end
                    end
                    if found then
                        config.reader_top_status_bar[order_key] = new_this
                    else
                        -- Remove from any other slot first.
                        for _j, other in ipairs(other_slots) do
                            local new_other = {}
                            for _k, k in ipairs(config.reader_top_status_bar[other] or {}) do
                                if k ~= key then table.insert(new_other, k) end
                            end
                            config.reader_top_status_bar[other] = new_other
                        end
                        -- Insert at canonical position.
                        local new_key_pos = canon_pos[key] or math.huge
                        local insert_at = #this_order + 1
                        for idx, k in ipairs(this_order) do
                            if (canon_pos[k] or math.huge) > new_key_pos then
                                insert_at = idx
                                break
                            end
                        end
                        table.insert(this_order, insert_at, key)
                        config.reader_top_status_bar[order_key] = this_order
                    end
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                    save_clock()
                end,
            })
        end
        return t
    end

    table.insert(items, {
        text = _("Top status bar"),
        sub_item_table = {
            make_enable_feature_item("reader_top_status_bar", _("Enable top status bar")),
            {
                text = _("Left items"),
                sub_item_table = make_header_slot_items("left", _("Arrange left items")),
            },
            {
                text = _("Center items"),
                sub_item_table = make_header_slot_items("center", _("Arrange center items")),
            },
            {
                text = _("Right items"),
                sub_item_table = make_header_slot_items("right", _("Arrange right items")),
            },
            {
                text_func = function()
                    local name = type(config.reader_top_status_bar) == "table" and config.reader_top_status_bar.custom_text or ""
                    local Device = require("device")
                    if name == nil or name == "" then name = Device.model or "" end
                    return _("Custom text: ") .. name
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local InputDialog = require("ui/widget/inputdialog")
                    local Device = require("device")
                    local dlg
                    dlg = InputDialog:new{
                        title = _("Custom text"),
                        input = type(config.reader_top_status_bar) == "table" and config.reader_top_status_bar.custom_text or "",
                        hint = Device.model or "",
                        buttons = {{
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function() UIManager:close(dlg) end,
                            },
                            {
                                text = _("Set"),
                                is_enter_default = true,
                                callback = function()
                                    if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                                    config.reader_top_status_bar.custom_text = dlg:getInputText()
                                    UIManager:close(dlg)
                                    save_clock()
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            },
                        }},
                    }
                    UIManager:show(dlg)
                    dlg:onShowKeyboard()
                end,
            },
            {
                text_func = function()
                    local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
                    local face = type(config.reader_top_status_bar) == "table" and config.reader_top_status_bar.font_face
                    local text = (not face or face == "default") and _("default")
                        or (ok_fc and FontChooser.getFontNameText(face) or face)
                    local size = type(config.reader_top_status_bar) == "table" and config.reader_top_status_bar.font_size or 14
                    return string.format("%s %s, %s", _("Font:"), text, size)
                end,
                sub_item_table = {
                    {
                        text_func = function()
                            local size = type(config.reader_top_status_bar) == "table" and config.reader_top_status_bar.font_size or 14
                            return string.format("%s %s", _("Font size:"), size)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local SpinWidget = require("ui/widget/spinwidget")
                            UIManager:show(SpinWidget:new{
                                title_text = _("Font size"),
                                value = type(config.reader_top_status_bar) == "table" and config.reader_top_status_bar.font_size or 14,
                                value_min = 8,
                                value_max = 36,
                                default_value = 14,
                                callback = function(spin)
                                    if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                                    config.reader_top_status_bar.font_size = spin.value
                                    save_clock()
                                    if touchmenu_instance then touchmenu_instance:updateItems() end
                                end,
                            })
                        end,
                    },
                    {
                        text_func = function()
                            local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
                            local face = type(config.reader_top_status_bar) == "table" and config.reader_top_status_bar.font_face
                            local text = (not face or face == "default") and _("default")
                                or (ok_fc and FontChooser.getFontNameText(face) or face)
                            return string.format("%s %s", _("Font:"), text)
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
                            if not ok_fc then return end
                            local footer_settings = G_reader_settings:readSetting("footer") or {}
                            local footer_font = footer_settings.text_font_face or "NotoSans-Regular.ttf"
                            local current_face = type(config.reader_top_status_bar) == "table" and config.reader_top_status_bar.font_face
                            local display_face = (not current_face or current_face == "default")
                                and footer_font or current_face
                            UIManager:show(FontChooser:new{
                                title = _("Top bar font"),
                                font_file = display_face,
                                default_font_file = footer_font,
                                callback = function(file)
                                    if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                                    if config.reader_top_status_bar.font_face ~= file then
                                        config.reader_top_status_bar.font_face = file
                                        save_clock()
                                        if touchmenu_instance then touchmenu_instance:updateItems() end
                                    end
                                end,
                            })
                        end,
                        hold_callback = function(touchmenu_instance)
                            if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                            if config.reader_top_status_bar.font_face ~= "default" then
                                config.reader_top_status_bar.font_face = "default"
                                save_clock()
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end
                        end,
                    },
                    {
                        text = _("Use default font"),
                        show_func = function()
                            local ok = pcall(require, "ui/widget/fontchooser")
                            return ok
                        end,
                        callback = function(touchmenu_instance)
                            if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                            config.reader_top_status_bar.font_face = "default"
                            save_clock()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    },
                },
            },
            (function()
                local function cur_sep_key()
                    return type(config.reader_top_status_bar) == "table"
                        and config.reader_top_status_bar.separator_key or "small-space"
                end
                local function cur_sep_label()
                    local key = cur_sep_key()
                    for _i, s in ipairs(constants.SEPARATOR_PRESETS) do
                        if s.key == key then return _(s.label) end
                    end
                    return key
                end
                local sub = {}
                for _i, sep in ipairs(constants.SEPARATOR_PRESETS) do
                    if sep.key ~= "custom" then  -- custom not yet wired to reader top bar
                        local key = sep.key
                        table.insert(sub, {
                            text = _(sep.label),
                            checked_func = function() return cur_sep_key() == key end,
                            callback = function(touchmenu_instance)
                                if type(config.reader_top_status_bar) ~= "table" then config.reader_top_status_bar = {} end
                                config.reader_top_status_bar.separator_key = key
                                save_clock()
                                if touchmenu_instance then touchmenu_instance:updateItems() end
                            end,
                        })
                    end
                end
                return {
                    text_func = function()
                        return string.format("%s: %s", _("Separator"), cur_sep_label())
                    end,
                    sub_item_table = sub,
                }
            end)(),
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
            local function resolve_preset_font(preset)
                if not (preset.footer and preset.footer.text_font_face) then return preset end
                local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
                if not ok_fc then return preset end
                local face = preset.footer.text_font_face
                if FontChooser.isFontRegistered(face) then return preset end
                -- bare filename: search fontinfo for a matching full path
                local FontList = require("fontlist")
                FontList:getFontList()
                local suffix = "/" .. face
                for path in pairs(FontList.fontinfo) do
                    if path:sub(-#suffix) == suffix then
                        local util = require("util")
                        local copy = util.tableDeepCopy(preset)
                        copy.footer.text_font_face = path
                        return copy
                    end
                end
                return preset
            end

            local function apply_footer_preset(preset)
                ui.view.footer:loadPreset(resolve_preset_font(preset))
                config.features["reader_top_status_bar"] = true
                save_and_apply("reader_top_status_bar")
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
            local footer_presets = require("modules/reader/patches/reader_footer_presets")
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
    -- Cover Mode
    -- -------------------------------------------------------------------------
    
    -- Helper function: get coverable drawer types
    local function getCoveredDrawers()
        return G_reader_settings:readSetting("cover_mode_drawers", {lighten = true})
    end
    
    -- Helper function: save coverable drawer types and refresh
    local function saveCoveredDrawers(drawers)
        G_reader_settings:saveSetting("cover_mode_drawers", drawers)
        local ReaderUI = require("apps/reader/readerui")
        if ReaderUI and ReaderUI.instance and ReaderUI.instance.view then
            if ReaderUI.instance.view.recalculate then
                ReaderUI.instance.view:recalculate()
            end
            ReaderUI.instance:handleEvent(Event:new("RedrawCurrentView"))
            UIManager:setDirty(nil, "full")
        end
    end
    
    -- Build coverable drawer types submenu
    local function buildDrawerSettingsSubMenu()
        local sub_items = {}
        local drawer_names = {
            lighten = _("Highlight"),
            underscore = _("Underline"),
            strikeout = _("Strikethrough"),
            invert = _("Invert"),
        }
        
        for drawer, name in pairs(drawer_names) do
            table.insert(sub_items, {
                text = name,
                checked_func = function()
                    local covered = getCoveredDrawers()
                    return covered[drawer] == true
                end,
                callback = function(touchmenu_instance)
                    local covered = getCoveredDrawers()
                    covered[drawer] = not covered[drawer]
                    saveCoveredDrawers(covered)
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            })
        end
        return sub_items
    end
    
    table.insert(items, {
        text = _("Cover Mode"),
        sub_item_table = {
            -- Enable Cover - directly uses original setting
            {
                text = _("Enable Cover"),
                checked_func = function()
                    return G_reader_settings:readSetting("cover_mode_enabled", true)
                end,
                callback = function(touchmenu_instance)
                    local new_value = not G_reader_settings:readSetting("cover_mode_enabled", true)
                    G_reader_settings:saveSetting("cover_mode_enabled", new_value)
                    local Notification = require("ui/widget/notification")
                    if new_value then
                        Notification:notify(_("Cover mode enabled"))
                    else
                        Notification:notify(_("Cover mode disabled"))
                    end
                    local ReaderUI = require("apps/reader/readerui")
                    if ReaderUI and ReaderUI.instance then
                        if ReaderUI.instance.view and ReaderUI.instance.view.recalculate then
                            ReaderUI.instance.view:recalculate()
                        end
                        ReaderUI.instance:handleEvent(Event:new("RedrawCurrentView"))
                        UIManager:setDirty(nil, "full")
                    end
                    if touchmenu_instance then
                        touchmenu_instance:updateItems()
                    end
                end,
            },
            
            -- Cover all / Uncover all
            {
                text = _("Cover All / Uncover All"),
                enabled_func = function()
                    return G_reader_settings:readSetting("cover_mode_enabled", true)
                end,
                checked_func = function()
                    local ReaderUI = require("apps/reader/readerui")
                    if not ReaderUI or not ReaderUI.instance then return false end
                    local highlight = ReaderUI.instance.highlight
                    if not highlight or not highlight._temp_covered then return false end
                    local annotations = highlight.ui.annotation.annotations
                    for idx, item in ipairs(annotations) do
                        if item.drawer and highlight._temp_covered[idx] then
                            return true
                        end
                    end
                    return false
                end,
                callback = function()
                    local ReaderUI = require("apps/reader/readerui")
                    if ReaderUI and ReaderUI.instance then
                        ReaderUI.instance:onToggleCoverMode()
                    end
                end,
            },
            
            -- Toggle mode - displays current selection in menu text
            {
                text_func = function()
                    local mode = G_reader_settings:readSetting("cover_mode_toggle_mode", 1)
                    local mode_text = ""
                    if mode == 1 then
                        mode_text = _("Double-tap to toggle")
                    elseif mode == 2 then
                        mode_text = _("Single-tap to toggle (block menu)")
                    else
                        mode_text = _("Single-tap to toggle (show menu)")
                    end
                    return _("Single Cover - ") .. mode_text
                end,
                enabled_func = function()
                    return G_reader_settings:readSetting("cover_mode_enabled", true)
                end,
                sub_item_table = {
                    {
                        text = _("Double-tap to toggle"),
                        checked_func = function()
                            return G_reader_settings:readSetting("cover_mode_toggle_mode", 1) == 1
                        end,
                        callback = function(touchmenu_instance)
                            G_reader_settings:saveSetting("cover_mode_toggle_mode", 1)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text = _("Single-tap to toggle (block menu)"),
                        checked_func = function()
                            return G_reader_settings:readSetting("cover_mode_toggle_mode", 1) == 2
                        end,
                        callback = function(touchmenu_instance)
                            G_reader_settings:saveSetting("cover_mode_toggle_mode", 2)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                    {
                        text = _("Single-tap to toggle (show menu)"),
                        checked_func = function()
                            return G_reader_settings:readSetting("cover_mode_toggle_mode", 1) == 3
                        end,
                        callback = function(touchmenu_instance)
                            G_reader_settings:saveSetting("cover_mode_toggle_mode", 3)
                            if touchmenu_instance then
                                touchmenu_instance:updateItems()
                            end
                        end,
                    },
                },
            },
            
            -- Coverable drawer types
            {
                text = _("Coverable Drawer Types"),
                enabled_func = function()
                    return G_reader_settings:readSetting("cover_mode_enabled", true)
                end,
                sub_item_table = buildDrawerSettingsSubMenu(),
            },
        },
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
                        config.highlight_lookup.show_wikipedia ~= true
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
                        config.highlight_lookup.allow_unknown_items ~= true
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
                config.reader_footer.verbose_chapter_time ~= true
            plugin:saveConfig()
        end,
    })

    -- -------------------------------------------------------------------------
    -- Feature toggles
    -- -------------------------------------------------------------------------

    -- bottom swipe is forced on when page browser is active
    table.insert(items, {
        text = _("Enable bottom swipe"),
        checked_func = function()
            return config.features["reader_bottom_menu"] == true
                or config.features["page_browser"] == true
        end,
        enabled_func = function()
            return config.features["page_browser"] ~= true
        end,
        callback = function()
            config.features["reader_bottom_menu"] = config.features["reader_bottom_menu"] ~= true
            save_and_apply("reader_bottom_menu")
        end,
    })
    -- page browser requires bottom swipe; disabling bottom swipe unchecks this too
    table.insert(items, {
        text = _("Enable page browser"),
        checked_func = function()
            return config.features["page_browser"] == true
        end,
        enabled_func = function()
            return config.features["reader_bottom_menu"] == true
                or config.features["page_browser"] == true
        end,
        callback = function()
            config.features["page_browser"] = config.features["page_browser"] ~= true
            save_and_apply("page_browser")
        end,
    })
    table.insert(items, {
        text = _("Restore library view on return"),
        checked_func = function()
            return config.features["restore_library_view"] == true
        end,
        callback = function()
            config.features["restore_library_view"] = config.features["restore_library_view"] ~= true
            save_and_apply("restore_library_view")
        end,
    })

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

            local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
            if not ok_fc then FontChooser = nil end

            local font_sub_items = {
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
            }
            if FontChooser then
                table.insert(font_sub_items, {
                    text_func = function()
                        local footer_settings = G_reader_settings:readSetting("footer") or {}
                        local face = footer_settings.text_font_face
                        local text = (not face or face == "NotoSans-Regular.ttf")
                            and _("default") or FontChooser.getFontNameText(face)
                        return string.format("%s %s", _("Font:"), text)
                    end,
                    keep_menu_open = true,
                    callback = function(touchmenu_instance)
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
                })
            end
            table.insert(font_sub_items, {
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
            })
            local ok_fc_default = pcall(require, "ui/widget/fontchooser")
            if ok_fc_default then
                table.insert(font_sub_items, {
                    text = _("Use default font"),
                    callback = function(touchmenu_instance)
                        ui.view.footer.settings.text_font_face = "NotoSans-Regular.ttf"
                        ui.view.footer.settings.text_font_size = 14
                        ui.view.footer.settings.text_font_bold = false
                        ui.view.footer:updateFooterFont()
                        ui.view.footer:refreshFooter(true, true)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end
            local font_submenu = {
                text = _("Font"),
                sub_item_table = font_sub_items,
            }

            local mock = {}
            ui.view.footer:addToMainMenu(mock)
            local result = {}
            table.insert(result, font_submenu)
            table.insert(result, {
                text = _("Hide in CBZ/PDF files"),
                checked_func = function()
                    return type(config.reader_footer) == "table"
                        and config.reader_footer.hide_in_cbz == true
                end,
                callback = function()
                    if type(config.reader_footer) ~= "table" then
                        config.reader_footer = {}
                    end
                    config.reader_footer.hide_in_cbz =
                        config.reader_footer.hide_in_cbz ~= true
                    plugin:saveConfig()
                    -- Apply immediately to the current open document.
                    local footer = ui and ui.view and ui.view.footer
                    if footer then
                        footer:applyFooterMode()
                        footer:refreshFooter(true, true)
                    end
                end,
            })
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

local _ = require("gettext")
local UIManager = require("ui/uimanager")

local HomePresets = require("modules/filebrowser/patches/home/home_presets")
local PresetStore = require("config/preset_store")
local Registry = require("modules/filebrowser/patches/home/components/registry")
local library_font = require("modules/filebrowser/patches/library_font")
local ReadingGoals = require("common/reading_goals")

local M = {}

local DEFAULT_ORDER = {
    "datetime",
    "featured_recent",
    "featured_custom",
    "featured_tbr",
    "stats_triplet",
    "reading_goals",
    "strip_recent",
    "strip_custom",
    "strip_tbr",
    "quotes",
}

local DEFAULT_ENABLED = {
    datetime = true,
    featured_recent = true,
    quotes = true,
    strip_recent = true,
}

local DEFAULT_FEATURED_PROGRESS_META = {
    left = "percent",
    right = "total_pages",
}

local FEATURED_TEXT_STYLE_DEFAULTS = {
    title = { font_face = "default", font_size = 11, bold = true },
    author = { font_face = "default", font_size = 9, bold = false },
    description = { font_face = "default", font_size = 16, bold = false },
}

local function normalize_order(order)
    if order == "reverse" then return "reverse" end
    return "default"
end

local function ensure_featured_text_style(mcfg, key)
    if type(mcfg.text_styles) ~= "table" then mcfg.text_styles = {} end
    local defaults = FEATURED_TEXT_STYLE_DEFAULTS[key]
    if type(defaults) ~= "table" then return nil end
    if type(mcfg.text_styles[key]) ~= "table" then mcfg.text_styles[key] = {} end
    local style = mcfg.text_styles[key]
    if type(style.font_face) ~= "string" or style.font_face == "" then
        style.font_face = defaults.font_face
    end
    local size = tonumber(style.font_size)
    if not size then
        style.font_size = defaults.font_size
    else
        style.font_size = math.max(6, math.min(40, math.floor(size + 0.5)))
    end
    if style.bold == nil then
        style.bold = defaults.bold
    else
        style.bold = style.bold == true
    end
    return style
end

local function ensure_featured_text_styles(mcfg)
    for key, defaults in pairs(FEATURED_TEXT_STYLE_DEFAULTS) do
        if defaults then ensure_featured_text_style(mcfg, key) end
    end
end

local function ensure_module_cfg(dcfg, module_id)
    if type(dcfg.modules) ~= "table" then dcfg.modules = {} end
    if type(dcfg.modules[module_id]) ~= "table" then dcfg.modules[module_id] = {} end
    local mcfg = dcfg.modules[module_id]
    if module_id == "datetime" then
        mcfg.show_module_title = false
    elseif mcfg.show_module_title == nil then
        mcfg.show_module_title = false
    end
    return mcfg
end

local function ensure_featured_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if mcfg.show_description == nil then mcfg.show_description = true end
    if mcfg.interactive == nil then mcfg.interactive = true end
    if mcfg.show_status_bar == nil then mcfg.show_status_bar = false end
    if mcfg.status_bar_show_bottom_border == nil then mcfg.status_bar_show_bottom_border = true end
    if mcfg.status_bar_bold_text == nil then mcfg.status_bar_bold_text = true end
    ensure_featured_text_styles(mcfg)
    if type(mcfg.progress_meta) ~= "table" then mcfg.progress_meta = {} end
    if mcfg.progress_meta.left == nil and mcfg.progress_meta.right == nil then
        for key, side in pairs(mcfg.progress_meta) do
            if side == "left" and mcfg.progress_meta.left == nil then
                mcfg.progress_meta.left = key
            elseif side == "right" and mcfg.progress_meta.right == nil then
                mcfg.progress_meta.right = key
            end
        end
    end
    for side, metric in pairs(DEFAULT_FEATURED_PROGRESS_META) do
        if mcfg.progress_meta[side] ~= "total_pages"
                and mcfg.progress_meta[side] ~= "current_total"
                and mcfg.progress_meta[side] ~= "percent"
                and mcfg.progress_meta[side] ~= "time_left"
                and mcfg.progress_meta[side] ~= "off" then
            mcfg.progress_meta[side] = metric
        end
    end
    return mcfg
end

local function ensure_strip_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if mcfg.interactive == nil then mcfg.interactive = true end
    if module_id == "strip_recent" then
        if mcfg.filter_unread == nil then mcfg.filter_unread = false end
        if mcfg.filter_tbr == nil then mcfg.filter_tbr = false end
        if mcfg.filter_finished == nil then mcfg.filter_finished = false end
    end
    if mcfg.two_rows == nil then mcfg.two_rows = false end
    if type(mcfg.count) ~= "number" then mcfg.count = mcfg.two_rows and 8 or 4 end
    if mcfg.two_rows then
        if mcfg.count < 2 then mcfg.count = 2 end
        if mcfg.count > 10 then mcfg.count = 10 end
    else
        if mcfg.count < 3 then mcfg.count = 3 end
        if mcfg.count > 5 then mcfg.count = 5 end
    end
    if mcfg.show_strip_titles == nil then mcfg.show_strip_titles = false end
    if mcfg.show_badges == nil then mcfg.show_badges = false end
    if mcfg.center_books == nil then mcfg.center_books = false end
    return mcfg
end

local function ensure_home_widget_cfg(dcfg)
    local featured_custom = ensure_featured_cfg(dcfg, "featured_custom")
    if type(featured_custom.path) ~= "string" then featured_custom.path = nil end
    ensure_featured_cfg(dcfg, "featured_tbr")
    ensure_featured_cfg(dcfg, "featured_recent")
    local stats_triplet = ensure_module_cfg(dcfg, "stats_triplet")
    if stats_triplet.stat_style ~= "outline" and stats_triplet.stat_style ~= "none" then
        stats_triplet.stat_style = "divider"
    end
    local strip_custom = ensure_strip_cfg(dcfg, "strip_custom")
    if type(strip_custom.paths) ~= "table" then strip_custom.paths = {} end
    ensure_strip_cfg(dcfg, "strip_tbr")
    ensure_strip_cfg(dcfg, "strip_recent")
end

local function ensure_cfg(_config)
    local dcfg = PresetStore.getSettings("home")
    if type(dcfg) ~= "table" or next(dcfg) == nil then
        dcfg = HomePresets.defaultHomePage()
    end
    HomePresets.ensurePresetState(dcfg)

    dcfg.rows = Registry.normalizeRows(dcfg.rows, DEFAULT_ORDER, DEFAULT_ENABLED)

    if dcfg.show_status_bar == nil then dcfg.show_status_bar = true end

    if type(dcfg.middle_stats_triplet) ~= "table" then
        dcfg.middle_stats_triplet = { "today_pages", "today_duration", "streak" }
    end

    dcfg.goals = ReadingGoals.normalize(dcfg.goals)

    if type(dcfg.quotes) ~= "table" then dcfg.quotes = {} end
    if dcfg.quotes.show_author == nil then dcfg.quotes.show_author = true end

    for _i, comp in ipairs(Registry.list()) do
        ensure_module_cfg(dcfg, comp.id)
    end
    ensure_home_widget_cfg(dcfg)

    return dcfg
end

local function enabled_count(enabled)
    local n = 0
    for _k, v in pairs(enabled) do
        if v == true then n = n + 1 end
    end
    return n
end

local home_max_widgets = 5
local custom_strip_max_books = 50

function M.build(ctx)
    local config = ctx.config
    local dcfg = ensure_cfg(config)
    local home_rebuild_pending = false
    local home_rebuild_poll_active = false
    local schedule_home_rebuild_on_menu_close

    local function unique_user_preset_name(base)
        if not PresetStore.find("home", base) then return base end
        local i = 2
        while PresetStore.find("home", base .. " " .. i) do
            i = i + 1
        end
        return base .. " " .. i
    end

    local function editable_name_for_builtin(preset_name)
        if preset_name == HomePresets.DEFAULT_PRESET_NAME then
            return HomePresets.CUSTOM_PRESET_NAME
        end
        return tostring(preset_name or HomePresets.CUSTOM_PRESET_NAME) .. " custom"
    end

    local function copy_builtin_for_editing(preset_name)
        local name = unique_user_preset_name(editable_name_for_builtin(preset_name))
        dcfg.active_preset = name
        dcfg.title = name
        local state = HomePresets.captureHomePage(dcfg)
        state.title = name
        PresetStore.save("home", name, state)
        PresetStore.setActivePreset("home", name)
        return name
    end

    local function make_builtin_editable()
        if not HomePresets.isBuiltinPresetName(dcfg.active_preset) then return end
        copy_builtin_for_editing(dcfg.active_preset)
    end

    local function save_home(_mode, opts)
        if not (type(opts) == "table" and opts.make_builtin_editable == false) then
            make_builtin_editable()
        end
        PresetStore.saveSettings("home", dcfg)
        home_rebuild_pending = true
        schedule_home_rebuild_on_menu_close()
    end

    local function is_filemanager_menu_open()
        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        if not ok_fm or not FileManager or not FileManager.instance then return false end
        local fm = FileManager.instance
        local menu = fm.menu
        if not menu then return false end
        local menu_container = menu.menu_container
        local stack = UIManager._window_stack
        if not stack then return false end
        for _i, entry in ipairs(stack) do
            local widget = entry and entry.widget
            if widget == menu or (menu_container and widget == menu_container) then return true end
        end
        return false
    end

    schedule_home_rebuild_on_menu_close = function()
        if home_rebuild_poll_active then return end
        home_rebuild_poll_active = true
        local function tick()
            local plugin = ctx.plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            local settings_apply = ctx.settings_apply
            local home = settings_apply
                and settings_apply.get_shared
                and settings_apply.get_shared(plugin, "home")
            local home_waiting = home
                and home.hasActive
                and home.hasActive()
                and home.isActiveOnTop
                and not home.isActiveOnTop()
            if is_filemanager_menu_open() or home_waiting then
                UIManager:scheduleIn(0.25, tick)
                return
            end
            home_rebuild_poll_active = false
            if not home_rebuild_pending then return end
            home_rebuild_pending = false
            if home and home.rebuildActive then
                UIManager:scheduleIn(0, function()
                    home.rebuildActive()
                end)
            end
        end
        UIManager:scheduleIn(0.25, tick)
    end

    local function component_label(id)
        local comp = Registry.get(id)
        if comp and comp.label then return comp.label end
        return tostring(id) .. " (" .. _("Unavailable") .. ")"
    end

    local order_options = {
        { id = "default", text = _("Default") },
        { id = "reverse", text = _("Reverse") },
    }

    local progress_label_options = {
        { id = "off", text = _("Off") },
        { id = "percent", text = _("Percent") },
        { id = "time_left", text = _("Time to book end") },
        { id = "current_total", text = _("Current/total pages") },
        { id = "total_pages", text = _("Total pages") },
    }

    local function progress_label(metric)
        for _i, opt in ipairs(progress_label_options) do
            if opt.id == metric then return opt.text end
        end
        return _("Off")
    end

    local function build_order_items(mcfg)
        local items = {}
        for _i, opt in ipairs(order_options) do
            local order_id = opt.id
            items[#items + 1] = {
                text = opt.text,
                radio = true,
                checked_func = function()
                    return normalize_order(mcfg.order) == order_id
                end,
                callback = function()
                    mcfg.order = order_id
                    save_home("reinit")
                end,
            }
        end
        return items
    end

    local function build_progress_meta_items(mcfg)
        if type(mcfg.progress_meta) ~= "table" then mcfg.progress_meta = {} end
        local function side_items(side)
            local items = {}
            for _i, opt in ipairs(progress_label_options) do
                local metric = opt.id
                items[#items + 1] = {
                    text = opt.text,
                    radio = true,
                    checked_func = function()
                        return (mcfg.progress_meta[side] or "off") == metric
                    end,
                    callback = function()
                        mcfg.progress_meta[side] = metric
                        save_home("reinit")
                    end,
                }
            end
            return items
        end
        return {
            {
                text_func = function()
                    return _("Left") .. ": " .. progress_label(mcfg.progress_meta.left)
                end,
                sub_item_table = side_items("left"),
            },
            {
                text_func = function()
                    return _("Right") .. ": " .. progress_label(mcfg.progress_meta.right)
                end,
                sub_item_table = side_items("right"),
            },
        }
    end

    local function font_label(face)
        if face == nil or face == "" or face == "default" then return _("default") end
        local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
        return ok_fc and FontChooser.getFontNameText(face) or face
    end

    local function chooser_default_font()
        local font_name = library_font.getFontName()
        if font_name and font_name ~= "" and font_name ~= "cfont" then
            return font_name
        end
        local footer_settings = G_reader_settings:readSetting("footer") or {}
        return footer_settings.text_font_face or "NotoSans-Regular.ttf"
    end

    local function save_featured_text_style(touchmenu_instance)
        save_home("reinit")
        if touchmenu_instance then touchmenu_instance:updateItems() end
    end

    local function featured_text_style_summary(mcfg, key)
        local style = ensure_featured_text_style(mcfg, key)
        local weight = style.bold and _("bold") or _("regular")
        return string.format("%s, %s, %s", font_label(style.font_face), tostring(style.font_size), weight)
    end

    local function build_featured_text_style_items(mcfg, key, label)
        local defaults = FEATURED_TEXT_STYLE_DEFAULTS[key]
        return {
            {
                text_func = function()
                    local style = ensure_featured_text_style(mcfg, key)
                    return string.format("%s %s", _("Font size:"), tostring(style.font_size))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local SpinWidget = require("ui/widget/spinwidget")
                    local style = ensure_featured_text_style(mcfg, key)
                    UIManager:show(SpinWidget:new{
                        title_text = string.format("%s %s", label, _("font size")),
                        value = style.font_size,
                        value_min = 6,
                        value_max = 40,
                        default_value = defaults.font_size,
                        callback = function(spin)
                            style.font_size = math.max(6, math.min(40, spin.value))
                            save_featured_text_style(touchmenu_instance)
                        end,
                    })
                end,
            },
            {
                text_func = function()
                    local style = ensure_featured_text_style(mcfg, key)
                    return string.format("%s %s", _("Font:"), font_label(style.font_face))
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local ok_fc, FontChooser = pcall(require, "ui/widget/fontchooser")
                    if not ok_fc then return end
                    local style = ensure_featured_text_style(mcfg, key)
                    local default_font = chooser_default_font()
                    local display_face = style.font_face == "default" and default_font or style.font_face
                    UIManager:show(FontChooser:new{
                        title = string.format("%s %s", label, _("font")),
                        font_file = display_face,
                        default_font_file = default_font,
                        callback = function(file)
                            if style.font_face ~= file then
                                style.font_face = file
                                save_featured_text_style(touchmenu_instance)
                            end
                        end,
                    })
                end,
                hold_callback = function(touchmenu_instance)
                    local style = ensure_featured_text_style(mcfg, key)
                    if style.font_face ~= "default" then
                        style.font_face = "default"
                        save_featured_text_style(touchmenu_instance)
                    end
                end,
            },
            {
                text = _("Bold"),
                checked_func = function()
                    return ensure_featured_text_style(mcfg, key).bold == true
                end,
                callback = function(touchmenu_instance)
                    local style = ensure_featured_text_style(mcfg, key)
                    style.bold = style.bold ~= true
                    save_featured_text_style(touchmenu_instance)
                end,
            },
            {
                text = _("Use default style"),
                callback = function(touchmenu_instance)
                    mcfg.text_styles[key] = {
                        font_face = defaults.font_face,
                        font_size = defaults.font_size,
                        bold = defaults.bold,
                    }
                    save_featured_text_style(touchmenu_instance)
                end,
            },
        }
    end

    local function build_featured_text_styles_items(mcfg)
        local items = {
            needs_refresh = true,
            refresh_func = function()
                return build_featured_text_styles_items(mcfg)
            end,
        }
        items[#items + 1] = {
            sub_title = _("Title"),
            text_func = function()
                return _("Title") .. ": " .. featured_text_style_summary(mcfg, "title")
            end,
            sub_item_table = build_featured_text_style_items(mcfg, "title", _("Title")),
        }
        items[#items + 1] = {
            sub_title = _("Author"),
            text_func = function()
                return _("Author") .. ": " .. featured_text_style_summary(mcfg, "author")
            end,
            sub_item_table = build_featured_text_style_items(mcfg, "author", _("Author")),
        }
        items[#items + 1] = {
            sub_title = _("Description"),
            text_func = function()
                return _("Description") .. ": " .. featured_text_style_summary(mcfg, "description")
            end,
            sub_item_table = build_featured_text_style_items(mcfg, "description", _("Description")),
        }
        return items
    end

    local function featured_text_styles_item(mcfg)
        return {
            text = _("Text styles"),
            sub_item_table_func = function()
                return build_featured_text_styles_items(mcfg)
            end,
        }
    end

    local function interactive_item(mcfg)
        return {
            text = _("Interactive"),
            checked_func = function()
                return mcfg.interactive ~= false
            end,
            callback = function()
                mcfg.interactive = mcfg.interactive == false
                save_home("reinit")
            end,
        }
    end

    local function filter_status_item(mcfg, key, text)
        return {
            text = text,
            checked_func = function()
                return mcfg[key] == true
            end,
            callback = function()
                mcfg[key] = mcfg[key] ~= true
                save_home("reinit")
            end,
        }
    end

    local function toggle_featured_status_bar(mcfg)
        local enabled = mcfg.show_status_bar ~= true
        mcfg.show_status_bar = enabled
        if enabled and dcfg.show_status_bar ~= false then
            dcfg.show_status_bar = false
        end
        save_home("reinit")
    end

    local function featured_status_bar_item(mcfg)
        return {
            text = _("Show top status bar"),
            checked_func = function()
                return mcfg.show_status_bar == true
            end,
            callback = function()
                toggle_featured_status_bar(mcfg)
            end,
        }
    end

    local function featured_status_bar_options(mcfg)
        return {
            featured_status_bar_item(mcfg),
            {
                text = _("Show bottom border"),
                checked_func = function()
                    return mcfg.status_bar_show_bottom_border ~= false
                end,
                callback = function()
                    mcfg.status_bar_show_bottom_border = mcfg.status_bar_show_bottom_border == false
                    save_home("reinit")
                end,
            },
            {
                text = _("Bold text"),
                checked_func = function()
                    return mcfg.status_bar_bold_text ~= false
                end,
                callback = function()
                    mcfg.status_bar_bold_text = mcfg.status_bar_bold_text == false
                    save_home("reinit")
                end,
            },
        }
    end

    local function path_label(path)
        if type(path) ~= "string" or path == "" then
            return _("None")
        end
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if ok_bim and BookInfoManager then
            local bi = BookInfoManager:getBookInfo(path, false)
            if bi and type(bi.title) == "string" and bi.title ~= "" then
                return bi.title
            end
        end
        return (path:match("([^/]+)$") or path):gsub("%.[^%.]+$", "")
    end

    local function choose_book(callback)
        local PathChooser = require("ui/widget/pathchooser")
        local paths = require("common/paths")
        local start_path = paths.getHomeDir() or G_reader_settings:readSetting("lastdir") or "/"
        UIManager:show(PathChooser:new{
            select_directory = false,
            select_file = true,
            show_files = true,
            path = start_path,
            onConfirm = function(file_path)
                local lfs = require("libs/libkoreader-lfs")
                if type(file_path) == "string" and lfs.attributes(file_path, "mode") == "file" then
                    callback(file_path)
                end
            end,
        })
    end

    local function build_featured_custom_items(mcfg)
        return {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return mcfg.show_module_title == true
                end,
                callback = function()
                    mcfg.show_module_title = mcfg.show_module_title ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Show description"),
                checked_func = function()
                    return mcfg.show_description ~= false
                end,
                callback = function()
                    mcfg.show_description = mcfg.show_description == false
                    save_home("reinit")
                end,
            },
            interactive_item(mcfg),
            {
                text = _("Top status bar"),
                sub_item_table = featured_status_bar_options(mcfg),
            },
            featured_text_styles_item(mcfg),
            {
                text = _("Progress labels"),
                sub_item_table = build_progress_meta_items(mcfg),
            },
            {
                text_func = function()
                    return _("Book: ") .. path_label(mcfg.path)
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    choose_book(function(path)
                        mcfg.path = path
                        save_home("reinit")
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end)
                end,
            },
            {
                text = _("Clear book"),
                enabled_func = function()
                    return type(mcfg.path) == "string" and mcfg.path ~= ""
                end,
                callback = function()
                    mcfg.path = nil
                    save_home("reinit")
                end,
            },
        }
    end

    local function build_strip_custom_items(mcfg)
        if type(mcfg.paths) ~= "table" then mcfg.paths = {} end
        local function refresh_custom_strip_menu(touchmenu_instance)
            if touchmenu_instance then
                touchmenu_instance.item_table = build_strip_custom_items(mcfg)
                touchmenu_instance:updateItems()
            end
        end
        local items = {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return mcfg.show_module_title == true
                end,
                callback = function()
                    mcfg.show_module_title = mcfg.show_module_title ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Show book titles"),
                checked_func = function()
                    return mcfg.show_strip_titles == true
                end,
                callback = function()
                    mcfg.show_strip_titles = mcfg.show_strip_titles ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Show badges"),
                checked_func = function()
                    return mcfg.show_badges == true
                end,
                callback = function()
                    mcfg.show_badges = mcfg.show_badges ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Center books"),
                checked_func = function()
                    return mcfg.center_books == true
                end,
                callback = function()
                    mcfg.center_books = mcfg.center_books ~= true
                    save_home("reinit")
                end,
            },
            interactive_item(mcfg),
            {
                text = _("Two rows"),
                checked_func = function()
                    return mcfg.two_rows == true
                end,
                callback = function()
                    mcfg.two_rows = mcfg.two_rows ~= true
                    if mcfg.two_rows then
                        mcfg.count = 8
                    else
                        mcfg.count = 4
                    end
                    save_home("reinit")
                end,
            },
            {
                text_func = function()
                    return _("Books shown: ") .. tostring(mcfg.count or 4)
                end,
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local is_two = mcfg.two_rows == true
                    UIManager:show(SpinWidget:new{
                        title_text = _("Books shown"),
                        value = mcfg.count or (is_two and 8 or 4),
                        value_min = is_two and 2 or 3,
                        value_max = is_two and 10 or 5,
                        callback = function(spin)
                            mcfg.count = spin.value
                            save_home("reinit")
                        end,
                    })
                end,
            },
            {
                text = _("Add book"),
                keep_menu_open = true,
                enabled_func = function()
                    return #mcfg.paths < custom_strip_max_books
                end,
                callback = function(touchmenu_instance)
                    choose_book(function(path)
                        for _i, existing in ipairs(mcfg.paths) do
                            if existing == path then return end
                        end
                        mcfg.paths[#mcfg.paths + 1] = path
                        save_home("reinit")
                        refresh_custom_strip_menu(touchmenu_instance)
                    end)
                end,
            },
        }

        for i, path in ipairs(mcfg.paths) do
            items[#items + 1] = {
                text = _("Remove: ") .. path_label(path),
                callback = function(touchmenu_instance)
                    table.remove(mcfg.paths, i)
                    save_home("reinit")
                    refresh_custom_strip_menu(touchmenu_instance)
                end,
            }
        end

        items[#items + 1] = {
            text = _("Clear books"),
            enabled_func = function()
                return #mcfg.paths > 0
            end,
            callback = function(touchmenu_instance)
                mcfg.paths = {}
                save_home("reinit")
                refresh_custom_strip_menu(touchmenu_instance)
            end,
        }
        return items
    end

    local function build_featured_widget_items(module_id)
        local mcfg = ensure_featured_cfg(dcfg, module_id)
        if module_id == "featured_custom" then
            return build_featured_custom_items(mcfg)
        end
        local items = {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return mcfg.show_module_title == true
                end,
                callback = function()
                    mcfg.show_module_title = mcfg.show_module_title ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Show description"),
                checked_func = function()
                    return mcfg.show_description ~= false
                end,
                callback = function()
                    mcfg.show_description = mcfg.show_description == false
                    save_home("reinit")
                end,
            },
            interactive_item(mcfg),
            {
                text = _("Top status bar"),
                sub_item_table = featured_status_bar_options(mcfg),
            },
            featured_text_styles_item(mcfg),
            {
                text = _("Order"),
                sub_item_table = build_order_items(mcfg),
            },
            {
                text = _("Progress labels"),
                sub_item_table = build_progress_meta_items(mcfg),
            },
        }
        return items
    end

    local function build_strip_widget_items(module_id)
        local mcfg = ensure_strip_cfg(dcfg, module_id)
        if module_id == "strip_custom" then
            return build_strip_custom_items(mcfg)
        end
        local items = {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return mcfg.show_module_title == true
                end,
                callback = function()
                    mcfg.show_module_title = mcfg.show_module_title ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Show book titles"),
                checked_func = function()
                    return mcfg.show_strip_titles == true
                end,
                callback = function()
                    mcfg.show_strip_titles = mcfg.show_strip_titles ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Show badges"),
                checked_func = function()
                    return mcfg.show_badges == true
                end,
                callback = function()
                    mcfg.show_badges = mcfg.show_badges ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Center books"),
                checked_func = function()
                    return mcfg.center_books == true
                end,
                callback = function()
                    mcfg.center_books = mcfg.center_books ~= true
                    save_home("reinit")
                end,
            },
            interactive_item(mcfg),
            {
                text = _("Two rows"),
                checked_func = function()
                    return mcfg.two_rows == true
                end,
                callback = function()
                    mcfg.two_rows = mcfg.two_rows ~= true
                    if mcfg.two_rows then
                        mcfg.count = 8
                    else
                        mcfg.count = 4
                    end
                    save_home("reinit")
                end,
            },
            {
                text_func = function()
                    return _("Books shown: ") .. tostring(mcfg.count or 4)
                end,
                keep_menu_open = true,
                callback = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    local is_two = mcfg.two_rows == true
                    UIManager:show(SpinWidget:new{
                        title_text = _("Books shown"),
                        value = mcfg.count or (is_two and 8 or 4),
                        value_min = is_two and 2 or 3,
                        value_max = is_two and 10 or 5,
                        callback = function(spin)
                            mcfg.count = spin.value
                            save_home("reinit")
                        end,
                    })
                end,
            },
            {
                text = _("Order"),
                sub_item_table = build_order_items(mcfg),
            },
        }
        if module_id == "strip_recent" then
            table.insert(items, 3, filter_status_item(mcfg, "filter_unread", _("Hide unread books")))
            table.insert(items, 4, filter_status_item(mcfg, "filter_tbr", _("Hide TBR books")))
            table.insert(items, 5, filter_status_item(mcfg, "filter_finished", _("Hide finished books")))
        end
        return items
    end

    local function toggle_widget_enabled(cid)
        if dcfg.rows.enabled[cid] == true then
            if enabled_count(dcfg.rows.enabled) <= 1 and Registry.get(cid) then
                return false
            end
            dcfg.rows.enabled[cid] = false
        else
            if not Registry.get(cid) then return false end
            if enabled_count(dcfg.rows.enabled) >= home_max_widgets then
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("Maximum 5 widgets allowed"),
                })
                return false
            end
            dcfg.rows.enabled[cid] = true
        end
        save_home("reinit")
        return true
    end

    local build_widget_settings_items
    local widget_ids_with_settings = {
        featured_custom = true,
        featured_tbr = true,
        featured_recent = true,
        stats_triplet = true,
        reading_goals = true,
        strip_custom = true,
        strip_tbr = true,
        strip_recent = true,
        quotes = true,
    }

    local function arrange_widgets()
        local ZenArrangeList = require("common/ui/zen_arrange_list")
        dcfg.rows = Registry.normalizeRows(dcfg.rows, DEFAULT_ORDER, DEFAULT_ENABLED)
        local order = dcfg.rows.order
        local sort_items = {}
        local function should_dim_widget(id)
            if not Registry.get(id) then return true end
            return dcfg.rows.enabled[id] ~= true
                and enabled_count(dcfg.rows.enabled) >= home_max_widgets
        end
        local function update_dim_states()
            for _i, sort_item in ipairs(sort_items) do
                sort_item.dim = should_dim_widget(sort_item.orig_item)
            end
        end
        for _i, id in ipairs(order) do
            local item = {
                text = component_label(id),
                orig_item = id,
                dim = should_dim_widget(id),
                checked_func = function()
                    return dcfg.rows.enabled[id] == true
                end,
                callback = function()
                    if toggle_widget_enabled(id) then
                        update_dim_states()
                    end
                end,
            }
            if widget_ids_with_settings[id] then
                item.sub_title = component_label(id)
                item.sub_item_table_func = function()
                    return build_widget_settings_items(id)
                end
            end
            sort_items[#sort_items + 1] = item
        end
        ZenArrangeList.show{
            title = _("Widgets"),
            item_table = sort_items,
            callback = function()
                local new_order = {}
                for _i, item in ipairs(sort_items) do
                    new_order[#new_order + 1] = item.orig_item
                end
                dcfg.rows.order = new_order
                save_home("reinit")
            end,
        }
    end

    local function all_home_presets()
        local all = HomePresets.getBuiltinPresets()
        local presets = PresetStore.list("home")
        for _i, preset in ipairs(presets) do
            all[#all + 1] = preset
        end
        return all
    end

    local function apply_home_preset(preset, touchmenu_instance)
        local preset_name = preset and preset.name
        HomePresets.applyHomePagePreset(dcfg, preset)
        dcfg.active_preset = preset_name
        PresetStore.setActivePreset("home", preset_name)
        ensure_cfg(config)
        save_home("reinit", { make_builtin_editable = false })
        if touchmenu_instance then touchmenu_instance:updateItems() end
    end

    local build_preset_items

    local function refresh_preset_menu(touchmenu_instance)
        if touchmenu_instance then
            touchmenu_instance.item_table = build_preset_items()
            touchmenu_instance:updateItems()
        end
    end

    local function show_rename_preset_dialog(preset_name, touchmenu_instance)
        if type(preset_name) ~= "string" or preset_name == "" then return end
        local InputDialog = require("ui/widget/inputdialog")
        local dlg
        dlg = InputDialog:new{
            title = _("Preset name"),
            input = preset_name,
            input_hint = _("Home page preset"),
            buttons = {{
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dlg) end,
                },
                {
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local name = dlg:getInputText()
                        if not name or name:match("^%s*$") then return end
                        name = name:match("^%s*(.-)%s*$")
                        if name == preset_name then
                            UIManager:close(dlg)
                            return
                        end
                        if HomePresets.isBuiltinPresetName(name) then
                            name = unique_user_preset_name(HomePresets.CUSTOM_PRESET_NAME)
                        elseif PresetStore.find("home", name) then
                            name = unique_user_preset_name(name)
                        end
                        local preset = PresetStore.find("home", preset_name)
                        if not preset then return end
                        if type(preset.home_page) == "table" then
                            preset.home_page.title = name
                        else
                            preset.title = name
                        end
                        UIManager:close(dlg)
                        PresetStore.save("home", name, preset)
                        PresetStore.delete("home", preset_name)
                        if dcfg.active_preset == preset_name then
                            dcfg.active_preset = name
                            dcfg.title = name
                            PresetStore.setActivePreset("home", name)
                            save_home("reinit")
                        end
                        refresh_preset_menu(touchmenu_instance)
                    end,
                },
            }},
        }
        UIManager:show(dlg)
        dlg:onShowKeyboard()
    end

    local function show_delete_preset_confirm(preset_name, touchmenu_instance)
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = _("Delete preset?") .. "\n\n" .. (preset_name or ""),
            ok_text = _("Delete"),
            ok_callback = function()
                PresetStore.delete("home", preset_name)
                if dcfg.active_preset == preset_name then
                    dcfg.active_preset = nil
                    PresetStore.setActivePreset("home", nil)
                end
                save_home("reinit")
                refresh_preset_menu(touchmenu_instance)
            end,
        })
    end

    function build_preset_items()
        local all = all_home_presets()
        local items = {}

        items[#items + 1] = {
            text = _("Save current home page as preset"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local InputDialog = require("ui/widget/inputdialog")
                local dlg
                dlg = InputDialog:new{
                    title = _("Preset name"),
                    input = "",
                    input_hint = _("Home page preset"),
                    buttons = {{
                        {
                            text = _("Cancel"),
                            id = "close",
                            callback = function() UIManager:close(dlg) end,
                        },
                        {
                            text = _("Save"),
                            is_enter_default = true,
                            callback = function()
                                local name = dlg:getInputText()
                                if not name or name:match("^%s*$") then return end
                                name = name:match("^%s*(.-)%s*$")
                                if HomePresets.isBuiltinPresetName(name) then
                                    name = unique_user_preset_name(HomePresets.CUSTOM_PRESET_NAME)
                                end
                                UIManager:close(dlg)
                                local state = HomePresets.captureHomePage(dcfg)
                                state.title = name
                                PresetStore.save("home", name, state)
                                dcfg.active_preset = name
                                PresetStore.setActivePreset("home", name)
                                save_home("reinit")
                                refresh_preset_menu(touchmenu_instance)
                            end,
                        },
                    }},
                }
                UIManager:show(dlg)
                dlg:onShowKeyboard()
            end,
            separator = #all > 0,
        }

        for i, preset in ipairs(all) do
            local preset_name = preset.name
            local is_builtin = preset.builtin == true
            items[#items + 1] = {
                text_func = function()
                    local prefix = dcfg.active_preset == preset_name and "* " or ""
                    return prefix .. (preset_name or _("Unnamed preset"))
                end,
                callback = function(touchmenu_instance)
                    apply_home_preset(preset, touchmenu_instance)
                end,
                hold_callback = not is_builtin and function(touchmenu_instance)
                    local ButtonDialog = require("ui/widget/buttondialog")
                    local dialog
                    dialog = ButtonDialog:new{
                        buttons = {
                            {{
                                text = _("Rename"),
                                callback = function()
                                    UIManager:close(dialog)
                                    show_rename_preset_dialog(preset_name, touchmenu_instance)
                                end,
                            }},
                            {{
                                text = _("Delete"),
                                callback = function()
                                    UIManager:close(dialog)
                                    show_delete_preset_confirm(preset_name, touchmenu_instance)
                                end,
                            }},
                        },
                    }
                    UIManager:show(dialog)
                end or nil,
                separator = i == #all or (is_builtin and all[i + 1] and all[i + 1].builtin ~= true),
            }
        end

        return items
    end

    local function build_goals_items()
        local goals_cfg = ensure_module_cfg(dcfg, "reading_goals")
        local items = {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return goals_cfg.show_module_title == true
                end,
                callback = function()
                    goals_cfg.show_module_title = goals_cfg.show_module_title ~= true
                    save_home("reinit")
                end,
            },
        }
        local shared_items = ReadingGoals.settingsItems(dcfg.goals, function()
            save_home("reinit")
        end)
        for _i, item in ipairs(shared_items) do items[#items + 1] = item end
        return items
    end

    local stats_field_options = {
        { id = "today_pages", text = "Pages today" },
        { id = "today_duration", text = "Read today" },
        { id = "streak", text = "Day streak" },
        { id = "week_pages", text = "Week pages" },
        { id = "week_duration", text = "Week time" },
    }

    local function build_stats_triplet_items()
        local stats_cfg = ensure_module_cfg(dcfg, "stats_triplet")
        local items = {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return stats_cfg.show_module_title == true
                end,
                callback = function()
                    stats_cfg.show_module_title = stats_cfg.show_module_title ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Stat separators"),
                sub_item_table = {
                    {
                        text = _("Dividing lines"),
                        radio = true,
                        checked_func = function()
                            return stats_cfg.stat_style ~= "outline" and stats_cfg.stat_style ~= "none"
                        end,
                        callback = function()
                            stats_cfg.stat_style = "divider"
                            save_home("reinit")
                        end,
                    },
                    {
                        text = _("Outlined boxes"),
                        radio = true,
                        checked_func = function()
                            return stats_cfg.stat_style == "outline"
                        end,
                        callback = function()
                            stats_cfg.stat_style = "outline"
                            save_home("reinit")
                        end,
                    },
                    {
                        text = _("None"),
                        radio = true,
                        checked_func = function()
                            return stats_cfg.stat_style == "none"
                        end,
                        callback = function()
                            stats_cfg.stat_style = "none"
                            save_home("reinit")
                        end,
                    },
                },
            },
        }
        for slot = 1, 3 do
            items[#items + 1] = {
                text_func = function()
                    local cur = dcfg.middle_stats_triplet[slot] or "today_pages"
                    return _("Stat slot ") .. tostring(slot) .. ": " .. cur
                end,
                sub_item_table = (function()
                    local slot_items = {}
                    for _i, opt in ipairs(stats_field_options) do
                        local oid = opt.id
                        slot_items[#slot_items + 1] = {
                            text = opt.text,
                            radio = true,
                            checked_func = function()
                                return (dcfg.middle_stats_triplet[slot] or "today_pages") == oid
                            end,
                            callback = function()
                                dcfg.middle_stats_triplet[slot] = oid
                                save_home("reinit")
                            end,
                        }
                    end
                    return slot_items
                end)(),
            }
        end
        return items
    end

    local function build_quotes_items()
        local quotes_cfg = ensure_module_cfg(dcfg, "quotes")
        return {
            {
                text = _("Show widget title"),
                checked_func = function()
                    return quotes_cfg.show_module_title == true
                end,
                callback = function()
                    quotes_cfg.show_module_title = quotes_cfg.show_module_title ~= true
                    save_home("reinit")
                end,
            },
            {
                text = _("Show author"),
                checked_func = function()
                    return dcfg.quotes.show_author ~= false
                end,
                callback = function()
                    dcfg.quotes.show_author = dcfg.quotes.show_author == false
                    save_home("reinit")
                end,
            },
        }
    end

    build_widget_settings_items = function(id)
        local items
        if id == "featured_custom" or id == "featured_tbr" or id == "featured_recent" then
            items = build_featured_widget_items(id)
        elseif id == "strip_custom" or id == "strip_tbr" or id == "strip_recent" then
            items = build_strip_widget_items(id)
        elseif id == "reading_goals" then
            items = build_goals_items()
        elseif id == "stats_triplet" then
            items = build_stats_triplet_items()
        elseif id == "quotes" then
            items = build_quotes_items()
        end
        if items then items._zen_arrange_done_func = function() end end
        return items
    end

    return {
        text = _("Home"),
        sub_item_table = {
            {
                text = _("Widgets") .. " \u{25B8}",
                keep_menu_open = true,
                callback = arrange_widgets,
            },
            {
                text = _("Presets"),
                sub_item_table_func = build_preset_items,
            },
            {
                text = _("Show top status bar"),
                checked_func = function()
                    return dcfg.show_status_bar ~= false
                end,
                callback = function()
                    dcfg.show_status_bar = dcfg.show_status_bar == false
                    save_home("reinit")
                end,
            },
            --[[
            {
                text = _("Settings"),
                sub_item_table = {
                    {
                        text = _("Show top status bar"),
                        checked_func = function()
                            return dcfg.show_status_bar ~= false
                        end,
                        callback = function()
                            dcfg.show_status_bar = dcfg.show_status_bar == false
                            save_home("reinit")
                        end,
                    },
                    {
                        text = _("Featured widgets"),
                        sub_item_table = {
                            {
                                text = _("Custom featured widget"),
                                sub_item_table_func = function() return build_featured_widget_items("featured_custom") end,
                            },
                            {
                                text = _("To Be Read featured widget"),
                                sub_item_table_func = function() return build_featured_widget_items("featured_tbr") end,
                            },
                            {
                                text = _("Recently read featured widget"),
                                sub_item_table_func = function() return build_featured_widget_items("featured_recent") end,
                            },
                        },
                    },
                    {
                        text = _("Strip widgets"),
                        sub_item_table = {
                            {
                                text = _("Custom strip widget"),
                                sub_item_table_func = function() return build_strip_widget_items("strip_custom") end,
                            },
                            {
                                text = _("To Be Read strip widget"),
                                sub_item_table_func = function() return build_strip_widget_items("strip_tbr") end,
                            },
                            {
                                text = _("Recently read strip widget"),
                                sub_item_table_func = function() return build_strip_widget_items("strip_recent") end,
                            },
                        },
                    },
                    {
                        text = _("Reading goals"),
                        sub_item_table_func = build_goals_items,
                    },
                    {
                        text = _("Reading stats widget"),
                        sub_item_table_func = build_stats_triplet_items,
                    },
                    {
                        text = _("Quotes widget"),
                        sub_item_table_func = build_quotes_items,
                    },
                },
            },
            ]]
        },
    }
end

return M

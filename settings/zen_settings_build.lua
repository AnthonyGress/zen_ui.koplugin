local _ = require("gettext")
local UIManager = require("ui/uimanager")
local Device = require("device")
local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")

local settings_apply = require("settings/zen_settings_apply")
local updater = require("settings/zen_updater")

local M = {}

local function get_path(tbl, path)
    local node = tbl
    for _, key in ipairs(path) do
        node = node and node[key]
    end
    return node
end

local function set_path(tbl, path, value)
    local node = tbl
    for i = 1, #path - 1 do
        local key = path[i]
        if type(node[key]) ~= "table" then
            node[key] = {}
        end
        node = node[key]
    end
    node[path[#path]] = value
end

function M.build(plugin)
    -- Lazy one-shot update check (cached; silent if offline or on failure).
    updater.check_for_update()

    local config = plugin.config

    local function first_non_empty(...)
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if type(v) == "string" and v ~= "" then
                return v
            end
        end
        return nil
    end

    local function get_plugin_version()
        local value = first_non_empty(
            plugin and plugin.version,
            plugin and plugin._meta and plugin._meta.version,
            config and config._meta and config._meta.version
        )
        if value then
            return value
        end

        local ok_meta, meta = pcall(require, "_meta")
        if ok_meta and type(meta) == "table" then
            value = first_non_empty(meta.version)
            if value then
                return value
            end
        end

        -- Reliable fallback: load _meta.lua directly from this plugin's root.
        local src = debug.getinfo(1, "S").source or ""
        if src:sub(1, 1) == "@" then
            local this_file = src:sub(2)
            local plugin_root = this_file:match("^(.*)/settings/zen_settings_build%.lua$")
            if plugin_root then
                local ok_file, file_meta = pcall(dofile, plugin_root .. "/_meta.lua")
                if ok_file and type(file_meta) == "table" then
                    value = first_non_empty(file_meta.version)
                    if value then
                        return value
                    end
                end
            end
        end

        return "dev"
    end

    local function get_koreader_version()
        local ok_version, version_mod = pcall(require, "version")
        if ok_version then
            if type(version_mod) == "string" and version_mod ~= "" then
                return version_mod
            end
            if type(version_mod) == "table" then
                local value = first_non_empty(
                    version_mod.version,
                    version_mod.short,
                    version_mod.git,
                    version_mod.git_rev,
                    version_mod.build,
                    version_mod.tag
                )
                if value then
                    return value
                end
            end
        end

        local value = first_non_empty(
            rawget(_G, "KOREADER_VERSION"),
            rawget(_G, "KO_VERSION"),
            rawget(_G, "GIT_REV")
        )
        return value or "unknown"
    end

    local function normalize_value(v)
        if type(v) == "number" then
            v = tostring(v)
        end
        if type(v) ~= "string" then
            return nil
        end
        v = v:match("^%s*(.-)%s*$")
        if v == "" then
            return nil
        end
        return v
    end

    local function get_device_model_name()
        local function call_device_method(name)
            if not (Device and type(Device[name]) == "function") then
                return nil
            end
            local ok, value = pcall(Device[name], Device)
            value = ok and normalize_value(value) or nil
            if value then
                return value
            end
            ok, value = pcall(Device[name])
            return ok and normalize_value(value) or nil
        end

        local value = normalize_value(first_non_empty(
            Device and Device.model,
            Device and Device.model_name,
            Device and Device.device_model,
            Device and Device.product,
            Device and Device.name,
            Device and Device.friendly_name,
            Device and Device.id,
            rawget(_G, "DEVICE_MODEL")
        ))
        if value then
            return value
        end

        value = call_device_method("getModel")
            or call_device_method("getModelName")
            or call_device_method("getDeviceModel")
            or call_device_method("getFriendlyName")
            or call_device_method("getDeviceName")
        if value then
            return value
        end

        if Device and Device.isAndroid and Device:isAndroid() then
            local ok_model, model = pcall(function()
                local pipe = io.popen("getprop ro.product.model 2>/dev/null")
                if not pipe then return nil end
                local out = pipe:read("*l")
                pipe:close()
                return normalize_value(out)
            end)
            local ok_mfr, mfr = pcall(function()
                local pipe = io.popen("getprop ro.product.manufacturer 2>/dev/null")
                if not pipe then return nil end
                local out = pipe:read("*l")
                pipe:close()
                return normalize_value(out)
            end)
            if ok_model and model then
                if ok_mfr and mfr and not model:lower():find(mfr:lower(), 1, true) then
                    return mfr .. " " .. model
                end
                return model
            end
        end

        return "Device"
    end

    local function get_kindle_firmware_info()
        if not (Device and Device.isKindle and Device:isKindle()) then
            return "n/a", nil, nil
        end

        local function normalize_fw_value(v)
            return normalize_value(v)
        end

        local function read_first_line(path)
            local f = io.open(path, "r")
            if not f then
                return nil
            end
            local line = f:read("*l")
            f:close()
            return normalize_fw_value(line)
        end

        if type(Device.getFirmwareVersion) == "function" then
            local calls = {
                function() return Device:getFirmwareVersion() end,
                function() return Device.getFirmwareVersion(Device) end,
                function() return Device.getFirmwareVersion() end,
            }
            for _, get_fw in ipairs(calls) do
                local ok, value = pcall(get_fw)
                value = ok and normalize_fw_value(value) or nil
                if value then
                    return value, "Device FW", "Device FW"
                end
            end
        end

        local value = first_non_empty(
            Device.firmware,
            Device.firmware_version,
            Device.firmware_rev,
            Device.fw_version,
            Device.fw,
            Device.softwareVersion,
            rawget(_G, "KINDLE_FIRMWARE_VERSION"),
            rawget(_G, "KINDLE_FW_VERSION")
        )

        value = normalize_fw_value(value)
        if value then
            return value, "Device FW", "Device FW"
        end

        -- Last-resort probes used by Kindle Linux images.
        value = read_first_line("/etc/prettyversion.txt")
        if value then
            return value, "prettyversion", "prettyversion"
        end

        value = read_first_line("/etc/version.txt")
        if value then
            return value, "version", "version"
        end

        return "unknown", "Device FW", "Device FW"
    end

    local function get_kindle_firmware_version()
        local fw, _source_label = get_kindle_firmware_info()
        return fw
    end

    local function get_kindle_firmware_display()
        local fw = get_kindle_firmware_version()
        if fw == "n/a" then
            return fw
        end
        return fw
    end

    local function apply_feature(feature)
        local enabled = get_path(config, { "features", feature }) == true
        settings_apply.apply_feature_toggle(plugin, feature, enabled)
    end

    local function save_and_apply(feature)
        plugin:saveConfig()
        apply_feature(feature)
    end

    local function save_and_apply_navbar()
        save_and_apply("navbar")
    end

    local function ensure_navbar_color()
        local c = config.navbar.active_tab_color
        if type(c) ~= "table" then
            c = { 0x33, 0x99, 0xFF }
            config.navbar.active_tab_color = c
        end
        c[1] = tonumber(c[1]) or 0x33
        c[2] = tonumber(c[2]) or 0x99
        c[3] = tonumber(c[3]) or 0xFF
        c[1] = math.max(0, math.min(255, c[1]))
        c[2] = math.max(0, math.min(255, c[2]))
        c[3] = math.max(0, math.min(255, c[3]))
        return c
    end

    local function set_navbar_color(r, g, b)
        config.navbar.active_tab_color = {
            math.max(0, math.min(255, tonumber(r) or 0)),
            math.max(0, math.min(255, tonumber(g) or 0)),
            math.max(0, math.min(255, tonumber(b) or 0)),
        }
    end

    local function get_home_dir()
        return G_reader_settings:readSetting("home_dir")
            or require("apps/filemanager/filemanagerutil").getDefaultDir()
    end

    local function get_last_dir()
        return G_reader_settings:readSetting("lastdir") or "/"
    end

    local function get_current_dir()
        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok and FileManager and FileManager.instance
        if fm and fm.file_chooser and fm.file_chooser.path then
            return fm.file_chooser.path
        end
        return get_last_dir()
    end

    local function save_and_apply_quick_settings()
        save_and_apply("quick_settings")
    end

    local function save_and_apply_status_bar()
        save_and_apply("status_bar")
    end

    local function make_enable_feature_item(feature, enable_text)
        return {
            text = enable_text,
            checked_func = function()
                return config.features[feature] == true
            end,
            callback = function()
                config.features[feature] = not (config.features[feature] == true)
                save_and_apply(feature)
            end,
        }
    end

    local function order_items_by_text(item_table, preferred_order)
        local by_text = {}
        local ordered = {}
        local used = {}

        for _, item in ipairs(item_table) do
            if type(item.text) == "string" and item.text ~= "" then
                if by_text[item.text] == nil then
                    by_text[item.text] = item
                end
            end
        end

        for _, text in ipairs(preferred_order) do
            local item = by_text[text]
            if item then
                table.insert(ordered, item)
                used[item] = true
            end
        end

        for _, item in ipairs(item_table) do
            if not used[item] then
                table.insert(ordered, item)
            end
        end

        return ordered
    end

    local function reorder_nested_items_by_text(item_table, target_text, preferred_order)
        for _, item in ipairs(item_table) do
            if item.text == target_text and type(item.sub_item_table) == "table" then
                item.sub_item_table = order_items_by_text(item.sub_item_table, preferred_order)
                return true
            end
            if type(item.sub_item_table) == "table" then
                local found = reorder_nested_items_by_text(item.sub_item_table, target_text, preferred_order)
                if found then
                    return true
                end
            end
        end
        return false
    end

    local filebrowser_items = {}
    local menu_items = {}
    local reader_items = {}
    local general_items = {}

    local navbar_tab_items = {
        { id = "books", text = _("Books") },
        { id = "manga", text = _("Manga") },
        { id = "news", text = _("News") },
        { id = "continue", text = _("Continue") },
        { id = "history", text = _("History") },
        { id = "favorites", text = _("Favorites") },
        { id = "collections", text = _("Collections") },
        { id = "exit", text = _("Exit") },
        { id = "page_left", text = _("Previous page") },
        { id = "page_right", text = _("Next page") },
        { id = "menu", text = _("Menu") },
    }

    local navbar_tab_toggle_items = {}
    for _, tab in ipairs(navbar_tab_items) do
        if tab.id ~= "books" then
            table.insert(navbar_tab_toggle_items, {
                text = tab.text,
                checked_func = function()
                    return config.navbar.show_tabs[tab.id] == true
                end,
                callback = function()
                    local current = config.navbar.show_tabs[tab.id] == true
                    config.navbar.show_tabs[tab.id] = not current
                    save_and_apply_navbar()
                end,
            })
        end
    end

    table.insert(filebrowser_items, {
        text = _("Navbar"),
        sub_item_table = {
            make_enable_feature_item("navbar", _("Enable bottom nav bar")),
            {
                text = _("Show labels"),
                checked_func = function() return config.navbar.show_labels == true end,
                callback = function()
                    config.navbar.show_labels = not (config.navbar.show_labels == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Show top border"),
                checked_func = function() return config.navbar.show_top_border == true end,
                callback = function()
                    config.navbar.show_top_border = not (config.navbar.show_top_border == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Show in standalone views"),
                checked_func = function() return config.navbar.show_in_standalone == true end,
                callback = function()
                    config.navbar.show_in_standalone = not (config.navbar.show_in_standalone == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Show top gap"),
                checked_func = function() return config.navbar.show_top_gap == true end,
                callback = function()
                    config.navbar.show_top_gap = not (config.navbar.show_top_gap == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Active tab styling"),
                checked_func = function() return config.navbar.active_tab_styling == true end,
                callback = function()
                    config.navbar.active_tab_styling = not (config.navbar.active_tab_styling == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Bold active tab"),
                checked_func = function() return config.navbar.active_tab_bold == true end,
                enabled_func = function() return config.navbar.active_tab_styling == true end,
                callback = function()
                    config.navbar.active_tab_bold = not (config.navbar.active_tab_bold == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Active tab underline"),
                checked_func = function() return config.navbar.active_tab_underline == true end,
                enabled_func = function() return config.navbar.active_tab_styling == true end,
                callback = function()
                    config.navbar.active_tab_underline = not (config.navbar.active_tab_underline == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Underline above icon"),
                checked_func = function() return config.navbar.underline_above == true end,
                enabled_func = function() return config.navbar.active_tab_styling == true and config.navbar.active_tab_underline == true end,
                callback = function()
                    config.navbar.underline_above = not (config.navbar.underline_above == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Colored active tab"),
                checked_func = function() return config.navbar.colored == true end,
                enabled_func = function() return config.navbar.active_tab_styling == true end,
                callback = function()
                    config.navbar.colored = not (config.navbar.colored == true)
                    save_and_apply_navbar()
                end,
            },
            {
                text_func = function()
                    local c = ensure_navbar_color()
                    return _("Active tab color: ") .. string.format("%d,%d,%d", c[1], c[2], c[3])
                end,
                enabled_func = function()
                    return config.navbar.active_tab_styling == true and config.navbar.colored == true
                end,
                sub_item_table = {
                    {
                        text = _("Blue"),
                        checked_func = function()
                            local c = ensure_navbar_color()
                            return c[1] == 0x33 and c[2] == 0x99 and c[3] == 0xFF
                        end,
                        callback = function()
                            set_navbar_color(0x33, 0x99, 0xFF)
                            save_and_apply_navbar()
                        end,
                    },
                    {
                        text = _("Green"),
                        checked_func = function()
                            local c = ensure_navbar_color()
                            return c[1] == 0x33 and c[2] == 0xAA and c[3] == 0x55
                        end,
                        callback = function()
                            set_navbar_color(0x33, 0xAA, 0x55)
                            save_and_apply_navbar()
                        end,
                    },
                    {
                        text = _("Amber"),
                        checked_func = function()
                            local c = ensure_navbar_color()
                            return c[1] == 0xFF and c[2] == 0xAA and c[3] == 0x00
                        end,
                        callback = function()
                            set_navbar_color(0xFF, 0xAA, 0x00)
                            save_and_apply_navbar()
                        end,
                    },
                    {
                        text = _("Red"),
                        checked_func = function()
                            local c = ensure_navbar_color()
                            return c[1] == 0xDD and c[2] == 0x33 and c[3] == 0x33
                        end,
                        callback = function()
                            set_navbar_color(0xDD, 0x33, 0x33)
                            save_and_apply_navbar()
                        end,
                    },
                    {
                        text_func = function()
                            local c = ensure_navbar_color()
                            return _("Custom RGB") .. " (" .. string.format("%d,%d,%d", c[1], c[2], c[3]) .. ")"
                        end,
                        keep_menu_open = true,
                        callback = function(touchmenu_instance)
                            local InputDialog = require("ui/widget/inputdialog")
                            local c = ensure_navbar_color()
                            local dlg
                            dlg = InputDialog:new{
                                title = _("Active tab RGB"),
                                input = string.format("%d,%d,%d", c[1], c[2], c[3]),
                                hint = _("Format: R,G,B (0-255)"),
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
                                            local text = dlg:getInputText() or ""
                                            local r, g, b = text:match("^%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
                                            if r and g and b then
                                                set_navbar_color(tonumber(r), tonumber(g), tonumber(b))
                                                UIManager:close(dlg)
                                                save_and_apply_navbar()
                                                if touchmenu_instance then
                                                    touchmenu_instance:updateItems()
                                                end
                                            end
                                        end,
                                    },
                                }},
                            }
                            UIManager:show(dlg)
                            dlg:onShowKeyboard()
                        end,
                    },
                },
            },
            {
                text = _("Tabs"),
                sub_item_table = {
                    {
                        text = _("Arrange tabs"),
                        keep_menu_open = true,
                        callback = function()
                            local SortWidget = require("ui/widget/sortwidget")
                            local sort_items = {}
                            for _, tab in ipairs(navbar_tab_items) do
                                local is_visible = tab.id == "books" or config.navbar.show_tabs[tab.id] == true
                                table.insert(sort_items, {
                                    text = tab.text,
                                    orig_item = tab.id,
                                    dim = not is_visible,
                                })
                            end
                            UIManager:show(SortWidget:new{
                                title = _("Arrange navbar tabs"),
                                item_table = sort_items,
                                callback = function()
                                    for i, item in ipairs(sort_items) do
                                        config.navbar.tab_order[i] = item.orig_item
                                    end
                                    save_and_apply_navbar()
                                end,
                            })
                        end,
                    },
                    {
                        text_func = function()
                            local label = config.navbar.books_label
                            if label == nil or label == "" then
                                label = "Books"
                            end
                            return _("Books tab label: ") .. label
                        end,
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Books"),
                                checked_func = function()
                                    return config.navbar.books_label == nil or config.navbar.books_label == "" or config.navbar.books_label == "Books"
                                end,
                                callback = function()
                                    config.navbar.books_label = "Books"
                                    save_and_apply_navbar()
                                end,
                            },
                            {
                                text = _("Home"),
                                checked_func = function() return config.navbar.books_label == "Home" end,
                                callback = function()
                                    config.navbar.books_label = "Home"
                                    save_and_apply_navbar()
                                end,
                            },
                            {
                                text = _("Library"),
                                checked_func = function() return config.navbar.books_label == "Library" end,
                                callback = function()
                                    config.navbar.books_label = "Library"
                                    save_and_apply_navbar()
                                end,
                            },
                            {
                                text_func = function()
                                    local label = config.navbar.books_label or ""
                                    local presets = { [""] = true, Books = true, Home = true, Library = true }
                                    if presets[label] then
                                        return _("Custom")
                                    end
                                    return _("Custom: ") .. label
                                end,
                                checked_func = function()
                                    local label = config.navbar.books_label or ""
                                    local presets = { [""] = true, Books = true, Home = true, Library = true }
                                    return not presets[label]
                                end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    local InputDialog = require("ui/widget/inputdialog")
                                    local dlg
                                    dlg = InputDialog:new{
                                        title = _("Books tab label"),
                                        input = config.navbar.books_label or "",
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
                                                    local text = dlg:getInputText()
                                                    config.navbar.books_label = text ~= "" and text or "Books"
                                                    UIManager:close(dlg)
                                                    save_and_apply_navbar()
                                                    if touchmenu_instance then
                                                        touchmenu_instance:updateItems()
                                                    end
                                                end,
                                            },
                                        }},
                                    }
                                    UIManager:show(dlg)
                                    dlg:onShowKeyboard()
                                end,
                            },
                        },
                    },
                    {
                        text_func = function()
                            if config.navbar.manga_action == "folder" then
                                return _("Manga tab action: ") .. _("Folder")
                            end
                            return _("Manga tab action: ") .. _("Rakuyomi")
                        end,
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Open Rakuyomi"),
                                checked_func = function() return config.navbar.manga_action ~= "folder" end,
                                callback = function()
                                    config.navbar.manga_action = "rakuyomi"
                                    save_and_apply_navbar()
                                end,
                            },
                            {
                                text_func = function()
                                    if config.navbar.manga_action == "folder" and config.navbar.manga_folder ~= "" then
                                        local util = require("util")
                                        local _dir, folder_name = util.splitFilePathName(config.navbar.manga_folder)
                                        return _("Open folder: ") .. folder_name
                                    end
                                    return _("Open folder")
                                end,
                                checked_func = function() return config.navbar.manga_action == "folder" end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    local PathChooser = require("ui/widget/pathchooser")
                                    local start_path = config.navbar.manga_folder ~= "" and config.navbar.manga_folder
                                        or G_reader_settings:readSetting("lastdir") or "/"
                                    local path_chooser = PathChooser:new{
                                        select_file = false,
                                        show_files = false,
                                        path = start_path,
                                        onConfirm = function(dir_path)
                                            config.navbar.manga_action = "folder"
                                            config.navbar.manga_folder = dir_path
                                            save_and_apply_navbar()
                                            if touchmenu_instance then
                                                touchmenu_instance:updateItems()
                                            end
                                        end,
                                    }
                                    UIManager:show(path_chooser)
                                end,
                            },
                            {
                                text = _("Folder presets"),
                                sub_item_table = {
                                    {
                                        text = _("Use home folder"),
                                        callback = function()
                                            config.navbar.manga_action = "folder"
                                            config.navbar.manga_folder = get_home_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                    {
                                        text = _("Use last folder"),
                                        callback = function()
                                            config.navbar.manga_action = "folder"
                                            config.navbar.manga_folder = get_last_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                    {
                                        text = _("Use current folder"),
                                        callback = function()
                                            config.navbar.manga_action = "folder"
                                            config.navbar.manga_folder = get_current_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                },
                            },
                        },
                    },
                    {
                        text_func = function()
                            if config.navbar.news_action == "folder" then
                                return _("News tab action: ") .. _("Folder")
                            end
                            return _("News tab action: ") .. _("QuickRSS")
                        end,
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Open QuickRSS"),
                                checked_func = function() return config.navbar.news_action ~= "folder" end,
                                callback = function()
                                    config.navbar.news_action = "quickrss"
                                    save_and_apply_navbar()
                                end,
                            },
                            {
                                text_func = function()
                                    if config.navbar.news_action == "folder" and config.navbar.news_folder ~= "" then
                                        local util = require("util")
                                        local _dir, folder_name = util.splitFilePathName(config.navbar.news_folder)
                                        return _("Open folder: ") .. folder_name
                                    end
                                    return _("Open folder")
                                end,
                                checked_func = function() return config.navbar.news_action == "folder" end,
                                keep_menu_open = true,
                                callback = function(touchmenu_instance)
                                    local PathChooser = require("ui/widget/pathchooser")
                                    local start_path = config.navbar.news_folder ~= "" and config.navbar.news_folder
                                        or G_reader_settings:readSetting("lastdir") or "/"
                                    local path_chooser = PathChooser:new{
                                        select_file = false,
                                        show_files = false,
                                        path = start_path,
                                        onConfirm = function(dir_path)
                                            config.navbar.news_action = "folder"
                                            config.navbar.news_folder = dir_path
                                            save_and_apply_navbar()
                                            if touchmenu_instance then
                                                touchmenu_instance:updateItems()
                                            end
                                        end,
                                    }
                                    UIManager:show(path_chooser)
                                end,
                            },
                            {
                                text = _("Folder presets"),
                                sub_item_table = {
                                    {
                                        text = _("Use home folder"),
                                        callback = function()
                                            config.navbar.news_action = "folder"
                                            config.navbar.news_folder = get_home_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                    {
                                        text = _("Use last folder"),
                                        callback = function()
                                            config.navbar.news_action = "folder"
                                            config.navbar.news_folder = get_last_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                    {
                                        text = _("Use current folder"),
                                        callback = function()
                                            config.navbar.news_action = "folder"
                                            config.navbar.news_folder = get_current_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                },
                            },
                        },
                    },
                    {
                        text = _("Visibility"),
                        sub_item_table = navbar_tab_toggle_items,
                    },
                },
            },
            {
                text = _("Refresh navbar"),
                keep_menu_open = true,
                callback = function()
                    apply_feature("navbar")
                end,
            },
        },
    })

    local quick_button_items = {
        { key = "wifi", text = _("Wi-Fi") },
        { key = "night", text = _("Night mode") },
        { key = "rotate", text = _("Rotate") },
        { key = "usb", text = _("USB") },
        { key = "search", text = _("File search") },
        { key = "quickrss", text = _("QuickRSS") },
        { key = "cloud", text = _("Cloud storage") },
        { key = "zlibrary", text = _("Z-Library") },
        { key = "calibre", text = _("Calibre") },
        { key = "notion", text = _("Notion") },
        { key = "streak", text = _("Streak") },
        { key = "opds", text = _("OPDS") },
        { key = "filebrowser", text = _("Filebrowser") },
        { key = "restart", text = _("Restart") },
        { key = "exit", text = _("Exit") },
        { key = "sleep", text = _("Sleep") },
    }

    local quick_button_label_by_id = {}
    for _, quick_item in ipairs(quick_button_items) do
        quick_button_label_by_id[quick_item.key] = quick_item.text
    end

    local quick_button_sub_items = {}

    table.insert(quick_button_sub_items, {
        text = _("Arrange buttons"),
        keep_menu_open = true,
        separator = true,
        callback = function()
            local SortWidget = require("ui/widget/sortwidget")
            local sort_items = {}
            for _, id in ipairs(config.quick_settings.button_order) do
                local label = quick_button_label_by_id[id]
                if label then
                    table.insert(sort_items, {
                        text = label,
                        orig_item = id,
                        dim = not (config.quick_settings.show_buttons[id] == true),
                    })
                end
            end

            UIManager:show(SortWidget:new{
                title = _("Arrange quick settings buttons"),
                item_table = sort_items,
                callback = function()
                    for i, item in ipairs(sort_items) do
                        config.quick_settings.button_order[i] = item.orig_item
                    end
                    save_and_apply_quick_settings()
                end,
            })
        end,
    })

    for _, quick_item in ipairs(quick_button_items) do
        table.insert(quick_button_sub_items, {
            text = quick_item.text,
            checked_func = function()
                return config.quick_settings.show_buttons[quick_item.key] == true
            end,
            callback = function()
                local current = config.quick_settings.show_buttons[quick_item.key] == true
                config.quick_settings.show_buttons[quick_item.key] = not current
                save_and_apply_quick_settings()
            end,
        })
    end

    table.insert(menu_items, {
        text = _("Quick settings"),
        sub_item_table = {
            make_enable_feature_item("quick_settings", _("Enable quick settings panel")),
            {
                text = _("Show frontlight slider"),
                checked_func = function() return config.quick_settings.show_frontlight == true end,
                callback = function()
                    config.quick_settings.show_frontlight = not (config.quick_settings.show_frontlight == true)
                    save_and_apply_quick_settings()
                end,
            },
            {
                text = _("Show warmth slider"),
                checked_func = function() return config.quick_settings.show_warmth == true end,
                callback = function()
                    config.quick_settings.show_warmth = not (config.quick_settings.show_warmth == true)
                    save_and_apply_quick_settings()
                end,
            },
            {
                text = _("Always open on this tab"),
                checked_func = function() return config.quick_settings.open_on_start == true end,
                callback = function()
                    config.quick_settings.open_on_start = not (config.quick_settings.open_on_start == true)
                    save_and_apply_quick_settings()
                end,
            },
            {
                text = _("Buttons"),
                sub_item_table = quick_button_sub_items,
            },
        },
    })

    table.insert(filebrowser_items, {
        text = _("Status bar"),
        sub_item_table = {
            make_enable_feature_item("status_bar", _("Enable custom status bar")),
            {
                text_func = function()
                    local name = config.status_bar.custom_text
                    if name == nil or name == "" then
                        name = Device.model or ""
                    end
                    return _("Custom text: ") .. name
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local InputDialog = require("ui/widget/inputdialog")
                    local dlg
                    dlg = InputDialog:new{
                        title = _("Custom text"),
                        input = config.status_bar.custom_text or "",
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
                                    config.status_bar.custom_text = dlg:getInputText()
                                    UIManager:close(dlg)
                                    save_and_apply_status_bar()
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            },
                        }},
                    }
                    UIManager:show(dlg)
                    dlg:onShowKeyboard()
                end,
            },
            {
                text = _("Show time"),
                checked_func = function() return config.status_bar.show_time == true end,
                callback = function()
                    config.status_bar.show_time = not (config.status_bar.show_time == true)
                    save_and_apply_status_bar()
                end,
            },
            {
                text = _("12-hour time"),
                checked_func = function() return config.status_bar.time_12h == true end,
                enabled_func = function() return config.status_bar.show_time == true end,
                callback = function()
                    config.status_bar.time_12h = not (config.status_bar.time_12h == true)
                    save_and_apply_status_bar()
                end,
            },
            {
                text = _("Show bottom border"),
                checked_func = function() return config.status_bar.show_bottom_border == true end,
                callback = function()
                    config.status_bar.show_bottom_border = not (config.status_bar.show_bottom_border == true)
                    save_and_apply_status_bar()
                end,
            },
            {
                text = _("Bold text"),
                checked_func = function() return config.status_bar.bold_text == true end,
                callback = function()
                    config.status_bar.bold_text = not (config.status_bar.bold_text == true)
                    save_and_apply_status_bar()
                end,
            },
            {
                text = _("Colored status icons"),
                checked_func = function() return config.status_bar.colored == true end,
                callback = function()
                    config.status_bar.colored = not (config.status_bar.colored == true)
                    save_and_apply_status_bar()
                end,
            },
            {
                text = _("Items"),
                sub_item_table = {
                    {
                        text = _("Arrange items"),
                        keep_menu_open = true,
                        separator = true,
                        callback = function()
                            local SortWidget = require("ui/widget/sortwidget")
                            local status_bar_items = {
                                wifi = _("WiFi"),
                                disk = _("Disk space"),
                                ram = _("RAM usage"),
                                frontlight = _("Frontlight"),
                                battery = _("Battery"),
                            }
                            local sort_items = {}
                            for _, key in ipairs(config.status_bar.order) do
                                if status_bar_items[key] then
                                    table.insert(sort_items, {
                                        text = status_bar_items[key],
                                        orig_item = key,
                                        dim = not (config.status_bar.show[key] == true),
                                    })
                                end
                            end

                            UIManager:show(SortWidget:new{
                                title = _("Arrange status bar items"),
                                item_table = sort_items,
                                callback = function()
                                    for i, item in ipairs(sort_items) do
                                        config.status_bar.order[i] = item.orig_item
                                    end
                                    save_and_apply_status_bar()
                                end,
                            })
                        end,
                    },
                    {
                        text = _("Show WiFi"),
                        checked_func = function() return config.status_bar.show.wifi == true end,
                        callback = function()
                            config.status_bar.show.wifi = not (config.status_bar.show.wifi == true)
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Show disk space"),
                        checked_func = function() return config.status_bar.show.disk == true end,
                        callback = function()
                            config.status_bar.show.disk = not (config.status_bar.show.disk == true)
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Show RAM usage"),
                        checked_func = function() return config.status_bar.show.ram == true end,
                        callback = function()
                            config.status_bar.show.ram = not (config.status_bar.show.ram == true)
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Show frontlight"),
                        checked_func = function() return config.status_bar.show.frontlight == true end,
                        callback = function()
                            config.status_bar.show.frontlight = not (config.status_bar.show.frontlight == true)
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Show battery"),
                        checked_func = function() return config.status_bar.show.battery == true end,
                        callback = function()
                            config.status_bar.show.battery = not (config.status_bar.show.battery == true)
                            save_and_apply_status_bar()
                        end,
                    },
                },
            },
            {
                text_func = function()
                    local separator_label = {
                        dot = _("Middle dot"),
                        bar = _("Vertical bar"),
                        dash = _("Dash"),
                        bullet = _("Bullet"),
                        space = _("Space only"),
                        ["small-space"] = _("Space only (small)"),
                        none = _("No separator"),
                        custom = _("Custom"),
                    }
                    local key = config.status_bar.separator_key or "dot"
                    return _("Separator: ") .. (separator_label[key] or key)
                end,
                sub_item_table = {
                    {
                        text = _("Middle dot") .. "  '  ·  '",
                        checked_func = function() return config.status_bar.separator_key == "dot" end,
                        callback = function()
                            config.status_bar.separator_key = "dot"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Vertical bar") .. "  '  |  '",
                        checked_func = function() return config.status_bar.separator_key == "bar" end,
                        callback = function()
                            config.status_bar.separator_key = "bar"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Dash") .. "  '  -  '",
                        checked_func = function() return config.status_bar.separator_key == "dash" end,
                        callback = function()
                            config.status_bar.separator_key = "dash"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Bullet") .. "  '  •  '",
                        checked_func = function() return config.status_bar.separator_key == "bullet" end,
                        callback = function()
                            config.status_bar.separator_key = "bullet"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Space only") .. "  '   '",
                        checked_func = function() return config.status_bar.separator_key == "space" end,
                        callback = function()
                            config.status_bar.separator_key = "space"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Space only (small)") .. "  ' '",
                        checked_func = function() return config.status_bar.separator_key == "small-space" end,
                        callback = function()
                            config.status_bar.separator_key = "small-space"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("No separator"),
                        checked_func = function() return config.status_bar.separator_key == "none" end,
                        callback = function()
                            config.status_bar.separator_key = "none"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text_func = function()
                            return _("Custom") .. "  '" .. (config.status_bar.custom_separator or "") .. "'"
                        end,
                        checked_func = function() return config.status_bar.separator_key == "custom" end,
                        callback = function(touchmenu_instance)
                            local InputDialog = require("ui/widget/inputdialog")
                            local dlg
                            dlg = InputDialog:new{
                                title = _("Custom separator"),
                                input = config.status_bar.custom_separator or "",
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
                                            config.status_bar.custom_separator = dlg:getInputText()
                                            config.status_bar.separator_key = "custom"
                                            UIManager:close(dlg)
                                            save_and_apply_status_bar()
                                            if touchmenu_instance then
                                                touchmenu_instance:updateItems()
                                            end
                                        end,
                                    },
                                }},
                            }
                            UIManager:show(dlg)
                            dlg:onShowKeyboard()
                        end,
                    },
                },
            },
        },
    })

    table.insert(filebrowser_items, {
        text = _("Folders"),
        sub_item_table = {
            {
                text = _("Hide up folder"),
                checked_func = function() return config.browser_hide_up_folder.hide_up_folder == true end,
                callback = function()
                    config.browser_hide_up_folder.hide_up_folder = not (config.browser_hide_up_folder.hide_up_folder == true)
                    save_and_apply("browser_hide_up_folder")
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
                            -- "centered" is the default (nil); only toggle if currently set to true
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
                            -- "bottom" is stored as true; only toggle if currently nil
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

    table.insert(filebrowser_items, {
        text = _("Show item underline"),
        checked_func = function()
            return config.features.browser_hide_underline ~= true
        end,
        callback = function()
            config.features.browser_hide_underline = not (config.features.browser_hide_underline == true)
            save_and_apply("browser_hide_underline")
        end,
    })

    table.insert(filebrowser_items, make_enable_feature_item(
        "zen_pagination_bar",
        _("Zen pagination bar")
    ))

    table.insert(filebrowser_items, {
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
    })

    table.insert(filebrowser_items, {
        text = _("Rounded corners on mosaic covers"),
        checked_func = function()
            return type(config.features) == "table"
                and config.features.browser_cover_rounded_corners == true
        end,
        callback = function()
            if type(config.features) ~= "table" then
                config.features = {}
            end
            config.features.browser_cover_rounded_corners =
                not (config.features.browser_cover_rounded_corners == true)
            plugin:saveConfig()
            UIManager:setDirty(nil, "full")
        end,
    })

    table.insert(filebrowser_items, {
        text = _("Allow delete in context menu"),
        checked_func = function()
            return type(config.context_menu) == "table"
                and config.context_menu.allow_delete == true
        end,
        callback = function()
            if type(config.context_menu) ~= "table" then
                config.context_menu = {}
            end
            config.context_menu.allow_delete = not (config.context_menu.allow_delete == true)
            plugin:saveConfig()
        end,
    })

    -- Display mode
    local display_modes = {
        { text = _("Classic (filename only)"),                          mode = "classic"            },
        { text = _("Mosaic with cover images"),                         mode = "mosaic_image"       },
        { text = _("Mosaic with text"),                                 mode = "mosaic_text"        },
        { text = _("Detailed list with cover images and metadata"),     mode = "list_image_meta"    },
        { text = _("Detailed list with metadata, no images"),           mode = "list_only_meta"     },
        { text = _("Detailed list with cover images and filenames"),    mode = "list_image_filename"},
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
            checked_func = function()
                return get_display_mode() == entry.mode
            end,
            radio = true,
            callback = function()
                apply_display_mode(entry.mode)
            end,
        })
    end

    table.insert(filebrowser_items, {
        text = _("Display mode"),
        sub_item_table = display_mode_sub_items,
    })

    -- Items per page (mosaic portrait / landscape, list mode)
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

        table.insert(filebrowser_items, {
            text = _("Items per page"),
            sub_item_table = {
                {
                    text_func = function()
                        local bim = get_bim()
                        local fc = get_fc()
                        local c = (fc and fc.nb_cols_portrait) or (bim and bim:getSetting("nb_cols_portrait")) or 3
                        local r = (fc and fc.nb_rows_portrait) or (bim and bim:getSetting("nb_rows_portrait")) or 3
                        return _("Portrait mosaic: ") .. c .. "×" .. r
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
                        return _("Landscape mosaic: ") .. c .. "×" .. r
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

    -- Sort by
    local collate_options = {
        { key = "strcoll",                text = _("name")                              },
        { key = "natural",                text = _("name (natural sorting)")            },
        { key = "access",                 text = _("last read date")                    },
        { key = "date",                   text = _("date modified")                     },
        { key = "size",                   text = _("size")                              },
        { key = "type",                   text = _("type")                              },
        { key = "percent_unopened_first", text = _("percent - unopened first")          },
        { key = "percent_unopened_last",  text = _("percent - unopened last")           },
        { key = "percent_natural",        text = _("percent - unopened - finished last")                    },
        { key = "title",                  text = _("Title")                             },
        { key = "authors",                text = _("Authors")                           },
        { key = "series",                 text = _("Series")                            },
        { key = "keywords",               text = _("Keywords"),        separator = true },
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
            checked_func = function()
                return get_current_collate() == option.key
            end,
            radio = true,
            callback = function()
                apply_sort_by(option.key)
            end,
        })
    end
    table.insert(collate_sub_items, {
        text = _("Reverse sorting"),
        checked_func = function()
            return G_reader_settings:isTrue("reverse_collate")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("reverse_collate")
            refresh_filechooser()
        end,
    })
    table.insert(collate_sub_items, {
        text = _("Folders and files mixed"),
        checked_func = function()
            return G_reader_settings:isTrue("collate_mixed")
        end,
        callback = function()
            G_reader_settings:flipNilOrFalse("collate_mixed")
            refresh_filechooser()
        end,
    })

    table.insert(filebrowser_items, {
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

    table.insert(reader_items, {
        text = _("Reader clock"),
        sub_item_table = {
            make_enable_feature_item("reader_clock", _("Enable reader clock")),
            {
                text = _("Use 24-hour time"),
                checked_func = function()
                    return config.reader_clock and config.reader_clock.use_24h == true
                end,
                callback = function()
                    if type(config.reader_clock) ~= "table" then config.reader_clock = {} end
                    config.reader_clock.use_24h = not (config.reader_clock.use_24h == true)
                    save_and_apply("reader_clock")
                end,
            },
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
        },
    })

    table.insert(reader_items, make_enable_feature_item(
        "reader_bottom_menu", _("Enable bottom menu")))

    table.insert(reader_items, {
        text = _("Verbose time to chapter end"),
        checked_func = function()
            return type(config.reader_footer) == "table"
                and config.reader_footer.verbose_chapter_time == true
        end,
        callback = function()
            if type(config.reader_footer) ~= "table" then
                config.reader_footer = {}
            end
            config.reader_footer.verbose_chapter_time = not (config.reader_footer.verbose_chapter_time == true)
            plugin:saveConfig()
        end,
    })

    -- -------------------------------------------------------------------------
    -- Global scheduler helpers
    -- -------------------------------------------------------------------------

    local function fmt_time(h, m)
        return string.format("%02d:%02d", h, m)
    end

    local function show_time_picker(title, h, m, callback)
        UIManager:show(require("ui/widget/doublespinwidget"):new{
            title_text      = title,
            left_text       = _("Hour"),
            left_value      = h,
            left_min        = 0,
            left_max        = 23,
            left_step       = 1,
            left_hold_step  = 3,
            left_precision  = "%02d",
            right_text      = _("Minute"),
            right_value     = m,
            right_min       = 0,
            right_max       = 59,
            right_step      = 1,
            right_hold_step = 15,
            right_precision = "%02d",
            callback        = callback,
        })
    end

    local function show_value_picker(title, value, callback)
        UIManager:show(require("ui/widget/spinwidget"):new{
            title_text      = title,
            value           = value,
            value_min       = 0,
            value_max       = 24,
            value_step      = 1,
            value_hold_step = 4,
            callback        = function(spin) callback(spin.value) end,
        })
    end

    -- -------------------------------------------------------------------------
    -- Night mode schedule
    -- -------------------------------------------------------------------------

    local function get_night_schedule_config()
        if type(config.night_mode_schedule) ~= "table" then
            config.night_mode_schedule = {}
        end
        local cfg = config.night_mode_schedule
        return {
            night_on_h  = tonumber(cfg.night_on_h)  or 22,
            night_on_m  = tonumber(cfg.night_on_m)  or 0,
            night_off_h = tonumber(cfg.night_off_h) or 7,
            night_off_m = tonumber(cfg.night_off_m) or 0,
        }
    end

    local function trigger_night_schedule_reschedule()
        local sched = rawget(_G, "__ZEN_UI_NIGHT_SCHEDULE")
        if sched and type(sched.reschedule) == "function" then
            sched.reschedule()
        end
    end

    -- -------------------------------------------------------------------------
    -- Warmth schedule
    -- -------------------------------------------------------------------------

    local function get_warmth_schedule_config()
        if type(config.warmth_schedule) ~= "table" then
            config.warmth_schedule = {}
        end
        local cfg = config.warmth_schedule
        return {
            day_h       = tonumber(cfg.day_h)       or 7,
            day_m       = tonumber(cfg.day_m)       or 0,
            day_value   = tonumber(cfg.day_value)   or 30,
            night_h     = tonumber(cfg.night_h)     or 20,
            night_m     = tonumber(cfg.night_m)     or 0,
            night_value = tonumber(cfg.night_value) or 80,
        }
    end

    local function trigger_warmth_schedule_reschedule()
        local sched = rawget(_G, "__ZEN_UI_WARMTH_SCHEDULE")
        if sched and type(sched.reschedule) == "function" then
            sched.reschedule()
        end
    end

    -- -------------------------------------------------------------------------
    -- Brightness schedule
    -- -------------------------------------------------------------------------

    local function get_brightness_schedule_config()
        if type(config.brightness_schedule) ~= "table" then
            config.brightness_schedule = {}
        end
        local cfg = config.brightness_schedule
        return {
            day_h       = tonumber(cfg.day_h)       or 7,
            day_m       = tonumber(cfg.day_m)       or 0,
            day_value   = tonumber(cfg.day_value)   or 80,
            night_h     = tonumber(cfg.night_h)     or 20,
            night_m     = tonumber(cfg.night_m)     or 0,
            night_value = tonumber(cfg.night_value) or 20,
        }
    end

    local function trigger_brightness_schedule_reschedule()
        local sched = rawget(_G, "__ZEN_UI_BRIGHTNESS_SCHEDULE")
        if sched and type(sched.reschedule) == "function" then
            sched.reschedule()
        end
    end

    -- -------------------------------------------------------------------------
    -- Global items table
    -- -------------------------------------------------------------------------

    local global_items = {}

    table.insert(global_items, {
        text = _("Night mode schedule"),
        sub_item_table = {
            {
                text = _("Enable night mode schedule"),
                checked_func = function()
                    return config.features.night_mode_schedule == true
                end,
                callback = function()
                    config.features.night_mode_schedule = not (config.features.night_mode_schedule == true)
                    plugin:saveConfig()
                    trigger_night_schedule_reschedule()
                end,
            },
            {
                text_func = function()
                    local cfg = get_night_schedule_config()
                    return _("Night mode on: ") .. fmt_time(cfg.night_on_h, cfg.night_on_m)
                end,
                enabled_func = function()
                    return config.features.night_mode_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_night_schedule_config()
                    show_time_picker(_("Night mode on time"), cfg.night_on_h, cfg.night_on_m,
                        function(h, m)
                            if type(config.night_mode_schedule) ~= "table" then
                                config.night_mode_schedule = {}
                            end
                            config.night_mode_schedule.night_on_h = h
                            config.night_mode_schedule.night_on_m = m
                            plugin:saveConfig()
                            trigger_night_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_night_schedule_config()
                    return _("Night mode off: ") .. fmt_time(cfg.night_off_h, cfg.night_off_m)
                end,
                enabled_func = function()
                    return config.features.night_mode_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_night_schedule_config()
                    show_time_picker(_("Night mode off time"), cfg.night_off_h, cfg.night_off_m,
                        function(h, m)
                            if type(config.night_mode_schedule) ~= "table" then
                                config.night_mode_schedule = {}
                            end
                            config.night_mode_schedule.night_off_h = h
                            config.night_mode_schedule.night_off_m = m
                            plugin:saveConfig()
                            trigger_night_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
        },
    })

    table.insert(global_items, {
        text = _("Brightness schedule"),
        sub_item_table = {
            {
                text = _("Enable brightness schedule"),
                checked_func = function()
                    return config.features.brightness_schedule == true
                end,
                callback = function()
                    config.features.brightness_schedule = not (config.features.brightness_schedule == true)
                    plugin:saveConfig()
                    trigger_brightness_schedule_reschedule()
                end,
            },
            {
                text_func = function()
                    local cfg = get_brightness_schedule_config()
                    return _("Day brightness time: ") .. fmt_time(cfg.day_h, cfg.day_m)
                end,
                enabled_func = function()
                    return config.features.brightness_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_brightness_schedule_config()
                    show_time_picker(_("Day brightness time"), cfg.day_h, cfg.day_m,
                        function(h, m)
                            if type(config.brightness_schedule) ~= "table" then
                                config.brightness_schedule = {}
                            end
                            config.brightness_schedule.day_h = h
                            config.brightness_schedule.day_m = m
                            plugin:saveConfig()
                            trigger_brightness_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_brightness_schedule_config()
                    return _("Day brightness: ") .. cfg.day_value
                end,
                enabled_func = function()
                    return config.features.brightness_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_brightness_schedule_config()
                    show_value_picker(_("Day brightness"), cfg.day_value,
                        function(v)
                            if type(config.brightness_schedule) ~= "table" then
                                config.brightness_schedule = {}
                            end
                            config.brightness_schedule.day_value = v
                            plugin:saveConfig()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_brightness_schedule_config()
                    return _("Night brightness time: ") .. fmt_time(cfg.night_h, cfg.night_m)
                end,
                enabled_func = function()
                    return config.features.brightness_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_brightness_schedule_config()
                    show_time_picker(_("Night brightness time"), cfg.night_h, cfg.night_m,
                        function(h, m)
                            if type(config.brightness_schedule) ~= "table" then
                                config.brightness_schedule = {}
                            end
                            config.brightness_schedule.night_h = h
                            config.brightness_schedule.night_m = m
                            plugin:saveConfig()
                            trigger_brightness_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_brightness_schedule_config()
                    return _("Night brightness: ") .. cfg.night_value
                end,
                enabled_func = function()
                    return config.features.brightness_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_brightness_schedule_config()
                    show_value_picker(_("Night brightness"), cfg.night_value,
                        function(v)
                            if type(config.brightness_schedule) ~= "table" then
                                config.brightness_schedule = {}
                            end
                            config.brightness_schedule.night_value = v
                            plugin:saveConfig()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
        },
    })

    table.insert(global_items, {
        text = _("Warmth schedule"),
        enabled_func = function() return Device:hasNaturalLight() end,
        sub_item_table = {
            {
                text = _("Enable warmth schedule"),
                checked_func = function()
                    return config.features.warmth_schedule == true
                end,
                callback = function()
                    config.features.warmth_schedule = not (config.features.warmth_schedule == true)
                    plugin:saveConfig()
                    trigger_warmth_schedule_reschedule()
                end,
            },
            {
                text_func = function()
                    local cfg = get_warmth_schedule_config()
                    return _("Day warmth time: ") .. fmt_time(cfg.day_h, cfg.day_m)
                end,
                enabled_func = function()
                    return config.features.warmth_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_warmth_schedule_config()
                    show_time_picker(_("Day warmth time"), cfg.day_h, cfg.day_m,
                        function(h, m)
                            if type(config.warmth_schedule) ~= "table" then
                                config.warmth_schedule = {}
                            end
                            config.warmth_schedule.day_h = h
                            config.warmth_schedule.day_m = m
                            plugin:saveConfig()
                            trigger_warmth_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_warmth_schedule_config()
                    return _("Day warmth: ") .. cfg.day_value
                end,
                enabled_func = function()
                    return config.features.warmth_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_warmth_schedule_config()
                    show_value_picker(_("Day warmth"), cfg.day_value,
                        function(v)
                            if type(config.warmth_schedule) ~= "table" then
                                config.warmth_schedule = {}
                            end
                            config.warmth_schedule.day_value = v
                            plugin:saveConfig()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_warmth_schedule_config()
                    return _("Night warmth time: ") .. fmt_time(cfg.night_h, cfg.night_m)
                end,
                enabled_func = function()
                    return config.features.warmth_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_warmth_schedule_config()
                    show_time_picker(_("Night warmth time"), cfg.night_h, cfg.night_m,
                        function(h, m)
                            if type(config.warmth_schedule) ~= "table" then
                                config.warmth_schedule = {}
                            end
                            config.warmth_schedule.night_h = h
                            config.warmth_schedule.night_m = m
                            plugin:saveConfig()
                            trigger_warmth_schedule_reschedule()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
            {
                text_func = function()
                    local cfg = get_warmth_schedule_config()
                    return _("Night warmth: ") .. cfg.night_value
                end,
                enabled_func = function()
                    return config.features.warmth_schedule == true
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local cfg = get_warmth_schedule_config()
                    show_value_picker(_("Night warmth"), cfg.night_value,
                        function(v)
                            if type(config.warmth_schedule) ~= "table" then
                                config.warmth_schedule = {}
                            end
                            config.warmth_schedule.night_value = v
                            plugin:saveConfig()
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end)
                end,
            },
        },
    })

    table.insert(general_items, updater.build_update_now_item(plugin))

    table.insert(general_items, {
        text = _("Developer"),
        sub_item_table = {
            {
                text = _("Show hidden and unsupported files outside home folder"),
                checked_func = function()
                    return type(config.developer) == "table"
                        and config.developer.show_hidden_outside_home == true
                end,
                callback = function()
                    if type(config.developer) ~= "table" then
                        config.developer = {}
                    end
                    local enabling = not (config.developer.show_hidden_outside_home == true)
                    config.developer.show_hidden_outside_home = enabling
                    plugin:saveConfig()

                    -- Set initial G_reader_settings state based on current directory
                    if enabling then
                        -- When enabling, check current directory and set appropriately
                        local current_dir = get_current_dir()
                        local home_dir = get_home_dir()
                        local is_outside_home = current_dir ~= home_dir
                            and current_dir:sub(1, #home_dir + 1) ~= home_dir .. "/"
                        G_reader_settings:saveSetting("show_hidden", is_outside_home)
                        G_reader_settings:saveSetting("show_unsupported", is_outside_home)
                    else
                        -- When disabling, always hide hidden files and unsupported files
                        G_reader_settings:saveSetting("show_hidden", false)
                        G_reader_settings:saveSetting("show_unsupported", false)
                        local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
                        local fm = ok and FileManager and FileManager.instance
                        if fm and fm.file_chooser then
                            fm.file_chooser.show_hidden = false
                            fm.file_chooser.show_unsupported = false
                            fm.file_chooser:refreshPath()
                        end
                    end

                    -- Defer ConfirmBox to avoid button dimension race condition
                    UIManager:nextTick(function()
                        settings_apply.prompt_restart()
                    end)
                end,
                keep_menu_open = true,
            },
        },
    })

    table.insert(general_items, {
        text_func = function()
            return _("Zen UI: ") .. get_plugin_version()
        end,
        keep_menu_open = true,
    })
    table.insert(general_items, {
        text_func = function()
            return _("KOReader: ") .. get_koreader_version()
        end,
        keep_menu_open = true,
    })
    table.insert(general_items, {
        text_func = function()
            return _("Device: ") .. get_device_model_name()
        end,
        keep_menu_open = true,
    })
    table.insert(general_items, {
        text_func = function()
            local fw = get_kindle_firmware_display()
            if fw == "n/a" then return nil end
            return _("Firmware: ") .. fw
        end,
        enabled_func = function()
            local fw = get_kindle_firmware_display()
            return fw ~= "n/a"
        end,
        keep_menu_open = true,
    })

    filebrowser_items = order_items_by_text(filebrowser_items, {
        _("Display mode"),
        _("Items per page"),
        _("Sort by"),
        _("Status bar"),
        _("Navbar"),
    })

    menu_items = order_items_by_text(menu_items, {
        _("Quick settings"),
    })

    reorder_nested_items_by_text(filebrowser_items, _("Status bar"), {
        _("Enable custom status bar"),
        _("Show time"),
        _("12-hour time"),
        _("Show bottom border"),
        _("Bold text"),
        _("Colored status icons"),
        _("Items"),
    })

    reorder_nested_items_by_text(filebrowser_items, _("Navbar"), {
        _("Enable bottom nav bar"),
        _("Show labels"),
        _("Show top border"),
        _("Show in standalone views"),
        _("Show top gap"),
        _("Tabs"),
        _("Active tab styling"),
        _("Bold active tab"),
        _("Active tab underline"),
        _("Underline above icon"),
        _("Colored active tab"),
        _("Refresh navbar"),
    })

    reorder_nested_items_by_text(filebrowser_items, _("Tabs"), {
        _("Visibility"),
        _("Arrange tabs"),
    })

    reorder_nested_items_by_text(menu_items, _("Quick settings"), {
        _("Enable quick settings panel"),
        _("Show frontlight slider"),
        _("Show warmth slider"),
        _("Always open on this tab"),
        _("Buttons"),
    })


    local root_items = {
        {
            text = _("Zen UI"),
            keep_menu_open = true,
            separator = true,
            callback = function() end,
        },
        {
            text = _("Zen Mode"),
            checked_func = function()
                return config.features["zen_mode"] == true
            end,
            callback = function()
                config.features["zen_mode"] = not (config.features["zen_mode"] == true)
                save_and_apply("zen_mode")
            end,
        },
        {
            text = _("File browser"),
            sub_item_table = filebrowser_items,
        },
        {
            text = _("Menu"),
            sub_item_table = menu_items,
        },
        {
            text = _("Reader"),
            sub_item_table = reader_items,
        },
        {
            text = _("Global"),
            sub_item_table = global_items,
        },
        {
            text = _("About"),
            sub_item_table = general_items,
            separator = true,
        },
        {
            text = _("Quit KOReader"),
            callback = function()
                local Event = require("ui/event")
                local ConfirmBox = require("ui/widget/confirmbox")
                UIManager:show(ConfirmBox:new{
                    text = _("Are you sure you want to quit KOReader?"),
                    ok_text = _("Quit"),
                    ok_callback = function()
                        UIManager:broadcastEvent(Event:new("Exit"))
                    end,
                })
            end,
        },
    }

    -- Insert an "Update available" banner at position 2 (right after the
    -- "Zen UI" header) when a newer release has been detected.
    local update_banner = updater.build_update_available_item(plugin)
    if update_banner then
        table.insert(root_items, 2, update_banner)
    end

    return {
        text = _("Zen UI"),
        sub_item_table = root_items,
    }
end

return M

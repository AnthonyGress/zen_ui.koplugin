-- settings/sections/library/navbar.lua
-- Navbar settings item for Zen UI.
-- Returns a single menu-item table: { text = _("Navbar"), sub_item_table = {...} }
-- Receives ctx: { config, save_and_apply, apply_feature }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local utils = require("settings/zen_settings_utils")

local M = {}

function M.build(ctx)
    local config        = ctx.config
    local save_and_apply = ctx.save_and_apply
    local apply_feature  = ctx.apply_feature

    local function save_and_apply_navbar() save_and_apply("navbar") end

    local function make_enable_feature_item(feature, text)
        return utils.make_enable_feature_item(feature, text, config, save_and_apply)
    end

    -- -------------------------------------------------------------------------
    -- Color helpers
    -- -------------------------------------------------------------------------

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

    -- -------------------------------------------------------------------------
    -- Tab definitions
    -- -------------------------------------------------------------------------

    local navbar_tab_items = {
        { id = "books",       text = _("Books")         },
        { id = "manga",       text = _("Manga")         },
        { id = "news",        text = _("News")          },
        { id = "continue",    text = _("Continue")      },
        { id = "history",     text = _("History")       },
        { id = "favorites",   text = _("Favorites")     },
        { id = "collections", text = _("Collections")   },
        { id = "authors",     text = _("Authors")       },
        { id = "series",      text = _("Series")        },
        { id = "to_be_read",  text = _("To Be Read")    },
        { id = "search",      text = _("Search")        },
        { id = "stats",       text = _("Stats")         },
        { id = "exit",        text = _("Exit")          },
        { id = "page_left",   text = _("Previous page") },
        { id = "page_right",  text = _("Next page")     },
        { id = "menu",        text = _("Menu")          },
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

    -- -------------------------------------------------------------------------
    -- Navbar item
    -- -------------------------------------------------------------------------

    return {
        text = _("Navbar"),
        sub_item_table = {
            {
                text = _("Show top border"),
                checked_func = function() return config.navbar.show_top_border == true end,
                callback = function()
                    config.navbar.show_top_border = not (config.navbar.show_top_border == true)
                    save_and_apply("navbar")
                end,
            },
            {
                text = _("Show labels"),
                checked_func = function() return config.navbar.show_labels == true end,
                callback = function()
                    config.navbar.show_labels = not (config.navbar.show_labels == true)
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
                enabled_func = function()
                    return config.navbar.active_tab_styling == true
                        and config.navbar.active_tab_underline == true
                end,
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
                            if label == nil or label == "" then label = "Books" end
                            return _("Books tab label: ") .. label
                        end,
                        separator = true,
                        sub_item_table = {
                            {
                                text = _("Books"),
                                checked_func = function()
                                    return config.navbar.books_label == nil
                                        or config.navbar.books_label == ""
                                        or config.navbar.books_label == "Books"
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
                                    if presets[label] then return _("Custom") end
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
                                            config.navbar.manga_folder = utils.get_home_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                    {
                                        text = _("Use last folder"),
                                        callback = function()
                                            config.navbar.manga_action = "folder"
                                            config.navbar.manga_folder = utils.get_last_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                    {
                                        text = _("Use current folder"),
                                        callback = function()
                                            config.navbar.manga_action = "folder"
                                            config.navbar.manga_folder = utils.get_current_dir()
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
                                            config.navbar.news_folder = utils.get_home_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                    {
                                        text = _("Use last folder"),
                                        callback = function()
                                            config.navbar.news_action = "folder"
                                            config.navbar.news_folder = utils.get_last_dir()
                                            save_and_apply_navbar()
                                        end,
                                    },
                                    {
                                        text = _("Use current folder"),
                                        callback = function()
                                            config.navbar.news_action = "folder"
                                            config.navbar.news_folder = utils.get_current_dir()
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
    }
end

return M

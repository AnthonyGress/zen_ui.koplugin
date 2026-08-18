local UIManager = require("ui/uimanager")

local M = {}
local dictionary_requested = false

local function reader()
    return require("apps/reader/readerui").instance
end

local function is_visible(target)
    if not target then return false end
    for _i, window in ipairs(UIManager._window_stack or {}) do
        if window and window.widget == target then return true end
    end
    return false
end

local function find_widget(predicate)
    for index = #(UIManager._window_stack or {}), 1, -1 do
        local window = UIManager._window_stack[index]
        local widget = window and window.widget
        if widget and predicate(widget) then return widget end
    end
end

local function page_browser()
    return find_widget(function(widget)
        return type(widget._zen_switch_single) == "function"
            and type(widget._zen_switch_grid) == "function"
    end)
end

local function toc_overlay()
    return find_widget(function(widget)
        return type(widget._entries) == "table"
            and type(widget._gotoTocPage) == "function"
            and type(widget._moveFocus) == "function"
    end)
end

local function book_info_overlay()
    return find_widget(function(widget)
        return widget._description_widget ~= nil
            and widget._L and widget._L.description_h ~= nil
    end)
end

local function bookmark_menu()
    local ui = reader()
    local bookmark = ui and ui.bookmark
    local container = bookmark and bookmark.bookmark_menu
    return container and container[1], container
end

local function open_launcher_page(page)
    local ui = reader()
    local menu = ui and ui.menu
    if not menu then return false, "reader menu unavailable" end
    if menu.tab_item_table == nil and type(menu.setUpdateItemTable) == "function" then
        menu:setUpdateItemTable()
    end
    if type(menu.onShowMenu) == "function" then
        menu:onShowMenu()
    end
    local touch_menu = menu.menu_container and menu.menu_container[1]
    if not touch_menu then return false, "reader menu unavailable" end
    touch_menu._app_launcher_page = page
    for index, tab in ipairs(menu.tab_item_table or {}) do
        if tab.id == "app_launcher" then
            local icon = touch_menu.bar and touch_menu.bar.icon_widgets
                and touch_menu.bar.icon_widgets[index]
            if icon and type(icon.callback) == "function" then
                icon.callback()
                return true
            end
            if type(touch_menu.switchMenuTab) == "function" then
                touch_menu:switchMenuTab(index)
                return true
            end
        end
    end
    return false, "launcher tab unavailable"
end

local function find_control(widget, icon, seen, depth)
    if type(widget) ~= "table" or depth > 16 or seen[widget] then return end
    seen[widget] = true
    local file = widget.file
    local filename = type(file) == "string" and (file:match("([^/]+)$") or file) or ""
    local matches_icon = widget.icon == icon
        or (filename:sub(1, #icon) == icon and filename:sub(#icon + 1, #icon + 1) == ".")
    if matches_icon and type(widget.callback) == "function" then return widget end
    for _i, child in ipairs(widget) do
        local found = find_control(child, icon, seen, depth + 1)
        if found then return found end
    end
end

local function activate_icon(widget, icon)
    local control = find_control(widget, icon, {}, 0)
    if not control then return false end
    control.callback()
    return true
end

function M.page_browser_state()
    local browser = page_browser()
    if not browser then return nil end
    local selected = browser.selected
    local row = selected and browser.layout and browser.layout[selected.y]
    local focused = row and row[selected.x]
    local controls = { "single", "grid" }
    if find_control(browser.title_bar or browser, "appbar.textsize", {}, 0) then
        controls[#controls + 1] = "aa"
    end
    return {
        layout = browser.nb_cols == 1 and browser.nb_rows == 1 and "single" or "grid",
        thumbnail_count = browser.nb_grid_items or 0,
        focus_page = browser.focus_page or browser.cur_page,
        focused = focused and focused._zen_focus_id,
        controls = controls,
    }
end

function M.page_browser_key(key)
    local browser = page_browser()
    if not browser then return false, "page browser unavailable" end
    local Event = require("ui/event")
    local Key = require("device/key")
    return browser:handleEvent(Event:new("KeyPress", Key:new(key, {}))) == true
end

function M.hardware_overlay_state()
    local toc = toc_overlay()
    if toc then
        return {
            kind = "toc",
            focused = toc._zen_focus_area,
            entry = toc._zen_focus_entry_idx,
            footer = toc._zen_footer_side,
        }
    end
    local info = book_info_overlay()
    if info then
        return { kind = "book_info", focused = info._zen_focus_area }
    end
    local menu, container = bookmark_menu()
    if menu and is_visible(container) then
        local selected = menu.selected
        local row = selected and menu.layout and menu.layout[selected.y]
        local focused = row and row[selected.x]
        local title_bar = menu.title_bar
        local area = focused == (title_bar and title_bar.left_button) and "back"
            or focused == (title_bar and title_bar.right_button) and "filter"
            or focused and "bookmark" or nil
        return { kind = "bookmarks", focused = area }
    end
end

function M.hardware_overlay_key(key)
    local menu, container = bookmark_menu()
    local target = toc_overlay() or book_info_overlay()
        or (menu and is_visible(container) and menu)
    if not target then return false, "hardware overlay unavailable" end
    local Event = require("ui/event")
    local Key = require("device/key")
    return target:handleEvent(Event:new("KeyPress", Key:new(key, {}))) == true
end

function M.overlay_state()
    local ui = reader()
    if not ui then return {} end
    local highlight_dialog = ui.highlight and ui.highlight.highlight_dialog
    local config_dialog = ui.config and ui.config.config_dialog
    local browser = page_browser()
    local highlight_visible = is_visible(highlight_dialog)
    local top_window = UIManager._window_stack
        and UIManager._window_stack[#UIManager._window_stack]
    local top_widget = top_window and top_window.widget
    local controls = {}
    if highlight_visible then
        local known = {
            dictionary = "lookup.dictionary",
            highlight = "lookup.highlight",
            search = "lookup.search",
            translate = "lookup.translate",
        }
        for name, icon in pairs(known) do
            if find_control(highlight_dialog, icon, {}, 0) then controls[#controls + 1] = name end
        end
        table.sort(controls)
    end
    return {
        page_browser = browser ~= nil,
        aa_menu = is_visible(config_dialog),
        highlight_menu = highlight_visible,
        highlight_controls = controls,
        dictionary_menu = dictionary_requested
            and not highlight_visible
            and browser == nil
            and top_widget ~= nil
            and top_widget ~= ui
            and top_widget ~= config_dialog,
    }
end

function M.launcher_state()
    local ui = reader()
    local menu = ui and ui.menu
    local container = menu and menu.menu_container
    local touch_menu = container and container[1]
    local refs = touch_menu and touch_menu._zen_panel_refs
    return {
        open = is_visible(container) and refs ~= nil and touch_menu.item_table
            and touch_menu.item_table.id == "app_launcher" or false,
        page = refs and refs.page or nil,
        page_num = refs and refs.page_num or nil,
    }
end

function M.activate(name)
    local ui = reader()
    if not (ui and ui.document) then return false, "reader unavailable" end
    if name == "reader_menu" then
        local menu = ui.menu
        if not (menu and type(menu.onShowMenu) == "function") then
            return false, "reader menu unavailable"
        end
        menu:onShowMenu()
        return menu.menu_container ~= nil
    end
    if name == "launcher_book_switcher" then
        return open_launcher_page(2)
    end
    if name == "launcher_book_details" then
        return open_launcher_page(3)
    end
    if name == "launcher_book_details_fullscreen" then
        local opened, err = open_launcher_page(3)
        if not opened then return false, err end
        local menu = ui.menu
        local touch_menu = menu and menu.menu_container and menu.menu_container[1]
        local button = touch_menu and touch_menu._zen_panel_refs
            and touch_menu._zen_panel_refs.buttons and touch_menu._zen_panel_refs.buttons[1]
        if not (button and type(button.callback) == "function") then
            return false, "book details action unavailable"
        end
        button.callback()
        return true
    end
    if name == "page_browser" then
        local config = ui.config
        if not (config and type(config.onSwipeShowConfigMenu) == "function") then
            return false, "reader config unavailable"
        end
        return config:onSwipeShowConfigMenu({
            direction = "north",
            pos = { x = 1, y = require("device").screen:getHeight() - 1 },
        }) == true
    end
    local browser = page_browser()
    if name == "page_browser_toc" then
        if not browser then return false, "page browser unavailable" end
        return activate_icon(browser.title_bar or browser, "toc")
    elseif name == "page_browser_bookmarks" then
        if not browser then return false, "page browser unavailable" end
        return activate_icon(browser.title_bar or browser, "bookmark")
    elseif name == "page_browser_book_info" then
        if not browser then return false, "page browser unavailable" end
        return activate_icon(browser.title_bar or browser, "info")
    elseif name == "page_browser_single" then
        if not browser then return false, "page browser unavailable" end
        browser._zen_switch_single()
        return true
    elseif name == "page_browser_grid" then
        if not browser then return false, "page browser unavailable" end
        browser._zen_switch_grid()
        return true
    elseif name == "page_browser_aa" then
        if not browser then return false, "page browser unavailable" end
        return activate_icon(browser.title_bar or browser, "appbar.textsize")
    elseif name == "show_highlight_menu" then
        local highlight = ui.highlight
        if not (highlight and type(highlight.onShowHighlightMenu) == "function") then
            return false, "highlight unavailable"
        end
        highlight.hold_pos = { x = 10, y = 10 }
        highlight.selected_text = {
            text = "deterministic",
            pos0 = { page = 1, x = 10, y = 10 },
            pos1 = { page = 1, x = 80, y = 30 },
            sboxes = { { x = 10, y = 10, w = 70, h = 20 } },
        }
        highlight:onShowHighlightMenu()
        return is_visible(highlight.highlight_dialog)
    elseif name == "highlight_dictionary" then
        local highlight_dialog = ui.highlight and ui.highlight.highlight_dialog
        if not is_visible(highlight_dialog) then return false, "highlight menu unavailable" end
        dictionary_requested = activate_icon(highlight_dialog, "lookup.dictionary")
        return dictionary_requested
    end
    return false, "unknown reader control"
end

return M

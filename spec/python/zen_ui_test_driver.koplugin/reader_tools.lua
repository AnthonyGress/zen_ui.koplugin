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

local function find_control(widget, icon, seen, depth)
    if type(widget) ~= "table" or depth > 16 or seen[widget] then return end
    seen[widget] = true
    if widget.icon == icon and type(widget.callback) == "function" then return widget end
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
    local controls = { "single", "grid" }
    if find_control(browser.title_bar or browser, "appbar.textsize", {}, 0) then
        controls[#controls + 1] = "aa"
    end
    return {
        layout = browser.nb_cols == 1 and browser.nb_rows == 1 and "single" or "grid",
        thumbnail_count = browser.nb_grid_items or 0,
        focus_page = browser.focus_page or browser.cur_page,
        controls = controls,
    }
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

function M.activate(name)
    local ui = reader()
    if not (ui and ui.document) then return false, "reader unavailable" end
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
    if name == "page_browser_single" then
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

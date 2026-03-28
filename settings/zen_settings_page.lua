local _ = require("gettext")
local Device = require("device")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")

local settings_builder = require("settings/zen_settings_build")

local M = {}
local Screen = Device.screen

local function safe_call(fn, fallback)
    if type(fn) ~= "function" then
        return fallback
    end
    local ok, value = pcall(fn)
    if ok then
        return value
    end
    return fallback
end

local function refresh_page(page)
    if not (page and page.updateItems) then
        return
    end

    -- Try to preserve current anchor when refreshing, if Menu exposes it.
    local target_page = page.page or page.cur_page or page.current_page
    local target_item = page.selected or page.selected_item or page.itemnumber or page.cur_idx

    local ok = pcall(page.updateItems, page, target_page, target_item)
    if not ok then
        pcall(page.updateItems, page)
    end
end

local function wrap_items(item_table, get_page)
    local wrapped = {}

    for _, item in ipairs(item_table or {}) do
        local entry = {}
        for k, v in pairs(item) do
            entry[k] = v
        end

        local is_checkable = item.checked_func ~= nil or item.checked ~= nil
        local base_text = item.text
        local base_text_func = item.text_func

        if is_checkable then
            -- We render checkbox state in text ourselves; remove native checkable
            -- metadata so Menu doesn't switch to checkbox-padding layout.
            entry.checked = nil
            entry.checked_func = nil
            entry.text = nil
            entry.text_func = function()
                local label = base_text
                if base_text_func then
                    label = safe_call(base_text_func, base_text)
                end
                local checked = item.checked == true
                if item.checked_func then
                    checked = safe_call(item.checked_func, false) == true
                end
                -- Keep a visible marker in both states to avoid first-toggle reflow/jump.
                return string.format("%s %s", checked and "☑" or "☐", label or "")
            end
        end

        if item.sub_item_table then
            entry.sub_item_table = wrap_items(item.sub_item_table, get_page)
        elseif item.sub_item_table_func then
            entry.sub_item_table_func = function(...)
                local dynamic_items = item.sub_item_table_func(...)
                return wrap_items(dynamic_items, get_page)
            end
        end

        if type(item.callback) == "function" and item.sub_item_table == nil and item.sub_item_table_func == nil then
            local original_callback = item.callback
            entry.callback = function(...)
                original_callback(...)
                local page = get_page()
                refresh_page(page)
            end
        end

        table.insert(wrapped, entry)
    end

    return wrapped
end

function M.show_page(plugin, show_parent)
    local root = settings_builder.build(plugin)
    local page
    local item_table = wrap_items(root.sub_item_table or {}, function() return page end)

    page = Menu:new{
        name = "zen_ui_settings",
        title = _("Zen UI settings"),
        item_table = item_table,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        show_parent = show_parent,
    }
    UIManager:show(page)
    -- Ensure initial layout matches subsequent refresh layout.
    refresh_page(page)
    return page
end

return M

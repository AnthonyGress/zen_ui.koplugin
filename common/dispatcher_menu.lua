local M = {}

local function install_flush_on_update(menu)
    if type(menu) ~= "table" or menu._zen_dispatch_flush_installed then return end
    menu._zen_dispatch_flush_installed = true
    local orig_update_items = menu.updateItems
    if type(orig_update_items) ~= "function" then return end
    menu.updateItems = function(self, ...)
        local result = orig_update_items(self, ...)
        M.flush(self)
        return result
    end
end

local function register_update(menu, caller, on_update)
    if type(menu) ~= "table" then return end
    install_flush_on_update(menu)
    menu._zen_dispatch_updates = menu._zen_dispatch_updates or {}
    menu._zen_dispatch_updates[caller] = on_update
end

function M.flush(menu)
    local updates = type(menu) == "table" and menu._zen_dispatch_updates
    if type(updates) ~= "table" then return false end
    local flushed = false
    for caller, on_update in pairs(updates) do
        if caller.updated then
            caller.updated = false
            on_update(menu)
            flushed = true
        end
    end
    return flushed
end

function M.wrap(items, caller, on_update, marker)
    if type(items) ~= "table" then return end
    marker = marker or "_zen_dispatch_wrapped"
    for _i, item in ipairs(items) do
        local callback_marker = marker .. "_callback"
        if type(item.callback) == "function" and not item[callback_marker] then
            local orig_callback = item.callback
            item.callback = function(touch_menu, ...)
                register_update(touch_menu, caller, on_update)
                caller.updated = false
                local result = orig_callback(touch_menu, ...)
                M.flush(touch_menu)
                return result
            end
            item[callback_marker] = true
        end
        local hold_marker = marker .. "_hold"
        if type(item.hold_callback) == "function" and not item[hold_marker] then
            local orig_hold_callback = item.hold_callback
            item.hold_callback = function(touch_menu, ...)
                register_update(touch_menu, caller, on_update)
                caller.updated = false
                local result = orig_hold_callback(touch_menu, ...)
                M.flush(touch_menu)
                return result
            end
            item[hold_marker] = true
        end
        local func_marker = marker .. "_func"
        if type(item.sub_item_table_func) == "function" and not item[func_marker] then
            local orig_sub_item_table_func = item.sub_item_table_func
            item.sub_item_table_func = function(...)
                local sub_items = orig_sub_item_table_func(...)
                M.wrap(sub_items, caller, on_update, marker)
                return sub_items
            end
            item[func_marker] = true
        end
        M.wrap(item.sub_item_table, caller, on_update, marker)
    end
end

return M

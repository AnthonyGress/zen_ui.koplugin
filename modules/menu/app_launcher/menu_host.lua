local _ = require("gettext")
local ZenToggle = require("common/ui/zen_toggle")

local M = {}

local BACK_PREFIX = "< "

local function is_checkbox(item)
    return type(item) == "table"
        and item.radio ~= true
        and type(item.checked_func) == "function"
end

local function has_checkboxes(items)
    for _i, item in ipairs(items or {}) do
        if is_checkbox(item) then return true end
    end
    return false
end

local function row_text(item)
    if type(item.text_func) == "function" then
        return item.text_func()
    end
    return item.text
end

local function source_items(host, item)
    if type(item.sub_item_table_func) == "function" then
        local ok, items = pcall(item.sub_item_table_func, host._shim)
        return ok and items or nil
    end
    return item.sub_item_table
end

local function map_items(host, src_items)
    local rows = {}
    for _i, item in ipairs(src_items or {}) do
        local text = type(item) == "table" and row_text(item)
        if type(text) == "string" then
            local enabled = item.enabled ~= false
            if item.enabled_func then
                enabled = item.enabled_func() ~= false
            end
            local row = {
                text = text,
                dim = not enabled or nil,
                _src = item,
            }
            if is_checkbox(item) then
                row.state = ZenToggle:new{
                    width = host._toggle_width,
                    height = host._toggle_height,
                    value_func = function()
                        return item.checked_func() == true
                    end,
                }
            end
            if item.sub_item_table ~= nil or item.sub_item_table_func ~= nil then
                row.sub_item_table_func = function()
                    return source_items(host, item) or {}
                end
            end
            if enabled then
                row.callback = function()
                    local sub_items = source_items(host, item)
                    if type(sub_items) == "table" then
                        host:_push(text, sub_items)
                        return
                    end
                    local callback = item.callback_func and item.callback_func() or item.callback
                    if callback then
                        callback(host._shim)
                        if is_checkbox(item) then
                            if not item.check_callback_updates_menu
                                    and not item.check_callback_closes_menu then
                                host:_refresh()
                            end
                        elseif item.keep_menu_open then
                            host:_refresh()
                        else
                            M.close(host)
                        end
                    end
                end
            else
                row.select_enabled = false
            end
            rows[#rows + 1] = row
        end
    end
    return rows
end

local function level_items(host, src_items, pushed)
    local rows = map_items(host, src_items)
    if pushed then
        table.insert(rows, 1, {
            text = BACK_PREFIX .. _("Back"),
            callback = function()
                host:_pop()
            end,
        })
    end
    return rows
end

local function hold_item(host, row)
    local item = row and row._src
    if not item then return true end
    local enabled = item.enabled ~= false
    if item.enabled_func then enabled = item.enabled_func() ~= false end
    if not enabled then return true end
    local hold_callback = item.hold_callback_func and item.hold_callback_func()
        or item.hold_callback
    if not hold_callback then return true end
    if item.hold_keep_menu_open == false then
        M.close(host)
    end
    hold_callback(host._shim, item)
    if host._refresh then host:_refresh() end
    return true
end

function M.show(opts)
    local Menu = require("ui/widget/menu")
    local Screen = require("device").screen
    local UIManager = require("ui/uimanager")

    local host = {
        _stack = {},
        _toggle_width = Screen:scaleBySize(56),
        _toggle_height = Screen:scaleBySize(28),
    }
    host._shim = {
        updateItems = function()
            if host._refresh then host:_refresh() end
        end,
        closeMenu = function()
            M.close(host)
        end,
        handleEvent = function()
            return false
        end,
    }

    function host:_current()
        return self._stack[#self._stack]
    end

    function host:_refresh()
        if self._closed then return end
        local level = self:_current()
        if not level then return end
        self._menu.state_w = has_checkboxes(level.items) and self._toggle_width or nil
        self._menu:switchItemTable(level.title,
            level_items(self, level.items, #self._stack > 1))
    end

    function host:_push(title, items)
        self._stack[#self._stack + 1] = { title = title, items = items }
        self._menu.paths[#self._menu.paths + 1] = { title = title }
        self._menu.state_w = has_checkboxes(items) and self._toggle_width or nil
        self._menu:switchItemTable(title, level_items(self, items, true))
    end

    function host:_pop()
        if #self._stack <= 1 then
            M.close(self)
            return
        end
        table.remove(self._stack)
        table.remove(self._menu.paths)
        self:_refresh()
    end

    host._stack[1] = { title = opts.title, items = opts.item_table }
    host._menu = Menu:new{
        title = opts.title,
        item_table = map_items(host, opts.item_table),
        state_w = has_checkboxes(opts.item_table) and host._toggle_width or nil,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        onReturn = function()
            host:_pop()
        end,
    }
    host._shim.show_parent = host._menu
    host._menu.onCloseAllMenus = function()
        M.close(host)
        return true
    end
    host._menu.onMenuHold = function(_menu, row)
        return hold_item(host, row)
    end
    UIManager:show(host._menu)
    return host
end

function M.close(host)
    if not host or host._closed then return end
    host._closed = true
    require("ui/uimanager"):close(host._menu)
end

return M

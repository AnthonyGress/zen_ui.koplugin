local BD = require("ui/bidi")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")
local Utf8Proc = require("ffi/utf8proc")
local util = require("util")
local _ = require("gettext")

local ArrangeState = require("common/arrange_state")
local IconItem = require("common/ui/icon_menu_item")
local SettingsTitleBar = require("common/ui/zen_settings_titlebar")
local zen_settings = require("modules/settings/zen_settings")

local M = {}
local active_page

IconItem.installMenuPatch()

local function install_modal_keyboard_dismissal()
    local InputDialog = require("ui/widget/inputdialog")
    if InputDialog._zen_settings_keyboard_dismissal then return end
    InputDialog._zen_settings_keyboard_dismissal = true
    local orig_init = InputDialog.init
    InputDialog.init = function(self, ...)
        if rawget(_G, "__ZEN_UI_SETTINGS_PAGE") then
            local original_enter_callback = self.enter_callback
            self.enter_callback = function()
                if self:isKeyboardVisible() then
                    self:onCloseKeyboard()
                    if self._input_widget and self._input_widget.unfocus then
                        self._input_widget:unfocus()
                    end
                    return true
                end
                if original_enter_callback then return original_enter_callback() end
                for _i, button_row in ipairs(self.buttons or {}) do
                    for _j, button in ipairs(button_row) do
                        if button.is_enter_default and type(button.callback) == "function" then
                            return button.callback()
                        end
                    end
                end
            end
        end
        return orig_init(self, ...)
    end
end

local function copy_array(items)
    local copy = {}
    for i, item in ipairs(items or {}) do copy[i] = item end
    return copy
end

local function item_text(item)
    if type(item) ~= "table" then return "" end
    local text
    if type(item.text_func) == "function" then
        local ok, value = pcall(item.text_func)
        if ok then text = value end
    else
        text = item.text
    end
    text = type(text) == "string" and text or ""
    return ArrangeState.stripSubmenuCaret(text)
end

local function normalized(text)
    text = type(text) == "string" and text or ""
    return Utf8Proc.lowercase(util.fixUtf8(text, "?"))
end

local function enabled(item)
    if item.enabled == false then return false end
    if type(item.enabled_func) == "function" then
        return item.enabled_func() ~= false
    end
    return true
end

local function callback_for(item)
    if type(item.callback_func) == "function" then
        return item.callback_func()
    end
    return item.callback
end

local function has_declared_submenu(item, display_text)
    if item.sub_item_table ~= nil or type(item.sub_item_table_func) == "function" then
        return true
    end
    local raw_text
    if type(item.text_func) == "function" then
        local ok, value = pcall(item.text_func)
        if ok then raw_text = value end
    else
        raw_text = item.text
    end
    return (type(raw_text) == "string"
        and ArrangeState.stripSubmenuCaret(raw_text) ~= raw_text)
        or item._zen_settings_submenu == true
        or (display_text and item.sub_title ~= nil)
end

local ZenSettingsPage = Menu:extend{}

local function is_near_header_control(title_bar, pos)
    if not (title_bar and pos and pos.x and pos.y) then return false end
    local screen = Device.screen
    local padding = type(screen.scaleBySize) == "function" and screen:scaleBySize(8) or 8

    local function is_near(control)
        if not control or control.skip_paint then return false end
        local dimen = control.dimen
        return dimen and dimen.x and dimen.y and dimen.w and dimen.h
            and pos.x >= dimen.x - padding and pos.x < dimen.x + dimen.w + padding
            and pos.y >= dimen.y - padding and pos.y < dimen.y + dimen.h + padding
    end

    return is_near(title_bar.back_button)
        or is_near(title_bar.search_button)
        or is_near(title_bar.search_frame)
        or is_near(title_bar.action_button)
        or is_near(title_bar.more_button)
        or is_near(title_bar.close_button)
end

function ZenSettingsPage:_resolveSubItems(item)
    if type(item.sub_item_table_func) == "function" then
        local ok, items = pcall(item.sub_item_table_func, self)
        if ok and type(items) == "table" then return items end
        return nil
    end
    return type(item.sub_item_table) == "table" and item.sub_item_table or nil
end

function ZenSettingsPage:_currentTitle()
    return self.item_table and self.item_table._zen_title or self.title or _("Settings")
end

function ZenSettingsPage:_prepareItems()
    local caret = BD.mirroredUILayout() and "chevron.left" or "chevron.right"
    for _i, item in ipairs(self.item_table or {}) do
        if type(item) == "table" then
            local text = item_text(item)
            item._zen_settings_row = true
            item._zen_display_text = text
            item._zen_has_submenu = has_declared_submenu(item, text)
                or (item._zen_search_result
                    and type(item._zen_search_result.open_callback) == "function")
            item._zen_caret_icon = caret
        end
    end
end

function ZenSettingsPage:_ensureCurrentTitle()
    if type(self.item_table) ~= "table" then return end
    local depth = #self.item_table_stack
    if not self.item_table._zen_title then
        if depth > (self._title_stack_depth or 0) and self._pending_navigation_title then
            self.item_table._zen_title = self._pending_navigation_title
        else
            self.item_table._zen_title = self._displayed_title or self.title or _("Settings")
        end
    end
    self._displayed_title = self.item_table._zen_title
    self._title_stack_depth = depth
end

function ZenSettingsPage:_syncHeader()
    if not self.title_bar then return end
    local at_root = #self.item_table_stack == 0
    self.title_bar:setState(self:_currentTitle(), not at_root, true)
end

function ZenSettingsPage:_focusSearchInput()
    local input = self.title_bar and self.title_bar.search_input
    if input and not input.focused then input:focus() end
end

function ZenSettingsPage:openKoreaderMenu()
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    local filemanager_menu = ok_fm and FileManager.instance and FileManager.instance.menu
    if filemanager_menu and type(filemanager_menu.onShowMenu) == "function" then
        filemanager_menu:onShowMenu()
        return true
    end

    local ok_rui, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader_menu = ok_rui and ReaderUI.instance and ReaderUI.instance.menu
    if reader_menu and type(reader_menu.onShowMenu) == "function" then
        reader_menu:onShowMenu()
        return true
    end
    return false
end

function ZenSettingsPage:init()
    self.name = "zen_settings"
    self.title = self.title or _("Settings")
    self.item_table = self.item_table or {}
    self.item_table._zen_title = self.title
    self.width = Device.screen:getWidth()
    self.height = Device.screen:getHeight()
    self.is_borderless = true
    self.is_popout = false
    self.linesize = require("ui/size").line.thin
    self.line_color = require("ffi/blitbuffer").COLOR_LIGHT_GRAY
    self._search_index = nil
    self._search_active = false
    self._closed = false
    self._title_stack_depth = 0
    self._displayed_title = self.title
    self.is_enable_shortcut = false

    self.custom_title_bar = SettingsTitleBar:new{
        width = self.width,
        title = self.title,
        back_visible = false,
        search_visible = true,
        show_parent = self,
        back_callback = function() self:backToUpperMenu() end,
        close_callback = function() self:closeMenu() end,
        search_callback = function(query) self:_onSearchChanged(query) end,
        plugin = self.plugin,
    }
    Menu.init(self)
    self.key_events = self.key_events or {}
    self.key_events.SelectByShortCut = nil
    _G.__ZEN_UI_SETTINGS_PAGE = self
end

function ZenSettingsPage:updateItems(...)
    if self._closed then return end
    self:_ensureCurrentTitle()
    self:_prepareItems()
    self:_syncHeader()
    return Menu.updateItems(self, ...)
end

function ZenSettingsPage:handleEvent(event)
    if event.handler == "onGesture" then
        local gesture = event.args[1]
        for _i, zone in ipairs(self._zen_page_number_zones or {}) do
            local registered = self._zones and self._zones[zone.id]
            if registered and registered.gs_range:match(gesture) then
                if registered.handler(gesture) then return true end
            end
        end
    end
    return Menu.handleEvent(self, event)
end

function ZenSettingsPage:onTap(arg, ges_ev)
    if is_near_header_control(self.title_bar, ges_ev and ges_ev.pos) then return true end
    if Menu.onTap then return Menu.onTap(self, arg, ges_ev) end
end

function ZenSettingsPage:onSwipe(arg, ges_ev)
    if is_near_header_control(self.title_bar, ges_ev and ges_ev.pos) then return true end
    if Menu.onSwipe then return Menu.onSwipe(self, arg, ges_ev) end
end

function ZenSettingsPage:_recalculateDimen(no_recalculate_dimen)
    local requested_page = self.page or 1
    Menu._recalculateDimen(self, no_recalculate_dimen)
    if not (self.available_height and self.item_dimen) then return end

    local row_height = IconItem.getSettingsRowHeight()
    self.perpage = math.max(1, math.floor(self.available_height / row_height))
    self.font_size = IconItem.getSettingsFontSize()
    self.item_dimen.h = row_height
    self.page_num = self:getPageNumber(#self.item_table)
    self.page = math.min(requested_page, self.page_num)
end

function ZenSettingsPage:_openSubmenu(item, items)
    if type(items) ~= "table" or #items == 0 then return false end
    self:_leaveSearch(false)
    if self.title_bar and self.title_bar.collapseSearch then
        self.title_bar:collapseSearch()
    end
    self.item_table._zen_title = self:_currentTitle()
    table.insert(self.item_table_stack, self.item_table)
    items._zen_title = item.sub_title or item_text(item)
    self.parent_id = nil
    self.item_table = items
    self:updateItems(1)
    return true
end

function ZenSettingsPage:onMenuSelect(item)
    if item._zen_search_result then
        self:_openSearchResult(item._zen_search_result)
        return true
    end
    if not enabled(item) then return true end
    self._pending_navigation_title = item.sub_title or item_text(item)

    local sub_items = self:_resolveSubItems(item)
    if sub_items then
        self:_openSubmenu(item, sub_items)
        return true
    end

    local callback = callback_for(item)
    if type(callback) == "function" then
        callback(self)
        self._search_index = nil
        if self._closed then return true end
        if item.checked ~= nil or type(item.checked_func) == "function" then
            if not item.check_callback_updates_menu and not item.check_callback_closes_menu then
                self:updateItems()
            end
        elseif not item.keep_menu_open then
            self:closeMenu()
        end
    end
    return true
end

function ZenSettingsPage:onMenuHold(item, text_truncated)
    if not enabled(item) then return true end
    local hold_callback = type(item.hold_callback_func) == "function"
        and item.hold_callback_func() or item.hold_callback
    if type(hold_callback) == "function" then
        if item.hold_keep_menu_open == false then self:closeMenu() end
        hold_callback(self, item)
        return true
    end
    local help_text = type(item.help_text_func) == "function"
        and item.help_text_func(self) or item.help_text
    if help_text then
        UIManager:show(InfoMessage:new{ text = help_text })
        return true
    end
    if text_truncated then
        UIManager:show(InfoMessage:new{ text = item_text(item), show_icon = false })
    end
    return true
end

function ZenSettingsPage:backToUpperMenu(no_close)
    if self._search_active then
        self:_leaveSearch(true)
        return true
    end
    if #self.item_table_stack == 0 then
        if not no_close then self:closeMenu() end
        return true
    end
    local parent = table.remove(self.item_table_stack)
    local parent_title = parent._zen_title
    if parent.needs_refresh and type(parent.refresh_func) == "function" then
        parent = parent.refresh_func() or parent
    end
    parent._zen_title = parent._zen_title or parent_title
    self.item_table = parent
    self.parent_id = nil
    self._pending_navigation_title = nil
    self:updateItems(1)
    return true
end

function ZenSettingsPage:onClose()
    return self:backToUpperMenu()
end

function ZenSettingsPage:onLeftButtonTap()
    return self:openKoreaderMenu()
end

function ZenSettingsPage:onCloseAllMenus()
    self:closeMenu()
    return true
end

function ZenSettingsPage:closeMenu()
    if self._closed then return true end
    self._closed = true
    if self.title_bar and self.title_bar.clearStatusRefresh then
        self.title_bar:clearStatusRefresh()
    end
    if active_page == self then active_page = nil end
    if rawget(_G, "__ZEN_UI_SETTINGS_PAGE") == self then
        _G.__ZEN_UI_SETTINGS_PAGE = nil
    end
    UIManager:close(self)
    return true
end

function ZenSettingsPage:onCloseWidget()
    if self.title_bar and self.title_bar.clearStatusRefresh then
        self.title_bar:clearStatusRefresh()
    end
    if active_page == self then active_page = nil end
    if rawget(_G, "__ZEN_UI_SETTINGS_PAGE") == self then
        _G.__ZEN_UI_SETTINGS_PAGE = nil
    end
    return Menu.onCloseWidget(self)
end

function ZenSettingsPage:_buildSearchIndex()
    if self._search_index then return self._search_index end
    local index = {}
    local seen = {}

    local function add_virtual_items(provider, levels, owner_title)
        if type(provider) ~= "function" then return end
        local ok, items = pcall(provider, self)
        if not ok or type(items) ~= "table" then return end
        for _i, item in ipairs(items) do
            local label = item_text(item)
            if label ~= "" and type(item._zen_search_open) == "function" then
                local crumbs = {}
                for i = 2, #levels do crumbs[#crumbs + 1] = levels[i].title end
                if not item._zen_search_breadcrumb and owner_title and owner_title ~= "" then
                    crumbs[#crumbs + 1] = owner_title
                end
                local breadcrumb = item._zen_search_breadcrumb or table.concat(crumbs, " › ")
                local help_text = item.help_text
                if type(item.help_text_func) == "function" then
                    local help_ok, value = pcall(item.help_text_func, self)
                    if help_ok then help_text = value end
                end
                index[#index + 1] = {
                    item = item,
                    label = label,
                    breadcrumb = breadcrumb,
                    open_callback = item._zen_search_open,
                    haystack = normalized(table.concat({
                        label,
                        breadcrumb,
                        type(help_text) == "string" and help_text or "",
                    }, " ")),
                }
            end
        end
    end

    local function walk(items, levels, depth)
        if depth > 12 or seen[items] then return end
        seen[items] = true
        for item_index, item in ipairs(items or {}) do
            if type(item) == "table" then
                local label = item_text(item)
                if label ~= "" then
                    local crumbs = {}
                    for i = 2, #levels do crumbs[#crumbs + 1] = levels[i].title end
                    local breadcrumb = table.concat(crumbs, " › ")
                    local help_text = item.help_text
                    if type(item.help_text_func) == "function" then
                        local ok, value = pcall(item.help_text_func, self)
                        if ok then help_text = value end
                    end
                    local sub_items = self:_resolveSubItems(item)
                    index[#index + 1] = {
                        item = item,
                        index = item_index,
                        label = label,
                        breadcrumb = breadcrumb,
                        levels = copy_array(levels),
                        sub_items = sub_items,
                        haystack = normalized(table.concat({
                            label,
                            breadcrumb,
                            type(help_text) == "string" and help_text or "",
                        }, " ")),
                    }
                    if sub_items and #sub_items > 0 then
                        sub_items._zen_title = item.sub_title or label
                        local child_levels = copy_array(levels)
                        child_levels[#child_levels + 1] = {
                            title = sub_items._zen_title,
                            items = sub_items,
                        }
                        walk(sub_items, child_levels, depth + 1)
                    end
                    add_virtual_items(item._zen_search_items_func, levels, label)
                end
            end
        end
    end

    walk(self._root_items, {{ title = _("Settings"), items = self._root_items }}, 1)
    self._search_index = index
    return index
end

function ZenSettingsPage:_searchResults(query)
    local results = { _zen_title = self:_currentTitle(), _zen_search_results = true }
    local needle = normalized(query)
    for _i, entry in ipairs(self:_buildSearchIndex()) do
        if entry.haystack:find(needle, 1, true) then
            local source = entry.item
            results[#results + 1] = {
                text = entry.label,
                icon_glyph = source.icon_glyph,
                icon_width = source.icon_width,
                radio = source.radio,
                checked = source.checked,
                checked_func = source.checked_func,
                enabled = source.enabled,
                enabled_func = source.enabled_func,
                _zen_settings_row = true,
                _zen_display_text = entry.label,
                _zen_settings_breadcrumb = entry.breadcrumb,
                _zen_has_submenu = entry.sub_items ~= nil or entry.open_callback ~= nil,
                _zen_search_result = entry,
            }
        end
    end
    return results
end

function ZenSettingsPage:_onSearchChanged(query)
    query = type(query) == "string" and query:match("^%s*(.-)%s*$") or ""
    if query == "" then
        self:_leaveSearch(true)
        return
    end
    if not self._search_active then
        self._search_active = true
        self._search_snapshot = {
            item_table = self.item_table,
            item_table_stack = copy_array(self.item_table_stack),
        }
    end
    self.item_table = self:_searchResults(query)
    self:updateItems(1)
    self:_focusSearchInput()
end

function ZenSettingsPage:_leaveSearch(restore)
    if not self._search_active then return end
    local snapshot = self._search_snapshot
    self._search_active = false
    self._search_snapshot = nil
    self.title_bar:setQuery("")
    if restore and snapshot then
        self.item_table = snapshot.item_table
        self.item_table_stack = snapshot.item_table_stack
        self:updateItems(1)
        self:_focusSearchInput()
    end
end

function ZenSettingsPage:_setPath(levels, current_items)
    self.item_table_stack = {}
    for i = 1, #levels - 1 do
        self.item_table_stack[#self.item_table_stack + 1] = levels[i].items
    end
    self.item_table = current_items
    self.parent_id = nil
end

function ZenSettingsPage:_openSearchResult(entry)
    if type(entry.open_callback) == "function" then
        self:_leaveSearch(true)
        if self.title_bar and self.title_bar.collapseSearch then
            self.title_bar:collapseSearch()
        end
        entry.open_callback()
        return
    end
    self:_leaveSearch(false)
    if self.title_bar and self.title_bar.collapseSearch then
        self.title_bar:collapseSearch()
    end
    local levels = entry.levels
    local sub_items = entry.sub_items
    if sub_items and #sub_items > 0 then
        self:_setPath(levels, levels[#levels].items)
        table.insert(self.item_table_stack, self.item_table)
        self.item_table = sub_items
        self:updateItems(1)
        return
    end

    self:_setPath(levels, levels[#levels].items)
    self.itemnumber = entry.index
    self.page = self:getPageNumber(entry.index)
    self:updateItems(1)
    if has_declared_submenu(entry.item, entry.label) then
        UIManager:nextTick(function()
            if not self._closed then self:onMenuSelect(entry.item) end
        end)
    end
end

function ZenSettingsPage:openPath(markers)
    for _i, marker in ipairs(markers or {}) do
        local found
        for _j, item in ipairs(self.item_table or {}) do
            if item[marker.key] == marker.value then
                found = item
                break
            end
        end
        if not found then return false end
        local sub_items = self:_resolveSubItems(found)
        if sub_items then
            self:_openSubmenu(found, sub_items)
        else
            self:onMenuSelect(found)
        end
    end
    return true
end

function M.show(plugin, opts)
    opts = opts or {}
    install_modal_keyboard_dismissal()
    local root_items = zen_settings.build(plugin).sub_item_table
    root_items._zen_title = _("Settings")
    local page = ZenSettingsPage:new{
        title = _("Settings"),
        item_table = root_items,
        _root_items = root_items,
        plugin = plugin,
    }
    active_page = page
    UIManager:show(page)
    if type(opts.path) == "table" and #opts.path > 0 then
        UIManager:nextTick(function()
            if not page._closed then page:openPath(opts.path) end
        end)
    end
    return page
end

function M.closeActive()
    if active_page then active_page:closeMenu() end
end

function M.searchActive(query)
    if not active_page or active_page._closed then
        local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        if not plugin then return false end
        active_page = M.show(plugin)
    end
    active_page.title_bar:setQuery(query)
    active_page:_onSearchChanged(query)
    return true
end

M.Page = ZenSettingsPage

return M

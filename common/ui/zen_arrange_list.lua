local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckMark = require("ui/widget/checkmark")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local SortWidget = require("ui/widget/sortwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local _ = require("gettext")
local icons = require("common/inline_icon_map")
local IconItem = require("common/ui/icon_menu_item")
local ZenToggle = require("common/ui/zen_toggle")
local utils = require("common/utils")
local ArrangeState = require("common/arrange_state")

local M = {}
local show_submenu
local repopulate
local plus_icon_path

local function get_plus_icon_path()
    if plus_icon_path ~= nil then return plus_icon_path end
    plus_icon_path = false
    local ok_root, root = pcall(require, "common/plugin_root")
    if ok_root and root then
        plus_icon_path = utils.resolveLocalIcon(root .. "/icons/", "plus") or false
    end
    return plus_icon_path or nil
end

local function suppress_footer_cancel(button)
    if not button then return end
    button:disableWithoutDimming()
    button.callback = function() return true end
    button.onTapSelectButton = function() return true end
    button.onHoldSelectButton = function() return true end
    button.hidden = false
    button.skip_paint = true
    button:hide()
end

local function toggle_sort_item(sort_widget, item)
    if not (sort_widget and item and item.checked_func and item.callback) then
        return false
    end
    item:callback()
    if sort_widget.marked and sort_widget.marked > 0 then
        sort_widget.marked = 0
    end
    sort_widget:_populateItems()
    return true
end

local function get_marked_item(sort_widget)
    local idx = sort_widget and sort_widget.marked
    if type(idx) ~= "number" or idx <= 0 then return nil end
    return sort_widget.item_table and sort_widget.item_table[idx]
end

local function get_focused_item(sort_widget)
    local focused = sort_widget and sort_widget.getFocusItem and sort_widget:getFocusItem()
    return focused and focused.item
end

local function sync_footer_cancel(sort_widget)
    local button = sort_widget and sort_widget.footer_cancel
    local item = get_marked_item(sort_widget)
    if not (button and item and item.checked_func and item.callback and item.checked_func()) then
        suppress_footer_cancel(button)
        return
    end
    button.skip_paint = false
    button:show()
    button:enable()
    button.onTapSelectButton = nil
    button.onHoldSelectButton = nil
    button.onHoldReleaseSelectButton = nil
    button.callback = function()
        return toggle_sort_item(sort_widget, item)
    end
end

local function hide_button_icon(button)
    if not button then return end
    if button._zen_arrange_callback == nil then
        button._zen_arrange_callback = button.callback
        button._zen_arrange_on_tap = button.onTapSelectButton
        button._zen_arrange_on_hold = button.onHoldSelectButton
        button._zen_arrange_on_hold_release = button.onHoldReleaseSelectButton
    end
    button:disableWithoutDimming()
    button.callback = function() return true end
    button.onTapSelectButton = function() return true end
    button.onHoldSelectButton = function() return true end
    button.onHoldReleaseSelectButton = function() return true end
    button.hidden = false
    button.skip_paint = true
    button:hide()
end

local function restore_button_icon(button)
    if not button then return end
    button.skip_paint = false
    if button._zen_arrange_callback ~= nil then
        button.callback = button._zen_arrange_callback
        button.onTapSelectButton = button._zen_arrange_on_tap
        button.onHoldSelectButton = button._zen_arrange_on_hold
        button.onHoldReleaseSelectButton = button._zen_arrange_on_hold_release
    end
    button:show()
end

local function suppress_footer_jump_buttons(sort_widget)
    if not sort_widget then return end
    local moving = sort_widget.marked and sort_widget.marked > 0
    if moving then
        restore_button_icon(sort_widget.footer_first_up)
        restore_button_icon(sort_widget.footer_last_down)
        return
    end

    hide_button_icon(sort_widget.footer_first_up)
    hide_button_icon(sort_widget.footer_last_down)
end

local function suppress_footer_page_button(sort_widget)
    local button = sort_widget and sort_widget.footer_page
    if not button then return end
    button.call_hold_input_on_tap = false
    button.tap_input = nil
    button.tap_input_func = nil
    button.hold_input = nil
    button.hold_input_func = nil
    button.callback = nil
    button:disableWithoutDimming()
    button.onTapSelectButton = function() return true end
    button.onHoldSelectButton = function() return true end
    button.onHoldReleaseSelectButton = function() return true end
end

local function has_rearranged_items(sort_widget)
    return ArrangeState.hasRearrangedItems(
        sort_widget and sort_widget.orig_item_table,
        sort_widget and sort_widget.item_table
    )
end

local function sync_footer_ok(sort_widget)
    local button = sort_widget and sort_widget.footer_ok
    if not button then return end
    if has_rearranged_items(sort_widget) then
        restore_button_icon(button)
        button:enable()
    else
        hide_button_icon(button)
    end
end

local function rebuild_icon_row(row)
    local item = row and row.item
    if not (item and row.width and row.height) then return end

    local item_checkable = false
    local item_checked = item.checked
    if item.checked_func then
        item_checkable = true
        item_checked = item.checked_func()
    end
    local toggle_h = math.max(16, math.floor(row.height * 0.45))
    local check_w = toggle_h * 2
    if item_checkable then
        row.checkmark_widget = ZenToggle:new{
            value = item_checked,
            width = check_w,
            height = toggle_h,
        }
    else
        row.checkmark_widget = CheckMark:new{ checkable = false }
    end
    local icon_w = item.icon_glyph and IconItem.getWidth(item) or 0
    local toggle_gap = Size.padding.default
    local text_max_width = math.max(1, row.width - 2 * Size.padding.default - check_w - toggle_gap - icon_w)
    local face = item.face or row.face or Font:getFace("smallinfofont")
    local row_items = {
        align = "center",
        CenterContainer:new{
            dimen = Geom:new{ w = check_w },
            row.checkmark_widget,
        },
        HorizontalSpan:new{ width = toggle_gap },
    }
    if item.icon_glyph then
        table.insert(row_items, IconItem.makeState(item.icon_glyph, icon_w, row.height, face))
    end
    table.insert(row_items, VerticalGroup:new{
        align = "left",
        TextWidget:new{
            text = item.text,
            max_width = text_max_width,
            face = face,
            fgcolor = item.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
        },
        row.show_parent.underscore_checked_item and item_checked and LineWidget:new{
            dimen = Geom:new{ w = text_max_width, h = Size.line.thick },
            background = Blitbuffer.COLOR_DARK_GRAY,
        },
    })

    row[1] = FrameContainer:new{
        padding = 0,
        bordersize = 0,
        focusable = true,
        focus_border_size = Size.border.thin,
        LeftContainer:new{
            dimen = Geom:new{
                w = row.width,
                h = row.height,
            },
            HorizontalGroup:new(row_items),
        },
    }
    row[1].invert = row.invert
end

local function apply_icon_rows(sort_widget)
    if not sort_widget or not sort_widget.main_content then return end
    for _i, child in ipairs(sort_widget.main_content) do
        rebuild_icon_row(child)
    end
end

local function suppress_page_centering(sort_widget)
    local content = sort_widget and sort_widget[1] and sort_widget[1][1]
    local frame_content = content and content[1]
    local vertical_group = frame_content and frame_content[1]
    local padding_span = vertical_group and vertical_group[2]
    if vertical_group and padding_span and vertical_group[3] == sort_widget.main_content then
        padding_span.width = 0
        if vertical_group.resetLayout then
            vertical_group:resetLayout()
        end
    end
end

local function get_done_action(items, fallback)
    if type(items) ~= "table" then return false end
    local done_func = items._zen_arrange_done_func
    local finish = type(done_func) == "function"
    if not finish and fallback then
        done_func = fallback.done_func
    end
    if type(done_func) ~= "function" then return false end
    local enabled_func = items._zen_arrange_done_enabled_func
    if enabled_func == nil and fallback then
        enabled_func = fallback.done_enabled_func
    end
    if type(enabled_func) == "function" and not enabled_func() then return false end
    return {
        done_func = done_func,
        finish = finish,
        text = (finish and icons.check or icons.save)
            .. " "
            .. (finish and _("Finish") or _("Done")),
    }
end

local function remove_done_button(sort_widget)
    local title_bar = sort_widget and sort_widget.title_bar
    local button = title_bar and title_bar._zen_arrange_done_button
    if not button then return end
    for i = #title_bar, 1, -1 do
        if title_bar[i] == button then
            table.remove(title_bar, i)
            break
        end
    end
    button:free()
    title_bar._zen_arrange_done_button = nil
    title_bar._zen_arrange_done_text = nil
    if title_bar.right_button and title_bar._zen_arrange_right_button_ges_events ~= nil then
        title_bar.right_button.ges_events = title_bar._zen_arrange_right_button_ges_events or {}
        title_bar._zen_arrange_right_button_ges_events = nil
    end
end

local function sync_done_button(sort_widget, menu_proxy, fallback)
    local title_bar = sort_widget and sort_widget.title_bar
    if not title_bar then return end
    local items = menu_proxy and menu_proxy.item_table or sort_widget.item_table
    local action = get_done_action(items, fallback)
    if not action then
        remove_done_button(sort_widget)
        return
    end
    if title_bar._zen_arrange_done_button then
        if title_bar._zen_arrange_done_text == action.text then return end
        remove_done_button(sort_widget)
    end
    if title_bar.right_button and title_bar._zen_arrange_right_button_ges_events == nil then
        title_bar._zen_arrange_right_button_ges_events = title_bar.right_button.ges_events or false
        title_bar.right_button.ges_events = {}
    end
    local button = Button:new{
        text = action.text,
        bordersize = 0,
        radius = 0,
        padding_h = Size.padding.default,
        padding_v = Size.padding.small,
        text_font_face = "smallinfofont",
        text_font_size = 18,
        text_font_bold = true,
        allow_flash = false,
        show_parent = sort_widget,
        callback = function()
            local current_items = menu_proxy and menu_proxy.item_table or sort_widget.item_table
            local current_action = get_done_action(current_items, fallback)
            if not current_action then return true end
            current_action.done_func(menu_proxy)
            UIManager:close(sort_widget)
            if current_action.finish and fallback and type(fallback.close_arrange) == "function" then
                fallback.close_arrange()
            elseif fallback and type(fallback.return_to_parent) == "function" then
                fallback.return_to_parent()
            end
            return true
        end,
    }
    local button_size = button:getSize()
    local title_h = title_bar:getHeight()
    local content_h = math.max(1, title_h - (title_bar.bottom_v_padding or 0) - Size.line.thick)
    button.overlap_offset = {
        math.max(0, (title_bar.width or 0) - button_size.w - Size.padding.default),
        math.max(0, math.floor((content_h - button_size.h) / 2)),
    }
    title_bar._zen_arrange_done_button = button
    title_bar._zen_arrange_done_text = action.text
    table.insert(title_bar, button)
end

local function configure_title_bar(sort_widget, opts)
    opts = opts or {}
    local title_bar = sort_widget and sort_widget.title_bar
    if not title_bar then return end

    local left_button = title_bar.left_button
    if left_button then
        left_button:setIcon("chevron.left")
        left_button.allow_flash = false
        left_button.callback = function()
            return sort_widget:onClose()
        end
        left_button.hold_callback = false
        left_button.onHoldIconButton = function() return true end
        left_button.onHoldReleaseIconButton = function() return true end
    end

    local right_button = title_bar.right_button
    if right_button then
        if type(opts.add_item_table) == "table" and #opts.add_item_table > 0 then
            local icon_path = get_plus_icon_path()
            if icon_path and right_button.image and right_button.horizontal_group then
                right_button.image:free()
                right_button.image = IconWidget:new{
                    file = icon_path,
                    width = right_button.width,
                    height = right_button.height,
                }
                right_button.horizontal_group[2] = right_button.image
                right_button:update()
            elseif title_bar.setRightIcon then
                title_bar:setRightIcon("plus")
            elseif right_button.setIcon then
                right_button:setIcon("plus")
            end
            right_button.enabled = true
            right_button.callback = function()
                if show_submenu then
                    show_submenu(opts.add_title or "", opts.add_item_table, function()
                        if sort_widget._zen_arrange_refresh then
                            sort_widget:_zen_arrange_refresh()
                        else
                            repopulate(sort_widget)
                        end
                    end, {
                        close_arrange = opts.close_arrange,
                    })
                end
                return true
            end
            right_button.onTapIconButton = nil
            if right_button.image then
                right_button.image.hide = false
            end
            if right_button.show then right_button:show() end
            if right_button.enable then right_button:enable() end
        else
            right_button.enabled = false
            right_button.callback = nil
            right_button.onTapIconButton = function() return true end
            if right_button.image then
                right_button.image.hide = true
            end
        end
        right_button.hold_callback = false
        right_button.allow_flash = false
        right_button.onHoldIconButton = function() return true end
        right_button.onHoldReleaseIconButton = function() return true end
    end
end

local function strip_submenu_caret(text)
    return ArrangeState.stripSubmenuCaret(text)
end

local function has_submenu(item)
    return type(item) == "table"
        and (type(item.sub_item_table) == "table"
            or type(item.sub_item_table_func) == "function")
end

local function item_base_text(item)
    if type(item) ~= "table" then return nil end
    if type(item.text_func) == "function" then
        return strip_submenu_caret(item.text_func())
    end
    if item._zen_arrange_base_text == nil then
        item._zen_arrange_base_text = strip_submenu_caret(item.text)
    end
    return item._zen_arrange_base_text
end

local function strip_value_suffix(text)
    return ArrangeState.stripValueSuffix(text)
end

local function item_submenu_title(item)
    return item.sub_title or strip_value_suffix(item_base_text(item)) or item.text
end

local function update_dynamic_text(items)
    if type(items) ~= "table" then return end
    for _i, item in ipairs(items) do
        local text = item_base_text(item)
        if has_submenu(item) and type(text) == "string" then
            item.text = text .. ArrangeState.SUBMENU_CARET
        elseif text ~= nil then
            item.text = text
        end
    end
end

repopulate = function(sort_widget)
    if not sort_widget then return end
    sort_widget:_populateItems()
    UIManager:setDirty(sort_widget, "ui")
end

local function install_titlebar_focus(sort_widget)
    if not (sort_widget and sort_widget.layout) then return end
    local title_bar = sort_widget.title_bar
    local left_button = title_bar and title_bar.left_button
    if not left_button then return end
    local first = sort_widget.layout[1]
    if first and first[1] == left_button then return end
    table.insert(sort_widget.layout, 1, { left_button })
    if sort_widget.selected then
        sort_widget.selected.y = (sort_widget.selected.y or 1) + 1
    end
end

local function patch_move_item_kb(sort_widget)
    if not sort_widget or sort_widget._zen_move_kb_patched then return end
    sort_widget._zen_move_kb_patched = true
    sort_widget.onMoveItemKB = function(self, diff)
        local focused = self.getFocusItem and self:getFocusItem()
        if focused and focused.index then
            self.marked = focused.index
            self:moveItem(diff)
        end
        return true
    end
end

local function refresh_after_callbacks(items, refresh, menu_proxy)
    if type(items) ~= "table" or type(refresh) ~= "function" then return end
    for _i, item in ipairs(items) do
        if type(item.callback) == "function"
                and (not item._zen_arrange_refresh_wrapped
                    or item._zen_arrange_refresh_proxy ~= menu_proxy) then
            local orig_callback = item._zen_arrange_orig_callback or item.callback
            item.callback = function(...)
                local result = orig_callback(menu_proxy, select(2, ...))
                refresh()
                return result
            end
            item._zen_arrange_orig_callback = orig_callback
            item._zen_arrange_refresh_proxy = menu_proxy
            item._zen_arrange_refresh_wrapped = true
        end
        refresh_after_callbacks(item.sub_item_table, refresh, menu_proxy)
    end
end

local install_submenu_tap_handlers
local install_root_tap_handlers

local function open_submenu_for_item(sort_widget, item)
    if not (sort_widget and item and has_submenu(item)) then
        return false
    end
    local sub_items = item.sub_item_table
    if type(item.sub_item_table_func) == "function" then
        sub_items = item.sub_item_table_func()
    end
    show_submenu(item_submenu_title(item), sub_items, function()
        if sort_widget._zen_arrange_refresh then
            sort_widget:_zen_arrange_refresh()
        else
            repopulate(sort_widget)
        end
    end, {
        close_arrange = sort_widget._zen_arrange_close_all,
        done_func = sort_widget._zen_arrange_done_func,
        done_enabled_func = sort_widget._zen_arrange_done_enabled_func,
        return_to_parent = sort_widget.item_table
            and sort_widget.item_table._zen_arrange_done_func == nil
            and sort_widget._zen_arrange_done_func ~= nil
            and sort_widget._zen_arrange_return_to_parent
            or nil,
    })
    return true
end

local function toggle_arrange_selection(row)
    if not (row and row.show_parent and row.index) then return false end
    if row.show_parent.marked == row.index then
        row.show_parent.marked = 0
    else
        row.show_parent.marked = row.index
    end
    repopulate(row.show_parent)
    return true
end

local function ensure_submenu_callbacks(items)
    if type(items) ~= "table" then return end
    for _i, item in ipairs(items) do
        if not item.hold_callback and has_submenu(item) then
            local submenu_item = item
            item.hold_callback = function(_item, refresh)
                local sub_items = submenu_item.sub_item_table
                if type(submenu_item.sub_item_table_func) == "function" then
                    sub_items = submenu_item.sub_item_table_func()
                end
                show_submenu(item_submenu_title(submenu_item), sub_items, refresh)
            end
        end
        if item.hold_callback and has_submenu(item) then
            item._zen_arrange_submenu_on_tap = true
        end
        ensure_submenu_callbacks(item.sub_item_table)
    end
end

show_submenu = function(title, items, refresh, opts)
    if type(items) ~= "table" or #items == 0 then return end
    opts = opts or {}
    if opts.return_to_parent == nil then
        opts.return_to_parent = refresh
    end
    ensure_submenu_callbacks(items)
    update_dynamic_text(items)

    local sort_widget
    local menu_proxy
    local function refresh_lists()
        if menu_proxy and type(menu_proxy.item_table) == "table" and menu_proxy.item_table ~= items then
            items = menu_proxy.item_table
        end
        ensure_submenu_callbacks(items)
        update_dynamic_text(items)
        refresh_after_callbacks(items, refresh_lists, menu_proxy)
        if sort_widget then
            sort_widget.item_table = items
            sort_widget._zen_arrange_done_func = items._zen_arrange_done_func or opts.done_func
            sort_widget._zen_arrange_done_enabled_func =
                items._zen_arrange_done_enabled_func or opts.done_enabled_func
            repopulate(sort_widget)
        end
        if refresh then refresh() end
    end

    menu_proxy = {
        item_table_stack = {},
        item_table = items,
        backToUpperMenu = function()
            if #menu_proxy.item_table_stack > 0 then
                items = table.remove(menu_proxy.item_table_stack)
                menu_proxy.item_table = items
                refresh_lists()
                return
            end
            if sort_widget then
                UIManager:close(sort_widget)
                sort_widget = nil
            end
            if refresh then refresh() end
        end,
        updateItems = function(self)
            if type(self.item_table) == "table" then
                items = self.item_table
            end
            refresh_lists()
        end,
    }
    refresh_after_callbacks(items, refresh_lists, menu_proxy)
    sort_widget = SortWidget:new{
        title = title,
        item_table = items,
        sort_disabled = false,
    }
    sort_widget.sort_disabled = true
    sort_widget._zen_arrange_close_all = opts.close_arrange
    sort_widget._zen_arrange_return_to_parent = function()
        if sort_widget then
            UIManager:close(sort_widget)
            sort_widget = nil
        end
        if type(opts.return_to_parent) == "function" then
            opts.return_to_parent()
        end
    end
    sort_widget._zen_arrange_done_func = items._zen_arrange_done_func or opts.done_func
    sort_widget._zen_arrange_done_enabled_func =
        items._zen_arrange_done_enabled_func or opts.done_enabled_func

    sort_widget.key_events = sort_widget.key_events or {}
    sort_widget.key_events.FocusRight = nil
    sort_widget.key_events.AlternativeFocusRight = nil
    sort_widget.key_events.ZenArrangeOpenSubmenu = {
        { "Right" },
        event = "ZenArrangeOpenSubmenu",
    }
    sort_widget.onZenArrangeOpenSubmenu = function(self)
        open_submenu_for_item(self, get_focused_item(self))
        return true
    end

    configure_title_bar(sort_widget)
    suppress_page_centering(sort_widget)
    sync_done_button(sort_widget, menu_proxy, opts)
    if sort_widget.title_bar and sort_widget.title_bar.left_button then
        sort_widget.title_bar.left_button.callback = function()
            menu_proxy:backToUpperMenu()
            return true
        end
    end
    suppress_footer_cancel(sort_widget.footer_cancel)
    suppress_footer_jump_buttons(sort_widget)
    suppress_footer_page_button(sort_widget)
    sync_footer_ok(sort_widget)
    apply_icon_rows(sort_widget)
    install_submenu_tap_handlers(sort_widget)

    local orig_populate = sort_widget._populateItems
    sort_widget._populateItems = function(self, ...)
        update_dynamic_text(self.item_table)
        local result = orig_populate(self, ...)
        suppress_page_centering(self)
        suppress_footer_cancel(self.footer_cancel)
        suppress_footer_jump_buttons(self)
        suppress_footer_page_button(self)
        sync_footer_ok(self)
        sync_done_button(self, menu_proxy, opts)
        apply_icon_rows(self)
        install_submenu_tap_handlers(self)
        install_titlebar_focus(self)
        return result
    end
    install_titlebar_focus(sort_widget)

    UIManager:show(sort_widget)
end

install_submenu_tap_handlers = function(sort_widget)
    if not sort_widget or not sort_widget.main_content then return end
    for _i, child in ipairs(sort_widget.main_content) do
        local item = type(child) == "table" and child.item or nil
        if item and item._zen_arrange_submenu_on_tap and not child._zen_arrange_submenu_tap_patched then
            child._zen_arrange_submenu_tap_patched = true
            child.onTap = function(row, _arg, ges)
                if item.checked_func and row.checkmark_widget and ges and ges.pos
                        and ges.pos:intersectWith(row.checkmark_widget.dimen) then
                    if item.callback then
                        item:callback()
                    end
                    repopulate(row.show_parent)
                    return true
                end
                open_submenu_for_item(row.show_parent, item)
                return true
            end
        end
    end
end

install_root_tap_handlers = function(sort_widget)
    if not sort_widget or not sort_widget.main_content then return end
    for _i, child in ipairs(sort_widget.main_content) do
        local item = type(child) == "table" and child.item or nil
        if item and not child._zen_arrange_root_hold_patched then
            child._zen_arrange_root_hold_patched = true
            child.onHoldTouch = function(row)
                toggle_arrange_selection(row)
                return true
            end
        end
        if item and item._zen_arrange_submenu_on_tap and not child._zen_arrange_root_tap_patched then
            child._zen_arrange_root_tap_patched = true
            child.onTap = function(row, _arg, ges)
                if item.checked_func and row.checkmark_widget and ges and ges.pos
                        and ges.pos:intersectWith(row.checkmark_widget.dimen) then
                    if item.callback then
                        item:callback()
                    end
                    repopulate(row.show_parent)
                    return true
                end
                open_submenu_for_item(row.show_parent, item)
                return true
            end
        end
    end
end

function M.show(opts)
    opts = opts or {}
    local item_table = opts.item_table or {}
    update_dynamic_text(item_table)
    ensure_submenu_callbacks(item_table)

    local sort_widget = SortWidget:new{
        title = opts.title or "",
        item_table = item_table,
        callback = opts.callback,
    }
    sort_widget._zen_arrange_refresh = function(self)
        if type(opts.refresh_func) == "function" then
            local refreshed = opts.refresh_func()
            if type(refreshed) == "table" then
                item_table = refreshed
                self.item_table = item_table
                ensure_submenu_callbacks(item_table)
                update_dynamic_text(item_table)
            end
        end
        self:_populateItems()
    end
    sort_widget._zen_arrange_close_all = function()
        if sort_widget.callback then
            sort_widget:callback()
        end
        sort_widget.marked = 0
        sort_widget.orig_item_table = nil
        return sort_widget:onClose()
    end
    local title_opts = {
        add_title = opts.add_title,
        add_item_table = opts.add_item_table,
        close_arrange = sort_widget._zen_arrange_close_all,
    }

    local orig_on_press = sort_widget.onPress
    sort_widget.onPress = function(self)
        if toggle_sort_item(self, get_focused_item(self)) then return true end
        return orig_on_press and orig_on_press(self)
    end
    sort_widget.key_events = sort_widget.key_events or {}
    sort_widget.key_events.ZenArrangeToggleReturn = {
        { "Return" },
        event = "ZenArrangeToggle",
    }
    sort_widget.onZenArrangeToggle = function(self)
        if toggle_sort_item(self, get_focused_item(self)) then return true end
        if has_rearranged_items(self) then
            return self:onReturn()
        end
        return true
    end
    sort_widget.key_events.FocusRight = nil
    sort_widget.key_events.AlternativeFocusRight = nil
    sort_widget.key_events.ZenArrangeOpenSubmenu = {
        { "Right" },
        event = "ZenArrangeOpenSubmenu",
    }
    sort_widget.onZenArrangeOpenSubmenu = function(self)
        if open_submenu_for_item(self, get_focused_item(self)) then return true end
        return true
    end

    configure_title_bar(sort_widget, title_opts)
    suppress_page_centering(sort_widget)
    if opts.hide_footer_cancel then
        suppress_footer_cancel(sort_widget.footer_cancel)
    else
        sync_footer_cancel(sort_widget)
    end
    suppress_footer_jump_buttons(sort_widget)
    suppress_footer_page_button(sort_widget)
    sync_footer_ok(sort_widget)
    apply_icon_rows(sort_widget)
    install_root_tap_handlers(sort_widget)
    patch_move_item_kb(sort_widget)
    local orig_populate = sort_widget._populateItems
    sort_widget._populateItems = function(self, ...)
        update_dynamic_text(self.item_table)
        local result = orig_populate(self, ...)
        suppress_page_centering(self)
        if opts.hide_footer_cancel then
            suppress_footer_cancel(self.footer_cancel)
        else
            sync_footer_cancel(self)
        end
        suppress_footer_jump_buttons(self)
        suppress_footer_page_button(self)
        sync_footer_ok(self)
        apply_icon_rows(self)
        install_root_tap_handlers(self)
        install_titlebar_focus(self)
        return result
    end
    install_titlebar_focus(sort_widget)

    UIManager:show(sort_widget)
    if opts.open_add_on_show and type(opts.add_item_table) == "table" and #opts.add_item_table > 0 then
        UIManager:nextTick(function()
            show_submenu(opts.add_title or "", opts.add_item_table, function()
                if sort_widget._zen_arrange_refresh then
                    sort_widget:_zen_arrange_refresh()
                else
                    repopulate(sort_widget)
                end
            end, {
                close_arrange = sort_widget._zen_arrange_close_all,
            })
        end)
    end
    return sort_widget
end

return M

-- zen_ui: bookmarks patch
-- Makes page numbers in the bookmark/highlight list slightly larger and
-- always renders them in black (instead of dimming future-page entries to gray).

local function apply_bookmarks()
    local ReaderBookmark = require("apps/reader/modules/readerbookmark")
    local Device = require("device")

    local function supports_hardware_focus()
        local has_dpad = type(Device.hasDPad) == "function" and Device:hasDPad()
        local has_keyboard = type(Device.hasKeyboard) == "function" and Device:hasKeyboard()
        return has_dpad or has_keyboard
    end

    local function add_icon_focus(button)
        if not button or button._zen_hardware_focus_patched then return end
        button._zen_hardware_focus_patched = true
        local orig_paint_to = button.paintTo
        button.onFocus = function(self_btn)
            self_btn._zen_keyboard_focused = true
            if self_btn.image then self_btn.image.invert = false end
            return true
        end
        button.onUnfocus = function(self_btn)
            self_btn._zen_keyboard_focused = nil
            if self_btn.image then self_btn.image.invert = false end
            return true
        end
        if orig_paint_to then
            button.paintTo = function(self_btn, bb, x, y)
                if self_btn.image then self_btn.image.invert = false end
                local result = orig_paint_to(self_btn, bb, x, y)
                local image_dimen = self_btn.image and self_btn.image.dimen
                if self_btn._zen_keyboard_focused and image_dimen then
                    local focus_pad = Device.screen:scaleBySize(3)
                    bb:invertRect(
                        image_dimen.x - focus_pad,
                        image_dimen.y - focus_pad,
                        image_dimen.w + 2 * focus_pad,
                        image_dimen.h + 2 * focus_pad
                    )
                end
                return result
            end
        end
    end

    local function install_hardware_focus(menu)
        if not supports_hardware_focus() or menu._zen_hardware_focus_patched then return end
        menu._zen_hardware_focus_patched = true
        local title_bar = menu.title_bar
        if not title_bar then return end
        add_icon_focus(title_bar.left_button)
        add_icon_focus(title_bar.right_button)

        menu.mergeTitleBarIntoLayout = function(self_m)
            local title_layout = self_m.title_bar and self_m.title_bar:generateHorizontalLayout() or {}
            for i, row in ipairs(title_layout) do
                table.insert(self_m.layout, i, row)
            end
            if self_m.selected then self_m.selected.y = self_m.selected.y + #title_layout end
        end

        local orig_on_key_press = menu.onKeyPress
        menu.onKeyPress = function(self_m, key)
            if key and type(key.match) == "function" then
                if key:match({ "Up" }) then
                    return self_m:onFocusMove({ 0, -1 })
                elseif key:match({ "Right" }) then
                    return self_m:onFocusMove({ 1, 0 })
                elseif key:match({ "Down" }) then
                    return self_m:onFocusMove({ 0, 1 })
                elseif key:match({ "Left" }) then
                    return self_m:onFocusMove({ -1, 0 })
                elseif key:match({ "Press" }) or key:match({ "Return" }) or key:match({ "Enter" }) then
                    return self_m:onPress()
                end
            end
            return orig_on_key_press and orig_on_key_press(self_m, key)
        end

        local orig_on_key_repeat = menu.onKeyRepeat
        menu.onKeyRepeat = function(self_m, key)
            if key and type(key.match) == "function" then
                if key:match({ "Up" }) then
                    return self_m:onFocusMove({ 0, -1 })
                elseif key:match({ "Right" }) then
                    return self_m:onFocusMove({ 1, 0 })
                elseif key:match({ "Down" }) then
                    return self_m:onFocusMove({ 0, 1 })
                elseif key:match({ "Left" }) then
                    return self_m:onFocusMove({ -1, 0 })
                end
            end
            return orig_on_key_repeat and orig_on_key_repeat(self_m, key)
        end
    end

    local function focus_back_button(menu)
        if not menu._zen_hardware_focus_patched then return end
        local back = menu.title_bar and menu.title_bar.left_button
        if not (back and menu.layout) then return end
        local Event = require("ui/event")
        local UIManager = require("ui/uimanager")
        for y, row in ipairs(menu.layout) do
            for x, widget in ipairs(row) do
                if widget == back then
                    local current_row = menu.selected and menu.layout[menu.selected.y]
                    local current = current_row and current_row[menu.selected.x]
                    if current and current ~= back and type(current.handleEvent) == "function" then
                        current:handleEvent(Event:new("Unfocus"))
                    end
                    menu.selected = { x = x, y = y }
                    if type(back.handleEvent) == "function" then
                        back:handleEvent(Event:new("Focus"))
                    elseif type(back.onFocus) == "function" then
                        back:onFocus()
                    end
                    UIManager:setDirty(menu.show_parent or menu, "fast")
                    return
                end
            end
        end
    end

    local _orig_onShowBookmark = ReaderBookmark.onShowBookmark

    ReaderBookmark.onShowBookmark = function(self, ...)
        _orig_onShowBookmark(self, ...)

        local bm_menu = self.bookmark_menu and self.bookmark_menu[1]
        if not bm_menu then return end

        -- Default mandatory (page number) font size is font_size - 4.
        -- Use font_size - 2 for a slightly larger page number.
        bm_menu.items_mandatory_font_size = (bm_menu.font_size or 18) - 2

        -- Wrap the instance's updateItems so that every subsequent re-render
        -- (page turns, filter/sort, bulk-select) also clears mandatory_dim,
        -- keeping page numbers in black.
        if not bm_menu._zen_bm_patched then
            bm_menu._zen_bm_patched = true
            local _orig_updateItems = bm_menu.updateItems
            bm_menu.updateItems = function(self_m, ...)
                for _i, item in ipairs(self_m.item_table or {}) do
                    item.mandatory_dim = nil
                end
                return _orig_updateItems(self_m, ...)
            end
        end

        -- Swap title-bar icons: left chevron (close) on the left,
        -- hamburger (filter/sort menu) on the right.
        local tb = bm_menu.title_bar
        if tb and tb.left_button and tb.right_button then
            local orig_left_tap  = tb.left_button.callback
            local orig_left_hold = tb.left_button.hold_callback
            local orig_right_tap = tb.right_button.callback
            -- Left: chevron.left = close the bookmark list
            tb.left_button:setIcon("chevron.left")
            tb.left_button.callback      = orig_right_tap
            tb.left_button.hold_callback = nil
            -- Right: appbar.menu = original left-button action
            tb.right_button:setIcon("appbar.menu")
            tb.right_button.callback      = orig_left_tap
            tb.right_button.hold_callback = orig_left_hold
        end

        install_hardware_focus(bm_menu)

        -- Apply immediately to items already built by onShowBookmark.
        for _i, item in ipairs(bm_menu.item_table) do
            item.mandatory_dim = nil
        end
        bm_menu:updateItems(1, true)
        focus_back_button(bm_menu)
    end
end

return apply_bookmarks

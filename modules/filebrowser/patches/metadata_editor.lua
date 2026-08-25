local function apply_metadata_editor()
    local Device = require("device")
    local BookInfo = require("apps/filemanager/filemanagerbookinfo")
    local Button = require("ui/widget/button")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local KeyValuePage = require("ui/widget/keyvaluepage")
    local TitleBar = require("ui/widget/titlebar")
    local pager = require("common/ui/zen_pager")
    local ZenSettingsTitleBar = require("common/ui/zen_settings_titlebar")
    local _ = require("gettext")

    if BookInfo._zen_details_navigation_patched then return end
    BookInfo._zen_details_navigation_patched = true
    pager.setPlugin(rawget(_G, "__ZEN_UI_PLUGIN"))

    local pending_details_context

    local function clear_rename_hook(page)
        local hook = page._zen_rename_hook
        if not hook then return end
        if rawget(hook.file_manager, "moveFile") == hook.wrapper then
            rawset(hook.file_manager, "moveFile", hook.previous)
        end
        page._zen_rename_hook = nil
    end

    local function watch_rename(page, context, entry, file_manager, source)
        clear_rename_hook(page)
        local move_file = file_manager.moveFile
        if type(move_file) ~= "function" then return end
        local previous = rawget(file_manager, "moveFile")
        local wrapper
        wrapper = function(self, from, to, ...)
            local moved = move_file(self, from, to, ...)
            if moved and from == source then
                clear_rename_hook(page)
                context.file = to
                entry[2] = require("ffi/util").basename(to)
                page:_populateItems()
            end
            return moved
        end
        page._zen_rename_hook = {
            file_manager = file_manager,
            previous = previous,
            wrapper = wrapper,
        }
        rawset(file_manager, "moveFile", wrapper)
    end

    local function install_metadata_actions(page, context)
        local file_manager = context.bookinfo and context.bookinfo.ui
        if type(context.file) ~= "string" or type(page.kv_pairs) ~= "table" then return end

        local format_index
        for index, entry in ipairs(page.kv_pairs) do
            if type(entry) == "table" then
                if entry[1] == _("Filename:")
                        and file_manager
                        and type(file_manager.showRenameFileDialog) == "function" then
                    entry.hold_callback = function()
                        local file = context.file
                        watch_rename(page, context, entry, file_manager, file)
                        file_manager:showRenameFileDialog(file, true)
                    end
                elseif entry[1] == _("Format:") then
                    format_index = index
                end
            end
        end

        if format_index and file_manager
                and type(file_manager.showOpenWithDialog) == "function" then
            page._zen_open_with_format_index = format_index
            page._zen_open_with_callback = function()
                file_manager:showOpenWithDialog(context.file)
            end
        end
    end

    local function install_close_cleanup(page)
        local orig_on_close = page.onClose
        if type(orig_on_close) ~= "function" then return end
        page.onClose = function(self, ...)
            clear_rename_hook(self)
            return orig_on_close(self, ...)
        end
    end

    local function install_open_with_button(page)
        local format_index = page._zen_open_with_format_index
        if not (format_index and page.layout) then return end

        for _row_i, layout_row in ipairs(page.layout) do
            local item = layout_row[1]
            if item and item.kv_pairs_idx == format_index then
                local content_row = item[1] and item[1][1]
                local value_container = content_row and content_row[3]
                local value_widget = value_container and value_container[1]
                if not value_widget then return end

                local Screen = Device.screen
                local button = Button:new{
                    text = _("Open with…"),
                    text_font_face = "cfont",
                    text_font_size = tonumber(page.items_font_size) or 20,
                    text_font_bold = true,
                    margin = 0,
                    bordersize = Screen:scaleBySize(2),
                    radius = Screen:scaleBySize(10),
                    padding_h = Screen:scaleBySize(10),
                    padding_v = Screen:scaleBySize(3),
                    show_parent = page,
                    callback = page._zen_open_with_callback,
                }
                button._zen_metadata_open_with = true
                value_container[1] = HorizontalGroup:new{
                    align = "center",
                    value_widget,
                    HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                    button,
                }
                if type(content_row.resetLayout) == "function" then
                    content_row:resetLayout()
                end
                layout_row[1] = button
                return
            end
        end
    end

    local function new_zen_header(values, context)
        local close_callback = values.close_callback
        if type(context.close_parent_callback) == "function" then
            close_callback = function()
                local result = values.close_callback and values.close_callback()
                context.close_parent_callback()
                return result == nil and true or result
            end
        end
        return ZenSettingsTitleBar:new{
            width = values.width,
            title = values.title,
            title_full_width = true,
            back_visible = values.left_icon ~= nil,
            search_visible = false,
            show_parent = values.show_parent,
            status_factory = function() end,
            back_callback = values.left_icon_tap_callback,
            back_hold_callback = values.left_icon_hold_callback,
            close_callback = close_callback,
        }
    end

    local function install_pager(page)
        local page_info = page.page_info
        if not (page_info and page.dimen and page.registerTouchZones) then return end

        local Screen = Device.screen
        local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
        local footer_h = math.max(1, tonumber(page_info:getSize().h) or pager.PN_FOOTER_H)
        local footer_y = page.dimen.y + page.dimen.h - footer_h
        local bar_x, bar_w = pager.getFooterGeometry(page.dimen.x, page.dimen.w)
        local chevron_w = pager.getChevronHitWidth(bar_w)

        local function can_navigate()
            return pager.getStyle() == "page_number" and (page.pages or 0) > 1
        end

        local function jump(direction)
            if not can_navigate() then return end
            local current = page.show_page or 1
            local skip = pager.getHoldSkip()
            local target
            if skip == "ends" then
                target = direction < 0 and 1 or page.pages
            else
                target = current + direction * (tonumber(skip) or 10)
                target = math.max(1, math.min(page.pages, target))
            end
            page:onGoToPage(target)
            return true
        end

        page_info.propagateEvent = function() return false end
        page_info.paintTo = function(_self, bb, _x, y)
            pager.paint(bb, bar_x, y, bar_w, footer_h,
                page.show_page or 1, page.pages or 1)
        end

        local hit_bottom = pager.getChevronHitBottom(
            footer_y, footer_h, page.dimen.y + page.dimen.h)
        local side_h = hit_bottom - footer_y
        page:registerTouchZones({
            {
                id = "zen_metadata_editor_left_tap",
                ges = "tap",
                screen_zone = {
                    ratio_x = bar_x / screen_w,
                    ratio_y = footer_y / screen_h,
                    ratio_w = chevron_w / screen_w,
                    ratio_h = side_h / screen_h,
                },
                handler = function()
                    if not can_navigate() then return end
                    return page:onPrevPage()
                end,
            },
            {
                id = "zen_metadata_editor_right_tap",
                ges = "tap",
                screen_zone = {
                    ratio_x = (bar_x + bar_w - chevron_w) / screen_w,
                    ratio_y = footer_y / screen_h,
                    ratio_w = chevron_w / screen_w,
                    ratio_h = side_h / screen_h,
                },
                handler = function()
                    if not can_navigate() then return end
                    return page:onNextPage()
                end,
            },
            {
                id = "zen_metadata_editor_center_tap",
                ges = "tap",
                screen_zone = {
                    ratio_x = (bar_x + chevron_w) / screen_w,
                    ratio_y = footer_y / screen_h,
                    ratio_w = math.max(0, bar_w - 2 * chevron_w) / screen_w,
                    ratio_h = footer_h / screen_h,
                },
                handler = function()
                    if not can_navigate() then return end
                    local button = page.page_info_text
                    if button and type(button.onTapSelectButton) == "function" then
                        button:onTapSelectButton()
                    end
                    return true
                end,
            },
            {
                id = "zen_metadata_editor_left_hold",
                ges = "hold",
                screen_zone = {
                    ratio_x = bar_x / screen_w,
                    ratio_y = footer_y / screen_h,
                    ratio_w = chevron_w / screen_w,
                    ratio_h = side_h / screen_h,
                },
                handler = function() return jump(-1) end,
            },
            {
                id = "zen_metadata_editor_right_hold",
                ges = "hold",
                screen_zone = {
                    ratio_x = (bar_x + bar_w - chevron_w) / screen_w,
                    ratio_y = footer_y / screen_h,
                    ratio_w = chevron_w / screen_w,
                    ratio_h = side_h / screen_h,
                },
                handler = function() return jump(1) end,
            },
        })
    end

    local orig_populate_items = KeyValuePage._populateItems
    KeyValuePage._populateItems = function(self, ...)
        local result = orig_populate_items(self, ...)
        install_open_with_button(self)
        if self.title_bar and type(self.title_bar.installFocusLayout) == "function" then
            self.title_bar:installFocusLayout(self)
        end
        return result
    end

    local orig_keyvalue_init = KeyValuePage.init
    KeyValuePage.init = function(self, ...)
        local details_context = pending_details_context
        if details_context then
            self.title_bar_left_icon = true
            self.title_bar_left_icon_tap_callback = function()
                return self:onClose()
            end
            install_metadata_actions(self, details_context)
        end
        local ok, result
        if details_context then
            local orig_titlebar_new = TitleBar.new
            TitleBar.new = function(_class, values)
                return new_zen_header(values, details_context)
            end
            ok, result = pcall(orig_keyvalue_init, self, ...)
            TitleBar.new = orig_titlebar_new
            if not ok then error(result, 0) end
            install_close_cleanup(self)
            install_pager(self)
        else
            result = orig_keyvalue_init(self, ...)
        end
        return result
    end

    local orig_show = BookInfo.show
    function BookInfo:showFromBookDetails(doc_settings_or_file, book_props, options)
        local file = doc_settings_or_file
        if type(file) == "table" and type(file.readSetting) == "function" then
            file = file:readSetting("doc_path")
        end
        pending_details_context = {
            bookinfo = self,
            file = file,
            close_parent_callback = type(options) == "table"
                and options.close_parent_callback or nil,
        }
        local ok, result = pcall(orig_show, self, doc_settings_or_file, book_props)
        pending_details_context = nil
        if not ok then error(result, 0) end
        return result
    end
end

return apply_metadata_editor

-- Full-screen paginated single-select list picker.

local function showMenuPicker(opts)
    local _          = require("gettext")
    local Device     = require("device")
    local Screen     = Device.screen
    local Geom       = require("ui/geometry")
    local Blitbuffer = require("ffi/blitbuffer")
    local Font       = require("ui/font")
    local Size       = require("ui/size")
    local UIManager  = require("ui/uimanager")
    local FocusManager = require("ui/widget/focusmanager")
    local IW         = require("ui/widget/iconwidget")
    local TW         = require("ui/widget/textwidget")
    local pager      = require("common/ui/zen_pager")

    opts = opts or {}
    local items = type(opts.items) == "table" and opts.items or {}
    local on_select = type(opts.on_select) == "function" and opts.on_select or function() end
    local back_hold_callback = opts.back_hold_callback
    if type(back_hold_callback) ~= "function" then
        local settings_page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        if settings_page and settings_page.backToRootMenu then
            back_hold_callback = function()
                return settings_page:backToRootMenu()
            end
        end
    end

    local sw, sh   = Screen:getWidth(), Screen:getHeight()
    local pad      = Size.padding.default
    local span     = Size.span.vertical_default
    local row_pad  = Screen:scaleBySize(12)
    local row_h    = Screen:scaleBySize(48)
    local row_face = Font:getFace("cfont", 24)
    local indent_step = Screen:scaleBySize(16)
    local content_w = sw - 2 * pad
    local bar_area_h = pager.PN_FOOTER_H
    local divider_gap = Size.padding.default
    local divider_pad = Size.padding.large
    local divider_h   = Size.line.thick

    local back_sz  = Screen:scaleBySize(24)
    local back_gap = Screen:scaleBySize(6)
    local back_iw  = IW:new{ icon = "chevron.left", width = back_sz, height = back_sz }

    local title_text_w = content_w - back_sz - back_gap
    local title_tw = TW:new{
        text  = opts.title or _("Choose item"),
        face  = Font:getFace("smallinfofont"),
        bold  = true,
        width = title_text_w,
    }
    local title_text_h = title_tw:getSize().h
    local title_h      = math.max(back_sz, title_text_h)
    local title_block_h = title_h + divider_gap + divider_h + divider_gap

    local content_x = pad
    local content_y = pad
    local list_x    = content_x
    local divider_y = content_y + title_h + divider_gap
    local list_y    = content_y + title_block_h
    local overhead  = 2 * pad + title_block_h + span + bar_area_h
    local list_h    = math.max(row_h, sh - overhead)
    local rows_per_page = math.max(1, math.floor(list_h / row_h))
    local page_h    = rows_per_page * row_h
    local bar_y = pager.getCenteredFooterY(
        list_y + page_h,
        sh - pad - bar_area_h,
        bar_area_h,
        true
    )
    local total_pages = math.max(1, math.ceil(math.max(#items, 1) / rows_per_page))
    local cur_page = 1

    local dialog
    local closed = false
    local selected_idx = #items > 0 and 1 or nil
    local back_focused = #items == 0

    local function closeDialog()
        if closed then return end
        closed = true
        UIManager:close(dialog, "ui")
        UIManager:forceRePaint()
    end

    local function backToSettingsRoot()
        closeDialog()
        if back_hold_callback then back_hold_callback() end
        return true
    end

    local function goToPage(page)
        if page < 1 or page > total_pages then return end
        cur_page = page
        UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
    end

    local function selectItem(item)
        if not item then return true end
        closeDialog()
        UIManager:nextTick(function()
            local ok_select, err = xpcall(function()
                on_select(item)
            end, debug.traceback)
            if not ok_select then
                require("common/zen_logger").new("zen_menu_picker").warn("Selection failed:", err)
            end
        end)
        return true
    end

    local function moveSelection(diff)
        if back_focused then
            if diff > 0 and selected_idx then
                back_focused = false
                selected_idx = 1
                goToPage(1)
            end
            return true
        end
        if not selected_idx then return true end
        if diff < 0 and selected_idx == 1 then
            back_focused = true
            UIManager:setDirty(dialog, function() return "ui", dialog.dimen end)
            return true
        end
        selected_idx = ((selected_idx - 1 + diff) % #items) + 1
        goToPage(math.ceil(selected_idx / rows_per_page))
        return true
    end

    local function changePage(diff)
        if total_pages <= 1 then return true end
        local row_i = (selected_idx - 1) % rows_per_page
        local page = ((cur_page - 1 + diff) % total_pages) + 1
        local first = (page - 1) * rows_per_page + 1
        selected_idx = math.min(first + row_i, #items)
        goToPage(page)
        return true
    end

    local function canUsePageNumber()
        return total_pages > 1
    end

    local function inPageNumberBar(gx, gy)
        return canUsePageNumber()
            and gy >= bar_y and gy < bar_y + bar_area_h
            and gx >= content_x and gx < content_x + content_w
    end

    local function pageNumberZone(gx)
        if gx < content_x + pager.CHEV_W then return "left" end
        if gx >= content_x + content_w - pager.CHEV_W then return "right" end
        return "center"
    end

    local function handlePageNumberTap(gx, gy)
        if not inPageNumberBar(gx, gy) then return false end
        local zone = pageNumberZone(gx)
        if zone == "left" then
            goToPage(cur_page > 1 and cur_page - 1 or total_pages)
        elseif zone == "right" then
            goToPage(cur_page < total_pages and cur_page + 1 or 1)
        end
        return true
    end

    local function handlePageNumberHold(gx, gy)
        if not inPageNumberBar(gx, gy) then return false end
        local zone = pageNumberZone(gx)
        if zone == "left" then
            local skip = pager.getHoldSkip()
            goToPage(skip == "ends" and 1 or math.max(1, cur_page - (tonumber(skip) or 10)))
            return true
        elseif zone == "right" then
            local skip = pager.getHoldSkip()
            goToPage(skip == "ends" and total_pages or math.min(total_pages, cur_page + (tonumber(skip) or 10)))
            return true
        end
        return true
    end

    local Picker = FocusManager:extend{}

    function Picker:init()
        self:_init()
        self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
        if Device:hasKeys() then
            self.key_events.CancelOrClose = { { Device.input.group.Back } }
            self.key_events.MenuPickerPrevPage = { { Device.input.group.PgBack }, event = "MenuPickerPage", args = -1 }
            self.key_events.MenuPickerPageForward = { { Device.input.group.PgFwd }, event = "MenuPickerPage", args = 1 }
            if not Device:hasDPad() then
                self.key_events.MenuPickerUp = { { "Up" }, event = "MenuPickerMove", args = -1 }
                self.key_events.MenuPickerDown = { { "Down" }, event = "MenuPickerMove", args = 1 }
                self.key_events.MenuPickerPreviousPage = { { "Left" }, event = "MenuPickerPage", args = -1 }
                self.key_events.MenuPickerNextPage = { { "Right" }, event = "MenuPickerPage", args = 1 }
                self.key_events.MenuPickerSelect = { { "Press" }, event = "MenuPickerSelect" }
            end
        end
        self:registerTouchZones({
            {
                id          = "zen_menu_picker_tap",
                ges         = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler     = function(ges)
                    local gx, gy = ges.pos.x, ges.pos.y
                    if gx >= content_x and gx < content_x + back_sz
                       and gy >= content_y and gy < content_y + title_h then
                        closeDialog()
                        return true
                    end
                    if handlePageNumberTap(gx, gy) then return true end
                    if gx >= list_x and gx < list_x + content_w
                       and gy >= list_y and gy < list_y + page_h then
                        local row_i = math.floor((gy - list_y) / row_h)
                        local idx = (cur_page - 1) * rows_per_page + row_i + 1
                        selectItem(items[idx])
                    end
                    return true
                end,
            },
            {
                id          = "zen_menu_picker_hold",
                ges         = "hold",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler     = function(ges)
                    local gx, gy = ges.pos.x, ges.pos.y
                    if gx >= content_x and gx < content_x + content_w
                            and gy >= content_y and gy < content_y + title_h then
                        return backToSettingsRoot()
                    end
                    return handlePageNumberHold(gx, gy)
                end,
            },
            {
                id          = "zen_menu_picker_swipe",
                ges         = "swipe",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler     = function(ges)
                    if ges.direction == "west" then
                        goToPage(cur_page + 1)
                    elseif ges.direction == "east" then
                        goToPage(cur_page - 1)
                    end
                    return true
                end,
            },
        })
    end

    function Picker:onCancelOrClose()
        closeDialog()
        return true
    end

    function Picker:onMenuPickerMove(diff)
        return moveSelection(diff)
    end

    function Picker:onMenuPickerPage(diff)
        return changePage(diff)
    end

    function Picker:onFocusMove(args)
        local dx = args and args[1] or 0
        local dy = args and args[2] or 0
        if dy ~= 0 then return moveSelection(dy) end
        if back_focused then return true end
        if dx ~= 0 then return changePage(dx) end
        return true
    end

    function Picker:onPress()
        if back_focused then
            closeDialog()
            return true
        end
        return selectItem(selected_idx and items[selected_idx])
    end

    function Picker:onMenuPickerSelect()
        return self:onPress()
    end

    function Picker:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        bb:paintRect(0, 0, sw, sh, Blitbuffer.COLOR_WHITE)

        back_iw.invert = back_focused
        back_iw:paintTo(bb, content_x, content_y + math.floor((title_h - back_sz) / 2))
        title_tw:paintTo(bb, content_x + back_sz + back_gap,
            content_y + math.floor((title_h - title_text_h) / 2))
        bb:paintRect(divider_pad, divider_y, sw - 2 * divider_pad,
            divider_h, Blitbuffer.COLOR_DARK_GRAY)

        local first = (cur_page - 1) * rows_per_page + 1
        local last = math.min(#items, first + rows_per_page - 1)
        for idx = first, last do
            local row_i = idx - first
            local row_y = list_y + row_i * row_h
            local item = items[idx]
            local text = type(item.text) == "string" and item.text or tostring(item.text or "")
            local text_indent = math.max(0, tonumber(item.indent_level) or 0) * indent_step
            local selected = not back_focused
                and (not Device:isTouchDevice() or Device:hasDPad() or Device:hasKeyboard())
                and idx == selected_idx
            if selected then
                bb:paintRect(list_x, row_y, content_w, row_h, Blitbuffer.COLOR_BLACK)
            end
            local tw = TW:new{
                text      = text,
                face      = row_face,
                bold      = item.bold == true,
                max_width = content_w - row_pad * 2 - text_indent,
                padding   = 0,
                fgcolor   = selected and Blitbuffer.COLOR_WHITE or nil,
            }
            local sz = tw:getSize()
            tw:paintTo(bb, list_x + row_pad + text_indent,
                row_y + math.floor((row_h - sz.h) / 2))
            tw:free()
            bb:paintRect(list_x, row_y + row_h - 1, content_w, 1, Blitbuffer.COLOR_LIGHT_GRAY)
        end

        pager.paint(bb, content_x, bar_y, content_w, bar_area_h, cur_page, total_pages, "page_number")
    end

    dialog = Picker:new{}
    UIManager:show(dialog, "full")
end

return showMenuPicker

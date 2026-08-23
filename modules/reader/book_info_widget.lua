local InputContainer = require("ui/widget/container/inputcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Cover = require("common/cover_utils")
local BookProgress = require("common/ui/book_progress")
local TruncatedTextMessage = require("common/ui/truncated_text_message")
local TitleStyle = require("common/ui/zen_title_style")
local utils = require("common/utils")
local TopMenu = require("modules/global/patches/menu_top_swipe")
local icons = require("common/inline_icon_map")
local _ = require("gettext")

local COVER_BORDER_COLOR = Blitbuffer.COLOR_BLACK
local DESCRIPTION_MIN_SCREEN_RATIO = 0.50

local function supports_hardware_focus()
    local has_dpad = type(Device.hasDPad) == "function" and Device:hasDPad()
    local has_keyboard = type(Device.hasKeyboard) == "function" and Device:hasKeyboard()
    return has_dpad or has_keyboard
end

local BookInfoWidget = InputContainer:extend{
    title = nil,
    details = nil,
    description = nil,
    cover = nil,
    cover_width = nil,
    cover_height = nil,
    cover_tap_callback = nil,
    edit_callback = nil,
    close_all_callback = nil,
    rounded_cover = false,
    text_face = nil,
    text_size = nil,
    text_faces = nil,
    progress = nil,
    progress_pages = nil,
    progress_right_text = nil,
}

local function resolve_stock_icon(name)
    local lfs = require("libs/libkoreader-lfs")
    return utils.resolveLocalIcon(lfs.currentdir() .. "/resources/icons/mdlight/", name)
end

function BookInfoWidget:init()
    local sw = Device.screen:getWidth()
    local sh = Device.screen:getHeight()
    local pad = Device.screen:scaleBySize(16)
    local title_h = TitleStyle.HEADER_CONTENT_HEIGHT
    local title_divider_h = TitleStyle.DIVIDER_HEIGHT
    local gap = Device.screen:scaleBySize(14)
    local metadata_gap = Device.screen:scaleBySize(32)
    local body_y = title_h + title_divider_h + pad
    self._text_face = self.text_face or Font:getFace("cfont", self.text_size or 16)
    self._text_faces = self.text_faces or {}
    local description_overhead = 2 * gap + 1
    local description_available_h = math.max(
        0, sh - body_y - description_overhead - pad)
    local description_min_h = math.min(
        description_available_h,
        math.max(Device.screen:scaleBySize(80),
            math.ceil(sh * DESCRIPTION_MIN_SCREEN_RATIO)))
    local max_header_h = math.max(
        0, description_available_h - description_min_h)
    local cover_w = self.cover and (self.cover_width or 0) or 0
    local cover_h = self.cover and (self.cover_height or 0) or 0
    local max_cover_h = math.min(max_header_h,
        math.max(Device.screen:scaleBySize(100), math.floor(sh * 0.30)))
    if max_cover_h <= 0 then
        cover_w, cover_h = 0, 0
    elseif cover_h > max_cover_h and cover_h > 0 then
        local scale = max_cover_h / cover_h
        cover_w = math.floor(cover_w * scale)
        cover_h = max_cover_h
    end

    local border = Cover.BORDER_SIZE

    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self._L = {
        sw = sw,
        sh = sh,
        pad = pad,
        gap = gap,
        title_h = title_h,
        title_divider_h = title_divider_h,
        body_y = body_y,
        back_x = TitleStyle.LEFT_PADDING,
        back_w = TitleStyle.BUTTON_SIZE,
        close_all_x = sw - TitleStyle.RIGHT_PADDING - TitleStyle.BUTTON_SIZE,
        close_all_w = TitleStyle.BUTTON_SIZE,
        cover_x = pad + border,
        cover_y = body_y,
        cover_w = cover_w,
        cover_h = cover_h,
        cover_border = border,
        details_x = pad + cover_w + (cover_w > 0 and 2 * border + metadata_gap or 0),
    }

    if self.edit_callback then
        self._edit_widget = TextWidget:new{
            text = icons.edit .. "  " .. _("Edit"),
            face = Font:getFace("smallinfofont", TitleStyle.ICON_BASE_SIZE),
            fgcolor = Blitbuffer.COLOR_BLACK,
            padding = 0,
        }
        local edit_size = self._edit_widget:getSize()
        self._L.edit_w = edit_size.w + 2 * TitleStyle.BUTTON_PADDING
        self._L.edit_close_gap = Device.screen:scaleBySize(12)
        self._L.edit_x = self._L.close_all_x
            - self._L.edit_close_gap - self._L.edit_w
    end

    local title_right = self._L.edit_x or self._L.close_all_x
    local details_w = math.max(Device.screen:scaleBySize(60), sw - self._L.details_x - pad)
    self._title_widget = TextWidget:new{
        text = self.title or _("Book details"),
        face = TitleStyle.getTitleFace(),
        bold = true,
        max_width = math.max(1, title_right - TitleStyle.getTitleX(0)),
        padding = 0,
    }
    self._L.title_x = TitleStyle.getTitleX(0)
    self._L.title_w = self._title_widget:getSize().w
    self._detail_widgets = {}
    for _i, detail in ipairs(self.details or {}) do
        local face = self._text_faces[detail.style] or self._text_face
        local widget = TextWidget:new{
            text = tostring(detail.text):gsub("%s*\n%s*", " "),
            face = face,
            bold = detail.bold == true,
            max_width = details_w,
            truncate_with_ellipsis = true,
            padding = 0,
        }
        local size = widget:getSize()
        local gap_before = Device.screen:scaleBySize(detail.gap_before or 0)
        if _i > 1 then gap_before = gap_before + Device.screen:scaleBySize(2) end
        local truncated = widget:isTruncated()
        table.insert(self._detail_widgets, {
            widget = widget,
            h = size.h,
            gap_before = gap_before,
            style = detail.style,
            truncated = truncated,
            full_text = widget.text,
            dimen = truncated and Geom:new{ w = details_w, h = size.h } or nil,
        })
    end
    if tonumber(self.progress) then
        self._progress_gap = Device.screen:scaleBySize(10)
        self._progress_widget = BookProgress.build{
            ratio = self.progress,
            pages = self.progress_pages,
            right_text = self.progress_right_text,
            width = details_w,
            bar_height = math.max(2, Device.screen:scaleBySize(6)),
            face = self._text_faces.secondary or self._text_face,
        }
        if self._progress_widget then
            self._progress_h = self._progress_widget:getSize().h
        end
    end

    local progress_layout_h = self._progress_widget
        and self._progress_gap + self._progress_h or 0
    local bottom_details_h = progress_layout_h
    for _i, entry in ipairs(self._detail_widgets) do
        if entry.style == "page" then
            bottom_details_h = bottom_details_h + entry.gap_before + entry.h
        end
    end
    local top_details_h = 0
    for _i, entry in ipairs(self._detail_widgets) do
        local entry_h = entry.gap_before + entry.h
        if entry.style == "page" then
            entry.visible = true
        elseif top_details_h + entry_h + bottom_details_h <= max_header_h then
            entry.visible = true
            top_details_h = top_details_h + entry_h
        end
    end
    self._progress_visible = self._progress_widget ~= nil
    self._bottom_details_h = bottom_details_h
    local details_h = top_details_h + bottom_details_h

    self._L.header_h = math.min(max_header_h, math.max(cover_h, details_h))
    self._L.description_divider_y = body_y + self._L.header_h + gap
    self._L.description_y = self._L.description_divider_y + 1 + gap
    self._L.description_min_h = description_min_h
    self._L.description_h = math.max(
        description_min_h, sh - self._L.description_y - pad)
    self._L.description_x = pad
    self._L.description_w = sw - pad * 2

    self._back_icon = IconWidget:new{
        file = resolve_stock_icon("chevron.left"),
        width = TitleStyle.ICON_SIZE,
        height = TitleStyle.ICON_SIZE,
    }
    self._close_icon = IconWidget:new{
        file = resolve_stock_icon("close"),
        width = TitleStyle.ICON_SIZE,
        height = TitleStyle.ICON_SIZE,
    }
    if self.cover and cover_w > 0 and cover_h > 0 then
        self._cover_widget = ImageWidget:new{
            image = self.cover,
            image_disposable = true,
            width = cover_w,
            height = cover_h,
            original_in_nightmode = true,
        }
    end
    self._description_widget = ScrollTextWidget:new{
        text = self.description ~= "" and self.description or _("No description."),
        face = self._text_face,
        fgcolor = Blitbuffer.COLOR_BLACK,
        width = self._L.description_w,
        height = self._L.description_h,
        dialog = self,
        alignment = "left",
        justified = false,
        scroll_by_pan = true,
    }
    self._zen_focus_enabled = supports_hardware_focus()
    if self._zen_focus_enabled then self._zen_focus_area = "back" end

    self:registerTouchZones({
        {
            id = "zen_book_info_tap",
            ges = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:_onTap(ges) end,
        },
        {
            id = "zen_book_info_swipe",
            ges = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:_onSwipe(ges) end,
        },
        {
            id = "zen_book_info_hold",
            ges = "hold",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:_onHold(ges) end,
        },
        {
            id = "zen_book_info_pan",
            ges = "pan",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:_onPan(ges) end,
        },
        {
            id = "zen_book_info_pan_release",
            ges = "pan_release",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler = function(ges) return self:_onPanRelease(ges) end,
        },
    })
    if Device:hasKeys() then
        self.key_events = {
            Close = { { Device.input.group.Back } },
            BookInfoPageUp = {
                { Device.input.group.PgBack },
                event = "BookInfoPage",
                args = -1,
            },
            BookInfoPageDown = {
                { Device.input.group.PgFwd },
                event = "BookInfoPage",
                args = 1,
            },
        }
    end
end

function BookInfoWidget:_setFocusArea(area)
    if not self._zen_focus_enabled or self._zen_focus_area == area then return end
    self._zen_focus_area = area
    UIManager:setDirty(self, "fast")
end

function BookInfoWidget:_scrollDescription(lines)
    local description = self._description_widget
    local text_widget = description and description.text_widget
    if text_widget and type(text_widget.scrollLines) == "function" then
        text_widget:scrollLines(lines)
        description:updateScrollBar(true)
    elseif description and type(description.scrollText) == "function" then
        description:scrollText(lines)
    end
    return true
end

function BookInfoWidget:_descriptionAtTop()
    local description = self._description_widget
    local text_widget = description and description.text_widget
    local line = text_widget and tonumber(text_widget.virtual_line_num)
    if line then return line <= 1 end
    local low = description and tonumber(description.prev_low)
    return low ~= nil and low <= 0
end

function BookInfoWidget:onBookInfoPage(direction)
    local description = self._description_widget
    if direction < 0 and description and type(description.onScrollUp) == "function" then
        description:onScrollUp()
    elseif direction > 0 and description and type(description.onScrollDown) == "function" then
        description:onScrollDown()
    end
    if self._zen_focus_enabled then self:_setFocusArea("description") end
    return true
end

local _orig_onKeyPress = InputContainer.onKeyPress
function BookInfoWidget:onKeyPress(key)
    if self._zen_focus_enabled and key and type(key.match) == "function" then
        if key:match({ "Up" }) then
            if self._zen_focus_area == "description" then
                if self:_descriptionAtTop() then
                    self:_setFocusArea("back")
                    return true
                end
                return self:_scrollDescription(-1)
            end
            return true
        elseif key:match({ "Right" }) and self._zen_focus_area == "back" then
            self:_setFocusArea(self._edit_widget and "edit" or "close")
            return true
        elseif key:match({ "Right" }) and self._zen_focus_area == "edit" then
            self:_setFocusArea("close")
            return true
        elseif key:match({ "Left" }) and self._zen_focus_area == "close" then
            self:_setFocusArea(self._edit_widget and "edit" or "back")
            return true
        elseif key:match({ "Left" }) and self._zen_focus_area == "edit" then
            self:_setFocusArea("back")
            return true
        elseif key:match({ "Down" }) then
            if self._zen_focus_area == "back" or self._zen_focus_area == "edit"
                    or self._zen_focus_area == "close" then
                self:_setFocusArea("description")
                return true
            end
            return self:_scrollDescription(1)
        elseif key:match({ "Press" }) or key:match({ "Return" }) or key:match({ "Enter" }) then
            if self._zen_focus_area == "back" then return self:onClose() end
            if self._zen_focus_area == "edit" then return self:onEdit() end
            if self._zen_focus_area == "close" then return self:onCloseAll() end
            return true
        end
    end
    return _orig_onKeyPress and _orig_onKeyPress(self, key)
end

local _orig_onKeyRepeat = InputContainer.onKeyRepeat
function BookInfoWidget:onKeyRepeat(key)
    if self._zen_focus_enabled and key and type(key.match) == "function" then
        if key:match({ "Up" }) and self._zen_focus_area == "description" then
            if self:_descriptionAtTop() then
                self:_setFocusArea("back")
                return true
            end
            return self:_scrollDescription(-1)
        elseif key:match({ "Down" }) and self._zen_focus_area == "description" then
            return self:_scrollDescription(1)
        end
    end
    return _orig_onKeyRepeat and _orig_onKeyRepeat(self, key)
end

function BookInfoWidget:_inDescription(pos)
    local L = self._L
    return pos.x >= L.description_x and pos.x < L.description_x + L.description_w
        and pos.y >= L.description_y and pos.y < L.description_y + L.description_h
end

function BookInfoWidget:_inCover(pos)
    local L = self._L
    return self._cover_widget
        and pos.x >= L.cover_x and pos.x < L.cover_x + L.cover_w
        and pos.y >= L.cover_y and pos.y < L.cover_y + L.cover_h
end

function BookInfoWidget:paintTo(bb, x, y)
    local L = self._L
    bb:paintRect(x, y, L.sw, L.sh, Blitbuffer.COLOR_WHITE)
    bb:paintRect(x, y + L.title_h, L.sw, L.title_divider_h,
        TitleStyle.DIVIDER_COLOR)

    local title_size = self._title_widget:getSize()
    self._title_widget:paintTo(bb,
        TitleStyle.getTitleX(x),
        y + TitleStyle.VERTICAL_PADDING
            + math.floor((TitleStyle.ROW_HEIGHT - title_size.h) / 2))
    local back_size = self._back_icon:getSize()
    local back_focused = self._zen_focus_enabled and self._zen_focus_area == "back"
    self._back_icon.invert = back_focused
    if back_focused then
        local focus_pad = Device.screen:scaleBySize(4)
        bb:paintRect(
            TitleStyle.getLeadingIconX(x) - focus_pad,
            y + TitleStyle.VERTICAL_PADDING
                + math.floor((TitleStyle.ROW_HEIGHT - back_size.h) / 2) - focus_pad,
            back_size.w + 2 * focus_pad,
            back_size.h + 2 * focus_pad,
            Blitbuffer.COLOR_BLACK
        )
    end
    self._back_icon:paintTo(bb,
        TitleStyle.getLeadingIconX(x),
        y + TitleStyle.VERTICAL_PADDING
            + math.floor((TitleStyle.ROW_HEIGHT - back_size.h) / 2))

    if self._edit_widget then
        local edit_size = self._edit_widget:getSize()
        local edit_x = x + L.edit_x + math.floor((L.edit_w - edit_size.w) / 2)
        local edit_y = y + TitleStyle.VERTICAL_PADDING
            + math.floor((TitleStyle.ROW_HEIGHT - edit_size.h) / 2)
        local edit_focused = self._zen_focus_enabled and self._zen_focus_area == "edit"
        self._edit_widget.fgcolor = edit_focused
            and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        if edit_focused then
            bb:paintRect(x + L.edit_x, y + TitleStyle.VERTICAL_PADDING,
                L.edit_w, TitleStyle.ROW_HEIGHT, Blitbuffer.COLOR_BLACK)
        end
        self._edit_widget:paintTo(bb, edit_x, edit_y)
    end

    local close_size = self._close_icon:getSize()
    local close_x = TitleStyle.getTrailingIconX(L.sw, x)
    local close_y = y + TitleStyle.VERTICAL_PADDING
        + math.floor((TitleStyle.ROW_HEIGHT - close_size.h) / 2)
    local close_focused = self._zen_focus_enabled and self._zen_focus_area == "close"
    self._close_icon.invert = close_focused
    if close_focused then
        local focus_pad = Device.screen:scaleBySize(4)
        bb:paintRect(
            close_x - focus_pad,
            close_y - focus_pad,
            close_size.w + 2 * focus_pad,
            close_size.h + 2 * focus_pad,
            Blitbuffer.COLOR_BLACK
        )
    end
    self._close_icon:paintTo(bb, close_x, close_y)

    if self._cover_widget then
        self._cover_widget:paintTo(bb, x + L.cover_x, y + L.cover_y)
        local frame_x = x + L.cover_x - L.cover_border
        local frame_y = y + L.cover_y - L.cover_border
        local frame_w = L.cover_w + 2 * L.cover_border
        local frame_h = L.cover_h + 2 * L.cover_border
        bb:paintBorder(frame_x, frame_y, frame_w, frame_h,
            L.cover_border, COVER_BORDER_COLOR, 0)
        if self.rounded_cover then
            local radius = Device.screen:scaleBySize(6)
            for j = 0, radius - 1 do
                local inner = math.sqrt(radius * radius - (radius - j) * (radius - j))
                local cut = math.ceil(radius - inner)
                if cut > 0 then
                    bb:paintRect(frame_x, frame_y + j, cut, 1, Blitbuffer.COLOR_WHITE)
                    bb:paintRect(frame_x + frame_w - cut, frame_y + j, cut, 1, Blitbuffer.COLOR_WHITE)
                    bb:paintRect(frame_x, frame_y + frame_h - 1 - j, cut, 1, Blitbuffer.COLOR_WHITE)
                    bb:paintRect(frame_x + frame_w - cut, frame_y + frame_h - 1 - j, cut, 1, Blitbuffer.COLOR_WHITE)
                end
            end
            for j = 0, radius - 1 do
                for c = 0, radius - 1 do
                    local dx = radius - c - 0.5
                    local dy = radius - j - 0.5
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist >= radius - L.cover_border and dist <= radius then
                        bb:paintRect(frame_x + c, frame_y + j, 1, 1, COVER_BORDER_COLOR)
                        bb:paintRect(frame_x + frame_w - 1 - c, frame_y + j, 1, 1, COVER_BORDER_COLOR)
                        bb:paintRect(frame_x + c, frame_y + frame_h - 1 - j, 1, 1, COVER_BORDER_COLOR)
                        bb:paintRect(frame_x + frame_w - 1 - c, frame_y + frame_h - 1 - j, 1, 1, COVER_BORDER_COLOR)
                    end
                end
            end
        end
    end

    local details_y = y + L.body_y
    for _i, entry in ipairs(self._detail_widgets) do
        if entry.visible and entry.style ~= "page" then
            details_y = details_y + entry.gap_before
            local details_x = x + L.details_x
            if entry.dimen then
                entry.dimen.x, entry.dimen.y = details_x, details_y
            end
            entry.widget:paintTo(bb, details_x, details_y)
            details_y = details_y + entry.h
        end
    end
    details_y = y + L.body_y + L.header_h - self._bottom_details_h
    for _i, entry in ipairs(self._detail_widgets) do
        if entry.visible and entry.style == "page" then
            details_y = details_y + entry.gap_before
            local details_x = x + L.details_x
            if entry.dimen then
                entry.dimen.x, entry.dimen.y = details_x, details_y
            end
            entry.widget:paintTo(bb, details_x, details_y)
            details_y = details_y + entry.h
        end
    end
    if self._progress_visible then
        details_y = details_y + self._progress_gap
        self._progress_widget:paintTo(bb, x + L.details_x, details_y)
    end

    bb:paintRect(x, y + L.description_divider_y, L.sw, 1, Blitbuffer.COLOR_LIGHT_GRAY)
    self._description_widget:paintTo(bb, x + L.description_x, y + L.description_y)
    if self._zen_focus_enabled and self._zen_focus_area == "description" then
        bb:paintBorder(
            x + L.description_x,
            y + L.description_y,
            L.description_w,
            L.description_h,
            Device.screen:scaleBySize(2),
            Blitbuffer.COLOR_BLACK,
            0
        )
    end
end

function BookInfoWidget:_onTap(ges)
    local pos = ges.pos
    local in_header = pos.y >= 0 and pos.y < self._L.title_h
    if in_header and pos.x >= 0 and pos.x < self._L.title_x then
        return self:onClose()
    end
    if self._edit_widget and pos.x >= self._L.edit_x
            and pos.x < self._L.edit_x + self._L.edit_w
            and pos.y >= 0 and pos.y < self._L.title_h then
        return self:onEdit()
    end
    if pos.x >= self._L.close_all_x
            and pos.x < self._L.close_all_x + self._L.close_all_w
            and in_header then
        return self:onCloseAll()
    end
    if in_header and pos.x >= self._L.title_x
            and pos.x < self._L.title_x + self._L.title_w then
        return self:onClose()
    end
    local handled = TopMenu.handleTap(nil, ges)
    if handled then return handled end
    if self:_inCover(pos) then
        if self.cover_tap_callback then self.cover_tap_callback() end
        return true
    end
    if self:_inDescription(pos) then
        self._description_widget:onTapScrollText(nil, ges)
    end
    return true
end

function BookInfoWidget:_onHold(ges)
    local pos = ges and ges.pos
    if not pos then return false end
    for _i, entry in ipairs(self._detail_widgets) do
        local dimen = entry.visible and entry.truncated and entry.dimen
        if dimen and pos.x >= dimen.x and pos.x < dimen.x + dimen.w
                and pos.y >= dimen.y and pos.y < dimen.y + dimen.h then
            TruncatedTextMessage.showMetadata(entry.full_text, dimen)
            return true
        end
    end
    return false
end

function BookInfoWidget:_onSwipe(ges)
    if ges.direction == "south" and ges.pos.y < Device.screen:getHeight() * 0.14 then
        return TopMenu.handleSwipe(ges)
    end
    if self:_inDescription(ges.pos) then
        self._description_widget:onScrollText(nil, ges)
    end
    return true
end

function BookInfoWidget:_onPan(ges)
    if self:_inDescription(ges.pos) then
        self._description_widget:onPanText(nil, ges)
    end
    return true
end

function BookInfoWidget:_onPanRelease(ges)
    if self:_inDescription(ges.pos) then
        self._description_widget:onPanReleaseText(nil, ges)
    end
    return true
end

function BookInfoWidget:onShow()
    UIManager:setDirty(self, function() return "partial", self.dimen end)
end

function BookInfoWidget:onClose()
    if self._description_widget then self._description_widget:free() end
    if self._cover_widget then self._cover_widget:free() end
    if self._back_icon then self._back_icon:free() end
    if self._close_icon then self._close_icon:free() end
    if self._edit_widget then self._edit_widget:free() end
    if self._title_widget then self._title_widget:free() end
    for _i, entry in ipairs(self._detail_widgets or {}) do entry.widget:free() end
    if self._progress_widget then self._progress_widget:free() end
    UIManager:close(self)
    return true
end

function BookInfoWidget:onEdit()
    if self.edit_callback then self.edit_callback(self) end
    return true
end

function BookInfoWidget:onCloseAll()
    self:onClose()
    if self.close_all_callback then self.close_all_callback() end
    return true
end

return BookInfoWidget

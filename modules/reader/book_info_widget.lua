local InputContainer = require("ui/widget/container/inputcontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Cover = require("common/cover_utils")
local utils = require("common/utils")
local TopMenu = require("modules/global/patches/menu_top_swipe")
local _ = require("gettext")

local COVER_BORDER_COLOR = Blitbuffer.COLOR_BLACK

local BookInfoWidget = InputContainer:extend{
    title = nil,
    details = nil,
    description = nil,
    cover = nil,
    cover_width = nil,
    cover_height = nil,
    cover_tap_callback = nil,
    rounded_cover = false,
    text_face = nil,
    text_size = nil,
    text_faces = nil,
}

local function resolve_stock_icon(name)
    local DataStorage = require("datastorage")
    return utils.resolveLocalIcon(DataStorage:getDataDir() .. "/resources/icons/mdlight/", name)
end

function BookInfoWidget:init()
    local sw = Device.screen:getWidth()
    local sh = Device.screen:getHeight()
    local pad = Device.screen:scaleBySize(16)
    local title_h = Device.screen:scaleBySize(52)
    local gap = Device.screen:scaleBySize(14)
    local metadata_gap = Device.screen:scaleBySize(32)
    local body_y = title_h + pad
    local cover_w = self.cover and (self.cover_width or 0) or 0
    local cover_h = self.cover and (self.cover_height or 0) or 0
    local max_cover_h = math.max(Device.screen:scaleBySize(100), math.floor(sh * 0.30))
    if cover_h > max_cover_h and cover_h > 0 then
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
        body_y = body_y,
        cover_x = pad + border,
        cover_y = body_y,
        cover_w = cover_w,
        cover_h = cover_h,
        cover_border = border,
        details_x = pad + cover_w + (cover_w > 0 and 2 * border + metadata_gap or 0),
    }

    local details_w = math.max(Device.screen:scaleBySize(60), sw - self._L.details_x - pad)
    self._text_face = self.text_face or Font:getFace("cfont", self.text_size or 16)
    self._text_faces = self.text_faces or {}
    self._title_widget = TextWidget:new{
        text = self.title or _("Book details"),
        face = self._text_face,
        bold = true,
        padding = 0,
    }
    self._description_label = TextWidget:new{
        text = _("Description"),
        face = self._text_face,
        bold = true,
        padding = 0,
    }
    self._detail_widgets = {}
    local details_h = 0
    for _i, detail in ipairs(self.details or {}) do
        local face = self._text_faces[detail.style] or self._text_face
        local widget = TextBoxWidget:new{
            text = detail.text,
            face = face,
            bold = detail.bold == true,
            width = details_w,
            alignment = "left",
        }
        local size = widget:getSize()
        local gap_before = Device.screen:scaleBySize(detail.gap_before or 0)
        if _i > 1 then gap_before = gap_before + Device.screen:scaleBySize(2) end
        table.insert(self._detail_widgets, {
            widget = widget,
            h = size.h,
            gap_before = gap_before,
        })
        details_h = details_h + gap_before + size.h
    end

    self._L.header_h = math.max(cover_h, details_h)
    self._L.description_divider_y = body_y + self._L.header_h + gap
    self._L.description_label_y = self._L.description_divider_y + 1 + gap
    self._L.description_y = self._L.description_label_y
        + self._description_label:getSize().h + gap
    self._L.description_h = math.max(
        Device.screen:scaleBySize(80),
        sh - self._L.description_y - pad
    )
    self._L.description_x = pad
    self._L.description_w = sw - pad * 2

    self._back_icon = IconWidget:new{
        file = resolve_stock_icon("chevron.left"),
        width = Device.screen:scaleBySize(26),
        height = Device.screen:scaleBySize(26),
    }
    if self.cover then
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
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
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
    bb:paintRect(x, y + L.title_h, L.sw, 1, Blitbuffer.COLOR_LIGHT_GRAY)

    local title_size = self._title_widget:getSize()
    self._title_widget:paintTo(bb,
        x + math.floor((L.sw - title_size.w) / 2),
        y + math.floor((L.title_h - title_size.h) / 2))
    local back_size = self._back_icon:getSize()
    self._back_icon:paintTo(bb,
        x + math.floor((L.title_h - back_size.w) / 2),
        y + math.floor((L.title_h - back_size.h) / 2))

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
        details_y = details_y + entry.gap_before
        entry.widget:paintTo(bb, x + L.details_x, details_y)
        details_y = details_y + entry.h
    end

    bb:paintRect(x, y + L.description_divider_y, L.sw, 1, Blitbuffer.COLOR_LIGHT_GRAY)
    self._description_label:paintTo(bb, x + L.description_x, y + L.description_label_y)
    self._description_widget:paintTo(bb, x + L.description_x, y + L.description_y)
end

function BookInfoWidget:_onTap(ges)
    local pos = ges.pos
    if pos.x < self._L.title_h and pos.y < self._L.title_h then
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
    if self._title_widget then self._title_widget:free() end
    if self._description_label then self._description_label:free() end
    for _i, entry in ipairs(self._detail_widgets or {}) do entry.widget:free() end
    UIManager:close(self)
    return true
end

return BookInfoWidget

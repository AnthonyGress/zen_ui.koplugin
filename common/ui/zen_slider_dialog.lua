-- common/zen_slider_dialog.lua
-- Modal dialog that wraps ZenSlider with +/- buttons, a live value label,
-- and Close/Apply buttons.  Pattern mirrors KOReader's SpinWidget.
--
-- Usage:
--   UIManager:show(ZenSliderDialog:new{
--       title     = "Day brightness",
--       value     = 80,
--       value_min = 0,
--       value_max = 100,
--       callback  = function(v) ... end,
--   })

local Blitbuffer      = require("ffi/blitbuffer")
local Button          = require("ui/widget/button")
local ButtonTable     = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local GestureRange    = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local InputContainer  = require("ui/widget/container/inputcontainer")
local Size            = require("ui/size")
local TextWidget      = require("ui/widget/textwidget")
local TitleBar        = require("ui/widget/titlebar")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local ZenSlider       = require("common/ui/zen_slider")
local _               = require("gettext")
local Screen          = Device.screen

local ZenSliderDialog = InputContainer:extend{
    title     = "",
    value     = 0,
    value_min = 0,
    value_max = 100,
    callback  = nil,
}

function ZenSliderDialog:init()
    local sw    = Screen:getWidth()
    local sh    = Screen:getHeight()
    local width = math.floor(math.min(sw, sh) * 0.8)
    local pad   = Size.padding.large

    local cur = math.max(self.value_min, math.min(self.value_max, self.value))

    local label_face  = Font:getFace("cfont", 22)
    local value_label = TextWidget:new{ text = tostring(cur), face = label_face }

    -- Fixed-width box sized to the widest number so the label never shifts.
    local max_sample  = TextWidget:new{ text = tostring(self.value_max), face = label_face }
    local label_h     = max_sample:getSize().h
    local label_max_w = max_sample:getSize().w
    max_sample:free()

    local btn_font_size = 22
    local btn_w  = Screen:scaleBySize(44)
    local gap_w  = Screen:scaleBySize(8)
    local slider_w = width - 2 * pad - 2 * btn_w - 4 * gap_w

    local slider = ZenSlider:new{
        width     = slider_w,
        value     = cur,
        value_min = self.value_min,
        value_max = self.value_max,
    }

    local function update(v)
        cur = math.max(self.value_min, math.min(self.value_max, v))
        slider:setValue(cur)
        value_label:setText(tostring(cur))
        UIManager:setDirty(self, "ui")
    end

    -- During drag: paint slider + label directly to Screen.bb, then push a
    -- single A2 refresh covering both (same technique as brightness_slider).
    -- On release, _dragging is cleared before the final on_change, so we
    -- fall through to a normal "ui" redraw.
    local gap_above_slider = Screen:scaleBySize(8)  -- matches the VerticalSpan between label_row and slider
    slider.on_change = function(v)
        cur = math.max(self.value_min, math.min(self.value_max, v))
        if slider._dragging then
            slider:paintTo(Screen.bb, slider.dimen.x, slider.dimen.y)
            -- Clear and repaint the centered value label above the slider.
            local label_y  = slider.dimen.y - gap_above_slider - label_h
            local center_x = slider.dimen.x + math.floor(slider.dimen.w / 2)
            local clear_x  = center_x - math.floor(label_max_w / 2)
            Screen.bb:paintRect(clear_x, label_y, label_max_w, label_h, Blitbuffer.COLOR_WHITE)
            value_label:setText(tostring(cur))
            local cur_w   = value_label:getSize().w
            local paint_x = center_x - math.floor(cur_w / 2)
            value_label:paintTo(Screen.bb, paint_x, label_y)
            -- Single A2 covering label + slider to avoid racing refreshes.
            UIManager:setDirty(nil, "fast", Geom:new{
                x = slider.dimen.x,
                y = label_y,
                w = slider.dimen.w,
                h = slider.dimen.y + slider.dimen.h - label_y,
            })
        else
            value_label:setText(tostring(cur))
            UIManager:setDirty(self, "ui")
        end
    end

    local gap = HorizontalSpan:new{ width = gap_w }

    local minus_btn = Button:new{
        text           = "−",
        text_font_face = "infofont",
        text_font_size = btn_font_size,
        text_font_bold = false,
        width          = btn_w,
        bordersize     = 0,
        show_parent    = self,
        callback       = function() update(cur - 1) end,
    }
    local plus_btn = Button:new{
        text           = "＋",
        text_font_face = "infofont",
        text_font_size = btn_font_size,
        text_font_bold = false,
        width          = btn_w,
        bordersize     = 0,
        show_parent    = self,
        callback       = function() update(cur + 1) end,
    }

    local slider_row = HorizontalGroup:new{
        align = "center",
        minus_btn, gap, slider, gap, plus_btn,
    }

    local title_bar = TitleBar:new{
        title            = self.title,
        width            = width,
        with_bottom_line = true,
        close_callback   = function() self:onClose() end,
        show_parent      = self,
    }

    local label_row = CenterContainer:new{
        dimen = Geom:new{ w = width, h = label_h },
        value_label,
    }

    local ok_cancel = ButtonTable:new{
        width       = width - 2 * pad,
        zero_sep    = true,
        show_parent = self,
        buttons     = {{
            { text = _("Close"), callback = function() self:onClose() end },
            { text = _("Apply"), callback = function()
                if self.callback then self.callback(cur) end
                self:onClose()
            end },
        }},
    }

    local vgroup = VerticalGroup:new{
        align = "center",
        title_bar,
        VerticalSpan:new{ width = pad },
        label_row,
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        CenterContainer:new{
            dimen = Geom:new{ w = width, h = slider:getSize().h },
            slider_row,
        },
        VerticalSpan:new{ width = pad },
        ok_cancel,
    }

    self._frame = FrameContainer:new{
        radius     = Size.radius.window,
        padding    = 0,
        bordersize = Size.border.window,
        background = Blitbuffer.COLOR_WHITE,
        vgroup,
    }

    self[1] = CenterContainer:new{
        dimen = Geom:new{ w = sw, h = sh },
        self._frame,
    }

    self._slider = slider

    local full = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self.ges_events.TapClose = {
        GestureRange:new{ ges = "tap", range = full },
    }
    self.ges_events.SliderPan = {
        GestureRange:new{ ges = "pan", range = full },
    }
    self.ges_events.SliderPanRelease = {
        GestureRange:new{ ges = "pan_release", range = full },
    }
    self.ges_events.SliderSwipe = {
        GestureRange:new{ ges = "swipe", range = full },
    }
end

function ZenSliderDialog:onTapClose(_, ges)
    if ges.pos:notIntersectWith(self._frame.dimen) then
        self:onClose()
    end
    return true
end

function ZenSliderDialog:onSliderPan(_, ges)
    self._slider:handlePan(ges)
    return true
end

function ZenSliderDialog:onSliderPanRelease(_, ges)
    self._slider:handlePanRelease(ges, self, self._frame.dimen)
    return true
end

function ZenSliderDialog:onSliderSwipe(_, ges)
    self._slider:handleSwipe(ges, self, self._frame.dimen)
    return true
end

function ZenSliderDialog:onShow()
    UIManager:setDirty(self, function()
        return "ui", self._frame.dimen
    end)
    return true
end

function ZenSliderDialog:onCloseWidget()
    UIManager:setDirty(nil, function()
        return "ui", self._frame.dimen
    end)
end

function ZenSliderDialog:onClose()
    UIManager:close(self)
    return true
end

return ZenSliderDialog

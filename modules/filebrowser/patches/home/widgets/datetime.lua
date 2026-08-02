local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local FrameContainer = require("ui/widget/container/framecontainer")
local TextWidget = require("ui/widget/textwidget")
local WidgetResources = require("common/widget_resources")

local function time_text()
    local gs = rawget(_G, "G_reader_settings")
    local twelve_hour = gs and gs:isTrue("twelve_hour_clock")
    local text = os.date(twelve_hour and "%I:%M" or "%H:%M")
    if twelve_hour then
        text = text:gsub("^0(%d:)", "%1")
    end
    return text
end

local function date_text()
    local datetime = require("datetime")
    local t = os.date("*t")
    local weekday = datetime.shortDayOfWeekToLongTranslation[datetime.weekDays[t.wday]] or os.date("%A")
    local month = datetime.longMonthTranslation[os.date("%B")] or os.date("%B")
    return weekday .. ", " .. month .. " " .. tostring(t.day)
end

return {
    id = "datetime",
    label = "Date/time widget",
    size = { preferred_pct = 0.15, min_pct = 0.10, max_pct = 0.26, grow_priority = 2 },
    build = function(ctx)
        local width = ctx.width
        local height = ctx.height
        local Screen = Device.screen
        local date_gap = math.max(1, Screen:scaleBySize(2))
        local max_content_h = math.max(1, height - Screen:scaleBySize(2))
        local time_widget
        local date_widget
        local time_size
        local date_size
        local time_h
        local date_h
        local content_h
        local time_date_overlap = 0
        local top = 0
        local resources = {}

        local min_time_px = 4
        local max_time_px = math.max(22, math.min(480, height * 2))

        local function rebuild_clock_widgets()
            WidgetResources.free(time_widget)
            WidgetResources.free(date_widget)
            time_widget = nil
            date_widget = nil
            resources[1] = nil
            resources[2] = nil

            local time_str = time_text()
            local date_str = date_text()
            local function make_clock_widgets(time_px)
                local date_px = math.max(8, math.floor(time_px * 0.36))
                local tw = TextWidget:new{
                    text = time_str,
                    face = Font:getFace("smallinfofont", Screen:scaleBySize(time_px)),
                    bold = true,
                }
                local dw = TextWidget:new{
                    text = date_str,
                    face = Font:getFace("smallinfofont", Screen:scaleBySize(date_px)),
                    fgcolor = Blitbuffer.COLOR_GRAY_3,
                }
                local ts = tw:getSize()
                local ds = dw:getSize()
                local th = ts.h or 18
                local dh = ds.h or 10
                local overlap = math.floor(th * 0.16)
                local ch = th - overlap + date_gap + dh
                return tw, dw, ts, ds, th, dh, overlap, ch
            end

            local low, high = min_time_px, max_time_px
            local best
            while low <= high do
                local time_px = math.floor((low + high) / 2)
                local tw, dw, ts, ds, th, dh, overlap, ch = make_clock_widgets(time_px)
                if ch <= max_content_h then
                    WidgetResources.free(best and best.tw)
                    WidgetResources.free(best and best.dw)
                    best = {
                        tw = tw, dw = dw, ts = ts, ds = ds,
                        th = th, dh = dh, overlap = overlap, ch = ch,
                    }
                    low = time_px + 1
                else
                    WidgetResources.free(tw)
                    WidgetResources.free(dw)
                    high = time_px - 1
                end
            end

            if not best then
                local tw, dw, ts, ds, th, dh, overlap, ch = make_clock_widgets(min_time_px)
                best = {
                    tw = tw, dw = dw, ts = ts, ds = ds,
                    th = th, dh = dh, overlap = overlap, ch = ch,
                }
            end

            time_widget = best.tw
            date_widget = best.dw
            time_size = best.ts
            date_size = best.ds
            time_h = best.th
            date_h = best.dh
            content_h = best.ch
            time_date_overlap = best.overlap

            resources[1] = time_widget
            resources[2] = date_widget

            local spare_h = math.max(0, height - content_h)
            top = math.floor(spare_h * 0.70)
        end

        rebuild_clock_widgets()

        local content = WidgetResources.managedPaintWidget{
            dimen = Geom:new{ w = width, h = height },
            resources = resources,
            paintTo = function(_self, bb, x, y)
                local time_x = x + math.floor((width - (time_size.w or 0)) / 2)
                local date_x = x + math.floor((width - (date_size.w or 0)) / 2)
                local time_y = y + top
                local date_y = math.min(y + height - date_h, time_y + time_h - time_date_overlap + date_gap)
                time_widget:paintTo(bb, time_x, time_y)
                date_widget:paintTo(bb, date_x, date_y)
            end,
            free = function()
                time_widget = nil
                date_widget = nil
            end,
        }

        if type(ctx.registerClockRefresh) == "function" then
            ctx.registerClockRefresh(function()
                rebuild_clock_widgets()
                return true
            end)
        end

        return FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
            content,
        }
    end,
}

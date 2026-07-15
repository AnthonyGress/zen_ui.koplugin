local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local WidgetResources = require("common/widget_resources")

local function get_quote(ctx)
    local q = ctx.data:getCurrentQuote()
    if q then return q end
    return { text = "No quote available.", author = "" }
end

local function fit_quote_face(text, width, max_h)
    local Screen = Device.screen
    local min_px = 4
    local max_px = 12
    local chosen = Font:getFace("smallinfofont", Screen:scaleBySize(min_px))

    for px = max_px, min_px, -1 do
        local face = Font:getFace("smallinfofont", Screen:scaleBySize(px))
        local probe = TextBoxWidget:new{
            text = text,
            width = width,
            face = face,
            alignment = "center",
            height_adjust = true,
            height_overflow_show_ellipsis = false,
        }
        local need_h = probe:getSize().h or 0
        WidgetResources.free(probe)
        if need_h <= max_h then
            chosen = face
            break
        end
    end

    return chosen
end

return {
    id = "quotes",
    label = "Quotes widget",
    size = { preferred_pct = 0.16, min_pct = 0.10, max_pct = 0.28, grow_priority = 3 },
    build = function(ctx)
        local width = ctx.width
        local height = ctx.height
        local quote = get_quote(ctx)
        local show_author = ctx.config.quotes and ctx.config.quotes.show_author ~= false
        local Screen = Device.screen

        local padding = Screen:scaleBySize(8)
        local content_w = math.max(30, width - padding * 2)
        local inner_h = math.max(20, height - 12)
        local quote_text = '"' .. (quote.text or "") .. '"'
        local author_face = Font:getFace("smallinfofont", Screen:scaleBySize(10))
        local author_h = 0
        if show_author and quote.author and quote.author ~= "" then
            local author_probe = TextWidget:new{ text = "A", face = author_face }
            local author_line_h = author_probe:getSize().h or 0
            WidgetResources.free(author_probe)
            author_h = author_line_h + 5
        end
        local author_gap = author_h > 0 and 3 or 0
        local quote_face = fit_quote_face(quote_text, content_w, math.max(10, inner_h - author_h - author_gap))
        local quote_widget = TextBoxWidget:new{
            text = quote_text,
            width = content_w,
            face = quote_face,
            alignment = "center",
            height_adjust = true,
            height_overflow_show_ellipsis = false,
        }
        local quote_size = quote_widget:getSize()
        local author_widget

        if show_author and quote.author and quote.author ~= "" then
            author_widget = TextWidget:new{
                text = "\226\128\148 " .. quote.author,
                face = author_face,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
        end
        local author_size = author_widget and author_widget:getSize() or nil
        local quote_h = quote_size.h or 0
        local content_h = quote_h
        if author_widget then
            content_h = content_h + author_gap + (author_size.h or 0)
        end
        local available_h = math.max(0, height - content_h)
        local content_top = math.min(available_h, Screen:scaleBySize(6))
        local content = WidgetResources.managedPaintWidget{
            dimen = Geom:new{ w = width, h = height },
            resources = { quote_widget, author_widget },
            paintTo = function(_self, bb, x, y)
                local quote_x = x + math.floor((width - content_w) / 2)
                local quote_y = y + content_top
                quote_widget:paintTo(bb, quote_x, quote_y)
                if author_widget then
                    local author_x = x + math.floor((width - (author_size.w or 0)) / 2)
                    local author_y = quote_y + quote_h + author_gap
                    author_widget:paintTo(bb, author_x, author_y)
                end
            end,
            free = function()
                quote_widget = nil
                author_widget = nil
            end,
        }

        local body = FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
            content,
        }

        local tap = InputContainer:new{
            dimen = Geom:new{ w = width, h = height },
            ges_events = {
                TapQuote = {
                    GestureRange:new{ ges = "tap", range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(), h = Screen:getHeight(),
                    } },
                },
            },
        }
        tap.onTapQuote = function(tap_self, _arg, ges)
            if not tap_self.dimen or not ges or not ges.pos then
                return false
            end
            if ctx.openTopMenu and ctx.openTopMenu(ges) then
                return true
            end
            if not tap_self.dimen:contains(ges.pos) then
                return false
            end
            local prev_zone = tap_self.dimen.x + math.floor(tap_self.dimen.w * 0.35)
            if ges.pos.x < prev_zone then
                if ctx.data.prevQuote then ctx.data:prevQuote() end
            else
                if ctx.data.nextQuote then ctx.data:nextQuote() end
            end
            return true
        end
        tap[1] = body
        return tap
    end,
}

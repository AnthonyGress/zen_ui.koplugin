local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextBoxWidget = require("ui/widget/textboxwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local WidgetResources = require("common/widget_resources")

local function get_quote(ctx)
    local q = ctx.data:getCurrentQuote()
    if q then return q end
    return { text = "No quote available.", author = "" }
end

return {
    id = "quotes",
    label = "Quotes widget",
    size = { units = 1.5 },
    build = function(ctx)
        local width = ctx.width
        local height = ctx.height
        local quote = get_quote(ctx)
        local quotes = ctx.config.quotes or {}
        local show_author = quotes.show_author ~= false
        local show_title = quotes.show_title ~= false
        local automatic_font_size = quotes.automatic_font_size == true
        local Screen = Device.screen
        local quote_font_size = quotes.font_size
        if quote_font_size == nil then
            quote_font_size = quotes.use_home_font_size and ctx.config.font_size or 12
        end
        quote_font_size = math.max(4, math.min(32, tonumber(quote_font_size) or 12))

        local padding = Screen:scaleBySize(8)
        local vertical_padding = Screen:scaleBySize(4)
        local content_w = math.max(30, width - padding * 2)
        local inner_h = math.max(20, height - vertical_padding * 2)
        local quote_text = '"' .. (quote.text or "") .. '"'
        local attribution_parts = {}
        if show_author and quote.author and quote.author ~= "" then
            attribution_parts[#attribution_parts + 1] = quote.author
        end
        if show_title and quote.title and quote.title ~= "" then
            attribution_parts[#attribution_parts + 1] = quote.title
        end
        local attribution = table.concat(attribution_parts, ",  ")
        if attribution == "" and show_author
                and (not quote.author or quote.author == "")
                and (not quote.title or quote.title == "") then
            attribution = quote.attribution or ""
        end

        local quote_line_height = 0.55
        if automatic_font_size then
            local max_font_size = math.max(
                4, math.min(32, tonumber(quotes.max_font_size) or 14)
            )
            quote_font_size = 4
            quote_line_height = 0.3
            for candidate = max_font_size, 4, -1 do
                local candidate_face = Font:getFace(
                    "smallinfofont", Screen:scaleBySize(candidate)
                )
                local author_h = 0
                if attribution ~= "" then
                    local candidate_author_face = Font:getFace(
                        "smallinfofont",
                        Screen:scaleBySize(math.max(6, math.floor(candidate * 9 / 10)))
                    )
                    local author_probe = TextBoxWidget:new{
                        text = "\226\128\148 " .. attribution,
                        width = content_w,
                        face = candidate_author_face,
                        alignment = "center",
                    }
                    author_h = author_probe:getSize().h or 0
                    WidgetResources.free(author_probe)
                end
                local quote_probe = TextBoxWidget:new{
                    text = quote_text,
                    width = content_w,
                    face = candidate_face,
                    alignment = "center",
                    line_height = 0.3,
                }
                local measured_h = quote_probe:getSize().h or 0
                WidgetResources.free(quote_probe)
                if measured_h + author_h <= inner_h then
                    quote_font_size = candidate
                    -- Keep the roomiest spacing available at the chosen font size.
                    for line_height_step = 11, 7, -1 do
                        local candidate_line_height = line_height_step / 20
                        local spacing_probe = TextBoxWidget:new{
                            text = quote_text,
                            width = content_w,
                            face = candidate_face,
                            alignment = "center",
                            line_height = candidate_line_height,
                        }
                        local spacing_h = spacing_probe:getSize().h or 0
                        WidgetResources.free(spacing_probe)
                        if spacing_h + author_h <= inner_h then
                            quote_line_height = candidate_line_height
                            break
                        end
                    end
                    break
                end
            end
        end

        local quote_face = Font:getFace("smallinfofont", Screen:scaleBySize(quote_font_size))
        local quote_probe = TextBoxWidget:new{
            text = "A\nA",
            width = content_w,
            face = quote_face,
            line_height = quote_line_height,
        }
        local two_quote_lines_h = quote_probe:getSize().h or 0
        WidgetResources.free(quote_probe)
        local quote_three_line_probe = TextBoxWidget:new{
            text = "A\nA\nA",
            width = content_w,
            face = quote_face,
            line_height = quote_line_height,
        }
        local three_quote_lines_h = quote_three_line_probe:getSize().h or 0
        WidgetResources.free(quote_three_line_probe)
        local quote_line_probe = TextBoxWidget:new{
            text = "A",
            width = content_w,
            face = quote_face,
            line_height = quote_line_height,
        }
        local quote_line_h = quote_line_probe:getSize().h or 0
        WidgetResources.free(quote_line_probe)
        local quote_height_probe = TextBoxWidget:new{
            text = quote_text,
            width = content_w,
            face = quote_face,
            line_height = quote_line_height,
        }
        local natural_quote_h = quote_height_probe:getSize().h or 0
        WidgetResources.free(quote_height_probe)
        local author_face = Font:getFace(
            "smallinfofont",
            Screen:scaleBySize(math.max(6, math.floor(quote_font_size * 9 / 10)))
        )
        local author_h = 0
        if attribution ~= "" then
            local author_probe = TextBoxWidget:new{
                text = "\226\128\148 " .. attribution,
                width = content_w,
                face = author_face,
                alignment = "center",
            }
            local author_line_h = author_probe:getSize().h or 0
            WidgetResources.free(author_probe)
            author_h = author_line_h
        end
        local author_gap = 0
        local max_quote_h = math.max(10, inner_h - author_h - author_gap)
        local quote_h
        if automatic_font_size then
            quote_h = math.min(natural_quote_h, max_quote_h)
        else
            quote_h = math.min(natural_quote_h, three_quote_lines_h, max_quote_h)
        end
        local line_height_target = 2
        if natural_quote_h > two_quote_lines_h and quote_h < three_quote_lines_h
                and quote_h >= quote_face.size * 3 then
            line_height_target = 3
        end
        if not automatic_font_size and natural_quote_h > quote_line_h
                and quote_h < (line_height_target == 3
                and three_quote_lines_h or two_quote_lines_h) then
            quote_line_height = math.max(0, math.min(
                quote_line_height,
                math.floor(quote_h / line_height_target) / math.max(1, quote_face.size or 1) - 1
            ))
        end
        local quote_widget = TextBoxWidget:new{
            text = quote_text,
            width = content_w,
            height = quote_h,
            face = quote_face,
            alignment = "center",
            line_height = quote_line_height,
            height_overflow_show_ellipsis = true,
        }
        local quote_size = quote_widget:getSize()
        local author_widget

        if attribution ~= "" then
            author_widget = TextBoxWidget:new{
                text = "\226\128\148 " .. attribution,
                width = content_w,
                face = author_face,
                alignment = "center",
                fgcolor = Blitbuffer.COLOR_BLACK,
                height_overflow_show_ellipsis = true,
            }
        end
        local author_size = author_widget and author_widget:getSize() or nil
        local quote_height = quote_size.h or 0
        local content_h = quote_height
        if author_widget then
            content_h = content_h + author_gap + (author_size.h or 0)
        end
        local available_h = math.max(0, height - content_h)
        local is_multiline = natural_quote_h > quote_line_h
        local content_top = is_multiline and math.min(vertical_padding, available_h)
            or math.floor(available_h / 2)
        local visual_shift = 0
        if type(ctx.setContentBounds) == "function" then
            ctx.setContentBounds{
                top = vertical_padding,
                bottom = height - vertical_padding,
                min_shift = 0,
                max_shift = 0,
                set_shift = function(shift) visual_shift = shift end,
            }
        end
        local content = WidgetResources.managedPaintWidget{
            dimen = Geom:new{ w = width, h = height },
            resources = { quote_widget, author_widget },
            paintTo = function(_self, bb, x, y)
                local quote_x = x + math.floor((width - content_w) / 2)
                local quote_y = y + content_top + visual_shift
                quote_widget:paintTo(bb, quote_x, quote_y)
                if author_widget then
                    local author_x = x + math.floor((width - content_w) / 2)
                    local author_y = quote_y + quote_height + author_gap
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
                HoldQuote = {
                    GestureRange:new{ ges = "hold", range = Geom:new{
                        x = 0, y = 0,
                        w = Screen:getWidth(), h = Screen:getHeight(),
                    } },
                },
                SwipeQuote = {
                    GestureRange:new{ ges = "swipe", range = Geom:new{
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
            if quote.is_annotation and ctx.data.openQuote then
                return ctx.data:openQuote(quote)
            end
            return true
        end
        tap.onSwipeQuote = function(tap_self, _arg, ges)
            if not (tap_self.dimen and ges and ges.pos and tap_self.dimen:contains(ges.pos)) then
                return false
            end
            if ges.direction == "west" then
                if ctx.data.nextQuote then ctx.data:nextQuote() end
                return true
            elseif ges.direction == "east" then
                if ctx.data.prevQuote then ctx.data:prevQuote() end
                return true
            end
            return false
        end
        tap.onHoldQuote = function(tap_self, _arg, ges)
            if not (tap_self.dimen and ges and ges.pos and tap_self.dimen:contains(ges.pos)) then
                return false
            end
            if ctx.editMode and ctx.openWidgetSettings then
                return ctx.openWidgetSettings()
            end
            return false
        end
        tap[1] = body
        return tap
    end,
}

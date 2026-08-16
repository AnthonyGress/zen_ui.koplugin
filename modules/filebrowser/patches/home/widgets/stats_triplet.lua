local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LineWidget = require("ui/widget/linewidget")
local TextWidget = require("ui/widget/textwidget")
local IconWidget = require("ui/widget/iconwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local Device = require("device")
local Font = require("ui/font")
local utils = require("common/utils")
local WidgetResources = require("common/widget_resources")
local _ = require("gettext")

local _icons_dir
do
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then
        local root = src:sub(2):match("^(.*)/modules/")
        if root then _icons_dir = root .. "/icons/" end
    end
end

local flame_icon_path = _icons_dir and utils.resolveLocalIcon(_icons_dir, "flame") or nil

local function time_unit(unit)
    if type(_) == "table" and type(_.pgettext) == "function" then
        return _.pgettext("Time", unit)
    end
    return _(unit)
end

local function fmt_time(secs)
    secs = math.floor(secs or 0)
    if secs <= 0 then return "0" .. time_unit("m") end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    if h > 0 then
        return h .. time_unit("h") .. " " .. m .. time_unit("m")
    end
    return m .. time_unit("m")
end

local FIELD_MAP = {
    today_pages = { id = "today_pages", label = _("Pages today"), get = function(s) return tostring(s.today_pages or 0) end },
    today_duration = { id = "today_duration", label = _("Read today"), get = function(s) return fmt_time(s.today_duration or 0) end },
    streak = { id = "streak", label = _("Day streak"), get = function(s) return tostring(s.streak or 0) end },
    week_pages = { id = "week_pages", label = _("Pages this week"), get = function(s) return tostring(s.week_pages or 0) end },
    week_duration = { id = "week_duration", label = _("Time this week"), get = function(s) return fmt_time(s.week_duration or 0) end },
}

local function metric_content(width, height, value_widget, label_widget)
    local value_size = value_widget:getSize()
    local label_size = label_widget:getSize()
    local value_h = value_size.h or 1
    local label_h = label_size.h or 1
    local overlap = math.floor(value_h * 0.18)
    local gap = 1
    local content_h = value_h - overlap + gap + label_h
    local top = math.floor(math.max(0, height - content_h) / 2)

    local content = WidgetResources.managedPaintWidget{
        dimen = Geom:new{ w = width, h = height },
        resources = { value_widget, label_widget },
        paintTo = function(_self, bb, x, y)
            local value_x = x + math.floor((width - (value_size.w or 0)) / 2)
            local value_y = y + top
            local label_x = x + math.floor((width - (label_size.w or 0)) / 2)
            local label_y = value_y + value_h - overlap + gap
            value_widget:paintTo(bb, value_x, value_y)
            label_widget:paintTo(bb, label_x, label_y)
        end,
        free = function()
            value_widget = nil
            label_widget = nil
        end,
    }
    return content, top, content_h
end

local function configured_font_size(ctx)
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    local config = type(ctx.config) == "table" and ctx.config or {}
    return math.max(8, math.min(32,
        tonumber(module_cfg.font_size) or tonumber(config.font_size) or 18))
end

return {
    id = "stats_triplet",
    label = _("Reading stats"),
    size = "xs",
    build = function(ctx)
        local outer_width = ctx.width
        local height = ctx.height
        local stats = ctx.data.stats or {}
        local module_cfg = ctx.module_cfg or {}
        local stat_style = module_cfg.stat_style == "outline" and "outline"
            or module_cfg.stat_style == "none" and "none"
            or "divider"
        local horizontal_padding = stat_style == "outline"
            and Device.screen:scaleBySize(8) or 0
        local width = math.max(1, outer_width - horizontal_padding * 2)

        local config = ctx.config.middle_stats_triplet or { "today_pages", "today_duration", "streak" }
        local fields = {}
        for _i, fid in ipairs(config) do
            local entry = FIELD_MAP[fid] or FIELD_MAP.today_pages
            table.insert(fields, entry)
            if #fields >= 3 then break end
        end
        while #fields < 3 do
            table.insert(fields, FIELD_MAP.today_pages)
        end

        local gap_w = stat_style == "outline" and math.max(10, math.floor(width * 0.045))
            or stat_style == "divider" and 8
            or 6
        local cell_w = math.max(20, math.floor((width - gap_w * 2) / 3))
        local card_h = math.max(20, height)
        local border_size = stat_style == "outline" and 2 or 0
        local Screen = Device.screen
        local font_size = configured_font_size(ctx)
        local value_face = Font:getFace("smallinfofont", Screen:scaleBySize(font_size))
        local label_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.max(6, math.floor(font_size * 0.6))))
        local row = HorizontalGroup:new{ align = "center" }
        local visual_top = height
        local visual_bottom = 0
        local divider_visual_top

        for _i, field in ipairs(fields) do
            local value_widget = TextWidget:new{
                text = field.get(stats),
                face = value_face,
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            if field.id == "streak" and flame_icon_path then
                local value_size = value_widget:getSize()
                local icon_size = math.max(8, math.floor((value_size.h or 12) * 0.62))
                value_widget = HorizontalGroup:new{
                    align = "center",
                    IconWidget:new{
                        file = flame_icon_path,
                        width = icon_size,
                        height = icon_size,
                        alpha = true,
                    },
                    HorizontalSpan:new{ width = 3 },
                    value_widget,
                }
            end
            local inner_w = math.max(1, cell_w - 12 - border_size * 2)
            local inner_h = math.max(1, card_h - 12 - border_size * 2)
            local content, metric_top, metric_h = metric_content(inner_w, inner_h, value_widget,
                TextWidget:new{ text = field.label, face = label_face, fgcolor = Blitbuffer.COLOR_BLACK })
            visual_top = math.min(visual_top, 6 + metric_top)
            visual_bottom = math.max(visual_bottom, 6 + metric_top + metric_h)
            local card = FrameContainer:new{
                width = cell_w,
                height = card_h,
                padding = 6,
                bordersize = border_size,
                color = Blitbuffer.COLOR_DARK_GRAY,
                radius = stat_style == "outline" and 8 or 0,
                background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
                CenterContainer:new{
                    dimen = Geom:new{ w = inner_w, h = inner_h },
                    content,
                },
            }
            table.insert(row, card)
            if _i < 3 then
                if stat_style == "outline" then
                    table.insert(row, HorizontalSpan:new{ width = gap_w })
                elseif stat_style == "divider" then
                    local divider_trim = math.min(
                        math.max(0, metric_h - 1),
                        math.max(1, Screen:scaleBySize(4))
                    )
                    local divider_h = math.min(card_h, math.max(1, metric_h - divider_trim))
                    local divider_bottom = 6 + metric_top + metric_h
                    local divider_top = divider_bottom - divider_h
                    local divider_shift = divider_top - math.floor((card_h - divider_h) / 2)
                    divider_visual_top = math.min(divider_visual_top or divider_top, divider_top)
                    visual_bottom = math.max(visual_bottom, divider_top + divider_h)
                    local divider_container = CenterContainer:new{
                        dimen = Geom:new{ w = gap_w, h = card_h },
                        LineWidget:new{
                            dimen = Geom:new{ w = 2, h = divider_h },
                            background = Blitbuffer.COLOR_DARK_GRAY,
                        },
                    }
                    local original_divider_paint = divider_container.paintTo
                    divider_container.paintTo = function(self, bb, x, y)
                        return original_divider_paint(self, bb, x, y + divider_shift)
                    end
                    table.insert(row, divider_container)
                else
                    table.insert(row, HorizontalSpan:new{ width = gap_w })
                end
            end
        end

        if stat_style == "outline" then
            visual_top = 0
            visual_bottom = height
        elseif stat_style == "divider" and divider_visual_top then
            visual_top = math.min(visual_top, divider_visual_top)
        end
        local visual_shift = 0
        local row_container = CenterContainer:new{
            dimen = Geom:new{ w = outer_width, h = height },
            row,
        }
        local original_row_paint = row_container.paintTo
        row_container.paintTo = function(self, bb, x, y)
            return original_row_paint(self, bb, x, y + visual_shift)
        end
        if type(ctx.setContentBounds) == "function" then
            ctx.setContentBounds{
                top = visual_top,
                bottom = visual_bottom,
                min_shift = -visual_top,
                max_shift = height - visual_bottom,
                set_shift = function(shift) visual_shift = shift end,
            }
        end

        return FrameContainer:new{
            width = outer_width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
            row_container,
        }
    end,
}

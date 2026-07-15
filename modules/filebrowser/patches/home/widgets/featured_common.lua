local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local GestureRange = require("ui/gesturerange")
local Device = require("device")
local Font = require("ui/font")
local util = require("util")
local zen_utils = require("common/utils")
local WidgetResources = require("common/widget_resources")
local cover_common = require("modules/filebrowser/patches/home/widgets/cover_common")
local library_font = require("modules/filebrowser/patches/library_font")
local _ = require("gettext")

local M = {}
M.SIZE = { preferred_pct = 0.36, min_pct = 0.22, max_pct = 0.50, grow_priority = 1 }

local DEFAULT_TEXT_STYLES = {
    title = { font_face = "default", font_size = 11, bold = true },
    author = { font_face = "default", font_size = 9, bold = false },
    description = { font_face = "default", font_size = 16, bold = false },
}

local function clamp(v, min_v, max_v)
    if v < min_v then return min_v end
    if v > max_v then return max_v end
    return v
end

local function text_style(module_cfg, key)
    local defaults = DEFAULT_TEXT_STYLES[key]
    local styles = type(module_cfg.text_styles) == "table" and module_cfg.text_styles or {}
    local style = type(styles[key]) == "table" and styles[key] or {}
    local size = tonumber(style.font_size) or defaults.font_size
    return {
        font_face = type(style.font_face) == "string" and style.font_face ~= "" and style.font_face or defaults.font_face,
        font_size = clamp(math.floor(size + 0.5), 6, 40),
        bold = style.bold == nil and defaults.bold or style.bold == true,
    }
end

local function get_text_face(style, size)
    local font_name = style.font_face == "default" and library_font.getFontName() or style.font_face
    return Font:getFace(font_name, size)
end

local function paint_pill(bb, x, y, w, h, color)
    if w <= 0 or h <= 0 then return end
    if h <= 1 then
        bb:paintRect(x, y, w, h, color)
        return
    end
    local r = math.floor(h / 2)
    if w <= h then
        local cx = x + math.floor(w / 2)
        for row = 0, h - 1 do
            local dy = row - r + 0.5
            local half = math.floor(math.sqrt(math.max(0, r * r - dy * dy)) + 0.5)
            local x0 = math.max(x, cx - half)
            local rw = math.min(w, half * 2)
            if rw > 0 then bb:paintRect(x0, y + row, rw, 1, color) end
        end
        return
    end
    for row = 0, h - 1 do
        local dy = row - r + 0.5
        local inset = math.floor(r - math.sqrt(math.max(0, r * r - dy * dy)) + 0.5)
        local rw = w - inset * 2
        if rw > 0 then bb:paintRect(x + inset, y + row, rw, 1, color) end
    end
end

local function render_progress(percent, w, h)
    local pct = percent or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end

    local fill_w = math.floor(w * pct)
    return {
        dimen = Geom:new{ w = w, h = h },
        getSize = function(self)
            return self.dimen
        end,
        handleEvent = function()
            return false
        end,
        paintTo = function(_self, bb, x, y)
            paint_pill(bb, x, y, w, h, Blitbuffer.COLOR_LIGHT_GRAY)
            if fill_w > 0 then
                paint_pill(bb, x, y, math.min(w, math.max(fill_w, h)), h, Blitbuffer.COLOR_GRAY_5)
            end
        end,
    }
end

local function fmt_duration(secs)
    secs = math.floor(tonumber(secs) or 0)
    if secs <= 0 then return "" end
    local hours = math.floor(secs / 3600)
    local mins = math.floor((secs % 3600) / 60)
    if hours > 0 then
        return tostring(hours) .. "h " .. tostring(mins) .. "m"
    end
    return tostring(math.max(1, mins)) .. "m"
end

local function build_progress_text(book, pct, progress_meta)
    progress_meta = type(progress_meta) == "table" and progress_meta or {}
    local left = {}
    local right = {}
    local total_pages = tonumber(book.stable_pages) or tonumber(book.pages)
    local current_page = tonumber(book.stable_current_page) or tonumber(book.current_page)
    local stable_current_label = type(book.stable_current_label) == "string"
        and book.stable_current_label ~= "" and book.stable_current_label or nil
    local stable_last_label = type(book.stable_last_label) == "string"
        and book.stable_last_label ~= "" and book.stable_last_label or nil
    local current_label = stable_current_label or (current_page and tostring(current_page))
    local total_label = stable_last_label or (total_pages and tostring(total_pages))
    local time_left = fmt_duration(book.time_left_secs)
    local entries = {
        total_pages = total_pages and zen_utils.formatPageCount(total_pages, true) or "",
        current_total = total_label and current_label and (tostring(current_label) .. " / " .. tostring(total_label)) or "",
        percent = tostring(pct) .. "%",
        time_left = time_left ~= "" and string.format(_("%s left"), time_left) or "",
    }
    local order = { "total_pages", "current_total", "percent", "time_left" }
    for _i, key in ipairs(order) do
        local text = entries[key]
        if text and text ~= "" then
            if progress_meta.left == key then
                left[#left + 1] = text
            end
            if progress_meta.right == key then
                right[#right + 1] = text
            end
        end
    end
    return table.concat(left, "  \194\183  "), table.concat(right, "  \194\183  ")
end

function M.build(ctx, source_key)
    local outer_width = ctx.width
    local outer_height = ctx.height
    local Screen = Device.screen
    local padding = Screen:scaleBySize(8)
    local width = math.max(1, outer_width - padding * 2)
    local height = math.max(1, outer_height - padding * 2)
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    local interactive = module_cfg.interactive ~= false
    local source = source_key or "recently_read"
    local order = module_cfg.order or "default"
    local book = ctx.data:getFeaturedBook(source, order)
    local show_description = module_cfg.show_description ~= false
    local show_status_bar = module_cfg.show_status_bar == true and type(ctx.buildStatusRow) == "function"

    local col_top_pad = math.max(1, math.floor(height * 0.015))
    local col_bottom_pad = math.max(3, math.floor(height * 0.02))
    local gap = math.max(4, math.floor(width * 0.025))

    if not book then
        return FrameContainer:new{
            width = outer_width,
            height = outer_height,
            padding = 0,
            bordersize = 0,
            background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
            CenterContainer:new{
                dimen = Geom:new{ w = outer_width, h = outer_height },
                TextWidget:new{ text = "No books found", face = ctx.face_label },
            },
        }
    end

    if type(ctx.setWidgetActions) == "function" then
        ctx.setWidgetActions{
            activate = function()
                ctx.openBook(book.path)
                return true
            end,
            context = function()
                if ctx.showBookMenu then return ctx.showBookMenu(book.path, source) end
                return false
            end,
        }
    end

    -- Both columns share this height so tops and bottoms align
    local col_h = math.max(1, height - col_top_pad - col_bottom_pad)

    -- Left column: cover fills col_h, width is natural (aspect ratio driven)
    local cover_max_w = math.max(1, math.floor(col_h * 0.80))
    local cover_widget, cover_w, cover_actual_h = cover_common.make_cover_widget(
        book, cover_max_w, col_h,
        { border = 1, background = Blitbuffer.COLOR_LIGHT_GRAY }
    )
    -- Right column must match the actual rendered cover height exactly
    local cover_col_w = math.max(1, cover_w or cover_max_w)
    col_h = math.max(1, cover_actual_h or col_h)
    gap = math.min(gap, math.max(0, width - cover_col_w - 1))
    local text_w = math.max(1, width - cover_col_w - gap)

    -- Fonts
    local scale = clamp(col_h / 300, 0.55, 1.28) * library_font.getScale(18)
    local title_style = text_style(module_cfg, "title")
    local author_style = text_style(module_cfg, "author")
    local description_style = text_style(module_cfg, "description")
    local title_face = get_text_face(title_style, Screen:scaleBySize(math.floor(title_style.font_size * scale + 0.5)))
    local meta_face = get_text_face(author_style, Screen:scaleBySize(math.floor(author_style.font_size * scale + 0.5)))
    local stats_face = Font:getFace("smallinfofont", Screen:scaleBySize(math.floor(6.5 * scale + 0.5)))
    local desc_face = get_text_face(description_style, library_font.scaleValue(description_style.font_size))

    -- Optional status bar (top of right column)
    local status_opts = {
        padding = 0,
        font_name = "xx_smallinfofont",
        font_size_delta = -2,
        row_height = 14,
        bold_text = module_cfg.status_bar_bold_text ~= false,
        show_bottom_border = module_cfg.status_bar_show_bottom_border ~= false,
    }
    local function build_status_widget()
        return show_status_bar and ctx.buildStatusRow(text_w, status_opts) or nil
    end
    local status_widget = build_status_widget()
    local status_h = status_widget and (status_widget:getSize().h or 0) or 0
    local status_gap = status_h > 0 and math.max(1, math.floor(col_h * 0.015)) or 0

    -- Progress bar anchored to bottom of right column
    local progress_percent = book.status == "new" and 0 or book.percent
    if book.status ~= "new"
            and book.stable_current_page and book.stable_pages and book.stable_pages > 0 then
        progress_percent = book.stable_current_page / book.stable_pages
    end
    local pct = math.floor((progress_percent or 0) * 100 + 0.5)
    local left_progress_text, right_progress_text = "", ""
    if book.status ~= "new" then
        left_progress_text, right_progress_text =
            build_progress_text(book, pct, module_cfg.progress_meta)
    end
    local has_progress_text = left_progress_text ~= "" or right_progress_text ~= ""
    local progress_h = math.max(1, math.floor(height * 0.022))
    local stats_text_h = 0
    if has_progress_text then
        local stats_probe = TextWidget:new{ text = "A", face = stats_face }
        stats_text_h = (stats_probe:getSize().h or 8)
        WidgetResources.free(stats_probe)
    end
    local bar_h = math.max(progress_h, stats_text_h)

    local progress_row
    if bar_h > 0 and book.status ~= "new" then
        if has_progress_text then
            local lw = TextWidget:new{ text = left_progress_text, face = stats_face, fgcolor = Blitbuffer.COLOR_BLACK }
            local rw = TextWidget:new{ text = right_progress_text, face = stats_face, fgcolor = Blitbuffer.COLOR_BLACK }
            local tgap = math.max(4, math.floor(text_w * 0.02))
            local bar_w = math.max(20, text_w - lw:getSize().w - rw:getSize().w - tgap * 2)
            progress_row = HorizontalGroup:new{
                align = "center",
                lw,
                HorizontalSpan:new{ width = tgap },
                render_progress(progress_percent, bar_w, progress_h),
                HorizontalSpan:new{ width = tgap },
                rw,
            }
        else
            progress_row = render_progress(progress_percent, text_w, progress_h)
        end
    end
    local bottom_h = progress_row and bar_h or 0

    -- Title: up to 2 lines before truncating
    local title_line_h = math.max(1, math.floor((tonumber(title_face.size) or 12) * 1.05 + 0.5))
    local author_line_h = math.max(1, math.floor((tonumber(meta_face.size) or 10) * 1.05 + 0.5))
    local probe = TextWidget:new{ text = book.title or "", face = title_face, bold = title_style.bold == true }
    local title_needs_2_lines = probe:getSize().w > text_w
    WidgetResources.free(probe)
    local title_h = title_line_h * (title_needs_2_lines and 2 or 1)

    local author_text = (book.authors or ""):gsub("%s*\n%s*", ", "):gsub("%s+", " ")
    local has_author = author_text ~= ""
    local author_h = 0
    if has_author then
        local author_probe = TextWidget:new{ text = author_text, face = meta_face, bold = author_style.bold == true }
        local lines = author_probe:getSize().w > text_w and 2 or 1
        WidgetResources.free(author_probe)
        author_h = author_line_h * lines
    end
    local title_author_gap = has_author and math.max(1, Screen:scaleBySize(1)) or 0

    -- Build top block widgets first so we can measure actual heights
    local top_items = {}
    local top_budget = col_h - bottom_h

    if status_widget and status_h > 0 then
        if top_budget >= status_h then
            local status_slot = FrameContainer:new{
                width = text_w,
                height = status_h,
                padding = 0,
                bordersize = 0,
                background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
                status_widget,
            }
            if type(ctx.registerClockRefresh) == "function" then
                ctx.registerClockRefresh(function()
                    local next_widget = build_status_widget()
                    if not next_widget then return false end
                    WidgetResources.replaceChild(status_slot, 1, next_widget)
                    return true
                end)
            end
            table.insert(top_items, status_slot)
            if status_gap > 0 then
                table.insert(top_items, VerticalSpan:new{ width = status_gap })
            end
            top_budget = top_budget - status_h - status_gap
        end
    end

    -- Clamp title/author to remaining budget
    if title_h + title_author_gap + author_h > top_budget then
        if has_author and top_budget >= author_line_h then
            if top_budget < title_h + title_author_gap + author_h then
                author_h = author_line_h
            end
            title_h = math.min(title_h, math.max(0, top_budget - title_author_gap - author_h))
        else
            author_h = 0
            title_author_gap = 0
            title_h = math.min(title_h, math.max(0, top_budget))
        end
    end
    if title_h <= 0 then title_author_gap = 0 end

    if title_h > 0 then
        table.insert(top_items, TextBoxWidget:new{
            text = book.title or "",
            width = text_w,
            height = title_h,
            face = title_face,
            bold = title_style.bold == true,
            line_height = 0,
            height_overflow_show_ellipsis = true,
        })
    end
    if title_author_gap > 0 then
        table.insert(top_items, VerticalSpan:new{ width = title_author_gap })
    end
    if has_author and author_h > 0 then
        table.insert(top_items, TextBoxWidget:new{
            text = author_text,
            width = text_w,
            height = author_h,
            face = meta_face,
            bold = author_style.bold == true,
            line_height = 0,
            fgcolor = Blitbuffer.COLOR_BLACK,
            height_overflow_show_ellipsis = true,
        })
    end

    -- Measure actual rendered top height (TextBoxWidget snaps to line boundaries)
    local actual_top_h = 0
    for _i, w in ipairs(top_items) do
        actual_top_h = actual_top_h + w:getSize().h
    end
    local actual_bottom_h = progress_row and progress_row:getSize().h or 0
    local spacer_h = math.max(0, col_h - actual_top_h - actual_bottom_h)

    -- Description fills the middle space
    local desc_line_h_probe = TextBoxWidget:new{
        text = "A\nA",
        width = text_w,
        face = desc_face,
        bold = description_style.bold == true,
    }
    local desc_line_h = math.max(1, math.ceil(desc_line_h_probe:getSize().h / 2))
    WidgetResources.free(desc_line_h_probe)

    local v_pad = math.max(2, math.floor(col_h * 0.02))
    local desc_available = math.max(0, spacer_h - v_pad * 2)
    local desc_text = book.description and util.htmlToPlainTextIfHtml(book.description) or ""
    local can_show_desc = show_description and desc_text ~= "" and desc_available >= desc_line_h
    local desc_h = 0
    if can_show_desc then
        desc_h = math.floor(desc_available / desc_line_h) * desc_line_h
    end

    -- Assemble right column: title/author top, desc middle, progress bottom
    local detail_children = { align = "left" }
    for _i, w in ipairs(top_items) do
        table.insert(detail_children, w)
    end

    if can_show_desc and desc_h > 0 then
        local desc_widget = TextBoxWidget:new{
            text = desc_text,
            width = text_w,
            height = desc_h,
            face = desc_face,
            bold = description_style.bold == true,
            fgcolor = Blitbuffer.COLOR_BLACK,
            height_overflow_show_ellipsis = true,
        }
        local actual_desc_h = desc_widget:getSize().h
        local after = math.max(0, spacer_h - v_pad - actual_desc_h)
        table.insert(detail_children, VerticalSpan:new{ width = v_pad })
        table.insert(detail_children, desc_widget)
        if after > 0 then
            table.insert(detail_children, VerticalSpan:new{ width = after })
        end
    elseif spacer_h > 0 then
        table.insert(detail_children, VerticalSpan:new{ width = spacer_h })
    end

    -- Progress anchored at bottom
    if progress_row then
        table.insert(detail_children, progress_row)
    end

    local detail = FrameContainer:new{
        width = text_w,
        height = col_h,
        padding = 0,
        bordersize = 0,
        background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
        VerticalGroup:new(detail_children),
    }

    local body = HorizontalGroup:new{
        align = "top",
        cover_widget,
        HorizontalSpan:new{ width = gap },
        detail,
    }

    local frame = FrameContainer:new{
        width = outer_width,
        height = outer_height,
        padding = 0,
        bordersize = 0,
        background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
        CenterContainer:new{
            dimen = Geom:new{ w = outer_width, h = outer_height },
            TopContainer:new{
            dimen = Geom:new{ w = width, h = height },
            VerticalGroup:new{
                align = "center",
                VerticalSpan:new{ width = col_top_pad },
                body,
            },
            },
        },
    }

    if not Device:isTouchDevice() or not interactive then
        return frame
    end
    local tap = InputContainer:new{
        dimen = Geom:new{ w = outer_width, h = outer_height },
        ges_events = {
            TapFeatured = {
                GestureRange:new{ ges = "tap", range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(), h = Screen:getHeight(),
                } },
            },
            HoldFeatured = {
                GestureRange:new{ ges = "hold", range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(), h = Screen:getHeight(),
                } },
            },
        },
    }
    tap.onTapFeatured = function(tap_self, _arg, ges)
        if not tap_self.dimen or not ges or not ges.pos then return false end
        if ctx.openTopMenu and ctx.openTopMenu(ges) then return true end
        if not tap_self.dimen:contains(ges.pos) then return false end
        ctx.openBook(book.path)
        return true
    end
    tap.onHoldFeatured = function(tap_self, _arg, ges)
        if not tap_self.dimen or not ges or not ges.pos then return false end
        if not tap_self.dimen:contains(ges.pos) then return false end
        if ctx.showBookMenu then return ctx.showBookMenu(book.path) end
        return false
    end
    tap[1] = frame
    return tap
end

return M

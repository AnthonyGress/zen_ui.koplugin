local Background = require("common/ui/background")
local Blitbuffer = require("ffi/blitbuffer")
local CornerBanner = require("common/ui/corner_banner")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local FrameContainer = require("ui/widget/container/framecontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local TextWidget = require("ui/widget/textwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local GestureRange = require("ui/gesturerange")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local cover_common = require("modules/filebrowser/patches/home/widgets/cover_common")
local library_font = require("modules/filebrowser/patches/library_font")
local Font = require("ui/font")
local Device = require("device")
local utils = require("common/utils")
local WidgetResources = require("common/widget_resources")
local _ = require("gettext")

local M = {}
M.SIZE = { preferred_pct = 0.20, min_pct = 0.12, max_pct = 0.50, grow_priority = 1 }

-- ── Strip badge helpers ───────────────────────────────────────────────────────

local function get_zen_config(plugin)
    if plugin and type(plugin.config) == "table" then
        return plugin.config
    end
    local global_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if global_plugin and type(global_plugin.config) == "table" then
        return global_plugin.config
    end
    local ok, ConfigManager = pcall(require, "config/manager")
    if ok and ConfigManager and type(ConfigManager.get) == "function" then
        return ConfigManager.get()
    end
end

local function paintPentagon(bb, bx, by, bw, bh, color)
    local rect_h = math.floor(bh * 30 / 42)
    local tip_h  = bh - rect_h
    bb:paintRectRGB32(bx, by, bw, rect_h, color)
    for row = 0, tip_h - 1 do
        local frac = (row + 1) / tip_h
        local rw   = math.max(2, math.floor(bw * (1 - frac)))
        local rx   = bx + math.floor((bw - rw) / 2)
        bb:paintRectRGB32(rx, by + rect_h + row, rw, 1, color)
    end
end

local function paintCheck(bb, bx, by, bw, bh, color)
    local tk = math.max(2, math.floor(math.min(bw, bh) / 8))
    local function drawLine(x0, y0, x1, y1)
        local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        if steps == 0 then steps = 1 end
        for i = 0, steps do
            local t = i / steps
            bb:paintRectRGB32(math.floor(x0 + t*(x1-x0)), math.floor(y0 + t*(y1-y0)), tk, tk, color)
        end
    end
    local lx0 = bx + math.floor(bw * 0.08); local ly0 = by + math.floor(bh * 0.62)
    local lx1 = bx + math.floor(bw * 0.30); local ly1 = by + math.floor(bh * 0.82)
    drawLine(lx0, ly0, lx1, ly1)
    drawLine(lx1, ly1, bx + math.floor(bw * 0.82), by + math.floor(bh * 0.18))
end

local function paintCircle(bb, cx, cy, r, color)
    for row = -r, r do
        local hw = math.floor(math.sqrt(math.max(0, r*r - row*row)))
        if hw > 0 then bb:paintRectRGB32(cx - hw, cy + row, 2*hw, 1, color) end
    end
end

local function paintPill(bb, bx, by, bw, bh, color)
    local r = bh / 2
    for row = 0, bh - 1 do
        local dy = math.abs(row + 0.5 - r)
        local dx = math.sqrt(math.max(0, r*r - dy*dy))
        local x0 = math.ceil(bx + r - dx)
        local x1 = math.floor(bx + bw - r + dx)
        local w  = x1 - x0
        if w > 0 then bb:paintRectRGB32(x0, by + row, w, 1, color) end
    end
end

-- Wraps a cover FrameContainer paintTo to draw library-style badges over the cover.
-- book fields: percent (0-1 float), status (string|nil), pages (number|nil), path (string)
-- series_index resolved lazily via BookInfoManager.
-- is_fav resolved lazily via ReadCollection.
local function apply_strip_badges(frame, book, plugin)
    local orig_paintTo = frame.paintTo
    if type(orig_paintTo) ~= "function" then return end

    -- per-item cache (lives on closure, one per cover widget)
    local _cached_pct_tw, _cached_pct_str, _cached_pct_fs, _cached_pct_dark
    local _cached_pause_tw, _cached_pause_fs, _cached_pause_dark
    local _cached_pages_tw, _cached_pages_str, _cached_pages_fs, _cached_pages_dark
    local _cached_series_tw, _cached_series_idx, _cached_series_fs, _cached_series_dark
    local _cached_fav_mark, _cached_fav_size, _cached_fav_dark

    local function get_fav_mark(size, is_dark)
        if _cached_fav_mark and _cached_fav_size == size and _cached_fav_dark == is_dark then
            return _cached_fav_mark
        end
        WidgetResources.free(_cached_fav_mark)
        _cached_fav_mark = TextWidget:new{
            text    = "\u{2606}",
            face    = Font:getFace("cfont", math.max(6, math.floor(size * 0.45))),
            fgcolor = is_dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
            padding = 0,
        }
        _cached_fav_size = size
        _cached_fav_dark = is_dark
        return _cached_fav_mark
    end

    local function free_badge_cache()
        WidgetResources.free(_cached_pct_tw)
        WidgetResources.free(_cached_pause_tw)
        WidgetResources.free(_cached_pages_tw)
        WidgetResources.free(_cached_series_tw)
        WidgetResources.free(_cached_fav_mark)
        _cached_pct_tw, _cached_pause_tw, _cached_pages_tw, _cached_series_tw, _cached_fav_mark = nil, nil, nil, nil, nil
    end

    WidgetResources.wrapFree(frame, free_badge_cache)

    frame.paintTo = function(self, bb, x, y)
        orig_paintTo(self, bb, x, y)

        local d = self.dimen
        if not (d and d.w and d.h and d.w > 0 and d.h > 0) then return end

        local border      = self.bordersize or 0
        local config      = get_zen_config(plugin)
        local badge_col   = utils.getBadgeColor(config)
        local badge_fg    = utils.getBadgeTextColor(config)
        local outline     = badge_fg
        local is_dark     = utils.isBadgeDark(config)
        local badge_scale = utils.getBadgeScale(config)
        local cover_badges = type(config) == "table" and type(config.browser_cover_badges) == "table"
            and config.browser_cover_badges or {}
        local show_favorite = cover_badges.show_favorite_badge == true
        local show_new = cover_badges.show_new_banner == true
        local show_progress = cover_badges.show_mosaic_progress == true
        local show_pages = type(config) == "table"
            and type(config.browser_page_count) == "table"
            and config.browser_page_count.show_page_count == true
        local show_series = type(config) == "table"
            and type(config.browser_series_badge) == "table"
            and config.browser_series_badge.show_series_badge == true

        local cov_w = d.w - 2 * border
        local cov_h = d.h - 2 * border
        if cov_w <= 0 or cov_h <= 0 then return end

        local ScreenDev = Device.screen
        local base_sz   = math.floor(math.max(ScreenDev:scaleBySize(20),
                            math.floor(d.w * 0.14)) * badge_scale)

        -- favorite: top-left circle with star
        if show_favorite then
            local ok_rc, ReadCollection = pcall(require, "readcollection")
            if ok_rc and ReadCollection then
                local is_fav = ReadCollection:isFileInCollections(book.path, true)
                if is_fav then
                    local r      = math.floor(base_sz * 0.45)
                    local inset  = utils.getBadgeInset(r)
                    local cx     = x + border + r + inset
                    local cy     = y + border + r + inset
                    paintCircle(bb, cx, cy, r + 2, outline)
                    paintCircle(bb, cx, cy, r,     badge_col)
                    local mark = get_fav_mark(r * 2, is_dark)
                    local msz  = mark:getSize()
                    mark:paintTo(bb, cx - math.ceil(msz.w/2), cy - math.ceil(msz.h/2))
                end
            end
        end

        -- progress/status: top-right pentagon
        local pct    = type(book.percent) == "number" and book.percent or 0
        local status = book.status
        local is_new = status == "new"
        local do_check = (status == "complete")
        local do_pause = (status == "abandoned")
        local do_pct   = not is_new and not do_check and not do_pause and pct > 0

        if show_progress and (do_check or do_pause or do_pct) then
            local bw  = math.floor(base_sz * 1.2)
            local bh  = math.floor(base_sz * 1.1)
            local bdg_x = x + d.w - bw - math.floor(bw * 0.25)
            local bdg_y = y + 2
            paintPentagon(bb, bdg_x - 2, bdg_y - 2, bw + 4, bh + 4, outline)
            paintPentagon(bb, bdg_x,     bdg_y,     bw,     bh,     badge_col)
            bb:paintRect(bdg_x - 2, bdg_y - 2, bw + 4, math.max(1, border), self.color or Blitbuffer.COLOR_BLACK)

            local rect_h = math.floor(bh * 30 / 42)
            local pad_x  = math.floor(bw * 0.12)
            local pad_y  = math.floor(rect_h * 0.15)
            local icon_x = bdg_x + pad_x
            local icon_y = bdg_y + pad_y
            local icon_w = bw - 2 * pad_x
            local icon_h = rect_h - 2 * pad_y

            if do_check then
                local sq   = math.min(icon_w, icon_h)
                paintCheck(bb, icon_x + math.floor((icon_w-sq)/2),
                               icon_y + math.floor((icon_h-sq)/2), sq, sq, badge_fg)
            elseif do_pause then
                local fs = math.max(7, math.floor(base_sz * 0.40))
                if not _cached_pause_tw or _cached_pause_fs ~= fs or _cached_pause_dark ~= is_dark then
                    WidgetResources.free(_cached_pause_tw)
                    _cached_pause_tw   = TextWidget:new{ text="\u{F0150}", face=Font:getFace("cfont",fs), fgcolor=badge_fg, padding=0 }
                    _cached_pause_fs   = fs
                    _cached_pause_dark = is_dark
                end
                local tsz = _cached_pause_tw:getSize()
                _cached_pause_tw:paintTo(bb, bdg_x + math.floor((bw-tsz.w)/2), bdg_y + math.floor((rect_h-tsz.h)/2))
            else
                local pct_str = math.floor(100 * pct) .. "%"
                local fs = math.max(7, math.floor(base_sz * 0.24))
                if not _cached_pct_tw or _cached_pct_str ~= pct_str or _cached_pct_fs ~= fs or _cached_pct_dark ~= is_dark then
                    WidgetResources.free(_cached_pct_tw)
                    _cached_pct_tw   = TextWidget:new{ text=pct_str, face=Font:getFace("cfont",fs), bold=true, fgcolor=badge_fg, padding=0 }
                    _cached_pct_str  = pct_str
                    _cached_pct_fs   = fs
                    _cached_pct_dark = is_dark
                end
                local tsz = _cached_pct_tw:getSize()
                _cached_pct_tw:paintTo(bb, bdg_x + math.floor((bw-tsz.w)/2), bdg_y + math.floor((rect_h-tsz.h)/2))
            end
        end

        -- page count: bottom-left pill
        local pages = tonumber(book.stable_pages) or tonumber(book.pages)
        if show_pages and pages and pages > 0 then
            local page_str = utils.formatPageCount(pages)
            local fs = math.max(7, math.floor(base_sz * 0.24))
            if not _cached_pages_tw or _cached_pages_str ~= page_str or _cached_pages_fs ~= fs or _cached_pages_dark ~= is_dark then
                WidgetResources.free(_cached_pages_tw)
                _cached_pages_tw   = TextWidget:new{ text=page_str, face=Font:getFace("cfont",fs), bold=true, fgcolor=badge_fg, padding=0 }
                _cached_pages_str  = page_str
                _cached_pages_fs   = fs
                _cached_pages_dark = is_dark
            end
            local tsz   = _cached_pages_tw:getSize()
            local bh    = math.floor(base_sz * 0.85)
            local h_pad = math.floor(base_sz * 0.12)
            local bw    = tsz.w + 2 * h_pad
            local inset = utils.getBadgeInset(math.floor(bh / 2))
            local bx    = x + inset
            local by    = y + d.h - bh - inset
            paintPill(bb, bx - 2, by - 2, bw + 4, bh + 4, outline)
            paintPill(bb, bx,     by,     bw,     bh,     badge_col)
            _cached_pages_tw:paintTo(bb, bx + math.floor((bw-tsz.w)/2), by + math.floor((bh-tsz.h)/2))
        end

        -- series: bottom-right circle
        if show_series then
            local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
            if ok_bim and BookInfoManager then
                local bi = BookInfoManager:getBookInfo(book.path, false)
                local series_idx = bi and tonumber(bi.series_index)
                if series_idx and series_idx > 0 then
                    local idx_str
                    if series_idx == math.floor(series_idx) then
                        idx_str = "#" .. tostring(math.floor(series_idx))
                    else
                        idx_str = "#" .. string.format("%.1f", series_idx)
                    end
                    local r    = math.floor(base_sz / 2)
                    local fs   = math.max(7, math.floor(base_sz * 0.26))
                    if not _cached_series_tw or _cached_series_idx ~= series_idx or _cached_series_fs ~= fs or _cached_series_dark ~= is_dark then
                        WidgetResources.free(_cached_series_tw)
                        local inner_w = math.floor(r * 1.30)
                        local function make_tw(label, sz)
                            return TextWidget:new{ text=label, face=Font:getFace("cfont",sz), bold=true, fgcolor=badge_fg, padding=0 }
                        end
                        local tw = make_tw(idx_str, fs)
                        if tw:getSize().w > inner_w then
                            WidgetResources.free(tw)
                            local no_hash = idx_str:sub(1,1) == "#" and idx_str:sub(2) or idx_str
                            local tw2 = make_tw(no_hash, fs)
                            if tw2:getSize().w <= inner_w then
                                tw = tw2
                            else
                                WidgetResources.free(tw2)
                                local sz = fs
                                while sz > 7 do
                                    local t = make_tw(no_hash, sz)
                                    if t:getSize().w <= inner_w then tw = t; break end
                                    WidgetResources.free(t)
                                    sz = sz - 1
                                end
                                if not tw then tw = make_tw(no_hash, 7) end
                            end
                        end
                        _cached_series_tw   = tw
                        _cached_series_idx  = series_idx
                        _cached_series_fs   = fs
                        _cached_series_dark = is_dark
                    end
                    local inset = utils.getBadgeInset(r)
                    local cx = x + d.w - r - inset
                    local cy = y + d.h - r - inset
                    paintCircle(bb, cx, cy, r + 2, outline)
                    paintCircle(bb, cx, cy, r,     badge_col)
                    local tsz = _cached_series_tw:getSize()
                    _cached_series_tw:paintTo(bb, cx - math.floor(tsz.w/2), cy - math.floor(tsz.h/2))
                end
            end
        end

        if show_new and is_new then
            local span = math.floor(base_sz * 2.5)
            local band_thick = math.floor(span * 0.35)
            local font_size = math.max(6, math.floor(base_sz * 0.25))
            CornerBanner.paint(
                bb, x, x + d.w, y, d.h,
                span, band_thick, _("New"), font_size, badge_col, badge_fg
            )
            if border > 0 then
                local border_color = self.bordercolor or Blitbuffer.COLOR_BLACK
                bb:paintRect(x, y, d.w, border, border_color)
                bb:paintRect(x + d.w - border, y, border, d.h, border_color)
            end
        end
    end
end

function M.build_strip(ctx, source_key)
    local width = ctx.width
    local height = ctx.height
    local Screen = Device.screen
    local module_cfg = type(ctx.module_cfg) == "table" and ctx.module_cfg or {}
    local source = source_key or "recently_read"
    local order = module_cfg.order or "default"
    local two_rows = module_cfg.two_rows == true
    local per_row
    local count
    if two_rows then
        count = tonumber(module_cfg.count) or 8
        if count < 2 then count = 2 end
        if count > 10 then count = 10 end
        per_row = math.ceil(count / 2)
    else
        count = tonumber(module_cfg.count) or 4
        if count < 3 then count = 3 end
        if count > 5 then count = 5 end
        per_row = count
    end
    local show_strip_titles = module_cfg.show_strip_titles == true
    local show_badges = module_cfg.show_badges == true
    local center_books = module_cfg.center_books == true
    local interactive = module_cfg.interactive ~= false

    local books = ctx.data:getBooksForStrip(source, count, order, ctx.component_id)
    if #books == 0 then
        return FrameContainer:new{
            width = width,
            height = height,
            padding = 0,
            bordersize = 0,
            background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
            CenterContainer:new{
                dimen = Geom:new{ w = width, h = height },
                TextWidget:new{ text = "No books found", face = ctx.face_label },
            },
        }
    end

    local num_rows = two_rows and 2 or 1
    local row_gap = two_rows and math.max(2, Screen:scaleBySize(3)) or 0
    local row_top_pad = math.max(4, Screen:scaleBySize(4))
    local row_bottom_pad = math.max(4, Screen:scaleBySize(4))
    local row_inner_bottom_pad = two_rows and math.max(2, Screen:scaleBySize(4)) or 0
    local strip_title_face = library_font.getFace(library_font.scaleValue(16))
    -- Measure the real rendered single-line height: TextBoxWidget renders at
    -- round((1+line_height)*face.size) and bumps a too-small height up to that,
    -- so a guessed title_h underreserves and the title overflows into the navbar.
    local title_h = 0
    if show_strip_titles then
        local probe = TextBoxWidget:new{
            text = "Ag",
            width = width,
            face = strip_title_face,
            bold = true,
        }
        title_h = probe:getSize().h
        WidgetResources.free(probe)
        if title_h < 1 then title_h = math.max(14, Screen:scaleBySize(12)) end
    end
    local title_gap = show_strip_titles and math.max(1, Screen:scaleBySize(2)) or 0
    -- cover_common floors cover height at 28px, so a row never shrinks below it.
    local MIN_COVER_H = 28

    local row_books = {}
    for r = 1, num_rows do
        row_books[r] = {}
    end
    for i, book in ipairs(books) do
        local r = math.ceil(i / per_row)
        if r <= num_rows then
            table.insert(row_books[r], book)
        end
    end
    local visible_rows = 0
    for r = 1, num_rows do
        if #row_books[r] > 0 then
            visible_rows = visible_rows + 1
        end
    end
    if visible_rows < 1 then visible_rows = 1 end
    local fixed_h = row_top_pad
        + row_bottom_pad
        + math.max(0, visible_rows - 1) * row_gap
        + visible_rows * row_inner_bottom_pad
    local avail_h = height - fixed_h
    -- Covers can't shrink below MIN_COVER_H; if titles won't also fit within `height`,
    -- drop them so the strip never overflows downward into the navbar (2-row / rotation).
    if show_strip_titles
            and avail_h < visible_rows * (MIN_COVER_H + title_gap + title_h) then
        show_strip_titles = false
        title_h = 0
        title_gap = 0
    end
    local per_row_budget = math.floor((avail_h - visible_rows * (title_h + title_gap)) / visible_rows)
    local max_cover_h_per_row = math.max(1, math.min(MIN_COVER_H, per_row_budget))
    if per_row_budget > MIN_COVER_H then max_cover_h_per_row = per_row_budget end

    local function build_row_widget(row_list, row_num)
        local n = #row_list
        local row_capacity = two_rows and per_row or n
        local center_short_row = center_books and n <= 3
        local left_align_partial = not center_short_row and two_rows and row_num == 2 and n < per_row
        local min_gap = math.max(6, math.min(Screen:scaleBySize(14), math.floor(width * 0.018)))
        local max_cover_w = math.max(24, math.floor((width - min_gap * (row_capacity - 1)) / row_capacity))
        local cover_h = math.min(max_cover_h_per_row, math.floor(max_cover_w * 1.62))
        if cover_h < 1 then cover_h = max_cover_h_per_row end

        local items = {}
        local covers_w = 0
        local row_h = 0
        for _i, book in ipairs(row_list) do
            local cover, cover_w = cover_common.make_cover_widget(
                book,
                max_cover_w,
                cover_h,
                {
                    border = 1,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    decorate = show_badges and function(frame)
                        apply_strip_badges(frame, book, rawget(_G, "__ZEN_UI_PLUGIN"))
                    end or nil,
                }
            )
            cover_w = cover_w or max_cover_w
            local cover_size = cover.getSize and cover:getSize() or nil
            local actual_cover_h = (cover_size and cover_size.h) or cover_h
            local item_h = show_strip_titles and (actual_cover_h + title_gap + title_h) or actual_cover_h
            if item_h > row_h then row_h = item_h end
            covers_w = covers_w + cover_w
            items[#items + 1] = {
                book = book,
                cover = cover,
                w = cover_w,
                cover_h = actual_cover_h,
                h = item_h,
            }
        end

        local gap = 0
        local extra_gap_px = 0
        if #items > 1 then
            local gap_slots = left_align_partial and math.max(1, row_capacity - 1) or (#items - 1)
            local avg_cover_w = math.floor(covers_w / #items)
            local cover_slots_w = left_align_partial and (avg_cover_w * row_capacity) or covers_w
            local available_gap = center_short_row
                and (min_gap * gap_slots)
                or math.max(min_gap * gap_slots, width - cover_slots_w)
            gap = math.floor(available_gap / gap_slots)
            extra_gap_px = left_align_partial and 0 or (available_gap - gap * gap_slots)
        end

        local row = HorizontalGroup:new{ align = "center" }
        for idx, item in ipairs(items) do
            local book = item.book
            local item_w = item.w
            local path = book.path

            local content
            if show_strip_titles and title_h > 0 then
                content = VerticalGroup:new{
                    align = "center",
                    CenterContainer:new{
                        dimen = Geom:new{ w = item_w, h = item.cover_h },
                        item.cover,
                    },
                    VerticalSpan:new{ width = title_gap },
                    TextBoxWidget:new{
                        text = book.title or "",
                        width = item_w,
                        height = title_h,
                        face = strip_title_face,
                        bold = true,
                        alignment = "center",
                        fgcolor = Blitbuffer.COLOR_BLACK,
                        height_overflow_show_ellipsis = true,
                    },
                }
            else
                content = CenterContainer:new{ dimen = Geom:new{ w = item_w, h = item.cover_h }, item.cover }
            end

            local item_widget = content
            if interactive and Device:isTouchDevice() then
                local tap = InputContainer:new{
                    dimen = Geom:new{ w = item_w, h = item.h },
                    ges_events = {
                        TapCover = {
                            GestureRange:new{ ges = "tap", range = Geom:new{
                                x = 0, y = 0,
                                w = Screen:getWidth(), h = Screen:getHeight(),
                            } },
                        },
                        HoldCover = {
                            GestureRange:new{ ges = "hold", range = Geom:new{
                                x = 0, y = 0,
                                w = Screen:getWidth(), h = Screen:getHeight(),
                            } },
                        },
                    },
                }
                tap.onTapCover = function(tap_self, _, ges)
                    if not tap_self.dimen or not ges or not ges.pos then return false end
                    if ctx.openTopMenu and ctx.openTopMenu(ges) then return true end
                    if not tap_self.dimen:contains(ges.pos) then return false end
                    ctx.openBook(path)
                    return true
                end
                tap.onHoldCover = function(tap_self, _, ges)
                    if not tap_self.dimen or not ges or not ges.pos then return false end
                    if not tap_self.dimen:contains(ges.pos) then return false end
                    if ctx.showBookMenu then return ctx.showBookMenu(path, source) end
                    return false
                end
                tap[1] = content
                item_widget = tap
            end
            if interactive and type(ctx.registerHomeFocusTarget) == "function" then
                item_widget = ctx.registerHomeFocusTarget({
                    key = "book:" .. tostring(path),
                    subrow = row_num or 1,
                    col = idx,
                    width = item_w,
                    height = item.h,
                    activate = function()
                        ctx.openBook(path)
                        return true
                    end,
                    context = function()
                        if ctx.showBookMenu then return ctx.showBookMenu(path, source) end
                        return false
                    end,
                }, item_widget)
            end

            table.insert(row, item_widget)
            if idx < #items then
                local gap_w = gap
                if extra_gap_px > 0 then
                    gap_w = gap_w + 1
                    extra_gap_px = extra_gap_px - 1
                end
                table.insert(row, HorizontalSpan:new{ width = gap_w })
            end
        end

        return row, row_h
    end

    local vgroup = VerticalGroup:new{}
    table.insert(vgroup, VerticalSpan:new{ width = row_top_pad })
    local total_row_h = 0
    for r = 1, num_rows do
        if #row_books[r] > 0 then
            local row_widget, row_h = build_row_widget(row_books[r], r)
            total_row_h = total_row_h + row_h
            local container = two_rows and r == 2 and #row_books[r] < per_row
                and not (center_books and #row_books[r] <= 3)
                and LeftContainer or CenterContainer
            table.insert(vgroup, container:new{ dimen = Geom:new{ w = width, h = row_h }, row_widget })
            if row_inner_bottom_pad > 0 then
                table.insert(vgroup, VerticalSpan:new{ width = row_inner_bottom_pad })
            end
            if r < num_rows and #row_books[r + 1] > 0 then
                table.insert(vgroup, VerticalSpan:new{ width = row_gap })
            end
        end
    end
    table.insert(vgroup, VerticalSpan:new{ width = row_bottom_pad })

    local frame = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = Background.tile_bg(Blitbuffer.COLOR_WHITE),
        TopContainer:new{
            dimen = Geom:new{ w = width, h = height },
            vgroup,
        },
    }

    if not interactive or not Device:isTouchDevice() then
        return frame
    end

    local swipe = InputContainer:new{
        dimen = Geom:new{ w = width, h = height },
        ges_events = {
            SwipeStrip = {
                GestureRange:new{ ges = "swipe", range = Geom:new{
                    x = 0, y = 0,
                    w = Screen:getWidth(), h = Screen:getHeight(),
                } },
            },
        },
    }
    swipe.onSwipeStrip = function(swipe_self, _, ges)
        if not swipe_self.dimen or not ges or not ges.pos then return false end
        if not swipe_self.dimen:contains(ges.pos) then return false end
        if ges.direction == "west" then
            if ctx.shiftStrip then ctx.shiftStrip(source, count, order, "next", ctx.component_id, two_rows) end
            return true
        elseif ges.direction == "east" then
            if ctx.shiftStrip then ctx.shiftStrip(source, count, order, "previous", ctx.component_id, two_rows) end
            return true
        end
        return false
    end
    swipe[1] = frame
    return swipe
end

return M

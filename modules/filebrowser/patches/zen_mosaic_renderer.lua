-- Zen-owned file tiles for mosaic mode. Folder tiles stay on CoverBrowser's
-- renderer so the existing folder-cover integration remains unchanged.
local function apply_zen_mosaic_renderer()
    local MosaicMenu = require("mosaicmenu")
    if MosaicMenu._zen_mosaic_renderer_patched then return end
    local plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")
    local stock_builder = MosaicMenu._updateItemsBuildUI
    if type(stock_builder) ~= "function" then return end

    local function get_upvalue(fn, name)
        for index = 1, 128 do
            local upvalue_name, value = debug.getupvalue(fn, index)
            if not upvalue_name then break end
            if upvalue_name == name then return value end
        end
    end

    -- Keep this name as an upvalue: Zen's existing mosaic patches continue to
    -- decorate CoverBrowser folder/group tiles without touching book tiles.
    local MosaicMenuItem = get_upvalue(stock_builder, "MosaicMenuItem")
    if not MosaicMenuItem then return end

    local Blitbuffer = require("ffi/blitbuffer")
    local BookInfoManager = require("bookinfomanager")
    local BD = require("ui/bidi")
    local Device = require("device")
    local Screen = Device.screen
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local Menu = require("ui/widget/menu")
    local TextWidget = require("ui/widget/textwidget")
    local UnderlineContainer = require("ui/widget/container/underlinecontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Size = require("ui/size")
    local CoverWidget = require("modules/filebrowser/patches/home/widgets/cover_common")
    local book_status = require("common/book_status")
    local library_font = require("modules/filebrowser/patches/library_font")
    local utils = require("common/utils")

    local ZenMosaicItem = InputContainer:extend{
        entry = nil,
        text = nil,
        dimen = nil,
        bookinfo_found = false,
        is_directory = false,
    }

    local function plugin_config()
        local plugin = plugin_ref or rawget(_G, "__ZEN_UI_PLUGIN")
        return plugin and type(plugin.config) == "table" and plugin.config or {}
    end

    local function strip_options()
        local config = plugin_config().mosaic_title_strip or {}
        return config.show_title == true, config.show_author == true
    end

    local function filename(path)
        return (path or ""):match("([^/]+)$") or ""
    end

    local function fallback_title(path)
        return filename(path):gsub("%.[^%.]+$", "")
    end

    local function cover_dimensions(width, height)
        local border = Size.border.thin
        local max_w = width - 2 * border
        local max_h = height - 2 * border
        local features = plugin_config().features or {}
        if features.browser_cover_mosaic_uniform ~= true then
            return math.max(1, max_w), math.max(1, max_h), border, false
        end
        local ratio = G_reader_settings:readSetting("uniform_cover_ratio") or "2:3"
        local numerator, denominator = ratio:match("(%d+):(%d+)")
        local aspect = (tonumber(numerator) or 2) / (tonumber(denominator) or 3)
        local target_w, target_h
        if max_w / max_h > aspect then
            target_h = max_h
            target_w = math.floor(max_h * aspect)
        else
            target_w = max_w
            target_h = math.floor(max_w / aspect)
        end
        return math.max(1, target_w), math.max(1, target_h), border, true
    end

    local function strip_metrics(show_title, show_author)
        if not show_title and not show_author then return 0 end
        local padding = Screen:scaleBySize(3)
        local gap = Screen:scaleBySize(2)
        local height = 2 * padding
        if show_title then
            local title = TextWidget:new{
                text = "Ag", face = library_font.getFace(library_font.scaleValue(16)),
                bold = true, padding = 0,
            }
            height = height + title:getSize().h
            title:free()
        end
        if show_title and show_author then height = height + gap end
        if show_author then
            local author = TextWidget:new{
                text = "Ag", face = library_font.getFace(library_font.scaleValue(13)),
                padding = 0,
            }
            height = height + author:getSize().h
            author:free()
        end
        return height
    end

    function ZenMosaicItem:init()
        self.filepath = self.entry.file or self.entry.path
        self.ges_events = {
            TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
            HoldSelect = { GestureRange:new{ ges = "hold", range = self.dimen } },
        }
        self._underline_container = UnderlineContainer:new{
            vertical_align = "top",
            padding = Size.padding.tiny,
            dimen = Geom:new{ w = self.width, h = self.height + Size.line.focus_indicator },
            linesize = Size.line.focus_indicator,
        }
        self[1] = self._underline_container
        self:update()
        self.init_done = true
    end

    function ZenMosaicItem:update()
        local show_title, show_author = strip_options()
        local strip_h = strip_metrics(show_title, show_author)
        local content_h = math.max(1, self.height - strip_h)
        local target_w, target_h, border, uniform = cover_dimensions(self.width, content_h)
        local specs = { max_cover_w = target_w, max_cover_h = target_h }
        self.menu.cover_specs = self.do_cover_image and specs or false
        self.file_deleted = self.entry.dim
        self.is_directory = false
        self.bookinfo_found = false
        self._has_cover_image = false
        self.cover_specs = nil
        self._zen_cover_frame = nil

        local info = BookInfoManager:getBookInfo(self.filepath, self.do_cover_image)
        local cover
        if info then
            self.bookinfo_found = true
            self._zen_bookinfo = info
            local book_info = type(self.menu.getBookInfo) == "function"
                and self.menu.getBookInfo(self.filepath) or self.entry or {}
            self.status = book_info.status
            self.percent_finished = book_info.percent_finished
            self._zen_effective_status = book_status.getComputedStatus(
                self.filepath, self.status, self.percent_finished
            )
            local badge = plugin_config().browser_cover_badges or {}
            local is_collection = self.menu.name == "collections" or self.menu._zen_coll_list
            if badge.show_favorite_badge == true and not is_collection then
                local ReadCollection = require("readcollection")
                self._zen_is_fav = ReadCollection:isFileInCollections(self.filepath, true)
            else
                self._zen_is_fav = false
            end
            self._has_cover_image = self.do_cover_image and info.has_cover
                and not info.ignore_cover and info.cover_bb ~= nil
        else
            self.cover_specs = specs
        end

        -- This is shared with Home and the list layout. It gives real and
        -- generated covers the same uniform dimensions, border, and corner
        -- treatment while retaining the fast final-render cache.
        local book = {
            path = self.filepath,
            cover_bb = self._has_cover_image and info.cover_bb or nil,
            -- false is intentional: generated filename covers must not repeat
            -- the BookInfo lookup the tile already performed.
            bookinfo = info or false,
        }
        if info and info.cover_bb and not self._has_cover_image then
            info.cover_bb:free()
            info.cover_bb = nil
        end
        local frame = CoverWidget.make_cover_widget(book, target_w, target_h, {
            border = border,
            uniform = uniform,
        })
        if info then info.cover_bb = nil end
        cover = CenterContainer:new{
            dimen = Geom:new{ w = self.width, h = content_h },
            frame,
        }
        self._zen_cover_frame = frame
        if self._has_cover_image then self.menu._has_cover_images = true end

        local content = VerticalGroup:new{ align = "center", cover }
        if strip_h > 0 then
            local lines = VerticalGroup:new{ align = "center" }
            if show_title and info then
                table.insert(lines, TextWidget:new{
                    text = (not info.ignore_meta and info.title) or fallback_title(self.filepath),
                    face = library_font.getFace(library_font.scaleValue(16)),
                    bold = true,
                    max_width = self.width - Screen:scaleBySize(12),
                    truncate_with_ellipsis = true,
                    padding = 0,
                })
            end
            if show_author and info and info.authors then
                table.insert(lines, TextWidget:new{
                    text = info.authors:match("^[^\n]+") or info.authors,
                    face = library_font.getFace(library_font.scaleValue(13)),
                    max_width = self.width - Screen:scaleBySize(12),
                    truncate_with_ellipsis = true,
                    padding = 0,
                })
            end
            table.insert(content, CenterContainer:new{
                dimen = Geom:new{ w = self.width, h = strip_h },
                lines,
            })
        end
        if self._underline_container[1] then self._underline_container[1]:free() end
        self._underline_container[1] = content
    end

    function ZenMosaicItem:onFocus()
        local features = plugin_config().features or {}
        self._underline_container.color = features.browser_hide_underline == true
            and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        return true
    end

    function ZenMosaicItem:onUnfocus()
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end

    function ZenMosaicItem:onTapSelect()
        self.menu:onMenuSelect(self.entry)
        return true
    end

    function ZenMosaicItem:onHoldSelect()
        self.menu:onMenuHold(self.entry)
        return true
    end

    local function paint_circle(bb, cx, cy, radius, color)
        for row = -radius, radius do
            local half = math.floor(math.sqrt(math.max(0, radius * radius - row * row)))
            if half > 0 then bb:paintRectRGB32(cx - half, cy + row, 2 * half, 1, color) end
        end
    end

    local function paint_pill(bb, x, y, width, height, color)
        local radius = height / 2
        for row = 0, height - 1 do
            local dy = math.abs(row + 0.5 - radius)
            local dx = math.sqrt(math.max(0, radius * radius - dy * dy))
            local x0 = math.ceil(x + radius - dx)
            local x1 = math.floor(x + width - radius + dx)
            if x1 > x0 then bb:paintRectRGB32(x0, y + row, x1 - x0, 1, color) end
        end
    end

    local function paint_pentagon(bb, x, y, width, height, color)
        local rect_h = math.floor(height * 30 / 42)
        bb:paintRectRGB32(x, y, width, rect_h, color)
        local tip_h = height - rect_h
        for row = 0, tip_h - 1 do
            local row_w = math.max(2, math.floor(width * (1 - (row + 1) / tip_h)))
            bb:paintRectRGB32(x + math.floor((width - row_w) / 2), y + rect_h + row, row_w, 1, color)
        end
    end

    local function paint_check(bb, x, y, width, height, color)
        local thickness = math.max(2, math.floor(math.min(width, height) / 8))
        local function line(x0, y0, x1, y1)
            local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
            if steps == 0 then steps = 1 end
            for step = 0, steps do
                local t = step / steps
                bb:paintRectRGB32(math.floor(x0 + t * (x1 - x0)),
                    math.floor(y0 + t * (y1 - y0)), thickness, thickness, color)
            end
        end
        local lx0, ly0 = x + math.floor(width * 0.08), y + math.floor(height * 0.62)
        local lx1, ly1 = x + math.floor(width * 0.30), y + math.floor(height * 0.82)
        line(lx0, ly0, lx1, ly1)
        line(lx1, ly1, x + math.floor(width * 0.82), y + math.floor(height * 0.18))
    end

    local function badge_colors(config)
        local badge = config.browser_cover_badges or {}
        local color = badge.badge_color
        local is_dark = color == nil or (type(color) == "table"
            and color[1] == 0 and color[2] == 0 and color[3] == 0)
        return utils.getBadgeColor(config), is_dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
    end

    local function badge_size(frame, config)
        local base = math.max(Screen:scaleBySize(20), math.floor(frame.dimen.w * 0.14))
        return math.floor(base * utils.getBadgeScale(config))
    end

    local function banner_size(item, frame, config)
        local width = tonumber(item.width) or frame.dimen.w
        local height = tonumber(item.height) or frame.dimen.h
        local base = math.max(math.floor(math.min(width, height) / 8),
            math.floor(frame.dimen.w * 0.14))
        return math.floor(base * utils.getBadgeScale(config))
    end

    local function badge_text(item, key, text, size, color)
        local cached = item[key]
        if cached and (cached.text ~= text or cached.size ~= size or cached.color ~= color) then
            cached.widget:free()
            cached = nil
        end
        if not cached then
            cached = {
                text = text,
                size = size,
                color = color,
                widget = TextWidget:new{
                    text = text,
                    face = Font:getFace("cfont", size),
                    bold = true,
                    fgcolor = color,
                    padding = 0,
                },
            }
            item[key] = cached
        end
        return cached.widget
    end

    local function paint_page_badge(item, bb, text, config)
        local frame = item._zen_cover_frame
        if not frame or not frame.dimen then return end
        local size = badge_size(frame, config)
        local color, foreground = badge_colors(config)
        local widget = badge_text(item, "_zen_pages_badge", text, math.max(7, math.floor(size * 0.24)), foreground)
        local widget_size = widget:getSize()
        local height = math.floor(size * 0.85)
        local width = widget_size.w + 2 * math.floor(size * 0.12)
        local inset = utils.getBadgeInset(math.floor(height / 2))
        local x = frame.dimen.x + inset
        local y = frame.dimen.y + frame.dimen.h - height - inset
        paint_pill(bb, x - 2, y - 2, width + 4, height + 4, foreground)
        paint_pill(bb, x, y, width, height, color)
        widget:paintTo(bb, x + math.floor((width - widget_size.w) / 2),
            y + math.floor((height - widget_size.h) / 2))
    end

    local function paint_series_badge(item, bb, text, config)
        local frame = item._zen_cover_frame
        if not frame or not frame.dimen then return end
        local size = badge_size(frame, config)
        local radius = math.floor(size / 2)
        local color, foreground = badge_colors(config)
        local font_size = math.max(7, math.floor(size * 0.26))
        local widget = badge_text(item, "_zen_series_badge", text, font_size, foreground)
        while font_size > 7 and widget:getSize().w > math.floor(radius * 1.3) do
            font_size = font_size - 1
            widget = badge_text(item, "_zen_series_badge", text, font_size, foreground)
        end
        local widget_size = widget:getSize()
        local inset = utils.getBadgeInset(radius)
        local x = frame.dimen.x + frame.dimen.w - radius - inset
        local y = frame.dimen.y + frame.dimen.h - radius - inset
        paint_circle(bb, x, y, radius + 2, foreground)
        paint_circle(bb, x, y, radius, color)
        widget:paintTo(bb, x - math.floor(widget_size.w / 2), y - math.floor(widget_size.h / 2))
    end

    local function paint_progress_badge(item, bb, config)
        local badge = config.browser_cover_badges or {}
        if badge.show_mosaic_progress ~= true or not item._zen_effective_status then return end
        local effective_status = item._zen_effective_status
        local dim_finished = badge.dim_finished_books == true and effective_status == "complete"
        local is_new = effective_status == "new"
        local do_check = effective_status == "complete" and not dim_finished
        local do_pause = effective_status == "abandoned"
        local do_pct = not is_new and not dim_finished and not do_check and not do_pause
            and item.percent_finished ~= nil
        if not (do_check or do_pause or do_pct) then return end

        local frame = item._zen_cover_frame
        if not frame or not frame.dimen then return end
        local size = badge_size(frame, config)
        local width = math.floor(size * 1.2)
        local height = math.floor(size * 1.1)
        local color, foreground = badge_colors(config)
        local x = frame.dimen.x + frame.dimen.w - width - math.floor(width * 0.25)
        local y = frame.dimen.y + 2
        paint_pentagon(bb, x - 2, y - 2, width + 4, height + 4, foreground)
        paint_pentagon(bb, x, y, width, height, color)
        local border = math.max(1, frame.bordersize or 0)
        bb:paintRect(x - 2, y - 2, width + 4, border, Blitbuffer.COLOR_BLACK)

        local rect_h = math.floor(height * 30 / 42)
        if do_check then
            local padding = math.floor(width * 0.12)
            local icon_w = width - 2 * padding
            local icon_h = rect_h - 2 * math.floor(rect_h * 0.15)
            local square = math.min(icon_w, icon_h)
            paint_check(bb, x + padding + math.floor((icon_w - square) / 2),
                y + math.floor(rect_h * 0.15) + math.floor((icon_h - square) / 2), square, square, foreground)
            return
        end

        local text = do_pause and "\u{F0150}" or (math.floor(100 * item.percent_finished) .. "%")
        local font_size = do_pause and math.max(7, math.floor(size * 0.40))
            or math.max(7, math.floor(size * 0.24))
        local widget = badge_text(item, "_zen_progress_badge", text, font_size, foreground)
        local widget_size = widget:getSize()
        widget:paintTo(bb, x + math.floor((width - widget_size.w) / 2),
            y + math.floor((rect_h - widget_size.h) / 2))
    end

    local function paint_favorite_badge(item, bb, config)
        local badge = config.browser_cover_badges or {}
        if badge.show_favorite_badge ~= true or not item._zen_is_fav then return end
        local frame = item._zen_cover_frame
        if not frame or not frame.dimen then return end
        local size = badge_size(frame, config)
        local radius = math.floor(size * 0.45)
        local color, foreground = badge_colors(config)
        local inset = utils.getBadgeInset(radius)
        local x = BD.mirroredUILayout() and (frame.dimen.x + frame.dimen.w - radius - inset)
            or (frame.dimen.x + radius + inset)
        local y = frame.dimen.y + radius + inset
        paint_circle(bb, x, y, radius + 2, foreground)
        paint_circle(bb, x, y, radius, color)
        local widget = badge_text(item, "_zen_favorite_badge", "\u{2606}",
            math.max(6, math.floor(radius * 2 * 0.45)), foreground)
        local widget_size = widget:getSize()
        widget:paintTo(bb, x - math.ceil(widget_size.w / 2), y - math.ceil(widget_size.h / 2))
    end

    local function paint_native_progress(item, bb, config)
        local badge = config.browser_cover_badges or {}
        if badge.show_native_progress_bar ~= true or item.percent_finished == nil
                or item._zen_effective_status == "new" or item._zen_effective_status == "complete" then
            return
        end
        local frame = item._zen_cover_frame
        if not frame or not frame.dimen then return end
        local ProgressWidget = require("ui/widget/progresswidget")
        local height = Screen:scaleBySize(8)
        local margin = math.floor((badge_size(frame, config) - height) / 2)
        local width = math.max(1, frame.dimen.w - 2 * margin)
        local progress = item._zen_native_progress
        if not progress then
            progress = ProgressWidget:new{
                bgcolor = Blitbuffer.COLOR_WHITE,
                fillcolor = Blitbuffer.COLOR_BLACK,
                bordercolor = Blitbuffer.COLOR_BLACK,
                height = height,
                margin_h = Screen:scaleBySize(1),
                width = width,
                radius = Size.border.thin,
                bordersize = Size.border.default,
            }
            item._zen_native_progress = progress
        end
        progress.width = width
        progress.fillcolor = item._zen_effective_status == "abandoned"
            and Blitbuffer.COLOR_GRAY_6 or Blitbuffer.COLOR_BLACK
        progress:setPercentage(item.percent_finished)
        progress:paintTo(bb, frame.dimen.x + margin,
            frame.dimen.y + frame.dimen.h - badge_size(frame, config) + margin)
    end

    local function paint_new_banner(item, bb, config)
        local badge = config.browser_cover_badges or {}
        if badge.show_new_banner ~= true or item._zen_effective_status ~= "new" then return end
        local frame = item._zen_cover_frame
        if not frame or not frame.dimen then return end
        local CornerBanner = require("common/ui/corner_banner")
        local _ = require("gettext")
        local size = banner_size(item, frame, config)
        local color, foreground = badge_colors(config)
        local span = math.floor(size * 2.5)
        CornerBanner.paint(bb, frame.dimen.x, frame.dimen.x + frame.dimen.w,
            frame.dimen.y, frame.dimen.h, span, math.floor(span * 0.35),
            _("New"), math.max(6, math.floor(size * 0.25)), color, foreground)
    end

    local function dim_finished_cover(item, bb, config)
        local badge = config.browser_cover_badges or {}
        if badge.dim_finished_books ~= true or item._zen_effective_status ~= "complete" then return end
        local frame = item._zen_cover_frame
        if not frame or not frame.dimen then return end
        local border = frame.bordersize or 0
        local width, height = frame.dimen.w - 2 * border, frame.dimen.h - 2 * border
        if width > 0 and height > 0 then
            bb:lightenRect(frame.dimen.x + border, frame.dimen.y + border, width, height, 0.4)
        end
    end

    function ZenMosaicItem:paintTo(bb, x, y)
        InputContainer.paintTo(self, bb, x, y)
        local config = plugin_config()
        dim_finished_cover(self, bb, config)
        paint_favorite_badge(self, bb, config)
        paint_native_progress(self, bb, config)
        paint_progress_badge(self, bb, config)
        if config.browser_page_count and config.browser_page_count.show_page_count
                and self._zen_bookinfo then
            local pages = utils.getStablePageCount(self.filepath, self._zen_bookinfo.pages)
            if pages then paint_page_badge(self, bb, utils.formatPageCount(pages), config) end
        end
        if config.browser_series_badge and config.browser_series_badge.show_series_badge
                and self._zen_bookinfo and tonumber(self._zen_bookinfo.series_index) then
            local index = tonumber(self._zen_bookinfo.series_index)
            local label = index == math.floor(index) and "#" .. math.floor(index)
                or string.format("#%.1f", index)
            paint_series_badge(self, bb, label, config)
        end
        paint_new_banner(self, bb, config)
    end

    function MosaicMenu:_updateItemsBuildUI()
        local index_offset = (self.page - 1) * self.perpage
        local line_layout = {}
        local select_number
        for slot = 1, self.perpage do
            local index = index_offset + slot
            local entry = self.item_table[index]
            if not entry then break end
            if index == self.itemnumber then select_number = slot end
            local shortcut, shortcut_style
            if self.is_enable_shortcut then
                shortcut = self.item_shortcuts[slot]
                shortcut_style = (slot < 11 or slot > 20) and "square" or "grey_square"
            end
            if slot % self.nb_cols == 1 then
                if slot > 1 then table.insert(self.layout, line_layout) end
                line_layout = {}
                table.insert(self.item_group, VerticalSpan:new{ width = self.item_margin })
                local row = HorizontalGroup:new{}
                local container = self._do_center_partial_rows and CenterContainer or LeftContainer
                table.insert(self.item_group, container:new{
                    dimen = Geom:new{ w = self.inner_dimen.w, h = self.item_height },
                    row,
                })
                table.insert(row, HorizontalSpan:new{ width = self.item_margin })
                self._zen_mosaic_row = row
            end
            entry.idx = index
            local common = {
                height = self.item_height,
                width = self.item_width,
                entry = entry,
                text = Menu.getMenuText(entry),
                show_parent = self.show_parent,
                mandatory = entry.mandatory,
                dimen = self.item_dimen:copy(),
                shortcut = shortcut,
                shortcut_style = shortcut_style,
                menu = self,
                do_cover_image = self._do_cover_images,
                do_hint_opened = self._do_hint_opened,
            }
            -- MosaicMenuItem must remain a direct upvalue of this builder:
            -- folder-cover and badge patches discover and decorate this class.
            local item = (entry.is_file or entry.file) and ZenMosaicItem:new(common)
                or MosaicMenuItem:new(common)
            table.insert(self._zen_mosaic_row, item)
            table.insert(self._zen_mosaic_row, HorizontalSpan:new{ width = self.item_margin })
            table.insert(line_layout, item)
            if not item.bookinfo_found and not item.is_directory and not item.file_deleted then
                table.insert(self.items_to_update, item)
            end
        end
        if #line_layout > 0 then table.insert(self.layout, line_layout) end
        table.insert(self.item_group, VerticalSpan:new{ width = self.item_margin })
        self._zen_mosaic_row = nil
        return select_number
    end

    MosaicMenu._zen_mosaic_renderer_patched = true
    MosaicMenu._zen_mosaic_item_class = ZenMosaicItem
    local ok, FileChooser = pcall(require, "ui/widget/filechooser")
    if ok and FileChooser and FileChooser._updateItemsBuildUI == stock_builder then
        FileChooser._updateItemsBuildUI = MosaicMenu._updateItemsBuildUI
    end
end

return apply_zen_mosaic_renderer

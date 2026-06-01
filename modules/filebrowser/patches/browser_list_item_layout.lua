local function apply_browser_list_item_layout()
    -- Capture plugin reference while __ZEN_UI_PLUGIN is still set by run_feature.
    local _plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")
    local Cover = require("common/cover_utils")

    local BD = require("ui/bidi")
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local IconWidget = require("ui/widget/iconwidget")
    local ImageWidget = require("ui/widget/imagewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local ReadCollection = require("readcollection")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local book_status = require("common/book_status")
    local library_font = require("common/library_font")
    local util = require("util")
    local zen_utils = require("common/utils")
    local _ = require("gettext")

    local Screen = Device.screen
    local scale_by_size = Screen:scaleBySize(1000000) * (1 / 1000000)

    local function patchListMenu()
        local ListMenu = require("listmenu")
        local ListMenuItem = Cover.getUpvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
        if not ListMenuItem then return end
        if ListMenuItem._zen_bll_patched then return end

        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if not ok_bim then return end

        -- Corner-mask helpers
        local corner_radius = Screen:scaleBySize(8)

        local function paintCornerMasks(bb, tx, ty, tw, th, r)
            local color = Blitbuffer.COLOR_WHITE
            for j = 0, r - 1 do
                local inner = math.sqrt(r * r - (r - j) * (r - j))
                local cut = math.ceil(r - inner)
                if cut > 0 then
                    bb:paintRect(tx, ty + j, cut, 1, color)
                    bb:paintRect(tx + tw - cut, ty + j, cut, 1, color)
                    bb:paintRect(tx, ty + th - 1 - j, cut, 1, color)
                    bb:paintRect(tx + tw - cut, ty + th - 1 - j, cut, 1, color)
                end
            end
        end

        local function paintCornerBorderArcs(bb, tx, ty, tw, th, r, bsz, color)
            local r_outer = r
            local r_inner = r - bsz
            for j = 0, r - 1 do
                for c = 0, r - 1 do
                    local dx = r - c - 0.5
                    local dy = r - j - 0.5
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist >= r_inner and dist <= r_outer then
                        bb:paintRect(tx + c, ty + j, 1, 1, color)
                        bb:paintRect(tx + tw - 1 - c, ty + j, 1, 1, color)
                        bb:paintRect(tx + c, ty + th - 1 - j, 1, 1, color)
                        bb:paintRect(tx + tw - 1 - c, ty + th - 1 - j, 1, 1, color)
                    end
                end
            end
        end

        local original_update = ListMenuItem.update

        function ListMenuItem:update()
            -- Intercept list mode (no covers) to fix directory text wrapping
            if not self.do_cover_image then
                original_update(self)
                local is_dir = not (self.entry.is_file or self.entry.file)
                if is_dir then
                    -- Fix folder name widget (TextBoxWidget) overflowing to 3+ lines in list mode
                    pcall(function()
                        local widget = self[1] and self[1][1] and self[1][1][2]
                        local wleft = widget and widget[1] and widget[1][1] and widget[1][1][2]
                        if wleft and wleft.height_adjust and wleft.getLineHeight then
                            local scale = library_font.getScale(18)
                            local dimen_h = self.height - 2
                            local fs = math.floor(20 * dimen_h * (1 / 64) / scale_by_size * scale + 0.5)
                            local max_scaled = math.max(1, math.floor(24 * scale + 0.5))
                            if fs > max_scaled then fs = max_scaled end

                            wleft:free(true)
                            wleft.face = library_font.getFace(fs)
                            wleft:init() -- init once to compute font metrics

                            local lh = wleft:getLineHeight()
                            wleft.height_adjust = false -- CRITICAL: prevent it from expanding
                            wleft.height = lh * 2

                            wleft:free(true)
                            wleft:init() -- re-measure limited to max 2 lines
                        end
                    end)
                end
                return
            end

            local is_dir = not (self.entry.is_file or self.entry.file)
            if is_dir then
                -- Render all directory rows (up-folder and regular folders) with the
                -- same padded layout so long names never overlap the top separator.
                do
                    local is_go_up = self.entry.is_go_up
                    local underline_h = 1
                    local dimen_h     = self.height - 2 * underline_h
                    local text_safe_pad_top = math.max(2, Screen:scaleBySize(4))
                    local text_safe_pad_bottom = math.max(2, Screen:scaleBySize(3))
                    local content_h = math.max(1, dimen_h - text_safe_pad_top - text_safe_pad_bottom)
                    local border_size = Size.border.thin
                    local cover_v_pad = Screen:scaleBySize(4)
                    local cover_zone_w = dimen_h
                    local max_img  = dimen_h - 2 * border_size - 2 * cover_v_pad
                    local ratio = Cover.getRatio()
                    local cover_w = math.floor(max_img * ratio)

                    local function _fontSize(nominal, max_size)
                        local scale = library_font.getScale(18)
                        local fs = math.floor(nominal * dimen_h * (1 / 64) / scale_by_size * scale + 0.5)
                        if max_size then
                            local max_scaled = math.max(1, math.floor(max_size * scale + 0.5))
                            if fs >= max_scaled then return max_scaled end
                        end
                        return fs
                    end

                    -- Folder icon: open for up-folder, outline for regular directories
                    local folder_icon = is_go_up and "\u{F024B}" or "\u{F024A}"
                    local cover_frame = FrameContainer:new{
                        width = cover_w + 2 * border_size,
                        height = max_img + 2 * border_size,
                        margin = 0, padding = 0, bordersize = border_size,
                        CenterContainer:new{
                            dimen = { w = cover_w, h = max_img },
                            TextWidget:new{
                                text = folder_icon,
                                face = library_font.getFace(_fontSize(20)),
                            },
                        },
                    }
                    local wleft = CenterContainer:new{
                        dimen = { w = cover_zone_w, h = dimen_h },
                        cover_frame,
                    }
                    self._cover_frame = cover_frame

                    local pad_left = Screen:scaleBySize(6)
                    local pad_right = Screen:scaleBySize(10)
                    local left_offset = cover_zone_w + pad_left
                    local fs_title = _fontSize(18, 21)
                    fs_title = math.min(fs_title, math.max(9, math.floor(content_h * 0.45)))
                    local title_text = is_go_up
                        and (BD.mirroredUILayout() and BD.ltr("../ \u{F062}") or "\u{F062}  ../")
                        or BD.directory(self.text)

                    local right_widgets = {}
                    local right_w = 0
                    if not is_go_up and self.mandatory then
                        local file_count = tonumber(self.mandatory:match("(%d+)%s*\xef\x80\x96")) or 0
                        local dir_count = tonumber(self.mandatory:match("(%d+)%s*\xef\x84\x94")) or 0
                        local fs_right = _fontSize(16, 20)
                        fs_right = math.min(fs_right, math.max(8, math.floor(content_h * 0.34)))
                        if dir_count > 0 then
                            table.insert(right_widgets, TextWidget:new{
                                text = tostring(dir_count) .. " " .. (dir_count == 1 and _("Folder") or _("Folders")),
                                face = library_font.getFace(fs_right),
                                padding = 0,
                            })
                        end
                        table.insert(right_widgets, TextWidget:new{
                            text = tostring(file_count) .. " " .. (file_count == 1 and _("Book") or _("Books")),
                            face = library_font.getFace(fs_right),
                            padding = 0,
                        })
                        for _i, widget in ipairs(right_widgets) do
                            right_w = math.max(right_w, widget:getWidth())
                        end
                        local right_available = math.max(0, self.width - left_offset - 2 * pad_right)
                        right_w = math.min(right_w, math.floor(right_available * 0.45))
                    end

                    local main_w = math.max(1, self.width - left_offset - right_w - 2 * pad_right)
                    local line_probe = TextWidget:new{
                        text = "Ag",
                        face = library_font.getFace(fs_title),
                        bold = true,
                        padding = 0,
                    }
                    local title_h = math.min(content_h, line_probe:getSize().h * 2)
                    line_probe:free()
                    local wtitle = TextBoxWidget:new{
                        text = title_text,
                        face = library_font.getFace(fs_title),
                        width = main_w,
                        height = title_h,
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                        alignment = "left",
                        bold = true,
                    }
                    local row_dimen = { w = self.width, h = dimen_h }
                    local widget = OverlapGroup:new{
                        dimen = row_dimen,
                        LeftContainer:new{
                            dimen = { w = self.width, h = dimen_h },
                            HorizontalGroup:new{
                                wleft,
                                HorizontalSpan:new{ width = pad_left },
                                LeftContainer:new{
                                    dimen = { w = main_w, h = dimen_h },
                                    VerticalGroup:new{
                                        VerticalSpan:new{ width = text_safe_pad_top },
                                        wtitle,
                                    },
                                },
                            },
                        },
                    }
                    if #right_widgets > 0 then
                        local right_stack = VerticalGroup:new{ align = "right" }
                        table.insert(right_stack, VerticalSpan:new{ width = text_safe_pad_top })
                        for _i, right_widget in ipairs(right_widgets) do
                            table.insert(right_stack, right_widget)
                        end
                        table.insert(widget, RightContainer:new{
                            dimen = row_dimen,
                            HorizontalGroup:new{
                                right_stack,
                                HorizontalSpan:new{ width = pad_right },
                            },
                        })
                    end
                    if self._underline_container[1] then
                        self._underline_container[1]:free()
                    end
                    self._underline_container[1] = VerticalGroup:new{
                        VerticalSpan:new{ width = underline_h },
                        widget,
                    }
                    self.bookinfo_found = true
                    self.init_done = true
                end
                return
            end

            -- filepath set in ListMenuItem:init()
            local filepath = self.filepath
            if not filepath then
                return original_update(self)
            end

            local underline_h = 1 -- matches self.underline_h in ListMenuItem:init()
            local dimen_h = self.height - 2 * underline_h
            local border_size = Size.border.thin
            local cover_v_pad = Screen:scaleBySize(4)  -- top+bottom breathing room
            local cover_zone_w = dimen_h  -- squared, identical to stock list mode
            local max_img = dimen_h - 2 * border_size - 2 * cover_v_pad
            local ratio = Cover.getRatio()
            local cover_w = math.floor(max_img * ratio)

            -- Font sizing identical to listmenu.lua's internal _fontSize closure.
            local function _fontSize(nominal, max_size)
                local scale = library_font.getScale(18)
                local fs = math.floor(nominal * dimen_h * (1 / 64) / scale_by_size * scale + 0.5)
                if max_size then
                    local max_scaled = math.max(1, math.floor(max_size * scale + 0.5))
                    if fs >= max_scaled then return max_scaled end
                end
                return fs
            end

            -- Attempt to get bookinfo (without cover) first to check availability.
            local bookinfo = BookInfoManager:getBookInfo(filepath, false)

            -- If not yet indexed fall back to the original renderer so the
            -- loading hint ("…") is shown and the item queues for extraction.
            if not bookinfo then
                return original_update(self)
            end

            -- Set cover_specs early so that when we fall through to original_update
            -- (below), extraction is queued with our portrait specs rather than the
            -- stock square ones.
            local cover_specs
            if self.do_cover_image then
                cover_specs = {
                    max_cover_w = cover_w,
                    max_cover_h = max_img,
                }
                self.menu.cover_specs = cover_specs
            end

            -- Mirror stock CoverBrowser: if cover hasn't been fetched yet, defer so
            -- the item is added to items_to_update and extraction is queued.
            if self.do_cover_image and not bookinfo.cover_fetched then
                return original_update(self)
            end

            -- Re-fetch with cover only when in cover-image mode and cover exists.
            if self.do_cover_image and bookinfo.has_cover and not bookinfo.ignore_cover
               and not self.menu.no_refresh_covers then
                bookinfo = BookInfoManager:getBookInfo(filepath, true) or bookinfo
            end

            -- Mirror stock: if the cached thumbnail is too small for our specs
            -- (e.g. first extracted in mosaic mode at a smaller size), fall through
            -- so KOReader queues a re-extraction at the correct cover_specs.
            if self.do_cover_image and bookinfo.has_cover and not bookinfo.ignore_cover
               and not self.menu.no_refresh_covers
               and bookinfo.cover_bb
               and BookInfoManager.isCachedCoverInvalid(bookinfo, cover_specs) then
                bookinfo.cover_bb:free()
                return original_update(self)
            end

            local file_deleted = self.entry.dim
            local fgcolor = file_deleted and Blitbuffer.COLOR_DARK_GRAY or nil

            -- ── Cover image (left zone) ──────────────────────────────────────
            local cover_bb_used = false
            local wleft

            if self.do_cover_image then
                if bookinfo.has_cover and not bookinfo.ignore_cover
                   and bookinfo.cover_bb and not self.menu.no_refresh_covers
                then
                    cover_bb_used = true
                    -- Uniform fill: scale from the actual cached-bb dimensions so
                    -- the image covers the entire 2:3 frame, then centre-crop to
                    -- exactly cover_w × max_img.
                    local bb_w     = bookinfo.cover_bb:getWidth()
                    local bb_h     = bookinfo.cover_bb:getHeight()
                    local sf       = math.max(cover_w / bb_w, max_img / bb_h)
                    local scaled_w = math.max(cover_w,  math.ceil(bb_w * sf))
                    local scaled_h = math.max(max_img,  math.ceil(bb_h * sf))
                    local x_off    = math.floor((scaled_w - cover_w) / 2)
                    local y_off    = math.floor((scaled_h - max_img) / 2)
                    local scaled_bb = bookinfo.cover_bb:scale(scaled_w, scaled_h)
                    local fill_bb   = Blitbuffer.new(cover_w, max_img, scaled_bb:getType())
                    fill_bb:blitFrom(scaled_bb, 0, 0, x_off, y_off, cover_w, max_img)
                    scaled_bb:free()
                    local wimage = ImageWidget:new{
                        image        = fill_bb,
                        scale_factor = 1,
                        _free_image  = true,
                    }
                    wimage:_render()
                    local cover_frame = FrameContainer:new{
                        width = cover_w + 2 * border_size,
                        height = max_img + 2 * border_size,
                        margin = 0, padding = 0, bordersize = border_size,
                        dim = file_deleted,
                        CenterContainer:new{
                            dimen = { w = cover_w, h = max_img },
                            wimage,
                        },
                    }
                    wleft = CenterContainer:new{
                        dimen = { w = cover_zone_w, h = dimen_h },
                        cover_frame,
                    }
                    self._cover_frame = cover_frame
                    self.menu._has_cover_images = true
                    self._has_cover_image = true
                else
                    -- No cover or not yet fetched - use unified placeholder generator
                    local final_bb = Cover.genCover(filepath, cover_w, max_img)
                    local wimage = ImageWidget:new{
                        image = final_bb,
                        width = cover_w,
                        height = max_img,
                        _free_image = true,
                    }
                    wimage:_render()
                    local cover_frame = FrameContainer:new{
                        width = cover_w + 2 * border_size,
                        height = max_img + 2 * border_size,
                        margin = 0, padding = 0, bordersize = border_size,
                        dim = file_deleted,
                        CenterContainer:new{
                            dimen = { w = cover_w, h = max_img },
                            wimage,
                        },
                    }
                    wleft = CenterContainer:new{
                        dimen = { w = cover_zone_w, h = dimen_h },
                        cover_frame,
                    }
                    self._cover_frame = cover_frame
                    self.menu._has_cover_images = true
                    self._has_cover_image = true
                end
            end

            -- Free unused cover blitbuffer
            if bookinfo.cover_bb and not cover_bb_used then
                bookinfo.cover_bb:free()
            end

            -- ── Metadata ─────────────────────────────────────────────────────
            local book_info = self.menu.getBookInfo(filepath)
            self.been_opened = book_info.been_opened

            local filename = select(2, util.splitFilePathName(filepath))
            local filename_without_suffix = filemanagerutil.splitFileNameType(filename)
            local has_description = bookinfo.description ~= nil
            self.has_description = has_description

            local title   = (not bookinfo.ignore_meta and bookinfo.title)   or filename_without_suffix
            local authors = (not bookinfo.ignore_meta and bookinfo.authors)
            local series  = (not bookinfo.ignore_meta and bookinfo.series)
            local series_index = (not bookinfo.ignore_meta and bookinfo.series_index)

            title   = title   and BD.auto(title)   or BD.filename(filename_without_suffix)
            if title and #title > 60 then
                title = title:sub(1, 60) .. "…"
            end
            authors = authors and BD.auto(authors)

            local series_str
            if series then
                series = BD.auto(series)
                if series_index then
                    series_str = string.format("#%.4g – %s", series_index, series)
                else
                    series_str = series
                end
            end

            -- ── Progress / right widget ───────────────────────────────────────
            local percent_finished = book_info.percent_finished
            local status = book_info.status
            local pages = book_info.pages or bookinfo.pages
            local is_new = book_status.isNewStatus(status, percent_finished)

            local status_label, progress_str
            if status == "complete" then
                status_label = _("Finished")
                progress_str = "\u{F012C}"  -- MD check
            elseif status == "abandoned" then
                status_label = _("To Be Read")
                progress_str = "\u{F0150}"  -- MD Clock icon
            elseif is_new then
                status_label = _("New")
            elseif percent_finished then
                -- has recorded progress
                status_label = string.format(_("%d%% Read"), math.floor(100 * percent_finished))
            else
                status_label = _("Reading")
            end

            -- ── Book tags (Calibre keywords field from bookinfo DB) ──────────
            -- Only show tags in "list with metadata" mode, not filename-only modes.
            local tags_str
            if not self.do_filename_only
                and not bookinfo.ignore_meta and bookinfo.keywords
                and bookinfo.keywords ~= "" then
                -- Normalize any separator (newline, semicolon, " · ") to ", "
                tags_str = bookinfo.keywords
                    :gsub("%s*[\n;]%s*", ", ")
                    :gsub("%s+·%s+", ", ")
                    :gsub("^,%s*", ""):gsub(",%s*$", "")
            end

            -- ── Layout constants ─────────────────────────────────────────────
            local pad_left  = self.do_cover_image and Screen:scaleBySize(6) or Screen:scaleBySize(10)
            local pad_right = Screen:scaleBySize(10)
            local fs_title   = _fontSize(18, 21)
            local fs_meta    = _fontSize(14, 18)
            local fs_right   = _fontSize(14, 18)
            local text_safe_pad_top = math.max(2, Screen:scaleBySize(4))
            local text_safe_pad_bottom = math.max(2, Screen:scaleBySize(3))
            local content_h = math.max(1, dimen_h - text_safe_pad_top - text_safe_pad_bottom)

            -- Keep text readable but bounded to the usable content height.
            fs_title = math.min(fs_title, math.max(9, math.floor(content_h * 0.45)))
            fs_meta = math.min(fs_meta, math.max(8, math.floor(content_h * 0.34)))
            fs_right = math.min(fs_right, math.max(8, math.floor(content_h * 0.34)))

            local left_offset = self.do_cover_image and (cover_zone_w + pad_left) or pad_left

            -- ── Step 1: compute right-column natural widths ───────────────────
            local status_nat_w, pages_nat_w = 0, 0
            local fs_pages = math.max(7, fs_right - 2)
            local pages_str
            if status_label then
                if progress_str then
                    local icon_probe = TextWidget:new{
                        text    = progress_str,
                        face    = library_font.getFace(fs_right),
                        fgcolor = fgcolor,
                        padding = 0,
                    }
                    local label_probe = TextWidget:new{
                        text    = " " .. status_label,
                        face    = library_font.getFace(fs_right),
                        fgcolor = fgcolor,
                        padding = 0,
                    }
                    status_nat_w = icon_probe:getWidth() + label_probe:getWidth()
                    icon_probe:free()
                    label_probe:free()
                else
                    local status_probe = TextWidget:new{
                        text    = status_label,
                        face    = library_font.getFace(fs_right),
                        fgcolor = fgcolor,
                        padding = 0,
                    }
                    status_nat_w = status_probe:getWidth()
                    status_probe:free()
                end
            end
            if pages and pages > 0 and not self.do_filename_only then
                pages_str = zen_utils.formatPageCount(pages, true)
                local pages_probe = TextWidget:new{
                    text    = pages_str,
                    face    = library_font.getFace(fs_pages),
                    padding = 0,
                }
                pages_nat_w = pages_probe:getWidth()
                pages_probe:free()
            end

            -- Clamp right-column width so oversized fonts do not push content outside row.
            local right_available = math.max(0, self.width - left_offset - 2 * pad_right)
            local max_right_w = math.floor(right_available * 0.45)
            local wright_w = math.max(status_nat_w, pages_nat_w)
            if max_right_w > 0 then
                wright_w = math.min(wright_w, max_right_w)
            end

            -- ── Step 2: build right-column widgets with clamped width ─────────
            local wright_status, wright_pages
            if status_label and wright_w > 0 then
                if progress_str then
                    local icon_w = TextWidget:new{
                        text    = progress_str,
                        face    = library_font.getFace(fs_right),
                        fgcolor = fgcolor,
                        padding = 0,
                    }
                    local label_max_w = math.max(1, wright_w - icon_w:getWidth())
                    local label_w = TextWidget:new{
                        text      = " " .. status_label,
                        face      = library_font.getFace(fs_right),
                        fgcolor   = fgcolor,
                        padding   = 0,
                        max_width = label_max_w,
                    }
                    wright_status = HorizontalGroup:new{
                        icon_w,
                        label_w,
                    }
                else
                    wright_status = TextWidget:new{
                        text      = status_label,
                        face      = library_font.getFace(fs_right),
                        fgcolor   = fgcolor,
                        padding   = 0,
                        max_width = math.max(1, wright_w),
                    }
                end
            end
            if pages_str and wright_w > 0 then
                wright_pages = TextWidget:new{
                    text      = pages_str,
                    face      = library_font.getFace(fs_pages),
                    fgcolor   = Blitbuffer.COLOR_GRAY_3,
                    padding   = 0,
                    max_width = math.max(1, wright_w),
                }
            end

            local main_w = math.max(1, self.width - left_offset - wright_w - 2 * pad_right)

            -- ── Text stack (title / authors / series) ────────────────────────
            local function make_text_line(text, bold_flag)
                return TextBoxWidget:new{
                    text = text,
                    face = bold_flag and library_font.getFace(fs_title) or library_font.getFace(fs_meta),
                    width = main_w,
                    height = content_h,          -- will shrink via height_adjust
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                    alignment = "left",
                    bold = bold_flag or false,
                    fgcolor = fgcolor,
                }
            end

            local wtitle = make_text_line(title, true)

            -- Authors: single line, truncated with ellipsis
            local wauthors
            if authors then
                wauthors = TextWidget:new{
                    text      = authors:gsub("\n", ", "),
                    face      = library_font.getFace(fs_meta),
                    max_width = main_w,
                    fgcolor   = fgcolor,
                    padding   = 0,
                }
            end

            -- Tags: single line under author, left column
            local wtags_left
            if tags_str then
                wtags_left = TextWidget:new{
                    text      = tags_str,
                    face      = library_font.getFace(math.max(7, fs_meta - 2)),
                    max_width = main_w,
                    fgcolor   = Blitbuffer.COLOR_GRAY_3,
                    padding   = 0,
                }
            end

            local wseries
            if series_str then
                wseries = TextWidget:new{
                    text      = series_str,
                    face      = library_font.getFace(fs_meta),
                    max_width = main_w,
                    fgcolor   = fgcolor,
                    padding   = 0,
                }
            end

            -- Fit metadata stack to row height. Keep title visible, then add
            -- optional lines only while there is room.
            local optional_widgets = {}
            if wauthors then table.insert(optional_widgets, wauthors) end
            if wseries then table.insert(optional_widgets, wseries) end
            if wtags_left then table.insert(optional_widgets, wtags_left) end

            local title_min_h = math.max(1, math.floor(content_h * 0.45))
            local optional_budget = math.max(0, content_h - title_min_h)
            local used_optional_h = 0
            local visible_optional = {}

            for _i, w in ipairs(optional_widgets) do
                local h = w:getSize().h
                if used_optional_h + h <= optional_budget then
                    used_optional_h = used_optional_h + h
                    table.insert(visible_optional, w)
                else
                    w:free()
                end
            end

            local title_budget = math.max(1, content_h - used_optional_h)
            wtitle.height = title_budget
            wtitle.height_adjust = true
            wtitle.height_overflow_show_ellipsis = true
            wtitle:free(true)
            wtitle:init()

            local text_stack = VerticalGroup:new{ align = "left" }
            table.insert(text_stack, wtitle)
            for _i, w in ipairs(visible_optional) do
                table.insert(text_stack, w)
            end

            local text_stack_container = VerticalGroup:new{ align = "left" }
            table.insert(text_stack_container, VerticalSpan:new{ width = text_safe_pad_top })
            table.insert(text_stack_container, text_stack)

            local wmain = LeftContainer:new{
                dimen = { w = self.width, h = dimen_h },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = left_offset },
                    LeftContainer:new{
                        dimen = { w = main_w, h = dimen_h },
                        text_stack_container,
                    },
                },
            }

            -- ── Assemble full row ─────────────────────────────────────────────
            local row_dimen = { w = self.width, h = dimen_h }
            local widget = OverlapGroup:new{
                dimen = row_dimen,
                wmain,
            }

            if wleft then
                table.insert(widget, 1, wleft)
            end

            if wright_status or wright_pages then
                if wright_status and wright_pages then
                    local right_h = wright_status:getSize().h + wright_pages:getSize().h
                    if right_h > content_h then
                        wright_pages:free()
                        wright_pages = nil
                    end
                end
                local right_stack = VerticalGroup:new{ align = "right" }
                table.insert(right_stack, VerticalSpan:new{ width = text_safe_pad_top })
                if wright_status then table.insert(right_stack, wright_status) end
                if wright_pages  then table.insert(right_stack, wright_pages)  end
                table.insert(widget, RightContainer:new{
                    dimen = row_dimen,
                    HorizontalGroup:new{
                        right_stack,
                        HorizontalSpan:new{ width = pad_right },
                    },
                })
            end

            -- ── Favorite star overlay (top-right corner, absolute) ─────────
            if self.menu.name ~= "collections"
                and ReadCollection:isFileInCollection(filepath, "favorites") then
                local star_sz = Screen:scaleBySize(22)
                local star_pad = Screen:scaleBySize(3)
                local star_icon = IconWidget:new{
                    icon = "star.empty",
                    width = star_sz,
                    height = star_sz,
                    alpha = true,
                    overlap_align = "right",
                }
                -- overlap_align on the child positions it at the right edge of the parent OverlapGroup.
                table.insert(widget, OverlapGroup:new{
                    dimen = { w = row_dimen.w - star_pad, h = star_sz },
                    allow_mirroring = false,
                    star_icon,
                })
            end

            -- ── Commit to underline container ────────────────────────────────
            if self._underline_container[1] then
                self._underline_container[1]:free()
            end
            self._underline_container[1] = VerticalGroup:new{
                VerticalSpan:new{ width = underline_h },
                widget,
            }

            self.bookinfo_found = true
            self.init_done = true
        end

        -- ── Cover-frame paintTo ───────────────────────────────────────────────
        -- Fill-scaled images overflow their ImageWidget bounds and can paint
        -- over the FrameContainer border (which KOReader draws *before* child
        -- content).  We always redraw the border on top after the base paint so
        -- it is never obscured.  Rounded corners build on top of that.
        local orig_paintTo = ListMenuItem.paintTo
        if orig_paintTo then
            function ListMenuItem:paintTo(bb, x, y)
                orig_paintTo(self, bb, x, y)
                if not self._cover_frame then return end
                local target = self._cover_frame
                if not (target.dimen
                    and target.dimen.x and target.dimen.y
                    and target.dimen.w and target.dimen.h
                    and target.dimen.w > 0 and target.dimen.h > 0)
                then
                    return
                end
                local tx, ty = target.dimen.x, target.dimen.y
                local tw, th = target.dimen.w, target.dimen.h
                local bsz    = math.max(1, target.bordersize or 0)

                -- Always redraw straight border on top (fixes fill-overflow masking).
                local bc = Blitbuffer.COLOR_BLACK
                bb:paintRect(tx,            ty,            tw,  bsz, bc)
                bb:paintRect(tx,            ty + th - bsz, tw,  bsz, bc)
                bb:paintRect(tx,            ty,            bsz, th,  bc)
                bb:paintRect(tx + tw - bsz, ty,            bsz, th,  bc)

                local plug = _plugin_ref or rawget(_G, "__ZEN_UI_PLUGIN")
                if plug
                    and type(plug.config) == "table"
                    and type(plug.config.features) == "table"
                    and plug.config.features.browser_cover_rounded_corners == true
                then
                    -- Corner masks white-out the sharp corners (content + redrawn border).
                    paintCornerMasks(bb, tx, ty, tw, th, corner_radius)
                    -- Then draw the rounded arc border over the masked area.
                    paintCornerBorderArcs(bb, tx, ty, tw, th, corner_radius, bsz, Blitbuffer.COLOR_BLACK)
                end
            end
        end
        ListMenuItem._zen_bll_patched = true
    end

    -- ── Remove list separator lines ────────────────────────────────────────
    -- CoverMenu.updateItems calls _updateItemsBuildUI which inserts shared
    -- LineWidgets before the first item and after each item.
    -- We always strip the first and last LineWidgets (top/bottom borders).
    -- When hide_list_borders is enabled we remove ALL LineWidgets.
    -- Patched on the CoverMenu prototype (not _updateItemsBuildUI) so that
    -- get_upvalue() chains used by other patches remain intact.

    local function isHideAllBorders()
        local p = _plugin_ref or rawget(_G, "__ZEN_UI_PLUGIN")
        return p
            and type(p.config) == "table"
            and type(p.config.browser_list_item_layout) == "table"
            and p.config.browser_list_item_layout.hide_list_borders == true
    end

    -- Strip LineWidgets from item_group.  Always removes first/last;
    -- removes all when hide_list_borders config is enabled.
    local function stripListBorders(menu)
        local ig = menu.item_group
        if not ig or #ig == 0 then return end

        if isHideAllBorders() then
            for i = #ig, 1, -1 do
                if ig[i] and ig[i].background then
                    table.remove(ig, i)
                end
            end
        else
            -- Remove only the first and last LineWidgets (top/bottom borders)
            if ig[#ig] and ig[#ig].background then
                table.remove(ig, #ig)
            end
            if ig[1] and ig[1].background then
                table.remove(ig, 1)
            end
        end
    end

    -- Required here so the setupLayout closure can reference it for dynamic dispatch.
    local FileChooser = require("ui/widget/filechooser")

    local ok_cm, CoverMenu = pcall(require, "covermenu")
    if ok_cm and CoverMenu and not CoverMenu._zen_strip_list_borders_patched then
        CoverMenu._zen_strip_list_borders_patched = true
        local orig_cm_updateItems = CoverMenu.updateItems
        function CoverMenu:updateItems(...)
            orig_cm_updateItems(self, ...)
            stripListBorders(self)
        end
        -- No class-level FileChooser.updateItems wrap: CoverBrowser replaces it on
        -- every mode switch (CoverMenu.updateItems <-> _FileChooser_updateItems_orig),
        -- so any captured static reference goes stale. Dynamic dispatch (below) handles it.
    end

    -- Apply immediately: at plugin init time listmenu may already be loaded by CoverBrowser.
    -- This ensures BLL is active before History/Collections views are first shown,
    -- and avoids the fragile FileManager.setupLayout timing race.
    patchListMenu()

    -- Hook FileManager:setupLayout as a safety-net fallback (e.g., listmenu loads later
    -- or we return from the reader and layout is re-run). patchListMenu() is idempotent.
    local FileManager = require("apps/filemanager/filemanager")
    local orig_fm_setupLayout = FileManager.setupLayout

    FileManager.setupLayout = function(self)
        orig_fm_setupLayout(self)
        patchListMenu()
        -- Set (or re-set) an instance wrapper that calls FileChooser.updateItems at
        -- dispatch time rather than capturing it at wrap time.  CoverBrowser swaps
        -- FileChooser.updateItems on every classic<->cover mode toggle, so a static
        -- capture would stay stale and call CoverMenu.updateItems (which expects
        -- self:_updateItemsBuildUI()) on a classic-mode instance where that method
        -- is nil, crashing KOReader.
        local fc = self.file_chooser
        if fc and fc.updateItems then
            if fc._zen_strip_list_borders_fn ~= fc.updateItems then
                local function zen_fc_updateItems(s, ...)
                    FileChooser.updateItems(s, ...)
                    stripListBorders(s)
                end
                fc._zen_strip_list_borders_fn = zen_fc_updateItems
                fc.updateItems = zen_fc_updateItems
            end
            -- setupLayout already called updateItems before our wrapper was installed,
            -- so strip the current item_group now (covers return-from-reader).
            local UIManager = require("ui/uimanager")
            stripListBorders(fc)
            UIManager:setDirty(fc, "ui")
        end
    end

    -- Restart fix: FileManager may already be on screen before the plugin loaded.
    -- Strip borders from the existing item_group immediately.
    local fm = FileManager.instance
    if fm and fm.file_chooser then
        local UIManager = require("ui/uimanager")
        stripListBorders(fm.file_chooser)
        UIManager:setDirty(fm.file_chooser, "ui")
    end
end

return apply_browser_list_item_layout

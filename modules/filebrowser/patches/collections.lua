local logger = require("logger")
logger.warn("zen-coll: module loaded")

local function apply_collections()
    logger.warn("zen-coll: apply_collections() called")

    local FileManagerCollection = require("apps/filemanager/filemanagercollection")
    local Menu = require("ui/widget/menu")

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then
        return
    end

    local function is_enabled()
        local features = zen_plugin.config and zen_plugin.config.features
        return type(features) == "table" and features.collections == true
    end

    local function should_match_statusbar_height()
        local features = zen_plugin.config and zen_plugin.config.features
        if type(features) ~= "table" or features.status_bar ~= true then
            return false
        end
        local sb_cfg = type(zen_plugin.config.status_bar) == "table"
            and zen_plugin.config.status_bar or {}
        local hide = sb_cfg.hide_browser_bar
        return hide == true or hide == nil
    end

    ---------------------------------------------------------------------------
    -- Utility: walk upvalue chain to find a named upvalue
    ---------------------------------------------------------------------------
    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then return nil end
        for i = 1, 64 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then break end
            if upname == name then return value end
        end
    end

    ---------------------------------------------------------------------------
    -- Display mode setup: match the filemanager display mode setting
    -- Returns the mode type ("mosaic", "list") or "classic" / false
    ---------------------------------------------------------------------------
    local function setup_display_mode(menu)
        local BookInfoManager = require("bookinfomanager")
        local display_mode = BookInfoManager:getSetting("filemanager_display_mode")
        menu._zen_coll_list = true

        if not display_mode then
            return "classic"
        end

        local ok_cm, CoverMenu = pcall(require, "covermenu")
        if not ok_cm then return false end

        local display_mode_type = display_mode:gsub("_.*", "") -- "mosaic" or "list"

        menu.updateItems  = CoverMenu.updateItems
        menu.onCloseWidget = CoverMenu.onCloseWidget

        menu.nb_cols_portrait  = BookInfoManager:getSetting("nb_cols_portrait")  or 3
        menu.nb_rows_portrait  = BookInfoManager:getSetting("nb_rows_portrait")  or 3
        menu.nb_cols_landscape = BookInfoManager:getSetting("nb_cols_landscape") or 4
        menu.nb_rows_landscape = BookInfoManager:getSetting("nb_rows_landscape") or 2
        menu.files_per_page    = BookInfoManager:getSetting("files_per_page")
        menu.display_mode_type = display_mode_type

        if display_mode_type == "mosaic" then
            local ok_mm, MosaicMenu = pcall(require, "mosaicmenu")
            if not ok_mm then return false end
            menu._recalculateDimen    = MosaicMenu._recalculateDimen
            menu._updateItemsBuildUI  = MosaicMenu._updateItemsBuildUI
            menu._do_cover_images     = display_mode ~= "mosaic_text"
            menu._do_center_partial_rows = false
            menu._do_hint_opened      = false
        elseif display_mode_type == "list" then
            local ok_lm, ListMenu = pcall(require, "listmenu")
            if not ok_lm then return false end
            menu._recalculateDimen    = ListMenu._recalculateDimen
            menu._updateItemsBuildUI  = ListMenu._updateItemsBuildUI
            menu._do_cover_images     = display_mode ~= "list_only_meta"
            menu._do_filename_only    = display_mode == "list_image_filename"
        end

        -- Stubs: prevent CoverMenu from crashing on BookList-only APIs
        if not menu.getBookInfo then
            menu.getBookInfo = function() return {} end
        end
        if not menu.resetBookInfoCache then
            menu.resetBookInfoCache = function() end
        end

        return display_mode_type
    end

    ---------------------------------------------------------------------------
    -- Hook MosaicMenuItem.update once for collection gallery covers
    ---------------------------------------------------------------------------
    local _mosaic_item_patched = false

    local function patch_mosaic_item()
        if _mosaic_item_patched then return end

        local ok, MosaicMenu = pcall(require, "mosaicmenu")
        if not ok then return end
        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end
        _mosaic_item_patched = true

        local ReadCollection  = require("readcollection")
        local BookInfoManager = require("bookinfomanager")
        local util            = require("util")

        -- Ensure onFocus keeps underlines hidden for all mosaic items.
        -- browser_hide_underline patches this via userpatch, but if the
        -- userpatch callback hasn't fired yet (or silently failed), the
        -- original onFocus sets COLOR_BLACK on the focused item — which
        -- is the exact symptom when navigating back to collections list.
        local Blitbuffer_uc = require("ffi/blitbuffer")
        if not MosaicMenuItem._zen_coll_focus_patched then
            MosaicMenuItem._zen_coll_focus_patched = true
            function MosaicMenuItem:onFocus()
                if self._underline_container then
                    self._underline_container.color = Blitbuffer_uc.COLOR_WHITE
                end
                return true
            end
        end

        local orig_update = MosaicMenuItem.update
        function MosaicMenuItem:update(...)
            if not (self.menu and self.menu._zen_coll_list
                    and self.entry and self.entry.name) then
                return orig_update(self, ...)
            end

            -- Mark as directory to keep CoverMenu from scheduling extraction
            self.is_directory = true

            local coll_name = self.entry.name
            local coll = ReadCollection.coll[coll_name]
            local book_count = coll and util.tableSize(coll) or 0

            -- Gather first 4 covers sorted by order
            local covers = {}
            if coll then
                local sorted = {}
                for _, item in pairs(coll) do
                    table.insert(sorted, item)
                end
                table.sort(sorted, function(a, b)
                    return (a.order or 0) < (b.order or 0)
                end)
                for i = 1, math.min(#sorted, 4) do
                    local bi = BookInfoManager:getBookInfo(sorted[i].file, true)
                    if bi and bi.cover_bb and bi.has_cover
                            and bi.cover_fetched and not bi.ignore_cover then
                        table.insert(covers, {
                            data = bi.cover_bb:copy(),
                            w    = bi.cover_w,
                            h    = bi.cover_h,
                        })
                    end
                end
            end

            -- Render via browser_folder_cover's _setFolderCover when available
            if self._setFolderCover then
                self:_setFolderCover {
                    gallery    = covers,
                    book_count = book_count,
                }
                return
            end

            -- Fallback: build gallery widget inline
            local Blitbuffer       = require("ffi/blitbuffer")
            local CenterContainer  = require("ui/widget/container/centercontainer")
            local FrameContainer   = require("ui/widget/container/framecontainer")
            local HorizontalGroup  = require("ui/widget/horizontalgroup")
            local ImageWidget      = require("ui/widget/imagewidget")
            local LineWidget       = require("ui/widget/linewidget")
            local OverlapGroup     = require("ui/widget/overlapgroup")
            local Size             = require("ui/size")
            local VerticalGroup    = require("ui/widget/verticalgroup")
            local VerticalSpan     = require("ui/widget/verticalspan")

            local border = Size.border.thin
            local max_w  = self.width  - 2 * border
            local bh     = self.height - 2 * border
            local portrait_w, portrait_h
            if bh * 2 <= max_w * 3 then
                portrait_h = bh
                portrait_w = math.floor(bh * 2 / 3)
            else
                portrait_w = max_w
                portrait_h = math.min(math.floor(max_w * 3 / 2), bh)
            end

            local sep     = 1
            local half_w  = math.floor((portrait_w - sep) / 2)
            local half_w2 = portrait_w - sep - half_w
            local half_h  = math.floor((portrait_h - sep) / 2)
            local half_h2 = portrait_h - sep - half_h
            local cell_dims = {
                { w = half_w,  h = half_h  },
                { w = half_w2, h = half_h  },
                { w = half_w,  h = half_h2 },
                { w = half_w2, h = half_h2 },
            }
            local cells = {}
            for i = 1, 4 do
                local c  = covers[i]
                local cd = cell_dims[i]
                if c then
                    cells[i] = CenterContainer:new{
                        dimen = { w = cd.w, h = cd.h },
                        ImageWidget:new{ image = c.data, width = cd.w, height = cd.h },
                    }
                else
                    cells[i] = CenterContainer:new{
                        dimen = { w = cd.w, h = cd.h },
                        VerticalSpan:new{ width = 1 },
                    }
                end
            end
            local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }
            local image_widget = FrameContainer:new{
                padding = 0, bordersize = border,
                width = dimen.w, height = dimen.h,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                CenterContainer:new{
                    dimen = { w = portrait_w, h = portrait_h },
                    VerticalGroup:new{
                        HorizontalGroup:new{
                            cells[1],
                            LineWidget:new{
                                background = Blitbuffer.COLOR_WHITE,
                                dimen = { w = sep, h = half_h },
                            },
                            cells[2],
                        },
                        LineWidget:new{
                            background = Blitbuffer.COLOR_WHITE,
                            dimen = { w = portrait_w, h = sep },
                        },
                        HorizontalGroup:new{
                            cells[3],
                            LineWidget:new{
                                background = Blitbuffer.COLOR_WHITE,
                                dimen = { w = sep, h = half_h2 },
                            },
                            cells[4],
                        },
                    },
                },
                overlap_align = "center",
            }
            local centered_top = math.floor((self.height - dimen.h) / 2)
            local widget = OverlapGroup:new{
                dimen = { w = self.width, h = self.height },
                VerticalGroup:new{
                    VerticalSpan:new{ width = centered_top },
                    CenterContainer:new{
                        dimen = { w = self.width, h = dimen.h },
                        image_widget,
                    },
                },
            }
            if self._underline_container[1] then
                self._underline_container[1]:free()
            end
            self._underline_container[1] = widget
        end
    end

    ---------------------------------------------------------------------------
    -- Hook ListMenuItem.update once for collection list-mode rendering
    -- (mirrors the visual style of browser_list_item_layout)
    ---------------------------------------------------------------------------
    local _list_item_patched = false

    local function patch_list_item()
        if _list_item_patched then return end

        local ok, ListMenu = pcall(require, "listmenu")
        if not ok then return end
        local ListMenuItem = get_upvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
        if not ListMenuItem then return end
        _list_item_patched = true

        local BD              = require("ui/bidi")
        local Blitbuffer      = require("ffi/blitbuffer")
        local BookInfoManager = require("bookinfomanager")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local Device          = require("device")
        local Font            = require("ui/font")
        local FrameContainer  = require("ui/widget/container/framecontainer")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan  = require("ui/widget/horizontalspan")
        local ImageWidget     = require("ui/widget/imagewidget")
        local LeftContainer   = require("ui/widget/container/leftcontainer")
        local LineWidget      = require("ui/widget/linewidget")
        local OverlapGroup    = require("ui/widget/overlapgroup")
        local ReadCollection  = require("readcollection")
        local RightContainer  = require("ui/widget/container/rightcontainer")
        local Size            = require("ui/size")
        local TextBoxWidget   = require("ui/widget/textboxwidget")
        local TextWidget      = require("ui/widget/textwidget")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local VerticalSpan    = require("ui/widget/verticalspan")
        local util            = require("util")

        local Screen = Device.screen
        local scale_by_size = Screen:scaleBySize(1000000) * (1 / 1000000)

        local orig_list_update = ListMenuItem.update

        function ListMenuItem:update(...)
            if not (self.menu and self.menu._zen_coll_list
                    and self.entry and self.entry.name) then
                return orig_list_update(self, ...)
            end

            self.is_directory = true

            local coll_name  = self.entry.name
            local coll       = ReadCollection.coll[coll_name]
            local book_count = coll and util.tableSize(coll) or 0
            local display_name = coll_name
            if coll_name == ReadCollection.default_collection_name then
                local _ = require("gettext")
                display_name = _("Favorites")
            end

            local underline_h  = 1
            local dimen_h      = self.height - 2 * underline_h
            local border_size  = Size.border.thin
            local cover_zone_w = dimen_h
            local max_img      = dimen_h - 2 * border_size
            local cover_w      = math.floor(max_img * 2 / 3)

            local function _fontSize(nominal, max_size)
                local fs = math.floor(nominal * dimen_h * (1 / 64) / scale_by_size)
                if max_size and fs >= max_size then return max_size end
                return fs
            end

            -- ── Cover thumbnail ──────────────────────────────────────────
            local wleft
            if self.do_cover_image then
                local gallery_mode = BookInfoManager:getSetting("folder_gallery_mode")
                local max_covers = gallery_mode and 4 or 1
                local covers = {}
                if coll then
                    local sorted = {}
                    for _, item in pairs(coll) do
                        table.insert(sorted, item)
                    end
                    table.sort(sorted, function(a, b)
                        return (a.order or 0) < (b.order or 0)
                    end)
                    for i = 1, #sorted do
                        local bi = BookInfoManager:getBookInfo(sorted[i].file, true)
                        if bi and bi.cover_bb and bi.has_cover
                                and bi.cover_fetched and not bi.ignore_cover then
                            table.insert(covers, { data = bi.cover_bb:copy() })
                            if #covers >= max_covers then break end
                        end
                    end
                end

                local cover_frame
                if gallery_mode then
                    -- 2×2 gallery mosaic
                    local gall_w = cover_w
                    local gall_h = max_img
                    if #covers > 0 then
                        local sep     = 1
                        local half_w  = math.floor((gall_w - sep) / 2)
                        local half_w2 = gall_w - sep - half_w
                        local half_h  = math.floor((gall_h - sep) / 2)
                        local half_h2 = gall_h - sep - half_h
                        local cell_dims = {
                            { w = half_w,  h = half_h  },
                            { w = half_w2, h = half_h  },
                            { w = half_w,  h = half_h2 },
                            { w = half_w2, h = half_h2 },
                        }
                        local cells = {}
                        for i = 1, 4 do
                            local c  = covers[i]
                            local cd = cell_dims[i]
                            if c then
                                cells[i] = CenterContainer:new{
                                    dimen = { w = cd.w, h = cd.h },
                                    ImageWidget:new{
                                        image  = c.data,
                                        width  = cd.w,
                                        height = cd.h,
                                    },
                                }
                            else
                                cells[i] = CenterContainer:new{
                                    dimen = { w = cd.w, h = cd.h },
                                    VerticalSpan:new{ width = 1 },
                                }
                            end
                        end
                        cover_frame = FrameContainer:new{
                            width = gall_w + 2 * border_size,
                            height = gall_h + 2 * border_size,
                            margin = 0, padding = 0, bordersize = border_size,
                            background = Blitbuffer.COLOR_LIGHT_GRAY,
                            CenterContainer:new{
                                dimen = { w = gall_w, h = gall_h },
                                VerticalGroup:new{
                                    HorizontalGroup:new{
                                        cells[1],
                                        LineWidget:new{
                                            background = Blitbuffer.COLOR_WHITE,
                                            dimen = { w = sep, h = half_h },
                                        },
                                        cells[2],
                                    },
                                    LineWidget:new{
                                        background = Blitbuffer.COLOR_WHITE,
                                        dimen = { w = gall_w, h = sep },
                                    },
                                    HorizontalGroup:new{
                                        cells[3],
                                        LineWidget:new{
                                            background = Blitbuffer.COLOR_WHITE,
                                            dimen = { w = sep, h = half_h2 },
                                        },
                                        cells[4],
                                    },
                                },
                            },
                        }
                        self.menu._has_cover_images = true
                        self._has_cover_image = true
                    else
                        -- Empty gallery placeholder
                        cover_frame = FrameContainer:new{
                            width = gall_w + 2 * border_size,
                            height = gall_h + 2 * border_size,
                            margin = 0, padding = 0, bordersize = border_size,
                            background = Blitbuffer.COLOR_LIGHT_GRAY,
                            CenterContainer:new{
                                dimen = { w = gall_w, h = gall_h },
                                VerticalSpan:new{ width = 1 },
                            },
                        }
                    end
                elseif #covers > 0 then
                    -- Single cover (first book)
                    local bb     = covers[1].data
                    local bb_w   = bb:getWidth()
                    local bb_h   = bb:getHeight()
                    local sf     = math.max(cover_w / bb_w, max_img / bb_h)
                    local scaled_w = math.max(cover_w,  math.ceil(bb_w * sf))
                    local scaled_h = math.max(max_img, math.ceil(bb_h * sf))
                    local x_off  = math.floor((scaled_w - cover_w) / 2)
                    local y_off  = math.floor((scaled_h - max_img) / 2)
                    local scaled_bb = bb:scale(scaled_w, scaled_h)
                    local fill_bb   = Blitbuffer.new(cover_w, max_img,
                                                     scaled_bb:getType())
                    fill_bb:blitFrom(scaled_bb, 0, 0,
                                     x_off, y_off, cover_w, max_img)
                    scaled_bb:free()
                    bb:free()
                    local wimage = ImageWidget:new{
                        image        = fill_bb,
                        scale_factor = 1,
                        _free_image  = true,
                    }
                    wimage:_render()
                    cover_frame = FrameContainer:new{
                        width = cover_w + 2 * border_size,
                        height = max_img + 2 * border_size,
                        margin = 0, padding = 0, bordersize = border_size,
                        CenterContainer:new{
                            dimen = { w = cover_w, h = max_img },
                            wimage,
                        },
                    }
                    self.menu._has_cover_images = true
                    self._has_cover_image = true
                else
                    -- Empty placeholder
                    cover_frame = FrameContainer:new{
                        width = cover_w + 2 * border_size,
                        height = max_img + 2 * border_size,
                        margin = 0, padding = 0, bordersize = border_size,
                        background = Blitbuffer.COLOR_LIGHT_GRAY,
                        CenterContainer:new{
                            dimen = { w = cover_w, h = max_img },
                            VerticalSpan:new{ width = 1 },
                        },
                    }
                end
                wleft = CenterContainer:new{
                    dimen = { w = cover_zone_w, h = dimen_h },
                    cover_frame,
                }
                self._cover_frame = cover_frame
            end

            -- ── Layout constants (match browser_list_item_layout) ────────
            local pad_left  = self.do_cover_image
                              and Screen:scaleBySize(6) or Screen:scaleBySize(10)
            local pad_right = Screen:scaleBySize(10)
            local fs_title  = _fontSize(18, 21)
            local fs_meta   = _fontSize(14, 18)
            local left_offset = self.do_cover_image
                                and (cover_zone_w + pad_left) or pad_left

            -- ── Right widget: book count ─────────────────────────────────
            local count_str  = tostring(book_count) .. " " .. (book_count == 1 and "book" or "books")
            local wright_status = TextWidget:new{
                text    = count_str,
                face    = Font:getFace("cfont", fs_meta),
                fgcolor = Blitbuffer.COLOR_GRAY_3,
                padding = 0,
            }
            local wright_w = wright_status:getWidth()

            -- ── Main text area ───────────────────────────────────────────
            local main_w = math.max(1,
                self.width - left_offset - wright_w - 2 * pad_right)

            local wtitle = TextBoxWidget:new{
                text      = BD.auto(display_name),
                face      = Font:getFace("cfont", fs_title),
                width     = main_w,
                height    = dimen_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
                alignment = "left",
                bold      = true,
            }

            local wmain = LeftContainer:new{
                dimen = { w = self.width, h = dimen_h },
                HorizontalGroup:new{
                    HorizontalSpan:new{ width = left_offset },
                    LeftContainer:new{
                        dimen = { w = main_w, h = dimen_h },
                        wtitle,
                    },
                },
            }

            -- ── Assemble row ─────────────────────────────────────────────
            local row_dimen = { w = self.width, h = dimen_h }
            local widget = OverlapGroup:new{
                dimen = row_dimen,
                wmain,
            }
            if wleft then
                table.insert(widget, 1, wleft)
            end
            table.insert(widget, RightContainer:new{
                dimen = row_dimen,
                HorizontalGroup:new{
                    wright_status,
                    HorizontalSpan:new{ width = pad_right },
                },
            })

            -- ── Commit to underline container ────────────────────────────
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
    end

    ---------------------------------------------------------------------------
    -- Context menus
    ---------------------------------------------------------------------------

    -- Build a cover header widget for a collection (gallery of up to 4 covers
    -- with collection name + book count beside it — same aesthetic as the
    -- folder header in context_menu.lua).
    local function build_coll_cover_header(coll_name, book_count)
        local BookInfoManager  = require("bookinfomanager")
        local Blitbuffer       = require("ffi/blitbuffer")
        local CenterContainer  = require("ui/widget/container/centercontainer")
        local Device           = require("device")
        local Font             = require("ui/font")
        local FrameContainer   = require("ui/widget/container/framecontainer")
        local Geom             = require("ui/geometry")
        local HorizontalGroup  = require("ui/widget/horizontalgroup")
        local HorizontalSpan   = require("ui/widget/horizontalspan")
        local ImageWidget      = require("ui/widget/imagewidget")
        local LeftContainer    = require("ui/widget/container/leftcontainer")
        local LineWidget       = require("ui/widget/linewidget")
        local ReadCollection   = require("readcollection")
        local Size             = require("ui/size")
        local TextWidget       = require("ui/widget/textwidget")
        local VerticalGroup    = require("ui/widget/verticalgroup")
        local VerticalSpan     = require("ui/widget/verticalspan")
        local util             = require("util")
        local _                = require("gettext")

        local Screen = Device.screen
        local border = Size.border.thin
        local gap    = Screen:scaleBySize(8)
        local dlg_w  = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
        local avail_w = dlg_w - 2 * (Size.border.window + Size.padding.button)
                              - 2 * (Size.padding.default + Size.margin.default)
        local cover_max_w = Screen:scaleBySize(90)
        local cover_max_h = Screen:scaleBySize(140)

        local function apply_rounded_corners(frame_widget, bsz)
            local plug = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            if not (plug
                and type(plug.config) == "table"
                and type(plug.config.features) == "table"
                and plug.config.features.browser_cover_rounded_corners == true)
            then
                return
            end
            local r       = Screen:scaleBySize(6)
            local r_inner = r - bsz
            local orig_pt = frame_widget.paintTo
            frame_widget.paintTo = function(self, bb, x, y)
                orig_pt(self, bb, x, y)
                if not (self.dimen and self.dimen.x) then return end
                local tx, ty = self.dimen.x, self.dimen.y
                local tw, th = self.dimen.w, self.dimen.h
                local wh  = Blitbuffer.COLOR_WHITE
                local blk = Blitbuffer.COLOR_BLACK
                for j = 0, r - 1 do
                    local inner = math.sqrt(r * r - (r - j) * (r - j))
                    local cut   = math.ceil(r - inner)
                    if cut > 0 then
                        bb:paintRect(tx,            ty + j,           cut, 1, wh)
                        bb:paintRect(tx + tw - cut, ty + j,           cut, 1, wh)
                        bb:paintRect(tx,            ty + th - 1 - j,  cut, 1, wh)
                        bb:paintRect(tx + tw - cut, ty + th - 1 - j,  cut, 1, wh)
                    end
                end
                for j = 0, r - 1 do
                    for c = 0, r - 1 do
                        local dx   = r - c - 0.5
                        local dy   = r - j - 0.5
                        local dist = math.sqrt(dx * dx + dy * dy)
                        if dist >= r_inner and dist <= r then
                            bb:paintRect(tx + c,          ty + j,           1, 1, blk)
                            bb:paintRect(tx + tw - 1 - c, ty + j,           1, 1, blk)
                            bb:paintRect(tx + c,          ty + th - 1 - j,  1, 1, blk)
                            bb:paintRect(tx + tw - 1 - c, ty + th - 1 - j,  1, 1, blk)
                        end
                    end
                end
            end
        end

        -- Collect covers from the collection
        local gallery_mode = BookInfoManager:getSetting("folder_gallery_mode")
        local max_covers = gallery_mode and 4 or 1
        local coll = ReadCollection.coll[coll_name]
        local covers = {}
        if coll then
            local sorted = {}
            for _, it in pairs(coll) do table.insert(sorted, it) end
            table.sort(sorted, function(a, b) return (a.order or 0) < (b.order or 0) end)
            for i = 1, #sorted do
                local bi = BookInfoManager:getBookInfo(sorted[i].file, true)
                if bi and bi.has_cover and bi.cover_bb and not bi.ignore_cover then
                    table.insert(covers, { data = bi.cover_bb:copy() })
                    if #covers >= max_covers then break end
                end
            end
        end

        local cover_widget
        if gallery_mode and #covers > 0 then
            -- 2×2 gallery mosaic
            local sep     = 1
            local half_w  = math.floor((cover_max_w - sep) / 2)
            local half_w2 = cover_max_w - sep - half_w
            local half_h  = math.floor((cover_max_h - sep) / 2)
            local half_h2 = cover_max_h - sep - half_h
            local cell_dims = {
                { w = half_w,  h = half_h  },
                { w = half_w2, h = half_h  },
                { w = half_w,  h = half_h2 },
                { w = half_w2, h = half_h2 },
            }
            local cells = {}
            for i = 1, 4 do
                local c  = covers[i]
                local cd = cell_dims[i]
                if c then
                    cells[i] = CenterContainer:new{
                        dimen = Geom:new{ w = cd.w, h = cd.h },
                        ImageWidget:new{
                            image            = c.data,
                            image_disposable = true,
                            width            = cd.w,
                            height           = cd.h,
                        },
                    }
                else
                    cells[i] = CenterContainer:new{
                        dimen = Geom:new{ w = cd.w, h = cd.h },
                        VerticalSpan:new{ width = 1 },
                    }
                end
            end
            cover_widget = FrameContainer:new{
                padding    = 0,
                bordersize = border,
                width      = cover_max_w + 2 * border,
                height     = cover_max_h + 2 * border,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                CenterContainer:new{
                    dimen = Geom:new{ w = cover_max_w, h = cover_max_h },
                    VerticalGroup:new{
                        HorizontalGroup:new{
                            cells[1],
                            LineWidget:new{
                                background = Blitbuffer.COLOR_WHITE,
                                dimen = Geom:new{ w = sep, h = half_h },
                            },
                            cells[2],
                        },
                        LineWidget:new{
                            background = Blitbuffer.COLOR_WHITE,
                            dimen = Geom:new{ w = cover_max_w, h = sep },
                        },
                        HorizontalGroup:new{
                            cells[3],
                            LineWidget:new{
                                background = Blitbuffer.COLOR_WHITE,
                                dimen = Geom:new{ w = sep, h = half_h2 },
                            },
                            cells[4],
                        },
                    },
                },
            }
        elseif not gallery_mode and #covers > 0 then
            -- Single cover (first book)
            local bb = covers[1].data
            local src_w = bb:getWidth()
            local src_h = bb:getHeight()
            local sf    = math.min(cover_max_w / src_w, cover_max_h / src_h)
            local img_w = math.floor(src_w * sf)
            local img_h = math.floor(src_h * sf)
            cover_widget = FrameContainer:new{
                padding    = 0,
                bordersize = border,
                width      = cover_max_w + 2 * border,
                height     = cover_max_h + 2 * border,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                CenterContainer:new{
                    dimen = Geom:new{ w = cover_max_w, h = cover_max_h },
                    ImageWidget:new{
                        image            = bb,
                        image_disposable = true,
                        width            = img_w,
                        height           = img_h,
                    },
                },
            }
        else
            -- Placeholder (empty collection) — matches browser_folder_cover blank
            cover_widget = FrameContainer:new{
                padding    = 0,
                bordersize = border,
                width      = cover_max_w + 2 * border,
                height     = cover_max_h + 2 * border,
                background = Blitbuffer.COLOR_LIGHT_GRAY,
                CenterContainer:new{
                    dimen = Geom:new{ w = cover_max_w, h = cover_max_h },
                    VerticalSpan:new{ width = 1 },
                },
            }
        end

        apply_rounded_corners(cover_widget, border)

        -- Text column: collection name + book count
        local framed_h   = cover_max_h + 2 * border
        local text_col_w = math.max(avail_w - cover_max_w - 2 * border - gap,
                                    Screen:scaleBySize(60))
        local vstack = VerticalGroup:new{ align = "left" }
        table.insert(vstack, TextWidget:new{
            text      = coll_name,
            face      = Font:getFace("cfont", 20),
            bold      = true,
            max_width = text_col_w,
        })
        local count_str = book_count == 1
            and "1 " .. _("book")
            or  tostring(book_count) .. " " .. _("books")
        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
        table.insert(vstack, TextWidget:new{
            text      = count_str,
            face      = Font:getFace("cfont", 17),
            max_width = text_col_w,
        })

        return LeftContainer:new{
            dimen = Geom:new{ w = avail_w, h = framed_h },
            HorizontalGroup:new{
                align = "top",
                cover_widget,
                HorizontalSpan:new{ width = gap },
                vstack,
            },
        }
    end

    local function show_coll_item_menu(fm_coll, item, coll_list)
        if not item then return false end
        local ReadCollection = require("readcollection")
        local ButtonDialog   = require("ui/widget/buttondialog")
        local UIManager_cm   = require("ui/uimanager")
        local util           = require("util")
        local _              = require("gettext")

        local coll_name    = item.name
        local is_favorites = coll_name == ReadCollection.default_collection_name
        local coll         = ReadCollection.coll[coll_name]
        local book_count   = coll and util.tableSize(coll) or 0
        local button_dialog

        local function close_dialog()
            UIManager_cm:close(button_dialog)
        end

        -- Cover header
        local cover_header = build_coll_cover_header(coll_name, book_count)

        -- Sort submenu
        local SORT_OPTIONS = {
            { key = "title",    text = "\u{F031}  " .. _("Title")         },
            { key = "authors",  text = "\u{F007}  " .. _("Authors")       },
            { key = "series",   text = "\u{F0CB}  " .. _("Series")        },
            { key = "access",   text = "\u{F073}  " .. _("Recently read") },
            { key = "keywords", text = "\u{F02C}  " .. _("Keywords")      },
        }

        local function showSortSubmenu()
            close_dialog()
            local sort_dialog
            local sort_buttons = {}
            local coll_settings = ReadCollection.coll_settings[coll_name]
            local current = coll_settings and coll_settings.collate

            for _, opt in ipairs(SORT_OPTIONS) do
                local is_active = current == opt.key
                table.insert(sort_buttons, {{
                    text     = opt.text .. (is_active and "  \u{2713}" or ""),
                    align    = "left",
                    enabled  = not is_active,
                    callback = function()
                        UIManager_cm:close(sort_dialog)
                        if coll_settings then
                            coll_settings.collate = opt.key
                            coll_settings.collate_reverse = nil
                        end
                    end,
                }})
            end
            -- Manual (default ordering)
            local manual_active = current == nil
            table.insert(sort_buttons, {{
                text     = "\u{F0C9}  " .. _("Manual") .. (manual_active and "  \u{2713}" or ""),
                align    = "left",
                enabled  = not manual_active,
                callback = function()
                    UIManager_cm:close(sort_dialog)
                    if coll_settings then
                        coll_settings.collate = nil
                        coll_settings.collate_reverse = nil
                    end
                end,
            }})

            sort_dialog = ButtonDialog:new{
                title       = _("Sort collection by"),
                title_align = "center",
                buttons     = sort_buttons,
            }
            UIManager_cm:show(sort_dialog)
        end

        local buttons = {
            {{
                text     = "\u{F0DC}  " .. _("Sort  \u{25B8}"),
                align    = "left",
                callback = showSortSubmenu,
            }},
            {{
                text     = "\u{F0C1}  " .. _("Connect folders"),
                align    = "left",
                callback = function()
                    close_dialog()
                    fm_coll:showCollFolderList(item)
                end,
            }},
        }
        if not is_favorites then
            table.insert(buttons, {{
                text     = "\u{F031}  " .. _("Rename"),
                align    = "left",
                callback = function()
                    close_dialog()
                    fm_coll:renameCollection(item)
                end,
            }})
            table.insert(buttons, {{
                text     = "\u{F1F8}  " .. _("Remove"),
                align    = "left",
                callback = function()
                    close_dialog()
                    fm_coll:removeCollection(item)
                end,
            }})
        end
        button_dialog = ButtonDialog:new{
            buttons        = buttons,
            _added_widgets = { cover_header },
        }
        UIManager_cm:show(button_dialog)
        return true
    end

    local function show_coll_blank_menu(fm_coll)
        local ButtonDialog = require("ui/widget/buttondialog")
        local UIManager_bm = require("ui/uimanager")
        local _            = require("gettext")

        local button_dialog

        local function showDisplaySubmenu()
            UIManager_bm:close(button_dialog)
            local ok_bim, bim = pcall(require, "bookinfomanager")
            local ok_fm, FM   = pcall(require, "apps/filemanager/filemanager")
            local fm          = ok_fm and FM and FM.instance
            local cur_mode
            if ok_bim and bim then
                local ok3, m = pcall(function()
                    return bim:getSetting("filemanager_display_mode")
                end)
                if ok3 then cur_mode = m end
            end
            local function apply_mode(mode)
                if fm and type(fm.onSetDisplayMode) == "function" then
                    pcall(fm.onSetDisplayMode, fm, mode)
                elseif ok_bim and bim then
                    pcall(bim.saveSetting, bim, "filemanager_display_mode", mode)
                end
            end
            local view_dialog
            local function viewBtn(label, icon, mode)
                local active = cur_mode == mode
                return {{
                    text     = icon .. "  " .. label .. (active and "  \u{2713}" or ""),
                    align    = "left",
                    enabled  = not active,
                    callback = function()
                        UIManager_bm:close(view_dialog)
                        apply_mode(mode)
                        if fm_coll.coll_list then
                            UIManager_bm:close(fm_coll.coll_list)
                            fm_coll.coll_list = nil
                            fm_coll:onShowCollList()
                        end
                    end,
                }}
            end
            view_dialog = ButtonDialog:new{
                title       = _("Display mode"),
                title_align = "center",
                buttons     = {
                    viewBtn(_("Mosaic"),          "\u{F00A}", "mosaic_image"),
                    viewBtn(_("List (detailed)"), "\u{F03A}", "list_image_meta"),
                    viewBtn(_("List (basic)"),    "\u{F0CA}", "list_image_filename"),
                },
            }
            UIManager_bm:show(view_dialog)
        end

        local buttons = {
            {{
                text     = "\u{F07B}\u{207A}  " .. _("New collection"),
                align    = "left",
                callback = function()
                    UIManager_bm:close(button_dialog)
                    fm_coll:addCollection()
                end,
            }},
            {{
                text     = "\u{F0DC}  " .. _("Arrange"),
                align    = "left",
                callback = function()
                    UIManager_bm:close(button_dialog)
                    fm_coll:sortCollections()
                end,
            }},
            {{
                text     = "\u{F002}  " .. _("Search"),
                align    = "left",
                callback = function()
                    UIManager_bm:close(button_dialog)
                    fm_coll:onShowCollectionsSearchDialog()
                end,
            }},
            {{
                text     = "\u{F06E}  " .. _("Display  \u{25B8}"),
                align    = "left",
                callback = showDisplaySubmenu,
            }},
        }
        button_dialog = ButtonDialog:new{
            buttons = buttons,
        }
        UIManager_bm:show(button_dialog)
        return true
    end

    ---------------------------------------------------------------------------
    -- Flag set during onShowCollList so Menu:init can detect coll_list creation
    ---------------------------------------------------------------------------
    local _patching_coll_list = false

    ---------------------------------------------------------------------------
    -- Menu:init hook — minimal TitleBar + optional mosaic setup
    ---------------------------------------------------------------------------
    local orig_menu_init = Menu.init
    function Menu:init()
        local should_patch = is_enabled() and should_match_statusbar_height()
            and (self.name == "collections" or _patching_coll_list)
        if should_patch then
            local TitleBar    = require("ui/widget/titlebar")
            local orig_tb_new = TitleBar.new
            TitleBar.new = function(cls, t)
                if type(t) == "table" then
                    t.subtitle                 = nil
                    t.subtitle_fullwidth       = nil
                    t.left_icon                = nil
                    t.left_icon_tap_callback   = nil
                    t.left_icon_hold_callback  = nil
                    t.right_icon               = nil
                    t.right_icon_tap_callback  = nil
                    t.right_icon_hold_callback = nil
                    t.close_callback           = nil
                    t.title_tap_callback       = nil
                    t.title_hold_callback      = nil
                    t.bottom_v_padding         = 0
                    t.title                    = " "
                end
                return orig_tb_new(cls, t)
            end
            orig_menu_init(self)
            TitleBar.new = orig_tb_new

            -- For the collections list, set up display mode BEFORE any updateItems
            if _patching_coll_list then
                local mode_type = setup_display_mode(self)
                if mode_type == "mosaic" then
                    patch_mosaic_item()
                elseif mode_type == "list" then
                    patch_list_item()
                end
            end
        else
            orig_menu_init(self)
        end
    end

    ---------------------------------------------------------------------------
    -- Shared: swipe override
    ---------------------------------------------------------------------------
    ---------------------------------------------------------------------------
    -- Shared: icon removal helper
    ---------------------------------------------------------------------------
    local function remove_from_overlap(group, widget)
        if not widget then return end
        for i = #group, 1, -1 do
            if rawequal(group[i], widget) then
                table.remove(group, i)
                return
            end
        end
    end

    ---------------------------------------------------------------------------
    -- clean_nav: customises a NAMED collection's booklist_menu
    ---------------------------------------------------------------------------
    local function clean_nav(menu, collection_name)
        if not menu then return end

        local UIManager_mod = require("ui/uimanager")

        menu._do_center_partial_rows = false
        menu:updateItems(1, true)

        local arrow = menu.page_return_arrow
        if arrow then
            local Geom = require("ui/geometry")
            arrow:hide()
            arrow.show     = function() end
            arrow.showHide = function() end
            arrow.dimen    = Geom:new{ w = 0, h = 0 }
        end

        local tb = menu.title_bar
        if not tb then return end

        local createStatusRowCustomBack = zen_plugin._zen_shared
            and zen_plugin._zen_shared.createStatusRowCustomBack

        if createStatusRowCustomBack and tb.title_group and #tb.title_group >= 2 then
            local back_callback = menu.onReturn and function() menu.onReturn() end
                               or function() end

            local status_row = createStatusRowCustomBack(back_callback, collection_name)
            tb.title_group[2] = status_row
            tb.title_group:resetLayout()

            remove_from_overlap(tb, tb.left_button)
            remove_from_overlap(tb, tb.right_button)
            tb.has_left_icon  = false
            tb.has_right_icon = false

            menu._zen_status_refresh = function()
                if tb.title_group and #tb.title_group >= 2 then
                    tb.title_group[2] = createStatusRowCustomBack(back_callback, collection_name)
                    tb.title_group:resetLayout()
                    UIManager_mod:setDirty(menu, "ui", tb.dimen)
                end
            end
            UIManager_mod:setDirty(menu, "ui", tb.dimen)
        else
            remove_from_overlap(tb, tb.left_button)
            remove_from_overlap(tb, tb.right_button)
            tb.has_left_icon  = false
            tb.has_right_icon = false
        end
    end

    ---------------------------------------------------------------------------
    -- clean_nav_list: customises the COLLECTIONS LIST (coll_list) Menu
    ---------------------------------------------------------------------------
    local function clean_nav_list(menu, fm_coll)
        if not menu then return end

        local UIManager_mod = require("ui/uimanager")
        local Device        = require("device")

        -- ── Replace onMenuHold with our context menu ────────────────────────
        menu.onMenuHold = function(menu_self, item)
            return show_coll_item_menu(fm_coll, item, menu)
        end

        -- ── Add blank-space hold gesture for general menu ───────────────────
        if Device:isTouchDevice() then
            local GestureRange_g = require("ui/gesturerange")
            local Geom_g         = require("ui/geometry")
            if not menu.ges_events then
                menu.ges_events = {}
            end
            menu.ges_events.ZenCollBlankHold = {
                GestureRange_g:new{
                    ges   = "hold",
                    range = Geom_g:new{
                        x = 0, y = 0,
                        w = Device.screen:getWidth(),
                        h = Device.screen:getHeight(),
                    },
                },
            }
            menu.onZenCollBlankHold = function()
                return show_coll_blank_menu(fm_coll)
            end
        end

        -- ── Status bar in titlebar ──────────────────────────────────────────
        local tb = menu.title_bar
        if not tb then return end

        local createStatusRow = zen_plugin._zen_shared
            and zen_plugin._zen_shared.createStatusRow

        if createStatusRow and tb.title_group and #tb.title_group >= 2 then
            local FileManager = require("apps/filemanager/filemanager")
            local status_row = createStatusRow(nil, FileManager.instance)
            tb.title_group[2] = status_row
            tb.title_group:resetLayout()

            remove_from_overlap(tb, tb.left_button)
            remove_from_overlap(tb, tb.right_button)
            tb.has_left_icon  = false
            tb.has_right_icon = false

            menu._zen_status_refresh = function()
                if tb.title_group and #tb.title_group >= 2 then
                    tb.title_group[2] = createStatusRow(nil, FileManager.instance)
                    tb.title_group:resetLayout()
                    UIManager_mod:setDirty(menu, "ui", tb.dimen)
                end
            end
            UIManager_mod:setDirty(menu, "ui", tb.dimen)
        else
            remove_from_overlap(tb, tb.left_button)
            remove_from_overlap(tb, tb.right_button)
            tb.has_left_icon  = false
            tb.has_right_icon = false
        end
    end

    ---------------------------------------------------------------------------
    -- Hook onShowColl (named collection view)
    ---------------------------------------------------------------------------
    local orig_onShowColl = FileManagerCollection.onShowColl
    function FileManagerCollection:onShowColl(collection_name)
        local ok, ReadCollection = pcall(require, "readcollection")
        local resolved_name = collection_name or (ok and ReadCollection.default_collection_name)
        local is_favorites = not ok
            or resolved_name == nil
            or (ok and resolved_name == ReadCollection.default_collection_name)

        if is_enabled() and self.ui then
            local coverbrowser = self.ui.coverbrowser
            if coverbrowser and type(coverbrowser.setupWidgetDisplayMode) == "function" then
                local BookInfoManager = require("bookinfomanager")
                local fm_mode   = BookInfoManager:getSetting("filemanager_display_mode")
                local coll_mode = BookInfoManager:getSetting("collection_display_mode")
                if fm_mode ~= coll_mode then
                    coverbrowser.setupWidgetDisplayMode("collections", fm_mode)
                end
            end
        end

        orig_onShowColl(self, collection_name)

        if not is_enabled() then return end

        if is_favorites and collection_name == nil then
            return
        end

        local display_name = resolved_name
        if is_favorites then
            local _ = require("gettext")
            display_name = _("Favorites")
        end

        clean_nav(self.booklist_menu, display_name)
    end

    ---------------------------------------------------------------------------
    -- Prevent partial-row centering on subsequent updateCollListItemTable calls
    ---------------------------------------------------------------------------
    local orig_updateCollListItemTable = FileManagerCollection.updateCollListItemTable
    function FileManagerCollection:updateCollListItemTable(...)
        if is_enabled() and self.coll_list then
            self.coll_list._do_center_partial_rows = false
        end
        return orig_updateCollListItemTable(self, ...)
    end

    ---------------------------------------------------------------------------
    -- Hook onShowCollList (collections list view — browse mode only)
    ---------------------------------------------------------------------------
    local orig_onShowCollList = FileManagerCollection.onShowCollList
    function FileManagerCollection:onShowCollList(file_or_selected_collections, caller_callback, no_dialog)
        local is_browse = file_or_selected_collections == nil

        -- Set flag so Menu:init creates minimal TitleBar + sets up mosaic
        if is_browse and is_enabled() and should_match_statusbar_height() then
            _patching_coll_list = true
        end

        local result = orig_onShowCollList(self, file_or_selected_collections, caller_callback, no_dialog)
        _patching_coll_list = false

        if not is_enabled() then return result end
        if not is_browse then return result end
        if not self.coll_list then return result end

        clean_nav_list(self.coll_list, self)
        return result
    end

    logger.warn("zen-coll: all hooks installed")
end

return apply_collections

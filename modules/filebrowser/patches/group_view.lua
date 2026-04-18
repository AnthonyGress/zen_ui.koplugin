local logger = require("logger")

local M = {}

-- One-time patch guards
local _mosaic_item_patched = false
local _list_item_patched   = false

-- Active group view menus (so we can refresh them)
local _authors_menu = nil
local _series_menu  = nil
local _tbr_menu     = nil

-- Set during apply (called at init while __ZEN_UI_PLUGIN is set)
local _zen_shared    = nil
local _zen_plugin    = nil  -- captured at init; __ZEN_UI_PLUGIN is cleared after init

-------------------------------------------------------------------------------
-- Utility: walk upvalue chain to find a named upvalue
-------------------------------------------------------------------------------
local function get_upvalue(fn, name)
    if type(fn) ~= "function" then return nil end
    for i = 1, 64 do
        local upname, value = debug.getupvalue(fn, i)
        if not upname then break end
        if upname == name then return value end
    end
end

-------------------------------------------------------------------------------
-- setup_display_mode: mirror fi CoverMenu/MosaicMenu/ListMenu onto menu
-- Returns "mosaic", "list", or "classic"
-------------------------------------------------------------------------------
local function setup_display_mode(menu, is_group_view, tab_id)
    local BookInfoManager = require("bookinfomanager")
    local display_mode
    if tab_id then
        local g_settings = rawget(_G, "G_reader_settings")
        display_mode = g_settings and g_settings:readSetting("zen_" .. tab_id .. "_display_mode")
            or "list_image_meta"
    else
        display_mode = BookInfoManager:getSetting("filemanager_display_mode")
    end
    if is_group_view then
        menu._zen_group_view = true
    end

    if not display_mode then return "classic" end

    local ok_cm, CoverMenu = pcall(require, "covermenu")
    if not ok_cm then return false end

    local display_mode_type = display_mode:gsub("_.*", "")  -- "mosaic" or "list"

    menu.updateItems   = CoverMenu.updateItems
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

    -- Provide proper getBookInfo for badge support
    if not menu.getBookInfo then
        if is_group_view then
            menu.getBookInfo = function() return {} end
        else
            -- Return reading status (percent_finished, status, been_opened) from sidecar.
            -- Called as menu.getBookInfo(filepath) — dot syntax, ONE arg only.
            menu.getBookInfo = function(file_path)
                if not file_path then return {} end
                local ok_ds, DocSettings = pcall(require, "docsettings")
                if not ok_ds then return {} end
                if not DocSettings:hasSidecarFile(file_path) then return {} end
                local ok2, doc = pcall(DocSettings.open, DocSettings, file_path)
                if not ok2 or not doc then return {} end
                local summary = doc:readSetting("summary")
                return {
                    been_opened      = true,
                    percent_finished = doc:readSetting("percent_finished"),
                    status           = summary and summary.status,
                }
            end
        end
    end
    if not menu.resetBookInfoCache then
        menu.resetBookInfoCache = function() end
    end

    return display_mode_type
end

-------------------------------------------------------------------------------
-- patch_mosaic_item: one-time install of MosaicMenuItem.update override
-- Uses self.entry._zen_files (list of absolute file paths)
-------------------------------------------------------------------------------
local function patch_mosaic_item()
    if _mosaic_item_patched then return end

    local ok, MosaicMenu = pcall(require, "mosaicmenu")
    if not ok then return end
    local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then return end
    _mosaic_item_patched = true

    local BookInfoManager = require("bookinfomanager")

    -- Keep underlines hidden on focus (same guard as collections.lua)
    local Blitbuffer_uc = require("ffi/blitbuffer")
    if not MosaicMenuItem._zen_as_focus_patched then
        MosaicMenuItem._zen_as_focus_patched = true
        local orig_onFocus = MosaicMenuItem.onFocus
        function MosaicMenuItem:onFocus()
            if self._underline_container then
                self._underline_container.color = Blitbuffer_uc.COLOR_WHITE
            end
            if orig_onFocus then return orig_onFocus(self) end
            return true
        end
    end

    local orig_update = MosaicMenuItem.update
    function MosaicMenuItem:update(...)
        if not (self.menu and self.menu._zen_group_view
                and self.entry and self.entry._zen_files) then
            return orig_update(self, ...)
        end

        self.is_directory = true

        local files      = self.entry._zen_files
        local book_count = #files
        local covers     = {}
        for i = 1, math.min(book_count, 4) do
            local bi = BookInfoManager:getBookInfo(files[i], true)
            if bi and bi.cover_bb and bi.has_cover
                    and bi.cover_fetched and not bi.ignore_cover then
                table.insert(covers, {
                    data = bi.cover_bb:copy(),
                    w    = bi.cover_w,
                    h    = bi.cover_h,
                })
            end
        end

        -- Delegate to browser_folder_cover's method when available
        if self._setFolderCover then
            self:_setFolderCover{ gallery = covers, book_count = book_count }
            return
        end

        -- Inline fallback gallery (matches collections.lua)
        local Blitbuffer      = require("ffi/blitbuffer")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local FrameContainer  = require("ui/widget/container/framecontainer")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local ImageWidget     = require("ui/widget/imagewidget")
        local LineWidget      = require("ui/widget/linewidget")
        local OverlapGroup    = require("ui/widget/overlapgroup")
        local Size            = require("ui/size")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local VerticalSpan    = require("ui/widget/verticalspan")

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

-------------------------------------------------------------------------------
-- patch_list_item: one-time install of ListMenuItem.update override
-------------------------------------------------------------------------------
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
    local RightContainer  = require("ui/widget/container/rightcontainer")
    local Size            = require("ui/size")
    local TextBoxWidget   = require("ui/widget/textboxwidget")
    local TextWidget      = require("ui/widget/textwidget")
    local VerticalGroup   = require("ui/widget/verticalgroup")
    local VerticalSpan    = require("ui/widget/verticalspan")

    local Screen = Device.screen
    local scale_by_size = Screen:scaleBySize(1000000) * (1 / 1000000)

    local orig_list_update = ListMenuItem.update

    function ListMenuItem:update(...)
        if not (self.menu and self.menu._zen_group_view
                and self.entry and self.entry._zen_files) then
            return orig_list_update(self, ...)
        end

        self.is_directory = true

        local files      = self.entry._zen_files
        local book_count = #files
        local display_name = self.entry.text or ""

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

        local wleft
        if self.do_cover_image then
            local gallery_mode = BookInfoManager:getSetting("folder_gallery_mode")
            local max_covers   = gallery_mode and 4 or 1
            local covers       = {}
            for i = 1, #files do
                local bi = BookInfoManager:getBookInfo(files[i], true)
                if bi and bi.cover_bb and bi.has_cover
                        and bi.cover_fetched and not bi.ignore_cover then
                    table.insert(covers, { data = bi.cover_bb:copy() })
                    if #covers >= max_covers then break end
                end
            end

            local cover_frame
            if gallery_mode then
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
                                ImageWidget:new{ image = c.data, width = cd.w, height = cd.h },
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
                local bb       = covers[1].data
                local bb_w     = bb:getWidth()
                local bb_h     = bb:getHeight()
                local sf       = math.max(cover_w / bb_w, max_img / bb_h)
                local scaled_w = math.max(cover_w,  math.ceil(bb_w * sf))
                local scaled_h = math.max(max_img, math.ceil(bb_h * sf))
                local x_off    = math.floor((scaled_w - cover_w) / 2)
                local y_off    = math.floor((scaled_h - max_img) / 2)
                local scaled_bb = bb:scale(scaled_w, scaled_h)
                local fill_bb   = Blitbuffer.new(cover_w, max_img, scaled_bb:getType())
                fill_bb:blitFrom(scaled_bb, 0, 0, x_off, y_off, cover_w, max_img)
                scaled_bb:free()
                bb:free()
                local wimage = ImageWidget:new{
                    image = fill_bb, scale_factor = 1, _free_image = true,
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
                cover_frame = FrameContainer:new{
                    width = cover_w + 2 * border_size,
                    height = max_img + 2 * border_size,
                    margin = 0, padding = 0, bordersize = border_size,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    CenterContainer:new{
                        dimen = { w = max_img, h = max_img },
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

        local pad_left    = self.do_cover_image and Screen:scaleBySize(6) or Screen:scaleBySize(10)
        local pad_right   = Screen:scaleBySize(10)
        local fs_title    = _fontSize(18, 21)
        local fs_meta     = _fontSize(14, 18)
        local left_offset = self.do_cover_image and (cover_zone_w + pad_left) or pad_left

        local count_str = tostring(book_count) .. " " .. (book_count == 1 and "book" or "books")
        local wright_status = TextWidget:new{
            text    = count_str,
            face    = Font:getFace("cfont", fs_meta),
            fgcolor = Blitbuffer.COLOR_GRAY_3,
            padding = 0,
        }
        local wright_w = wright_status:getWidth()
        local main_w = math.max(1, self.width - left_offset - wright_w - 2 * pad_right)

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

-------------------------------------------------------------------------------
-- remove_from_overlap: remove widget from an OverlapGroup/widget list
-------------------------------------------------------------------------------
local function remove_from_overlap(group, widget)
    if not widget then return end
    for i = #group, 1, -1 do
        if rawequal(group[i], widget) then
            table.remove(group, i)
            return
        end
    end
end

-------------------------------------------------------------------------------
-- clean_nav: suppress back arrow, inject status bar row, set display mode
-- back_callback: optional function for the status bar back chevron
-------------------------------------------------------------------------------
local function clean_nav(menu, tab_label, back_callback)
    if not menu then return end

    local UIManager_mod = require("ui/uimanager")

    menu._do_center_partial_rows = false

    local arrow = menu.page_return_arrow
    if arrow then
        local Geom = require("ui/geometry")
        arrow:hide()
        arrow.show     = function() end
        arrow.showHide = function() end
        arrow.dimen    = Geom:new{ w = 0, h = 0 }
    end

    local tb = menu.title_bar
    if not tb then
        logger.warn("zen-authors-series: clean_nav: no title_bar")
        return
    end

    local createStatusRow     = _zen_shared and _zen_shared.createStatusRow
    local createStatusRowCB   = _zen_shared and _zen_shared.createStatusRowCustomBack
    local repaintTitleBar     = _zen_shared and _zen_shared.repaintTitleBar

    local function makeRow()
        if back_callback and createStatusRowCB then
            return createStatusRowCB(back_callback, tab_label)
        elseif createStatusRow then
            local FileManager = require("apps/filemanager/filemanager")
            return createStatusRow(nil, FileManager.instance)
        end
    end

    local status_row = makeRow()
    if status_row and tb.title_group and #tb.title_group >= 2 then
        tb.title_group[2] = status_row
        tb.title_group:resetLayout()

        remove_from_overlap(tb, tb.left_button)
        remove_from_overlap(tb, tb.right_button)
        tb.has_left_icon  = false
        tb.has_right_icon = false

        menu._zen_status_refresh = function()
            local row = makeRow()
            if row and tb.title_group and #tb.title_group >= 2 then
                tb.title_group[2] = row
                tb.title_group:resetLayout()
                if repaintTitleBar then repaintTitleBar(tb) end
            end
        end
    else
        remove_from_overlap(tb, tb.left_button)
        remove_from_overlap(tb, tb.right_button)
        tb.has_left_icon  = false
        tb.has_right_icon = false
    end
end

-------------------------------------------------------------------------------
-- build_group_item_table: convert db_bookinfo groups to Menu item_table entries
-- data_type: "authors" or "series"
-- groups: output of db_bookinfo.getGroupedByAuthor() / getGroupedBySeries()
-------------------------------------------------------------------------------
local function build_group_item_table(groups, data_type)
    local _ = require("gettext")
    local items = {}
    for _, group in ipairs(groups) do
        local files
        if data_type == "authors" then
            files = group.files
        else
            -- series items: extract file paths in order
            files = {}
            for _, item in ipairs(group.items) do
                table.insert(files, item.file)
            end
        end
        local display = group.author or group.series or "?"
        table.insert(items, {
            text        = display,
            _zen_files  = files,
            _zen_type   = data_type,
            _zen_group  = (data_type == "series") and group or nil,
        })
    end
    if #items == 0 then
        table.insert(items, {
            text     = _("No books found"),
            dim      = true,
            callback = function() end,
        })
    end

    -- Apply reverse sort if enabled
    local settings_key = data_type == "authors" and "zen_authors_reverse" or "zen_series_reverse"
    local g_settings = rawget(_G, "G_reader_settings")
    if g_settings and g_settings:isTrue(settings_key) and #items > 0 then
        -- Reverse the array (skip the placeholder)
        if items[1].text ~= _("No books found") then
            local reversed = {}
            for i = #items, 1, -1 do
                table.insert(reversed, items[i])
            end
            items = reversed
        end
    end

    return items
end

-- Forward declaration so showDisplayModeDialog can reference showGroupView.
local showGroupView

-------------------------------------------------------------------------------
-- showDisplayModeDialog: show display mode selection dialog
-- menu: optional Menu instance to refresh after mode change
-------------------------------------------------------------------------------
local function showDisplayModeDialog(menu, tab_id)
    local _ = require("gettext")
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager = require("ui/uimanager")

    local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
    local fm = ok_fm and FM and FM.instance
    local ok_bim, bim = pcall(require, "bookinfomanager")
    local cur_mode
    if tab_id then
        local g_settings = rawget(_G, "G_reader_settings")
        cur_mode = (g_settings and g_settings:readSetting("zen_" .. tab_id .. "_display_mode"))
            or "list_image_meta"
    elseif ok_bim and bim then
        local ok3, m = pcall(function()
            return bim:getSetting("filemanager_display_mode")
        end)
        if ok3 then cur_mode = m end
    end

    local function apply_mode(mode)
        if tab_id then
            local g_settings = rawget(_G, "G_reader_settings")
            if g_settings then
                g_settings:saveSetting("zen_" .. tab_id .. "_display_mode", mode)
            end
        else
            -- Use FM:onSetDisplayMode to update CoverBrowser state and save to BIM.
            local via_fm = false
            if fm and type(fm.onSetDisplayMode) == "function" then
                via_fm = pcall(fm.onSetDisplayMode, fm, mode)
            end
            if not via_fm and ok_bim and bim then
                pcall(bim.saveSetting, bim, "filemanager_display_mode", mode)
            end
        end

        -- Rebuild in-place: swap methods for the new mode, then redraw once.
        if menu then
            local is_group = menu._zen_group_view or false
            local new_mode_type = setup_display_mode(menu, is_group, tab_id)
            if new_mode_type == "mosaic" then
                patch_mosaic_item()
            elseif new_mode_type == "list" then
                patch_list_item()
            else
                -- Classic mode: restore base Menu methods
                local Menu_class = require("ui/widget/menu")
                menu.updateItems         = Menu_class.updateItems
                menu._updateItemsBuildUI = nil
                menu._recalculateDimen   = nil
                menu.display_mode_type   = nil
            end
            menu:updateItems()
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
                UIManager:close(view_dialog)
                apply_mode(mode)
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
    UIManager:show(view_dialog)
end


-------------------------------------------------------------------------------
-- showGroupSortDialog: show ascending/descending sort dialog for group view
-- tab_id: "authors" | "series"
-- menu: the Menu instance to refresh after sort change
-------------------------------------------------------------------------------
local function showGroupSortDialog(tab_id, menu)
    local _ = require("gettext")
    local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
    local fm = ok_fm and FM and FM.instance
    if not fm then return end

    local settings_key = tab_id == "authors" and "zen_authors_reverse" or "zen_series_reverse"
    local g_settings = rawget(_G, "G_reader_settings")
    if not g_settings then return end

    local title = tab_id == "authors" and _("Sort authors") or _("Sort series")

    fm.file_chooser:showSortOrderDialog({
        title           = title,
        current_reverse = g_settings:isTrue(settings_key),
        on_select       = function(reverse)
            if reverse then
                g_settings:saveSetting(settings_key, true)
            else
                g_settings:delSetting(settings_key)
            end
            if menu then
                local ok, db = pcall(require, "common/db_bookinfo")
                if ok then
                    local groups = tab_id == "authors"
                        and db.getGroupedByAuthor()
                        or db.getGroupedBySeries()
                    menu.item_table = build_group_item_table(groups, tab_id)
                    menu:updateItems()
                end
            end
        end,
    })
end

-------------------------------------------------------------------------------
-- sortDetailFiles: sort files array by collate field and reverse flag
-- Returns sorted array of file paths
-------------------------------------------------------------------------------
local function sortDetailFiles(files, collate, reverse)
    if not files or #files == 0 then return files end

    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim then return files end

    -- Build sortable array with metadata
    local items = {}
    for _, fpath in ipairs(files) do
        local bookinfo = BookInfoManager:getBookInfo(fpath, true)
        local sort_key

        if collate == "title" then
            sort_key = (bookinfo and bookinfo.title) or fpath:match("([^/]+)$") or fpath
        elseif collate == "series" then
            sort_key = (bookinfo and bookinfo.series) or ""
        elseif collate == "access" then
            -- Recently read: use last_read timestamp (higher = more recent)
            sort_key = (bookinfo and bookinfo.last_read) or 0
        else
            sort_key = fpath:match("([^/]+)$") or fpath
        end

        table.insert(items, { path = fpath, key = sort_key })
    end

    -- Sort by key
    table.sort(items, function(a, b)
        if collate == "access" then
            -- For access, higher timestamp = more recent, so reverse the comparison
            return reverse and (a.key < b.key) or (a.key > b.key)
        else
            -- For title/series, alphabetical
            local a_lower = type(a.key) == "string" and a.key:lower() or tostring(a.key)
            local b_lower = type(b.key) == "string" and b.key:lower() or tostring(b.key)
            return reverse and (a_lower > b_lower) or (a_lower < b_lower)
        end
    end)

    -- Extract sorted paths
    local sorted = {}
    for _, item in ipairs(items) do
        table.insert(sorted, item.path)
    end

    return sorted
end

-------------------------------------------------------------------------------
-- showDetailSortDialog: show sort options dialog for detail view
-- group_name: the author or series name
-- tab_id: "authors" | "series"
-- menu: the Menu instance to refresh after sort change
-- files: list of file paths
-------------------------------------------------------------------------------
local function showDetailSortDialog(group_name, tab_id, menu, files)
    local _ = require("gettext")
    local ButtonDialog = require("ui/widget/buttondialog")
    local UIManager = require("ui/uimanager")

    local collate_key = "zen_" .. tab_id .. "_detail_collate_" .. group_name
    local reverse_key = "zen_" .. tab_id .. "_detail_reverse_" .. group_name
    local g_settings = rawget(_G, "G_reader_settings")
    if not g_settings then return end

    local cur_collate = g_settings:readSetting(collate_key) or "title"
    local cur_reverse = g_settings:isTrue(reverse_key)

    local SORT_OPTIONS = {
        { key = "title",  text = "\u{F031}  " .. _("Title") },
        { key = "series", text = "\u{F0CB}  " .. _("Series") },
        { key = "access", text = "\u{F073}  " .. _("Recently read") },
    }

    local function rebuildMenu(collate, reverse)
        if not (menu and files) then return end

        local sorted_files = sortDetailFiles(files, collate, reverse)

        local book_items = {}
        for _, fpath in ipairs(sorted_files) do
            local fname = fpath:match("([^/]+)$") or fpath
            local display = fname:gsub("%.[^%.]+$", "")

            table.insert(book_items, {
                text = display,
                path = fpath,      -- Standard KOReader file item field
                is_file = true,    -- Required for CoverBrowser to recognize as file
            })
        end

        menu.item_table = book_items
        menu:updateItems()
    end

    local sort_dialog
    local sort_buttons = {}

    -- Add collate field options
    for _, opt in ipairs(SORT_OPTIONS) do
        local is_active = cur_collate == opt.key
        table.insert(sort_buttons, {{
            text     = opt.text .. (is_active and "  \u{2713}" or ""),
            align    = "left",
            enabled  = not is_active,
            callback = function()
                g_settings:saveSetting(collate_key, opt.key)
                UIManager:close(sort_dialog)
                rebuildMenu(opt.key, cur_reverse)
            end,
        }})
    end

    -- Order submenu
    table.insert(sort_buttons, {{
        text     = "\u{F0DC}  " .. _("Order  ▶"),
        align    = "left",
        callback = function()
            local order_dialog
            local order_buttons = {
                {{
                    text     = "\u{F15D}  " .. _("Ascending") .. (not cur_reverse and "  \u{2713}" or ""),
                    align    = "left",
                    enabled  = cur_reverse,
                    callback = function()
                        g_settings:delSetting(reverse_key)
                        UIManager:close(order_dialog)
                        UIManager:close(sort_dialog)
                        rebuildMenu(cur_collate, false)
                    end,
                }},
                {{
                    text     = "\u{F15E}  " .. _("Descending") .. (cur_reverse and "  \u{2713}" or ""),
                    align    = "left",
                    enabled  = not cur_reverse,
                    callback = function()
                        g_settings:saveSetting(reverse_key, true)
                        UIManager:close(order_dialog)
                        UIManager:close(sort_dialog)
                        rebuildMenu(cur_collate, true)
                    end,
                }},
            }
            order_dialog = ButtonDialog:new{
                title       = _("Sort order"),
                title_align = "center",
                buttons     = order_buttons,
            }
            UIManager:show(order_dialog)
        end,
    }})

    sort_dialog = ButtonDialog:new{
        title       = _("Sort books by"),
        title_align = "center",
        buttons     = sort_buttons,
    }
    UIManager:show(sort_dialog)
end

-------------------------------------------------------------------------------
-- showDetailView: book list for one author/series group
-- Called from onMenuSelect on the group list menu
-------------------------------------------------------------------------------
local function showDetailView(group_item, injectNavbar, tab_id)
    local _ = require("gettext")
    local Menu      = require("ui/widget/menu")
    local TitleBar  = require("ui/widget/titlebar")
    local UIManager = require("ui/uimanager")
    local ReaderUI  = require("apps/reader/readerui")

    local files      = group_item._zen_files or {}
    local group_name = group_item.text or ""
    local detail_name = tab_id == "authors" and "authors_detail" or "series_detail"

    -- Get sort settings for this group
    local collate_key = "zen_" .. tab_id .. "_detail_collate_" .. group_name
    local reverse_key = "zen_" .. tab_id .. "_detail_reverse_" .. group_name
    local g_settings = rawget(_G, "G_reader_settings")
    local cur_collate = g_settings and g_settings:readSetting(collate_key) or "title"
    local cur_reverse = g_settings and g_settings:isTrue(reverse_key) or false

    -- Sort files based on current settings
    local sorted_files = sortDetailFiles(files, cur_collate, cur_reverse)

    -- Build menu items from sorted files
    local book_items = {}
    for _, fpath in ipairs(sorted_files) do
        local fname = fpath:match("([^/]+)$") or fpath
        local display = fname:gsub("%.[^%.]+$", "")

        table.insert(book_items, {
            text = display,
            path = fpath,      -- Standard KOReader file item field
            filepath = fpath,  -- Required for MosaicMenuItem badge access
            is_file = true,    -- Required for CoverBrowser to recognize as file
        })
    end
    if #book_items == 0 then
        table.insert(book_items, {
            text = _("No books found"),
            dim  = true,
            callback = function() end,
        })
    end

    -- Minimise TitleBar during Menu creation
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

    local detail_menu = Menu:new{
        name               = detail_name,
        title              = group_name,
        covers_fullscreen  = true,
        is_borderless      = true,
        is_popout          = false,
        title_bar_fm_style = true,  -- picked up by zen_scroll_bar patch
        item_table         = book_items,
        onMenuSelect       = function(menu_self, item)
            if item.path then
                ReaderUI:showReader(item.path)
            end
        end,
        onMenuHold         = function(menu_self, item)
            if not item.path then return end
            local FileManager = require("apps/filemanager/filemanager")
            local fm = FileManager.instance
            if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
                fm.file_chooser:showFileDialog({
                    path    = item.path,
                    is_file = true,
                    text    = item.text,
                })
            end
        end,
        updateItems        = function(menu_self, ...) end,  -- prevent default pagination
    }
    TitleBar.new = orig_tb_new

    -- Install same display mode as the library (mosaic/list/classic)
    local mode_type = setup_display_mode(detail_menu, false, tab_id)
    if mode_type == "mosaic" then
        patch_mosaic_item()
    elseif mode_type == "list" then
        patch_list_item()
    elseif mode_type == "classic" or not mode_type then
        local Menu_class = require("ui/widget/menu")
        detail_menu.updateItems = Menu_class.updateItems
    end

    detail_menu.close_callback = function()
        UIManager:close(detail_menu)
    end

    -- Close the parent group menu too (used by navbar tap to unwind the full stack)
    detail_menu._zen_close_stack = function()
        local parent = tab_id == "authors" and _authors_menu or _series_menu
        if parent then
            UIManager:close(parent)
            if tab_id == "authors" then _authors_menu = nil else _series_menu = nil end
        end
    end

    local back_to_group = function() UIManager:close(detail_menu) end
    clean_nav(detail_menu, group_name, back_to_group)

    if injectNavbar then
        injectNavbar(detail_menu, tab_id)  -- keep authors/series tab active
    end

    -- Add blank-space hold gesture handler for context menu
    local Device3 = require("device")
    if Device3:isTouchDevice() then
        local GestureRange2 = require("ui/gesturerange")
        local Geom2         = require("ui/geometry")
        if not detail_menu.ges_events then
            detail_menu.ges_events = {}
        end
        detail_menu.ges_events.ZenDetailBlankHold = {
            GestureRange2:new{
                ges   = "hold",
                range = Geom2:new{
                    x = 0, y = 0,
                    w = Device3.screen:getWidth(),
                    h = Device3.screen:getHeight(),
                },
            },
        }
        function detail_menu:onZenDetailBlankHold(arg, ges)
            local FileManager = require("apps/filemanager/filemanager")
            local fm = FileManager.instance
            if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
                fm.file_chooser:showFileDialog({
                    _zen_group_files = files,
                    _zen_group_name  = group_name,
                    _zen_sort_cb     = function()
                        showDetailSortDialog(group_name, tab_id, self, files)
                    end,
                    _zen_display_cb  = function()
                        showDisplayModeDialog(self, tab_id)
                    end,
                })
            end
            return true
        end
    end
    UIManager:show(detail_menu)
    UIManager:nextTick(function()
        detail_menu:updateItems()
        -- Re-inject status row after updateItems (it may reset title_group).
        local createSR2   = _zen_shared and _zen_shared.createStatusRowCustomBack
        local repaintTB2  = _zen_shared and _zen_shared.repaintTitleBar
        local tb2 = detail_menu.title_bar
        if tb2 and createSR2 and tb2.title_group and #tb2.title_group >= 2 then
            tb2.title_group[2] = createSR2(back_to_group, group_name)
            tb2.title_group:resetLayout()
            if repaintTB2 then repaintTB2(tb2) end
        end
    end)
end

-------------------------------------------------------------------------------
-- showGroupView: shared group-list menu builder for authors and series
-- tab_id: "authors" | "series"
-- injectNavbar: the injectStandaloneNavbar function from navbar.lua
-- groups: pre-loaded data from db_bookinfo
-------------------------------------------------------------------------------
showGroupView = function(tab_id, injectNavbar, groups)
    local _ = require("gettext")
    local Menu      = require("ui/widget/menu")
    local TitleBar  = require("ui/widget/titlebar")
    local UIManager = require("ui/uimanager")

    local title = tab_id == "authors" and _("Authors") or _("Series")
    local item_table = build_group_item_table(groups, tab_id)

    -- Minimise TitleBar during Menu creation
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

    local menu = Menu:new{
        name               = tab_id,
        title              = title,
        covers_fullscreen  = true,
        is_borderless      = true,
        is_popout          = false,
        title_bar_fm_style = true,  -- picked up by zen_scroll_bar patch
        item_table         = item_table,
        onMenuSelect       = function(menu_self, item)
            if item._zen_files then
                showDetailView(item, injectNavbar, tab_id)
            end
        end,
        onMenuHold         = function(menu_self, item)
            if item._zen_files then
                local FileManager = require("apps/filemanager/filemanager")
                local fm = FileManager.instance
                if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
                    fm.file_chooser:showFileDialog({
                        _zen_group_files = item._zen_files,
                        _zen_group_name  = item.text,
                        _zen_sort_cb     = function()
                            showGroupSortDialog(tab_id, menu_self)
                        end,
                    })
                end
            end
        end,
        updateItems        = function(menu_self, ...) end,  -- prevent default pagination
    }
    TitleBar.new = orig_tb_new

    -- Install display mode (mosaic/list) and set _zen_group_view sentinel
    local mode_type = setup_display_mode(menu, true, tab_id)
    if mode_type == "mosaic" then
        patch_mosaic_item()
    elseif mode_type == "list" then
        patch_list_item()
    end

    -- For classic mode (no CoverBrowser), restore the base updateItems
    if mode_type == "classic" or not mode_type then
        local Menu_class = require("ui/widget/menu")
        menu.updateItems = Menu_class.updateItems
    end

    menu.close_callback = function()
        UIManager:close(menu)
        if tab_id == "authors" then
            _authors_menu = nil
        else
            _series_menu = nil
        end
    end

    clean_nav(menu, title)

    if injectNavbar then
        injectNavbar(menu, tab_id)
    end

    if tab_id == "authors" then
        _authors_menu = menu
    else
        _series_menu = menu
    end

    -- Add blank-space hold gesture handler for context menu
    local Device2 = require("device")
    if Device2:isTouchDevice() then
        local GestureRange = require("ui/gesturerange")
        local Geom         = require("ui/geometry")
        if not menu.ges_events then
            menu.ges_events = {}
        end
        menu.ges_events.ZenGroupBlankHold = {
            GestureRange:new{
                ges   = "hold",
                range = Geom:new{
                    x = 0, y = 0,
                    w = Device2.screen:getWidth(),
                    h = Device2.screen:getHeight(),
                },
            },
        }
        function menu:onZenGroupBlankHold(arg, ges)
            local FileManager = require("apps/filemanager/filemanager")
            local fm = FileManager.instance
            if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
                local n = self.item_table and #self.item_table or 0
                local subtitle = tab_id == "authors"
                    and (n == 1 and _("1 author") or (tostring(n) .. " " .. _("authors")))
                    or  (n == 1 and _("1 series") or (tostring(n) .. " " .. _("series")))
                fm.file_chooser:showFileDialog({
                    _zen_group_files    = {},
                    _zen_group_name     = tab_id == "authors" and _("Authors") or _("Series"),
                    _zen_group_subtitle = subtitle,
                    _zen_sort_cb        = function() showGroupSortDialog(tab_id, self) end,
                    _zen_display_cb     = function() showDisplayModeDialog(self, tab_id) end,
                })
            end
            return true
        end
    end

    UIManager:show(menu)
    -- updateItems was stubbed during Menu:new to skip the premature init-time call.
    -- Trigger the real render now via nextTick, after the menu has been dimensioned.
    UIManager:nextTick(function()
        menu:updateItems()
        -- Re-inject status row after updateItems (it may reset title_group).
        local createSR2 = _zen_shared and _zen_shared.createStatusRow
        local repaintTB2 = _zen_shared and _zen_shared.repaintTitleBar
        local tb2 = menu.title_bar
        if tb2 and createSR2 and tb2.title_group and #tb2.title_group >= 2 then
            local FileManager2 = require("apps/filemanager/filemanager")
            tb2.title_group[2] = createSR2(nil, FileManager2.instance)
            tb2.title_group:resetLayout()
            if repaintTB2 then repaintTB2(tb2) end
        end
    end)
end

-------------------------------------------------------------------------------
-- Public API called by navbar.lua tab callbacks
-------------------------------------------------------------------------------
function M.showAuthorsView(injectNavbar)
    local ok, db = pcall(require, "common/db_bookinfo")
    if not ok then return end
    local groups = db.getGroupedByAuthor()
    showGroupView("authors", injectNavbar, groups)
end

function M.showSeriesView(injectNavbar)
    local ok, db = pcall(require, "common/db_bookinfo")
    if not ok then return end
    local groups = db.getGroupedBySeries()
    showGroupView("series", injectNavbar, groups)
end

-------------------------------------------------------------------------------
-- M.showTBRView: flat book list filtered to "To Be Read" (abandoned) status
-------------------------------------------------------------------------------
function M.showTBRView(injectNavbar)
    local _          = require("gettext")
    local Menu       = require("ui/widget/menu")
    local TitleBar   = require("ui/widget/titlebar")
    local UIManager  = require("ui/uimanager")
    local ReaderUI   = require("apps/reader/readerui")

    local ok, db = pcall(require, "common/db_bookinfo")
    if not ok then return end
    local files = db.getTBRBooks()

    local tab_id     = "to_be_read"
    local SORT_GROUP = "to_be_read"
    local group_name = _("To Be Read")

    local collate_key = "zen_" .. tab_id .. "_detail_collate_" .. SORT_GROUP
    local reverse_key = "zen_" .. tab_id .. "_detail_reverse_" .. SORT_GROUP
    local g_settings  = rawget(_G, "G_reader_settings")
    local cur_collate = g_settings and g_settings:readSetting(collate_key) or "title"
    local cur_reverse = g_settings and g_settings:isTrue(reverse_key) or false

    local sorted_files = sortDetailFiles(files, cur_collate, cur_reverse)

    local function buildItems(flist)
        local items = {}
        for _, fpath in ipairs(flist) do
            local fname   = fpath:match("([^/]+)$") or fpath
            local display = fname:gsub("%.[^%.]+$", "")
            table.insert(items, {
                text     = display,
                path     = fpath,
                filepath = fpath,
                is_file  = true,
            })
        end
        if #items == 0 then
            table.insert(items, {
                text     = _("No books found"),
                dim      = true,
                callback = function() end,
            })
        end
        return items
    end

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

    local menu = Menu:new{
        name               = "to_be_read",
        title              = group_name,
        covers_fullscreen  = true,
        is_borderless      = true,
        is_popout          = false,
        title_bar_fm_style = true,
        item_table         = buildItems(sorted_files),
        onMenuSelect       = function(menu_self, item)
            if item.path then
                ReaderUI:showReader(item.path)
            end
        end,
        onMenuHold         = function(menu_self, item)
            if not item.path then return end
            local FileManager = require("apps/filemanager/filemanager")
            local fm = FileManager.instance
            if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
                fm.file_chooser:showFileDialog({
                    path    = item.path,
                    is_file = true,
                    text    = item.text,
                })
            end
        end,
        updateItems        = function(menu_self, ...) end,
    }
    TitleBar.new = orig_tb_new

    local mode_type = setup_display_mode(menu, false, tab_id)
    if mode_type == "mosaic" then
        patch_mosaic_item()
    elseif mode_type == "list" then
        patch_list_item()
    elseif mode_type == "classic" or not mode_type then
        local Menu_class = require("ui/widget/menu")
        menu.updateItems = Menu_class.updateItems
    end

    menu.close_callback = function()
        UIManager:close(menu)
        _tbr_menu = nil
    end

    clean_nav(menu, group_name)

    if injectNavbar then
        injectNavbar(menu, tab_id)
    end

    _tbr_menu = menu

    local Device_tbr = require("device")
    if Device_tbr:isTouchDevice() then
        local GestureRange_tbr = require("ui/gesturerange")
        local Geom_tbr         = require("ui/geometry")
        if not menu.ges_events then
            menu.ges_events = {}
        end
        menu.ges_events.ZenTBRBlankHold = {
            GestureRange_tbr:new{
                ges   = "hold",
                range = Geom_tbr:new{
                    x = 0, y = 0,
                    w = Device_tbr.screen:getWidth(),
                    h = Device_tbr.screen:getHeight(),
                },
            },
        }
        function menu:onZenTBRBlankHold(arg, ges)
            local FileManager = require("apps/filemanager/filemanager")
            local fm = FileManager.instance
            if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
                local n = self.item_table and #self.item_table or 0
                fm.file_chooser:showFileDialog({
                    _zen_group_files    = files,
                    _zen_group_name     = group_name,
                    _zen_group_subtitle = n == 1 and _("1 book") or (tostring(n) .. " " .. _("books")),
                    _zen_sort_cb        = function()
                        showDetailSortDialog(SORT_GROUP, tab_id, self, files)
                    end,
                    _zen_display_cb     = function()
                        showDisplayModeDialog(self, tab_id)
                    end,
                })
            end
            return true
        end
    end

    UIManager:show(menu)
    UIManager:nextTick(function()
        menu:updateItems()
        local createSR2  = _zen_shared and _zen_shared.createStatusRow
        local repaintTB2 = _zen_shared and _zen_shared.repaintTitleBar
        local tb2 = menu.title_bar
        if tb2 and createSR2 and tb2.title_group and #tb2.title_group >= 2 then
            local FileManager2 = require("apps/filemanager/filemanager")
            tb2.title_group[2] = createSR2(nil, FileManager2.instance)
            tb2.title_group:resetLayout()
            if repaintTB2 then repaintTB2(tb2) end
        end
    end)
end

return function()
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then return end
    if not zen_plugin._zen_shared then zen_plugin._zen_shared = {} end
    _zen_shared  = zen_plugin._zen_shared
    _zen_plugin  = zen_plugin  -- keep reference; __ZEN_UI_PLUGIN is cleared after init
    zen_plugin._zen_shared.group_view = M
end

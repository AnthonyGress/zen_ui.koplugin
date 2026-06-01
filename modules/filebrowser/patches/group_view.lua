local logger = require("logger")
local ConfigManager = require("config/manager")
local book_status = require("common/book_status")

local M = {}

-- One-time patch guards
local _mosaic_item_patched = false
local _list_item_patched   = false

-- Active group view menus (so we can refresh them)
local _authors_menu = nil
local _series_menu  = nil
local _tbr_menu     = nil
local _tags_menu    = nil
-- Detail view menus layered on top of the group menu
local _detail_menus = {}

-- Set during apply (called at init while __ZEN_UI_PLUGIN is set)
local _zen_shared    = nil
local _zen_plugin    = nil  -- captured at init; __ZEN_UI_PLUGIN is cleared after init

local function load_zen_config()
    if _zen_plugin and type(_zen_plugin.config) == "table" then
        return _zen_plugin.config
    end
    local ok, cfg = pcall(ConfigManager.load)
    if ok and type(cfg) == "table" then
        return cfg
    end
end

local function save_zen_config(cfg)
    if type(cfg) ~= "table" then return end
    if _zen_plugin and _zen_plugin.config == cfg and type(_zen_plugin.saveConfig) == "function" then
        _zen_plugin:saveConfig()
        return
    end
    pcall(ConfigManager.save, cfg)
    if _zen_plugin and type(_zen_plugin.config) == "table" then
        _zen_plugin.config = cfg
    end
end

local function get_group_display_mode(tab_id, fallback)
    local cfg = load_zen_config()
    local group_view = cfg and cfg.group_view
    local display_mode = group_view and group_view.display_mode
    local stored = display_mode and display_mode[tab_id]
    if type(stored) == "string" and stored ~= "" then
        return stored
    end
    local g_settings = rawget(_G, "G_reader_settings")
    local legacy = g_settings and g_settings:readSetting("zen_" .. tab_id .. "_display_mode")
    if type(legacy) == "string" and legacy ~= "" then
        return legacy
    end
    return fallback
end

local function set_group_display_mode(tab_id, mode)
    if type(mode) ~= "string" or mode == "" then return end
    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    if type(cfg.group_view.display_mode) ~= "table" then cfg.group_view.display_mode = {} end
    cfg.group_view.display_mode[tab_id] = mode
    save_zen_config(cfg)
end

local function get_detail_collate(tab_id, group_name, fallback)
    local cfg = load_zen_config()
    local group_view = cfg and cfg.group_view
    local detail_collate = group_view and group_view.detail_collate
    local tab_collate = detail_collate and detail_collate[tab_id]
    local stored = tab_collate and tab_collate[group_name]
    if type(stored) == "string" and stored ~= "" then
        return stored
    end
    local g_settings = rawget(_G, "G_reader_settings")
    local legacy_key = "zen_" .. tab_id .. "_detail_collate_" .. group_name
    local legacy = g_settings and g_settings:readSetting(legacy_key)
    if type(legacy) == "string" and legacy ~= "" then
        return legacy
    end
    return fallback
end

local function set_detail_collate(tab_id, group_name, collate)
    if type(collate) ~= "string" or collate == "" then return end
    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    if type(cfg.group_view.detail_collate) ~= "table" then cfg.group_view.detail_collate = {} end
    if type(cfg.group_view.detail_collate[tab_id]) ~= "table" then
        cfg.group_view.detail_collate[tab_id] = {}
    end
    cfg.group_view.detail_collate[tab_id][group_name] = collate
    save_zen_config(cfg)
end

local function get_group_reverse(tab_id)
    local cfg = load_zen_config()
    local group_view = cfg and cfg.group_view
    local group_reverse = group_view and group_view.group_reverse
    local stored = group_reverse and group_reverse[tab_id]
    if stored ~= nil then
        return stored == true
    end
    local g_settings = rawget(_G, "G_reader_settings")
    local legacy_key = tab_id == "authors" and "zen_authors_reverse"
        or (tab_id == "series" and "zen_series_reverse" or nil)
    if legacy_key and g_settings then
        return g_settings:isTrue(legacy_key)
    end
    return false
end

local function set_group_reverse(tab_id, reverse)
    if tab_id ~= "authors" and tab_id ~= "series" then return end
    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    if type(cfg.group_view.group_reverse) ~= "table" then
        cfg.group_view.group_reverse = {}
    end
    cfg.group_view.group_reverse[tab_id] = reverse == true
    save_zen_config(cfg)
end

local function get_tags_global_collate()
    local cfg = load_zen_config()
    local group_view = cfg and cfg.group_view
    local tags_global = group_view and group_view.tags_global
    local stored = tags_global and tags_global.collate
    if type(stored) == "string" and stored ~= "" then
        return stored
    end
    local g_settings = rawget(_G, "G_reader_settings")
    local legacy = g_settings and g_settings:readSetting("zen_tags_global_collate")
    if type(legacy) == "string" and legacy ~= "" then
        return legacy
    end
    return "title"
end

local function set_tags_global_collate(collate)
    if type(collate) ~= "string" or collate == "" then return end
    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    if type(cfg.group_view.tags_global) ~= "table" then
        cfg.group_view.tags_global = {}
    end
    cfg.group_view.tags_global.collate = collate
    save_zen_config(cfg)
end

local function is_tags_global_reverse()
    local cfg = load_zen_config()
    local group_view = cfg and cfg.group_view
    local tags_global = group_view and group_view.tags_global
    if tags_global and tags_global.reverse ~= nil then
        return tags_global.reverse == true
    end
    local g_settings = rawget(_G, "G_reader_settings")
    return g_settings and g_settings:isTrue("zen_tags_global_reverse") or false
end

local function set_tags_global_reverse(reverse)
    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    if type(cfg.group_view.tags_global) ~= "table" then
        cfg.group_view.tags_global = {}
    end
    cfg.group_view.tags_global.reverse = reverse == true
    save_zen_config(cfg)
end

local function get_detail_reverse(tab_id, group_name, fallback)
    local cfg = load_zen_config()
    local group_view = cfg and cfg.group_view
    local detail_reverse = group_view and group_view.detail_reverse
    local tab_reverse = detail_reverse and detail_reverse[tab_id]
    local stored = tab_reverse and tab_reverse[group_name]
    if stored ~= nil then
        return stored == true
    end
    local g_settings = rawget(_G, "G_reader_settings")
    local legacy_key = "zen_" .. tab_id .. "_detail_reverse_" .. group_name
    local legacy = g_settings and g_settings:readSetting(legacy_key)
    if legacy ~= nil then
        return legacy == true
    end
    return fallback == true
end

local function set_detail_reverse(tab_id, group_name, reverse)
    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    if type(cfg.group_view) ~= "table" then cfg.group_view = {} end
    if type(cfg.group_view.detail_reverse) ~= "table" then
        cfg.group_view.detail_reverse = {}
    end
    if type(cfg.group_view.detail_reverse[tab_id]) ~= "table" then
        cfg.group_view.detail_reverse[tab_id] = {}
    end
    if reverse then
        cfg.group_view.detail_reverse[tab_id][group_name] = true
    else
        cfg.group_view.detail_reverse[tab_id][group_name] = nil
    end
    save_zen_config(cfg)
end

-- True when up-folder items should be shown (mirrors browser_hide_up_folder config).
local function should_show_up_folder()
    local p = _zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
    if not p or type(p.config) ~= "table" then return true end
    local features = p.config.features
    -- Feature not enabled -> default KOReader behaviour: show up folder.
    if type(features) ~= "table" or not features.browser_hide_up_folder then return true end
    local cfg = p.config.browser_hide_up_folder
    -- Feature enabled; default is hide=true. Only show when explicitly set to false.
    return type(cfg) == "table" and cfg.hide_up_folder == false
end

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
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim then
        menu.display_mode_type = "classic"
        return "classic"
    end
    local display_mode
    if tab_id then
        display_mode = get_group_display_mode(tab_id, "list_image_meta")
    else
        display_mode = BookInfoManager:getSetting("filemanager_display_mode")
    end
    if is_group_view then
        menu._zen_group_view = true
    end

    if not display_mode then
        menu.display_mode_type = "classic"
        return "classic"
    end

    local ok_cm, CoverMenu = pcall(require, "covermenu")
    if not ok_cm then
        menu.display_mode_type = "classic"
        return "classic"
    end

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
                local stats   = doc:readSetting("stats")
                return {
                    been_opened      = true,
                    percent_finished = doc:readSetting("percent_finished"),
                    status           = summary and summary.status,
                    pages            = stats and stats.pages,
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
    local CoverUtils      = require("common/cover_utils")

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
        -- Up-folder item in a group view: render as a folder-cover-style placeholder.
        if self.menu and self.menu._zen_group_view and self.entry and self.entry.is_go_up then
            self._foldercover_processed = true
            if self._setFolderCover then
                self:_setFolderCover { no_image = true }
            else
                -- Inline fallback: portrait-shaped gray placeholder.
                local Blitbuffer2     = require("ffi/blitbuffer")
                local CenterContainer2 = require("ui/widget/container/centercontainer")
                local FrameContainer2  = require("ui/widget/container/framecontainer")
                local OverlapGroup2    = require("ui/widget/overlapgroup")
                local Size2            = require("ui/size")
                local VerticalGroup2   = require("ui/widget/verticalgroup")
                local VerticalSpan2    = require("ui/widget/verticalspan")
                local border   = Size2.border.thin
                local max_w    = self.width  - 2 * border
                local bh       = self.height - 2 * border
                local pw, ph
                local _ratio = CoverUtils.getRatio()
                if bh * _ratio <= max_w then
                    ph = bh; pw = math.floor(bh * _ratio)
                else
                    pw = max_w; ph = math.min(math.floor(max_w / _ratio), bh)
                end
                local frame = FrameContainer2:new{
                    padding = 0, bordersize = border,
                    width = pw + 2 * border, height = ph + 2 * border,
                    background = Blitbuffer2.COLOR_LIGHT_GRAY,
                    overlap_align = "center",
                    CenterContainer2:new{
                        dimen = { w = pw, h = ph },
                        VerticalSpan2:new{ width = 1 },
                    },
                }
                local top = math.floor((self.height - ph - 2 * border) / 2)
                if self._underline_container[1] then
                    self._underline_container[1]:free()
                end
                self._underline_container[1] = OverlapGroup2:new{
                    dimen = { w = self.width, h = self.height },
                    VerticalGroup2:new{
                        VerticalSpan2:new{ width = top },
                        CenterContainer2:new{
                            dimen = { w = self.width, h = ph + 2 * border },
                            frame,
                        },
                    },
                }
            end
            return
        end

        if not (self.menu and self.menu._zen_group_view
                and self.entry and self.entry._zen_files) then
            return orig_update(self, ...)
        end

        self.is_directory = true

        local files      = self.entry._zen_files
        local book_count = #files
        local mode, max_covers = CoverUtils.getMode()
        local is_gallery = mode == "gallery"
        local is_stack   = mode == "stack"
        -- Pre-compute portrait dims for per-slot fake cover generation
        local _Size_pre = require("ui/size")
        local _bdr_pre  = _Size_pre.border.thin
        local _mw_pre   = self.width  - 2 * _bdr_pre
        local _bh_pre   = self.height - 2 * _bdr_pre
        local _rat_pre  = CoverUtils.getRatio()
        local _pw_pre, _ph_pre
        if _bh_pre * _rat_pre <= _mw_pre then
            _ph_pre = _bh_pre; _pw_pre = math.floor(_bh_pre * _rat_pre)
        else
            _pw_pre = _mw_pre; _ph_pre = math.min(math.floor(_mw_pre / _rat_pre), _bh_pre)
        end

        local covers = {}
        for i = 1, math.min(book_count, max_covers) do
            local bi = BookInfoManager:getBookInfo(files[i], true)
            if bi and bi.cover_bb and bi.has_cover
                    and bi.cover_fetched and not bi.ignore_cover then
                table.insert(covers, {
                    data = bi.cover_bb:copy(),
                    w    = bi.cover_w,
                    h    = bi.cover_h,
                })
            else
                local gen_bb, gen_w, gen_h = CoverUtils.genCover(files[i], _pw_pre, _ph_pre)
                if gen_bb then
                    table.insert(covers, { data = gen_bb, w = gen_w, h = gen_h })
                end
            end
        end

        -- Delegate to browser_folder_cover's method when available.
        if self._setFolderCover then
            if is_gallery then
                self:_setFolderCover{ gallery = covers, book_count = book_count }
            elseif is_stack then
                self:_setFolderCover{ stack = covers, book_count = book_count }
            elseif #covers > 0 then
                self:_setFolderCover{ data = covers[1].data, w = covers[1].w, h = covers[1].h, book_count = book_count }
            else
                self:_setFolderCover{ no_image = true, book_count = book_count }
            end
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
        local _ratio = CoverUtils.getRatio()
        if bh * _ratio <= max_w then
            portrait_h = bh
            portrait_w = math.floor(bh * _ratio)
        else
            portrait_w = max_w
            portrait_h = math.min(math.floor(max_w / _ratio), bh)
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
        local image_widget
        if is_stack then
            image_widget = CoverUtils.drawStack(covers, portrait_w, portrait_h, border)
        else
            image_widget = FrameContainer:new{
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
        end
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
    local CoverUtils      = require("common/cover_utils")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device          = require("device")
    local library_font    = require("common/library_font")
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

    -- Save pre-patch update so BLL (if it runs later and wraps our function)
    -- is still called for non-group items regardless of init order.
    ListMenuItem._zen_gv_orig = ListMenuItem.update

    function ListMenuItem:update(...)
        if not (self.menu and self.menu._zen_group_view
                and self.entry and self.entry._zen_files) then
            -- Use the live fallthrough so BLL's patch is honoured even if it
            -- ran after our install (Android timing issue).
            local fallthrough = ListMenuItem._zen_gv_orig
            return fallthrough(self, ...)
        end

        self.is_directory = true

        local files      = self.entry._zen_files
        local book_count = #files
        local display_name = self.entry.text or ""

        local underline_h  = 1
        local dimen_h      = self.height - 2 * underline_h
        local border_size  = Size.border.thin
        local cover_v_pad  = Screen:scaleBySize(4)  -- matches bll top+bottom padding
        local cover_zone_w = dimen_h
        local max_img      = dimen_h - 2 * border_size - 2 * cover_v_pad
        local cover_w      = math.floor(max_img * CoverUtils.getRatio())

        local function _fontSize(nominal, max_size)
            local scale = library_font.getScale(18)
            local fs = math.floor(nominal * dimen_h * (1 / 64) / scale_by_size * scale + 0.5)
            if max_size then
                local max_scaled = math.max(1, math.floor(max_size * scale + 0.5))
                if fs >= max_scaled then return max_scaled end
            end
            return fs
        end

        local wleft
        if self.do_cover_image then
            local mode, max_covers = CoverUtils.getMode()
            local gallery_mode = mode == "gallery"
            local stack_mode   = mode == "stack"
            local covers       = {}
            for i = 1, #files do
                local bi = BookInfoManager:getBookInfo(files[i], true)
                if bi and bi.cover_bb and bi.has_cover
                        and bi.cover_fetched and not bi.ignore_cover then
                    table.insert(covers, { data = bi.cover_bb:copy() })
                else
                    local gen_bb = CoverUtils.genCover(files[i], cover_w, max_img)
                    if gen_bb then
                        table.insert(covers, { data = gen_bb })
                    end
                end
                if #covers >= max_covers then break end
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
            elseif stack_mode then
                cover_frame = CoverUtils.drawStack(covers, cover_w, max_img, border_size)
                if #covers > 0 then
                    self.menu._has_cover_images = true
                    self._has_cover_image = true
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

        local pad_left    = self.do_cover_image and Screen:scaleBySize(6) or Screen:scaleBySize(10)
        local pad_right   = Screen:scaleBySize(10)
        local fs_title    = _fontSize(18, 21)
        local fs_meta     = _fontSize(14, 18)
        local left_offset = self.do_cover_image and (cover_zone_w + pad_left) or pad_left

        local count_str = tostring(book_count) .. " " .. (book_count == 1 and "book" or "books")
        local wright_status = TextWidget:new{
            text    = count_str,
            face    = library_font.getFace(fs_meta),
            fgcolor = Blitbuffer.COLOR_GRAY_3,
            padding = 0,
        }
        local wright_w = wright_status:getWidth()
        local main_w = math.max(1, self.width - left_offset - wright_w - 2 * pad_right)

        local wtitle = TextBoxWidget:new{
            text      = BD.auto(display_name),
            face      = library_font.getFace(fs_title),
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
-- install_gesture_passthrough: delegate swipe/multiswipe to FileManager so
-- user-configured KOReader dispatcher gestures fire from within group views.
-- Always returns true to prevent Menu's default swipe-to-close / pagination.
-------------------------------------------------------------------------------
local function install_gesture_passthrough(menu)
    local function forward(ges)
        local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
        if ok_fm and FM and FM.instance then
            FM.instance:onGesture(ges)
        end
    end

    -- Override onGesture: let Menu handle its own gestures first (item taps via
    -- children, swipe pagination, top-swipe menu). For anything Menu doesn't
    -- consume, forward to FileManager's gesture dispatcher so user-configured
    -- Dispatcher gestures (corner taps, etc.) still fire.
    local _orig_onGesture = menu.onGesture
    function menu:onGesture(ges)
        local consumed = _orig_onGesture and _orig_onGesture(self, ges)
        if not consumed then
            forward(ges)
        end
        return true
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
    for _i, group in ipairs(groups) do
        local files
        if data_type == "authors" or data_type == "tags" then
            files = group.files
        else
            -- series items: extract file paths in order
            files = {}
            for _j, item in ipairs(group.items) do
                table.insert(files, item.file)
            end
        end
        local display = (group.author or group.series or group.tag or "?"):gsub("\n", ", ")
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

    -- Apply reverse sort if enabled (authors / series only; tags use per-group or global book sort)
    if (data_type == "authors" or data_type == "series") and get_group_reverse(data_type) and #items > 0 then
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
        cur_mode = get_group_display_mode(tab_id, "list_image_meta")
    elseif ok_bim and bim then
        local ok3, m = pcall(function()
            return bim:getSetting("filemanager_display_mode")
        end)
        if ok3 then cur_mode = m end
    end

    local function apply_mode(mode)
        if tab_id then
            set_group_display_mode(tab_id, mode)
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
-- tab_id: "authors" | "series" | "tags"
-- menu: the Menu instance to refresh after sort change
-------------------------------------------------------------------------------
local function showGroupSortDialog(tab_id, menu)
    local _ = require("gettext")

    -- Tags: show the same rich sort dialog as the detail view;
    -- settings are stored in zen_ui_config and used as defaults for tag detail views.
    if tab_id == "tags" then
        local ButtonDialog = require("ui/widget/buttondialog")
        local UIManager    = require("ui/uimanager")

        local cur_collate = get_tags_global_collate()
        local cur_reverse = is_tags_global_reverse()

        local SORT_OPTIONS = {
            { key = "series_index", text = "\u{F0CB}  " .. _("Series number") },
            { key = "title",        text = "\u{F031}  " .. _("Title") },
            { key = "access",       text = "\u{F073}  " .. _("Recently read") },
        }

        local sort_dialog
        local sort_buttons = {}
        for _i, opt in ipairs(SORT_OPTIONS) do
            local is_active = cur_collate == opt.key
            table.insert(sort_buttons, {{
                text     = opt.text .. (is_active and "  \u{2713}" or ""),
                align    = "left",
                enabled  = not is_active,
                callback = function()
                    set_tags_global_collate(opt.key)
                    UIManager:close(sort_dialog)
                end,
            }})
        end
        table.insert(sort_buttons, {{
            text     = "\u{F0DC}  " .. _("Order") .. "  \u{25B6}",
            align    = "left",
            callback = function()
                UIManager:close(sort_dialog)
                local order_dialog
                order_dialog = ButtonDialog:new{
                    title       = _("Sort order"),
                    title_align = "center",
                    buttons     = {
                        {{
                            text     = "\u{F15D}  " .. _("Ascending") .. (not cur_reverse and "  \u{2713}" or ""),
                            align    = "left",
                            enabled  = cur_reverse,
                            callback = function()
                                set_tags_global_reverse(false)
                                UIManager:close(order_dialog)
                            end,
                        }},
                        {{
                            text     = "\u{F15E}  " .. _("Descending") .. (cur_reverse and "  \u{2713}" or ""),
                            align    = "left",
                            enabled  = not cur_reverse,
                            callback = function()
                                set_tags_global_reverse(true)
                                UIManager:close(order_dialog)
                            end,
                        }},
                    },
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
        return
    end

    local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
    local fm = ok_fm and FM and FM.instance
    if not fm then return end

    local title        = tab_id == "authors" and _("Sort authors") or _("Sort series")

    fm.file_chooser:showSortOrderDialog({
        title           = title,
        current_reverse = get_group_reverse(tab_id),
        on_select       = function(reverse)
            set_group_reverse(tab_id, reverse)
            if menu then
                local ok, db = pcall(require, "common/db_bookinfo")
                if ok then
                    local groups
                    if tab_id == "authors" then
                        groups = db.getGroupedByAuthor()
                    elseif tab_id == "tags" then
                        groups = db.getGroupedByTags()
                    else
                        groups = db.getGroupedBySeries()
                    end
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
        elseif collate == "series_index" then
            -- Numeric; books without an index sort last.
            sort_key = (bookinfo and tonumber(bookinfo.series_index)) or math.huge
        elseif collate == "series" then
            sort_key = (bookinfo and bookinfo.series) or ""
        elseif collate == "access" then
            -- Use file access time, which KOReader updates via lfs.touch() on each open.
            local lfs = require("libs/libkoreader-lfs")
            sort_key = lfs.attributes(fpath, "access") or 0
        else
            sort_key = fpath:match("([^/]+)$") or fpath
        end

        table.insert(items, { path = fpath, key = sort_key })
    end

    -- Sort by key
    table.sort(items, function(a, b)
        if collate == "series_index" or collate == "access" then
            -- Numeric comparison; for access higher = more recent so invert.
            local a_n = type(a.key) == "number" and a.key or 0
            local b_n = type(b.key) == "number" and b.key or 0
            if collate == "access" then
                if reverse then return a_n < b_n else return a_n > b_n end
            else
                if reverse then return a_n > b_n else return a_n < b_n end
            end
        else
            -- Alphabetical for title/series
            local a_lower = type(a.key) == "string" and a.key:lower() or tostring(a.key)
            local b_lower = type(b.key) == "string" and b.key:lower() or tostring(b.key)
            if reverse then return a_lower > b_lower else return a_lower < b_lower end
        end
    end)

    -- Extract sorted paths
    local sorted = {}
    for _, item in ipairs(items) do
        table.insert(sorted, item.path)
    end

    return sorted
end

-- Filter a file list to only those matching FileChooser.show_filter.status.
-- Returns the original list unchanged when no filter is active.
local function apply_status_filter(files)
    local ok_fc, FileChooser = pcall(require, "ui/widget/filechooser")
    if not ok_fc then return files end
    local status_filter = FileChooser.show_filter and FileChooser.show_filter.status
    if not status_filter then return files end
    local filtered = {}
    for _i, fpath in ipairs(files) do
        local effective_status = book_status.getEffectiveStatusFromFile(fpath)
        if status_filter[effective_status] then
            table.insert(filtered, fpath)
        end
    end
    return filtered
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

    local default_collate
    if tab_id == "series" then
        default_collate = "series_index"
    elseif tab_id == "tags" then
        default_collate = get_tags_global_collate()
    else
        default_collate = "title"
    end
    local cur_collate = get_detail_collate(tab_id, group_name, default_collate)
    local reverse_fallback = tab_id == "tags" and is_tags_global_reverse() or false
    local cur_reverse = get_detail_reverse(tab_id, group_name, reverse_fallback)

    local SORT_OPTIONS = {
        { key = "series_index", text = "\u{F0CB}  " .. _("Series number") },
        { key = "title",        text = "\u{F031}  " .. _("Title") },
        { key = "access",       text = "\u{F073}  " .. _("Recently read") },
    }

    local function rebuildMenu(collate, reverse)
        if not (menu and files) then return end

        local sorted_files = sortDetailFiles(files, collate, reverse)
        sorted_files = apply_status_filter(sorted_files)

        local book_items = {}
        for _, fpath in ipairs(sorted_files) do
            local fname = fpath:match("([^/]+)$") or fpath
            local display = fname:gsub("%.[^%.]+$", "")

            table.insert(book_items, {
                text = display,
                path = fpath,
                is_file = true,
            })
        end

        if should_show_up_folder() then
            table.insert(book_items, 1, { text = "\u{2B06} ..", is_go_up = true, mandatory = "" })
        end

        menu.item_table = book_items
        menu:updateItems()
    end

    local sort_dialog
    local sort_buttons = {}

    -- Add collate field options
    for _i, opt in ipairs(SORT_OPTIONS) do
        local is_active = cur_collate == opt.key
        table.insert(sort_buttons, {{
            text     = opt.text .. (is_active and "  \u{2713}" or ""),
            align    = "left",
            enabled  = not is_active,
            callback = function()
                set_detail_collate(tab_id, group_name, opt.key)
                UIManager:close(sort_dialog)
                rebuildMenu(opt.key, cur_reverse)
            end,
        }})
    end

    -- Order submenu
    table.insert(sort_buttons, {{
        text     = "\u{F0DC}  " .. _("Order") .. "  ▶",
        align    = "left",
        callback = function()
            UIManager:close(sort_dialog)
            local order_dialog
            local order_buttons = {
                {{
                    text     = "\u{F15D}  " .. _("Ascending") .. (not cur_reverse and "  \u{2713}" or ""),
                    align    = "left",
                    enabled  = cur_reverse,
                    callback = function()
                        set_detail_reverse(tab_id, group_name, false)
                        UIManager:close(order_dialog)
                        rebuildMenu(cur_collate, false)
                    end,
                }},
                {{
                    text     = "\u{F15E}  " .. _("Descending") .. (cur_reverse and "  \u{2713}" or ""),
                    align    = "left",
                    enabled  = not cur_reverse,
                    callback = function()
                        set_detail_reverse(tab_id, group_name, true)
                        UIManager:close(order_dialog)
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
-- show_file_dialog_with_refresh: call fc:showFileDialog(item) but also
-- refresh menu_self after a status change (which triggers fc:refreshPath).
-- One-shot wrapper: restores the original after first call or on next refresh.
-------------------------------------------------------------------------------
local function show_file_dialog_with_refresh(fc, menu_self, item)
    local orig = fc.refreshPath
    fc.refreshPath = function(self2, ...)
        fc.refreshPath = orig  -- restore before doing anything
        orig(self2, ...)
        local UIManager2 = require("ui/uimanager")
        local is_shown
        if type(UIManager2.isShown) == "function" then
            is_shown = UIManager2:isShown(menu_self)
        else
            -- Fallback for older KOReader: scan window stack directly
            is_shown = false
            if type(UIManager2._window_stack) == "table" then
                for _, entry in ipairs(UIManager2._window_stack) do
                    if entry.widget == menu_self then is_shown = true; break end
                end
            end
        end
        if is_shown then
            menu_self:updateItems()
        end
    end
    fc:showFileDialog(item)
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

    local files      = group_item._zen_files or {}
    local group_name = group_item.text or ""
    local detail_name
    if tab_id == "authors" then
        detail_name = "authors_detail"
    elseif tab_id == "tags" then
        detail_name = "tags_detail"
    else
        detail_name = "series_detail"
    end

    -- Get sort settings for this group
    -- Series defaults to series_index; tags fall back to the global tags sort setting;
    -- authors default to title.
    local default_collate
    if tab_id == "series" then
        default_collate = "series_index"
    elseif tab_id == "tags" then
        default_collate = get_tags_global_collate()
    else
        default_collate = "title"
    end
    local cur_collate = get_detail_collate(tab_id, group_name, default_collate)
    local reverse_fallback = tab_id == "tags" and is_tags_global_reverse() or false
    local cur_reverse = get_detail_reverse(tab_id, group_name, reverse_fallback)

    -- Sort files based on current settings
    local sorted_files = sortDetailFiles(files, cur_collate, cur_reverse)
    sorted_files = apply_status_filter(sorted_files)

    -- Build menu items from sorted files
    local lfs_mod  = require("libs/libkoreader-lfs")
    local util_mod = require("util")
    local book_items = {}
    for _i, fpath in ipairs(sorted_files) do
        local fname = fpath:match("([^/]+)$") or fpath
        local display = fname:gsub("%.[^%.]+$", "")
        local attr = lfs_mod.attributes(fpath)
        table.insert(book_items, {
            text      = display,
            path      = fpath,
            filepath  = fpath,
            is_file   = true,
            mandatory = attr and util_mod.getFriendlySize(attr.size or 0) or "",
        })
    end
    if #book_items == 0 then
        table.insert(book_items, {
            text = _("No books found"),
            dim  = true,
            callback = function() end,
        })
    end
    if should_show_up_folder() then
        table.insert(book_items, 1, { text = "\u{2B06} ..", is_go_up = true, mandatory = "" })
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
            if item.is_go_up then
                if menu_self.close_callback then menu_self.close_callback()
                else UIManager:close(menu_self) end
                return
            end
            if item.path then
                local FileManager = require("apps/filemanager/filemanager")
                local fm = FileManager.instance
                local fmu = require("apps/filemanager/filemanagerutil")
                if fmu.openFile then
                    fmu.openFile(fm, item.path)
                elseif fm then
                    fm:openFile(item.path)
                end
            end
        end,
        onMenuHold         = function(menu_self, item)
            if not item.path then return end
            local FileManager = require("apps/filemanager/filemanager")
            local fm = FileManager.instance
            if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
                show_file_dialog_with_refresh(fm.file_chooser, menu_self, {
                    path    = item.path,
                    is_file = true,
                    text    = item.text,
                })
            end
        end,
        updateItems        = function(menu_self, ...) end,  -- prevent default pagination
    }
    TitleBar.new = orig_tb_new

    -- Suppress the invisible page-info tap target ("go to letter/page" dialog)
    if detail_menu.page_info_text then
        detail_menu.page_info_text.tap_input  = nil
        detail_menu.page_info_text.hold_input = nil
    end

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

    table.insert(_detail_menus, detail_menu)
    detail_menu._zen_group_name = group_name
    detail_menu._zen_tab_id     = tab_id
    detail_menu.close_callback = function()
        UIManager:close(detail_menu)
        for i, m in ipairs(_detail_menus) do
            if m == detail_menu then table.remove(_detail_menus, i); break end
        end
    end

    -- Close the parent group menu too (used by navbar tap to unwind the full stack)
    detail_menu._zen_close_stack = function()
        local parent
        if tab_id == "authors" then
            parent = _authors_menu
        elseif tab_id == "tags" then
            parent = _tags_menu
        else
            parent = _series_menu
        end
        if parent then
            UIManager:close(parent)
            if tab_id == "authors" then _authors_menu = nil
            elseif tab_id == "tags" then _tags_menu = nil
            else _series_menu = nil end
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
                    _zen_group_files       = sorted_files,
                    _zen_group_name        = group_name,
                    _zen_is_folder_view    = true,
                    _zen_sort_cb           = function()
                        showDetailSortDialog(group_name, tab_id, self, files)
                    end,
                    _zen_display_cb        = function()
                        showDisplayModeDialog(self, tab_id)
                    end,
                    _zen_filter_refresh_cb = function()
                        -- Rebuild item_table with new filter: close and reopen.
                        UIManager:close(detail_menu)
                        showDetailView(group_item, injectNavbar, tab_id)
                    end,
                })
            end
            return true
        end
    end
    UIManager:show(detail_menu)
    UIManager:nextTick(function()
        -- Restore page if returning from reader (detail view was open)
        local dstate = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
        if dstate and dstate.detail_group == group_name then
            detail_menu.page = dstate.detail_page or 1
            _G.__ZEN_UI_LIBRARY_STATE = nil
        end
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

    local title
    if tab_id == "authors" then
        title = _("Authors")
    elseif tab_id == "tags" then
        title = _("Tags")
    else
        title = _("Series")
    end
    local item_table = build_group_item_table(groups, tab_id)
    -- No up-folder at the root group list level.

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
            if item.is_go_up then
                if menu_self.close_callback then menu_self.close_callback()
                else UIManager:close(menu_self) end
                return
            end
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
                            showDetailSortDialog(item.text, tab_id, nil, item._zen_files)
                        end,
                        _zen_display_cb  = function()
                            showDisplayModeDialog(menu_self, tab_id)
                        end,
                    })
                end
            end
        end,
        updateItems        = function(menu_self, ...) end,  -- prevent default pagination
    }
    TitleBar.new = orig_tb_new

    -- Suppress the invisible page-info tap target ("go to letter/page" dialog)
    if menu.page_info_text then
        menu.page_info_text.tap_input  = nil
        menu.page_info_text.hold_input = nil
    end

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

    install_gesture_passthrough(menu)

    menu.close_callback = function()
        UIManager:close(menu)
        if tab_id == "authors" then
            _authors_menu = nil
        elseif tab_id == "tags" then
            _tags_menu = nil
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
    elseif tab_id == "tags" then
        _tags_menu = menu
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
                local subtitle
                if tab_id == "authors" then
                    subtitle = n == 1 and _("1 author") or (tostring(n) .. " " .. _("authors"))
                elseif tab_id == "tags" then
                    subtitle = n == 1 and _("1 tag") or (tostring(n) .. " " .. _("tags"))
                else
                    subtitle = n == 1 and _("1 series") or (tostring(n) .. " " .. _("series"))
                end
                local group_label
                if tab_id == "authors" then
                    group_label = _("Authors")
                elseif tab_id == "tags" then
                    group_label = _("Tags")
                else
                    group_label = _("Series")
                end
                fm.file_chooser:showFileDialog({
                    _zen_group_files    = {},
                    _zen_group_name     = group_label,
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
        -- Restore page if returning from reader
        local state = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
        local restore_detail = state and state.tab == tab_id and state.detail_group
        if state and state.tab == tab_id then
            menu.page = state.page or 1
        end
        if not restore_detail then
            _G.__ZEN_UI_LIBRARY_STATE = nil
        end
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
        -- Re-open the specific group folder that was open before reader.
        -- Guard: showFiles post-hook may have already opened it synchronously.
        if restore_detail then
            local detail_name = state.detail_group
            local already_open = false
            for _, dm in ipairs(_detail_menus) do
                if dm._zen_group_name == detail_name then already_open = true; break end
            end
            if not already_open then
                UIManager:nextTick(function()
                    for _, item in ipairs(item_table) do
                        if item.text == detail_name and item._zen_files then
                            showDetailView(item, injectNavbar, tab_id)
                            break
                        end
                    end
                end)
            end
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

function M.showTagsView(injectNavbar)
    local ok, db = pcall(require, "common/db_bookinfo")
    if not ok then return end
    local groups = db.getGroupedByTags()
    showGroupView("tags", injectNavbar, groups)
end

-------------------------------------------------------------------------------
-- M.showTBRView: flat book list filtered to "To Be Read" (abandoned) status
-------------------------------------------------------------------------------
function M.showTBRView(injectNavbar)
    local _          = require("gettext")
    local Menu       = require("ui/widget/menu")
    local TitleBar   = require("ui/widget/titlebar")
    local UIManager  = require("ui/uimanager")

    local ok, db = pcall(require, "common/db_bookinfo")
    if not ok then return end
    local files = db.getTBRBooks()

    local tab_id     = "to_be_read"
    local SORT_GROUP = "to_be_read"
    local group_name = _("To Be Read")

    local cur_collate = get_detail_collate(tab_id, SORT_GROUP, "title")
    local cur_reverse = get_detail_reverse(tab_id, SORT_GROUP, false)

    local sorted_files = sortDetailFiles(files, cur_collate, cur_reverse)
    sorted_files = apply_status_filter(sorted_files)

    local function buildItems(flist)
        local lfs_mod  = require("libs/libkoreader-lfs")
        local util_mod = require("util")
        local items = {}
        for _i, fpath in ipairs(flist) do
            local fname   = fpath:match("([^/]+)$") or fpath
            local display = fname:gsub("%.[^%.]+$", "")
            local attr = lfs_mod.attributes(fpath)
            table.insert(items, {
                text      = display,
                path      = fpath,
                filepath  = fpath,
                is_file   = true,
                mandatory = attr and util_mod.getFriendlySize(attr.size or 0) or "",
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
        item_table         = (function()
            local items = buildItems(sorted_files)
            if should_show_up_folder() then
                table.insert(items, 1, { text = "\u{2B06} ..", is_go_up = true, mandatory = "" })
            end
            return items
        end)(),
        onMenuSelect       = function(menu_self, item)
            if item.is_go_up then
                if menu_self.close_callback then menu_self.close_callback()
                else UIManager:close(menu_self) end
                return
            end
            if item.path then
                local FileManager = require("apps/filemanager/filemanager")
                local fm = FileManager.instance
                local fmu = require("apps/filemanager/filemanagerutil")
                if fmu.openFile then
                    fmu.openFile(fm, item.path)
                elseif fm then
                    fm:openFile(item.path)
                end
            end
        end,
        onMenuHold         = function(menu_self, item)
            if not item.path then return end
            local FileManager = require("apps/filemanager/filemanager")
            local fm = FileManager.instance
            if fm and fm.file_chooser and fm.file_chooser.showFileDialog then
                show_file_dialog_with_refresh(fm.file_chooser, menu_self, {
                    path    = item.path,
                    is_file = true,
                    text    = item.text,
                })
            end
        end,
        updateItems        = function(menu_self, ...) end,
    }
    TitleBar.new = orig_tb_new

    -- Suppress the invisible page-info tap target ("go to letter/page" dialog)
    if menu.page_info_text then
        menu.page_info_text.tap_input  = nil
        menu.page_info_text.hold_input = nil
    end

    -- Tag TBR as a real-book-list menu so _zen_update_impl in browser_folder_cover
    -- doesn't suppress covers the way it does for non-FM dialogs (e.g. screensaver picker).
    menu._zen_tab_id = tab_id

    local mode_type = setup_display_mode(menu, false, tab_id)
    if mode_type == "mosaic" then
        patch_mosaic_item()
    elseif mode_type == "list" then
        patch_list_item()
    elseif mode_type == "classic" or not mode_type then
        local Menu_class = require("ui/widget/menu")
        menu.updateItems = Menu_class.updateItems
    end

    install_gesture_passthrough(menu)

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
        -- Restore page if returning from reader
        local state = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
        if state and state.tab == "to_be_read" and state.page and state.page > 1 then
            menu.page = state.page
            _G.__ZEN_UI_LIBRARY_STATE = nil
        end
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

-- Open a detail view synchronously by group name (used by navbar.showFiles post-hook).
-- Called after showGroupView so _authors_menu/_series_menu is already set.
function M.restoreDetail(group_name, tab_id, injectNavbar_fn)
    local menu = tab_id == "authors" and _authors_menu or _series_menu
    if not menu or not menu.item_table then return end
    for _, item in ipairs(menu.item_table) do
        if item.text == group_name and item._zen_files then
            showDetailView(item, injectNavbar_fn, tab_id)
            return
        end
    end
end

-- Return the top-most open detail view info (group name, tab, page)
function M.getActiveDetail()
    if #_detail_menus > 0 then
        local m = _detail_menus[#_detail_menus]
        return { group_name = m._zen_group_name, tab_id = m._zen_tab_id, page = m.page or 1 }
    end
end

-- Return the current page of a group menu (for state save on reader open)
function M.getActivePage(tab_id)
    if tab_id == "authors" and _authors_menu then
        return _authors_menu.page
    elseif tab_id == "series" and _series_menu then
        return _series_menu.page
    elseif tab_id == "to_be_read" and _tbr_menu then
        return _tbr_menu.page
    elseif tab_id == "tags" and _tags_menu then
        return _tags_menu.page
    end
end

-- Close all open group/detail menus to prevent UIManager stack pollution
function M.closeAll()
    local UIManager2 = require("ui/uimanager")
    for _, m in ipairs(_detail_menus) do
        UIManager2:close(m)
    end
    _detail_menus = {}
    if _authors_menu then UIManager2:close(_authors_menu); _authors_menu = nil end
    if _series_menu  then UIManager2:close(_series_menu);  _series_menu  = nil end
    if _tbr_menu     then UIManager2:close(_tbr_menu);     _tbr_menu     = nil end
    if _tags_menu    then UIManager2:close(_tags_menu);    _tags_menu    = nil end
end

return function()
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    if not zen_plugin or type(zen_plugin.config) ~= "table" then return end
    if not zen_plugin._zen_shared then zen_plugin._zen_shared = {} end
    _zen_shared  = zen_plugin._zen_shared
    _zen_plugin  = zen_plugin  -- keep reference; __ZEN_UI_PLUGIN is cleared after init
    zen_plugin._zen_shared.group_view = M
end

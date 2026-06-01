local function apply_browser_folder_cover()
    -- Capture plugin reference at apply-time.
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local Cover = require("common/cover_utils")

    local AlphaContainer = require("ui/widget/container/alphacontainer")
    local BD = require("ui/bidi")
    local Blitbuffer = require("ffi/blitbuffer")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local FileChooser = require("ui/widget/filechooser")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local ImageWidget = require("ui/widget/imagewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local TopContainer = require("ui/widget/container/topcontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local lfs = require("libs/libkoreader-lfs")
    local paths = require("common/paths")
    local library_font = require("common/library_font")
    local utils = require("common/utils")

    local _ = require("gettext")
    local Screen = Device.screen

    local function getMenuItem(menu, ...)
        local function findItem(sub_items, texts)
            local find = {}
            local text_list = type(texts) == "table" and texts or { texts }
            for _, text in ipairs(text_list) do find[text] = true end
            for _, item in ipairs(sub_items) do
                local text = item.text or (item.text_func and item.text_func())
                if text and find[text] then return item end
            end
        end

        local sub_items, item
        for _, texts in ipairs { ... } do
            sub_items = (item or menu).sub_item_table
            if not sub_items then return end
            item = findItem(sub_items, texts)
            if not item then return end
        end
        return item
    end

    local function toKey(...)
        local keys = {}
        for _, key in pairs { ... } do
            if type(key) == "table" then
                table.insert(keys, "table")
                for k, v in pairs(key) do
                    table.insert(keys, tostring(k))
                    table.insert(keys, tostring(v))
                end
            else
                table.insert(keys, tostring(key))
            end
        end
        return table.concat(keys, "")
    end

    -- Performance tracking
    local _perf = {
        page_t0          = nil,
        update_calls     = 0,
        update_time      = 0,
        orig_update_time = 0,
        extra_getbi_time = 0,
        ancestor_calls   = 0,
        ancestor_hits    = 0,
        ancestor_time    = 0,
        collect_calls    = 0,
        collect_time     = 0,
        paint_tw_calls   = 0,
        gen_item_time    = 0,
        getlistitem_calls = 0,
        getlistitem_time  = 0,
        lfsdir_scans     = 0,
        lfsdir_time      = 0,
    }

    local function _perf_dump(tag)
        local logger = require("logger")
        local total = _perf.update_calls > 0 and _perf.update_time or 0
        logger.dbg(string.format(
            "[zen-perf] %s | items=%d update=%.1fms (orig=%.1fms extra_getbi=%.1fms)"
            .. " | ancestor: calls=%d hits=%d time=%.1fms"
            .. " | collect: calls=%d time=%.1fms"
            .. " | paintTo TW allocs=%d"
            .. " | genItemTable=%.1fms getListItem: calls=%d time=%.1fms"
            .. " | lfsdir: scans=%d time=%.1fms",
            tag,
            _perf.update_calls,
            total * 1000,
            _perf.orig_update_time * 1000,
            _perf.extra_getbi_time * 1000,
            _perf.ancestor_calls,
            _perf.ancestor_hits,
            _perf.ancestor_time * 1000,
            _perf.collect_calls,
            _perf.collect_time * 1000,
            _perf.paint_tw_calls,
            _perf.gen_item_time * 1000,
            _perf.getlistitem_calls,
            _perf.getlistitem_time * 1000,
            _perf.lfsdir_scans,
            _perf.lfsdir_time * 1000
        ))
    end

    local function _perf_reset()
        _perf.page_t0          = os.clock()
        _perf.update_calls     = 0
        _perf.update_time      = 0
        _perf.orig_update_time = 0
        _perf.extra_getbi_time = 0
        _perf.ancestor_calls   = 0
        _perf.ancestor_hits    = 0
        _perf.ancestor_time    = 0
        _perf.collect_calls    = 0
        _perf.collect_time     = 0
        _perf.paint_tw_calls   = 0
        _perf.gen_item_time    = 0
        _perf.getlistitem_calls = 0
        _perf.getlistitem_time  = 0
        _perf.lfsdir_scans     = 0
        _perf.lfsdir_time      = 0
    end

    local orig_FileChooser_getListItem = FileChooser.getListItem
    local cached_list = {}
    local _item_table_cache = nil

    function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
        if self._dummy or self.name ~= "filemanager" then
            return orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
        end
        local _t0_gli = os.clock()
        _perf.getlistitem_calls = _perf.getlistitem_calls + 1
        if attributes.mode == "directory" and collate
                and collate.can_collate_mixed and collate.mandatory_func and not collate.item_func then
            local item = orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
            local _t0_lfs = os.clock()
            _perf.lfsdir_scans = _perf.lfsdir_scans + 1
            local ok, iter, dir_obj = pcall(lfs.dir, fullpath)
            if ok then
                local max_access = attributes.access or 0
                local max_modification = attributes.modification or 0
                for fname in iter, dir_obj do
                    if fname ~= "." and fname ~= ".." then
                        local fattr = lfs.attributes(fullpath .. "/" .. fname)
                        if fattr and fattr.mode == "file" then
                            if fattr.access > max_access then
                                max_access = fattr.access
                            end
                            if fattr.modification > max_modification then
                                max_modification = fattr.modification
                            end
                        end
                    end
                end
                local new_attr = {}
                for k, v in pairs(attributes) do new_attr[k] = v end
                new_attr.access = max_access
                new_attr.modification = max_modification
                item.attr = new_attr
            end
            _perf.lfsdir_time = _perf.lfsdir_time + (os.clock() - _t0_lfs)
            _perf.getlistitem_time = _perf.getlistitem_time + (os.clock() - _t0_gli)
            return item
        end
        local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
        if not cached_list[key] then
            cached_list[key] = orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
        end
        local elapsed = os.clock() - _t0_gli
        if elapsed > 0.05 then
            require("logger").dbg("[zen-perf] SLOW getListItem:", f, string.format("%.1fms", elapsed * 1000))
        end
        _perf.getlistitem_time = _perf.getlistitem_time + elapsed
        return cached_list[key]
    end

    local function _item_table_key(path)
        local mtime = lfs.attributes(path, "modification") or 0
        local filter = FileChooser.show_filter and FileChooser.show_filter.status
        return string.format("%s|%d|%s|%s|%s|%s|%s",
            path, mtime,
            G_reader_settings:readSetting("collate", "strcoll"),
            tostring(G_reader_settings:isTrue("collate_mixed")),
            tostring(G_reader_settings:isTrue("reverse_collate")),
            tostring(FileChooser.show_hidden),
            tostring(filter))
    end

    local orig_FileChooser_genItemTableFromPath = FileChooser.genItemTableFromPath

    function FileChooser:genItemTableFromPath(path)
        if not self._dummy and self.name == "filemanager" then
            local collate_mode = G_reader_settings:readSetting("collate", "strcoll")
            local use_cache = collate_mode ~= "access"

            local key = _item_table_key(path)
            if use_cache and _item_table_cache and _item_table_cache.key == key then
                return _item_table_cache.table
            end
            if _perf.page_t0 then _perf_dump("prev-page") end
            _perf_reset()
            cached_list = {}
            local _t0_gen = os.clock()
            local result = orig_FileChooser_genItemTableFromPath(self, path)
            local elapsed = os.clock() - _t0_gen
            if elapsed > 0.1 then
                require("logger").dbg("[zen-perf] SLOW genItemTableFromPath:", path, string.format("%.1fms", elapsed * 1000))
            end
            _perf.gen_item_time = _perf.gen_item_time + elapsed
            if use_cache then
                _item_table_cache = { key = key, table = result }
            else
                _item_table_cache = nil
            end
            return result
        end
        return orig_FileChooser_genItemTableFromPath(self, path)
    end

    local Folder = {
        edge = {
            thick = Screen:scaleBySize(2.5),
            margin = Size.line.medium,
            color = Blitbuffer.COLOR_GRAY_4,
            width = 0.97,
        },
        face = {
            border_size = Size.border.thin,
            alpha = 0.75,
            nb_items_font_size = 15,
            nb_items_badge_size = Screen:scaleBySize(22),
            nb_items_offset = Screen:scaleBySize(5),
            dir_max_font_size = 25,
        },
    }

    local function placeholderBg()
        return Blitbuffer.COLOR_LIGHT_GRAY
    end

    local function patchCoverBrowser(plugin)
        local MosaicMenu = require("mosaicmenu")
        local MosaicMenuItem = Cover.getUpvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end
        local BookInfoManager = Cover.getUpvalue(MosaicMenuItem.update, "BookInfoManager")
        if not BookInfoManager then
            local ok, bim = pcall(require, "bookinfomanager")
            if ok then BookInfoManager = bim end
        end
        if not BookInfoManager then return end

        -- Force-disable the "show hint for books with description" indicator.
        BookInfoManager:saveSetting("no_hint_description", true)
        local original_update = MosaicMenuItem.update
        local logger = require("logger")
        local UIManager = require("ui/uimanager")

        local pending_folders_by_menu = setmetatable({}, { __mode = "k" })

        local function scheduleFolderRefresh(menu)
            if not menu._zen_folder_refresh_scheduled then
                menu._zen_folder_refresh_scheduled = true
                UIManager:scheduleIn(0.05, function()
                    menu._zen_folder_refresh_scheduled = nil
                    local pending = pending_folders_by_menu[menu]
                    if not pending then return end
                    local show_parent = menu.show_parent
                    pending_folders_by_menu[menu] = nil
                    for _, item in ipairs(pending) do
                        if item then
                            item._zen_pending_refresh = nil
                            if not item._foldercover_processed then
                                item:update()
                                if item._foldercover_processed and show_parent then
                                    UIManager:setDirty(show_parent, function()
                                        return "ui", item[1] and item[1].dimen or item.dimen,
                                            show_parent.dithered
                                    end)
                                end
                            end
                        end
                    end
                end)
            end
        end

        local _BlitBadge = require("ffi/blitbuffer")
        local _FontBadge = require("ui/font")
        local _TW        = require("ui/widget/textwidget")

        local function paintCircle(bb, cx, cy, r, color)
            for row = -r, r do
                local half_w = math.floor(math.sqrt(math.max(0, r * r - row * row)))
                if half_w > 0 then
                    bb:paintRectRGB32(cx - half_w, cy + row, 2 * half_w, 1, color)
                end
            end
        end

        local function find_uv_fn(fn, depth)
            depth = depth or 0
            if depth > 10 or type(fn) ~= "function" then return nil end
            for i = 1, 128 do
                local name, val = debug.getupvalue(fn, i)
                if not name then break end
                if name == "uv" and type(val) == "function" then return val end
                if name == "orig_paintTo" then
                    local found = find_uv_fn(val, depth + 1)
                    if found then return found end
                end
            end
            return nil
        end
        local _badge_uv_fn = find_uv_fn(MosaicMenuItem.paintTo)

        local _cached_badge_scale    = 1.0
        local _cached_badge_size_key = false
        local function get_badge_scale()
            local cur = _plugin and type(_plugin.config) == "table"
                and type(_plugin.config.browser_cover_badges) == "table"
                and _plugin.config.browser_cover_badges.badge_size or false
            if cur ~= _cached_badge_size_key then
                _cached_badge_size_key = cur
                _cached_badge_scale    = utils.getBadgeScale(_plugin and _plugin.config)
            end
            return _cached_badge_scale
        end

        local orig_folder_paintTo = MosaicMenuItem.paintTo
        local _last_known_night = Device.screen.night_mode
        function MosaicMenuItem:paintTo(bb, x, y)
            orig_folder_paintTo(self, bb, x, y)
            -- Fallback: detect night mode change at paint time and re-render all folder covers.
            local _cur_night = Device.screen.night_mode
            if _cur_night ~= _last_known_night then
                _last_known_night = _cur_night
                local _m = self.menu
                if _m and not _m._zen_night_refresh_scheduled then
                    _m._zen_night_refresh_scheduled = true
                    UIManager:scheduleIn(0, function()
                        _m._zen_night_refresh_scheduled = nil
                        _m:updateItems()
                    end)
                end
            end
            if self.is_go_up then return end
            local count = rawget(self, "_zen_folder_count")
            if not count then return end

            local cd = rawget(self, "_zen_cover_dimen")
            if not (cd and cd.w and cd.w > 0) then return end
            local corner_mark_size = (_badge_uv_fn and _badge_uv_fn("corner_mark_size"))
                or Screen:scaleBySize(20)
            local eff_size = math.floor(math.max(corner_mark_size, math.floor((cd.w or 0) * 0.14))
                * get_badge_scale())

            local cover_x = x + math.floor((self.width - cd.w) / 2)
            local cover_y = y + (rawget(self, "_zen_cover_top") or math.floor((self.height - cd.h) / 2))

            local count_str  = tostring(count)
            local font_size  = math.max(7, math.floor(eff_size * 0.24))

            local tw = rawget(self, "_zen_badge_tw")
            local _fc = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            local _bcc = _fc and type(_fc.config) == "table"
                and type(_fc.config.browser_cover_badges) == "table"
                and _fc.config.browser_cover_badges.badge_color
            local badge_is_dark = _bcc == nil or (type(_bcc) == "table" and _bcc[1] == 0 and _bcc[2] == 0 and _bcc[3] == 0)
            local badge_fg = badge_is_dark and _BlitBadge.COLOR_WHITE or _BlitBadge.COLOR_BLACK
            if tw then
                if rawget(self, "_zen_badge_str") ~= count_str or rawget(self, "_zen_badge_fs") ~= font_size or rawget(self, "_zen_badge_dark") ~= badge_is_dark then
                    if tw.free then tw:free() end
                    tw = nil
                end
            end
            if not tw then
                _perf.paint_tw_calls = _perf.paint_tw_calls + 1
                tw = _TW:new{
                    text    = count_str,
                    face    = _FontBadge:getFace("cfont", font_size),
                    bold    = true,
                    fgcolor = badge_is_dark and _BlitBadge.COLOR_WHITE or _BlitBadge.COLOR_BLACK,
                    padding = 0,
                }
                rawset(self, "_zen_badge_tw", tw)
                rawset(self, "_zen_badge_str", count_str)
                rawset(self, "_zen_badge_fs", font_size)
                rawset(self, "_zen_badge_dark", badge_is_dark)
            end

            local tw_sz = tw:getSize()
            local diam  = math.max(tw_sz.w, tw_sz.h) + math.floor(eff_size * 0.3)
            local r     = math.floor(diam / 2)
            local inset = utils.getBadgeInset(r)
            local cx = cover_x + cd.w - r - inset
            local cy = cover_y + r + inset

            paintCircle(bb, cx, cy, r + 2, badge_fg)
            paintCircle(bb, cx, cy, r,     utils.getBadgeColor(_plugin and _plugin.config))
            tw:paintTo(bb,
                cx - math.floor(tw_sz.w / 2),
                cy - math.floor(tw_sz.h / 2)
            )
        end

        local zen_migrated_paths = {}

        local ffiUtil = require("ffi/util")
        local MAX_ANCESTOR_LEVELS = 3

        local function getBookInfoWithFallback(path)
            local bi = BookInfoManager:getBookInfo(path, true)
            if bi then return bi, path end

            local basename = ffiUtil.basename(path)
            local home_dir = paths.getHomeDir()

            if not home_dir or not paths.isInHomeDir(path) then
                return nil, nil
            end

            _perf.ancestor_calls = _perf.ancestor_calls + 1
            local t0_anc = os.clock()
            local dir = ffiUtil.dirname(path)
            for _ = 1, MAX_ANCESTOR_LEVELS do
                local parent = ffiUtil.dirname(dir)
                if parent == dir then break end
                local candidate = parent .. "/" .. basename
                if candidate ~= path then
                    local candidate_bi = BookInfoManager:getBookInfo(candidate, true)
                    if candidate_bi
                            and candidate_bi.cover_bb
                            and candidate_bi.has_cover
                            and candidate_bi.cover_fetched
                            and not candidate_bi.ignore_cover then
                        _perf.ancestor_hits = _perf.ancestor_hits + 1
                        _perf.ancestor_time = _perf.ancestor_time + (os.clock() - t0_anc)
                        logger.dbg("[zen-ui] fallback: found cover at ancestor path",
                            candidate, "for", path)
                        return candidate_bi, candidate
                    end
                end
                if parent == home_dir then break end
                dir = parent
            end
            _perf.ancestor_time = _perf.ancestor_time + (os.clock() - t0_anc)
            return nil, nil
        end

        local function tryMigrateBookInfoPath(old_path, new_path)
            if old_path == new_path then return end
            pcall(function()
                local db = BookInfoManager.db_conn
                    or BookInfoManager.db
                    or BookInfoManager.db_connection
                    or BookInfoManager._db_conn
                if not db then return end
                local function sq_esc(s) return s:gsub("'", "''") end
                db:exec(
                    "UPDATE bookinfo SET filepath='" .. sq_esc(new_path) ..
                    "' WHERE filepath='" .. sq_esc(old_path) .. "'"
                )
                logger.dbg("[zen-ui] migrated DB row", old_path, "->", new_path)
            end)
        end

        -- Config accessors for browser_folder_cover settings.
        local function get_fbc()
            local p = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            local c = type(p) == "table" and type(p.config) == "table" and p.config.browser_folder_cover
            return type(c) == "table" and c or {}
        end
        local function save_fbc()
            local p = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            if type(p) == "table" and type(p.saveConfig) == "function" then p:saveConfig() end
        end
        local function set_cover_mode(mode)
            local c = get_fbc(); c.cover_mode = mode; save_fbc()
            local ui = require("apps/filemanager/filemanager").instance
            if ui and ui.file_chooser then ui.file_chooser:updateItems() end
        end

        local settings = {
            crop_to_fit = {
                get = function() return get_fbc().crop_to_fit ~= false end,
                toggle = function()
                    local c = get_fbc(); c.crop_to_fit = c.crop_to_fit == false; save_fbc()
                end,
            },
            name_centered = {
                get = function() return get_fbc().name_centered == true end,
                toggle = function()
                    local c = get_fbc(); c.name_centered = c.name_centered ~= true; save_fbc()
                end,
            },
            show_folder_name = {
                get = function() return get_fbc().show_folder_name ~= false end,
                toggle = function()
                    local c = get_fbc(); c.show_folder_name = c.show_folder_name == false; save_fbc()
                end,
            },
            show_item_count = {
                get = function() return get_fbc().show_item_count ~= false end,
                toggle = function()
                    local c = get_fbc(); c.show_item_count = c.show_item_count == false; save_fbc()
                end,
            },
            name_opaque = {
                get = function() return get_fbc().name_opaque == true end,
                toggle = function()
                    local c = get_fbc(); c.name_opaque = c.name_opaque ~= true; save_fbc()
                end,
            },
            gallery_mode = {
                text = _("Gallery view (4-grid)"),
                get = function() return get_fbc().cover_mode == "gallery" end,
                toggle = function() set_cover_mode(get_fbc().cover_mode == "gallery" and "normal" or "gallery") end,
            },
            stack_mode = {
                text = _("Stack effect (overlapping covers)"),
                get = function() return get_fbc().cover_mode == "stack" end,
                toggle = function() set_cover_mode(get_fbc().cover_mode == "stack" and "normal" or "stack") end,
            },
            none_mode = {
                text = _("None (folder name only)"),
                get = function() return get_fbc().cover_mode == "none" end,
                toggle = function() set_cover_mode(get_fbc().cover_mode == "none" and "normal" or "none") end,
            },
        }

        -- Main update implementation
        local function _zen_update_impl(self, ...)

            if self._zen_ancestor_cover then
                if self.entry and (self.entry.is_file or self.entry.file) then
                    local _p = self.entry.path or self.entry.file
                    if _p and not BookInfoManager:getBookInfo(_p, true) then
                        return
                    end
                end
                self._zen_ancestor_cover = nil
                self.refresh_dimen = nil
            end

            -- Apply cover logic to search results as well
            local is_search = self.menu and self.menu.name == "filesearcher"

            local is_non_fm = not (self.menu and (
                self.menu.name == "filemanager"
                or self.menu.name == "history"
                or self.menu._zen_tab_id
                or self.menu._zen_coll_list
                or is_search))

            if is_non_fm and (self.entry.is_file or self.entry.file) then
                local _path = self.entry.path or self.entry.file or ""
                local _ext = _path:match("%.([^%.]+)$")
                local _is_native_img = _ext and ({
                    jpg=1, jpeg=1, png=1, gif=1, bmp=1, webp=1, tiff=1, tif=1, svg=1,
                })[_ext:lower()] ~= nil
                if _is_native_img then
                    original_update(self, ...)
                else
                    local saved = self.do_cover_image
                    self.do_cover_image = false
                    original_update(self, ...)
                    self.do_cover_image = saved
                end
                return
            end

            local was_found = self.bookinfo_found
            local _t0_orig = os.clock()
            original_update(self, ...)
            _perf.orig_update_time = _perf.orig_update_time + (os.clock() - _t0_orig)
            -- Invalidate cached folder covers when night mode changes (pre-baked blitbufs need re-render).
            if self._foldercover_processed and not (self.entry.is_file or self.entry.file)
                    and self._zen_render_night ~= Device.screen.night_mode then
                self._foldercover_processed = nil
            end
            if self._foldercover_processed or self.menu.no_refresh_covers then return end
            if (self.entry.is_file or self.entry.file) then
                if not self.do_cover_image or not self.mandatory then return end
                if not was_found and self.bookinfo_found and self.menu then
                    scheduleFolderRefresh(self.menu)
                end
            end

            -- Handle single book files (Scenario 1 & 2)
            local _resolved_path = self.entry.path or self.entry.file
            if (self.entry.is_file or self.entry.file) and _resolved_path then
                local path = _resolved_path
                local _t0_xbi = os.clock()
                local bookinfo = BookInfoManager:getBookInfo(path, true)
                _perf.extra_getbi_time = _perf.extra_getbi_time + (os.clock() - _t0_xbi)
                if not bookinfo then
                    local ancestor_bi, ancestor_path = getBookInfoWithFallback(path)
                    if ancestor_bi and ancestor_path ~= path and ancestor_bi.cover_bb then
                        local cover_bb_copy = ancestor_bi.cover_bb:copy()
                        local border = Folder.face.border_size
                        local max_w = self.width - 2 * border
                        local strip_h = (not MosaicMenuItem._zen_in_init)
                            and (rawget(MosaicMenuItem, "_zen_strip_h") or 0) or 0
                        local eff_h = self.height - strip_h
                        local bh = eff_h - 2 * border
                        local portrait_w, portrait_h = Cover.calcDims(max_w, bh)
                        local cover_frame = FrameContainer:new {
                            padding     = 0,
                            bordersize  = border,
                            width       = portrait_w + 2 * border,
                            height      = portrait_h + 2 * border,
                            background  = placeholderBg(),
                            CenterContainer:new {
                                dimen = { w = portrait_w, h = portrait_h },
                                ImageWidget:new {
                                    image            = cover_bb_copy,
                                    image_disposable = true,
                                    width            = portrait_w,
                                    height           = portrait_h,
                                },
                            },
                            overlap_align = "center",
                        }
                        local overlap = OverlapGroup:new {
                            dimen = { w = self.width, h = eff_h },
                            cover_frame,
                        }
                        if self._underline_container[1] then
                            self._underline_container[1]:free()
                        end
                        self._underline_container[1] = overlap
                        self._zen_ancestor_cover = true
                        if not zen_migrated_paths[path] then
                            zen_migrated_paths[path] = true
                            tryMigrateBookInfoPath(ancestor_path, path)
                        end
                        return
                    end
                    -- no ancestor cover: fall through to unified placeholder below
                end
                -- Unified: not yet in DB, or confirmed no cover art
                if (not bookinfo) or (bookinfo.cover_fetched
                        and (bookinfo.ignore_cover or not bookinfo.has_cover)) then
                    local border = Folder.face.border_size
                    local max_w = self.width - 2 * border
                    local strip_h = (not MosaicMenuItem._zen_in_init)
                        and (rawget(MosaicMenuItem, "_zen_strip_h") or 0) or 0
                    local eff_h = self.height - strip_h
                    local bh = eff_h - 2 * border
                    local portrait_w, portrait_h = Cover.calcDims(max_w, bh)
                    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }
                    local centered_top = math.floor((eff_h - dimen.h) / 2)

                    local final_bb = Cover.genCover(path, portrait_w, portrait_h, true)

                    local gray_frame = FrameContainer:new {
                        padding       = 0,
                        bordersize    = border,
                        width         = dimen.w,
                        height        = dimen.h,
                        background    = placeholderBg(),
                        overlap_align = "center",
                        CenterContainer:new {
                            dimen = { w = portrait_w, h = portrait_h },
                            ImageWidget:new {
                                image = final_bb,
                                width = portrait_w,
                                height = portrait_h,
                            },
                        },
                    }

                    if self.dim or (self.entry and self.entry.dim) then
                        gray_frame.dim = true
                    end

                    self._cover_frame = gray_frame
                    local widget = OverlapGroup:new {
                        dimen = { w = self.width, h = eff_h },
                        VerticalGroup:new {
                            VerticalSpan:new { width = centered_top },
                            CenterContainer:new {
                                dimen = { w = self.width, h = dimen.h },
                                OverlapGroup:new {
                                    dimen = dimen,
                                    gray_frame,
                                },
                            },
                        },
                    }
                    if self._underline_container[1] then
                        self._underline_container[1]:free()
                    end
                    self._underline_container[1] = widget
                end
                -- Clear stale placeholder frame when real cover is now available.
                if bookinfo and bookinfo.cover_fetched and bookinfo.has_cover then
                    self._cover_frame = nil
                end
                -- Extend refresh_dimen to cover the title strip.
                -- CoverMenu defaults to item[1].dimen (h = H-STRIP_H), missing the strip.
                local _strip_h = rawget(MosaicMenuItem, "_zen_strip_h") or 0
                if _strip_h > 0 and self[1] and self[1].dimen and self[1].dimen.x then
                    self.refresh_dimen = self[1].dimen:copy()
                    self.refresh_dimen.h = self.refresh_dimen.h + _strip_h
                end
                return
            end

            -- Folder items (Scenario 3 & 4)
            local dir_path = self.entry and self.entry.path

            -- Handle "go up" item
            if self.entry.is_go_up then
                self._foldercover_processed = true
                self._zen_render_night = Device.screen.night_mode
                local border = Folder.face.border_size
                local max_w = self.width - 2 * border
                local strip_h = (not MosaicMenuItem._zen_in_init)
                    and (rawget(MosaicMenuItem, "_zen_strip_h") or 0) or 0
                local eff_h = self.height - strip_h
                local bh = eff_h - 2 * border
                local portrait_w, portrait_h = Cover.calcDims(max_w, bh)
                local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }
                local centered_top = math.floor((eff_h - dimen.h) / 2)

                local arrow_size = math.min(portrait_w, portrait_h) * 0.25
                local arrow_text = TextWidget:new{
                    text = "↑",
                    face = library_font.getFace(math.floor(arrow_size)),
                    fgcolor = Blitbuffer.COLOR_BLACK,
                }

                local gray_frame = FrameContainer:new {
                    padding = 0,
                    bordersize = border,
                    width = dimen.w, height = dimen.h,
                    background = placeholderBg(),
                    CenterContainer:new {
                        dimen = { w = portrait_w, h = portrait_h },
                        CenterContainer:new {
                            dimen = { w = portrait_w, h = portrait_h },
                            arrow_text,
                        },
                    },
                    overlap_align = "center",
                }

                self._cover_frame = gray_frame

                local widget = OverlapGroup:new {
                    dimen = { w = self.width, h = eff_h },
                    VerticalGroup:new {
                        VerticalSpan:new { width = centered_top },
                        CenterContainer:new {
                            dimen = { w = self.width, h = dimen.h },
                            OverlapGroup:new {
                                dimen = dimen,
                                gray_frame,
                            },
                        },
                    },
                }
                if self._underline_container[1] then
                    self._underline_container[1]:free()
                end
                self._underline_container[1] = widget
                return
            end

            if not dir_path then return end

            -- PathChooser: shape + name only
            if is_non_fm then
                self._foldercover_processed = true
                self._zen_render_night = Device.screen.night_mode
                self:_setFolderCover { no_image = true }
                return
            end

            local _fm = require("apps/filemanager/filemanager").instance
            local _main_chooser = _fm and _fm.file_chooser
            local _chooser = _main_chooser
                or (self.menu.genItemTableFromPath and self.menu)

            -- Use unified makeCover - auto-detects cover files and collects book covers
            local border = Folder.face.border_size
            local max_w = self.width - 2 * border
            local bh = self.height - 2 * border
            local folder_name = dir_path:match("([^/]+)/?$") or dir_path
            folder_name = BD.directory(folder_name)

            local cover_widget = Cover.makeCover(dir_path, _chooser, {
                is_folder = true,
                max_w = max_w,
                max_h = bh,
                folder_name = folder_name,
            })

            -- Pass the cover widget to _setFolderCover
            if cover_widget then
                self._foldercover_processed = true
                self._zen_render_night = Device.screen.night_mode
                self:_setFolderCover { image_widget = cover_widget }
            else
                self:_setFolderCover { no_image = true }
            end
        end

        function MosaicMenuItem:update(...)
            local _t0 = os.clock()
            local _t0_orig_before = _perf.orig_update_time
            _zen_update_impl(self, ...)
            local elapsed = os.clock() - _t0
            local orig_elapsed = _perf.orig_update_time - _t0_orig_before
            _perf.update_calls = _perf.update_calls + 1
            _perf.update_time  = _perf.update_time + elapsed
            if elapsed > 0.05 then
                local title = self.text or (self.entry and self.entry.text) or "unknown"
                require("logger").dbg("[zen-perf] SLOW update:", title, string.format("%.1fms", elapsed * 1000), "orig:", string.format("%.1fms", orig_elapsed * 1000))
            end
        end

        function MosaicMenuItem:_setFolderCover(img)
            local border = Folder.face.border_size
            local max_w = self.width - 2 * border
            local strip_h = (not MosaicMenuItem._zen_in_init)
                and (rawget(MosaicMenuItem, "_zen_strip_h") or 0) or 0
            local eff_h = self.height - strip_h
            local bh = eff_h - 2 * border
            local portrait_w, portrait_h = Cover.calcDims(max_w, bh)
            local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

            -- Use the image_widget if provided by makeCover, otherwise draw based on img type
            local image_widget = img.image_widget

            if not image_widget then
                if img.gallery then
                    image_widget = Cover.drawGallery(img.gallery, portrait_w, portrait_h, border, placeholderBg)
                elseif img.stack then
                    image_widget = Cover.drawStack(img.stack, portrait_w, portrait_h, border, placeholderBg)
                elseif img.no_image then
                    local folder_name = self.text:gsub("/$", "")
                    folder_name = BD.directory(folder_name)
                    image_widget = Cover.drawNoImage(folder_name, portrait_w, portrait_h, border, placeholderBg)
                elseif img.data then
                    image_widget = Cover.drawSingle(img.data, portrait_w, portrait_h, border, placeholderBg)
                elseif img.file then
                    -- Custom image from file
                    local img_options = { file = img.file }
                    if img.scale_to_fit then
                        img_options.scale_factor = math.max(portrait_h / img.h, portrait_w / img.w)
                    end
                    local image = ImageWidget:new(img_options)
                    image:_render()
                    image_widget = image
                else
                    image_widget = Cover.drawNoImage(self.text, portrait_w, portrait_h, border, placeholderBg)
                end
            end

            self._zen_cover_dimen = dimen
            self._zen_cover_top = math.floor((eff_h - dimen.h) / 2)

            local _file_count = type(self.mandatory) == "string"
                and (tonumber(self.mandatory:match("(%d+)%s*\xef\x80\x96")) or 0) or 0
            self._zen_folder_count = (settings.show_item_count.get() and _file_count > 0)
                and _file_count or nil

            local directory = self:_getTextBoxes { w = portrait_w, h = portrait_h }

            local folder_name_widget
            if settings.show_folder_name.get() and not MosaicMenuItem._zen_title_strip_patched then
                local NameContainer = settings.name_centered.get() and CenterContainer or BottomContainer
                local name_frame = FrameContainer:new {
                    padding = 0,
                    bordersize = Folder.face.border_size,
                    background = Blitbuffer.COLOR_WHITE,
                    directory,
                }
                folder_name_widget = NameContainer:new {
                    dimen = dimen,
                    settings.name_opaque.get()
                        and name_frame
                        or AlphaContainer:new { alpha = Folder.face.alpha, name_frame },
                    overlap_align = "center",
                }
            else
                folder_name_widget = VerticalSpan:new { width = 0 }
            end

            local nbitems_widget = VerticalSpan:new { width = 0 }

            local centered_top = math.floor((eff_h - dimen.h) / 2)
            local top_h = 2 * (Folder.edge.thick + Folder.edge.margin)
            local spine_gap = Screen:scaleBySize(9)
            local use_top_lines = centered_top >= top_h
                or math.floor((self.width - dimen.w) / 2) < spine_gap

            local plug = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            local rounded = plug
                and type(plug.config) == "table"
                and type(plug.config.features) == "table"
                and plug.config.features.browser_cover_rounded_corners == true
            local line_inset = rounded and Screen:scaleBySize(4) or 0

            local decoration_layer
            if get_fbc().show_spine_lines ~= false then
                if use_top_lines then
                    local line1_w = math.max(0, math.floor(dimen.w * (Folder.edge.width ^ 2)) - 2 * line_inset)
                    local line2_w = math.max(0, math.floor(dimen.w * Folder.edge.width) - 2 * line_inset)
                    decoration_layer = TopContainer:new {
                        dimen = { w = self.width, h = self.height },
                        VerticalGroup:new {
                            VerticalSpan:new { width = centered_top - top_h },
                            CenterContainer:new {
                                dimen = { w = self.width, h = top_h },
                                VerticalGroup:new {
                                    LineWidget:new {
                                        background = Folder.edge.color,
                                        dimen = { w = line1_w, h = Folder.edge.thick },
                                    },
                                    VerticalSpan:new { width = Folder.edge.margin },
                                    LineWidget:new {
                                        background = Folder.edge.color,
                                        dimen = { w = line2_w, h = Folder.edge.thick },
                                    },
                                },
                            },
                        },
                    }
                else
                    local spine_x = math.max(0, math.floor((self.width - dimen.w) / 2))
                    local line1_h = math.max(0, math.floor(dimen.h * (Folder.edge.width ^ 2)) - 2 * line_inset)
                    local line2_h = math.max(0, math.floor(dimen.h * Folder.edge.width) - 2 * line_inset)
                    decoration_layer = LeftContainer:new {
                        dimen = { w = self.width, h = eff_h },
                        HorizontalGroup:new {
                            HorizontalSpan:new { width = math.max(0, spine_x - spine_gap) },
                            CenterContainer:new {
                                dimen = { w = Folder.edge.thick, h = eff_h },
                                LineWidget:new {
                                    background = Folder.edge.color,
                                    dimen = { w = Folder.edge.thick, h = line1_h },
                                },
                            },
                            HorizontalSpan:new { width = Folder.edge.margin },
                            CenterContainer:new {
                                dimen = { w = Folder.edge.thick, h = eff_h },
                                LineWidget:new {
                                    background = Folder.edge.color,
                                    dimen = { w = Folder.edge.thick, h = line2_h },
                                },
                            },
                        },
                    }
                end
            end

            local widget = OverlapGroup:new {
                dimen = { w = self.width, h = self.height },
                VerticalGroup:new {
                    VerticalSpan:new { width = centered_top },
                    CenterContainer:new {
                         dimen = { w = self.width, h = dimen.h },
                         OverlapGroup:new {
                            dimen = dimen,
                            image_widget,
                            folder_name_widget,
                            nbitems_widget,
                        },
                    },
                },
                decoration_layer,
            }
            if self._underline_container[1] then
                local previous_widget = self._underline_container[1]
                previous_widget:free()
            end

            self._underline_container[1] = widget
        end

        function MosaicMenuItem:_getTextBoxes(dimen)
            local nb_font_size = dimen.badge_font_size or Folder.face.nb_items_font_size

            local badge_ref = TextWidget:new {
                text = "0",
                face = library_font.getFace(nb_font_size),
                bold = true,
                padding = 0,
            }
            local badge_h = badge_ref:getSize().h
            badge_ref:free()

            local text = self.text
            if text:match("/$") then text = text:sub(1, -2) end
            text = BD.directory(text)
            local available_height = dimen.h - 2 * badge_h
            local dir_font_size = library_font.scaleValue(Folder.face.dir_max_font_size)
            local min_font_size = library_font.scaleValue(14)
            local x_pad = Screen:scaleBySize(4)
            local text_w = dimen.w - 2 * x_pad
            local directory

            local probe
            local single_line_fits = false
            while dir_font_size >= min_font_size do
                if probe then probe:free() end
                probe = TextWidget:new {
                    text    = text,
                    face    = library_font.getFace(dir_font_size),
                    bold    = true,
                    padding = 0,
                }
                local ps = probe:getSize()
                if ps.w <= text_w and ps.h <= available_height then
                    single_line_fits = true
                    break
                end
                dir_font_size = dir_font_size - 1
            end

            if single_line_fits then
                probe:free()
                directory = TextBoxWidget:new {
                    text      = text,
                    face      = library_font.getFace(dir_font_size),
                    width     = dimen.w,
                    alignment = "center",
                    bold      = true,
                }
            else
                if probe then probe:free() end
                local line_probe = TextWidget:new {
                    text = "Ag", face = library_font.getFace(min_font_size),
                    bold = true, padding = 0,
                }
                local two_line_h = math.min(available_height, 2 * line_probe:getSize().h)
                line_probe:free()
                directory = TextBoxWidget:new {
                    text      = text,
                    face      = library_font.getFace(min_font_size),
                    width     = dimen.w,
                    alignment = "center",
                    bold      = true,
                    height    = two_line_h,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                }
            end

            return directory
        end

        -- List mode cover handling
        do
            local ListMenu = require("listmenu")
            local ListMenuItem = Cover.getUpvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
            if ListMenuItem then
                local original_list_update = ListMenuItem.update

                function ListMenuItem:update(...)
                    original_list_update(self, ...)
                    if self.entry.is_go_up then return end
                    -- Invalidate cached folder covers when night mode changes.
                    if self._foldercover_processed and self._zen_render_night ~= Device.screen.night_mode then
                        self._foldercover_processed = nil
                    end
                    if self._foldercover_processed or self.menu.no_refresh_covers then return end
                    if self.entry.is_file or self.entry.file then return end
                    local dir_path = self.entry and self.entry.path
                    if not dir_path then return end

                    local _fm_inst = require("apps/filemanager/filemanager").instance
                    local _main_ch = _fm_inst and _fm_inst.file_chooser
                    local _chooser = _main_ch
                        or (self.menu.genItemTableFromPath and self.menu)

                    -- Use unified makeCover - auto-detects cover files and collects book covers
                    local folder_name = dir_path:match("([^/]+)/?$") or dir_path
                    folder_name = BD.directory(folder_name)

                    -- Get dimensions for list mode
                    local underline_h = 1
                    local dimen_h = self.height - 2 * underline_h
                    local border_size = Size.border.thin
                    local cover_v_pad = Screen:scaleBySize(4)
                    local max_img = dimen_h - 2 * border_size - 2 * cover_v_pad
                    local ratio = Cover.getRatio()
                    local cover_w = math.floor(max_img * ratio)

                    local cover_widget = Cover.makeCover(dir_path, _chooser, {
                        is_folder = true,
                        max_w = cover_w + 2 * border_size,
                        max_h = max_img + 2 * border_size,
                        folder_name = folder_name,
                    })

                    if cover_widget then
                        self._foldercover_processed = true
                        self._zen_render_night = Device.screen.night_mode
                        self:_setListFolderCover { image_widget = cover_widget }
                    else
                        self:_setListFolderCover { no_image = true }
                    end
                end

                function ListMenuItem:_setListFolderCover(img)
                    local underline_h = 1
                    local border_size = Size.border.thin
                    local cover_v_pad = Screen:scaleBySize(4)
                    local dimen_h = self.height - 2 * underline_h
                    local cover_zone_w = dimen_h
                    local max_img = dimen_h - 2 * border_size - 2 * cover_v_pad

                    local scale_by_size = Screen:scaleBySize(1000000) * (1 / 1000000)
                    local function _fontSize(nominal, max_size)
                        local scale = library_font.getScale(18)
                        local fs = math.floor(nominal * dimen_h * (1 / 64) / scale_by_size * scale + 0.5)
                        if max_size then
                            local max_scaled = math.max(1, math.floor(max_size * scale + 0.5))
                            if fs >= max_scaled then return max_scaled end
                        end
                        return fs
                    end

                    local ratio = Cover.getRatio()
                    local portrait_w = math.floor(max_img * ratio)
                    local cover_w = portrait_w + 2 * border_size
                    local spine_x = math.max(0, math.floor((cover_zone_w - cover_w) / 2))

                    local white_bg = function() return Blitbuffer.COLOR_WHITE end
                    local light_gray_bg = function() return Blitbuffer.COLOR_LIGHT_GRAY end

                    local cover_display_widget = img.image_widget

                    if not cover_display_widget then
                        if img.gallery then
                            cover_display_widget = Cover.drawGallery(img.gallery, portrait_w, max_img, border_size, light_gray_bg)
                        elseif img.stack then
                            cover_display_widget = Cover.drawStack(img.stack, portrait_w, max_img, border_size, light_gray_bg)
                        elseif img.no_image then
                            local folder_name = self.text:gsub("/$", "")
                            folder_name = BD.directory(folder_name)
                            cover_display_widget = Cover.drawNoImage(folder_name, portrait_w, max_img, border_size, white_bg)
                        elseif img.data then
                            cover_display_widget = Cover.drawSingle(img.data, portrait_w, max_img, border_size, light_gray_bg)
                        elseif img.file then
                            local img_options = { file = img.file }
                            if img.scale_to_fit then
                                img_options.scale_factor = math.max(max_img / img.h, portrait_w / img.w)
                            end
                            local image = ImageWidget:new(img_options)
                            image:_render()
                            cover_display_widget = image
                        else
                            local folder_name = self.text:gsub("/$", "")
                            folder_name = BD.directory(folder_name)
                            cover_display_widget = Cover.drawNoImage(folder_name, portrait_w, max_img, border_size, white_bg)
                        end
                    end

                    local wleft = CenterContainer:new {
                        dimen = { w = cover_zone_w, h = dimen_h },
                        cover_display_widget,
                    }
                    -- Spine lines
                    local plug_rc = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
                    local rounded = plug_rc
                        and type(plug_rc.config) == "table"
                        and type(plug_rc.config.features) == "table"
                        and plug_rc.config.features.browser_cover_rounded_corners == true
                    local line_inset = rounded and Screen:scaleBySize(4) or 0
                    local line1_h = math.max(0, math.floor(dimen_h * (Folder.edge.width ^ 2)) - 2 * line_inset)
                    local line2_h = math.max(0, math.floor(dimen_h * Folder.edge.width) - 2 * line_inset)
                    local spine_gap = Screen:scaleBySize(8)
                    self._cover_frame = wleft[1]
                    if get_fbc().show_spine_lines ~= false then
                        wleft = OverlapGroup:new {
                            dimen = { w = cover_zone_w, h = dimen_h },
                            wleft,
                            LeftContainer:new {
                                dimen = { w = cover_zone_w, h = dimen_h },
                                HorizontalGroup:new {
                                    HorizontalSpan:new { width = math.max(0, spine_x - spine_gap) },
                                    CenterContainer:new {
                                        dimen = { w = Folder.edge.thick, h = dimen_h },
                                        LineWidget:new {
                                            background = Folder.edge.color,
                                            dimen = { w = Folder.edge.thick, h = line1_h },
                                        },
                                    },
                                    HorizontalSpan:new { width = Folder.edge.margin },
                                    CenterContainer:new {
                                        dimen = { w = Folder.edge.thick, h = dimen_h },
                                        LineWidget:new {
                                            background = Folder.edge.color,
                                            dimen = { w = Folder.edge.thick, h = line2_h },
                                        },
                                    },
                                },
                            },
                        }
                    end

                    -- Right column with counts
                    local pad = Screen:scaleBySize(10)
                    local wmain_left_pad = Screen:scaleBySize(5)
                    local _file_count = tonumber((self.mandatory or ""):match("(%d+)%s*\xef\x80\x96")) or 0
                    local _dir_count = tonumber((self.mandatory or ""):match("(%d+)%s*\xef\x84\x94")) or 0
                    local fs_right = _fontSize(16, 20)
                    local file_label = tostring(_file_count) .. " " .. (_file_count == 1 and _("Book") or _("Books"))
                    local dir_label = tostring(_dir_count) .. " " .. (_dir_count == 1 and _("Folder") or _("Folders"))
                    local wfile = TextWidget:new{ text = file_label, face = library_font.getFace(fs_right), padding = 0 }
                    local wdir = TextWidget:new{ text = dir_label, face = library_font.getFace(fs_right), padding = 0 }
                    local wright_w = math.max(wfile:getWidth(), _dir_count > 0 and wdir:getWidth() or 0)
                    local wright_right_pad = pad
                    local wright = VerticalGroup:new{}
                    if _dir_count > 0 then table.insert(wright, wdir) end
                    table.insert(wright, wfile)

                    -- Folder name (middle column)
                    local text = self.text
                    if text:match("/$") then text = text:sub(1, -2) end
                    text = BD.directory(text)
                    local wmain_w = self.width - cover_zone_w - wmain_left_pad - pad - wright_w - wright_right_pad
                    local text_safe_pad_top = math.max(2, Screen:scaleBySize(4))
                    local text_safe_pad_bottom = math.max(2, Screen:scaleBySize(3))
                    local content_h = math.max(1, dimen_h - text_safe_pad_top - text_safe_pad_bottom)
                    local name_font_size = _fontSize(20, 24)
                    name_font_size = math.min(name_font_size, math.max(9, math.floor(content_h * 0.45)))
                    local name_probe = TextWidget:new {
                        text = "Ag",
                        face = library_font.getFace(name_font_size),
                        bold = true,
                        padding = 0,
                    }
                    local name_h = math.min(content_h, name_probe:getSize().h * 2)
                    name_probe:free()
                    local wname = TextBoxWidget:new {
                        text = text,
                        face = library_font.getFace(name_font_size),
                        width = math.max(wmain_w, 0),
                        alignment = "left",
                        bold = true,
                        height = name_h,
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                    }

                    -- Assemble final widget
                    local dimen = { w = self.width, h = dimen_h }
                    local widget = OverlapGroup:new {
                        dimen = dimen,
                        wleft,
                        LeftContainer:new {
                            dimen = dimen,
                            HorizontalGroup:new {
                                HorizontalSpan:new { width = cover_zone_w },
                                HorizontalSpan:new { width = wmain_left_pad },
                                VerticalGroup:new {
                                    VerticalSpan:new { width = text_safe_pad_top },
                                    wname,
                                },
                            },
                        },
                        RightContainer:new {
                            dimen = dimen,
                            HorizontalGroup:new {
                                wright,
                                HorizontalSpan:new { width = wright_right_pad },
                            },
                        },
                    }

                    if self._underline_container[1] then
                        local previous_widget = self._underline_container[1]
                        previous_widget:free()
                    end
                    self._underline_container[1] = VerticalGroup:new {
                        VerticalSpan:new { width = underline_h },
                        widget,
                    }
                end
            end
        end

        -- Hook CoverBrowser's onBookInfoUpdated
        if type(plugin.onBookInfoUpdated) == "function" then
            local orig_biu = plugin.onBookInfoUpdated
            function plugin:onBookInfoUpdated(filepath, bookinfo)
                zen_migrated_paths[filepath] = nil
                orig_biu(self, filepath, bookinfo)
                _item_table_cache = nil
                local fm = require("apps/filemanager/filemanager").instance
                local fc = fm and fm.file_chooser
                if fc and pending_folders_by_menu[fc] then
                    scheduleFolderRefresh(fc)
                end
            end
        end

        -- menu
        local orig_CoverBrowser_addToMainMenu = plugin.addToMainMenu

        function plugin:addToMainMenu(menu_items)
            orig_CoverBrowser_addToMainMenu(self, menu_items)
            if menu_items.filebrowser_settings == nil then return end

            local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
            if item then
                item.sub_item_table[#item.sub_item_table].separator = true
                for i, setting in pairs(settings) do
                    if not getMenuItem(
                            menu_items.filebrowser_settings,
                            _("Mosaic and detailed list settings"),
                            setting.text
                        ) then
                        table.insert(item.sub_item_table, {
                            text = setting.text,
                            checked_func = function() return setting.get() end,
                            callback = function()
                                setting.toggle()
                                self.ui.file_chooser:updateItems()
                            end,
                        })
                    end
                end
            end
        end
    end

    local FileManager = require("apps/filemanager/filemanager")
    local orig_fm_setupLayout = FileManager.setupLayout
    local coverbrowser_patched = false

    FileManager.setupLayout = function(self)
        orig_fm_setupLayout(self)
        if not coverbrowser_patched and self.coverbrowser then
            patchCoverBrowser(self.coverbrowser)
            coverbrowser_patched = true
            local UIManager = require("ui/uimanager")
            UIManager:scheduleIn(0, function()
                if self.file_chooser then
                    self.file_chooser:updateItems()
                end
            end)
        end
    end

    -- Primary hook: intercept setNightMode so folder covers re-render immediately
    -- on hardware night mode toggle (where paintTo is not called after the flip).
    local _orig_setNightMode = Device.screen.setNightMode
    if type(_orig_setNightMode) == "function" then
        Device.screen.setNightMode = function(screen, night_mode, ...)
            _orig_setNightMode(screen, night_mode, ...)
            local fm = require("apps/filemanager/filemanager")
            local fc = fm and rawget(fm, "instance") and rawget(fm, "instance").file_chooser
            if fc and not fc._zen_night_refresh_scheduled then
                fc._zen_night_refresh_scheduled = true
                local UIM = require("ui/uimanager")
                UIM:scheduleIn(0, function()
                    fc._zen_night_refresh_scheduled = nil
                    if fc.updateItems then fc:updateItems() end
                end)
            end
        end
    end
end

return apply_browser_folder_cover

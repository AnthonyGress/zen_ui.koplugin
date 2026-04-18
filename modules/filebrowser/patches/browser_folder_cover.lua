local function apply_browser_folder_cover()
    -- Capture plugin reference at apply-time.
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local AlphaContainer = require("ui/widget/container/alphacontainer")
    local BD = require("ui/bidi")
    local Blitbuffer = require("ffi/blitbuffer")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local FileChooser = require("ui/widget/filechooser")
    local Font = require("ui/font")
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
    local util = require("util")

    local _ = require("gettext")
    local Screen = Device.screen

    local FolderCover = {
        name = ".cover",
        exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
    }

    local function findCover(dir_path)
        local path = dir_path .. "/" .. FolderCover.name
        for _, ext in ipairs(FolderCover.exts) do
            local fname = path .. ext
            if util.fileExists(fname) then return fname end
        end
    end

    local function getMenuItem(menu, ...) -- path
        local function findItem(sub_items, texts)
            local find = {}
            local texts = type(texts) == "table" and texts or { texts }
            -- stylua: ignore
            for _, text in ipairs(texts) do find[text] = true end
            for _, item in ipairs(sub_items) do
                local text = item.text or (item.text_func and item.text_func())
                if text and find[text] then return item end
            end
        end

        local sub_items, item
        for _, texts in ipairs { ... } do -- walk path
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

    local orig_FileChooser_getListItem = FileChooser.getListItem
    local cached_list = {}

    function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
        -- Skip all extras for PathChooser/dialog instances (name is not 'filemanager').
        if self.name ~= "filemanager" then
            return orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
        end
        -- For time-based collate on directories, compute sort key from children's
        -- max atime/mtime (folder's own atime is not updated when books are read).
        if attributes.mode == "directory" and collate
                and collate.can_collate_mixed and collate.mandatory_func and not collate.item_func then
            local item = orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
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
            return item
        end
        local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
        cached_list[key] = cached_list[key] or orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
        return cached_list[key]
    end

    -- Invalidate cache on directory rescan to prevent unbounded growth.
    local orig_FileChooser_genItemTableFromPath = FileChooser.genItemTableFromPath

    function FileChooser:genItemTableFromPath(path)
        -- Only clear the main browser's cache; don't thrash it from PathChooser.
        if not self._dummy and self.name == "filemanager" then
            cached_list = {}
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
            nb_items_badge_size = Screen:scaleBySize(22),  -- fixed circle diameter
            nb_items_offset = Screen:scaleBySize(5),       -- push badge down from top edge
            dir_max_font_size = 25,
        },
    }

    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then
            return nil
        end
        for i = 1, 64 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then
                break
            end
            if upname == name then
                return value
            end
        end
    end

    local function patchCoverBrowser(plugin)
        local MosaicMenu = require("mosaicmenu")
        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end -- Protect against remnants of project title
        local BookInfoManager = get_upvalue(MosaicMenuItem.update, "BookInfoManager")
        local original_update = MosaicMenuItem.update
        local logger = require("logger")

        -- Folder book-count badge drawn directly at paint time.
        local _BlitBadge = require("ffi/blitbuffer")
        local _FontBadge = require("ui/font")
        local _TW        = require("ui/widget/textwidget")

        local function paintCircle(bb, cx, cy, r, color)
            for row = -r, r do
                local half_w = math.floor(math.sqrt(math.max(0, r * r - row * row)))
                if half_w > 0 then
                    bb:paintRect(cx - half_w, cy + row, 2 * half_w, 1, color)
                end
            end
        end

        -- Walk the paintTo wrapper chain for the uv accessor from browser_cover_badges.
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
        -- Captured once at setupLayout time; uv reads corner_mark_size live.
        local _badge_uv_fn = find_uv_fn(MosaicMenuItem.paintTo)

        local orig_folder_paintTo = MosaicMenuItem.paintTo
        function MosaicMenuItem:paintTo(bb, x, y)
            orig_folder_paintTo(self, bb, x, y)
            local count = rawget(self, "_zen_folder_count")
            if not count then return end

            -- Use stored cover dimen to position the badge (widget-tree depth differs from books).
            local cd = rawget(self, "_zen_cover_dimen")
            if not (cd and cd.w and cd.w > 0) then return end
            local corner_mark_size = (_badge_uv_fn and _badge_uv_fn("corner_mark_size"))
                or Screen:scaleBySize(20)

            -- Cover is centered within the cell (same math as _setFolderCover).
            local cover_x = x + math.floor((self.width  - cd.w) / 2)
            local cover_y = y + math.floor((self.height - cd.h) / 2)

            local count_str  = tostring(count)
            local font_size  = math.max(7, math.floor(corner_mark_size * 0.24))
            local tw = _TW:new{
                text    = count_str,
                face    = _FontBadge:getFace("cfont", font_size),
                bold    = true,
                fgcolor = _BlitBadge.COLOR_BLACK,
                padding = 0,
            }
            local tw_sz = tw:getSize()
            local diam   = math.max(tw_sz.w, tw_sz.h) + math.floor(corner_mark_size * 0.3)
            local r      = math.floor(diam / 2)
            local margin = math.floor(corner_mark_size * 0.3)
            -- top-right of cover frame
            local cx = cover_x + cd.w - r - margin
            local cy = cover_y + r + margin

            paintCircle(bb, cx, cy, r + 2, _BlitBadge.COLOR_BLACK)
            paintCircle(bb, cx, cy, r,     _BlitBadge.COLOR_LIGHT_GRAY)
            tw:paintTo(bb,
                cx - math.floor(tw_sz.w / 2),
                cy - math.floor(tw_sz.h / 2)
            )
            if tw.free then tw:free() end
        end

        -- Per-session set to avoid repeated SQL for the same path.
        local zen_migrated_paths = {}

        -- Walk ancestor dirs for a DB entry matching basename; handles books moved to subfolders.
        local ffiUtil = require("ffi/util")
        local MAX_ANCESTOR_LEVELS = 3

        local function getBookInfoWithFallback(path)
            local bi = BookInfoManager:getBookInfo(path, true)
            if bi then return bi, path end

            local basename = ffiUtil.basename(path)
            local home_dir = G_reader_settings and G_reader_settings:readSetting("home_dir") or nil

            -- Search ancestor dirs only within home_dir.
            if not home_dir or path:sub(1, #home_dir) ~= home_dir then
                return nil, nil
            end

            -- Probe <ancestor>/<basename> at each level up.
            local dir = ffiUtil.dirname(path)  -- immediate containing dir
            for _ = 1, MAX_ANCESTOR_LEVELS do
                local parent = ffiUtil.dirname(dir)
                if parent == dir then break end  -- filesystem root
                local candidate = parent .. "/" .. basename
                if candidate ~= path then
                    local candidate_bi = BookInfoManager:getBookInfo(candidate, true)
                    if candidate_bi
                            and candidate_bi.cover_bb
                            and candidate_bi.has_cover
                            and candidate_bi.cover_fetched
                            and not candidate_bi.ignore_cover then
                        logger.warn("[zen-ui] fallback: found cover at ancestor path",
                            candidate, "for", path)
                        return candidate_bi, candidate
                    end
                end
                if parent == home_dir then break end  -- don't walk above home
                dir = parent
            end
            return nil, nil
        end

        -- Best-effort DB path migration; silently ignored on error.
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
                logger.warn("[zen-ui] migrated DB row", old_path, "->", new_path)
            end)
        end

        --- Recursively collect book covers from dir_path and its subdirectories.
        --- @return table covers     List of {data=bb, w=number, h=number}
        --- @return number book_count Total book files found (recursive)
        local function collectCoversFromDir(dir_path, chooser, max_covers, max_depth, copy_bb, entries)
            local covers = {}
            local book_count = 0
            local subdirs = {}

            if not entries then
                chooser._dummy = true
                entries = chooser:genItemTableFromPath(dir_path)
                chooser._dummy = false
            end
            if not entries then return covers, book_count end

            for _, entry in ipairs(entries) do
                if entry.is_file or entry.file then
                    book_count = book_count + 1
                    if #covers < max_covers then
                        local bookinfo, found_at = getBookInfoWithFallback(entry.path)
                        if bookinfo and bookinfo.cover_bb
                                and bookinfo.has_cover and bookinfo.cover_fetched
                                and not bookinfo.ignore_cover then
                            if found_at ~= entry.path then
                                tryMigrateBookInfoPath(found_at, entry.path)
                            end
                            local bb = copy_bb and bookinfo.cover_bb:copy() or bookinfo.cover_bb
                            table.insert(covers, { data = bb, w = bookinfo.cover_w, h = bookinfo.cover_h })
                        end
                    end
                elseif entry.path and not entry.is_go_up and not entry.path:match("/%.$") then
                    table.insert(subdirs, entry.path)
                end
            end

            if max_depth > 0 then
                for _, sub_path in ipairs(subdirs) do
                    local remaining = max_covers - #covers
                    local sub_covers, sub_count = collectCoversFromDir(
                        sub_path, chooser,
                        remaining > 0 and remaining or 0,
                        max_depth - 1, copy_bb)
                    book_count = book_count + sub_count
                    for _, c in ipairs(sub_covers) do
                        if #covers < max_covers then
                            table.insert(covers, c)
                        elseif copy_bb and c.data and c.data.free then
                            c.data:free()
                        end
                    end
                end
            end

            return covers, book_count
        end

        -- setting
        function BooleanSetting(text, name, default)
            local self = { text = text }
            self.get = function()
                local setting = BookInfoManager:getSetting(name)
                if default then return not setting end -- false is stored as nil, so we need or own logic for boolean default
                return setting
            end
            self.toggle = function() return BookInfoManager:toggleSetting(name) end
            return self
        end

        local settings = {
            crop_to_fit = BooleanSetting(_("Crop folder custom image"), "folder_crop_custom_image", true),
            name_centered = BooleanSetting(_("Folder name centered"), "folder_name_centered", true),
            show_folder_name = BooleanSetting(_("Show folder name"), "folder_name_show", true),
            show_item_count = BooleanSetting(_("Show item count on folder covers"), "folder_item_count_show", true),
            name_opaque = BooleanSetting(_("Folder name opaque background"), "folder_name_opaque", true),
            gallery_mode = BooleanSetting(_("Gallery view"), "folder_gallery_mode"),
        }

        -- cover item
        function MosaicMenuItem:update(...)
            -- Guard: block update() while ancestor cover is shown but bookinfo isn't
            -- in the DB yet, to prevent dimension mismatches and ghost pixels.
            if self._zen_ancestor_cover then
                if self.entry and (self.entry.is_file or self.entry.file) then
                    local _p = self.entry.path or self.entry.file
                    if _p and not BookInfoManager:getBookInfo(_p, true) then
                        return  -- bookinfo still nil; keep ancestor cover
                    end
                end
                self._zen_ancestor_cover = nil
                self.refresh_dimen = nil  -- force full-cell repaint to clear ancestor ghost
            end

            original_update(self, ...)
            if self._foldercover_processed or self.menu.no_refresh_covers then return end
            -- For file items CoverBrowser must have enabled cover rendering and set mandatory.
            -- For folder items (incl. search results) we always attempt it regardless.
            if (self.entry.is_file or self.entry.file) then
                if not self.do_cover_image or not self.mandatory then return end
            end

            -- For moved books: render cover from ancestor bookinfo instead of FakeCover
            -- while KOReader's extraction runs. Standard rendering takes over on update.
            local _resolved_path = self.entry.path or self.entry.file
            if (self.entry.is_file or self.entry.file) and _resolved_path then
                local path = _resolved_path
                local bookinfo = BookInfoManager:getBookInfo(path, true)
                if not bookinfo then
                    local ancestor_bi, ancestor_path = getBookInfoWithFallback(path)
                    if ancestor_bi and ancestor_path ~= path and ancestor_bi.cover_bb then
                        -- Copy the blitbuffer: BookInfoManager frees its cached copy
                        -- after extraction; painting a freed buffer crashes.
                        local cover_bb_copy = ancestor_bi.cover_bb:copy()
                        local border = Folder.face.border_size
                        local max_w = self.width - 2 * border
                        local bh = self.height - 2 * border
                        local portrait_w, portrait_h
                        if bh * 2 <= max_w * 3 then
                            portrait_h = bh
                            portrait_w = math.floor(bh * 2 / 3)
                        else
                            portrait_w = max_w
                            portrait_h = math.min(math.floor(max_w * 3 / 2), bh)
                        end
                        local cover_frame = FrameContainer:new {
                            padding     = 0,
                            bordersize  = border,
                            width       = portrait_w + 2 * border,
                            height      = portrait_h + 2 * border,
                            background  = Blitbuffer.COLOR_LIGHT_GRAY,
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
                            dimen = { w = self.width, h = self.height },
                            cover_frame,
                        }
                        if self._underline_container[1] then
                            self._underline_container[1]:free()
                        end
                        self._underline_container[1] = overlap
                        -- Mark this item so update() calls are blocked until bookinfo
                        -- is available at the new path (see flag check at top of update).
                        self._zen_ancestor_cover = true
                        -- Best-effort DB migration for next standard render cycle.
                        if not zen_migrated_paths[path] then
                            zen_migrated_paths[path] = true
                            tryMigrateBookInfoPath(ancestor_path, path)
                        end
                        return
                    end
                    -- No ancestor cover found (genuinely new/unindexed file).
                    -- Replace KOReader's FakeCover with a clean portrait-sized
                    -- placeholder so there is never a size mismatch between what
                    -- sits on the e-ink panel and the real cover that will replace
                    -- it.  Using the same portrait dimensions as the real cover
                    -- means the repaint region when bookinfo arrives covers every
                    -- pixel that our placeholder occupied — no ghost border remains.
                    -- This also survives navigate-away-and-back: widget instances
                    -- are recreated on return, so a flag on the old instance would
                    -- be lost; overwriting _underline_container[1] here works on
                    -- every render regardless of prior state.
                    do
                        local border = Folder.face.border_size
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
                        local placeholder = FrameContainer:new {
                            padding       = 0,
                            bordersize    = border,
                            width         = portrait_w + 2 * border,
                            height        = portrait_h + 2 * border,
                            background    = Blitbuffer.COLOR_LIGHT_GRAY,
                            overlap_align = "center",
                            CenterContainer:new {
                                dimen = { w = portrait_w, h = portrait_h },
                                VerticalSpan:new { width = 1 },
                            },
                        }
                        if self._underline_container[1] then
                            self._underline_container[1]:free()
                        end
                        self._underline_container[1] = OverlapGroup:new {
                            dimen = { w = self.width, h = self.height },
                            placeholder,
                        }
                    end
                    return
                end
                if bookinfo and bookinfo.cover_fetched
                        and (bookinfo.ignore_cover or not bookinfo.has_cover) then
                    local border     = Folder.face.border_size
                    local max_w      = self.width  - 2 * border
                    local bh         = self.height - 2 * border
                    local portrait_w, portrait_h
                    if bh * 2 <= max_w * 3 then
                        portrait_h = bh
                        portrait_w = math.floor(bh * 2 / 3)
                    else
                        portrait_w = max_w
                        portrait_h = math.min(math.floor(max_w * 3 / 2), bh)
                    end
                    local dimen        = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }
                    local centered_top = math.floor((self.height - dimen.h) / 2)
                    -- Plain gray square — text goes in the overlay below, not inside.
                    local gray_frame = FrameContainer:new {
                        padding       = 0,
                        bordersize    = border,
                        width         = dimen.w,
                        height        = dimen.h,
                        background    = Blitbuffer.COLOR_LIGHT_GRAY,
                        overlap_align = "center",
                        CenterContainer:new {
                            dimen = { w = portrait_w, h = portrait_h },
                            VerticalSpan:new { width = 1 },
                        },
                    }
                    -- Filename overlay — mirrors folder_name_widget in _setFolderCover.
                    -- Uses self.text (filename + extension) at a small font size so it
                    -- fits comfortably inside portrait covers even on tight grids.
                    -- Respects the same "centered / bottom" and "opaque background"
                    -- Zen settings that control folder name display.
                    local fname = self.text or ""
                    if fname:match("/$") then fname = fname:sub(1, -2) end
                    local name_fs = math.min(13, math.max(8, math.floor(portrait_h / 6)))
                    local NameContainer = settings.name_centered.get() and CenterContainer or BottomContainer
                    local name_text = TextBoxWidget:new {
                        text      = fname,
                        face      = Font:getFace("cfont", name_fs),
                        width     = portrait_w,
                        alignment = "center",
                        height    = math.floor(portrait_h / 3),
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                    }
                    local name_bg = FrameContainer:new {
                        padding    = 0,
                        bordersize = Folder.face.border_size,
                        background = Blitbuffer.COLOR_WHITE,
                        name_text,
                    }
                    local filename_widget = NameContainer:new {
                        dimen = dimen,
                        settings.name_opaque.get()
                            and name_bg
                            or AlphaContainer:new { alpha = Folder.face.alpha, name_bg },
                        overlap_align = "center",
                    }
                    -- Use the same OverlapGroup → VerticalGroup → CenterContainer → OverlapGroup{dimen}
                    -- nesting as _setFolderCover so that find_cover_frame in
                    -- browser_cover_rounded_corners can locate and mask the FrameContainer
                    -- when the rounded corners feature is enabled.
                    local widget = OverlapGroup:new {
                        dimen = { w = self.width, h = self.height },
                        VerticalGroup:new {
                            VerticalSpan:new { width = centered_top },
                            CenterContainer:new {
                                dimen = { w = self.width, h = dimen.h },
                                OverlapGroup:new {
                                    dimen = dimen,
                                    gray_frame,
                                    filename_widget,
                                },
                            },
                        },
                    }
                    if self._underline_container[1] then
                        self._underline_container[1]:free()
                    end
                    self._underline_container[1] = widget
                end
                return
            end

            -- Folder items only below this point.
            local dir_path = self.entry and self.entry.path
            if not dir_path then return end

            local cover_file = findCover(dir_path) --custom
            if cover_file then
                local success, w, h = pcall(function()
                    local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
                    tmp_img:_render()
                    local orig_w = tmp_img:getOriginalWidth()
                    local orig_h = tmp_img:getOriginalHeight()
                    tmp_img:free()
                    return orig_w, orig_h
                end)
                if success then
                    self._foldercover_processed = true
                    self:_setFolderCover { file = cover_file, w = w, h = h, scale_to_fit = settings.crop_to_fit.get() }
                    return
                end
            end

            local _fm = require("apps/filemanager/filemanager").instance
            local _main_chooser = _fm and _fm.file_chooser
            -- Prefer the main file chooser so all files are visible regardless of
            -- how the current menu was opened (e.g. move-dialog uses a dirs-only
            -- chooser which returns zero book entries and a blank cover).
            local _chooser = _main_chooser
                or (self.menu.genItemTableFromPath and self.menu)
            if not _chooser then
                self._foldercover_processed = true
                return
            end
            _chooser._dummy = true
            local entries = _chooser:genItemTableFromPath(dir_path) -- sorted
            _chooser._dummy = false
            if not entries then
                self._foldercover_processed = true
                return
            end

            -- Collect covers recursively (bubbles up from child folders).
            local is_gallery = settings.gallery_mode.get()
            local max_covers = is_gallery and 4 or 1
            local covers, book_count = collectCoversFromDir(dir_path, _chooser, max_covers, 2, is_gallery, entries)

            if is_gallery then
                if #covers > 0 then self._foldercover_processed = true end
                self:_setFolderCover { gallery = covers, book_count = book_count }
            else
                if #covers > 0 then
                    self._foldercover_processed = true
                    self:_setFolderCover { data = covers[1].data, w = covers[1].w, h = covers[1].h, book_count = book_count }
                else
                    -- Do NOT set _foldercover_processed here: leave it nil so the
                    -- next updateItems() re-scans once cover extraction completes.
                    self:_setFolderCover { no_image = true, book_count = book_count }
                end
            end
        end

        function MosaicMenuItem:_setFolderCover(img)
            -- Compute the largest 2:3 portrait box that fits within the cell.
            -- Uses both self.width and self.height so the cover scales correctly
            -- for any grid layout (2×2, 4×3, etc.), matching the dual-constraint
            -- approach used in browser_cover_mosaic_uniform.lua.
            local border      = Folder.face.border_size  -- Size.border.thin
            local max_w       = self.width  - 2 * border
            local bh          = self.height - 2 * border
            local available_h = bh
            local portrait_w, portrait_h
            if available_h * 2 <= max_w * 3 then
                -- Height-constrained: cell is wide enough for a 2:3 portrait box.
                portrait_h = available_h
                portrait_w = math.floor(available_h * 2 / 3)
            else
                -- Width-constrained: cell is narrower than portrait; clamp to width.
                portrait_w = max_w
                portrait_h = math.min(math.floor(max_w * 3 / 2), available_h)
            end

            local size  = { w = portrait_w, h = portrait_h }
            local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

            -- All images are fit-to-box (width=portrait_w, height=portrait_h, no
            -- explicit scale_factor) so KOReader auto-scales to min(w,h) ratio.
            -- This guarantees zero overflow regardless of source aspect ratio.
            local image_widget
            if img.gallery then
                local covers = img.gallery
                local sep = 1
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
                    local c = covers[i]
                    local cd = cell_dims[i]
                    if c then
                        cells[i] = CenterContainer:new {
                            dimen = { w = cd.w, h = cd.h },
                            ImageWidget:new {
                                image  = c.data,
                                width  = cd.w,
                                height = cd.h,
                            },
                        }
                    else
                        -- Empty slot: transparent widget with correct dimensions so the
                        -- layout engine sizes the row/column correctly.  The outer
                        -- FrameContainer's LIGHT_GRAY background shows through.
                        cells[i] = CenterContainer:new {
                            dimen = { w = cd.w, h = cd.h },
                            VerticalSpan:new { width = 1 },
                        }
                    end
                end
                image_widget = FrameContainer:new {
                    padding = 0,
                    bordersize = border,
                    width = dimen.w, height = dimen.h,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    CenterContainer:new {
                        dimen = { w = portrait_w, h = portrait_h },
                        VerticalGroup:new {
                            HorizontalGroup:new {
                                cells[1],
                                LineWidget:new { background = Blitbuffer.COLOR_WHITE, dimen = { w = sep, h = half_h } },
                                cells[2],
                            },
                            LineWidget:new { background = Blitbuffer.COLOR_WHITE, dimen = { w = portrait_w, h = sep } },
                            HorizontalGroup:new {
                                cells[3],
                                LineWidget:new { background = Blitbuffer.COLOR_WHITE, dimen = { w = sep, h = half_h2 } },
                                cells[4],
                            },
                        },
                    },
                    overlap_align = "center",
                }
            elseif img.no_image then
                image_widget = FrameContainer:new {
                    padding = 0,
                    bordersize = border,
                    width = dimen.w, height = dimen.h,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    CenterContainer:new {
                        dimen = { w = portrait_w, h = portrait_h },
                        VerticalSpan:new { width = 1 },
                    },
                    overlap_align = "center",
                }
            else
                image_widget = FrameContainer:new {
                    padding = 0,
                    bordersize = border,
                    width = dimen.w, height = dimen.h,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    CenterContainer:new {
                        dimen = { w = portrait_w, h = portrait_h },
                        ImageWidget:new {
                            file   = img.file,
                            image  = img.data,
                            width  = portrait_w,
                            height = portrait_h,
                        },
                    },
                    overlap_align = "center",
                }
            end

            -- Pass inner image dimensions; the FrameContainer (bordersize) brings the
            -- banner flush with the outer cover edge (dimen.w = size.w + 2*border_size).
            -- Cover geometry is stored on self so the paintTo wrapper can position
            -- the badge correctly without walking the widget tree at paint time.
            self._zen_cover_dimen = dimen
            self._zen_folder_count = (settings.show_item_count.get() and img.book_count and img.book_count > 0)
                and img.book_count or nil
            local directory = self:_getTextBoxes { w = size.w, h = size.h }

            local folder_name_widget
            if settings.show_folder_name.get() then
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

            -- Badge is now drawn in paintTo (paint-time, scales with corner_mark_size).
            local nbitems_widget = VerticalSpan:new { width = 0 }

            -- Center the image exactly like a book cover so folder covers align with
            -- their row neighbours in all grid layouts.
            -- Loose grids (e.g. 3×2): enough space above the image → horizontal tab
            --   lines float above the cover (classic look).
            -- Tight grids (e.g. 3×3): no clear space above → vertical spine lines on
            --   the left of the cover, mirroring list mode.
            -- In both cases the line closer to the cover is longer; the outer one is
            -- shorter.  Rounded corners inset the lines on both sides.
            local centered_top  = math.floor((self.height - dimen.h) / 2)
            local top_h         = 2 * (Folder.edge.thick + Folder.edge.margin)
            local use_top_lines = centered_top >= top_h

            local plug = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            local rounded = plug
                and type(plug.config) == "table"
                and type(plug.config.features) == "table"
                and plug.config.features.browser_cover_rounded_corners == true
            local line_inset = rounded and Screen:scaleBySize(4) or 0

            local decoration_layer
            if use_top_lines then
                -- Horizontal lines above the image.
                -- line1 (top / farther from cover): shorter.  line2 (bottom / closer): longer.
                local line1_w = math.max(0, math.floor(dimen.w * (Folder.edge.width ^ 2)) - 2 * line_inset)
                local line2_w = math.max(0, math.floor(dimen.w * Folder.edge.width)       - 2 * line_inset)
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
                -- Vertical spine lines to the left of the cover image.
                -- line1 (outer / farther from cover): shorter.  line2 (inner / closer): longer.
                local spine_gap = Screen:scaleBySize(9)
                local spine_x   = math.max(0, math.floor((self.width - dimen.w) / 2))
                local line1_h   = math.max(0, math.floor(dimen.h * (Folder.edge.width ^ 2)) - 2 * line_inset)
                local line2_h   = math.max(0, math.floor(dimen.h * Folder.edge.width)       - 2 * line_inset)
                decoration_layer = LeftContainer:new {
                    dimen = { w = self.width, h = self.height },
                    HorizontalGroup:new {
                        HorizontalSpan:new { width = math.max(0, spine_x - spine_gap) },
                        CenterContainer:new {
                            dimen = { w = Folder.edge.thick, h = self.height },
                            LineWidget:new {
                                background = Folder.edge.color,
                                dimen = { w = Folder.edge.thick, h = line1_h },
                            },
                        },
                        HorizontalSpan:new { width = Folder.edge.margin },
                        CenterContainer:new {
                            dimen = { w = Folder.edge.thick, h = self.height },
                            LineWidget:new {
                                background = Folder.edge.color,
                                dimen = { w = Folder.edge.thick, h = line2_h },
                            },
                        },
                    },
                }
            end

            local widget = OverlapGroup:new {
                dimen = { w = self.width, h = self.height },
                -- Layer 1: image cover + overlays, centered to match adjacent book covers.
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
                -- Layer 2: tab lines above (loose grids) or spine lines left (tight grids).
                decoration_layer,
            }
            if self._underline_container[1] then
                local previous_widget = self._underline_container[1]
                previous_widget:free()
            end

            self._underline_container[1] = widget
        end

        function MosaicMenuItem:_getTextBoxes(dimen)
            -- Use entry-counted books when available (correct in search results and
            -- move-dialog folders where mandatory uses a different/absent glyph format).
            local nb_font_size = dimen.badge_font_size or Folder.face.nb_items_font_size

            -- Reserve a fixed height so the directory text doesn't crowd the badge
            -- area at the top of the cover.  Use the same font as before for the
            -- height probe so we don't need to know corner_mark_size here.
            local badge_ref = TextWidget:new {
                text = "0",
                face = Font:getFace("cfont", nb_font_size),
                bold = true,
                padding = 0,
            }
            local badge_h = badge_ref:getSize().h
            badge_ref:free()

            local text = self.text
            if text:match("/$") then text = text:sub(1, -2) end -- remove "/"
            text = BD.directory(text)
            local available_height = dimen.h - 2 * badge_h
            local dir_font_size = Folder.face.dir_max_font_size
            local min_font_size = 14  -- shrink to this before allowing wrap/overflow
            local x_pad = Screen:scaleBySize(4)  -- horizontal breathing room
            local text_w = dimen.w - 2 * x_pad
            local directory

            -- Phase 1: shrink font until the text fits on a single line within
            -- text_w (cover width minus horizontal padding).  Using a single-line
            -- TextWidget probe avoids the awkward two-words-per-line wrapping that
            -- happens at large font sizes on narrow covers.
            local probe
            local single_line_fits = false
            while dir_font_size >= min_font_size do
                if probe then probe:free() end
                probe = TextWidget:new {
                    text    = text,
                    face    = Font:getFace("cfont", dir_font_size),
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

            -- Always render at dimen.w so the background FrameContainer spans the
            -- full cover width.  x_pad is only used in the probe above to ensure
            -- the chosen font has comfortable breathing room; the natural centering
            -- of the text inside the full-width widget provides the visual padding.
            if single_line_fits then
                probe:free()
                directory = TextBoxWidget:new {
                    text      = text,
                    face      = Font:getFace("cfont", dir_font_size),
                    width     = dimen.w,
                    alignment = "center",
                    bold      = true,
                }
            else
                -- Could not fit on one line even at min_font_size; allow wrap +
                -- ellipsis so very long names are still legible.
                if probe then probe:free() end
                directory = TextBoxWidget:new {
                    text      = text,
                    face      = Font:getFace("cfont", min_font_size),
                    width     = dimen.w,
                    alignment = "center",
                    bold      = true,
                    height    = available_height,
                    height_adjust = true,
                    height_overflow_show_ellipsis = true,
                }
            end

            return directory
        end

        -- list mode cover
        do
            local ListMenu = require("listmenu")
            local ListMenuItem = get_upvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
            if ListMenuItem then
                local original_list_update = ListMenuItem.update

                function ListMenuItem:update(...)
                    original_list_update(self, ...)
                    if self._foldercover_processed or self.menu.no_refresh_covers then return end
                    -- Only handle folder items; file items are handled by CoverBrowser directly.
                    -- Do not gate on mandatory: search results don't set it on directory items.
                    if self.entry.is_file or self.entry.file then return end
                    local dir_path = self.entry and self.entry.path
                    if not dir_path then return end

                    local cover_file = findCover(dir_path)
                    if cover_file then
                        local success, w, h = pcall(function()
                            local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
                            tmp_img:_render()
                            local orig_w = tmp_img:getOriginalWidth()
                            local orig_h = tmp_img:getOriginalHeight()
                            tmp_img:free()
                            return orig_w, orig_h
                        end)
                        if success then
                            self._foldercover_processed = true
                            self:_setListFolderCover { file = cover_file, w = w, h = h, scale_to_fit = settings.crop_to_fit.get() }
                            return
                        end
                    end

                    local _fm_inst = require("apps/filemanager/filemanager").instance
                    local _main_ch = _fm_inst and _fm_inst.file_chooser
                    local _chooser = _main_ch
                        or (self.menu.genItemTableFromPath and self.menu)
                    if not _chooser then
                        self._foldercover_processed = true
                        return
                    end
                    _chooser._dummy = true
                    local entries = _chooser:genItemTableFromPath(dir_path)
                    _chooser._dummy = false
                    if not entries then
                        self._foldercover_processed = true
                        return
                    end

                    -- Collect covers recursively (bubbles up from child folders).
                    local is_gallery = settings.gallery_mode.get()
                    local max_covers = is_gallery and 4 or 1
                    local covers, book_count_l = collectCoversFromDir(dir_path, _chooser, max_covers, 2, is_gallery, entries)

                    if is_gallery then
                        if #covers > 0 then self._foldercover_processed = true end
                        self:_setListFolderCover { gallery = covers, book_count = book_count_l }
                    else
                        self._foldercover_processed = true
                        if #covers > 0 then
                            self:_setListFolderCover { data = covers[1].data, w = covers[1].w, h = covers[1].h, book_count = book_count_l }
                        else
                            self:_setListFolderCover { no_image = true, book_count = book_count_l }
                        end
                    end
                end

                function ListMenuItem:_setListFolderCover(img)
                    local underline_h = 1 -- same as self.underline_h = 1 set in ListMenuItem:init()
                    local border_size = Size.border.thin
                    local dimen_h = self.height - 2 * underline_h
                    local cover_zone_w = dimen_h -- squared, matches book cover zone in list mode
                    local max_img = dimen_h - 2 * border_size

                    -- Font sizes scaled to item height, matching ListMenuItem's _fontSize formula.
                    local scale_by_size = Screen:scaleBySize(1000000) * (1 / 1000000)
                    local function _fontSize(nominal, max_size)
                        local fs = math.floor(nominal * dimen_h * (1 / 64) / scale_by_size)
                        if max_size and fs >= max_size then return max_size end
                        return fs
                    end

                    -- Build the cover image widget (left side, squared zone, same as book covers).
                    -- spine_x = left edge of the cover image within the cover zone (for spine line placement).
                    local wleft
                    local spine_x
                    if img.gallery then
                        local covers = img.gallery
                        local gall_h = max_img
                        local gall_w = math.floor(max_img * 2 / 3)  -- 2:3 portrait, matches book covers in list mode
                        local cover_w = gall_w + 2 * border_size
                        local cover_h = gall_h + 2 * border_size
                        spine_x = math.max(0, math.floor((cover_zone_w - cover_w) / 2))
                        if #covers == 0 then
                            -- No covers extracted yet; show placeholder and keep retrying.
                            wleft = CenterContainer:new {
                                dimen = { w = cover_zone_w, h = dimen_h },
                                FrameContainer:new {
                                    width = cover_w, height = cover_h,
                                    margin = 0, padding = 0, bordersize = border_size,
                                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                                    CenterContainer:new {
                                        dimen = { w = gall_w, h = gall_h },
                                        VerticalSpan:new { width = 1 },
                                    },
                                },
                            }
                        else
                            local sep = 1
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
                                local c = covers[i]
                                local cd = cell_dims[i]
                                if c then
                                    cells[i] = CenterContainer:new {
                                        dimen = { w = cd.w, h = cd.h },
                                        ImageWidget:new {
                                            image  = c.data,
                                            width  = cd.w,
                                            height = cd.h,
                                        },
                                    }
                                else
                                    cells[i] = CenterContainer:new {
                                        dimen = { w = cd.w, h = cd.h },
                                        VerticalSpan:new { width = 1 },
                                    }
                                end
                            end
                            wleft = CenterContainer:new {
                                dimen = { w = cover_zone_w, h = dimen_h },
                                FrameContainer:new {
                                    width = cover_w, height = cover_h,
                                    margin = 0, padding = 0, bordersize = border_size,
                                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                                    CenterContainer:new {
                                        dimen = { w = gall_w, h = gall_h },
                                        VerticalGroup:new {
                                            HorizontalGroup:new {
                                                cells[1],
                                                LineWidget:new { background = Blitbuffer.COLOR_WHITE, dimen = { w = sep, h = half_h } },
                                                cells[2],
                                            },
                                            LineWidget:new { background = Blitbuffer.COLOR_WHITE, dimen = { w = gall_w, h = sep } },
                                            HorizontalGroup:new {
                                                cells[3],
                                                LineWidget:new { background = Blitbuffer.COLOR_WHITE, dimen = { w = sep, h = half_h2 } },
                                                cells[4],
                                            },
                                        },
                                    },
                                },
                            }
                        end
                    elseif img.no_image then
                        local portrait_w = math.floor(max_img * 2 / 3)  -- 2:3, matches gallery and book covers
                        local cover_w = portrait_w + 2 * border_size
                        spine_x = math.max(0, math.floor((cover_zone_w - cover_w) / 2))
                        wleft = CenterContainer:new {
                            dimen = { w = cover_zone_w, h = dimen_h },
                            FrameContainer:new {
                                width = cover_w,
                                height = max_img + 2 * border_size,
                                margin = 0, padding = 0, bordersize = border_size,
                                background = Blitbuffer.COLOR_LIGHT_GRAY,
                                CenterContainer:new {
                                    dimen = { w = portrait_w, h = max_img },
                                    VerticalSpan:new { width = 1 },
                                },
                            },
                        }
                    else
                        local img_options = { file = img.file, image = img.data }
                        if img.scale_to_fit then
                            img_options.scale_factor = math.max(max_img / img.w, max_img / img.h)
                            img_options.width = max_img
                            img_options.height = max_img
                        else
                            img_options.scale_factor = math.min(max_img / img.w, max_img / img.h)
                        end
                        local image = ImageWidget:new(img_options)
                        image:_render()
                        local image_size = image:getSize()
                        local cover_w = image_size.w + 2 * border_size
                        spine_x = math.max(0, math.floor((cover_zone_w - cover_w) / 2))
                        wleft = CenterContainer:new {
                            dimen = { w = cover_zone_w, h = dimen_h },
                            FrameContainer:new {
                                width = cover_w,
                                height = image_size.h + 2 * border_size,
                                margin = 0, padding = 0, bordersize = border_size,
                                image,
                            },
                        }
                    end

                    -- Spine lines slightly offset from the left edge of the cover image.
                    -- line1 (outer, farther from cover) = shorter; line2 (inner, closer) = longer.
                    -- Mirrors the vertical-spine proportions used in _setFolderCover (tight mosaic grids).
                    local plug_rc = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
                    local rounded = plug_rc
                        and type(plug_rc.config) == "table"
                        and type(plug_rc.config.features) == "table"
                        and plug_rc.config.features.browser_cover_rounded_corners == true
                    local line_inset = rounded and Screen:scaleBySize(4) or 0
                    local line1_h = math.max(0, math.floor(dimen_h * (Folder.edge.width ^ 2)) - 2 * line_inset)
                    local line2_h = math.max(0, math.floor(dimen_h *  Folder.edge.width)       - 2 * line_inset)
                    local spine_gap = Screen:scaleBySize(8)
                    self._cover_frame = wleft[1]  -- FrameContainer child; used by paintTo for rounded corners
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

                    -- Right-side item count widget.
                    local pad = Screen:scaleBySize(10)
                    local wmain_left_pad = Screen:scaleBySize(5) -- narrower padding when cover present
                    -- Use entry-counted books when available; fall back to mandatory parsing
                    -- for custom-cover items that skip entry enumeration.
                    local count_num = img.book_count ~= nil and img.book_count
                        or tonumber((self.mandatory or "0"):match("^%s*(%d+)")) or 0
                    local fs_right = _fontSize(16, 20)
                    local label_str = tostring(count_num) .. " " .. (count_num == 1 and _("Book") or _("Books"))
                    local wright = TextWidget:new{
                        text = label_str,
                        face = Font:getFace("cfont", fs_right),
                        padding = 0,
                    }
                    local wright_w = wright:getWidth()
                    local wright_right_pad = pad

                    -- Folder name widget (middle area).
                    local text = self.text
                    if text:match("/$") then text = text:sub(1, -2) end
                    text = BD.directory(text)
                    local wmain_w = self.width - cover_zone_w - wmain_left_pad - pad - wright_w - wright_right_pad
                    local wname = TextBoxWidget:new {
                        text = text,
                        face = Font:getFace("cfont", _fontSize(20, 24)),
                        width = math.max(wmain_w, 0),
                        alignment = "left",
                        bold = true,
                        height = dimen_h,
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                    }

                    local dimen = { w = self.width, h = dimen_h }
                    local widget = OverlapGroup:new {
                        dimen = dimen,
                        wleft,
                        LeftContainer:new {
                            dimen = dimen,
                            HorizontalGroup:new {
                                HorizontalSpan:new { width = cover_zone_w },
                                HorizontalSpan:new { width = wmain_left_pad },
                                wname,
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

        -- Hook CoverBrowser's onBookInfoUpdated.
        -- Flash suppression: the per-item _zen_ancestor_cover flag in update()
        -- blocks original_update() from rebuilding a FakeCover while bookinfo is
        -- not yet in the DB at the item's actual path.  Once extraction completes
        -- (which is when this event fires), the guard detects the now-available
        -- bookinfo, clears itself, and lets original_update() install the real cover.
        -- So orig_biu MUST run for migrated paths — suppressing it would freeze the
        -- ancestor cover on screen indefinitely.  Just clear the migration flag here
        -- so future update() calls don't re-attempt the SQL migration.
        if type(plugin.onBookInfoUpdated) == "function" then
            local orig_biu = plugin.onBookInfoUpdated
            function plugin:onBookInfoUpdated(filepath, bookinfo)
                -- Clear migration flag (prevents redundant SQL on future update calls)
                -- but always let orig_biu run so the item gets its real cover.
                zen_migrated_paths[filepath] = nil
                orig_biu(self, filepath, bookinfo)
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
                    if
                        not getMenuItem( -- already exists ?
                            menu_items.filebrowser_settings,
                            _("Mosaic and detailed list settings"),
                            setting.text
                        )
                    then
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

    -- `require("coverbrowser")` fails at plugin-init time because the plugin
    -- hasn't been instantiated yet.  By the time FileManager:setupLayout() runs
    -- (inside FileManager:init()), all plugins — including coverbrowser — have
    -- already been registered on `self`.  Hook there instead.
    local FileManager = require("apps/filemanager/filemanager")
    local orig_fm_setupLayout = FileManager.setupLayout
    local coverbrowser_patched = false

    FileManager.setupLayout = function(self)
        orig_fm_setupLayout(self)
        if not coverbrowser_patched and self.coverbrowser then
            patchCoverBrowser(self.coverbrowser)
            coverbrowser_patched = true
            -- The file list may have already rendered before patching completed.
            -- Schedule a refresh so our cover rendering runs on all visible items.
            local UIManager = require("ui/uimanager")
            UIManager:scheduleIn(0, function()
                if self.file_chooser then
                    self.file_chooser:updateItems()
                end
            end)
        end
    end
end


return apply_browser_folder_cover

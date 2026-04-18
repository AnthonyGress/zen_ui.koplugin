local function apply_context_menu()
    --[[
        Replaces the long-hold file/folder context menu in the file browser with
        a clean, minimal layout:

            New folder
            Move          (opens PathChooser to pick destination, then moves immediately)
            Add/Remove from favorites
            Description   (files only: shows book description if one exists)
            Book status ▶ (files only: Unread · Reading · On hold · Finished)
            View ▶        (current dir only: Mosaic · List (detailed) · List (basic))
            Edit ▶        (anchored submenu at right edge: Select · Rename · Delete · Cut · Copy · Paste)

        Everything else (book info, collections, open with, reset, status rows,
        scripts, converter, shortcuts, etc.) is intentionally hidden.
        No feature toggle – always active.
    ]]

    local BD           = require("ui/bidi")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Device       = require("device")
    local FileChooser  = require("ui/widget/filechooser")
    local FileManager  = require("apps/filemanager/filemanager")
    local PathChooser  = require("ui/widget/pathchooser")
    local UIManager    = require("ui/uimanager")
    local _            = require("gettext")
    local C_           = _.pgettext
    local zen_plugin   = rawget(_G, "__ZEN_UI_PLUGIN")

    -- ── MoveChooser ──────────────────────────────────────────────────────────
    -- PathChooser subclass for picking a move destination.
    --   • Cover-browser rendering applies automatically when the coverbrowser
    --     plugin is active (it hooks MosaicMenuItem.update on FileChooser items).
    --   • genItemTable strips hidden folders (.sdr, .thumbnails, etc.) and the
    --     go-up row — the list is intentionally flat.
    --   • onMenuSelect fires immediately on single tap (no navigate-into behaviour).
    -- _zen_no_forced_repaint: opt out of the partial_page_repaint forced flush.
    -- MoveChooser is a transient overlay — the full-page E-ink flash it causes
    -- when folder count < perpage is visually jarring and unnecessary.
    local MoveChooser = PathChooser:extend{ _zen_no_forced_repaint = true }

    -- Build a flat, depth-first folder list from root up to 2 levels deep.
    -- Each folder is immediately followed by its own children so the list reads:
    --   Home/
    --   FolderA               ← child of root
    --   FolderA/Sub1          ← child of FolderA (level 2)
    --   FolderA/Sub2
    --   FolderB               ← next child of root
    --   FolderB/Sub1
    --   …
    function MoveChooser:genItemTableFromPath(path)
        local ffiUtil3 = require("ffi/util")
        local lfs3     = require("libs/libkoreader-lfs")
        local BD3      = require("ui/bidi")
        local root     = ffiUtil3.realpath(path) or path
        local MAX_DEPTH = 3
        local items    = {}

        -- Root / Home entry — omitted only when the book already lives there
        -- (moving it would be a no-op).
        if not self.src_dir or self.src_dir ~= root then
            table.insert(items, {
                text           = ffiUtil3.basename(root),
                path           = root,
                is_file        = false,
                bidi_wrap_func = BD3.directory,
                mandatory      = self:getMenuItemMandatory({ path = root }),
            })
        end

        local function scan(dir_path, depth)
            local ok3, iter3, dir_obj3 = pcall(lfs3.dir, dir_path)
            if not ok3 then return end
            local subdirs = {}
            for fname in iter3, dir_obj3 do
                if fname ~= "." and fname ~= ".."
                        and not fname:match("^%.")
                        and self:show_dir(fname) then
                    local fpath = dir_path .. "/" .. fname
                    if lfs3.attributes(fpath, "mode") == "directory" then
                        table.insert(subdirs, { name = fname, path = fpath })
                    end
                end
            end
            table.sort(subdirs, function(a, b) return a.name < b.name end)
            for _, sub in ipairs(subdirs) do
                local rel = sub.path:sub(#root + 2)  -- e.g. "Fantasy/Pratchett"
                table.insert(items, {
                    text           = rel,
                    path           = sub.path,
                    is_file        = false,
                    bidi_wrap_func = BD3.directory,
                    mandatory      = self:getMenuItemMandatory({ path = sub.path }),
                })
                if depth < MAX_DEPTH then
                    scan(sub.path, depth + 1)
                end
            end
        end

        scan(root, 1)
        return items
    end

    function MoveChooser:onMenuSelect(item)
        local path = item and item.path
        if not path then return true end
        local ffiUtil2 = require("ffi/util")
        local real = ffiUtil2.realpath(path)
        if not real then return true end
        local lfs2 = require("libs/libkoreader-lfs")
        if lfs2.attributes(real, "mode") == "directory" then
            if self.onConfirm then self.onConfirm(real) end
            UIManager:close(self)
        end
        return true
    end

    function MoveChooser:onMenuHold() return true end
    -- ─────────────────────────────────────────────────────────────────────────

    local orig_setupLayout = FileManager.setupLayout

    FileManager.setupLayout = function(self)
        orig_setupLayout(self)

        local file_chooser = self.file_chooser
        local file_manager = self

        -- Capture the original showFileDialog installed by setupLayout so we
        -- can delegate to it when not in the home directory.
        local orig_showFileDialog = file_chooser.showFileDialog

        -- Replace the instance-level showFileDialog defined by setupLayout
        file_chooser.showFileDialog = function(self_fc, item)
            -- Delegate to the stock KOReader dialog outside the home directory.
            local g_settings = rawget(_G, "G_reader_settings")
            local home_dir   = g_settings and g_settings:readSetting("home_dir")
            local cur_path   = self_fc.path or ""
            if home_dir then
                local norm_home = home_dir:gsub("/$", "")
                local norm_cur  = cur_path:gsub("/$", "")
                local is_at_or_under_home = norm_cur == norm_home
                    or norm_cur:sub(1, #norm_home + 1) == norm_home .. "/"
                if not is_at_or_under_home then
                    return orig_showFileDialog(self_fc, item)
                end
            end

            local file               = item.path
            local is_file            = item.is_file
            local is_not_parent_folder = not item.is_go_up
            local is_home_dir = (not is_file) and home_dir
                and (file:gsub("/$", "") == home_dir:gsub("/$", ""))

            local function close_dialog()
                UIManager:close(self_fc.file_dialog)
            end

            local function refresh()
                self_fc:refreshPath()
            end

            -- Build dialog header: cover left / text right (OverlapGroup) when a cover is
            -- available; text-only otherwise.  dialog_title is always set (used by the
            -- status sub-dialog and the text-only fallback).
            local dialog_title, dialog_cover_widget, book_description

            -- Open the full-resolution cover art in a fullscreen ImageViewer.
            local function showCoverFullscreen(cover_path)
                local ok2, bim2 = pcall(require, "bookinfomanager")
                if not ok2 then return end
                local bi2 = bim2:getBookInfo(cover_path, true)
                if not bi2 or not bi2.cover_bb or not bi2.has_cover
                    or bi2.ignore_cover then return end
                local ImageViewer = require("ui/widget/imageviewer")
                local iv = ImageViewer:new{
                    image            = bi2.cover_bb,
                    image_disposable = false,
                    fullscreen       = true,
                    with_title_bar   = false,
                }
                function iv:onTap() self:onClose() return true end
                UIManager:show(iv)
            end

            do
                local Screen   = Device.screen
                local SizeR    = require("ui/size")
                local border   = SizeR.border.thin
                local gap      = Screen:scaleBySize(8)
                local dlg_w    = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
                -- inner width available to _added_widgets inside ButtonDialog
                local avail_w  = dlg_w - 2 * (SizeR.border.window + SizeR.padding.button)
                                       - 2 * (SizeR.padding.default + SizeR.margin.default)
                local cover_max_w = Screen:scaleBySize(80)
                local cover_max_h = Screen:scaleBySize(120)

                -- ── Rounded cover corners ─────────────────────────────────────────────
                -- Monkey-patches a FrameContainer instance's paintTo to paint white
                -- quarter-circle masks at each corner (simulating rounded corners) and
                -- redraws a clean border arc, when the "Rounded cover corners" setting
                -- is enabled.  Consistent with browser_cover_rounded_corners.lua.
                local function _zen_apply_rounded_cover(frame_widget, bsz)
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
                        local Blitbuffer_rc = require("ffi/blitbuffer")
                        local wh  = Blitbuffer_rc.COLOR_WHITE
                        local blk = Blitbuffer_rc.COLOR_BLACK
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

                -- Build an OverlapGroup with cover at left edge, text stack at right edge.
                local function makeSideBySide(cover_bb, src_w, src_h, sf, title_str, authors_str, tags_str_arg, on_cover_tap)
                    local rendered_w  = math.floor(src_w * sf)
                    local rendered_h  = math.floor(src_h * sf)
                    local framed_h    = rendered_h + 2 * border
                    local text_col_w  = math.max(avail_w - rendered_w - 2 * border - gap,
                                                 Screen:scaleBySize(60))
                    local ImageWidget     = require("ui/widget/imagewidget")
                    local FrameContainer  = require("ui/widget/container/framecontainer")
                    local LeftContainer   = require("ui/widget/container/leftcontainer")
                    local HorizontalGroup = require("ui/widget/horizontalgroup")
                    local HorizontalSpan  = require("ui/widget/horizontalspan")
                    local TextWidget      = require("ui/widget/textwidget")
                    local VerticalGroup   = require("ui/widget/verticalgroup")
                    local VerticalSpan    = require("ui/widget/verticalspan")
                    local Font            = require("ui/font")
                    local Blitbuffer      = require("ffi/blitbuffer")
                    local Geom            = require("ui/geometry")
                    -- Raw point sizes (not pre-scaled) to match KOReader dialog conventions.
                    local fs_title   = 20
                    local fs_authors = 17
                    local fs_tags    = 14
                    local vstack = VerticalGroup:new{ align = "left" }
                    if title_str then
                        table.insert(vstack, TextWidget:new{
                            text      = title_str,
                            face      = Font:getFace("cfont", fs_title),
                            bold      = true,
                            max_width = text_col_w,
                        })
                    end
                    if authors_str then
                        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                        table.insert(vstack, TextWidget:new{
                            text      = authors_str,
                            face      = Font:getFace("cfont", fs_authors),
                            max_width = text_col_w,
                        })
                    end
                    if tags_str_arg and tags_str_arg ~= "" then
                        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(3) })
                        table.insert(vstack, TextWidget:new{
                            text      = tags_str_arg,
                            face      = Font:getFace("cfont", fs_tags),
                            fgcolor   = Blitbuffer.COLOR_GRAY_3,
                            max_width = text_col_w,
                        })
                    end
                    local cover_frame = FrameContainer:new{
                        padding    = 0,
                        bordersize = border,
                        ImageWidget:new{
                            image            = cover_bb,
                            image_disposable = true,
                            scale_factor     = sf,
                        },
                    }
                    _zen_apply_rounded_cover(cover_frame, border)
                    local cover_component
                    if on_cover_tap then
                        local InputContainer2 = require("ui/widget/container/inputcontainer")
                        local GestureRange2   = require("ui/gesturerange")
                        local cw = rendered_w + 2 * border
                        local wrapper = InputContainer2:new{
                            dimen = Geom:new{ w = cw, h = framed_h },
                            ges_events = {
                                TapCover = {
                                    GestureRange2:new{
                                        ges   = "tap",
                                        range = Geom:new{
                                            x = 0, y = 0,
                                            w = Screen:getWidth(),
                                            h = Screen:getHeight(),
                                        },
                                    },
                                },
                            },
                        }
                        function wrapper:onTapCover(_, ges)
                            if not self.dimen or not ges or not ges.pos then
                                return false
                            end
                            if not self.dimen:contains(ges.pos) then
                                return false
                            end
                            on_cover_tap()
                            return true
                        end
                        wrapper[1] = cover_frame
                        cover_component = wrapper
                    else
                        cover_component = cover_frame
                    end
                    return LeftContainer:new{
                        dimen = Geom:new{ w = avail_w, h = framed_h },
                        HorizontalGroup:new{
                            align = "top",
                            cover_component,
                            HorizontalSpan:new{ width = gap },
                            vstack,
                        },
                    }
                end

                if is_file then
                    local ok, BookInfoManager = pcall(require, "bookinfomanager")
                    local title_str, authors_str, tags_str_local
                    if ok then
                        local bookinfo = BookInfoManager:getBookInfo(file, true)
                        if bookinfo then
                            if not bookinfo.ignore_meta then
                                if bookinfo.title then
                                    title_str   = BD.auto(bookinfo.title)
                                    authors_str = bookinfo.authors and BD.auto(bookinfo.authors) or nil
                                end
                                if bookinfo.keywords and bookinfo.keywords ~= "" then
                                    tags_str_local = bookinfo.keywords
                                        :gsub("%s*[\n;]%s*", ", ")
                                        :gsub("%s+\xC2\xB7%s+", ", ")
                                        :gsub("^,%s*", ""):gsub(",%s*$", "")
                                end
                            end
                            if not bookinfo.ignore_meta and bookinfo.description
                                and bookinfo.description ~= "" then
                                book_description = bookinfo.description
                            end
                            if bookinfo.cover_bb and bookinfo.has_cover
                                and not bookinfo.ignore_cover then
                                local _, _, sf = BookInfoManager.getCachedCoverSize(
                                    bookinfo.cover_w, bookinfo.cover_h,
                                    cover_max_w, cover_max_h)
                                dialog_cover_widget = makeSideBySide(
                                    bookinfo.cover_bb,
                                    bookinfo.cover_w, bookinfo.cover_h,
                                    sf,
                                    title_str or BD.filename(file:match("([^/]+)$")),
                                    authors_str,
                                    tags_str_local,
                                    function() showCoverFullscreen(file) end)
                            end
                        end
                    end
                    -- dialog_title is the plain text fallback used by the text-only header
                    -- and the status sub-dialog: keep it as "title\nauthors"
                    local text_str
                    if title_str then
                        text_str = title_str
                        if authors_str then text_str = text_str .. "\n" .. authors_str end
                    end
                    dialog_title = text_str or BD.filename(file:match("([^/]+)$"))
                else
                    -- folder
                    local name = (file:match("([^/]+)/?$") or file):gsub("/$", "")
                    local folder_name_str = BD.directory(name)
                    local count = item.mandatory and tostring(item.mandatory):match("^%s*(%d+)")
                    local folder_count_str
                    if count then
                        local n = tonumber(count) or 0
                        folder_count_str = n == 1 and _("1 book") or (n .. " " .. _("books"))
                    end
                    -- Plain-text fallback for text-only header (no cover)
                    dialog_title = folder_count_str
                        and (folder_name_str .. "\n" .. folder_count_str)
                        or folder_name_str
                    local lfs = require("libs/libkoreader-lfs")
                    -- 1. Prefer cover.jpg / cover.jpeg / cover.png inside the folder.
                    local cover_candidates = { "cover.jpg", "cover.jpeg", "cover.png",
                                               "Cover.jpg", "Cover.jpeg", "Cover.png" }
                    local folder_cover_path
                    for _, cn in ipairs(cover_candidates) do
                        local cp = file .. "/" .. cn
                        if lfs.attributes(cp, "mode") == "file" then
                            folder_cover_path = cp
                            break
                        end
                    end
                    if folder_cover_path then
                        local ok_ri, RenderImage = pcall(require, "ui/renderimage")
                        if ok_ri then
                            local cover_bb = RenderImage:renderImageFile(
                                folder_cover_path, false, cover_max_w, cover_max_h)
                            if cover_bb then
                                local src_w = cover_bb:getWidth()
                                local src_h = cover_bb:getHeight()
                                dialog_cover_widget = makeSideBySide(
                                    cover_bb, src_w, src_h, 1.0,
                                    folder_name_str, folder_count_str, nil, nil)
                            end
                        end
                    end
                    -- 2. Fall back: gallery of up to 4 books' embedded covers (2×2 mosaic).
                    if not dialog_cover_widget then
                        local ok, BookInfoManager = pcall(require, "bookinfomanager")
                        if ok then
                            local DocRegistry = require("document/documentregistry")
                            local dir_files   = {}
                            local ok_dir, iter, dir_obj = pcall(lfs.dir, file)
                            if ok_dir then
                                for fname in iter, dir_obj do
                                    if fname ~= "." and fname ~= ".." and not fname:match("^%.") then
                                        local fpath = file .. "/" .. fname
                                        if lfs.attributes(fpath, "mode") == "file"
                                            and DocRegistry:hasProvider(fpath) then
                                            table.insert(dir_files, fpath)
                                        end
                                    end
                                end
                                if #dir_files > 0 then
                                    table.sort(dir_files)
                                    -- Collect up to 4 covers.
                                    local covers = {}
                                    for _, fpath in ipairs(dir_files) do
                                        local bi = BookInfoManager:getBookInfo(fpath, true)
                                        if bi and bi.has_cover and bi.cover_bb
                                                and not bi.ignore_cover then
                                            table.insert(covers, { data = bi.cover_bb:copy() })
                                            if #covers >= 4 then break end
                                        end
                                    end
                                    if #covers > 0 then
                                        local Blitbuffer2      = require("ffi/blitbuffer")
                                        local CenterContainer2 = require("ui/widget/container/centercontainer")
                                        local FrameContainer2  = require("ui/widget/container/framecontainer")
                                        local Font2            = require("ui/font")
                                        local Geom2            = require("ui/geometry")
                                        local HorizontalGroup2 = require("ui/widget/horizontalgroup")
                                        local HorizontalSpan2  = require("ui/widget/horizontalspan")
                                        local ImageWidget2     = require("ui/widget/imagewidget")
                                        local LeftContainer2   = require("ui/widget/container/leftcontainer")
                                        local LineWidget2      = require("ui/widget/linewidget")
                                        local TextWidget2      = require("ui/widget/textwidget")
                                        local VerticalGroup2   = require("ui/widget/verticalgroup")
                                        local VerticalSpan2    = require("ui/widget/verticalspan")
                                        -- 2×2 grid geometry (1 px separator lines).
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
                                                cells[i] = CenterContainer2:new{
                                                    dimen = Geom2:new{ w = cd.w, h = cd.h },
                                                    ImageWidget2:new{
                                                        image            = c.data,
                                                        image_disposable = true,
                                                        width            = cd.w,
                                                        height           = cd.h,
                                                    },
                                                }
                                            else
                                                cells[i] = CenterContainer2:new{
                                                    dimen = Geom2:new{ w = cd.w, h = cd.h },
                                                    VerticalSpan2:new{ width = 1 },
                                                }
                                            end
                                        end
                                        local framed_gallery = FrameContainer2:new{
                                            padding    = 0,
                                            bordersize = border,
                                            width      = cover_max_w + 2 * border,
                                            height     = cover_max_h + 2 * border,
                                            background = Blitbuffer2.COLOR_LIGHT_GRAY,
                                            CenterContainer2:new{
                                                dimen = Geom2:new{ w = cover_max_w, h = cover_max_h },
                                                VerticalGroup2:new{
                                                    HorizontalGroup2:new{
                                                        cells[1],
                                                        LineWidget2:new{
                                                            background = Blitbuffer2.COLOR_WHITE,
                                                            dimen = Geom2:new{ w = sep, h = half_h },
                                                        },
                                                        cells[2],
                                                    },
                                                    LineWidget2:new{
                                                        background = Blitbuffer2.COLOR_WHITE,
                                                        dimen = Geom2:new{ w = cover_max_w, h = sep },
                                                    },
                                                    HorizontalGroup2:new{
                                                        cells[3],
                                                        LineWidget2:new{
                                                            background = Blitbuffer2.COLOR_WHITE,
                                                            dimen = Geom2:new{ w = sep, h = half_h2 },
                                                        },
                                                        cells[4],
                                                    },
                                                },
                                            },
                                        }
                                        _zen_apply_rounded_cover(framed_gallery, border)
                                        -- Side-by-side layout: gallery left, text right.
                                        local framed_h   = cover_max_h + 2 * border
                                        local text_col_w = math.max(
                                            avail_w - cover_max_w - 2 * border - gap,
                                            Screen:scaleBySize(60))
                                        local vstack = VerticalGroup2:new{ align = "left" }
                                        table.insert(vstack, TextWidget2:new{
                                            text      = folder_name_str,
                                            face      = Font2:getFace("cfont", 20),
                                            bold      = true,
                                            max_width = text_col_w,
                                        })
                                        if folder_count_str then
                                            table.insert(vstack, VerticalSpan2:new{
                                                width = Screen:scaleBySize(2),
                                            })
                                            table.insert(vstack, TextWidget2:new{
                                                text      = folder_count_str,
                                                face      = Font2:getFace("cfont", 17),
                                                max_width = text_col_w,
                                            })
                                        end
                                        dialog_cover_widget = LeftContainer2:new{
                                            dimen = Geom2:new{ w = avail_w, h = framed_h },
                                            HorizontalGroup2:new{
                                                align = "top",
                                                framed_gallery,
                                                HorizontalSpan2:new{ width = gap },
                                                vstack,
                                            },
                                        }
                                    end
                                end
                            end
                        end
                    end
                end

                -- ── Placeholder cover (always shown when no real cover was found) ──────
                if not dialog_cover_widget then
                    local Blitbuffer2      = require("ffi/blitbuffer")
                    local CenterContainer2 = require("ui/widget/container/centercontainer")
                    local Font2            = require("ui/font")
                    local FrameContainer2  = require("ui/widget/container/framecontainer")
                    local Geom2            = require("ui/geometry")
                    local HorizontalGroup2 = require("ui/widget/horizontalgroup")
                    local HorizontalSpan2  = require("ui/widget/horizontalspan")
                    local LeftContainer2   = require("ui/widget/container/leftcontainer")
                    local TextWidget2      = require("ui/widget/textwidget")
                    local VerticalGroup2   = require("ui/widget/verticalgroup")
                    local VerticalSpan2    = require("ui/widget/verticalspan")

                    local ph_w    = cover_max_w
                    local ph_h    = cover_max_h
                    local framed_h = ph_h + 2 * border
                    local Widget2  = require("ui/widget/widget")
                    local ph_frame = FrameContainer2:new{
                        padding    = 0,
                        bordersize = border,
                        background = Blitbuffer2.COLOR_LIGHT_GRAY,
                        Widget2:new{ dimen = Geom2:new{ w = ph_w, h = ph_h } },
                    }
                    _zen_apply_rounded_cover(ph_frame, border)
                    local text_col_w = math.max(
                        avail_w - ph_w - 2 * border - gap,
                        Screen:scaleBySize(60))
                    local vstack = VerticalGroup2:new{ align = "left" }
                    -- Use the already-computed dialog_title as the text column content.
                    local title_line, sub_line = dialog_title, nil
                    if dialog_title then
                        local nl = dialog_title:find("\n")
                        if nl then
                            title_line = dialog_title:sub(1, nl - 1)
                            sub_line   = dialog_title:sub(nl + 1)
                        end
                    end
                    if title_line then
                        table.insert(vstack, TextWidget2:new{
                            text      = title_line,
                            face      = Font2:getFace("cfont", 20),
                            bold      = true,
                            max_width = text_col_w,
                        })
                    end
                    if sub_line then
                        table.insert(vstack, VerticalSpan2:new{ width = Screen:scaleBySize(2) })
                        table.insert(vstack, TextWidget2:new{
                            text      = sub_line,
                            face      = Font2:getFace("cfont", 17),
                            max_width = text_col_w,
                        })
                    end
                    dialog_cover_widget = LeftContainer2:new{
                        dimen = Geom2:new{ w = avail_w, h = framed_h },
                        HorizontalGroup2:new{
                            align = "top",
                            ph_frame,
                            HorizontalSpan2:new{ width = gap },
                            vstack,
                        },
                    }
                end
            end

            -- ── Edit submenu ──────────────────────────────────────────────────────────
            local function showEditSubmenu()
                close_dialog()
                local edit_dialog

                -- Home directory: only Paste is meaningful (can't cut/copy/rename/delete it).
                if is_home_dir then
                    edit_dialog = ButtonDialog:new{
                        buttons = {
                            {{
                                text     = "\u{F0EA}  " .. C_("File", "Paste"),
                                align    = "left",
                                enabled  = file_manager.clipboard and true or false,
                                callback = function()
                                    UIManager:close(edit_dialog)
                                    file_manager:pasteFileFromClipboard(file)
                                end,
                            }},
                        },
                    }
                    UIManager:show(edit_dialog)
                    return
                end

                local edit_buttons = {
                    {
                        {
                            text     = "\u{F14A}  " .. _("Select"),
                            align    = "left",
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:onToggleSelectMode()
                                if is_file then
                                    file_manager.selected_files[file] = true
                                    item.dim = true
                                    self_fc:updateItems(1, true)
                                end
                            end,
                        },
                    },
                    {
                        {
                            text     = "\u{F0C4}  " .. _("Cut"),
                            align    = "left",
                            enabled  = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:cutFile(file)
                            end,
                        },
                    },
                    {
                        {
                            text     = "\u{F0C5}  " .. C_("File", "Copy"),
                            align    = "left",
                            enabled  = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:copyFile(file)
                            end,
                        },
                    },
                    {
                        {
                            text     = "\u{F0EA}  " .. C_("File", "Paste"),
                            align    = "left",
                            enabled  = file_manager.clipboard and true or false,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:pasteFileFromClipboard(file)
                            end,
                        },
                    },
                }
                local allow_delete = zen_plugin
                    and type(zen_plugin.config) == "table"
                    and type(zen_plugin.config.context_menu) == "table"
                    and zen_plugin.config.context_menu.allow_delete == true
                if allow_delete then
                    table.insert(edit_buttons, {
                        {
                            text     = "\u{F1F8}  " .. _("Delete"),
                            align    = "left",
                            enabled  = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:showDeleteFileDialog(file, refresh)
                            end,
                        },
                    })
                end

                edit_dialog = ButtonDialog:new{
                    buttons = edit_buttons,
                }
                UIManager:show(edit_dialog)
            end

            -- ── Main dialog ───────────────────────────────────────────────────
            local buttons = {}

            -- Description first row (files only, when available)
            if is_file and is_not_parent_folder and book_description then
                table.insert(buttons, {
                    {
                        text     = "\u{F129}  " .. _("Description"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            local util       = require("util")
                            local TextViewer = require("ui/widget/textviewer")
                            UIManager:show(TextViewer:new{
                                title     = _("Description:"),
                                text      = util.htmlToPlainTextIfHtml(book_description),
                                text_type = "book_info",
                            })
                        end,
                    },
                })
            end

            -- Rename: folders only (not files, not the go-up row, not home dir)
            if not is_file and is_not_parent_folder and not is_home_dir then
                table.insert(buttons, {
                    {
                        text     = "\u{F031}  " .. _("Rename"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            file_manager:showRenameFileDialog(file, is_file)
                        end,
                    },
                })
            end

            -- New folder: only when invoked via the blank-space hold on the
            -- current directory — not from individual file/folder item menus.
            if item._is_current_dir then
                table.insert(buttons, {
                    {
                        text     = "\u{F07B}  " .. _("New folder"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            file_manager:createFolder()
                        end,
                    },
                })
            end

            if is_file and is_not_parent_folder then
                -- Move: open a folder picker then immediately execute the move
                table.insert(buttons, {
                    {
                        text     = "\u{F047}  " .. _("Move"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            local ffiUtil        = require("ffi/util")
                            local DocSettings    = require("docsettings")
                            local ReadHistory    = require("readhistory")
                            local ReadCollection = require("readcollection")
                            local lfs            = require("libs/libkoreader-lfs")
                            local src            = ffiUtil.realpath(file)
                            if not src then return end
                            local home_dir = (G_reader_settings and G_reader_settings:readSetting("home_dir"))
                                or file_chooser.path
                            if not home_dir then return end
                            local src_dir = ffiUtil.realpath(ffiUtil.dirname(src))
                            local chooser = MoveChooser:new{
                                select_directory = true,
                                select_file      = false,
                                show_files       = false,
                                title            = _("Move to…"),
                                path             = home_dir,
                                src_dir          = src_dir,
                                onConfirm        = function(dest_dir_real)
                                    local name      = ffiUtil.basename(src)
                                    local dest_file = ffiUtil.joinPath(dest_dir_real, name)
                                    if lfs.attributes(dest_file) then
                                        local InfoMessage = require("ui/widget/infomessage")
                                        UIManager:show(InfoMessage:new{
                                            text = _("An item with that name already exists."),
                                            icon = "notice-warning",
                                        })
                                        return
                                    end
                                    if file_manager:moveFile(src, dest_dir_real) then
                                        if is_file then
                                            DocSettings.updateLocation(src, dest_file)
                                            ReadHistory:updateItem(src, dest_file)
                                            ReadCollection:updateItem(src, dest_file)
                                            -- Migrate cover/metadata DB entry to the new path so
                                            -- folder covers and list metadata update immediately
                                            -- without requiring full re-extraction.
                                            local ok_bim2, bim2 = pcall(require, "bookinfomanager")
                                            if ok_bim2 and bim2
                                                    and type(bim2.onFileManagerFileRenamed) == "function" then
                                                pcall(bim2.onFileManagerFileRenamed, bim2, src, dest_file)
                                            end
                                        else
                                            ReadHistory:updateItemsByPath(src, dest_file)
                                            ReadCollection:updateItemsByPath(src, dest_file)
                                        end
                                        -- If the current directory is now empty and we're
                                        -- in a subfolder, navigate home to avoid a blank screen.
                                        local real_cur  = ffiUtil.realpath(file_chooser.path)
                                        local real_home = ffiUtil.realpath(home_dir)
                                        local at_home   = real_cur == real_home
                                        local n = 0
                                        if not at_home then
                                            local ok3, iter3, dir3 = pcall(lfs.dir, file_chooser.path)
                                            if ok3 then
                                                for f3 in iter3, dir3 do
                                                    if f3 ~= "." and f3 ~= ".." then n = n + 1 end
                                                end
                                            end
                                        end
                                        if not at_home and n == 0 then
                                            UIManager:nextTick(function()
                                                file_chooser:changeToPath(home_dir)
                                            end)
                                        else
                                            refresh()
                                        end
                                    else
                                        local InfoMessage = require("ui/widget/infomessage")
                                        UIManager:show(InfoMessage:new{
                                            text = _("Move failed."),
                                            icon = "notice-warning",
                                        })
                                    end
                                end,
                            }
                            UIManager:show(chooser)
                        end,
                    },
                })
            end

            if is_file then
                local ReadCollection = require("readcollection")
                local default_coll   = ReadCollection.default_collection_name
                local is_fav         = ReadCollection:isFileInCollection(file, default_coll)

                table.insert(buttons, {
                    {
                        text = is_fav and ("\u{F006}  " .. _("Remove from favorites")) or ("\u{F005}  " .. _("Add to favorites")),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            if is_fav then
                                ReadCollection:removeItem(file, default_coll)
                            else
                                ReadCollection:addItem(file, default_coll)
                            end
                            ReadCollection:write({ [default_coll] = true })
                        end,
                    },
                })
            end

            if is_file and is_not_parent_folder then
                -- Read status submenu
                table.insert(buttons, {
                    {
                        text     = "\u{F02D}  " .. _("Read status  ▶"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            local filemanagerutil = require("apps/filemanager/filemanagerutil")
                            local BookList        = require("ui/widget/booklist")
                            local DocSettings     = require("docsettings")
                            local doc_settings    = DocSettings:open(file)
                            local summary         = doc_settings:readSetting("summary") or {}
                            local current_status  = summary.status
                            local is_unread       = not current_status or current_status == ""
                            local status_dialog

                            local function setStatus(to_status)
                                if to_status == nil then
                                    summary.status = nil
                                    doc_settings:delSetting("percent_finished")
                                    doc_settings:delSetting("last_page")
                                    doc_settings:delSetting("last_xpointer")
                                    BookList.setBookInfoCacheProperty(file, "percent_finished", nil)
                                else
                                    summary.status = to_status
                                end
                                filemanagerutil.saveSummary(doc_settings, summary)
                                BookList.setBookInfoCacheProperty(file, "status", to_status)
                                UIManager:close(status_dialog)
                                refresh()
                            end

                            local function statusBtn(icon, label, to_status)
                                local is_cur = (to_status == nil and is_unread)
                                    or (to_status ~= nil and current_status == to_status)
                                return {{
                                    text     = icon .. "  " .. label .. (is_cur and "  \u{2713}" or ""),
                                    align    = "left",
                                    enabled  = not is_cur,
                                    callback = function() setStatus(to_status) end,
                                }}
                            end

                            status_dialog = ButtonDialog:new{
                                title       = _("Read status"),
                                title_align = "center",
                                buttons     = {
                                    statusBtn("\u{F02D}", _("Unread"),   nil),
                                    statusBtn("\u{F02E}", _("Reading"),  "reading"),
                                    statusBtn("\u{F04C}", _("On hold"),  "abandoned"),
                                    statusBtn("\u{F00C}", _("Finished"), "complete"),
                                },
                            }
                            UIManager:show(status_dialog)
                        end,
                    },
                })
            end

            -- ── Sort (folders only) ───────────────────────────────────────────────────
            if not is_file and is_not_parent_folder then
                local SORT_OPTIONS = {
                    { key = "title",    text = "\u{F031}  " .. _("Title")         },
                    { key = "authors",  text = "\u{F007}  " .. _("Authors")       },
                    { key = "series",   text = "\u{F0CB}  " .. _("Series")        },
                    { key = "access",   text = "\u{F073}  " .. _("Recently read") },
                    { key = "keywords", text = "\u{F02C}  " .. _("Keywords")      },
                }

                if is_home_dir then
                    -- Home dir: controls the KOReader global collate (persists across sessions).
                    local g_sort = rawget(_G, "G_reader_settings")
                    if g_sort then
                        table.insert(buttons, {
                            {
                                text     = "\u{F0DC}  " .. _("Sort library  ▶"),
                                align    = "left",
                                callback = function()
                                    close_dialog()
                                    local sort_dialog
                                    local sort_buttons = {}
                                    local cur = g_sort:readSetting("collate", "strcoll")
                                    -- "strcoll" is KOReader's default alpha sort; map to "title"
                                    -- so the Title option shows as active by default.
                                    if cur == "strcoll" then cur = "title" end
                                    for _, opt in ipairs(SORT_OPTIONS) do
                                        local is_active = cur == opt.key
                                        table.insert(sort_buttons, {{
                                            text     = opt.text .. (is_active and "  \u{2713}" or ""),
                                            align    = "left",
                                            enabled  = not is_active,
                                            callback = function()
                                                -- "title" collate is valid; "strcoll" is the
                                                -- KOReader default alias — save whichever the
                                                -- FileChooser collates table exposes.
                                                g_sort:saveSetting("collate", opt.key)
                                                UIManager:close(sort_dialog)
                                                self_fc:refreshPath()
                                            end,
                                        }})
                                    end
                                    sort_dialog = ButtonDialog:new{
                                        title       = _("Sort library by"),
                                        title_align = "center",
                                        buttons     = sort_buttons,
                                    }
                                    UIManager:show(sort_dialog)
                                end,
                            },
                        })
                    end
                else
                    -- Sub-folder: per-folder zen sort override.
                    local fsd_api = rawget(_G, "__ZEN_FOLDER_SORT")
                    if fsd_api then
                        local ffiUtil_fsd = require("ffi/util")
                        local real_folder = ffiUtil_fsd.realpath(file) or file

                        table.insert(buttons, {
                            {
                                text     = "\u{F0DC}  " .. _("Sort folder  ▶"),
                                align    = "left",
                                callback = function()
                                    close_dialog()
                                    local sort_dialog
                                    local sort_buttons = {}
                                    local current_override = fsd_api.get(real_folder)
                                    for _, opt in ipairs(SORT_OPTIONS) do
                                        local is_active = current_override == opt.key
                                        table.insert(sort_buttons, {{
                                            text     = opt.text .. (is_active and "  \u{2713}" or ""),
                                            align    = "left",
                                            enabled  = not is_active,
                                            callback = function()
                                                fsd_api.set(real_folder, opt.key)
                                                UIManager:close(sort_dialog)
                                            end,
                                        }})
                                    end
                                    -- "Clear" row — only shown when an override is active
                                    if current_override then
                                        table.insert(sort_buttons, {{
                                            text     = "\u{F0E2}  " .. _("Clear"),
                                            align    = "left",
                                            callback = function()
                                                fsd_api.clear(real_folder)
                                                UIManager:close(sort_dialog)
                                            end,
                                        }})
                                    end
                                    sort_dialog = ButtonDialog:new{
                                        title       = _("Sort folder by"),
                                        title_align = "center",
                                        buttons     = sort_buttons,
                                    }
                                    UIManager:show(sort_dialog)
                                end,
                            },
                        })
                    end
                end
            end

            -- ── Display mode (current dir only) ──────────────────────────────────────
            if item._is_current_dir then
                local function showViewSubmenu()
                    close_dialog()
                    local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
                    local fm          = ok_fm and FM and FM.instance
                    local ok_bim, bim = pcall(require, "bookinfomanager")
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

                table.insert(buttons, {
                    {
                        text     = "\u{F06E}  " .. _("Display  ▶"),
                        align    = "left",
                        callback = showViewSubmenu,
                    },
                })
            end

            table.insert(buttons, {
                {
                    text     = "\u{F040}  " .. _("Edit  ▶"),
                    align    = "left",
                    callback = showEditSubmenu,
                },
            })

            -- NOTE: using an explicit local avoids the Lua `A and nil or B` gotcha
            -- where `nil` is falsy so the expression always returns B.
            local dlg_title = dialog_cover_widget and "" or dialog_title
            self_fc.file_dialog = ButtonDialog:new{
                title          = dlg_title ~= "" and dlg_title or nil,
                title_align    = "center",
                buttons        = buttons,
                _added_widgets = dialog_cover_widget and { dialog_cover_widget } or nil,
            }
            UIManager:show(self_fc.file_dialog)
            return true
        end

        -- ── Blank-space hold → current-folder context menu ────────────────────
        -- KOReader dispatches "Gesture" events to child widgets FIRST
        -- (WidgetContainer:handleEvent propagates to children before calling
        -- the widget's own handler).  MenuItem items handle holds that land on
        -- an actual item and return true, consuming the event.  Only when the
        -- hold is on blank space does propagation fall through to file_chooser's
        -- own onGesture, where the ges_event below fires.
        if Device:isTouchDevice() then
            local GestureRange_bh = require("ui/gesturerange")
            local Geom_bh         = require("ui/geometry")
            if not file_chooser.ges_events then
                file_chooser.ges_events = {}
            end
            file_chooser.ges_events.ZenBlankHold = {
                GestureRange_bh:new{
                    ges   = "hold",
                    range = Geom_bh:new{
                        x = 0, y = 0,
                        w = Device.screen:getWidth(),
                        h = Device.screen:getHeight(),
                    },
                },
            }
            function file_chooser:onZenBlankHold(arg, ges)
                -- Mirror showFileDialog's home-dir boundary guard.
                local g_settings_bh = rawget(_G, "G_reader_settings")
                local home_dir_bh   = g_settings_bh and g_settings_bh:readSetting("home_dir")
                local cur_path_bh   = self.path or ""
                if home_dir_bh then
                    local norm_home = home_dir_bh:gsub("/$", "")
                    local norm_cur  = cur_path_bh:gsub("/$", "")
                    local at_or_under = norm_cur == norm_home
                        or norm_cur:sub(1, #norm_home + 1) == norm_home .. "/"
                    if not at_or_under then return false end
                end
                -- Synthesize a folder item for the current directory so that
                -- the patched showFileDialog (rename, new folder, sort, edit)
                -- works without duplicating any logic.
                local ffiUtil_bh = require("ffi/util")
                local cur_real   = ffiUtil_bh.realpath(cur_path_bh) or cur_path_bh
                self:showFileDialog({
                    path            = cur_real,
                    is_file         = false,
                    is_go_up        = false,
                    text            = ffiUtil_bh.basename(cur_real),
                    bidi_wrap_func  = BD.directory,
                    _is_current_dir = true,
                })
                return true
            end
        end
    end
end

return apply_context_menu

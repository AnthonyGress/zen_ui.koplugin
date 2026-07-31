-- common/cover_utils.lua
-- Shared cover handling for filebrowser patches

local Blitbuffer = require("ffi/blitbuffer")
local library_font = require("modules/filebrowser/patches/library_font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local RenderText = require("ui/rendertext")
local BD = require("ui/bidi")
local _ = require("gettext")
local RenderCache = require("common/cover_render_cache")
local plugin_root = require("common/plugin_root")

local CoverUtils = {}
do
    local ok, Device = pcall(require, "device")
    local screen = ok and Device and Device.screen
    local scaled = screen and type(screen.scaleBySize) == "function"
        and screen:scaleBySize(1)
    CoverUtils.BORDER_SIZE = scaled or 2
end
local ORNATE_FRAME_PATH = plugin_root and plugin_root .. "/images/ornate-cover-frame.svg" or nil
local ORNATE_FRAME_CACHE_KEY = (ORNATE_FRAME_PATH or "ornate-cover-frame") .. "\30background-v7"

-- Max list items per page that still render legible covers. Above this,
-- covers get too narrow for text. Enforced regardless of where the
-- setting was changed (zen UI, KOReader's coverbrowser, legacy saves).
CoverUtils.MAX_FILES_PER_PAGE = 12

-- Read files_per_page, clamp to MAX, and self-heal the persisted setting
-- if it was saved too high (e.g. by KOReader's own spinner). Returns the
-- clamped value, or nil if unset (let ListMenu compute its default).
function CoverUtils.getFilesPerPage()
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok then return nil end
    local v = BookInfoManager:getSetting("files_per_page")
    if not v then return nil end
    if v > CoverUtils.MAX_FILES_PER_PAGE then
        v = CoverUtils.MAX_FILES_PER_PAGE
        BookInfoManager:saveSetting("files_per_page", v)
        local ok_fc, FileChooser = pcall(require, "ui/widget/filechooser")
        if ok_fc and FileChooser then FileChooser.files_per_page = v end
        -- Also clamp the live file_chooser instance if one already exists,
        -- so an in-flight render uses the capped value (not its own stale field).
        local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
        local fm = ok_fm and FM and FM.instance
        if fm and fm.file_chooser then fm.file_chooser.files_per_page = v end
    end
    return v
end

-- ============================================================
-- Helper: get_upvalue
-- ============================================================

function CoverUtils.getUpvalue(fn, name)
    if type(fn) ~= "function" then return nil end
    for i = 1, 64 do
        local upname, value = debug.getupvalue(fn, i)
        if not upname then break end
        if upname == name then return value end
    end
end

-- ============================================================
-- Cover mode (gallery / stack / normal)
-- ============================================================

function CoverUtils.getMode()
    local p = rawget(_G, "__ZEN_UI_PLUGIN")
    local cfg = (type(p) == "table" and type(p.config) == "table" and p.config)
        or require("config/manager").get()
    local fbc = type(cfg) == "table" and cfg.browser_folder_cover or nil
    local mode = type(fbc) == "table" and fbc.cover_mode or "gallery"
    if mode == "gallery" then
        return "gallery", 4, true
    elseif mode == "stack" then
        return "stack", 4, true
    elseif mode == "none" then
        return "none", 0, false
    else
        return "normal", 1, false
    end
end

-- ============================================================
-- Cover ratio from settings (e.g., "2:3")
-- ============================================================

function CoverUtils.getRatio()
    local G = rawget(_G, "G_reader_settings")
    local ratio_str = G and G:readSetting("uniform_cover_ratio") or "2:3"
    local num, den = ratio_str:match("(%d+):(%d+)")
    return (tonumber(num) or 2) / (tonumber(den) or 3)
end

-- ============================================================
-- Calculate portrait dimensions from max_w and max_h
-- ============================================================

function CoverUtils.calcDims(max_w, max_h)
    local ratio = CoverUtils.getRatio()
    if max_h * ratio <= max_w then
        return math.floor(max_h * ratio), max_h
    else
        return max_w, math.floor(max_w / ratio)
    end
end

function CoverUtils.fitDims(max_w, max_h, source_w, source_h)
    source_w, source_h = tonumber(source_w), tonumber(source_h)
    if not source_w or source_w <= 0 or not source_h or source_h <= 0 then
        return CoverUtils.calcDims(max_w, max_h)
    end
    local scale = math.min(max_w / source_w, max_h / source_h)
    return math.max(1, math.floor(source_w * scale + 0.5)),
        math.max(1, math.floor(source_h * scale + 0.5))
end

function CoverUtils.getEmptyPlaceholderText(source)
    if source == "recently_read" then
        return _("Start reading a book to fill this space.")
    elseif source == "to_be_read" then
        return _("No TBR books found")
    elseif source == "custom_featured" or source == "custom_strip" then
        return _("No books found in the selected folder")
    end
    return _("No books found")
end

-- ============================================================
-- Generate placeholder cover from file path
-- ============================================================

local function ornate_background(width, height, paper)
    local cache_key = ORNATE_FRAME_CACHE_KEY
    local cached = RenderCache:get(cache_key, width, height)
    if cached then return cached end

    local background = Blitbuffer.new(width, height, Blitbuffer.TYPE_BBRGB32)
    background:paintRect(0, 0, width, height, paper)

    if ORNATE_FRAME_PATH and width >= 24 and height >= 36 then
        local ok_module, RenderImage = pcall(require, "ui/renderimage")
        local source_height = math.max(1, math.floor(width * 1.5 + 0.5))
        local ok_render, ornament, straight_alpha
        if ok_module then
            ok_render, ornament, straight_alpha = pcall(
                RenderImage.renderSVGImageFile, RenderImage,
                ORNATE_FRAME_PATH, width, source_height
            )
        end
        if ok_render and ornament then
            if source_height ~= height then
                local scaled = ornament:scale(width, height)
                ornament:free()
                ornament = scaled
            end
            if straight_alpha then
                background:alphablitFrom(ornament, 0, 0)
            else
                background:pmulalphablitFrom(ornament, 0, 0)
            end
            ornament:free()
        end
    end

    RenderCache:put(cache_key, width, height, background)
    return background
end

local function placeholder_cache_key(filepath, width, height, title, authors)
    local font_name = type(library_font.getFontName) == "function" and library_font.getFontName() or "cfont"
    local font_size = type(library_font.getBaseSize) == "function" and library_font.getBaseSize() or 18
    return table.concat({
        tostring(filepath), tostring(width), tostring(height), title, authors,
        tostring(font_name), tostring(font_size),
    }, "\30") .. "\30placeholder-v21"
end

local function paint_text_without_background(widget, bb, x, y, ink)
    local size = widget:getSize()
    local mask = widget._bb
    if mask and type(mask.invert) == "function" and type(bb.colorblitFrom) == "function" then
        mask:invert()
        bb:colorblitFrom(mask, x, y, 0, 0, size.w, size.h, ink)
    else
        widget:paintTo(bb, x, y)
    end
end

function CoverUtils.genCover(filepath, target_w, target_h, no_fallback, metadata)
    local width, height

    if target_w and target_h then
        width, height = CoverUtils.calcDims(target_w, target_h)
    elseif target_w then
        width, height = CoverUtils.calcDims(target_w, 9999)
    else
        width, height = CoverUtils.calcDims(9999, target_h or 300)
    end

    -- Get metadata
    local title = ""
    local authors = ""
    local bookinfo_found = false

    local bookinfo = metadata
    if metadata == nil then
        local ok, BookInfoManager = pcall(require, "bookinfomanager")
        if ok then
            bookinfo = BookInfoManager:getBookInfo(filepath, false)
        end
    end
    if type(bookinfo) == "table" and not bookinfo.ignore_meta then
        bookinfo_found = true
        title = bookinfo.title or ""
        authors = bookinfo.authors or ""
        if authors and authors:find("\n") then
            authors = authors:match("^([^\n]+)")
        end
    end

    -- Fallback to filename (suppressed when no_fallback=true)
    if title == "" and not no_fallback then
        local fname = filepath:match("([^/]+)$") or ""
        fname = fname:gsub("/$", "")
        fname = fname:gsub("%.[^%.]+$", "")
        title = fname
    end

    local title_only = type(metadata) == "table" and metadata.title_only == true
    if title_only then
        authors = ""
    elseif not no_fallback then
        if title == "" then title = _("Unknown") end
        if authors == "" then authors = _("Unknown Author") end
    elseif bookinfo_found and authors == "" then
        -- Metadata loaded but no author field: still label it.
        authors = _("Unknown Author")
    end

    local cache_key = placeholder_cache_key(filepath, width, height, title, authors)
    local cached = RenderCache:get(cache_key, width, height)
    if cached then return cached, width, height end

    local paper = Blitbuffer.COLOR_WHITE
    local ink = Blitbuffer.COLOR_BLACK
    local final_bb = ornate_background(width, height, paper)

    local divider_y = math.floor(height * 0.61)
    local title_top = math.floor(height * 0.22)
    local title_area_h = math.max(1, divider_y - title_top - math.floor(height * 0.08))
    local author_top = divider_y + math.floor(height * 0.08)
    local author_area_h = math.max(1, math.floor(height * 0.16))
    local max_text_width = width - math.max(16, math.floor(width * 0.20))

    if max_text_width < 1 or title_area_h < 1 or author_area_h < 1 then
        RenderCache:put(cache_key, width, height, final_bb)
        return final_bb, width, height
    end

    -- Title widget (skip when no text available)
    local title_font_size = library_font.scaleValue(20)
    local min_title_font = library_font.scaleValue(10)
    local title_widget = nil

    while title ~= "" and title_font_size >= min_title_font do
        if title_widget then title_widget:free() end
        local face = library_font.getFace(title_font_size)
        title_widget = TextBoxWidget:new{
            text = title,
            face = face,
            width = max_text_width,
            alignment = "center",
            bold = true,
            fgcolor = Blitbuffer.COLOR_BLACK,
            bgcolor = Blitbuffer.COLOR_WHITE,
        }
        if title_widget:getSize().h <= title_area_h then break end
        title_font_size = title_font_size - 1
    end

    if title_widget and title_widget:getSize().h > title_area_h then
        local face = library_font.getFace(min_title_font)
        -- Ellipsis fallback re-runs makeLine with (width - ellipsis_width);
        -- skip it when too narrow or makeLine gets non-positive width.
        if max_text_width > RenderText:getEllipsisWidth(face) then
            title_widget:free()
            title_widget = TextBoxWidget:new{
                text = title,
                face = face,
                width = max_text_width,
                alignment = "center",
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
                bgcolor = Blitbuffer.COLOR_WHITE,
                height = title_area_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            }
        end
    end
    if title_widget then title_widget.handleEvent = function() return false end end

    -- Author widget (skip when no text available)
    local authors_font_size = library_font.scaleValue(16)
    local min_authors_font = library_font.scaleValue(6)
    local authors_widget = nil

    while authors ~= "" and authors_font_size >= min_authors_font do
        if authors_widget then authors_widget:free() end
        local face = library_font.getFace(authors_font_size)
        authors_widget = TextBoxWidget:new{
            text = authors,
            face = face,
            width = max_text_width,
            alignment = "center",
            fgcolor = Blitbuffer.COLOR_BLACK,
            bgcolor = Blitbuffer.COLOR_WHITE,
        }
        if authors_widget:getSize().h <= author_area_h then break end
        authors_font_size = authors_font_size - 1
    end

    if authors_widget and authors_widget:getSize().h > author_area_h then
        local face = library_font.getFace(min_authors_font)
        if max_text_width > RenderText:getEllipsisWidth(face) then
            authors_widget:free()
            authors_widget = TextBoxWidget:new{
                text = authors,
                face = face,
                width = max_text_width,
                alignment = "center",
                fgcolor = Blitbuffer.COLOR_BLACK,
                bgcolor = Blitbuffer.COLOR_WHITE,
                height = author_area_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
            }
        end
    end
    if authors_widget then
        authors_widget.handleEvent = function() return false end
    end

    -- Paint
    if title_widget then
        local title_y = title_top + math.floor((title_area_h - title_widget:getSize().h) / 2)
        paint_text_without_background(
            title_widget, final_bb,
            math.max(0, (width - title_widget:getSize().w) / 2), title_y, ink
        )
        title_widget:free()
    end

    if authors_widget then
        local authors_y = author_top + math.floor((author_area_h - authors_widget:getSize().h) / 2)
        paint_text_without_background(
            authors_widget, final_bb,
            math.max(0, (width - authors_widget:getSize().w) / 2), authors_y, ink
        )
        authors_widget:free()
    end

    RenderCache:put(cache_key, width, height, final_bb)
    return final_bb, width, height
end

-- ============================================================
-- Scale a real cover to target dimensions while preserving aspect ratio
-- ============================================================

function CoverUtils.scaleCover(cover_bb, src_w, src_h, target_w, target_h)
    local scaled_bb = cover_bb:scale(target_w, target_h)
    return scaled_bb, target_w, target_h
end
-- ============================================================
-- Explicit cover file detection and loading
-- ============================================================

function CoverUtils.loadExplicitCovers(path, mode)
    local util = require("util")
    local RenderImage = require("ui/renderimage")
    local EXTS = { ".jpg", ".jpeg", ".png", ".webp", ".gif" }

    local function findAny(dir, stem)
        for _i, ext in ipairs(EXTS) do
            local f = dir .. "/" .. stem .. ext
            if util.fileExists(f) then return f end
        end
    end

    local files = {}
    if mode == "gallery" or mode == "stack" then
        for i = 1, 4 do
            local f = findAny(path, "cover" .. i)
            if f then files[i] = f end
        end
    end
    -- Slot 1 fallback: cover.ext / .cover.ext (applies to all modes)
    if not files[1] then
        files[1] = findAny(path, "cover") or findAny(path, ".cover")
    end

    local any = false
    for i = 1, 4 do if files[i] then any = true; break end end
    if not any then return nil end

    local result = {}
    for i = 1, 4 do
        if files[i] then
            local ok, bb = pcall(function()
                return RenderImage:renderImageFile(files[i], false)
            end)
            if ok and bb then
                table.insert(result, { data = bb, w = bb:getWidth(), h = bb:getHeight() })
            end
        end
    end
    return #result > 0 and result or nil
end

-- ============================================================
-- Collect covers from directory
-- ============================================================

function CoverUtils.collect(dir_path, chooser, max_covers, need_copy, entries, cover_specs)
    local covers = {}

    if not entries then
        if not chooser then return covers end
        -- Reuse the browser pipeline so cover order matches the opened folder.
        if type(chooser.genItemTableFromPath) == "function" then
            local was_collecting = chooser._zen_folder_cover_collect
            chooser._zen_folder_cover_collect = true
            local ok, item_table = pcall(chooser.genItemTableFromPath, chooser, dir_path)
            chooser._zen_folder_cover_collect = was_collecting
            if ok and type(item_table) == "table" then
                entries = item_table
            end
        end

        if not entries then
            local lfs = require("libs/libkoreader-lfs")
            local G = rawget(_G, "G_reader_settings")
            local collate = G and G:readSetting("collate") or "strcoll"
            local ok, iter, dir_obj = pcall(lfs.dir, dir_path)
            if not ok then return covers end
            local doc_exts = { epub=1, pdf=1, djvu=1, cbz=1, cbr=1, mobi=1, azw3=1, fb2=1, txt=1, rtf=1, html=1, chm=1, zip=1, kpub=1, epub3=1 }
            local files = {}
            for f in iter, dir_obj do
                if f:sub(1,1) ~= "." then
                    local ext = (f:match("%.([^%.]+)$") or ""):lower()
                    if doc_exts[ext] then
                        table.insert(files, { name = f, path = dir_path .. "/" .. f })
                    end
                end
            end

            if collate == "access" or collate == "modification" or collate == "creation" then
                local time_field = collate
                if time_field == "creation" then time_field = "modification" end -- lfs doesn't have creation, fallback to mod
                for _i, item in ipairs(files) do
                    local fattr = lfs.attributes(item.path)
                    item.time = fattr and fattr[time_field] or 0
                end
                local rev = G:isTrue("reverse_collate")
                table.sort(files, function(a, b)
                    if a.time == b.time then return a.name:lower() < b.name:lower() end
                    if rev then return a.time < b.time else return a.time > b.time end
                end)
            else
                local rev = G:isTrue("reverse_collate")
                table.sort(files, function(a, b)
                    if rev then return a.name:lower() > b.name:lower() else return a.name:lower() < b.name:lower() end
                end)
            end

            entries = {}
            for i = 1, math.min(#files, max_covers * 2) do
                table.insert(entries, { is_file = true, file = files[i].path })
            end
        end
    end

    if not entries then return covers end

    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok then return covers end

    local _img_exts = { jpg=1, jpeg=1, png=1, webp=1, gif=1 }
    for _i, entry in ipairs(entries) do
        if (entry.is_file or entry.file) and #covers < max_covers then
            local fpath = entry.path or entry.file
            -- skip folder cover image files (cover.png, .cover.png, cover1.jpg, etc.)
            local _fname = (fpath:match("([^/]+)$") or ""):lower()
            local _fext  = _fname:match("%.([^%.]+)$")
            if not (_fext and _img_exts[_fext] and _fname:match("^%.?cover%d*%.")) then
                local bookinfo = BookInfoManager:getBookInfo(fpath, true)
                local invalid = bookinfo and type(cover_specs) == "table"
                    and type(BookInfoManager.isCachedCoverInvalid) == "function"
                    and BookInfoManager.isCachedCoverInvalid(bookinfo, cover_specs)
                if bookinfo and bookinfo.cover_bb and bookinfo.has_cover
                        and bookinfo.cover_fetched and not bookinfo.ignore_cover
                        and not invalid then
                    local cover_bb = bookinfo.cover_bb
                    if need_copy then
                        cover_bb = cover_bb:copy()
                        bookinfo.cover_bb:free()
                    end
                    table.insert(covers, { data = cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h })
                else
                    if bookinfo and bookinfo.cover_bb then bookinfo.cover_bb:free() end
                    local metadata = entry.doc_props or bookinfo
                    local cover_bb, pw, ph = CoverUtils.genCover(fpath, 200, 300, nil, metadata)
                    if cover_bb then
                        table.insert(covers, { data = cover_bb, w = pw, h = ph })
                    end
                end
            end
        end
    end

    return covers
end

-- ============================================================
-- DRAWING FUNCTIONS
-- ============================================================

-- FrameContainer bg for covers: gray on eink (dark mode inverts once -> dark gray);
-- white on LCD/non-eink where color inversion doesn't apply.
local function coverBg()
    local ok, Device = pcall(require, "device")
    if ok and not Device:hasEinkScreen() then
        return Blitbuffer.COLOR_WHITE
    end
    return Blitbuffer.COLOR_LIGHT_GRAY
end

local function previewCover(cover, max_w, max_h, uniform, ImageWidget)
    if type(cover) ~= "table" or cover.data == nil then cover = { data = cover } end
    local source_w, source_h = tonumber(cover.w), tonumber(cover.h)
    if not source_w or source_w <= 0 or not source_h or source_h <= 0 then
        local ok, width, height = pcall(function()
            return cover.data:getWidth(), cover.data:getHeight()
        end)
        if ok then source_w, source_h = width, height end
    end

    local width, height, scale_factor
    if uniform == false then
        width, height = CoverUtils.fitDims(max_w, max_h, source_w, source_h)
        scale_factor = 0
    else
        width, height = CoverUtils.calcDims(max_w, max_h)
        if source_w and source_w > 0 and source_h and source_h > 0 then
            scale_factor = math.max(width / source_w, height / source_h)
        end
    end
    return ImageWidget:new{
        image = cover.data,
        image_disposable = true,
        width = width,
        height = height,
        scale_factor = scale_factor,
    }, width, height
end

function CoverUtils.drawGallery(covers, portrait_w, portrait_h, border, bg_fn, uniform)
    local sep = 1
    local half_w = math.floor((portrait_w - sep) / 2)
    local half_w2 = portrait_w - sep - half_w
    local half_h = math.floor((portrait_h - sep) / 2)
    local half_h2 = portrait_h - sep - half_h
    local cell_dims = {
        { w = half_w,  h = half_h  },
        { w = half_w2, h = half_h  },
        { w = half_w,  h = half_h2 },
        { w = half_w2, h = half_h2 },
    }

    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local ImageWidget = require("ui/widget/imagewidget")
    local LineWidget = require("ui/widget/linewidget")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")

    local cells = {}
    for i = 1, 4 do
        local c = covers[i]
        local cd = cell_dims[i]
        if c then
            local image = previewCover(c, cd.w, cd.h, uniform, ImageWidget)
            cells[i] = CenterContainer:new{
                dimen = { w = cd.w, h = cd.h },
                image,
            }
        else
            cells[i] = CenterContainer:new{
                dimen = { w = cd.w, h = cd.h },
                VerticalSpan:new{ width = 1 },
            }
        end
    end

    local bg = bg_fn and bg_fn() or coverBg()
    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        width = dimen.w,
        height = dimen.h,
        background = bg,
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

function CoverUtils.drawStack(covers, portrait_w, portrait_h, border, bg_fn, uniform)
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local VerticalSpan = require("ui/widget/verticalspan")

    local stack_count = #covers
    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }
    if stack_count == 0 then
        return FrameContainer:new{
            padding = 0,
            bordersize = border,
            width = dimen.w,
            height = dimen.h,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = { w = portrait_w, h = portrait_h },
                VerticalSpan:new{ width = 1 },
            },
            overlap_align = "center",
        }
    end

    -- A single cover uses the same sizing policy as an opened book.
    if stack_count == 1 then
        local image, image_w, image_h = previewCover(
            covers[1], portrait_w, portrait_h, uniform, ImageWidget)
        local frame_w, frame_h = image_w + 2 * border, image_h + 2 * border
        return FrameContainer:new{
            padding = 0,
            bordersize = border,
            width = frame_w,
            height = frame_h,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = { w = image_w, h = image_h },
                image,
            },
            overlap_align = "center",
        }
    end

    -- Multi-book stack via OverlapGroup: each ImageWidget handles night mode at
    -- paint time, so the bg (FrameContainer white) and covers update immediately
    -- on night mode toggle without needing a page turn.
    local book_width  = math.floor(portrait_w * 0.72)
    local book_height = math.floor(book_width * (portrait_h / portrait_w))
    local base_x = math.floor((portrait_w - book_width) / 2)
    local base_y = math.floor((portrait_h - book_height) / 2)
    local step_x = math.floor(base_x / 2)
    local step_y = math.floor(base_y / 2)

    local n = math.min(stack_count, 4)
    local offsets
    if n == 2 then
        offsets = { { x = step_x, y = -step_y }, { x = -step_x, y = step_y } }
    elseif n == 3 then
        offsets = { { x = step_x, y = -step_y }, { x = 0, y = 0 }, { x = -step_x, y = step_y } }
    else
        -- 4 covers: outer pair at ±step, inner pair at ±step/3.
        local s3x = math.floor(step_x / 3)
        local s3y = math.floor(step_y / 3)
        offsets = {
            { x =  step_x, y = -step_y },
            { x =  s3x,    y = -s3y    },
            { x = -s3x,    y =  s3y    },
            { x = -step_x, y =  step_y },
        }
    end

    -- Insert children back-to-front: index 1 = bottom layer (painted first by OverlapGroup).
    local children = {}
    for i = n, 1, -1 do
        local cover = covers[i]
        local off = offsets[n - i + 1] or { x = 0, y = 0 }
        local image, image_w, image_h = previewCover(
            cover, book_width, book_height, uniform, ImageWidget)
        local frame_w, frame_h = image_w + 2 * border, image_h + 2 * border
        table.insert(children, FrameContainer:new{
            padding = 0,
            bordersize = border,
            width = frame_w,
            height = frame_h,
            background = Blitbuffer.COLOR_WHITE,
            overlap_offset = {
                math.floor((portrait_w - frame_w) / 2) + off.x,
                math.floor((portrait_h - frame_h) / 2) + off.y,
            },
            image,
        })
    end

    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        width = dimen.w,
        height = dimen.h,
        background = Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = { w = portrait_w, h = portrait_h },
            OverlapGroup:new{
                dimen = { w = portrait_w, h = portrait_h },
                allow_mirroring = false, -- don't flip manually-computed pixel offsets for RTL
                table.unpack(children),
            },
        },
        overlap_align = "center",
    }
end

function CoverUtils.drawNoImage(folder_name, portrait_w, portrait_h, border)
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")

    local bg = Blitbuffer.COLOR_WHITE
    local final_bb = CoverUtils.genCover(
        "zen-folder-placeholder:" .. folder_name,
        portrait_w,
        portrait_h,
        true,
        { title = folder_name, authors = "", title_only = true }
    )

    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        width = dimen.w,
        height = dimen.h,
        background = bg,
        CenterContainer:new{
            dimen = { w = portrait_w, h = portrait_h },
            ImageWidget:new{
                image = final_bb,
                image_disposable = true,
                width = portrait_w,
                height = portrait_h,
                original_in_nightmode = false,
            },
        },
        overlap_align = "center",
    }
end

function CoverUtils.drawSingle(cover, portrait_w, portrait_h, border, uniform)
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")

    local image, image_w, image_h = previewCover(
        cover, portrait_w, portrait_h, uniform, ImageWidget)
    local bg = Blitbuffer.COLOR_LIGHT_GRAY
    local dimen = { w = image_w + 2 * border, h = image_h + 2 * border }

    return FrameContainer:new{
        padding = 0,
        bordersize = border,
        width = dimen.w,
        height = dimen.h,
        background = bg,
        CenterContainer:new{
            dimen = { w = image_w, h = image_h },
            image,
        },
        overlap_align = "center",
    }
end

-- ============================================================
-- UNIFIED ENTRY POINT
-- ============================================================

function CoverUtils.makeCover(path, chooser, options)
    options = options or {}

    -- Handle single book file
    if not options.is_folder then
        local ok, BookInfoManager = pcall(require, "bookinfomanager")

        local target_w = options.width or 200
        local target_h = options.height or 300

        -- Always use calcDims to get correct dimensions
        local final_w, final_h = CoverUtils.calcDims(target_w, target_h)

        if ok then
            local bookinfo = BookInfoManager:getBookInfo(path, true)

                if bookinfo and bookinfo.cover_bb and bookinfo.has_cover
                        and bookinfo.cover_fetched and not bookinfo.ignore_cover then
                local scaled_bb = CoverUtils.scaleCover(
                    bookinfo.cover_bb, bookinfo.cover_w, bookinfo.cover_h,
                    final_w, final_h)
                local need_copy = options.need_copy == true
                local cover_bb = need_copy and scaled_bb:copy() or scaled_bb
                return cover_bb, final_w, final_h, "single", "real_cover"
            end
        end

        local cover_bb = CoverUtils.genCover(path, final_w, final_h)
        return cover_bb, final_w, final_h, "single", "placeholder"
    end

    -- Handle folder
    local mode, max_covers, need_copy = CoverUtils.getMode()
    if options.max_covers then max_covers = options.max_covers end

    -- "none" mode: skip cover collection, show name-only placeholder immediately
    if mode == "none" then
        local fname = options.folder_name or (path:match("([^/]+)/?$") or path):gsub("/$", "")
        fname = BD.directory(fname)
        local border = CoverUtils.BORDER_SIZE
        local portrait_w, portrait_h = CoverUtils.calcDims(options.max_w or 200, options.max_h or 300)
        return CoverUtils.drawNoImage(fname, portrait_w, portrait_h, border), mode, "empty_folder", nil
    end

    local covers = options.covers_data
    if not covers or #covers == 0 then
        -- Auto-detect explicit cover image files (cover.png, cover1.png, etc.)
        covers = CoverUtils.loadExplicitCovers(path, mode)
    end
    if not covers or #covers == 0 then
        covers = CoverUtils.collect(path, chooser, max_covers, need_copy)
    elseif #covers < max_covers then
        -- Fewer explicit covers than needed; fill remaining slots from books.
        local combined = {}
        for _i, c in ipairs(covers) do table.insert(combined, c) end
        local extra = CoverUtils.collect(path, chooser, max_covers - #combined, need_copy)
        for _i, c in ipairs(extra) do table.insert(combined, c) end
        covers = combined
    end

    local folder_name = options.folder_name or (path:match("([^/]+)/?$") or path):gsub("/$", "")
    folder_name = BD.directory(folder_name)

    local border = CoverUtils.BORDER_SIZE
    local max_w = options.max_w or 200
    local max_h = options.max_h or 300

    local portrait_w, portrait_h = CoverUtils.calcDims(max_w, max_h)

    local cover_widget

    if #covers > 0 then
        if mode == "gallery" then
            cover_widget = CoverUtils.drawGallery(
                covers, portrait_w, portrait_h, border, nil, options.uniform)
        elseif mode == "stack" then
            cover_widget = CoverUtils.drawStack(
                covers, portrait_w, portrait_h, border, nil, options.uniform)
        else
            cover_widget = CoverUtils.drawSingle(
                covers[1], portrait_w, portrait_h, border, options.uniform)
        end
        return cover_widget, mode, "folder_covers", covers
    end

    cover_widget = CoverUtils.drawNoImage(folder_name, portrait_w, portrait_h, border)
    return cover_widget, mode, "empty_folder", nil
end

return CoverUtils

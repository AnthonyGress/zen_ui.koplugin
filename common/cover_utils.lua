-- common/cover_utils.lua
-- Shared cover handling for filebrowser patches

local Blitbuffer = require("ffi/blitbuffer")
local library_font = require("common/library_font")
local TextBoxWidget = require("ui/widget/textboxwidget")
local BD = require("ui/bidi")
local _ = require("gettext")

local CoverUtils = {}

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
    local G = rawget(_G, "G_reader_settings")
    local cfg = G and G:readSetting("zen_ui_config")
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

-- ============================================================
-- Generate placeholder cover from file path
-- ============================================================

function CoverUtils.genCover(filepath, target_w, target_h, no_fallback)
    local width, height

    if target_w and target_h then
        width, height = CoverUtils.calcDims(target_w, target_h)
    elseif target_w then
        width, height = CoverUtils.calcDims(target_w, 9999)
    else
        width, height = CoverUtils.calcDims(9999, target_h or 300)
    end

    -- Get metadata
    local ok, BookInfoManager = pcall(require, "bookinfomanager")
    local title = ""
    local authors = ""
    local bookinfo_found = false

    if ok then
        local bookinfo = BookInfoManager:getBookInfo(filepath, true)
        if bookinfo and not bookinfo.ignore_meta then
            bookinfo_found = true
            title = bookinfo.title or ""
            authors = bookinfo.authors or ""
            if authors and authors:find("\n") then
                authors = authors:match("^([^\n]+)")
            end
        end
    end

    -- Fallback to filename (suppressed when no_fallback=true)
    if title == "" and not no_fallback then
        local fname = filepath:match("([^/]+)$") or ""
        fname = fname:gsub("/$", "")
        fname = fname:gsub("%.[^%.]+$", "")
        title = fname
    end

    if not no_fallback then
        if title == "" then title = _("Unknown") end
        if authors == "" then authors = _("Unknown Author") end
    elseif bookinfo_found and authors == "" then
        -- Metadata loaded but no author field: still label it.
        authors = _("Unknown Author")
    end

    -- Create canvas
    local final_bb = Blitbuffer.new(width, height, Blitbuffer.TYPE_BBRGB32)

    local split_y = math.floor(height * 2 / 3)
    local lighter_color = Blitbuffer.ColorRGB32(212, 220, 243, 255)
    local darker_color = Blitbuffer.ColorRGB32(130, 159, 227, 255)

    for y = 0, split_y - 1 do
        for x = 0, width - 1 do
            final_bb:setPixel(x, y, lighter_color)
        end
    end
    for y = split_y, height - 1 do
        for x = 0, width - 1 do
            final_bb:setPixel(x, y, darker_color)
        end
    end

    local title_area_h = split_y - 10
    local author_area_h = height - split_y - 10
    local max_text_width = width - 16

    local title_color = Blitbuffer.ColorRGB32(1, 68, 142, 255)
    local authors_color = Blitbuffer.ColorRGB32(8, 51, 93, 255)

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
            fgcolor = title_color,
            bgcolor = lighter_color,
        }
        if title_widget:getSize().h <= title_area_h then break end
        title_font_size = title_font_size - 1
    end

    if title_widget and title_widget:getSize().h > title_area_h then
        title_widget:free()
        local face = library_font.getFace(min_title_font)
        title_widget = TextBoxWidget:new{
            text = title,
            face = face,
            width = max_text_width,
            alignment = "center",
            bold = true,
            fgcolor = title_color,
            bgcolor = lighter_color,
            height = title_area_h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
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
            fgcolor = authors_color,
            bgcolor = darker_color,
        }
        if authors_widget:getSize().h <= author_area_h then break end
        authors_font_size = authors_font_size - 1
    end

    if authors_widget and authors_widget:getSize().h > author_area_h then
        authors_widget:free()
        local face = library_font.getFace(min_authors_font)
        authors_widget = TextBoxWidget:new{
            text = authors,
            face = face,
            width = max_text_width,
            alignment = "center",
            fgcolor = authors_color,
            bgcolor = darker_color,
            height = author_area_h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
    end
    if authors_widget then
        authors_widget.handleEvent = function() return false end
    end

    -- Paint
    if title_widget then
        local title_y = math.max(5, (split_y - title_widget:getSize().h) / 2)
        title_widget:paintTo(final_bb, math.max(0, (width - title_widget:getSize().w) / 2), title_y)
        title_widget:free()
    end

    if authors_widget then
        local authors_y = split_y + math.max(5, (author_area_h - authors_widget:getSize().h) / 2)
        authors_widget:paintTo(final_bb, math.max(0, (width - authors_widget:getSize().w) / 2), authors_y)
        authors_widget:free()
    end

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

function CoverUtils.collect(dir_path, chooser, max_covers, need_copy, entries)
    local covers = {}

    if not entries then
        if not chooser then return covers end
        local lfs = require("libs/libkoreader-lfs")
        local G = rawget(_G, "G_reader_settings")
        local collate = G and G:readSetting("collate") or "strcoll"
        local ok, iter, dir_obj = pcall(lfs.dir, dir_path)
        if ok then
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
        else
            -- lfs.dir failed (e.g. virtual path like a collection name);
            -- try the chooser's item table as a fallback.
            if chooser and type(chooser.genItemTableFromPath) == "function" then
                local t = chooser:genItemTableFromPath(dir_path)
                entries = type(t) == "table" and t or {}
            else
                entries = {}
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
                if bookinfo and bookinfo.cover_bb and bookinfo.has_cover
                        and bookinfo.cover_fetched and not bookinfo.ignore_cover then
                    local cover_bb = need_copy and bookinfo.cover_bb:copy() or bookinfo.cover_bb
                    table.insert(covers, { data = cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h })
                else
                    local cover_bb, pw, ph = CoverUtils.genCover(fpath, 200, 300)
                    table.insert(covers, { data = cover_bb, w = pw, h = ph })
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

function CoverUtils.drawGallery(covers, portrait_w, portrait_h, border, bg_fn)
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
            cells[i] = CenterContainer:new{
                dimen = { w = cd.w, h = cd.h },
                ImageWidget:new{
                    image = c.data,
                    width = cd.w,
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

function CoverUtils.drawStack(covers, portrait_w, portrait_h, border, bg_fn)
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local VerticalSpan = require("ui/widget/verticalspan")

    local stack_count = #covers
    local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }
    -- Gray border baked into each cover's blitbuffer; survives double-inversion so
    -- it stays gray in both day and night mode.
    local border_color = Blitbuffer.ColorRGB32(128, 128, 128, 255)

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

    -- Single book: full-size cover with gray border baked in. No baked fill needed
    -- since the cover stretches to fill the entire portrait area.
    if stack_count == 1 then
        local cover = covers[1]
        local scaled_bb, sw, sh = CoverUtils.scaleCover(cover.data, cover.w, cover.h, portrait_w, portrait_h)
        for x = 0, sw - 1 do
            scaled_bb:setPixel(x, 0, border_color)
            scaled_bb:setPixel(x, sh - 1, border_color)
        end
        for y = 0, sh - 1 do
            scaled_bb:setPixel(0, y, border_color)
            scaled_bb:setPixel(sw - 1, y, border_color)
        end
        return FrameContainer:new{
            padding = 0,
            bordersize = border,
            width = dimen.w,
            height = dimen.h,
            background = Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = { w = portrait_w, h = portrait_h },
                ImageWidget:new{
                    image = scaled_bb,
                    image_disposable = true,
                    width = sw,
                    height = sh,
                },
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
        local scaled_bb, sw, sh = CoverUtils.scaleCover(cover.data, cover.w, cover.h, book_width, book_height)
        for x = 0, sw - 1 do
            scaled_bb:setPixel(x, 0, border_color)
            scaled_bb:setPixel(x, sh - 1, border_color)
        end
        for y = 0, sh - 1 do
            scaled_bb:setPixel(0, y, border_color)
            scaled_bb:setPixel(sw - 1, y, border_color)
        end
        table.insert(children, ImageWidget:new{
            image = scaled_bb,
            image_disposable = true,
            width = sw,
            height = sh,
            overlap_offset = { base_x + off.x, base_y + off.y },
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

    -- Use constant colors; original_in_nightmode=false lets the screen's live
    -- inversion handle night mode so the cover updates immediately on toggle.
    local bg = Blitbuffer.COLOR_WHITE
    local fg = Blitbuffer.COLOR_BLACK
    local final_bb = Blitbuffer.new(portrait_w, portrait_h, Blitbuffer.TYPE_BBRGB32)
    final_bb:fill(bg)

    local font_size = library_font.scaleValue(20)
    local min_font = library_font.scaleValue(10)
    local text_widget = nil

    while font_size >= min_font do
        if text_widget then text_widget:free() end
        local face = library_font.getFace(font_size)
        text_widget = TextBoxWidget:new{
            text = folder_name,
            face = face,
            width = portrait_w - 16,
            alignment = "center",
            bold = true,
            fgcolor = fg,
            bgcolor = bg,
        }
        if text_widget:getSize().h <= portrait_h - 10 then
            break
        end
        font_size = font_size - 1
    end

    text_widget.handleEvent = function() return false end

    if text_widget:getSize().h > portrait_h - 10 then
        text_widget:free()
        local face = library_font.getFace(min_font)
        text_widget = TextBoxWidget:new{
            text = folder_name,
            face = face,
            width = portrait_w - 16,
            alignment = "center",
            bold = true,
            fgcolor = fg,
            bgcolor = bg,
            height = portrait_h - 10,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
        }
        text_widget.handleEvent = function() return false end
    end

    local y = (portrait_h - text_widget:getSize().h) / 2
    text_widget:paintTo(final_bb, (portrait_w - text_widget:getSize().w) / 2, y)
    text_widget:free()

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

function CoverUtils.drawSingle(cover_data, portrait_w, portrait_h, border)
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")

    local bg = Blitbuffer.COLOR_LIGHT_GRAY
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
                image = cover_data,
                width = portrait_w,
                height = portrait_h,
            },
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
        local border = 2
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

    local border = 2
    local max_w = options.max_w or 200
    local max_h = options.max_h or 300

    local portrait_w, portrait_h = CoverUtils.calcDims(max_w, max_h)

    local cover_widget

    local scaled_covers = {}
    for _i, c in ipairs(covers) do
        if c.w ~= portrait_w or c.h ~= portrait_h then
            local scaled_bb, sw, sh = CoverUtils.scaleCover(c.data, c.w, c.h, portrait_w, portrait_h)
            table.insert(scaled_covers, { data = scaled_bb, w = sw, h = sh })
        else
            table.insert(scaled_covers, { data = c.data, w = c.w, h = c.h })
        end
    end

    if #scaled_covers > 0 then
        if mode == "gallery" then
            cover_widget = CoverUtils.drawGallery(scaled_covers, portrait_w, portrait_h, border)
        elseif mode == "stack" then
            cover_widget = CoverUtils.drawStack(scaled_covers, portrait_w, portrait_h, border)
        else
            cover_widget = CoverUtils.drawSingle(scaled_covers[1].data, portrait_w, portrait_h, border)
        end
        return cover_widget, mode, "folder_covers", scaled_covers
    end

    cover_widget = CoverUtils.drawNoImage(folder_name, portrait_w, portrait_h, border)
    return cover_widget, mode, "empty_folder", nil
end

return CoverUtils

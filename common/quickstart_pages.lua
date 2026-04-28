-- Quickstart slideshow page definitions.
-- build_install_pages(ctx): called on first install with { plugin, config }.
-- UPDATE_PAGES: keyed by version string; add a table for each release that
--   has noteworthy changes. Omit a key to silently skip the screen for that
--   release.
-- Each page: { title = string, image = string|nil, description = string }
-- Interactive pages also have: choice_type, choices, on_apply.

local M = {}

local _ = require("gettext")
local T = require("ffi/util").template

local _plugin_root = (function()
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) ~= "@" then return "" end
    return src:sub(2):match("^(.*)/common/[^/]+%.lua$") or ""
end)()

local function img(rel)
    return _plugin_root .. "/images/quickstart/" .. rel
end

-- Load up to `n` book covers. ReadHistory first, then home-dir scan to fill.
-- Returns array of { bb, w, h, progress, status } -- caller owns the blitbuffer copies.
local function loadQuickstartCovers(n)
    local ok, BIM = pcall(require, "bookinfomanager")
    if not ok or type(BIM) ~= "table" or type(BIM.getBookInfo) ~= "function" then
        return {}
    end
    local lfs    = require("libs/libkoreader-lfs")
    local ok_ds, DocSettings = pcall(require, "docsettings")
    local covers = {}
    local seen   = {}

    local function try_add(path)
        if #covers >= n or not path or seen[path] then return end
        seen[path] = true
        if lfs.attributes(path, "mode") ~= "file" then return end
        local info = BIM:getBookInfo(path, true)
        if info and info.has_cover and info.cover_bb
                and info.cover_fetched and not info.ignore_cover then
            local progress, status = nil, nil
            if ok_ds then
                pcall(function()
                    local ds = DocSettings:open(path)
                    progress = ds:readSetting("percent_finished")
                    local summary = ds:readSetting("summary")
                    status = summary and summary.status
                end)
            end
            table.insert(covers, { bb = info.cover_bb:copy(), w = info.cover_w, h = info.cover_h, progress = progress, status = status, title = info.title, authors = info.authors, pages = info.pages })
        end
    end

    local rh_ok, ReadHistory = pcall(require, "readhistory")
    if rh_ok and ReadHistory and ReadHistory.hist then
        for _, entry in ipairs(ReadHistory.hist) do
            if #covers >= n then break end
            try_add(entry.file)
        end
    end

    if #covers < n then
        local home = G_reader_settings and G_reader_settings:readSetting("home_dir")
        if home and lfs.attributes(home, "mode") == "directory" then
            local file_list = {}
            for fname in lfs.dir(home) do
                if fname ~= "." and fname ~= ".." then
                    local fpath = home .. "/" .. fname
                    if lfs.attributes(fpath, "mode") == "file" then
                        table.insert(file_list, fpath)
                    end
                end
            end
            table.sort(file_list)
            for _, path in ipairs(file_list) do
                if #covers >= n then break end
                try_add(path)
            end
        end
    end

    return covers
end

-- Downward-pointing pentagon badge shape (matches browser_cover_badges).
local function paintPentagon(bb, bx, by, bw, bh, color)
    local rect_h = math.floor(bh * 30 / 42)
    local tip_h  = bh - rect_h
    bb:paintRect(bx, by, bw, rect_h, color)
    for row = 0, tip_h - 1 do
        local frac = (row + 1) / tip_h
        local rw   = math.max(2, math.floor(bw * (1 - frac)))
        local rx   = bx + math.floor((bw - rw) / 2)
        bb:paintRect(rx, by + rect_h + row, rw, 1, color)
    end
end

-- Checkmark drawn as two diagonal line segments.
local function paintCheck(bb, bx, by, bw, bh, color)
    local tk = math.max(2, math.floor(math.min(bw, bh) / 8))
    local function drawLine(x0, y0, x1, y1)
        local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        if steps == 0 then steps = 1 end
        for i = 0, steps do
            local t = i / steps
            bb:paintRect(math.floor(x0 + t*(x1-x0)), math.floor(y0 + t*(y1-y0)), tk, tk, color)
        end
    end
    drawLine(bx+math.floor(bw*0.08), by+math.floor(bh*0.62), bx+math.floor(bw*0.30), by+math.floor(bh*0.82))
    drawLine(bx+math.floor(bw*0.30), by+math.floor(bh*0.82), bx+math.floor(bw*0.82), by+math.floor(bh*0.18))
end

-- Paint a progress/status badge (pentagon, matches browser_cover_badges) at the top-right
-- of a cover cell in a canvas. NOT pre-inverted -- night mode inverts it once naturally.
local function paintCoverBadge(canvas, Blitbuffer, Font, TextWidget, Screen,
                               cell_x, cell_y, cell_w, progress, status)
    local do_check = (status == "complete") or (progress and progress >= 1.0)
    local do_pause = not do_check and (status == "abandoned")
    local do_pct   = not do_check and not do_pause and (progress and progress > 0)
    if not (do_check or do_pause or do_pct) then return end
    local badge_size = math.max(Screen:scaleBySize(16), math.floor(cell_w * 0.14))
    local bw = math.floor(badge_size * 1.2)
    local bh = math.floor(badge_size * 1.1)
    local bdg_x = cell_x + cell_w - bw - math.floor(bw * 0.25)
    local bdg_y = cell_y + 2
    paintPentagon(canvas, bdg_x - 2, bdg_y - 2, bw + 4, bh + 4, Blitbuffer.COLOR_BLACK)
    paintPentagon(canvas, bdg_x, bdg_y, bw, bh, Blitbuffer.COLOR_LIGHT_GRAY)
    local rect_h = math.floor(bh * 30 / 42)
    local pad_x  = math.floor(bw * 0.12)
    local pad_y  = math.floor(rect_h * 0.15)
    local icon_w = bw - 2 * pad_x
    local icon_h = rect_h - 2 * pad_y
    if do_check then
        local sq   = math.min(icon_w, icon_h)
        paintCheck(canvas,
            bdg_x + pad_x + math.floor((icon_w - sq) / 2),
            bdg_y + pad_y + math.floor((icon_h - sq) / 2),
            sq, sq, Blitbuffer.COLOR_BLACK)
    elseif Font and TextWidget then
        local font_sz = do_pause
            and math.max(7, math.floor(badge_size * 0.40))
            or  math.max(7, math.floor(badge_size * 0.24))
        local tw = TextWidget:new{
            text    = do_pause and "\u{F0150}" or (math.floor(100 * progress) .. "%"),
            face    = Font:getFace("cfont", font_sz),
            bold    = not do_pause,
            fgcolor = Blitbuffer.COLOR_BLACK,
            padding = 0,
        }
        local tw_sz = tw:getSize()
        tw:paintTo(canvas,
            bdg_x + math.floor((bw     - tw_sz.w) / 2),
            bdg_y + math.floor((rect_h - tw_sz.h) / 2))
        tw:free()
    end
end

-- Render the library icon (circle border + library icon) centered on a white canvas.
-- Mirrors buildZenButtonBB sizing so the Home Folder page looks consistent.
local function buildHomeIconBB(avail_w)
    local ok_bb,  Blitbuffer = pcall(require, "ffi/blitbuffer")
    local ok_iw,  IconWidget = pcall(require, "ui/widget/iconwidget")
    local ok_dev, Device     = pcall(require, "device")
    if not (ok_bb and ok_iw and ok_dev) then return nil end
    local ok_u, utils = pcall(require, "common/utils")
    local Screen   = Device.screen
    local BTN_SZ   = Screen:scaleBySize(160)
    local BORDER   = Screen:scaleBySize(3)
    local ICO_SZ   = math.floor(BTN_SZ * 0.52)
    local canvas_h = BTN_SZ + Screen:scaleBySize(40)
    local canvas   = Blitbuffer.new(avail_w, canvas_h, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    local r  = math.floor(BTN_SZ / 2)
    local cx = math.floor(avail_w / 2)
    local cy = math.floor(canvas_h / 2)
    for dy = -r, r do
        local hw = math.floor(math.sqrt(r*r - dy*dy) + 0.5)
        if hw > 0 then canvas:paintRect(cx - hw, cy + dy, hw*2, 1, Blitbuffer.COLOR_BLACK) end
    end
    local ir = r - BORDER
    for dy = -ir, ir do
        local hw = math.floor(math.sqrt(ir*ir - dy*dy) + 0.5)
        if hw > 0 then canvas:paintRect(cx - hw, cy + dy, hw*2, 1, Blitbuffer.COLOR_WHITE) end
    end
    local icon_path = ok_u and utils.resolveIcon(_plugin_root .. "/icons/", "library")
    pcall(function()
        local ico = IconWidget:new{
            file   = icon_path or nil,
            icon   = icon_path and nil or "library",
            width  = ICO_SZ,
            height = ICO_SZ,
        }
        local isz = ico:getSize()
        ico:paintTo(canvas, cx - math.floor(isz.w / 2), cy - math.floor(isz.h / 2))
        ico:free()
    end)
    return canvas
end

-- Render the zen-mode quicksettings button (circle border + quick_zen icon) centered
-- on a white canvas. Returns a Blitbuffer (caller owns) or nil on error.
local function buildZenButtonBB(avail_w)
    local ok_bb,  Blitbuffer = pcall(require, "ffi/blitbuffer")
    local ok_iw,  IconWidget = pcall(require, "ui/widget/iconwidget")
    local ok_dev, Device     = pcall(require, "device")
    if not (ok_bb and ok_iw and ok_dev) then return nil end
    local ok_u, utils = pcall(require, "common/utils")
    local Screen   = Device.screen
    local BTN_SZ   = Screen:scaleBySize(160)
    local BORDER   = Screen:scaleBySize(3)
    local ICO_SZ   = math.floor(BTN_SZ * 0.52)
    local canvas_h = BTN_SZ + Screen:scaleBySize(40)
    local canvas   = Blitbuffer.new(avail_w, canvas_h, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    local r  = math.floor(BTN_SZ / 2)
    local cx = math.floor(avail_w / 2)
    local cy = math.floor(canvas_h / 2)
    -- Circle border
    for dy = -r, r do
        local hw = math.floor(math.sqrt(r*r - dy*dy) + 0.5)
        if hw > 0 then canvas:paintRect(cx - hw, cy + dy, hw*2, 1, Blitbuffer.COLOR_BLACK) end
    end
    -- White interior
    local ir = r - BORDER
    for dy = -ir, ir do
        local hw = math.floor(math.sqrt(ir*ir - dy*dy) + 0.5)
        if hw > 0 then canvas:paintRect(cx - hw, cy + dy, hw*2, 1, Blitbuffer.COLOR_WHITE) end
    end
    local icon_path = ok_u and utils.resolveIcon(_plugin_root .. "/icons/", "quick_zen")
    pcall(function()
        local ico = IconWidget:new{
            file   = icon_path or nil,
            icon   = icon_path and nil or "quick_zen",
            width  = ICO_SZ,
            height = ICO_SZ,
        }
        local isz = ico:getSize()
        ico:paintTo(canvas, cx - math.floor(isz.w / 2), cy - math.floor(isz.h / 2))
        ico:free()
    end)
    return canvas
end

-- Compose a 1x3 horizontal strip of portrait covers.
-- Returns a Blitbuffer (caller owns) or nil on error.
local function buildMosaicBB(covers, avail_w)
    local ok_bb,  Blitbuffer  = pcall(require, "ffi/blitbuffer")
    local ok_iw,  ImageWidget = pcall(require, "ui/widget/imagewidget")
    local ok_dev, Device      = pcall(require, "device")
    if not (ok_bb and ok_iw and ok_dev) then return nil end
    local ok_font, Font       = pcall(require, "ui/font")
    local ok_tw,  TextWidget  = pcall(require, "ui/widget/textwidget")
    local Screen = Device.screen
    local night  = Screen.night_mode
    local PAD    = Screen:scaleBySize(8)
    local GAP    = Screen:scaleBySize(6)
    local cell_w = math.floor((avail_w - 2 * PAD - 2 * GAP) / 3)
    local cell_h = math.floor(cell_w * 3 / 2)
    local canvas = Blitbuffer.new(avail_w, cell_h + 2 * PAD, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    for i = 0, 2 do
        local cx = PAD + i * (cell_w + GAP)
        canvas:paintRect(cx, PAD, cell_w, cell_h, Blitbuffer.COLOR_GRAY_4)
        local c = covers[i + 1]
        if c then
            pcall(function()
                local iw = ImageWidget:new{
                    image                 = c.bb,
                    width                 = cell_w,
                    height                = cell_h,
                    scale_factor          = 0,
                    image_disposable      = false,
                    original_in_nightmode = false,
                }
                local isz = iw:getSize()
                iw:paintTo(canvas,
                    cx  + math.floor((cell_w - isz.w) / 2),
                    PAD + math.floor((cell_h - isz.h) / 2))
                iw:free()
            end)
            -- Pre-invert the cover cell; display's night-mode inversion restores original colors.
            if night then canvas:invertRect(cx, PAD, cell_w, cell_h) end
            -- Badge painted after inversion: display inverts it once, matching browser_cover_badges behavior.
            pcall(paintCoverBadge, canvas, Blitbuffer,
                ok_font and Font or nil, ok_tw and TextWidget or nil,
                Screen, cx, PAD, cell_w, c.progress, c.status)
        end
    end
    return canvas
end

-- Compose 2 list rows: cover thumbnail left + actual book details right.
-- Returns a Blitbuffer (caller owns) or nil on error.
local function buildListBB(covers, avail_w)
    local ok_bb,  Blitbuffer  = pcall(require, "ffi/blitbuffer")
    local ok_iw,  ImageWidget = pcall(require, "ui/widget/imagewidget")
    local ok_dev, Device      = pcall(require, "device")
    if not (ok_bb and ok_iw and ok_dev) then return nil end
    local ok_font, Font       = pcall(require, "ui/font")
    local ok_tw,  TextWidget  = pcall(require, "ui/widget/textwidget")
    local Screen    = Device.screen
    local night     = Screen.night_mode
    local PAD       = Screen:scaleBySize(8)
    local GAP       = Screen:scaleBySize(8)
    local INNER_GAP = Screen:scaleBySize(10)
    local thumb_w   = math.floor(avail_w * 0.28)
    local thumb_h   = math.floor(thumb_w * 3 / 2)
    local total_h   = 2 * thumb_h + GAP + 2 * PAD
    local canvas    = Blitbuffer.new(avail_w, total_h, Blitbuffer.TYPE_BB8)
    canvas:fill(Blitbuffer.COLOR_WHITE)
    local text_x = PAD + thumb_w + INNER_GAP
    local text_w = avail_w - text_x - PAD
    for i = 0, 1 do
        local ry = PAD + i * (thumb_h + GAP)
        canvas:paintRect(PAD, ry, thumb_w, thumb_h, Blitbuffer.COLOR_GRAY_4)
        local c = covers[i + 1]
        if c then
            pcall(function()
                local iw = ImageWidget:new{
                    image                 = c.bb,
                    width                 = thumb_w,
                    height                = thumb_h,
                    scale_factor          = 0,
                    image_disposable      = false,
                    original_in_nightmode = false,
                }
                local isz = iw:getSize()
                iw:paintTo(canvas,
                    PAD + math.floor((thumb_w - isz.w) / 2),
                    ry  + math.floor((thumb_h - isz.h) / 2))
                iw:free()
            end)
            if night then canvas:invertRect(PAD, ry, thumb_w, thumb_h) end
        end
        if ok_font and ok_tw then
            local ty = ry + Screen:scaleBySize(8)
            -- Title
            local title_str = (c and c.title and c.title ~= "") and c.title or "Unknown Title"
            local t_tw = TextWidget:new{
                text    = title_str,
                face    = Font:getFace("cfont", 17),
                bold    = true,
                width   = text_w,
                padding = 0,
            }
            t_tw:paintTo(canvas, text_x, ty)
            ty = ty + t_tw:getSize().h + Screen:scaleBySize(4)
            t_tw:free()
            -- Author
            local auth_str = (c and c.authors and c.authors ~= "") and c.authors or ""
            if auth_str ~= "" then
                local a_tw = TextWidget:new{
                    text    = auth_str,
                    face    = Font:getFace("cfont", 15),
                    width   = text_w,
                    padding = 0,
                }
                a_tw:paintTo(canvas, text_x, ty)
                ty = ty + a_tw:getSize().h + Screen:scaleBySize(4)
                a_tw:free()
            end
            -- Pages
            if c and c.pages and c.pages > 0 then
                local m_tw = TextWidget:new{
                    text    = c.pages .. " pages",
                    face    = Font:getFace("cfont", 14),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    width   = text_w,
                    padding = 0,
                }
                m_tw:paintTo(canvas, text_x, ty)
                m_tw:free()
            end
        else
            -- Fallback: gray placeholder bars
            canvas:paintRect(text_x, ry + math.floor(thumb_h * 0.25),
                math.floor(text_w * 0.55), Screen:scaleBySize(10), Blitbuffer.COLOR_LIGHT_GRAY)
            canvas:paintRect(text_x, ry + math.floor(thumb_h * 0.25) + Screen:scaleBySize(18),
                math.floor(text_w * 0.35), Screen:scaleBySize(8), Blitbuffer.COLOR_LIGHT_GRAY)
        end
        if i < 1 then
            canvas:paintRect(PAD, ry + thumb_h + math.floor(GAP / 2),
                avail_w - 2 * PAD, 1, Blitbuffer.COLOR_LIGHT_GRAY)
        end
    end
    return canvas
end

-- ---------------------------------------------------------------------------
-- ctx = { plugin = <ZenUI plugin>, config = <config table> }
-- ---------------------------------------------------------------------------

function M.build_install_pages(ctx)
    local config = ctx.config
    local plugin = ctx.plugin

    local function save_and_apply(feature)
        plugin:saveConfig()
        local ok, apply_mod = pcall(require, "modules/settings/zen_settings_apply")
        if ok and type(apply_mod.apply_feature_toggle) == "function" then
            apply_mod.apply_feature_toggle(plugin, feature, config.features[feature] == true)
        end
    end

    -- Load screensaver presets once
    local builtin_presets = {}
    pcall(function()
        local bp_mod = require("config/screensaver_presets")
        if type(bp_mod.get) == "function" then
            builtin_presets = bp_mod.get(_plugin_root .. "/icons/")
        end
    end)

    -- Load footer presets once
    local footer_presets
    pcall(function()
        footer_presets = require("modules/reader/patches/reader_footer_presets")
    end)

    -- -----------------------------------------------------------------------
    -- Setting appliers
    -- -----------------------------------------------------------------------

    local function apply_screensaver_preset(preset)
        if type(preset) ~= "table" then return end
        local simple_keys = {
            "screensaver_type",
            "screensaver_img_background",
            "screensaver_document_cover",
            "screensaver_stretch_limit_percentage",
        }
        for _, k in ipairs(simple_keys) do
            if preset[k] ~= nil then
                G_reader_settings:saveSetting(k, preset[k])
            end
        end
        -- "cover" uses the last book's cover; stale document_cover paths are irrelevant
        -- and confusing, so clear the setting when switching to this type.
        if preset.screensaver_type == "cover" then
            G_reader_settings:delSetting("screensaver_document_cover")
        end
        if preset.screensaver_show_message ~= nil then
            if preset.screensaver_show_message then
                G_reader_settings:makeTrue("screensaver_show_message")
            else
                G_reader_settings:makeFalse("screensaver_show_message")
            end
        end
        if preset.screensaver_stretch_images ~= nil then
            if preset.screensaver_stretch_images then
                G_reader_settings:makeTrue("screensaver_stretch_images")
            else
                G_reader_settings:makeFalse("screensaver_stretch_images")
            end
        end
    end

    local function apply_footer_preset(preset)
        if type(preset) ~= "table" then return end
        if preset.footer then
            -- Deep-copy so the shared preset table is never aliased into
            -- G_reader_settings; KOReader's footer module receives readSetting()
            -- and can write defaults back into the same object, which would
            -- silently corrupt the preset and revert font fields on next load.
            local footer
            local ok_u, util_mod = pcall(require, "util")
            if ok_u and type(util_mod.tableDeepCopy) == "function" then
                footer = util_mod.tableDeepCopy(preset.footer)
            else
                footer = {}
                for k, v in pairs(preset.footer) do footer[k] = v end
            end
            footer.text_font_face = "NotoSans-Bold.ttf"
            footer.text_font_bold = false
            G_reader_settings:saveSetting("footer", footer)
        end
        if preset.reader_footer_mode ~= nil then
            G_reader_settings:saveSetting("reader_footer_mode", preset.reader_footer_mode)
        end
        if preset.reader_footer_custom_text then
            G_reader_settings:saveSetting("reader_footer_custom_text", preset.reader_footer_custom_text)
        end
        if preset.reader_footer_custom_text_repetitions then
            G_reader_settings:saveSetting("reader_footer_custom_text_repetitions",
                preset.reader_footer_custom_text_repetitions)
        end
        if preset.zen then
            if type(config.reader_footer) ~= "table" then config.reader_footer = {} end
            if preset.zen.verbose_chapter_time ~= nil then
                config.reader_footer.verbose_chapter_time = preset.zen.verbose_chapter_time
            end
            plugin:saveConfig()
        end
    end

    local function apply_display_mode(mode)
        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok_fm and FileManager and FileManager.instance
        if fm and type(fm.onSetDisplayMode) == "function" then
            pcall(fm.onSetDisplayMode, fm, mode)
        else
            local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
            if ok_bim then
                pcall(BookInfoManager.saveSetting, BookInfoManager,
                    "filemanager_display_mode", mode)
            end
        end
    end

    -- -----------------------------------------------------------------------
    -- Choice defaults (read current config so defaults feel intentional)
    -- -----------------------------------------------------------------------

    local show_tabs = (type(config.navbar) == "table" and type(config.navbar.show_tabs) == "table")
        and config.navbar.show_tabs or {}

    local is_12h = true
    local raw_12h = G_reader_settings:readSetting("twelve_hour_clock")
    if raw_12h ~= nil then
        is_12h = raw_12h ~= false
    end

    -- -----------------------------------------------------------------------
    -- Page table
    -- -----------------------------------------------------------------------

    local pages = {
        -- 1. Welcome (static)
        {
            title       = _("Welcome to Zen UI"),
            icon        = "zen_ui",
            description = _("A minimal, clean, and simple interface for your e-reader.\n\nSwipe or tap Next to continue."),
        },

        -- 2. File Browser (static)
        {
            title       = _("File Browser"),
            image       = img("onboarding/library_covers.png"),
            description = _("Clean, minimal library with mosaic cover art and list views, reduced clutter, and a streamlined context menu."),
        },
           -- 5. Context Menu (static)

        {
            title       = _("Context Menu"),
            image       = img("onboarding/context_menu.png"),
            description = _("Tap and hold any book or folder in your library to reveal details."),
        },

        -- 3. Authors & Series (static)
        {
            title       = _("Authors & Series"),
            image       = img("onboarding/authors.png"),
            description = _("Browse your entire library organized by author or series.\nAccess these views anytime from the navigation bar."),
        },

        -- 4. Library View (INTERACTIVE — radio)
        {
            title       = _("Library View"),
            choice_type = "radio",
            choices     = {
                { id = "mosaic", text = _("Mosaic - large cover thumbnails"),     image = img("onboarding/library_covers.png"), checked = true  },
                { id = "list",   text = _("List - detailed titles and metadata"), image = img("onboarding/library_list.png"),   checked = false },
            },
            on_apply = function(sel)
                if     sel["mosaic"] then apply_display_mode("mosaic_image")
                elseif sel["list"]   then apply_display_mode("list_image_meta")
                end
            end,
        },

        -- 6. Navigation Bar (static)
        {
            title       = _("Navigation Bar"),
            image       = img("onboarding/navbar.png"),
            description = _("A simple tab-based bar at the bottom of your library.\nFully customizable to make it your own"),
        },

        -- 7. Navbar Tabs (INTERACTIVE — checkbox)
        {
            title          = _("Navbar Tabs"),
            description    = _("Choose which tabs appear in your navigation bar.\nYou can rearrange or adjust these anytime in Settings."),
            choice_type    = "checkbox",
            max_selections = 7,
            choices        = {
                { id = "continue",    text = _("Continue"),    checked = show_tabs["continue"]    == true },
                { id = "history",     text = _("History"),     checked = show_tabs["history"]     == true },
                { id = "favorites",   text = _("Favorites"),   checked = show_tabs["favorites"]   == true },
                { id = "collections", text = _("Collections"), checked = show_tabs["collections"] == true },
                { id = "authors",     text = _("Authors"),     checked = show_tabs["authors"]     == true },
                { id = "series",      text = _("Series"),      checked = show_tabs["series"]      == true },
                { id = "to_be_read",  text = _("To Be Read"),  checked = show_tabs["to_be_read"]  == true },
                { id = "search",      text = _("Search"),      checked = show_tabs["search"]      == true },
                { id = "stats",       text = _("Stats"),       checked = show_tabs["stats"]       == true },
            },
            on_apply = function(sel)
                if type(config.navbar) ~= "table" then config.navbar = {} end
                if type(config.navbar.show_tabs) ~= "table" then config.navbar.show_tabs = {} end
                local tabs = { "continue", "history", "favorites", "collections",
                               "authors", "series", "to_be_read", "search", "stats" }
                for _, id in ipairs(tabs) do
                    config.navbar.show_tabs[id] = sel[id] == true
                end
                save_and_apply("navbar")
            end,
        },

        -- 8. Quick Settings (static)
        {
            title       = _("Quick Settings"),
            image       = img("onboarding/quicksettings.png"),
            description = _("Swipe down to reach quick settings like brightness, Wi-Fi, night mode, zen mode and more."),
        },

        -- 9. Zen Mode (static)
        {
            title       = _("Zen Mode"),
            image       = img("onboarding/zen_mode.png"),
            description = _("Turn on Zen mode to strip KOReader down to its bare essentials.\n\nRemove visual clutter for a focused, distraction-free reading experience. Exit at anytime from Settings."),
        },

        -- 10. Status Bars (static)
        {
            title       = _("Status Bar"),
            image       = img("onboarding/status_bar.png"),
            description = _("Minimal status bar in the library view.\nCustomizable - show only what you need: time, battery, etc."),
        },

        -- 11. Sleep Screen (INTERACTIVE — radio)
        {
            title       = _("Sleep Screen"),
            description = _("What should your device show when it goes to sleep?"),
            choice_type = "radio",
            choices     = {
                { id = "keep",          text = _("Keep existing settings"),         checked = true  },
                { id = "cover_black",   text = _("Book cover - black background"), checked = false },
                { id = "zen_white",     text = _("Zen icon - white background"),   checked = false },
            },
            on_apply = function(sel)
                if sel["keep"] then return end
                local preset
                if     sel["cover_black"] then preset = builtin_presets[1]
                elseif sel["zen_white"]   then preset = builtin_presets[2]
                end
                if preset then
                    apply_screensaver_preset(preset)
                    if type(config.sleep_screen) ~= "table" then
                        config.sleep_screen = { presets = {}, active_preset = nil }
                    end
                    config.sleep_screen.active_preset = preset.name
                    plugin:saveConfig()
                end
            end,
        },

        -- 12. Time Format (INTERACTIVE — radio)
        {
            title       = _("Time Format"),
            description = _("Which time format do you prefer?"),
            choice_type = "radio",
            choices     = {
                { id = "12h", text = _("12-hour  (3:30 PM)"), checked = is_12h      },
                { id = "24h", text = _("24-hour  (15:30)"),   checked = not is_12h  },
            },
            on_apply = function(sel)
                if sel["12h"] then
                    G_reader_settings:makeTrue("twelve_hour_clock")
                elseif sel["24h"] then
                    G_reader_settings:makeFalse("twelve_hour_clock")
                end
                -- TimeFormatChanged is reader-only; file manager status bar needs a direct refresh.
                local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
                local fm = ok_fm and FileManager and FileManager.instance
                if fm and type(fm._updateStatusBar) == "function" then
                    fm:_updateStatusBar()
                end
            end,
        },

        -- 13. Reader (INTERACTIVE — radio)
        {
            title       = _("Reader"),
            image       = img("onboarding/reader.png"),
            description = _("An unobtrusive reader view with customizable top clock and bottom progress bar."),
            choice_type = "radio",
            choices     = {
                { id = "keep", text = _("Keep existing settings"), checked = true  },
                { id = "zen",  text = _("Zen UI defaults"), checked = false },
            },
            on_apply = function(sel)
                if sel["keep"] then return end
                G_reader_settings:saveSetting("copt_h_page_margins", {30, 30})
                G_reader_settings:saveSetting("copt_sync_t_b_page_margins", 1)
                G_reader_settings:saveSetting("copt_t_page_margin", 30)
                G_reader_settings:saveSetting("copt_b_page_margin", 30)
                G_reader_settings:saveSetting("copt_word_spacing", {100, 90})
                G_reader_settings:saveSetting("copt_line_spacing", 110)
                G_reader_settings:saveSetting("copt_font_gamma", 25)  -- gamma index for 1.45
                G_reader_settings:saveSetting("copt_font_size", 23)
                G_reader_settings:saveSetting("copt_embedded_css", 0)
                G_reader_settings:saveSetting("copt_embedded_fonts", 0)
                G_reader_settings:saveSetting("copt_nightmode_images", 1)
                G_reader_settings:saveSetting("alt_status_bar", false)
            end,
        },

        -- 15. Reader Progress (INTERACTIVE — radio)
        {
            title       = _("Reader Progress"),
            description = _("Choose a preset for your reading progress bar."),
            choice_type = "radio",
            choices     = {
                { id = "keep",     text = _("Keep existing settings"),                                                       checked = true  },
                { id = "kindle",   text = _("Chapter Time + %"),      image = img("onboarding/kindle_like.png"),        checked = false },
                { id = "pages",    text = _("Pages and %"),      image = img("onboarding/pages_percent.png"),      checked = false },
                { id = "full",     text = _("Pages + Chapter Time + %"), image = img("onboarding/pages_time_percent.png"), checked = false },
                { id = "centered", text = _("Centered Pages"),   image = img("onboarding/centered_pages.png"),     checked = false },
            },
            on_apply = function(sel)
                if sel["keep"] then return end
                if not footer_presets then return end
                local preset
                if     sel["kindle"]   then preset = footer_presets[1]
                elseif sel["pages"]    then preset = footer_presets[2]
                elseif sel["full"]     then preset = footer_presets[3]
                elseif sel["centered"] then preset = footer_presets[4]
                end
                if preset then apply_footer_preset(preset) end
            end,
        },

                -- 14. Page Browser (static)
        {
            title       = _("Page Browser"),
            image       = img("onboarding/page_browser.png"),
            description = _("Swipe up from the bottom while reading to open the Page Browser.\n\nSkim through pages or skip chapters, browse the table of contents, manage bookmarks, adjust fonts and more."),
        },

        -- 16. Settings & Updates (static)
        {
            title       = _("Settings & Updates"),
            image       = img("onboarding/zen_ui_settings.png"),
            description = _("All settings in one unified tab.\nCheck for and install Zen UI updates directly from your e-reader."),
        },

        -- 17. Finale
        {
            title       = _("You're All Set"),
            icon        = "zen_ui",
            finale      = true,
            description = _("The best interface is the one you forget is there.\nNow go get lost in a good book."),
        },
    }

    -- Insert home folder page before finale if home_dir has not been customized.
    do
        local current_home = G_reader_settings and G_reader_settings:readSetting("home_dir")
        if not current_home or current_home == "" then
            -- Detect the device's primary storage root for path suggestions.
            local base_storage = "/"
            pcall(function()
                local Dev = require("device")
                if     Dev.isKobo       and Dev:isKobo()       then base_storage = "/mnt/onboard"
                elseif Dev.isKindle     and Dev:isKindle()     then base_storage = "/mnt/base-us"
                elseif Dev.isPocketBook and Dev:isPocketBook() then base_storage = "/mnt/ext1"
                elseif Dev.isAndroid    and Dev:isAndroid()    then base_storage = "/sdcard"
                end
            end)
            local books_dir = base_storage .. "/books"
            -- Insert at second-to-last position (before finale).
            table.insert(pages, #pages, {
                title       = _("Home Folder"),
                description = T(_("The place for all your books %1"), books_dir),
                choice_type = "radio",
                choices     = {
                    { id = "books",  text = _("Create this folder and use as home"), checked = true  },
                    { id = "choose", text = _("Choose a different folder"),           checked = false },
                    { id = "skip",   text = _("Skip"),                                checked = false },
                },
                on_apply = function(sel)
                    if sel["skip"] then return end
                    local function apply_sort_defaults()
                        G_reader_settings:saveSetting("collate", "access")
                        G_reader_settings:saveSetting("collate_mixed", true)
                    end
                    if sel["books"] then
                        local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
                        if not ok_lfs then return end
                        if lfs.attributes(books_dir, "mode") ~= "directory" then
                            lfs.mkdir(books_dir)
                        end
                        if lfs.attributes(books_dir, "mode") == "directory" then
                            G_reader_settings:saveSetting("home_dir", books_dir)
                            apply_sort_defaults()
                        end
                    elseif sel["choose"] then
                        local ok_ui, UIMan = pcall(require, "ui/uimanager")
                        if not ok_ui then return end
                        UIMan:scheduleIn(0.3, function()
                            local ok_pc, PathChooser = pcall(require, "ui/widget/pathchooser")
                            if not ok_pc then return end
                            UIMan:show(PathChooser:new{
                                select_directory = true,
                                path             = base_storage,
                                onConfirm        = function(chosen_path)
                                    if chosen_path and chosen_path ~= "" then
                                        G_reader_settings:saveSetting("home_dir", chosen_path)
                                        apply_sort_defaults()
                                    end
                                end,
                            })
                        end)
                    end
                end,
            })
        end
    end

    -- Inject real cover art and rendered icons into preview pages.
    local ok_inject, err_inject = pcall(function()
        local covers  = loadQuickstartCovers(3)
        local Device  = require("device")
        local avail_w = Device.screen:getWidth() - Device.screen:scaleBySize(80)
        local mosaic_bb  = #covers > 0 and buildMosaicBB(covers, avail_w) or nil
        local list_bb    = #covers > 0 and buildListBB(covers, avail_w) or nil
        local browser_bb = #covers > 0 and buildMosaicBB(covers, avail_w) or nil
        local zen_bb     = buildZenButtonBB(avail_w)
        local home_bb    = buildHomeIconBB(avail_w)
        for _, c in ipairs(covers) do c.bb:free() end
        for _i, page in ipairs(pages) do
            if page.title == _("File Browser") and browser_bb then
                page.image_bb, page.image = browser_bb, nil
            elseif page.title == _("Zen Mode") and zen_bb then
                page.image_bb, page.image = zen_bb, nil
            elseif page.title == _("Home Folder") and home_bb then
                page.image_bb, page.image = home_bb, nil
            end
            if page.choices then
                for _i, choice in ipairs(page.choices) do
                    if choice.id == "mosaic" and mosaic_bb then
                        choice.image_bb, choice.image = mosaic_bb, nil
                    elseif choice.id == "list" and list_bb then
                        choice.image_bb, choice.image = list_bb, nil
                    end
                end
            end
        end
    end)
    if not ok_inject then
        local logger = require("logger")
        logger.warn("ZenUI quickstart: cover injection failed:", err_inject)
    end

    return pages
end

-- ---------------------------------------------------------------------------

M.UPDATE_PAGES = {
    -- Add per-version pages when releasing updates. Example:
    -- ["0.1.0"] = {
    --     { title = "What's New in 0.1.0", image = img("0.1.0/feature.png"), description = "..." },
    -- },
}

-- Bullet list shown on the post-update splash screen (ZenScreen).
local ok_cl, changelog = pcall(require, "config/changelog")
M.CHANGELOGS = ok_cl and type(changelog) == "table" and changelog or {}

return M

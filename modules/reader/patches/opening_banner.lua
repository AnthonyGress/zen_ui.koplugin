-- Stores the screen dimen of the last tapped MosaicMenuItem so
-- showReaderCoroutine can position the banner over that specific cover cell.
local _last_cover_dimen = nil
-- _banner_active: true while a banner is on screen + doShowReader is running.
-- Blocks any showReaderCoroutine call that arrives BEFORE doShowReader finishes.
local _banner_active = false
-- _last_banner_seq: the _tap_seq value when the last banner was shown.
-- Blocks same-tap duplicate calls that arrive AFTER doShowReader finishes
-- (e.g. a DOM-version reload KOReader schedules during reader init).
-- Those calls are delegated to _orig so the reload happens without a banner.
-- Initialized to -1 so the very first call (e.g. from rakuyomi with no tap)
-- takes the banner path instead of being mistaken for a duplicate.
local _last_banner_seq = -1
-- Sequence counter: incremented on every onTapSelect call to correlate logs.
local _tap_seq = 0

-- Walk a widget tree (depth-first) to find the first rendered blitbuffer (_bb).
local function _find_cover_bb(w, depth)
    if depth > 5 or type(w) ~= "table" then return nil end
    local t = type(w._bb)
    if t == "userdata" or t == "cdata" then return w._bb end
    for i = 1, 8 do
        if not w[i] then break end
        local r = _find_cover_bb(w[i], depth + 1)
        if r then return r end
    end
    return nil
end

-- Sample the bottom 30 % of a blitbuffer and return the average luminance
-- (0 = black … 255 = white), or nil on failure.
local function _sample_bottom_luminance(bb)
    local w, h
    local ok = pcall(function() w = bb:getWidth(); h = bb:getHeight() end)
    if not ok or not w or w < 1 or not h or h < 1 then return nil end
    local y0 = math.max(0, math.floor(h * 0.70))
    local total, count = 0, 0
    local dx = math.max(1, math.floor(w / 12))
    local dy = math.max(1, math.floor(math.max(1, h - y0) / 4))
    pcall(function()
        for y = y0, h - 1, dy do
            for x = 0, w - 1, dx do
                local pix = bb:getPixel(x, y)
                local c8  = pix:getColor8()
                if c8 and c8.a then
                    total = total + c8.a
                    count = count + 1
                end
            end
        end
    end)
    if count == 0 then return nil end
    return total / count
end

local function apply_opening_banner()
    -- Replaces the default "Opening" InfoMessage with a slim strip pinned to
    -- the tapped cover cell; falls back to a full-width strip at the bottom
    -- of the screen when cover geometry is unknown (list mode, History, etc.).

    local ReaderUI = require("apps/reader/readerui")
    local UIManager = require("ui/uimanager")
    local Device = require("device")
    local Screen = Device.screen

    if type(ReaderUI.showReaderCoroutine) ~= "function" then
        return
    end

    -- Capture plugin reference while __ZEN_UI_PLUGIN is still set (it is cleared
    -- after patch application, so rawget at coroutine-time returns nil).
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local Blitbuffer = require("ffi/blitbuffer")
    local Font    = require("ui/font")
    local Geom    = require("ui/geometry")
    local TextWidget = require("ui/widget/textwidget")
    local Widget  = require("ui/widget/widget")
    local logger  = require("logger")
    local _       = require("gettext")

    -- Hook MosaicMenuItem.onTapSelect to capture cover cell geometry
    local function try_hook_mosaic()
        local ok, MosaicMenu = pcall(require, "mosaicmenu")
        if not ok or type(MosaicMenu) ~= "table" then return end

        local function get_upvalue(fn, name)
            if type(fn) ~= "function" then return nil end
            for i = 1, 64 do
                local n, v = debug.getupvalue(fn, i)
                if not n then break end
                if n == name then return v end
            end
        end

        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end

        if type(MosaicMenuItem.onTapSelect) ~= "function" then return end

        -- Match browser_cover_mosaic_uniform constants (kept in sync).
        local Size = require("ui/size")
        local _UNIFORM_BORDER = Size.border.thin or 1
        local _UNIFORM_UNDERLINE_RESERVE = 6
        local function _uniform_aspect()
            local s = _G.G_reader_settings and G_reader_settings:readSetting("uniform_cover_ratio") or "2:3"
            local n, d = tostring(s):match("(%d+):(%d+)")
            return (tonumber(n) or 2) / (tonumber(d) or 3)
        end
        -- Compute the rect of the actual painted cover for a tapped MosaicMenuItem.
        -- Primary source: _zen_cover_dimen, a snapshot of the cover widget's .dimen
        -- taken inside our paintTo wrapper (the only moment it is guaranteed to be
        -- set for all variants). Falls back to flag+cell-math for items that have
        -- not been painted yet (e.g. still-loading covers).
        local function find_cover_frame(item)
            local t = item[1] and item[1][1] and item[1][1][1]
            if not t then return nil end
            if t.bordersize ~= nil then return t end
            local inner = t[2] and t[2][1] and t[2][1][1]
            if inner and inner.bordersize ~= nil then return inner end
            return nil
        end

        local function _cover_rect(self_item, strip_h)
            -- Primary: exact screen rect captured after paintTo.
            local snap = self_item._zen_cover_dimen
            if snap and snap.w and snap.w > 0 then
                return { x = snap.x, y = snap.y, w = snap.w, h = snap.h, variant = "from-dimen" }
            end

            local id = self_item.dimen
            if not id then return nil end
            strip_h = strip_h or 0
            local cell_w      = id.w
            local cell_h_inner = id.h - strip_h
            if cell_w <= 0 or cell_h_inner <= 0 then return nil end

            -- Secondary: read actual width/height from the cover widget's constructor
            -- fields. These are set at build time (no paintTo needed) and give the
            -- correct position for both FakeCover (7/8 width, full height) and real
            -- covers (image-sized FrameContainer). More accurate than the uniform
            -- computation for FakeCover, which is NOT a 2:3 aspect-ratio widget.
            local cover_widget = find_cover_frame(self_item)
            if cover_widget
               and cover_widget.width  and cover_widget.width  > 0
               and cover_widget.height and cover_widget.height > 0
            then
                local cw = cover_widget.width
                local ch = cover_widget.height
                local cx = id.x + math.floor((cell_w      - cw) / 2)
                local cy = id.y + math.floor((cell_h_inner - ch) / 2)
                return { x = cx, y = cy, w = cw, h = ch, variant = "from-widget" }
            end

            -- Tertiary: if uniform cover mode is active, compute the uniform rect.
            -- Correct for uniform-resized real covers; FakeCover should have been
            -- caught by the from-widget path above, so this is a last resort.
            if MosaicMenuItem._zen_mosaic_uniform_patched == true then
                local border    = _UNIFORM_BORDER
                local max_img_w = cell_w - 2 * border
                local max_img_h = cell_h_inner - 2 * border - _UNIFORM_UNDERLINE_RESERVE
                if max_img_w > 0 and max_img_h > 0 then
                    local ar = _uniform_aspect()
                    local cw, ch
                    if max_img_w / max_img_h > ar then
                        ch = max_img_h
                        cw = math.floor(max_img_h * ar)
                    else
                        cw = max_img_w
                        ch = math.floor(max_img_w / ar)
                    end
                    local frame_w = cw + 2 * border
                    local frame_h = ch + 2 * border
                    local vpad   = math.floor((cell_h_inner - frame_h) / 2)
                    return {
                        x = id.x + math.floor((cell_w - frame_w) / 2),
                        y = id.y + vpad,
                        w = frame_w,
                        h = frame_h,
                        variant = "uniform",
                    }
                end
            end

            -- No usable rect found.
            return nil
        end

        -- Wrap paintTo to snapshot the cover widget's actual screen rect.
        -- cover.dimen is only set during paintTo, so this is the only reliable
        -- moment to read exact position/size regardless of cover variant.
        local orig_paintTo = MosaicMenuItem.paintTo
        if type(orig_paintTo) == "function" then
            MosaicMenuItem.paintTo = function(self_item, bb, x, y)
                orig_paintTo(self_item, bb, x, y)
                local cover = find_cover_frame(self_item)
                local d = cover and cover.dimen
                if d and d.w and d.w > 0 then
                    self_item._zen_cover_dimen = { x = d.x, y = d.y, w = d.w, h = d.h }
                end
            end
        end

        local orig_tap = MosaicMenuItem.onTapSelect
        MosaicMenuItem.onTapSelect = function(self_item, ...)
            _tap_seq = _tap_seq + 1
            -- Skip directories: a folder tap navigates the browser with no reader
            -- opening, so storing the dimen leaves a stale value that bleeds into
            -- the next book open (especially with folder-profile list mode).
            if not self_item.is_directory then
                -- self[1][1][1]: FrameContainer/FakeCover inside CenterContainer.
                local cover_frame = self_item[1] and self_item[1][1] and self_item[1][1][1]

                -- Use paintTo-snapshotted dimen if available (_zen_cover_dimen),
                -- with flag+cell-math as fallback for items not yet painted.
                local strip_h = self_item._zen_strip_h or 0
                local rect = _cover_rect(self_item, strip_h)
                if rect then
                    _last_cover_dimen = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
                end

                -- Require high contrast: if the cover's bottom is bright (lum >= 128),
                -- use a dark banner. If it's dark, use a light banner.
                -- Default to dark when no cover bb is available (placeholder cell).
                if _last_cover_dimen then
                    local cover_bb = _find_cover_bb(cover_frame or self_item, 0)
                    if cover_bb then
                        local lum = _sample_bottom_luminance(cover_bb)
                        _last_cover_dimen.dark_banner = lum == nil or lum >= 128
                    else
                        _last_cover_dimen.dark_banner = true
                    end
                end
            else
                -- Navigating into a folder: discard any previously stored dimen
                -- so it cannot bleed into a subsequent book open in list mode.
                _last_cover_dimen = nil
            end
            return orig_tap(self_item, ...)
        end
    end

    -- Hook ListMenuItem.onTapSelect to capture list-item geometry
    -- (used when a folder profile forces list mode inside a mosaic browser)
    local function try_hook_list()
        local ok, ListMenu = pcall(require, "listmenu")
        if not ok or type(ListMenu) ~= "table" then return end

        local function get_upvalue(fn, name)
            if type(fn) ~= "function" then return nil end
            for i = 1, 64 do
                local n, v = debug.getupvalue(fn, i)
                if not n then break end
                if n == name then return v end
            end
        end

        local ListMenuItem = get_upvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
        if not ListMenuItem then return end
        if type(ListMenuItem.onTapSelect) ~= "function" then return end

        local orig_tap = ListMenuItem.onTapSelect
        ListMenuItem.onTapSelect = function(self_item, ...)
            _tap_seq = _tap_seq + 1
            if not self_item.is_directory and self_item.dimen then
                -- Pin the banner to the bottom edge of the tapped list row.
                -- Flag as list mode so the banner can be offset past the cover art.
                _last_cover_dimen = {
                    x = self_item.dimen.x,
                    y = self_item.dimen.y,
                    w = self_item.dimen.w,
                    h = self_item.dimen.h,
                    is_list    = true,
                    dark_banner = true,  -- list mode always dark
                }
            else
                _last_cover_dimen = nil
            end
            return orig_tap(self_item, ...)
        end
    end

    pcall(try_hook_mosaic)
    pcall(try_hook_list)

    -- Bottom-corner masking for the banner
    local function _mask_bottom_corners(bb, x, y, w, h, r)
        local color = Blitbuffer.COLOR_WHITE
        for j = 0, r - 1 do
            local inner = math.sqrt(r * r - (r - j) * (r - j))
            local cut   = math.ceil(r - inner)
            if cut > 0 then
                bb:paintRect(x,           y + h - 1 - j, cut, 1, color)
                bb:paintRect(x + w - cut, y + h - 1 - j, cut, 1, color)
            end
        end
    end

    -- Border that follows rounded bottom corners
    -- Must be called AFTER _mask_bottom_corners so the border is never overwritten.
    local function _draw_border(bb, x, y, w, h, r, color)
        -- Top edge (always straight)
        bb:paintRect(x, y, w, 1, color)
        if r > 0 then
            -- Left / right: straight down to where the arc begins
            bb:paintRect(x,         y, 1, h - r, color)
            bb:paintRect(x + w - 1, y, 1, h - r, color)
            -- Bottom straight segment between the two arc zones
            if w > 2 * r then
                bb:paintRect(x + r, y + h - 1, w - 2 * r, 1, color)
            end
            -- Bottom-left and bottom-right 1px arc borders
            local r_inner = r - 1
            for j = 0, r - 1 do
                for c = 0, r - 1 do
                    local dx   = r - c - 0.5
                    local dy   = r - j - 0.5
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist >= r_inner and dist <= r then
                        bb:paintRect(x + c,           y + h - 1 - j, 1, 1, color)
                        bb:paintRect(x + w - 1 - c,   y + h - 1 - j, 1, 1, color)
                    end
                end
            end
        else
            -- Simple rectangular border (no rounding)
            bb:paintRect(x,         y + h - 1, w, 1, color)
            bb:paintRect(x,         y,         1, h, color)
            bb:paintRect(x + w - 1, y,         1, h, color)
        end
    end

    -- Tiny inline widget: black rect + centred "Opening" text
    local OpeningBanner = Widget:extend{}

    function OpeningBanner:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        -- XOR dark_banner with night mode so colors are always visually correct.
        local night_mode = G_reader_settings and G_reader_settings:isTrue("night_mode") or false
        local use_dark = self.dark_banner ~= night_mode
        local bg = use_dark and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local fg = use_dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local w, h = self.dimen.w, self.dimen.h
        local r    = self.round_bottom_corners and Screen:scaleBySize(8) or 0

        -- 1. Fill background
        bb:paintRect(x, y, w, h, bg)
        -- 2. Clip bottom corners (before border so the border draws on top)
        if r > 0 then
            _mask_bottom_corners(bb, x, y, w, h, r)
        end
        -- 3. Border contrasts with bg (fg color), consistent with night mode.
        _draw_border(bb, x, y, w, h, r, fg)

        local tw = TextWidget:new{
            text      = self.label or _("Opening"),
            face      = Font:getFace("cfont", Screen:scaleBySize(7)),
            fgcolor   = fg,
            bold      = true,
        }
        local tsz = tw:getSize()
        tw:paintTo(bb,
            x + math.floor((w - tsz.w) / 2),
            y + math.floor((h - tsz.h) / 2))
        tw:free()
    end

    -- Patch showReaderCoroutine.
    -- We do NOT call the original on the duplicate-tap path: the original
    -- shows its own "Opening file '%1'." InfoMessage which the user would
    -- perceive as a second banner overlapping ours. Instead, on a duplicate
    -- same-tap call we run doShowReader directly (no InfoMessage).
    local function _show_reader_no_banner(self, file, provider, seamless)
        logger.info("zen-ui opening_banner: _show_reader_no_banner called, file=", tostring(file))
        -- do NOT defer with nextTick: a deferred doShowReader allows UIManager
        -- to exit before the reader widget is shown (e.g. rakuyomi where the
        -- caller's widget tree unwinds before the next tick fires).
        logger.info("zen-ui opening_banner: _show_reader_no_banner creating doShowReader coroutine, file=", tostring(file), "provider=", tostring(provider))
        local co = coroutine.create(function()
            logger.info("zen-ui opening_banner: _show_reader_no_banner doShowReader coroutine starting")
            local doc_ok, doc_err = pcall(function()
                self:doShowReader(file, provider, seamless)
            end)
            if not doc_ok then
                logger.err("zen-ui opening_banner: _show_reader_no_banner doShowReader threw error:", tostring(doc_err))
                logger.err("zen-ui opening_banner: _show_reader_no_banner doShowReader traceback:", debug.traceback())
            end
            logger.info("zen-ui opening_banner: _show_reader_no_banner doShowReader coroutine finished, ok=", tostring(doc_ok))
        end)
        logger.info("zen-ui opening_banner: _show_reader_no_banner resuming doShowReader coroutine")
        local ok, err = coroutine.resume(co)
        logger.info("zen-ui opening_banner: _show_reader_no_banner doShowReader coroutine resumed, ok=", tostring(ok), "err=", tostring(err))
        if err ~= nil or ok == false then
            logger.err("zen-ui opening_banner: _show_reader_no_banner coroutine crashed, err=", tostring(err), "ok=", tostring(ok))
            io.stderr:write("[!] doShowReader coroutine crashed:\n")
            io.stderr:write(debug.traceback(co, err, 1))
            Device:setIgnoreInput(false)
            local Input = require("device/input")
            Input:inhibitInputUntil(0.2)
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("No reader engine for this file or invalid file."),
            })
            self:showFileManager(file)
        end
    end

        ReaderUI.showReaderCoroutine = function(self, file, provider, seamless)
        logger.info("zen-ui opening_banner: showReaderCoroutine called, file=", tostring(file), "provider=", tostring(provider), "seamless=", tostring(seamless))
        if seamless then
            -- Seamless reloads must keep KOReader's behavior (invisible InfoMessage).
            logger.info("zen-ui opening_banner: seamless reload, delegating to _show_reader_no_banner")
            return _show_reader_no_banner(self, file, provider, seamless)
        end
        -- While the banner is already on screen + doShowReader is running,
        -- skip entirely: the first call's nextTick will open the reader.
        if _banner_active then
            return
        end
        -- KOReader calls showReaderCoroutine more than once per tap in some
        -- cases (e.g. a DOM-version reload scheduled via nextTick during
        -- reader init). After the first banner for a given tap, run the
        -- reload via our InfoMessage-free path so no second banner appears.
        if _last_banner_seq == _tap_seq then
            return _show_reader_no_banner(self, file, provider, seamless)
        end
        _last_banner_seq = _tap_seq
        _banner_active = true

        local banner_h = Screen:scaleBySize(28)
        local cover    = _last_cover_dimen
        _last_cover_dimen = nil     -- consume immediately

        local bx, by, bw
        if cover then
            by = cover.y + cover.h - banner_h
            if cover.is_list then
                -- In list mode the cover art is a square thumbnail whose width
                -- equals the row height.  Start the banner just to the right of
                -- it so it never draws over the cover image.
                bx = cover.x + cover.h
                bw = cover.w - cover.h
            else
                -- Mosaic mode: banner spans the full cover cell width
                bx = cover.x
                bw = cover.w
            end
        else
            -- Fallback: full-width strip at the bottom of the screen
            bx = 0
            by = Screen:getHeight() - banner_h
            bw = Screen:getWidth()
        end

        local plug = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        local round_bottom = cover and not cover.is_list
            and plug
            and type(plug.config) == "table"
            and type(plug.config.features) == "table"
            and plug.config.features.browser_cover_rounded_corners == true

        local banner = OpeningBanner:new{
            dimen                = Geom:new{ x = bx, y = by, w = bw, h = banner_h },
            dark_banner          = cover and cover.dark_banner or false,
            round_bottom_corners = round_bottom and true or false,
        }

        UIManager:show(banner, "ui", Geom:new{x=bx, y=by, w=bw, h=banner_h}, bx, by)
        UIManager:forceRePaint()

        UIManager:nextTick(function()
            -- Close the banner before opening the reader: an orphaned banner
            -- prevents _gated_quit from firing (UIManager stack never empties),
            -- causing KOReader to hang when the user quits from any menu.
            UIManager:close(banner)
            logger.warn("zen-ui opening_banner: nextTick fired, creating doShowReader coroutine")

            -- Keep _banner_active=true until doShowReader completes so any
            -- spurious second showReaderCoroutine call is blocked by the guard.
            logger.info("zen-ui opening_banner: creating coroutine for doShowReader, file=", tostring(file), "provider=", tostring(provider))
            local co = coroutine.create(function()
                logger.info("zen-ui opening_banner: doShowReader coroutine starting")
                local doc_ok, doc_err = pcall(function()
                    self:doShowReader(file, provider, seamless)
                end)
                if not doc_ok then
                    logger.err("zen-ui opening_banner: doShowReader threw error:", tostring(doc_err))
                    logger.err("zen-ui opening_banner: doShowReader traceback:", debug.traceback())
                end
                logger.info("zen-ui opening_banner: doShowReader coroutine finished, ok=", tostring(doc_ok))
            end)
            logger.info("zen-ui opening_banner: resuming doShowReader coroutine")
            local ok, err = coroutine.resume(co)
            -- Reset AFTER doShowReader finishes. Sync _last_banner_seq to the
            -- CURRENT _tap_seq (not just the value when the banner was shown) so
            -- any tap that arrived during loading (incrementing _tap_seq) doesn't
            -- bypass the same-seq guard for subsequent reloads. Also discard any
            -- stale _last_cover_dimen that a mid-load tap may have written.
            _banner_active = false
            _last_banner_seq = _tap_seq
            _last_cover_dimen = nil
            logger.info("zen-ui opening_banner: doShowReader coroutine resumed, ok=", tostring(ok), "err=", tostring(err))
            if err ~= nil or ok == false then
                logger.err("zen-ui opening_banner: doShowReader coroutine crashed in showReaderCoroutine, err=", tostring(err), "ok=", tostring(ok))
                io.stderr:write("[!] doShowReader coroutine crashed:\n")
                io.stderr:write(debug.traceback(co, err, 1))
                Device:setIgnoreInput(false)
                local Input = require("device/input")
                Input:inhibitInputUntil(0.2)
                local InfoMessage = require("ui/widget/infomessage")
                UIManager:show(InfoMessage:new{
                    text = _("No reader engine for this file or invalid file."),
                })
                self:showFileManager(file)
            end
        end)
    end
end

return apply_opening_banner

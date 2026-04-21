-- Stores the screen dimen of the last tapped MosaicMenuItem so
-- showReaderCoroutine can position the banner over that specific cover cell.
local _last_cover_dimen = nil

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

        local orig_tap = MosaicMenuItem.onTapSelect
        MosaicMenuItem.onTapSelect = function(self_item, ...)
            -- Skip directories: a folder tap navigates the browser with no reader
            -- opening, so storing the dimen leaves a stale value that bleeds into
            -- the next book open (especially with folder-profile list mode).
            if not self_item.is_directory then
                -- self[1][1][1]: FrameContainer holding the cover image
                -- (UnderlineContainer → CenterContainer → FrameContainer).
                local cover_frame = self_item[1] and self_item[1][1] and self_item[1][1][1]
                local d = cover_frame and cover_frame.dimen
                if d and d.x and d.w then
                    _last_cover_dimen = { x = d.x, y = d.y, w = d.w, h = d.h }
                elseif self_item.dimen then
                    _last_cover_dimen = {
                        x = self_item.dimen.x,
                        y = self_item.dimen.y,
                        w = self_item.dimen.w,
                        h = self_item.dimen.h,
                    }
                end
                -- Determine banner contrast: bright cover (lum >= 128) -> dark banner.
                if _last_cover_dimen then
                    local cover_bb = _find_cover_bb(cover_frame or self_item, 0)
                    if cover_bb then
                        local lum = _sample_bottom_luminance(cover_bb)
                        _last_cover_dimen.dark_banner = lum ~= nil and lum >= 128
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
            if not self_item.is_directory and self_item.dimen then
                -- Pin the banner to the bottom edge of the tapped list row.
                -- Flag as list mode so the banner can be offset past the cover art.
                _last_cover_dimen = {
                    x = self_item.dimen.x,
                    y = self_item.dimen.y,
                    w = self_item.dimen.w,
                    h = self_item.dimen.h,
                    is_list = true,
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
        local bg = self.dark_banner and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE
        local fg = self.dark_banner and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        local w, h = self.dimen.w, self.dimen.h
        local r    = self.round_bottom_corners and Screen:scaleBySize(8) or 0

        -- 1. Fill background
        bb:paintRect(x, y, w, h, bg)
        -- 2. Clip bottom corners (before border so the border draws on top)
        if r > 0 then
            _mask_bottom_corners(bb, x, y, w, h, r)
        end
        -- 3. Border (after masking so it is never erased)
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

    -- Patch showReaderCoroutine
    local _orig = ReaderUI.showReaderCoroutine

    ReaderUI.showReaderCoroutine = function(self, file, provider, seamless)
        if seamless then
            return _orig(self, file, provider, seamless)
        end

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

            logger.dbg("zen-ui: creating coroutine for showing reader")
            local co = coroutine.create(function()
                self:doShowReader(file, provider, seamless)
            end)
            local ok, err = coroutine.resume(co)
            if err ~= nil or ok == false then
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

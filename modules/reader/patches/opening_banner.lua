-- Stores the screen dimen of the last tapped MosaicMenuItem so
-- showReaderCoroutine can position the banner over that specific cover cell.
local _last_cover_dimen = nil

local function apply_opening_banner()
    --[[
        Replaces KOReader's default "Opening file '...'" InfoMessage popup with a
        slim strip pinned to the bottom of the tapped book cover cell.

        If the cover dimen is unknown (list mode, History, etc.) the banner falls
        back to a full-width strip at the bottom of the screen.
    ]]

    local ReaderUI = require("apps/reader/readerui")
    local UIManager = require("ui/uimanager")
    local Device = require("device")
    local Screen = Device.screen

    if type(ReaderUI.showReaderCoroutine) ~= "function" then
        return
    end

    local Blitbuffer = require("ffi/blitbuffer")
    local Font    = require("ui/font")
    local Geom    = require("ui/geometry")
    local TextWidget = require("ui/widget/textwidget")
    local Widget  = require("ui/widget/widget")
    local logger  = require("logger")
    local _       = require("gettext")

    -- ── Hook MosaicMenuItem.onTapSelect to capture cover cell geometry ──────
    -- The coverbrowser plugin lives at plugins/coverbrowser.koplugin and
    -- exports MosaicMenu as a plain require("mosaicmenu") once its directory
    -- is on the package path.
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

        -- onTapSelect is the ges_events handler for "tap" on MosaicMenuItem
        if type(MosaicMenuItem.onTapSelect) ~= "function" then return end

        local orig_tap = MosaicMenuItem.onTapSelect
        MosaicMenuItem.onTapSelect = function(self_item, ...)
            -- Only capture dimen for book files, not directories.
            -- Tapping a folder navigates the browser (no reader opens), so
            -- storing the dimen here would leave a stale value that gets
            -- incorrectly consumed when the user later opens a book from inside
            -- that folder (e.g. when a folder profile forces list mode).
            if not self_item.is_directory then
                -- self[1][1][1] is the FrameContainer holding the actual cover
                -- image (UnderlineContainer → CenterContainer → FrameContainer).
                -- Its dimen has the exact absolute screen coordinates of the cover
                -- art, which is narrower/shorter than the full cell (self.dimen).
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
            else
                -- Navigating into a folder: discard any previously stored dimen
                -- so it cannot bleed into a subsequent book open in list mode.
                _last_cover_dimen = nil
            end
            return orig_tap(self_item, ...)
        end
    end

    -- ── Hook ListMenuItem.onTapSelect to capture list-item geometry ──────────
    -- When a folder profile forces list mode inside a globally-mosaic browser,
    -- MosaicMenuItem is not used.  Capture the list item's dimen so the banner
    -- can be pinned to the right-hand edge of the tapped row.
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
                -- Use full row width so it spans the item cleanly.
                _last_cover_dimen = {
                    x = self_item.dimen.x,
                    y = self_item.dimen.y,
                    w = self_item.dimen.w,
                    h = self_item.dimen.h,
                }
            else
                _last_cover_dimen = nil
            end
            return orig_tap(self_item, ...)
        end
    end

    pcall(try_hook_mosaic)
    pcall(try_hook_list)

    -- ── Tiny inline widget: black rect + centred "Opening" text ─────────────
    local OpeningBanner = Widget:extend{}

    function OpeningBanner:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        bb:paintRect(x, y, self.dimen.w, self.dimen.h, Blitbuffer.COLOR_BLACK)

        local tw = TextWidget:new{
            text      = self.label or _("Opening"),
            face      = Font:getFace("cfont", Screen:scaleBySize(7)),
            fgcolor   = Blitbuffer.COLOR_WHITE,
            bold      = true,
        }
        local tsz = tw:getSize()
        tw:paintTo(bb,
            x + math.floor((self.dimen.w - tsz.w) / 2),
            y + math.floor((self.dimen.h - tsz.h) / 2))
        tw:free()
    end

    -- ── Patch showReaderCoroutine ────────────────────────────────────────────
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
            -- Pin banner to the bottom edge of the tapped cover cell
            bx = cover.x
            by = cover.y + cover.h - banner_h
            bw = cover.w
        else
            -- Fallback: full-width strip at the bottom of the screen
            bx = 0
            by = Screen:getHeight() - banner_h
            bw = Screen:getWidth()
        end

        local banner = OpeningBanner:new{
            dimen = Geom:new{ x = bx, y = by, w = bw, h = banner_h },
        }

        UIManager:show(banner, "ui", Geom:new{x=bx, y=by, w=bw, h=banner_h}, bx, by)
        UIManager:forceRePaint()

        UIManager:nextTick(function()
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

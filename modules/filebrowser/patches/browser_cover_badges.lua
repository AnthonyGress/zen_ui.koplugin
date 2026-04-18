--[[
    browser_cover_badges.lua
    ─────────────────────────────────────────────────────────────────────────────
    Mosaic mode:
      • Removes dog-ear icons (reading / abandoned / complete corner marks).
      • Moves the collection-star (favorite) from top-right → top-left.
      • Optionally paints a progress-% badge (pentagon SVG + text) at top-right,
        controlled by the "Show progress % on mosaic covers" Zen UI setting.

    List mode:
      • Removes the dog-ear corner mark at bottom-right. Nothing else changes.

    Always applied – no feature flag required.
]]

-- Resolve the plugin icons/ directory at module-load time - kept for future use.
local _ICONS_DIR
do
    local src = debug.getinfo(1, "S").source or ""
    if src:sub(1, 1) == "@" then
        local plugin_root = src:sub(2):match("^(.*)/modules/")
        if plugin_root then _ICONS_DIR = plugin_root .. "/icons/" end
    end
end

local function apply_browser_cover_badges()
    local BD             = require("ui/bidi")
    local Blitbuffer     = require("ffi/blitbuffer")
    local Font           = require("ui/font")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local ReadCollection = require("readcollection")
    local Screen         = require("device").screen
    local TextWidget     = require("ui/widget/textwidget")

    -- ── Capture plugin reference NOW, while __ZEN_UI_PLUGIN is still set ──────
    -- run_feature() sets the global only during pcall(fn), so it is nil by the
    -- time paintTo fires. Closing over it here is the only safe approach.
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    -- ── Draw a downward-pointing pentagon directly with blitbuffer ───────────
    -- Matches icons/progress_badge.svg: viewBox "0 0 36 42",
    --   rect 0→30 (71.4 %), then triangle tip 30→42 centred.
    local function paintPentagon(bb, bx, by, bw, bh, color)
        local rect_h = math.floor(bh * 30 / 42)
        local tip_h  = bh - rect_h
        bb:paintRect(bx, by, bw, rect_h, color)
        for row = 0, tip_h - 1 do
            local frac = (row + 1) / tip_h          -- 0 → 1 as we approach the tip
            local rw   = math.max(2, math.floor(bw * (1 - frac)))
            local rx   = bx + math.floor((bw - rw) / 2)
            bb:paintRect(rx, by + rect_h + row, rw, 1, color)
        end
    end

    -- ── Draw a ✓ checkmark as two diagonal strokes (no background) ──────────────
    local function paintCheck(bb, bx, by, bw, bh, color)
        -- stroke width scales with badge size: ~1/8 of the shorter dimension
        local tk = math.max(2, math.floor(math.min(bw, bh) / 8))
        local function drawLine(x0, y0, x1, y1)
            local steps = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
            if steps == 0 then steps = 1 end
            for i = 0, steps do
                local t = i / steps
                bb:paintRect(
                    math.floor(x0 + t * (x1 - x0)),
                    math.floor(y0 + t * (y1 - y0)),
                    tk, tk, color)
            end
        end
        -- Short left arm: (8%,62%) → (30%,82%)  — shallow descent
        local lx0 = bx + math.floor(bw * 0.08)
        local ly0 = by + math.floor(bh * 0.62)
        local lx1 = bx + math.floor(bw * 0.30)
        local ly1 = by + math.floor(bh * 0.82)
        -- Long right arm: pivot → (82%,18%)
        local rx1 = bx + math.floor(bw * 0.82)
        local ry1 = by + math.floor(bh * 0.18)
        drawLine(lx0, ly0, lx1, ly1)
        drawLine(lx1, ly1, rx1, ry1)
    end

    -- ── Draw two vertical bars (pause / on-hold) ─────────────────────────────
    local function paintPauseBars(bb, bx, by, bw, bh, color)
        local bar_w = math.max(2, math.floor(bw * 0.12))
        local bar_h = math.floor(bh * 0.68)
        local gap   = math.max(2, math.floor(bw * 0.18))
        local total = 2 * bar_w + gap
        local bar1x = bx + math.floor((bw - total) / 2)
        local bar2x = bar1x + bar_w + gap
        local bar_y = by + math.floor((bh - bar_h) / 2)
        bb:paintRect(bar1x, bar_y, bar_w, bar_h, color)
        bb:paintRect(bar2x, bar_y, bar_w, bar_h, color)
    end

    -- ── Generic upvalue accessor ───────────────────────────────────────────────
    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then return nil end
        for i = 1, 128 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then break end
            if upname == name then return value end
        end
    end

    -- ── Mosaic patch ───────────────────────────────────────────────────────────
    local function patchMosaicMenu()
        local MosaicMenu     = require("mosaicmenu")
        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end

        local orig_paintTo = MosaicMenuItem.paintTo
        if not orig_paintTo then return end

        -- Build upvalue name→index map once at patch time for fast runtime reads.
        local uv_idx = {}
        for i = 1, 256 do
            local name = debug.getupvalue(orig_paintTo, i)
            if not name then break end
            uv_idx[name] = i
        end
        local function uv(name)
            local idx = uv_idx[name]
            if not idx then return nil end
            local _, v = debug.getupvalue(orig_paintTo, idx)
            return v
        end

        function MosaicMenuItem:paintTo(bb, x, y)
            -- 1. Base widget painting (cover image / FakeCover / folder tree)
            InputContainer.paintTo(self, bb, x, y)

            -- 2. Shortcut icon (top-left, unchanged)
            if self.shortcut_icon then
                local ix = BD.mirroredUILayout()
                    and (self.dimen.w - self.shortcut_icon.dimen.w) or 0
                self.shortcut_icon:paintTo(bb, x + ix, y)
            end

            -- Resolve inner cover-frame sub-widget and current mark size
            local target = self[1] and self[1][1] and self[1][1][1]
            if not (target and target.dimen and target.dimen.y) then return end

            local corner_mark_size = uv("corner_mark_size")
            if not (corner_mark_size and corner_mark_size > 0) then return end

            local border = target.bordersize or 0

            -- 3. Collection/favorite star → TOP-LEFT (was top-right) ────────────
            local collection_mark = uv("collection_mark")
            if collection_mark
                and self.filepath
                and self.menu.name ~= "collections"
                and ReadCollection:isFileInCollections(self.filepath)
            then
                local ix, rect_ix
                if BD.mirroredUILayout() then
                    ix      = self.width - math.ceil((self.width - target.dimen.w) / 2) - corner_mark_size
                    rect_ix = 0
                else
                    ix      = math.floor((self.width - target.dimen.w) / 2)
                    rect_ix = border
                end
                local rect_size = corner_mark_size - border
                bb:paintRect(
                    x + ix + rect_ix, target.dimen.y + border,
                    rect_size, rect_size,
                    Blitbuffer.COLOR_GRAY
                )
                collection_mark:paintTo(bb, x + ix, target.dimen.y)
            end

            -- 4. Dog-ear marks SUPPRESSED ────────────────────────────────────────

            -- 5. KOReader's own bottom progress bar (show_progress_in_mosaic) ────
            if self.show_progress_bar then
                local progress_widget = uv("progress_widget")
                if progress_widget then
                    local margin  = math.floor((corner_mark_size - progress_widget.height) / 2)
                    progress_widget.width = target.width - 2 * margin
                    local pos_x = x + math.ceil((self.width - progress_widget.width) / 2)
                    if self.do_hint_opened then
                        progress_widget.width = progress_widget.width - corner_mark_size
                        if BD.mirroredUILayout() then pos_x = pos_x + corner_mark_size end
                    end
                    local pos_y = y + self.height
                        - math.ceil((self.height - target.height) / 2)
                        - corner_mark_size + margin
                    progress_widget.fillcolor = (self.status == "abandoned")
                        and Blitbuffer.COLOR_GRAY_6 or Blitbuffer.COLOR_BLACK
                    progress_widget:setPercentage(self.percent_finished)
                    progress_widget:paintTo(bb, pos_x, pos_y)
                end
            end

            -- 6. Zen UI: status/progress badge at TOP-RIGHT ──────────────────────
            local show_badge = _plugin
                and _plugin.config
                and type(_plugin.config.browser_cover_badges) == "table"
                and _plugin.config.browser_cover_badges.show_mosaic_progress == true

            if show_badge and self.filepath then
                local do_check = (self.status == "complete")
                local do_pause = (self.status == "abandoned")
                local do_pct   = not do_check and not do_pause and self.percent_finished ~= nil

                if do_check or do_pause or do_pct then
                    local bw = math.floor(corner_mark_size * 1.2)
                    local bh = math.floor(corner_mark_size * 1.1)

                    -- Align to top-right edge of cover frame, inset slightly
                    local cover_left = x + math.floor((self.width - target.dimen.w) / 2)
                    local bdg_x = cover_left + target.dimen.w - bw - math.floor(bw * 0.25)
                    -- Shift down by border thickness so border top aligns with cover top
                    local bdg_y = target.dimen.y + 2

                    -- Border drawn 2px outside fill; COLOR_BLACK inverts to white in night mode
                    paintPentagon(bb, bdg_x - 2, bdg_y - 2, bw + 4, bh + 4, Blitbuffer.COLOR_BLACK)
                    paintPentagon(bb, bdg_x, bdg_y, bw, bh, Blitbuffer.COLOR_LIGHT_GRAY)

                    local rect_h = math.floor(bh * 30 / 42)
                    -- Inner icon/text area with a little padding
                    local pad_x  = math.floor(bw * 0.12)
                    local pad_y  = math.floor(rect_h * 0.15)
                    local icon_x = bdg_x + pad_x
                    local icon_y = bdg_y + pad_y
                    local icon_w = bw - 2 * pad_x
                    local icon_h = rect_h - 2 * pad_y

                    if do_check then
                        -- Constrain to square so the checkmark isn't distorted
                        local sq   = math.min(icon_w, icon_h)
                        local sq_x = icon_x + math.floor((icon_w - sq) / 2)
                        local sq_y = icon_y + math.floor((icon_h - sq) / 2)
                        paintCheck(bb, sq_x, sq_y, sq, sq, Blitbuffer.COLOR_BLACK)
                    elseif do_pause then
                        paintPauseBars(bb, icon_x, icon_y, icon_w, icon_h, Blitbuffer.COLOR_BLACK)
                    else
                        local pct     = math.floor(100 * self.percent_finished)
                        local pct_str = pct .. "%"
                        local font_sz = math.max(7, math.floor(corner_mark_size * 0.24))
                        local tw = TextWidget:new{
                            text    = pct_str,
                            face    = Font:getFace("cfont", font_sz),
                            bold    = true,
                            fgcolor = Blitbuffer.COLOR_BLACK,
                            padding = 0,
                        }
                        local tw_sz = tw:getSize()
                        tw:paintTo(bb,
                            bdg_x + math.floor((bw    - tw_sz.w) / 2),
                            bdg_y + math.floor((rect_h - tw_sz.h) / 2)
                        )
                        if tw.free then tw:free() end
                    end
                end
            end

            -- 7. Description indicator (unchanged from original) ─────────────────
            local BookInfoManager = uv("BookInfoManager")
            if self.has_description
                and BookInfoManager
                and not BookInfoManager:getSetting("no_hint_description")
            then
                local d_w = Screen:scaleBySize(3)
                local d_h = math.ceil(target.dimen.h / 8)
                local ix
                if BD.mirroredUILayout() then
                    ix = -d_w + 1
                    local x_overflow = x - target.dimen.x + ix
                    if x_overflow > 0 then
                        self.refresh_dimen = self[1].dimen:copy()
                        self.refresh_dimen.x = self.refresh_dimen.x - x_overflow
                        self.refresh_dimen.w = self.refresh_dimen.w + x_overflow
                    end
                else
                    ix = target.dimen.w - 1
                    local x_overflow = target.dimen.x + ix + d_w - x - self.dimen.w
                    if x_overflow > 0 then
                        self.refresh_dimen = self[1].dimen:copy()
                        self.refresh_dimen.w = self.refresh_dimen.w + x_overflow
                    end
                end
                bb:paintBorder(target.dimen.x + ix, target.dimen.y, d_w, d_h, 1)
            end
        end
    end

    -- ── List patch: suppress dog-ear only ─────────────────────────────────────
    local function patchListMenu()
        local ListMenu     = require("listmenu")
        local ListMenuItem = get_upvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
        if not ListMenuItem then return end

        local orig_list_paintTo = ListMenuItem.paintTo
        if not orig_list_paintTo then return end

        function ListMenuItem:paintTo(bb, x, y)
            local saved         = self.do_hint_opened
            self.do_hint_opened = false
            orig_list_paintTo(self, bb, x, y)
            self.do_hint_opened = saved
        end
    end

    -- ── Hook FileManager:setupLayout (same pattern as other patches) ───────────
    local FileManager      = require("apps/filemanager/filemanager")
    local orig_setupLayout = FileManager.setupLayout
    local patched          = false

    FileManager.setupLayout = function(self)
        orig_setupLayout(self)
        if not patched and self.coverbrowser then
            patchMosaicMenu()
            patchListMenu()
            patched = true
        end
    end
end

return apply_browser_cover_badges

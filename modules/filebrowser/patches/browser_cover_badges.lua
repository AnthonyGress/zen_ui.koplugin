--[[
    browser_cover_badges.lua
    Mosaic: removes dog-ears, moves favorite star to top-left, optionally
    paints a progress-% badge at top-right.
    List: removes the dog-ear mark.
    Always applied.
]]

-- Resolve the plugin icons/ directory at module-load time.
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
    local _              = require("gettext")

    -- Capture plugin reference while __ZEN_UI_PLUGIN is still set.
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    -- Draw a downward-pointing pentagon (matches progress_badge.svg viewBox 0 0 36 42).
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

    -- Draw a checkmark as two diagonal strokes.
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

    -- Draw a filled circle using scanline paintRect.
    local function paintCircle(bb, cx, cy, r, color)
        for row = -r, r do
            local half_w = math.floor(math.sqrt(math.max(0, r * r - row * row)))
            if half_w > 0 then
                bb:paintRect(cx - half_w, cy + row, 2 * half_w, 1, color)
            end
        end
    end

    -- Diagonal ribbon banner across the top-right corner.
    -- Renders a narrow band at 45 degrees with label text rotated inside it.
    -- Uses destination-driven inverse-map blitting from a temp buffer.
    local function paintCornerBanner(bb, cover_left, cover_right, cover_top, cover_h,
                                        span, band_thick, label, font_sz,
                                        fill_color, border_color)
        local C  = 0.70711  -- cos/sin 45 degrees
        -- Extend ribbon so ends protrude past cover top/right borders;
        -- cover-bounds clipping hides the ends cleanly (no visible end-cuts).
        local tw = math.ceil((span + band_thick * 2) * 1.41422)
        local th = band_thick
        if tw <= 0 or th <= 0 then return end

        local tmp = Blitbuffer.new(tw, th, bb:getType())
        if not tmp then return end

        -- 1px border on long edges, fill_color interior
        tmp:fill(border_color)
        local bw = 1
        if bw * 2 < th then
            tmp:paintRect(0, bw, tw, th - 2 * bw, fill_color)
        end

        -- Render text; step font down 1pt at a time until it fits, min 6pt
        local inner_h = math.max(1, th - bw * 2)
        local max_w   = math.floor(tw * 0.82)
        local lbl, lsz
        local fs = font_sz
        repeat
            if lbl and lbl.free then lbl:free() end
            lbl = TextWidget:new{
                text    = label,
                face    = Font:getFace("cfont", fs),
                bold    = true,
                fgcolor = border_color,
                padding = 0,
            }
            lsz = lbl:getSize()
            if lsz.w <= max_w and lsz.h <= inner_h then break end
            fs = fs - 1
        until fs < 6
        -- If still too large at minimum size, let it clip rather than disappear
        -- Clamp offsets: glyph metrics may exceed font_sz (line spacing etc.)
        local lx = math.max(0, math.floor((tw - lsz.w) / 2))
        local ly = math.max(0, math.floor((th - lsz.h) / 2))
        lbl:paintTo(tmp, lx, ly)
        if lbl.free then lbl:free() end

        -- Destination-driven inverse-map: for each screen pixel in the ribbon's
        -- bounding box, reverse-rotate to find the source pixel in tmp.
        local cx       = cover_right - math.floor(span / 2)
        local cy       = cover_top   + math.floor(span / 2)
        local half_box = math.ceil((tw + th) * C / 2) + 1
        local bb_w     = bb:getWidth()
        local bb_h     = bb:getHeight()
        local tw_half  = tw / 2
        local th_half  = th / 2
        for dy = cy - half_box, cy + half_box do
            if dy >= cover_top and dy < cover_top + cover_h and dy >= 0 and dy < bb_h then
                local dy_rel = dy - cy
                for dx = cx - half_box, cx + half_box do
                    if dx >= cover_left and dx < cover_right and dx >= 0 and dx < bb_w then
                        local dx_rel = dx - cx
                        -- inverse of +45 deg rotation ("\" band: top border -> right border)
                        local sx = math.floor(tw_half + (dx_rel + dy_rel) * C)
                        local sy = math.floor(th_half + (dy_rel - dx_rel) * C)
                        if sx >= 0 and sx < tw and sy >= 0 and sy < th then
                            bb:setPixel(dx, dy, tmp:getPixel(sx, sy))
                        end
                    end
                end
            end
        end

        tmp:free()
    end


    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then return nil end
        for i = 1, 128 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then break end
            if upname == name then return value end
        end
    end


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

        -- Cached star.empty icon for the favorite badge.
        local IconWidget   = require("ui/widget/iconwidget")
        local fav_mark     = nil
        local fav_mark_size = 0

        local function get_fav_mark(size)
            if fav_mark and fav_mark_size == size then return fav_mark end
            if fav_mark and fav_mark.free then fav_mark:free() end
            fav_mark = IconWidget:new{
                icon   = "star.empty",
                width  = size,
                height = size,
                alpha  = true,
            }
            fav_mark_size = size
            return fav_mark
        end

        function MosaicMenuItem:paintTo(bb, x, y)
            -- Clear the full cell to white before painting so that portrait
            -- covers (which are narrower than the cell) don't leave ghost pixels
            -- from a previously painted full-width placeholder in the margins.
            if self.width and self.height then
                bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
            end

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

            -- 3. Favorite star → top-left inside a circle
            local show_fav_badge = _plugin
                and _plugin.config
                and type(_plugin.config.browser_cover_badges) == "table"
                and _plugin.config.browser_cover_badges.show_favorite_badge == true
            if show_fav_badge
                and self.filepath
                and self.menu.name ~= "collections"
                and ReadCollection:isFileInCollections(self.filepath, true)
            then
                local eff_corner = math.max(corner_mark_size, math.floor((target.dimen.w or 0) * 0.14))
                local r      = math.floor(eff_corner / 2)
                local margin = math.floor(eff_corner * 0.3)
                local cx, cy
                if BD.mirroredUILayout() then
                    local cover_right = x + self.width
                        - math.ceil((self.width - target.dimen.w) / 2)
                    cx = cover_right - r - margin
                else
                    local cover_left = x + math.floor((self.width - target.dimen.w) / 2)
                    cx = cover_left + r + margin
                end
                cy = target.dimen.y + r + margin
                -- Border ring then fill (same two-call pattern as series badge)
                paintCircle(bb, cx, cy, r + 2, Blitbuffer.COLOR_BLACK)
                paintCircle(bb, cx, cy, r,     Blitbuffer.COLOR_LIGHT_GRAY)
                -- star.empty outline inverts correctly in night mode.
                -- math.ceil gives symmetric placement for both even and odd sizes.
                local mark = get_fav_mark(eff_corner)
                mark:paintTo(bb,
                    cx - math.ceil(eff_corner / 2),
                    cy - math.ceil(eff_corner / 2)
                )
            end

            -- 4. Dog-ear marks suppressed

            -- 5. KOReader's bottom progress bar (show_progress_in_mosaic)
            -- Gated on our own config so it defaults off and is immune to
            -- BookInfoManager DB timing issues. Users can re-enable via settings.
            local show_native = _plugin
                and _plugin.config
                and type(_plugin.config.browser_cover_badges) == "table"
                and _plugin.config.browser_cover_badges.show_native_progress_bar == true
            if self.show_progress_bar and show_native then
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

            -- 6. Zen UI: status/progress badge at top-right
            local show_badge = _plugin
                and _plugin.config
                and type(_plugin.config.browser_cover_badges) == "table"
                and _plugin.config.browser_cover_badges.show_mosaic_progress == true

            if show_badge and self.filepath then
                local do_check = (self.status == "complete")
                local do_pause = (self.status == "abandoned")
                local do_pct   = not do_check and not do_pause and self.percent_finished ~= nil

                if do_check or do_pause or do_pct then
                    local eff_size = math.max(corner_mark_size, math.floor((target.dimen.w or 0) * 0.14))
                    local bw = math.floor(eff_size * 1.2)
                    local bh = math.floor(eff_size * 1.1)

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
                        local font_sz = math.max(7, math.floor(eff_size * 0.40))
                        local tw = TextWidget:new{
                            text    = "\u{F0150}",  -- nf-md-clock_outline
                            face    = Font:getFace("cfont", font_sz),
                            fgcolor = Blitbuffer.COLOR_BLACK,
                            padding = 0,
                        }
                        local tw_sz = tw:getSize()
                        tw:paintTo(bb,
                            bdg_x + math.floor((bw     - tw_sz.w) / 2),
                            bdg_y + math.floor((rect_h - tw_sz.h) / 2)
                        )
                        if tw.free then tw:free() end
                    else
                        local pct     = math.floor(100 * self.percent_finished)
                        local pct_str = pct .. "%"
                        local font_sz = math.max(7, math.floor(eff_size * 0.24))
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

            -- 7. Description indicator (unchanged)
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

            -- 8. "New" corner ribbon for never-opened books
            local show_new_banner = _plugin
                and _plugin.config
                and type(_plugin.config.browser_cover_badges) == "table"
                and _plugin.config.browser_cover_badges.show_new_banner == true
            if show_new_banner and self.filepath then
                local is_new = self.percent_finished == nil
                    and self.status ~= "complete"
                    and self.status ~= "abandoned"
                if is_new then
                    local eff_size   = math.max(corner_mark_size, math.floor((target.dimen.w or 0) * 0.14))
                    local span       = math.floor(eff_size * 2.5)
                    local band_thick = math.floor(span * 0.35)
                    -- Font tied to cover size, not band thickness, so it stays small regardless of ribbon scale
                    local font_sz    = math.max(6, math.floor(eff_size * 0.25))
                    local cover_left = x + math.floor((self.width - target.dimen.w) / 2)
                    paintCornerBanner(bb,
                        cover_left, cover_left + target.dimen.w,
                        target.dimen.y, target.dimen.h,
                        span, band_thick, _("New"), font_sz,
                        Blitbuffer.COLOR_LIGHT_GRAY, Blitbuffer.COLOR_BLACK)
                    -- Repaint cover border over banner so it isn't obscured
                    if border > 0 then
                        local bclr = target.bordercolor or Blitbuffer.COLOR_BLACK
                        bb:paintRect(cover_left, target.dimen.y, target.dimen.w, border, bclr)
                        bb:paintRect(cover_left + target.dimen.w - border, target.dimen.y, border, target.dimen.h, bclr)
                    end
                end
            end
        end
    end


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

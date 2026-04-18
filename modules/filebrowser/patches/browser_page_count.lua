--[[
    browser_page_count.lua
    ─────────────────────────────────────────────────────────────────────────────
    Paints a small page-count badge for books in the file browser.

    Mosaic mode:  dark pill badge at the bottom-left corner of each book cover.
    List mode:    extra "Np" line below the tags row in the right column
                  (rendered by browser_list_item_layout.lua which reads the same
                  config flag, since it owns the list widget tree).

    Controlled by:  config.browser_page_count.show_page_count  (bool)
    Default:        false  (opt-in)

    Page count sources (first non-nil wins):
      1. BookList.getBookInfo  — sidecar-based; accurate for any opened book
      2. BookInfoManager.getBookInfo.pages — SQLite DB; accurate for PDF/CBZ;
         nil for epub/fb2 (CREngine can't count pages without a full render)

    Requires CoverBrowser plugin (bookinfomanager); silently inert without it.
    Wraps MosaicMenuItem.paintTo *after* browser_cover_badges has already patched
    it, so the page badge is painted on top of all other badge layers.

    Badge is drawn directly to the blitbuffer (no FrameContainer widget) to avoid
    bordersize = 0 rendering edge-cases present in some KOReader builds.
]]

local function apply_browser_page_count()
    -- Guard: CoverBrowser must be present.
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim or not BookInfoManager then return end

    -- Resolve pgettext once at apply time so paintTo doesn't depend on the
    -- C_ global being present (some KOReader builds don't expose it globally).
    local _C_
    do
        local _cg = rawget(_G, "C_")
        if type(_cg) == "function" then
            _C_ = _cg
        else
            local ok_gt, gt = pcall(require, "gettext")
            if ok_gt and gt and type(gt.pgettext) == "function" then
                _C_ = function(ctx, msgid) return gt.pgettext(ctx, msgid) end
            else
                _C_ = function(_, msgid) return msgid end
            end
        end
    end

    -- Capture plugin reference while __ZEN_UI_PLUGIN is still set (run_feature
    -- sets it only during pcall of this function).
    -- Also fall back to the global at paint time so toggling the setting without
    -- a restart is reflected immediately (same pattern as browser_cover_rounded_corners).
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local p = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        return p
            and type(p.config) == "table"
            and type(p.config.browser_page_count) == "table"
            and p.config.browser_page_count.show_page_count == true
    end

    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then return nil end
        for i = 1, 128 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then break end
            if upname == name then return value end
        end
    end

    -- Resolve page count: try BookList first (sidecar, any opened book), then
    -- BookInfoManager DB (indexed PDFs / CBZ, even if never opened).
    local function get_pages(filepath)
        -- BookList sidecar — fastest path for any previously opened book.
        local ok_bl, BookList = pcall(require, "ui/widget/booklist")
        if ok_bl and BookList then
            local bi = BookList.getBookInfo(filepath)
            if bi and bi.pages and bi.pages > 0 then
                return bi.pages
            end
        end
        -- SQLite DB fallback (accurate for PDF/CBZ; nil for epub/fb2 unread).
        local bookinfo = BookInfoManager:getBookInfo(filepath, false)
        return bookinfo and bookinfo.pages and bookinfo.pages > 0 and bookinfo.pages or nil
    end

    -- ── Pill drawing helper ────────────────────────────────────────────────────
    -- Draws a horizontal capsule shape row-by-row using paintRect.
    -- bx, by: top-left corner;  bw, bh: total bounding box;  color: fill color.
    local function paintPill(bb, bx, by, bw, bh, color)
        local r = bh / 2
        for row = 0, bh - 1 do
            local dy = math.abs(row + 0.5 - r)
            local dx = math.sqrt(math.max(0, r * r - dy * dy))
            local x0 = math.ceil(bx + r - dx)
            local x1 = math.floor(bx + bw - r + dx)
            local w  = x1 - x0
            if w > 0 then bb:paintRect(x0, by + row, w, 1, color) end
        end
    end

    local function patchMosaicMenu()
        local MosaicMenu     = require("mosaicmenu")
        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end

        -- Guard against double-patching (e.g. if FileManager.setupLayout is
        -- called more than once or another plugin also wraps it).
        if MosaicMenuItem._zen_page_count_patched then return end
        MosaicMenuItem._zen_page_count_patched = true

        local Blitbuffer = require("ffi/blitbuffer")
        local Font       = require("ui/font")
        local Screen     = require("device").screen
        local TextWidget = require("ui/widget/textwidget")

        -- By the time this runs, browser_cover_badges (and rounded_corners) have
        -- already replaced MosaicMenuItem.paintTo.  We wrap the current version.
        local orig_paintTo = MosaicMenuItem.paintTo

        -- Walk the orig_paintTo wrapper chain to find the `uv` accessor function.
        -- It lives inside browser_cover_badges' closure, but rounded_corners (and
        -- any other wrapper) sits on top of it, so a flat get_upvalue won't find
        -- it — we must traverse each `orig_paintTo` link until we reach it.
        local function find_uv_fn(fn, depth)
            depth = depth or 0
            if depth > 8 or type(fn) ~= "function" then return nil end
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
        local _uv_fn = find_uv_fn(orig_paintTo)

        function MosaicMenuItem:paintTo(bb, x, y)
            -- 1. Paint cover + all badge layers from previous patches.
            orig_paintTo(self, bb, x, y)

            -- 2. Skip if feature is off or item is not a regular book file.
            if not is_enabled() then return end
            if self.is_directory or self.file_deleted then return end
            if not self.filepath then return end

            -- 3. Resolve page count (sidecar → DB → skip).
            local pages = get_pages(self.filepath)
            if not pages then return end

            -- 4. Locate the cover FrameContainer in the widget tree.
            --    self[1]       = _underline_container
            --    self[1][1]    = OverlapGroup (cover + shortcut icon)
            --    self[1][1][1] = cover FrameContainer  ← target
            local target = self[1] and self[1][1] and self[1][1][1]
            if not (target and target.dimen and target.dimen.h and target.dimen.h > 0) then
                return
            end

            -- 5. Compute badge position using the paintTo x,y argument
            --    (same approach as browser_cover_badges / inspiration patch).
            --    cover_left = left edge of the cover rect within the cell.
            --    cover_bottom = bottom edge of the cover rect.
            -- Read corner_mark_size fresh each paint so it tracks layout changes.
            local corner_mark_size = (_uv_fn and _uv_fn("corner_mark_size"))
                or Screen:scaleBySize(20)
            local cover_left   = x + math.floor((self.width - target.dimen.w) / 2)
            local cover_bottom = y + self.height
                - math.floor((self.height - target.dimen.h) / 2)

            -- 6. Measure text — font, height, padding all scale with corner_mark_size
            --    matching the cover badge proportions exactly.
            local font_size = math.max(7, math.floor(corner_mark_size * 0.24))
            local page_str  = tostring(pages) .. " " .. _C_("page_count", "p.")
            local tw = TextWidget:new{
                text    = page_str,
                face    = Font:getFace("cfont", font_size),
                bold    = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
            }
            local tw_sz  = tw:getSize()
            -- Height fixed by corner_mark_size (same scale as cover badge bh).
            local bh     = math.floor(corner_mark_size * 0.95)
            -- Horizontal padding proportional to corner_mark_size (≈ bw * 0.12).
            local h_pad  = math.floor(corner_mark_size * 0.12)
            local bw     = tw_sz.w + 2 * h_pad
            local margin = math.floor(corner_mark_size * 0.3)
            local bx     = cover_left + margin
            local by     = cover_bottom - bh - margin

            -- 7. Paint pill: 2-px border offset (matches cover badge pattern).
            paintPill(bb, bx - 2, by - 2, bw + 4, bh + 4, Blitbuffer.COLOR_BLACK)
            paintPill(bb, bx, by, bw, bh, Blitbuffer.COLOR_LIGHT_GRAY)

            -- 8. Paint text centred inside the pill.
            tw:paintTo(bb,
                bx + math.floor((bw - tw_sz.w) / 2),
                by + math.floor((bh - tw_sz.h) / 2)
            )
            if tw.free then tw:free() end
        end
    end

    -- ── Hook FileManager:setupLayout (same pattern as browser_cover_badges) ──
    local FileManager      = require("apps/filemanager/filemanager")
    local orig_setupLayout = FileManager.setupLayout
    local patched          = false

    FileManager.setupLayout = function(self)
        orig_setupLayout(self)
        if not patched and self.coverbrowser then
            patchMosaicMenu()
            patched = true
        end
    end
end

return apply_browser_page_count

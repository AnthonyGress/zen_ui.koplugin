--[[
    browser_series_badge.lua
    Mosaic: "#N" pill badge bottom-right of cover.
    Controlled by config.browser_series_badge.show_series_badge. Requires CoverBrowser.
    Badge drawn directly to blitbuffer; wraps paintTo after browser_page_count.
]]

local function apply_browser_series_badge()
    -- Guard: CoverBrowser must be present.
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim or not BookInfoManager then return end

    -- Capture plugin reference while __ZEN_UI_PLUGIN is still set.
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local p = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        return p
            and type(p.config) == "table"
            and type(p.config.browser_series_badge) == "table"
            and p.config.browser_series_badge.show_series_badge == true
    end

    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then return nil end
        for i = 1, 128 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then break end
            if upname == name then return value end
        end
    end

    -- Resolve series index from BookInfoManager DB.
    local function get_series_index(filepath)
        local bookinfo = BookInfoManager:getBookInfo(filepath, false)
        if not bookinfo then return nil end
        local idx = bookinfo.series_index
        if idx == nil then return nil end
        -- series_index may be a number or a string like "1" or "1.5"
        local n = tonumber(idx)
        if not n or n <= 0 then return nil end
        return n
    end

    -- ── Circle drawing helper ──────────────────────────────────────────────────
    -- Draws a filled circle row-by-row using scanline fill.
    -- cx, cy: centre;  r: radius;  color: fill color.
    local function paintCircle(bb, cx, cy, r, color)
        for row = -r, r do
            local half_w = math.floor(math.sqrt(math.max(0, r * r - row * row)))
            if half_w > 0 then
                bb:paintRectRGB32(cx - half_w, cy + row, 2 * half_w, 1, color)
            end
        end
    end

    local function patchMosaicMenu()
        local MosaicMenu     = require("mosaicmenu")
        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end

        if MosaicMenuItem._zen_series_badge_patched then return end
        MosaicMenuItem._zen_series_badge_patched = true

        local Blitbuffer = require("ffi/blitbuffer")
        local Font       = require("ui/font")
        local Screen     = require("device").screen
        local TextWidget = require("ui/widget/textwidget")
        local utils      = require("common/utils")

        -- Walk the orig_paintTo wrapper chain to find the `uv` accessor function
        -- (lives inside browser_cover_badges' closure, potentially many layers deep).
        local function find_uv_fn(fn, depth)
            depth = depth or 0
            if depth > 10 or type(fn) ~= "function" then return nil end
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

        local _cached_badge_scale    = 1.0
        local _cached_badge_size_key = false
        local function get_badge_scale()
            local cur = _plugin and type(_plugin.config) == "table"
                and type(_plugin.config.browser_cover_badges) == "table"
                and _plugin.config.browser_cover_badges.badge_size or false
            if cur ~= _cached_badge_size_key then
                _cached_badge_size_key = cur
                _cached_badge_scale    = utils.getBadgeScale(_plugin and _plugin.config)
            end
            return _cached_badge_scale
        end
        local orig_paintTo = MosaicMenuItem.paintTo
        local _uv_fn = find_uv_fn(orig_paintTo)

        function MosaicMenuItem:paintTo(bb, x, y)
            -- 1. Paint cover + all badge layers from previous patches.
            orig_paintTo(self, bb, x, y)

            -- 2. Skip if feature is off or item is not a regular book file.
            if not is_enabled() then return end
            if self.is_directory or self.file_deleted then return end
            if not self.filepath then return end

            -- 3. Resolve series index (DB → skip if none or not in series).
            local series_idx = get_series_index(self.filepath)
            if not series_idx then return end

            -- 4. Locate the cover FrameContainer in the widget tree.
            --    self[1]       = _underline_container
            --    self[1][1]    = OverlapGroup (cover + shortcut icon)
            --    self[1][1][1] = cover FrameContainer  ← target
            local target = self[1] and self[1][1] and self[1][1][1]
            if not (target and target.dimen and target.dimen.h and target.dimen.h > 0) then
                return
            end

            -- 5. Compute badge dimensions and position.
            --    Mirror of browser_page_count: that badge sits at bottom-left,
            --    this one sits at bottom-right of the same cover frame.
            local corner_mark_size = (_uv_fn and _uv_fn("corner_mark_size"))
                or Screen:scaleBySize(20)
            local eff_size = math.floor(math.max(corner_mark_size, math.floor((target.dimen.w or 0) * 0.14))
                * get_badge_scale())
            local cover_left   = x + math.floor((self.width - target.dimen.w) / 2)
            local cover_right  = cover_left + target.dimen.w
            -- Use absolute coords so cover_bottom stays correct when a title strip
            -- below the cover inflates self.height beyond the actual image area.
            local cover_bottom = target.dimen.y + target.dimen.h

            -- 6. Format series index: integer → "#N", float → "#N.N"
            local idx_str
            if series_idx == math.floor(series_idx) then
                idx_str = "#" .. tostring(math.floor(series_idx))
            else
                idx_str = "#" .. string.format("%.1f", series_idx)
            end

            -- Radius matches favorites badge: eff_size / 2.
            local r     = math.floor(eff_size / 2)
            local inset = utils.getBadgeInset(r)
            local cx = cover_right  - r - inset
            local cy = cover_bottom - r - inset

            -- Usable text width inside the circle (conservative inner chord).
            local inner_w  = math.floor(r * 1.30)
            local font_size = math.max(7, math.floor(eff_size * 0.26))

            local tw = rawget(self, "_zen_series_tw")
            local tw_fs = rawget(self, "_zen_series_fs")
            local tw_idx = rawget(self, "_zen_series_idx")

            local _sc = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            local _bcc = _sc and type(_sc.config) == "table"
                and type(_sc.config.browser_cover_badges) == "table"
                and _sc.config.browser_cover_badges.badge_color
            local badge_is_dark = _bcc == nil or (type(_bcc) == "table" and _bcc[1] == 0 and _bcc[2] == 0 and _bcc[3] == 0)
            local badge_fg = badge_is_dark and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK

            if not tw or tw_fs ~= font_size or tw_idx ~= series_idx or rawget(self, "_zen_series_dark") ~= badge_is_dark then
                if tw and tw.free then tw:free() end

                local function make_tw(label, sz)
                    return TextWidget:new{
                        text    = label,
                        face    = Font:getFace("cfont", sz),
                        bold    = true,
                        fgcolor = badge_fg,
                        padding = 0,
                    }
                end

                -- Shrink font until label fits within inner_w (down to size 7).
                local function shrink_to_fit(label)
                    local sz = font_size
                    while sz > 7 do
                        local mtw = make_tw(label, sz)
                        if mtw:getSize().w <= inner_w then return mtw end
                        if mtw.free then mtw:free() end
                        sz = sz - 1
                    end
                    return make_tw(label, 7)
                end

                -- Single-digit whole numbers (#1-#9) always keep the "#".
                local is_single_digit = (series_idx == math.floor(series_idx) and series_idx >= 1 and series_idx <= 9)

                tw = make_tw(idx_str, font_size)
                if tw:getSize().w > inner_w then
                    if tw.free then tw:free() end
                    -- Only drop "#" for labels that won't fit and are not single-digit whole numbers.
                    local no_hash = (not is_single_digit and idx_str:sub(1, 1) == "#") and idx_str:sub(2) or idx_str
                    if no_hash ~= idx_str then
                        local tw2 = make_tw(no_hash, font_size)
                        if tw2:getSize().w <= inner_w then
                            tw = tw2
                        else
                            if tw2.free then tw2:free() end
                            tw = shrink_to_fit(no_hash)
                        end
                    else
                        tw = shrink_to_fit(idx_str)
                    end
                end

                rawset(self, "_zen_series_tw", tw)
                rawset(self, "_zen_series_fs", font_size)
                rawset(self, "_zen_series_idx", series_idx)
                rawset(self, "_zen_series_dark", badge_is_dark)
            end

            local tw_sz = tw:getSize()

            -- 7. Paint circle: 2-px border ring then fill.
            paintCircle(bb, cx, cy, r + 2, badge_fg)
            paintCircle(bb, cx, cy, r, utils.getBadgeColor(_plugin and _plugin.config))

            -- 8. Paint text centred inside the circle.
            tw:paintTo(bb,
                cx - math.floor(tw_sz.w / 2),
                cy - math.floor(tw_sz.h / 2)
            )
        end
    end

    -- ── Hook FileManager:setupLayout (same pattern as browser_page_count) ─────
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

return apply_browser_series_badge

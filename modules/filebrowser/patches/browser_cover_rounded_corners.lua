--[[
    browser_cover_rounded_corners.lua
    ─────────────────────────────────────────────────────────────────────────────
    Mosaic mode:
      • Paints white quarter-circle masks at all four corners of each cover
        frame, producing the appearance of rounded corners on book and folder
        covers.

    Controlled by the "Rounded corners on mosaic covers" Zen UI setting.
    Always applied at boot; the per-paint guard is a live config read so the
    effect can be toggled at runtime with a full repaint (no restart needed).
]]

local function apply_browser_cover_rounded_corners()
    local Blitbuffer = require("ffi/blitbuffer")
    local Screen     = require("device").screen

    -- Capture plugin reference at apply-time (same pattern as browser_cover_badges).
    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    -- ── Quarter-circle corner masking ─────────────────────────────────────────
    -- Paints white pixels outside the arc in each r×r corner zone, simulating
    -- rounded corners on the blitbuffer bb.  tx/ty/tw/th are the absolute
    -- screen coordinates and dimensions of the cover frame.
    local function paintCornerMasks(bb, tx, ty, tw, th, r)
        local color = Blitbuffer.COLOR_WHITE
        for j = 0, r - 1 do
            -- Number of pixels to mask from each edge at this row/column offset.
            -- Derived from the circle equation: pixel (c, j) is outside the arc
            -- whose centre is at (r, r) from the corner when c < r−√(r²−(r−j)²).
            local inner = math.sqrt(r * r - (r - j) * (r - j))
            local cut   = math.ceil(r - inner)
            if cut > 0 then
                -- top edge
                bb:paintRect(tx,            ty + j,          cut, 1, color)
                bb:paintRect(tx + tw - cut, ty + j,          cut, 1, color)
                -- bottom edge
                bb:paintRect(tx,            ty + th - 1 - j, cut, 1, color)
                bb:paintRect(tx + tw - cut, ty + th - 1 - j, cut, 1, color)
            end
        end
    end

    -- ── Circular arc border redraw ────────────────────────────────────────────
    -- After masking, the original rectangular border pixels in each corner are
    -- gone.  This redraws them as a circular arc so the border looks complete.
    -- Uses pixel-centre distances for a clean anti-alias-free arc.
    local function paintCornerBorderArcs(bb, tx, ty, tw, th, r, bsz, color)
        local r_outer = r
        local r_inner = r - bsz
        for j = 0, r - 1 do
            for c = 0, r - 1 do
                -- Distance from the arc centre (r, r) to the centre of pixel (c, j).
                local dx   = r - c - 0.5
                local dy   = r - j - 0.5
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist >= r_inner and dist <= r_outer then
                    bb:paintRect(tx + c,           ty + j,           1, 1, color)
                    bb:paintRect(tx + tw - 1 - c,  ty + j,           1, 1, color)
                    bb:paintRect(tx + c,           ty + th - 1 - j,  1, 1, color)
                    bb:paintRect(tx + tw - 1 - c,  ty + th - 1 - j,  1, 1, color)
                end
            end
        end
    end

    -- ── Mosaic patch ───────────────────────────────────────────────────────────
    local function patchMosaicMenu()
        local MosaicMenu = require("mosaicmenu")
        if not MosaicMenu then return end

        local function get_upvalue(fn, name)
            if type(fn) ~= "function" then return nil end
            for i = 1, 128 do
                local upname, value = debug.getupvalue(fn, i)
                if not upname then break end
                if upname == name then return value end
            end
        end

        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end

        -- Guard against double-patching (e.g. on FileManager re-layout).
        if MosaicMenuItem._zen_rounded_corners_patched then return end
        MosaicMenuItem._zen_rounded_corners_patched = true

        local orig_paintTo = MosaicMenuItem.paintTo
        if not orig_paintTo then return end

        local corner_radius = Screen:scaleBySize(8)

        -- Locate the cover FrameContainer for both book and folder items.
        --
        -- Book / standard folder (coverbrowser):
        --   self[1]       = _underline_container (outer FrameContainer)
        --   self[1][1]    = OverlapGroup (cover + shortcut icon)
        --   self[1][1][1] = cover FrameContainer  ← target
        --
        -- Folder cover (browser_folder_cover.lua):
        --   self[1]             = _underline_container
        --   self[1][1]          = CenterContainer  (widget from _setFolderCover)
        --   self[1][1][1]       = VerticalGroup
        --   self[1][1][1][6]    = OverlapGroup
        --   self[1][1][1][6][1] = image_widget FrameContainer  ← target
        --
        -- Discriminator: FrameContainers always carry a `bordersize` field;
        -- VerticalGroups do not.
        local function find_cover_frame(item)
            local t = item[1] and item[1][1] and item[1][1][1]
            if not t then return nil end
            -- Standard path: FrameContainer (book cover or stock folder icon)
            if t.bordersize ~= nil then
                return t
            end
            -- browser_folder_cover path: VerticalGroup → OverlapGroup → image_widget
            local img = t[6] and t[6][1]
            if img and img.dimen then
                return img
            end
            return nil
        end

        function MosaicMenuItem:paintTo(bb, x, y)
            -- 1. Full base painting (cover image + any previously applied overlays
            --    such as the badge patch).
            orig_paintTo(self, bb, x, y)

            -- 2. Runtime feature guard – check live config so toggling requires
            --    only a repaint, not a restart.
            local plug = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
            if not (plug
                and type(plug.config) == "table"
                and type(plug.config.features) == "table"
                and plug.config.features.browser_cover_rounded_corners == true)
            then
                return
            end

            -- 3. Locate the cover FrameContainer (book or folder).
            local target = find_cover_frame(self)
            if not (target and target.dimen
                and target.dimen.x and target.dimen.y
                and target.dimen.w and target.dimen.h
                and target.dimen.w > 0 and target.dimen.h > 0)
            then
                return
            end

            -- 4. Paint the four rounded corner masks, then redraw the border arc
            --    so the border looks unbroken around the rounded corners.
            local tx, ty = target.dimen.x, target.dimen.y
            local tw, th = target.dimen.w, target.dimen.h
            local bsz    = math.max(1, target.bordersize or 0)
            paintCornerMasks(bb, tx, ty, tw, th, corner_radius)
            paintCornerBorderArcs(bb, tx, ty, tw, th, corner_radius, bsz, Blitbuffer.COLOR_BLACK)
        end
    end

    -- ── Hook FileManager:setupLayout (same pattern as browser_cover_badges) ───
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

return apply_browser_cover_rounded_corners

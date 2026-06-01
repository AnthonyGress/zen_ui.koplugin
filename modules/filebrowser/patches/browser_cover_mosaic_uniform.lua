--[[
    browser_cover_mosaic_uniform.lua
    Enforces portrait aspect ratio on mosaic covers to prevent landscape
    covers from rendering wider than others. Ratio configurable via
    uniform_cover_ratio setting (e.g., "2:3" or "3:4").
]]

local function apply_browser_cover_mosaic_uniform()
    local Size = require("ui/size")
    local OverlapGroup = require("ui/widget/overlapgroup")

    local MosaicMenu = require("mosaicmenu")

    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then return nil end
        for i = 1, 128 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then break end
            if upname == name then return value, i end
        end
    end

    local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then
        return
    end

    if MosaicMenuItem._zen_mosaic_uniform_patched then
        return
    end
    MosaicMenuItem._zen_mosaic_uniform_patched = true

    -- 辅助函数：直接从 G_reader_settings 获取比例，不依赖 _plugin
    local function get_aspect_ratio()
        local ratio_str = G_reader_settings:readSetting("uniform_cover_ratio") or "2:3"
        local num, den = ratio_str:match("(%d+):(%d+)")
        local ratio = (tonumber(num) or 2) / (tonumber(den) or 3)
        return ratio
    end

    -- Find the ImageWidget upvalue inside MosaicMenuItem.update.
    local local_ImageWidget, upvalue_idx
    for i = 1, 128 do
        local name, value = debug.getupvalue(MosaicMenuItem.update, i)
        if not name then break end
        if name == "ImageWidget" then
            local_ImageWidget = value
            upvalue_idx = i
            break
        end
    end

    if not local_ImageWidget or not upvalue_idx then
        return
    end

    -- Capture cell inner dimensions per-init so the subclass can reference them.
    local UNDERLINE_RESERVE = 6
    local max_img_w, max_img_h
    local orig_init = MosaicMenuItem.init
    function MosaicMenuItem:init()
        if self.width and self.height then
            local border = Size.border.thin
            max_img_w = self.width  - 2 * border
            max_img_h = self.height - 2 * border - UNDERLINE_RESERVE
        end
        if orig_init then orig_init(self) end

        local uc = self._underline_container
        if uc and not uc._zen_underline_sized then
            uc._zen_underline_sized = true
            uc.paintTo = function(this, bb, x, y)
                this.dimen.x = x
                this.dimen.y = y
                OverlapGroup.paintTo(this, bb, x, y)
                if this.color == require("ffi/blitbuffer").COLOR_WHITE then return end
                local uw = this.dimen.w
                local aspect_ratio = get_aspect_ratio()
                if max_img_w and max_img_h and max_img_h > 0 then
                    if max_img_w / max_img_h > aspect_ratio then
                        uw = math.floor(max_img_h * aspect_ratio)
                    else
                        uw = max_img_w
                    end
                end
                local x_off = math.floor((this.dimen.w - uw) / 2)
                bb:paintRect(x + x_off, y + this.dimen.h - this.linesize, uw, this.linesize, this.color)
            end
        end
    end

    -- StretchingImageWidget
    local StretchingImageWidget = local_ImageWidget:extend({})

    StretchingImageWidget.init = function(self)
        if local_ImageWidget.init then
            local_ImageWidget.init(self)
        end
        if not max_img_w or not max_img_h then
            return
        end

        self.scale_factor = nil

        local aspect_ratio = get_aspect_ratio()

        if max_img_w / max_img_h > aspect_ratio then
            self.height = max_img_h
            self.width  = math.floor(max_img_h * aspect_ratio)
        else
            self.width  = max_img_w
            self.height = math.floor(max_img_w / aspect_ratio)
        end
    end

    debug.setupvalue(MosaicMenuItem.update, upvalue_idx, StretchingImageWidget)
end

return apply_browser_cover_mosaic_uniform

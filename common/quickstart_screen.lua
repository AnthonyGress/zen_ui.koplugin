-- Full-screen onboarding / "what's new" slideshow widget.
-- Follows zen_toc_widget.lua conventions: InputContainer, paintTo, registerTouchZones.
--
-- Usage:
--   local QuickstartScreen = require("common/quickstart_screen")
--   UIManager:show(QuickstartScreen:new{
--       pages    = require("common/quickstart_pages").build_install_pages(ctx),
--       on_close = function() ... end,
--   })
--
-- Interactive pages support a `choices` array for user selection:
--   { title, description, choice_type = "radio"|"checkbox",
--     choices = {{ id, text, checked }...}, on_apply = function(sel_set) end }

local InputContainer = require("ui/widget/container/inputcontainer")
local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local TextBoxWidget  = require("ui/widget/textboxwidget")
local TextWidget     = require("ui/widget/textwidget")
local UIManager      = require("ui/uimanager")
local ZenButton      = require("common/zen_button")
local Screen         = Device.screen
local _              = require("gettext")

local ok_iw, ImageWidget = pcall(require, "ui/widget/imagewidget")
if not ok_iw then ImageWidget = nil end

local ok_ico, IconWidget = pcall(require, "ui/widget/iconwidget")
if not ok_ico then IconWidget = nil end

local QuickstartScreen = InputContainer:extend{
    pages    = nil,
    on_close = nil,
}

function QuickstartScreen:init()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }

    self.pages     = self.pages or {}
    self._page_idx = 1
    self._total    = #self.pages

    local PAD     = Screen:scaleBySize(20)
    local TITLE_H = Screen:scaleBySize(60)
    local SEP_H   = 1
    local DOT_H   = Screen:scaleBySize(36)
    local NAV_H   = Screen:scaleBySize(64)
    -- Reserve 40% of screen height for description + dots + nav; image fills at most 60%.
    local BOTTOM_H = math.floor(sh * 0.40)
    local IMG_H    = sh - TITLE_H - SEP_H - BOTTOM_H
    local DESC_H   = BOTTOM_H - DOT_H - NAV_H

    local DOT_R   = Screen:scaleBySize(5)
    local DOT_GAP = Screen:scaleBySize(14)
    local n       = math.max(1, self._total)
    local dot_total_w = n * (DOT_R * 2) + (n - 1) * DOT_GAP

    self._L = {
        sw = sw, sh = sh, pad = PAD,
        title_h     = TITLE_H,
        sep_h       = SEP_H,
        img_y       = TITLE_H + SEP_H,
        img_h       = IMG_H,
        desc_y      = TITLE_H + SEP_H + IMG_H,
        desc_h      = DESC_H,
        dot_y       = TITLE_H + SEP_H + IMG_H + DESC_H,
        dot_h       = DOT_H,
        nav_y       = sh - NAV_H,
        nav_h       = NAV_H,
        dot_r       = DOT_R,
        dot_gap     = DOT_GAP,
        dot_start_x = math.floor((sw - dot_total_w) / 2),
    }

    -- Initialize selections from page choice defaults
    self._selections  = {}
    self._choice_area = nil
    self._finale_btn  = nil
    for i, page in ipairs(self.pages) do
        if page.choices then
            local sel = {}
            for _, choice in ipairs(page.choices) do
                if choice.checked then
                    sel[choice.id] = true
                end
            end
            self._selections[i] = sel
        end
    end

    self:registerTouchZones({
        {
            id          = "qs_swipe",
            ges         = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler     = function(ges) return self:_onSwipe(ges) end,
        },
        {
            id          = "qs_tap",
            ges         = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler     = function(ges) return self:_onTap(ges) end,
        },
    })
end

-- Draw a radio button indicator (ring + optional filled centre).
function QuickstartScreen:_paintRadio(bb, cx, cy, r, filled)
    -- Outer filled disk in dark gray
    for dy = -r, r do
        local hw = math.floor(math.sqrt(r * r - dy * dy) + 0.5)
        if hw > 0 then
            bb:paintRect(cx - hw, cy + dy, hw * 2, 1, Blitbuffer.COLOR_DARK_GRAY)
        end
    end
    -- White interior (creates ring effect)
    local ir = math.max(0, r - 2)
    for dy = -ir, ir do
        local hw = math.floor(math.sqrt(ir * ir - dy * dy) + 0.5)
        if hw > 0 then
            bb:paintRect(cx - hw, cy + dy, hw * 2, 1, Blitbuffer.COLOR_WHITE)
        end
    end
    -- Black fill when selected
    if filled then
        local fr = math.max(1, r - 4)
        for dy = -fr, fr do
            local hw = math.floor(math.sqrt(fr * fr - dy * dy) + 0.5)
            if hw > 0 then
                bb:paintRect(cx - hw, cy + dy, hw * 2, 1, Blitbuffer.COLOR_BLACK)
            end
        end
    end
end

-- Draw a checkbox indicator (square border + optional filled centre).
function QuickstartScreen:_paintCheckbox(bb, bx, by, sz, filled)
    local col = Blitbuffer.COLOR_DARK_GRAY
    bb:paintRect(bx,          by,          sz, 2,  col)
    bb:paintRect(bx,          by + sz - 2, sz, 2,  col)
    bb:paintRect(bx,          by,          2,  sz, col)
    bb:paintRect(bx + sz - 2, by,          2,  sz, col)
    if filled then
        local p = 4
        bb:paintRect(bx + p, by + p, sz - p * 2, sz - p * 2, Blitbuffer.COLOR_BLACK)
    end
end

-- Render choices using the full image+desc band (no image on the page).
function QuickstartScreen:_paintChoicesFullBand(bb, x, y, page)
    local L   = self._L
    local sel = self._selections[self._page_idx] or {}
    local n   = #page.choices

    local band_top = y + L.img_y + L.pad
    local band_bot = y + L.dot_y - L.pad

    local choices_top
    if page.description and page.description ~= "" then
        -- Description as prompt at top of band
        local prompt_w  = L.sw - L.pad * 2
        local prompt_tb = TextBoxWidget:new{
            text      = page.description,
            face      = Font:getFace("cfont", 20),
            width     = prompt_w,
            alignment = "center",
        }
        local psz = prompt_tb:getSize()
        prompt_tb:paintTo(bb, x + math.floor((L.sw - prompt_w) / 2), band_top)
        prompt_tb:free()
        choices_top = band_top + psz.h + Screen:scaleBySize(12)
    else
        choices_top = band_top
    end

    local choices_avail = band_bot - choices_top
    local row_h = n > 0 and math.max(20, math.floor(choices_avail / n)) or 20

    self._choice_area = { y = choices_top, row_h = row_h, n = n }
    self:_paintChoiceRows(bb, x, choices_top, row_h, page, sel)
end

-- Render choices in the description band (page has an image above).
function QuickstartScreen:_paintChoicesDescBand(bb, x, y, page, desc_paint_y, dsz_h)
    local L   = self._L
    local sel = self._selections[self._page_idx] or {}
    local n   = #page.choices

    local choices_top  = desc_paint_y + dsz_h + Screen:scaleBySize(10)
    local choices_bot  = y + L.dot_y - L.pad
    local choices_avail = choices_bot - choices_top
    local row_h = n > 0 and math.max(20, math.floor(choices_avail / n)) or 20

    self._choice_area = { y = choices_top, row_h = row_h, n = n }
    self:_paintChoiceRows(bb, x, choices_top, row_h, page, sel)
end

function QuickstartScreen:_paintChoiceRows(bb, x, choices_top, row_h, page, sel)
    local L           = self._L
    local ind_sz      = Screen:scaleBySize(16)
    local ind_x       = x + L.pad * 3
    local text_x      = ind_x + ind_sz + Screen:scaleBySize(10)
    local img_avail_w = L.sw - L.pad * 4

    for i, choice in ipairs(page.choices) do
        local row_y = choices_top + (i - 1) * row_h

        -- Reserve image space at the bottom of the row; text+indicator go above
        local img_reserve_h = 0
        if (choice.image or choice.image_bb) and ImageWidget then
            img_reserve_h = math.min(math.floor(row_h * 0.72), Screen:scaleBySize(400))
        end
        local text_h = row_h - img_reserve_h
        local mid_y  = row_y + math.floor(text_h / 2)
        local is_sel = sel[choice.id] == true

        if page.choice_type == "radio" then
            local r = math.floor(ind_sz / 2)
            self:_paintRadio(bb, ind_x + r, mid_y, r, is_sel)
        else
            local box_top = mid_y - math.floor(ind_sz / 2)
            self:_paintCheckbox(bb, ind_x, box_top, ind_sz, is_sel)
        end

        local tw = TextWidget:new{
            text    = choice.text or "",
            face    = Font:getFace("cfont", 18),
            bold    = is_sel,
            padding = 0,
        }
        local twsz = tw:getSize()
        tw:paintTo(bb, text_x, mid_y - math.floor(twsz.h / 2))
        tw:free()

        -- Image below the indicator+text
        if (choice.image or choice.image_bb) and ImageWidget then
            pcall(function()
                local iw
                if choice.image_bb then
                    iw = ImageWidget:new{
                        image                 = choice.image_bb,
                        width                 = img_avail_w,
                        height                = img_reserve_h,
                        scale_factor          = 0,
                        image_disposable      = false,
                        original_in_nightmode = false,
                    }
                else
                    iw = ImageWidget:new{
                        file         = choice.image,
                        width        = img_avail_w,
                        height       = img_reserve_h,
                        scale_factor = 0,
                        alpha        = true,
                    }
                end
                local isz = iw:getSize()
                iw:paintTo(bb, x + math.floor((L.sw - isz.w) / 2), row_y + text_h)
                iw:free()
            end)
        end
    end
end

function QuickstartScreen:paintTo(bb, x, y)
    local L = self._L

    bb:paintRect(x, y, L.sw, L.sh, Blitbuffer.COLOR_WHITE)

    local page = self.pages[self._page_idx] or {}
    local has_icon  = page.icon  and IconWidget  ~= nil
    local has_image = (page.image or page.image_bb) and ImageWidget ~= nil
    local has_visual = has_icon or has_image

    -- -------------------------------------------------------------------------
    -- Title bar
    -- -------------------------------------------------------------------------
    local title_tw = TextWidget:new{
        text    = page.title or "",
        face    = Font:getFace("cfont", 24),
        bold    = true,
        padding = 0,
    }
    local tsz = title_tw:getSize()
    title_tw:paintTo(bb,
        x + math.floor((L.sw - tsz.w) / 2),
        y + math.floor((L.title_h - tsz.h) / 2))
    title_tw:free()

    bb:paintRect(x, y + L.title_h, L.sw, L.sep_h, Blitbuffer.COLOR_LIGHT_GRAY)

    -- -------------------------------------------------------------------------
    -- Interactive page without image: use full image+desc band for content
    -- -------------------------------------------------------------------------
    if page.choices and not has_visual then
        self:_paintChoicesFullBand(bb, x, y, page)
    else
        -- Static page or choice page with an illustrative image

        -- Image area
        if has_icon then
            pcall(function()
                local max_h  = L.img_h - Screen:scaleBySize(8)
                local icon_sz = math.min(L.sw - L.pad * 2, max_h)
                local ico = IconWidget:new{
                    icon   = page.icon,
                    width  = icon_sz,
                    height = icon_sz,
                }
                local isz = ico:getSize()
                ico:paintTo(bb,
                    x + math.floor((L.sw - isz.w) / 2),
                    y + L.img_y + math.floor((L.img_h - isz.h) / 2))
                ico:free()
            end)
        elseif has_image then
            pcall(function()
                local max_w = L.sw - L.pad * 2
                local max_h = L.img_h - Screen:scaleBySize(8)
                local iw
                if page.image_bb then
                    iw = ImageWidget:new{
                        image                 = page.image_bb,
                        width                 = max_w,
                        height                = max_h,
                        scale_factor          = 0,
                        image_disposable      = false,
                        original_in_nightmode = false,
                    }
                else
                    iw = ImageWidget:new{
                        file         = page.image,
                        width        = max_w,
                        height       = max_h,
                        scale_factor = 0,
                        alpha        = true,
                    }
                end
                local isz = iw:getSize()
                iw:paintTo(bb,
                    x + math.floor((L.sw - isz.w) / 2),
                    y + L.img_y + math.floor((L.img_h - isz.h) / 2))
                iw:free()
            end)
        end

        -- Description text
        local desc_w  = L.sw - L.pad * 2
        local desc_tb = TextBoxWidget:new{
            text      = page.description or "",
            face      = Font:getFace("cfont", 20),
            width     = desc_w,
            alignment = "center",
        }
        local dsz = desc_tb:getSize()
        local desc_paint_y
        if page.choices or page.finale then
            desc_paint_y = y + L.desc_y + L.pad
        else
            desc_paint_y = y + L.desc_y + math.floor((L.desc_h - dsz.h) / 2)
        end
        desc_tb:paintTo(bb, x + math.floor((L.sw - desc_w) / 2), desc_paint_y)
        desc_tb:free()

        if page.choices then
            self:_paintChoicesDescBand(bb, x, y, page, desc_paint_y, dsz.h)
        elseif page.finale then
            self:_paintFinaleButton(bb, x, y, desc_paint_y, dsz.h)
            self._choice_area = nil
        else
            self._choice_area = nil
        end
    end

    -- -------------------------------------------------------------------------
    -- Dot indicators
    -- -------------------------------------------------------------------------
    local dot_cy = y + L.dot_y + math.floor(L.dot_h / 2)
    for i = 1, self._total do
        local dcx = x + L.dot_start_x + (i - 1) * (L.dot_r * 2 + L.dot_gap) + L.dot_r
        local color = (i == self._page_idx)
            and Blitbuffer.COLOR_BLACK
            or  Blitbuffer.COLOR_LIGHT_GRAY
        for row = -L.dot_r, L.dot_r do
            local half = math.floor(math.sqrt(L.dot_r * L.dot_r - row * row) + 0.5)
            if half > 0 then
                bb:paintRect(dcx - half, dot_cy + row, half * 2, 1, color)
            end
        end
    end

    -- -------------------------------------------------------------------------
    -- Navigation row
    -- -------------------------------------------------------------------------
    local nav_top = y + L.nav_y
    bb:paintRect(x, nav_top, L.sw, 1, Blitbuffer.COLOR_LIGHT_GRAY)

    local nav_cy   = nav_top + math.floor(L.nav_h / 2)
    local icon_sz  = Screen:scaleBySize(24)
    local icon_gap = Screen:scaleBySize(6)

    if self._page_idx > 1 then
        local prev_tw = TextWidget:new{
            text    = _("Prev"),
            face    = Font:getFace("cfont", 20),
            fgcolor = Blitbuffer.COLOR_BLACK,
            padding = 0,
        }
        local psz = prev_tw:getSize()
        if IconWidget then
            pcall(function()
                local ico = IconWidget:new{
                    icon   = "chevron.left",
                    width  = icon_sz,
                    height = icon_sz,
                }
                ico:paintTo(bb, x + L.pad, nav_cy - math.floor(icon_sz / 2))
                ico:free()
            end)
        end
        prev_tw:paintTo(bb,
            x + L.pad + icon_sz + icon_gap,
            nav_cy - math.floor(psz.h / 2))
        prev_tw:free()
    end

    local is_last = (self._page_idx == self._total)
    if not (is_last and page.finale) then
        local next_lbl     = is_last and _("Get Started") or _("Next")
        local show_chevron = not is_last and IconWidget ~= nil
        local next_tw      = TextWidget:new{
            text    = next_lbl,
            face    = Font:getFace("cfont", 20),
            bold    = is_last,
            fgcolor = Blitbuffer.COLOR_BLACK,
            padding = 0,
        }
        local nsz     = next_tw:getSize()
        local total_w = nsz.w + (show_chevron and (icon_gap + icon_sz) or 0)
        next_tw:paintTo(bb,
            x + L.sw - L.pad - total_w,
            nav_cy - math.floor(nsz.h / 2))
        next_tw:free()
        if show_chevron then
            pcall(function()
                local ico = IconWidget:new{
                    icon   = "chevron.right",
                    width  = icon_sz,
                    height = icon_sz,
                }
                ico:paintTo(bb,
                    x + L.sw - L.pad - icon_sz,
                    nav_cy - math.floor(icon_sz / 2))
                ico:free()
            end)
        end
    end
end

function QuickstartScreen:_paintFinaleButton(bb, x, y, desc_paint_y, desc_h)
    local L     = self._L
    local btn_w = Screen:scaleBySize(240)
    local btn_h = Screen:scaleBySize(54)
    local PAD   = Screen:scaleBySize(12)

    local avail_top = desc_paint_y + desc_h + PAD
    local avail_bot = y + L.dot_y - PAD
    local btn_x     = x + math.floor((L.sw - btn_w) / 2)
    local btn_y     = avail_top + math.floor((avail_bot - avail_top - btn_h) / 2)

    self._finale_btn = ZenButton.paintFilled(
        bb, btn_x, btn_y, btn_w, btn_h, _("Get Started"), 22)
end

function QuickstartScreen:setPage(n)
    if n < 1 or n > self._total then return end
    self._page_idx    = n
    self._choice_area = nil
    self._finale_btn  = nil
    UIManager:setDirty(self, function()
        return "ui", self.dimen
    end)
end

-- Call on_apply for the current page if it has choices (forward navigation only).
function QuickstartScreen:_applyCurrentPage()
    local page = self.pages[self._page_idx] or {}
    if page.choices and type(page.on_apply) == "function" then
        local sel = self._selections[self._page_idx] or {}
        pcall(page.on_apply, sel)
    end
end

function QuickstartScreen:_nextPage()
    self:_applyCurrentPage()
    if self._page_idx >= self._total then
        self:onClose()
    else
        self:setPage(self._page_idx + 1)
    end
end

function QuickstartScreen:_prevPage()
    if self._page_idx > 1 then
        self:setPage(self._page_idx - 1)
    end
end

function QuickstartScreen:_onSwipe(ges)
    if ges.direction == "west" then
        self:_nextPage()
    elseif ges.direction == "east" then
        self:_prevPage()
    end
    return true
end

function QuickstartScreen:_onTap(ges)
    local p = ges.pos
    local L = self._L

    -- Navigation row
    if p.y >= L.nav_y then
        local page = self.pages[self._page_idx] or {}
        if p.x < math.floor(L.sw / 2) then
            self:_prevPage()
        elseif not page.finale then
            -- On finale pages the nav-row right side is blank; only the
            -- rendered Get Started button should fire the close callback.
            self:_nextPage()
        end
        return true
    end

    -- Finale button
    local fb = self._finale_btn
    if fb and p.x >= fb.x and p.x < fb.x + fb.w and p.y >= fb.y and p.y < fb.y + fb.h then
        self:_nextPage()
        return true
    end

    -- Dot row — jump to page
    if p.y >= L.dot_y and p.y < L.dot_y + L.dot_h then
        for i = 1, self._total do
            local dx = L.dot_start_x + (i - 1) * (L.dot_r * 2 + L.dot_gap)
            if p.x >= dx and p.x < dx + L.dot_r * 2 then
                self:setPage(i)
                return true
            end
        end
    end

    -- Choice rows
    local ca = self._choice_area
    if ca and p.y >= ca.y and p.y < ca.y + ca.n * ca.row_h then
        local idx = math.floor((p.y - ca.y) / ca.row_h) + 1
        if idx >= 1 and idx <= ca.n then
            local page = self.pages[self._page_idx] or {}
            if page.choices and page.choices[idx] then
                local choice = page.choices[idx]
                local sel    = self._selections[self._page_idx] or {}
                if page.choice_type == "radio" then
                    sel = { [choice.id] = true }
                else
                    if not (sel[choice.id] == true) and page.max_selections then
                        local count = 0
                        for _, v in pairs(sel) do if v == true then count = count + 1 end end
                        if count >= page.max_selections then return true end
                    end
                    sel[choice.id] = not (sel[choice.id] == true)
                end
                self._selections[self._page_idx] = sel
                UIManager:setDirty(self, function() return "ui", self.dimen end)
                return true
            end
        end
    end

    return true
end

function QuickstartScreen:onCloseWidget()
    -- Free any dynamically composed cover blitbuffers.
    for _, page in ipairs(self.pages or {}) do
        if page.image_bb then
            page.image_bb:free()
            page.image_bb = nil
        end
        for _, choice in ipairs(page.choices or {}) do
            if choice.image_bb then
                choice.image_bb:free()
                choice.image_bb = nil
            end
        end
    end
end

function QuickstartScreen:onShow()
    UIManager:setDirty(self, function()
        return "partial", self.dimen
    end)
end

function QuickstartScreen:onClose()
    UIManager:setDirty(nil, "full")
    UIManager:close(self)
    -- Block filebrowser taps for 1.5s so the close-gesture doesn't open a file.
    _G.__ZEN_QUICKSTART_JUST_CLOSED = true
    UIManager:scheduleIn(1.5, function() _G.__ZEN_QUICKSTART_JUST_CLOSED = nil end)
    -- Evict quickstart modules so Lua GC can free all closures and page data.
    package.loaded["common/quickstart_screen"] = nil
    package.loaded["common/quickstart_pages"]  = nil
    if self.on_close then
        self.on_close()
    end
end

return QuickstartScreen

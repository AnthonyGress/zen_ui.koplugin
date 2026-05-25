-- common/zen_screen.lua
-- Fullscreen update / splash screen.
--
-- Shows the Zen UI logo centered with an optional title at the top and an
-- optional action button at the bottom. Tap or swipe anywhere to dismiss.
--
-- Usage:
--   local ZenScreen = require("common/zen_screen")
--   UIManager:show(ZenScreen:new{
--       title    = "Zen UI updated to v1.2.3",  -- nil hides the title bar
--       button   = "Get Started",               -- nil -> default label; false -> no button
--       on_close = function() ... end,
--   })

local InputContainer = require("ui/widget/container/inputcontainer")
local Blitbuffer     = require("ffi/blitbuffer")
local Device         = require("device")
local Font           = require("ui/font")
local Geom           = require("ui/geometry")
local Input          = require("device/input")
local TextBoxWidget  = require("ui/widget/textboxwidget")
local TextWidget     = require("ui/widget/textwidget")
local UIManager      = require("ui/uimanager")
local ZenButton      = require("common/zen_button")
local Screen         = Device.screen
local _              = require("gettext")

local logger           = require("logger")
local ok_iw, ImageWidget = pcall(require, "ui/widget/imagewidget")
if not ok_iw then ImageWidget = nil end

local _plugin_root = require("common/plugin_root") or ""

local ZenScreen = InputContainer:extend{
    title             = nil,   -- string shown in top bar; nil hides the title bar entirely
    subtitle          = nil,   -- string rendered above the icon (e.g. "Updated to v1.2.3")
    changelog         = nil,   -- array of strings; when set, logo shrinks to make room for a bullet list
    button            = nil,   -- button label string; nil -> "Get Started"; false -> no button
    later_button      = nil,   -- optional outlined secondary button to the left; tapping closes
    on_close          = nil,
    dismissable       = true,  -- when false, swipe/tap-outside won't close the screen
    _on_button_action = nil,   -- if set, button tap calls this instead of onClose
}

function ZenScreen:_computeLayout()
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    local PAD        = Screen:scaleBySize(20)
    local TITLE_H    = self.title and Screen:scaleBySize(60) or 0
    local SEP_H      = 0
    -- Tight subtitle band: just enough for one line + small breathing room.
    local SUBTITLE_H = self.subtitle and Screen:scaleBySize(44) or 0
    local BTN_H      = Screen:scaleBySize(80)
    self._L = {
        sw         = sw,
        sh         = sh,
        pad        = PAD,
        title_h    = TITLE_H,
        sep_h      = SEP_H,
        subtitle_h = SUBTITLE_H,
        btn_h      = BTN_H,
        -- Content area starts below subtitle, ends above button bar.
        content_y  = TITLE_H + SEP_H + SUBTITLE_H,
        content_h  = sh - TITLE_H - SEP_H - SUBTITLE_H - BTN_H,
        btn_y      = sh - BTN_H,
    }
end

function ZenScreen:init()
    logger.info("ZenScreen:init title=", self.title)
    local sw = Screen:getWidth()
    local sh = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self:_computeLayout()
    self._btn_rect = nil

    self:registerTouchZones({
        {
            id          = "zs_swipe",
            ges         = "swipe",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler     = function()
                if self.dismissable then self:onClose() end
                return true
            end,
        },
        {
            id          = "zs_tap",
            ges         = "tap",
            screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
            handler     = function(ges) return self:_onTap(ges) end,
        },
    })

    -- Physical key bindings (only registered when device has keys)
    if Device:hasKeys() then
        self.key_events = {
            ZsConfirm = {
                { "Press" },
                event = "ZsConfirm",
            },
            ZsConfirmPgFwd = {
                { Input.group.PgFwd },
                event = "ZsConfirm",
            },
            ZsDismiss = {
                { Input.group.PgBack },
                event = "ZsDismiss",
            },
        }
    end
end

-- Enter/PgFwd: activate primary button (or dismiss if no button)
function ZenScreen:onZsConfirm()
    if self.button ~= false then
        if self._on_button_action then
            self._on_button_action()
        else
            self:onClose()
        end
    elseif self.dismissable then
        self:onClose()
    end
    return true
end

-- PgBack: activate "Later" / dismiss
function ZenScreen:onZsDismiss()
    if self.dismissable then
        self:onClose()
    end
    return true
end

function ZenScreen:paintTo(bb, x, y)
    local L = self._L

    -- Measure changelog first so we know if the title bar needs an inline icon.
    local content_y = y + L.content_y
    local content_h = L.content_h
    local cl_x      = x + L.pad
    local cl_w      = L.sw - L.pad * 2
    local SEP_PX    = Screen:scaleBySize(8)
    local HDR_GAP   = Screen:scaleBySize(6)
    local ITEM_GAP  = Screen:scaleBySize(4)

    local logo_h = content_h
    local item_widgets = {}
    local hdr_tw, hdr_h

    if self.changelog and #self.changelog > 0 then
        hdr_tw = TextWidget:new{
            text    = _("What's New"),
            face    = Font:getFace("cfont", 18),
            bold    = true,
            padding = 0,
        }
        hdr_h = hdr_tw:getSize().h

        local items_h = 0
        for _i, item in ipairs(self.changelog) do
            local b_tw = TextBoxWidget:new{
                text      = "\u{2022} " .. item,
                face      = Font:getFace("cfont", 17),
                width     = cl_w,
                alignment = "left",
            }
            local bh = b_tw:getSize().h
            table.insert(item_widgets, { widget = b_tw, h = bh })
            items_h = items_h + bh + ITEM_GAP
        end

        local cl_total = 1 + SEP_PX + hdr_h + HDR_GAP + items_h + SEP_PX
        logo_h = math.max(0, content_h - cl_total)
    end

    local has_cl = hdr_tw ~= nil
    self._show_title_icon = false
    if has_cl then
        local min_logo_with_changelog = Screen:scaleBySize(140)
        local logo_candidate = math.floor(math.min(L.sw - L.pad * 2, logo_h - L.pad * 2))
        if logo_candidate < min_logo_with_changelog then
            logo_h = 0
            self._show_title_icon = true
        end
    end

    bb:paintRect(x, y, L.sw, L.sh, Blitbuffer.COLOR_WHITE)

    -- Title bar. When the logo is hidden by a long changelog, render a small
    -- inline icon to the left of the title at text-height so it adds no height.
    if self.title and L.title_h > 0 then
        local tw = TextWidget:new{
            text    = self.title,
            face    = Font:getFace("cfont", 24),
            bold    = true,
            padding = 0,
        }
        local tsz = tw:getSize()
        local icon_gap = Screen:scaleBySize(8)
        local icon_sz  = self._show_title_icon and tsz.h or 0
        local total_w  = tsz.w + (self._show_title_icon and (icon_sz + icon_gap) or 0)
        local base_x   = x + math.floor((L.sw - total_w) / 2)
        local text_y   = y + math.floor((L.title_h - tsz.h) / 2)

        if self._show_title_icon and ImageWidget and _plugin_root ~= "" then
            pcall(function()
                local iw = ImageWidget:new{
                    file   = _plugin_root .. "/icons/zen_ui.svg",
                    width  = icon_sz,
                    height = icon_sz,
                    alpha  = true,
                }
                iw:paintTo(bb, base_x, text_y)
                iw:free()
                if Screen.night_mode then
                    bb:invertRect(base_x, text_y, icon_sz, icon_sz)
                end
            end)
        end

        tw:paintTo(bb, base_x + (self._show_title_icon and (icon_sz + icon_gap) or 0), text_y)
        tw:free()
    end

    -- Subtitle above icon
    if self.subtitle and L.subtitle_h > 0 then
        local sub_y = y + L.title_h + L.sep_h
        local sw2 = TextWidget:new{
            text    = self.subtitle,
            face    = Font:getFace("cfont", 26),
            bold    = false,
            padding = 0,
        }
        local ssz = sw2:getSize()
        sw2:paintTo(bb,
            x + math.floor((L.sw - ssz.w) / 2),
            sub_y + math.floor((L.subtitle_h - ssz.h) / 2))
        sw2:free()
    end

    -- Logo (hidden when changelog consumes too much space).
    if ImageWidget and _plugin_root ~= "" then
        local logo    = _plugin_root .. "/icons/zen_ui.svg"
        local logo_sz = has_cl
            and math.floor(math.min(L.sw - L.pad * 2, logo_h - L.pad * 2))
            or  math.floor(math.min(L.sw - L.pad * 4, logo_h - L.pad * 4) * 0.75)
        if logo_sz > 0 then
            pcall(function()
                local iw = ImageWidget:new{
                    file   = logo,
                    width  = logo_sz,
                    height = logo_sz,
                    alpha  = true,
                }
                local isz = iw:getSize()
                local lx = x + math.floor((L.sw - isz.w) / 2)
                local ly = content_y + math.floor((logo_h - isz.h) / 2)
                iw:paintTo(bb, lx, ly)
                iw:free()
                if Screen.night_mode then
                    bb:invertRect(lx, ly, isz.w, isz.h)
                end
            end)
        end
    end

    -- Paint changelog below the logo region.
    if hdr_tw then
        local cl_y = content_y + logo_h
        bb:paintRect(x + L.pad, cl_y, cl_w, 1, Blitbuffer.COLOR_LIGHT_GRAY)
        cl_y = cl_y + 1 + SEP_PX
        hdr_tw:paintTo(bb, cl_x, cl_y)
        hdr_tw:free()
        cl_y = cl_y + hdr_h + HDR_GAP
        for _i, entry in ipairs(item_widgets) do
            entry.widget:paintTo(bb, cl_x, cl_y)
            entry.widget:free()
            cl_y = cl_y + entry.h + ITEM_GAP
        end
    else
        for _i, entry in ipairs(item_widgets) do entry.widget:free() end
    end

    -- Button(s)
    self._btn_rect       = nil
    self._later_btn_rect = nil
    if self.button ~= false and L.btn_h > 0 then
        local btn_h    = Screen:scaleBySize(54)
        local corner_r = Screen:scaleBySize(10)
        local btn_y    = y + L.btn_y + math.floor((L.btn_h - btn_h) / 2)

        if self.later_button then
            -- Two buttons: outlined "Later" left, filled primary right.
            local gap    = Screen:scaleBySize(16)
            local btn_w  = Screen:scaleBySize(200)
            local base_x = x + math.floor((L.sw - btn_w * 2 - gap) / 2)
            local bw     = Screen:scaleBySize(2)  -- outline border thickness

            -- Outlined Later button
            local lbx       = base_x
            local later_lbl = (type(self.later_button) == "string" and self.later_button ~= "")
                and self.later_button or _("Later")
            self._later_btn_rect = ZenButton.paintOutlined(
                bb, lbx, btn_y, btn_w, btn_h, later_lbl, 22, corner_r, bw)

            -- Filled primary button
            local pbx      = base_x + btn_w + gap
            local prim_lbl = (type(self.button) == "string" and self.button ~= "")
                and self.button or _("Get Started")
            self._btn_rect = ZenButton.paintFilled(
                bb, pbx, btn_y, btn_w, btn_h, prim_lbl, 22, corner_r)
        else
            -- Single centered filled button.
            local lbl   = (type(self.button) == "string" and self.button ~= "")
                and self.button or _("Get Started")
            local btn_w = Screen:scaleBySize(240)
            local btn_x = x + math.floor((L.sw - btn_w) / 2)
            self._btn_rect = ZenButton.paintFilled(
                bb, btn_x, btn_y, btn_w, btn_h, lbl, 22, corner_r)
        end
    end
end

function ZenScreen:_onTap(ges)
    local p  = ges.pos
    local L  = self._L
    local br = self._btn_rect
    local lr = self._later_btn_rect

    -- Later button: always dismisses
    if lr and p.x >= lr.x and p.x < lr.x + lr.w
           and p.y >= lr.y and p.y < lr.y + lr.h then
        self:onClose()
        return true
    end

    -- Primary button: call action override if set, otherwise close
    if br and p.x >= br.x and p.x < br.x + br.w
           and p.y >= br.y and p.y < br.y + br.h then
        if self._on_button_action then
            self._on_button_action()
        else
            self:onClose()
        end
        return true
    end

    -- Bottom nav area: only close if dismissable
    if L.btn_h > 0 and p.y >= L.btn_y then
        if self.dismissable then self:onClose() end
        return true
    end

    return true
end

--- Mutate subtitle/button/later_button/dismissable and repaint without closing/reopening.
function ZenScreen:update(opts)
    if opts.subtitle ~= nil then self.subtitle = opts.subtitle end
    if opts.button ~= nil then self.button = opts.button end
    if opts.later_button ~= nil then self.later_button = opts.later_button end
    if opts.dismissable ~= nil then self.dismissable = opts.dismissable end
    if opts.on_button ~= nil then self._on_button_action = opts.on_button end
    self:_computeLayout()
    UIManager:setDirty(self, function()
        return "partial", self.dimen
    end)
end

function ZenScreen:onShow()
    logger.info("ZenScreen:onShow dimen=", self.dimen)
    UIManager:setDirty(self, function()
        return "flashui", self.dimen
    end)
end

function ZenScreen:onClose()
    UIManager:setDirty(nil, "full")
    UIManager:close(self)
    -- Block filebrowser taps briefly so the dismiss gesture doesn't open a file.
    _G.__ZEN_QUICKSTART_JUST_CLOSED = true
    UIManager:scheduleIn(1.5, function() _G.__ZEN_QUICKSTART_JUST_CLOSED = nil end)
    package.loaded["common/zen_screen"] = nil
    if self.on_close then
        self.on_close()
    end
end

return ZenScreen

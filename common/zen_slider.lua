-- ZenSlider: a generic horizontal slider widget with a pill-shaped track and
-- a circular knob.  Pure visual widget — gesture handling is done externally
-- by the parent container via applyPosition() and hitTest().
--
-- Usage:
--   local ZenSlider = require("common/zen_slider")
--   local slider = ZenSlider:new{
--       width      = 300,
--       value      = 50,
--       value_min  = 0,
--       value_max  = 100,
--       on_change  = function(v) ... end,
--   }
--
-- API:
--   slider:paintTo(bb, x, y)    -- draw; keeps dimen.x/y for hit-testing
--   slider:getSize()             -- returns Geom (w, h)
--   slider:setValue(v)           -- update value; no callback
--   slider:getValue()            -- current integer value
--   slider:applyPosition(abs_x)  -- set value from screen X; fires on_change
--   slider:hitTest(pos)          -- true if pos intersects slider rect

local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Geom       = require("ui/geometry")
local Math       = require("optmath")
local UIManager  = require("ui/uimanager")
local Screen     = Device.screen

-- ---------------------------------------------------------------------------
-- Drawing helpers (scanline; uses bb:paintRect only)
-- ---------------------------------------------------------------------------

local function paintPill(bb, px, py, pw, ph, color)
    if pw <= 0 or ph <= 0 then return end
    local r = math.min(pw, ph) / 2.0
    for row = 0, ph - 1 do
        local dy    = (row + 0.5) - ph * 0.5
        local inset = 0
        if math.abs(dy) < r then
            inset = math.ceil(r - math.sqrt(r * r - dy * dy))
        end
        local rw = pw - 2 * inset
        if rw > 0 then
            bb:paintRect(px + inset, py + row, rw, 1, color)
        end
    end
end

local function paintCircle(bb, cx, cy, r, color)
    for row = -r, r do
        local half = math.floor(math.sqrt(r * r - row * row) + 0.5)
        if half > 0 then
            bb:paintRect(cx - half, cy + row, half * 2, 1, color)
        end
    end
end

-- ---------------------------------------------------------------------------
-- ZenSlider (plain table class — NOT an InputContainer)
-- ---------------------------------------------------------------------------

local ZenSlider = {}
ZenSlider.__index = ZenSlider

function ZenSlider:new(o)
    local obj = setmetatable(o or {}, self)
    obj.track_height  = obj.track_height  or Screen:scaleBySize(1)   -- very thin rail
    obj.fill_height   = obj.fill_height   or Screen:scaleBySize(6)   -- thicker filled bar
    obj.knob_radius   = obj.knob_radius   or Screen:scaleBySize(16.5)
    obj.fill_color    = obj.fill_color    or Blitbuffer.COLOR_BLACK
    obj.track_color   = obj.track_color   or obj.fill_color          -- same color: no flash on repaint
    obj.knob_color    = obj.knob_color    or Blitbuffer.COLOR_BLACK
    obj.knob_bg_color = obj.knob_bg_color or Blitbuffer.COLOR_WHITE
    local knob_d  = obj.knob_radius * 2
    obj.height    = knob_d + Screen:scaleBySize(6)
    obj.dimen     = Geom:new{ w = obj.width or 0, h = obj.height }
    obj._value    = math.max(obj.value_min,
                    math.min(obj.value_max,
                    Math.round(obj.value or obj.value_min)))
    return obj
end

-- ---------------------------------------------------------------------------
-- Internal geometry
-- ---------------------------------------------------------------------------

function ZenSlider:_trackBounds()
    local r = self.knob_radius
    return r, (self.width or 0) - r
end

function ZenSlider:_valueToX(v)
    local x0, x1 = self:_trackBounds()
    local range   = self.value_max - self.value_min
    if range == 0 then return x0 end
    return x0 + (v - self.value_min) / range * (x1 - x0)
end

function ZenSlider:_xToValue(local_x)
    local x0, x1 = self:_trackBounds()
    local frac    = (local_x - x0) / math.max(1, x1 - x0)
    frac          = math.max(0, math.min(1, frac))
    return math.max(self.value_min,
           math.min(self.value_max,
           Math.round(self.value_min + frac * (self.value_max - self.value_min))))
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function ZenSlider:getValue()
    return self._value
end

function ZenSlider:setValue(v)
    self._value = math.max(self.value_min,
                  math.min(self.value_max, Math.round(v)))
end

--- Update value from an absolute screen X; fires on_change if value changed.
function ZenSlider:applyPosition(abs_x)
    local local_x = abs_x - (self.dimen and self.dimen.x or 0)
    local new_val = self:_xToValue(local_x)
    if new_val ~= self._value then
        self._value = new_val
        if self.on_change then self.on_change(new_val) end
    end
end

--- Returns true if pos (Geom point) is inside the slider widget area.
function ZenSlider:hitTest(pos)
    return self.dimen ~= nil and pos:intersectWith(self.dimen)
end

function ZenSlider:getSize()
    return self.dimen
end

-- ---------------------------------------------------------------------------
-- Paint (also keeps dimen.x/y in sync for hit-testing)
-- ---------------------------------------------------------------------------

function ZenSlider:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    local w  = self.width or 0
    local h  = self.height
    local th = self.track_height
    local r  = self.knob_radius

    -- Clear own area first so stale pixels (e.g. from a moved knob) never
    -- accumulate and corrupt the e-ink differential-update baseline.
    bb:paintRect(x, y, w, h, self.knob_bg_color)

    local track_cy = math.floor(y + h / 2)
    local track_y  = track_cy - math.floor(th / 2)

    -- Full track (very thin pill)
    paintPill(bb, x, track_y, w, th, self.track_color)

    -- Filled left portion (thicker pill, centred on same axis)
    local fh     = self.fill_height
    local fill_y = track_cy - math.floor(fh / 2)
    local knob_x = math.floor(x + self:_valueToX(self._value))
    if knob_x > x then
        paintPill(bb, x, fill_y, knob_x - x, fh, self.fill_color)
    end

    -- Knob: white outer circle, then black inner circle (hidden while dragging)
    if not self.hide_knob then
        paintCircle(bb, knob_x, track_cy, r,                         self.knob_bg_color)
        paintCircle(bb, knob_x, track_cy, r - Screen:scaleBySize(2), self.knob_color)
    end
end

-- ---------------------------------------------------------------------------
-- Gesture helpers
-- ---------------------------------------------------------------------------

--- Absolute screen X of the knob centre (valid after first paintTo call).
function ZenSlider:_knobAbsX()
    return math.floor((self.dimen and self.dimen.x or 0) + self:_valueToX(self._value))
end

--- True when abs_x is within a 4× knob-radius touch zone around the knob.
function ZenSlider:_isNearKnob(abs_x)
    return math.abs(abs_x - self:_knobAbsX()) <= self.knob_radius * 4
end

-- ---------------------------------------------------------------------------
-- Gesture handlers (called by parent container)
-- ---------------------------------------------------------------------------

--- Tap anywhere on the track: jump knob to that position.
function ZenSlider:handleTap(ges)
    if not self.dimen or not ges.pos:intersectWith(self.dimen) then return false end
    self:applyPosition(ges.pos.x)
    return true
end

--- Pan: begins dragging when the gesture starts near the knob with any
-- direction that has a horizontal component (i.e. not purely north/south).
-- A fast grab rarely produces a pure "east"/"west" first pan event; diagonals
-- like "northeast" or "southeast" are common and must be accepted.
-- Once dragging has started, all subsequent pan events are tracked freely.
function ZenSlider:handlePan(ges)
    if self._dragging then
        self:applyPosition(ges.pos.x)
        return true
    end
    -- Initial contact: must be on the slider and near the knob, and the
    -- motion must not be purely vertical.
    if not (self.dimen and ges.pos:intersectWith(self.dimen)) then return false end
    local dir = ges.direction
    if dir == "north" or dir == "south" then return false end
    if not self:_isNearKnob(ges.pos.x) then return false end
    self._dragging = true
    self.hide_knob = true
    self:applyPosition(ges.pos.x)
    return true
end

--- Pan release: commit final value and repaint the knob.
function ZenSlider:handlePanRelease(ges, show_parent, dirty_dimen)
    if not self._dragging then return false end
    self._dragging = false
    self.hide_knob = false
    self:applyPosition(ges.pos.x)
    UIManager:setDirty(show_parent, "ui", dirty_dimen)
    return true
end

--- Returns true for any direction with a dominant horizontal component.
local function isHorizontalish(dir)
    return dir == "east" or dir == "west"
        or dir == "northeast" or dir == "northwest"
        or dir == "southeast" or dir == "southwest"
end

--- Returns +1 / -1 sign for the horizontal component of a direction.
local function hSign(dir)
    if dir == "east" or dir == "northeast" or dir == "southeast" then
        return 1
    end
    return -1
end

--- Swipe (fast drag): any direction with a horizontal component, starting near the knob.
-- ges.pos is the swipe START, so end position is reconstructed from direction + distance.
function ZenSlider:handleSwipe(ges, show_parent, dirty_dimen)
    if not isHorizontalish(ges.direction) then return false end
    if not self._dragging then
        if not (self.dimen and ges.pos:intersectWith(self.dimen)) then return false end
        if not self:_isNearKnob(ges.pos.x) then return false end
    end
    local was_dragging = self._dragging
    self._dragging = false
    self.hide_knob = false
    if not was_dragging then
        local dist  = ges.distance or 0
        local end_x = ges.pos.x + hSign(ges.direction) * dist
        self:applyPosition(end_x)
    else
        -- Pan events already positioned the knob; just repaint it.
        UIManager:setDirty(show_parent, "ui", dirty_dimen)
    end
    return true
end

--- Multiswipe (fast back-and-forth): only clean up an in-progress drag.
function ZenSlider:handleMultiSwipe(ges, show_parent, dirty_dimen)
    if not self._dragging then return false end
    self._dragging = false
    self.hide_knob = false
    UIManager:setDirty(show_parent, "ui", dirty_dimen)
    return true
end

--- Patch a TouchMenu class with slider-aware gesture handlers for pan,
--- pan_release, swipe, and multiswipe.  Call once during plugin init.
---
--- opts fields:
---   in_panel_mode(tm)            -> bool  true when the panel tab is active
---   get_sliders(tm)              -> []ZenSlider  sliders to dispatch to
---   is_locked(tm)                -> bool  true while slider input is suppressed
---   swipe_fallback(tm, ges)      -> called for swipes not claimed by a slider
---   multiswipe_fallback(tm, ges) -> called for multiswipes not claimed by a slider
function ZenSlider.installTouchMenuHooks(TouchMenu, opts)
    local in_panel  = opts.in_panel_mode
    local get_sl    = opts.get_sliders
    local is_locked = opts.is_locked
    local swipe_fb  = opts.swipe_fallback
    local mswipe_fb = opts.multiswipe_fallback

    function TouchMenu:onPanCloseAllMenus(arg, ges_ev)
        if not in_panel(self) then return end
        if is_locked(self) then return end
        for _, sl in ipairs(get_sl(self)) do
            if sl:handlePan(ges_ev) then return true end
        end
    end

    function TouchMenu:onPanReleaseCloseAllMenus(arg, ges_ev)
        if not in_panel(self) then return end
        for _, sl in ipairs(get_sl(self)) do
            if sl:handlePanRelease(ges_ev, self.show_parent, self.dimen) then return true end
        end
    end

    local orig_onSwipe = TouchMenu.onSwipe
    function TouchMenu:onSwipe(arg, ges_ev)
        if in_panel(self) then
            if not is_locked(self) then
                for _, sl in ipairs(get_sl(self)) do
                    if sl:handleSwipe(ges_ev, self.show_parent, self.dimen) then return true end
                end
            end
            if swipe_fb then swipe_fb(self, ges_ev) end
            return true
        end
        if orig_onSwipe then return orig_onSwipe(self, arg, ges_ev) end
    end

    local orig_onMultiSwipe = TouchMenu.onMultiSwipe
    function TouchMenu:onMultiSwipe(arg, ges_ev)
        if in_panel(self) then
            for _, sl in ipairs(get_sl(self)) do
                if sl:handleMultiSwipe(ges_ev, self.show_parent, self.dimen) then return true end
            end
            if mswipe_fb then mswipe_fb(self, ges_ev) end
            return true
        end
        if orig_onMultiSwipe then return orig_onMultiSwipe(self, arg, ges_ev) end
    end
end

-- Required by WidgetContainer.propagateEvent — called on every child during
-- event dispatch.  We handle no events here; all interaction goes through the
-- parent TouchMenu gesture hooks.
function ZenSlider:handleEvent(_event)
    return false
end

return ZenSlider

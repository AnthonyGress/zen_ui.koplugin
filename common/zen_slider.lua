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

    -- Knob: white outer circle, then black inner circle
    paintCircle(bb, knob_x, track_cy, r,                         self.knob_bg_color)
    paintCircle(bb, knob_x, track_cy, r - Screen:scaleBySize(2), self.knob_color)
end

-- Required by WidgetContainer.propagateEvent — called on every child during
-- event dispatch.  We handle no events here; all interaction goes through the
-- parent TouchMenu gesture hooks (applyPosition / handleSliderPan).
function ZenSlider:handleEvent(_event)
    return false
end

return ZenSlider

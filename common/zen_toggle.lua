-- ZenToggle: a pill-shaped boolean toggle switch for e-ink displays.
-- Pure visual widget — gesture handling is done externally by the parent
-- container via hitTest() and the supplied callback.
--
-- Usage:
--   local ZenToggle = require("common/zen_toggle")
--   local toggle = ZenToggle:new{
--       width      = 56,          -- optional; default Screen:scaleBySize(56)
--       height     = 28,          -- optional; default Screen:scaleBySize(28)
--       value      = false,       -- initial state (ignored when value_func set)
--       value_func = function() return some_bool end,  -- live-read state source
--   }
--
-- API:
--   toggle:paintTo(bb, x, y)     -- draw; keeps dimen.x/y for hit-testing
--   toggle:getSize()              -- returns Geom (w, h)
--   toggle:getValue()             -- current bool (via value_func when set)
--   toggle:setValue(bool)         -- update internal _value; no callback
--   toggle:toggle()               -- flip _value; fires on_change
--   toggle:hitTest(pos)           -- true if pos intersects toggle rect
--   toggle:handleEvent(e)         -- always false (WidgetContainer compat)

local Blitbuffer = require("ffi/blitbuffer")
local Device     = require("device")
local Geom       = require("ui/geometry")
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
-- ZenToggle (plain table class — NOT an InputContainer)
-- ---------------------------------------------------------------------------

local ZenToggle = {}
ZenToggle.__index = ZenToggle

function ZenToggle:new(o)
    local obj   = setmetatable(o or {}, self)
    obj.height  = obj.height or Screen:scaleBySize(28)
    obj.width   = obj.width  or Screen:scaleBySize(56)
    obj._border = Screen:scaleBySize(2)  -- border width for OFF state
    obj._pad    = Screen:scaleBySize(3)  -- gap between knob edge and pill edge
    obj._knob_r = math.max(1, math.floor(obj.height / 2) - obj._pad)
    obj._value  = obj.value and true or false
    obj.dimen   = Geom:new{ w = obj.width, h = obj.height }
    return obj
end

--- Returns the current boolean state.  value_func takes precedence for live reads.
function ZenToggle:getValue()
    if self.value_func then return self.value_func() end
    return self._value
end

--- Update internal state without firing on_change.
function ZenToggle:setValue(is_on)
    self._value = is_on and true or false
end

--- Flip internal state and fire on_change.
function ZenToggle:toggle()
    self._value = not self._value
    if self.on_change then self.on_change(self._value) end
end

--- Returns true if pos (Geom point) is inside the toggle area.
function ZenToggle:hitTest(pos)
    return self.dimen ~= nil and pos:intersectWith(self.dimen)
end

function ZenToggle:getSize()
    return self.dimen
end

-- ---------------------------------------------------------------------------
-- Paint (also keeps dimen.x/y in sync for hit-testing)
-- ---------------------------------------------------------------------------

function ZenToggle:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y

    local w   = self.width
    local h   = self.height
    local kr  = self._knob_r
    local pad = self._pad
    local bw  = self._border
    local cy  = y + math.floor(h / 2)

    local is_on = self.value_func and self.value_func() or self._value

    if is_on then
        -- ON: solid black pill, white knob on the right
        paintPill(bb, x, y, w, h, Blitbuffer.COLOR_BLACK)
        paintCircle(bb, x + w - pad - kr, cy, kr, Blitbuffer.COLOR_WHITE)
    else
        -- OFF: black-bordered pill (white interior), dark knob on the left
        -- Offset by bw so the visual gap from the inner wall matches ON-state gap
        paintPill(bb, x, y, w, h, Blitbuffer.COLOR_BLACK)
        paintPill(bb, x + bw, y + bw, w - 2 * bw, h - 2 * bw, Blitbuffer.COLOR_WHITE)
        paintCircle(bb, x + bw + pad + kr, cy, kr, Blitbuffer.COLOR_DARK_GRAY)
    end
end

-- Required by WidgetContainer.propagateEvent — we handle no events directly.
function ZenToggle:handleEvent(_event)
    return false
end

return ZenToggle

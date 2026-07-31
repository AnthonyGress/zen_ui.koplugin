-- Shared LRU of final-size cover bitmaps used by mosaic, list, and Home.
local Blitbuffer = require("ffi/blitbuffer")
local RenderImage

local M = {
    DEFAULT_BYTE_BUDGET = 24 * 1024 * 1024,
    _byte_budget = 24 * 1024 * 1024,
    _bytes = 0,
    _clock = 0,
    _entries = {},
    _hits = 0,
    _misses = 0,
    _puts = 0,
    _evictions = 0,
}

local function bytes(bb)
    if not bb then return 0 end
    local stride = tonumber(bb.stride)
    local height = (bb.getHeight and bb:getHeight()) or tonumber(bb.h) or 0
    return stride and stride * height or 0
end

local function free(bb)
    if bb and bb.free then pcall(bb.free, bb) end
end

local function key(path)
    return tostring(path)
end

local function same_aspect(width_a, height_a, width_b, height_b)
    if height_a < 1 or height_b < 1 then return false end
    local rounding_tolerance = math.max(width_a, height_a, width_b, height_b)
    return math.abs(width_a * height_b - width_b * height_a) <= rounding_tolerance
end

-- Takes ownership of source and returns an exact-size crop.
local function resize(source, width, height)
    local ok_dims, src_w, src_h = pcall(function()
        return source:getWidth(), source:getHeight()
    end)
    if not ok_dims or not src_w or not src_h then
        free(source)
        return nil
    end
    if src_w == width and src_h == height then return source end
    local scale = math.max(width / src_w, height / src_h)
    local scaled_w = math.max(width, math.ceil(src_w * scale))
    local scaled_h = math.max(height, math.ceil(src_h * scale))
    local scaled = source
    if scaled_w ~= src_w or scaled_h ~= src_h then
        RenderImage = RenderImage or require("ui/renderimage")
        local ok_scale, resized = pcall(
            RenderImage.scaleBlitBuffer, RenderImage,
            source, scaled_w, scaled_h, true
        )
        if not ok_scale or not resized then
            free(source)
            return nil
        end
        scaled = resized
    end
    local ok_out, out = pcall(Blitbuffer.new, width, height, scaled:getType())
    if not ok_out or not out then
        free(scaled)
        return nil
    end
    local ok_blit = pcall(out.blitFrom, out, scaled, 0, 0,
        math.floor((scaled_w - width) / 2),
        math.floor((scaled_h - height) / 2), width, height)
    free(scaled)
    if not ok_blit then
        free(out)
        return nil
    end
    return out
end

function M:_drop(cache_key, evicted)
    local entry = self._entries[cache_key]
    if not entry then return end
    self._entries[cache_key] = nil
    self._bytes = math.max(0, self._bytes - entry.bytes)
    free(entry.bb)
    if evicted then self._evictions = self._evictions + 1 end
end

function M:_makeRoom(needed)
    while self._bytes + needed > self._byte_budget do
        local oldest_key
        local oldest_touch
        for cache_key, entry in pairs(self._entries) do
            if not oldest_touch or entry.touch < oldest_touch then
                oldest_key, oldest_touch = cache_key, entry.touch
            end
        end
        if not oldest_key then break end
        self:_drop(oldest_key, true)
    end
end

function M:get(path, width, height)
    local entry = self._entries[key(path)]
    if not entry or entry.width < width or entry.height < height
            or not same_aspect(entry.width, entry.height, width, height) then
        self._misses = self._misses + 1
        return nil
    end
    local ok, copy = pcall(entry.bb.copy, entry.bb)
    if not ok or not copy then
        self._misses = self._misses + 1
        return nil
    end
    local resized = resize(copy, width, height)
    if not resized then
        self:_drop(key(path), true)
        self._misses = self._misses + 1
        return nil
    end
    self._clock = self._clock + 1
    entry.touch = self._clock
    self._hits = self._hits + 1
    return resized
end

function M:put(path, width, height, bb)
    if not path or not bb then return nil end
    local cache_key = key(path)
    local existing = self._entries[cache_key]
    if existing and existing.width >= width and existing.height >= height
            and same_aspect(existing.width, existing.height, width, height) then
        self._clock = self._clock + 1
        existing.touch = self._clock
        return bb
    end
    local size = bytes(bb)
    if size <= 0 or size > self._byte_budget then
        return nil
    end
    self:_drop(cache_key)
    self:_makeRoom(size)
    local ok, stored = pcall(bb.copy, bb)
    if not ok or not stored then return nil end
    size = bytes(stored)
    if size <= 0 or size > self._byte_budget then
        free(stored)
        return nil
    end
    self:_makeRoom(size)
    self._clock = self._clock + 1
    self._entries[cache_key] = {
        bb = stored,
        bytes = size,
        touch = self._clock,
        width = width,
        height = height,
    }
    self._bytes = self._bytes + size
    self._puts = self._puts + 1
    return bb
end

-- Takes ownership of source. The returned bitmap is caller-owned.
function M:render(path, source, width, height)
    local cached = self:get(path, width, height)
    if cached then
        free(source)
        return cached
    end
    if not source or width < 1 or height < 1 then return nil end
    local out = resize(source, width, height)
    if not out then return nil end
    self:put(path, width, height, out)
    return out
end

function M:setByteBudget(value)
    value = tonumber(value)
    if not value or value < 1 then return false end
    self._byte_budget = math.floor(value)
    self:_makeRoom(0)
    return true
end

function M:drop(path)
    self:_drop(key(path))
end

function M:clear()
    local keys = {}
    for cache_key in pairs(self._entries) do keys[#keys + 1] = cache_key end
    for _i, cache_key in ipairs(keys) do self:_drop(cache_key) end
    self._clock, self._hits, self._misses, self._puts, self._evictions = 0, 0, 0, 0, 0
end

function M:stats()
    return {
        bytes = self._bytes,
        byte_budget = self._byte_budget,
        hits = self._hits,
        misses = self._misses,
        puts = self._puts,
        evictions = self._evictions,
    }
end

return M

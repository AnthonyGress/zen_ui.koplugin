-- Shared LRU of final-size cover bitmaps used by mosaic, list, and Home.
local Blitbuffer = require("ffi/blitbuffer")

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

local function key(path, width, height)
    return tostring(path) .. "\31" .. tostring(width) .. "x" .. tostring(height)
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
    local entry = self._entries[key(path, width, height)]
    if not entry then
        self._misses = self._misses + 1
        return nil
    end
    local ok, copy = pcall(entry.bb.copy, entry.bb)
    if not ok or not copy then
        self._misses = self._misses + 1
        return nil
    end
    self._clock = self._clock + 1
    entry.touch = self._clock
    self._hits = self._hits + 1
    return copy
end

function M:put(path, width, height, bb)
    if not path or not bb then return nil end
    local ok, stored = pcall(bb.copy, bb)
    if not ok or not stored then return nil end
    local size = bytes(stored)
    if size <= 0 or size > self._byte_budget then
        free(stored)
        return nil
    end
    local cache_key = key(path, width, height)
    self:_drop(cache_key)
    self:_makeRoom(size)
    self._clock = self._clock + 1
    self._entries[cache_key] = { bb = stored, bytes = size, touch = self._clock }
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
    local src_w, src_h = source:getWidth(), source:getHeight()
    local scale = math.max(width / src_w, height / src_h)
    local scaled_w = math.max(width, math.ceil(src_w * scale))
    local scaled_h = math.max(height, math.ceil(src_h * scale))
    local scaled = source
    if scaled_w ~= src_w or scaled_h ~= src_h then
        scaled = source:scale(scaled_w, scaled_h)
        free(source)
    end
    local out = Blitbuffer.new(width, height, scaled:getType())
    out:blitFrom(scaled, 0, 0,
        math.floor((scaled_w - width) / 2), math.floor((scaled_h - height) / 2), width, height)
    if scaled ~= source then free(scaled) else free(source) end
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
    local prefix = tostring(path) .. "\31"
    local keys = {}
    for cache_key in pairs(self._entries) do
        if cache_key:sub(1, #prefix) == prefix then keys[#keys + 1] = cache_key end
    end
    for _i, cache_key in ipairs(keys) do self:_drop(cache_key) end
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

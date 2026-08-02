-- Standard Zen UI logger; adapts KOReader's logger backend.
local M = {}

local _logger
local _original = {}
local _installed = false
local _plugin_root

local LEVELS = { "dbg", "info", "warn", "err" }
M.SLOW_THRESHOLD_MS = 500

local function get_plugin_root()
    if _plugin_root ~= nil then return _plugin_root end
    local source = debug.getinfo(1, "S").source or ""
    _plugin_root = source:match("^@(.+)/common/zen_logger%.lua$") or false
    return _plugin_root
end

local function feature_from_source(source)
    local root = get_plugin_root()
    if type(source) ~= "string" or source:sub(1, 1) ~= "@" or not root then
        return nil
    end
    local path = source:sub(2)
    if path:sub(1, #root) ~= root then return nil end
    return path:match("([^/]+)%.lua$")
end

local function strip_legacy_prefix(message)
    message = message:gsub("^%[?[Zz]en[Uu][Ii]%]?[%s:]*", "")
    message = message:gsub("^%[?[Zz]en[ _%-][Uu][Ii]%]?[%s:]*", "")
    message = message:gsub("^%b[]:%s*", "")
    message = message:gsub("^ZenUpdater:%s*", "")
    message = message:gsub("^ZenBugReporter:%s*", "")
    message = message:gsub("^ZenScreen:%s*", "")
    message = message:gsub("^ZenHeader:%s*", "")
    message = message:gsub("^zen%-coll:%s*", "")
    return message
end

local function emit(level, feature, args)
    if type(args[1]) == "string" then
        args[1] = string.format("Zen UI: [%s] %s", feature, strip_legacy_prefix(args[1]))
    else
        table.insert(args, 1, string.format("Zen UI: [%s]", feature))
    end
    return _original[level](unpack(args))
end

local function emit_performance(feature, message, elapsed_ms, ...)
    elapsed_ms = math.floor((tonumber(elapsed_ms) or 0) + 0.5)
    local args = { message }
    for i = 1, select("#", ...) do
        args[#args + 1] = select(i, ...)
    end
    args[#args + 1] = "elapsed_ms="
    args[#args + 1] = elapsed_ms
    if elapsed_ms >= M.SLOW_THRESHOLD_MS then
        args[1] = "SLOW: " .. tostring(message)
        args[#args + 1] = "slow_threshold_ms="
        args[#args + 1] = M.SLOW_THRESHOLD_MS
        return emit("warn", feature, args)
    end
    return emit("dbg", feature, args)
end

function M.install()
    if _installed then return _logger end

    _logger = require("logger")
    local function wrap(level)
        return function(...)
            local source = debug.getinfo(2, "S").source
            local feature = feature_from_source(source)
            if feature then
                return emit(level, feature, { ... })
            end
            return _original[level](...)
        end
    end
    for _i, level in ipairs(LEVELS) do
        _original[level] = _logger[level]
        _logger[level] = wrap(level)
    end
    _installed = true
    return _logger
end

function M.new(feature)
    M.install()
    feature = feature or "unknown"
    local logger = {}
    local function method(level)
        return function(...)
            local source = debug.getinfo(2, "S").source
            return emit(level, feature_from_source(source) or feature, { ... })
        end
    end
    for _i, level in ipairs(LEVELS) do
        logger[level] = method(level)
    end
    logger.perf = function(message, elapsed_ms, ...)
        local source = debug.getinfo(2, "S").source
        return emit_performance(feature_from_source(source) or feature, message, elapsed_ms, ...)
    end
    return logger
end

return M

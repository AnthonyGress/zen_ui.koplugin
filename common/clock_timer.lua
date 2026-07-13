local M = {}

local subscribers = {}
local object_subscribers = setmetatable({}, { __mode = "k" })
local scheduled_fn = nil
local paused = false

local function get_ui_manager()
    return require("ui/uimanager")
end

local function next_minute_delay()
    local t = os.date("*t")
    local sec = type(t) == "table" and tonumber(t.sec) or 0
    sec = sec or 0
    local delay = 60 - sec
    if delay <= 0 or delay > 60 then delay = 60 end
    return delay
end

local function has_subscribers()
    return next(subscribers) ~= nil or next(object_subscribers) ~= nil
end

local function unschedule()
    if scheduled_fn then
        get_ui_manager():unschedule(scheduled_fn)
        scheduled_fn = nil
    end
end

local function safe_call(callback, ...)
    local ok, err = pcall(callback, ...)
    if not ok then
        require("common/zen_logger").new("clock_timer").warn("Callback failed:", tostring(err))
    end
end

local schedule_next

local function run_callbacks()
    for key, callback in pairs(subscribers) do
        if type(callback) == "function" then
            safe_call(callback, key)
        else
            subscribers[key] = nil
        end
    end

    for target, callback in pairs(object_subscribers) do
        if type(callback) == "function" then
            safe_call(callback, target)
        else
            object_subscribers[target] = nil
        end
    end
end

local function run_tick()
    scheduled_fn = nil
    if paused then return end

    run_callbacks()

    schedule_next()
end

schedule_next = function()
    if paused or scheduled_fn or not has_subscribers() then return end
    scheduled_fn = run_tick
    get_ui_manager():scheduleIn(next_minute_delay(), run_tick)
end

function M.subscribe(key, callback)
    if key == nil or type(callback) ~= "function" then return end
    subscribers[key] = callback
    schedule_next()
end

function M.unsubscribe(key)
    if key == nil then return end
    subscribers[key] = nil
    if not has_subscribers() then unschedule() end
end

function M.bind(target, callback)
    if type(target) ~= "table" or type(callback) ~= "function" then return end
    object_subscribers[target] = callback
    schedule_next()
end

function M.unbind(target)
    if type(target) ~= "table" then return end
    object_subscribers[target] = nil
    if not has_subscribers() then unschedule() end
end

function M.pause()
    paused = true
    unschedule()
end

function M.resume()
    paused = false
    schedule_next()
end

function M.restart()
    unschedule()
    schedule_next()
end

function M.refreshNow()
    if paused then return end
    run_callbacks()
end

return M

local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local ZenLogger = require("common/zen_logger")

local logger = ZenLogger.new("reader_park")
local M = {}

local IDLE_FINISH_S = 30
local PROBE_EVERY_S = 10

local parked
local pending_probe
local finishing = false
local last_input = 0

local function currentReader()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    return ok and ReaderUI and ReaderUI.instance or nil
end

local function cancelProbe()
    if not pending_probe then return end
    UIManager:unschedule(pending_probe)
    pending_probe = nil
end

local function clearParked()
    parked = nil
    cancelProbe()
end

local function findWidget(stack, widget)
    for i, entry in ipairs(stack or {}) do
        if entry and entry.widget == widget then return i end
    end
end

local function raiseWidgets(widgets, mark_dirty)
    local stack = UIManager._window_stack
    if type(stack) ~= "table" then return false end
    for _i, widget in ipairs(widgets or {}) do
        if not findWidget(stack, widget) then return false end
    end
    for _i, widget in ipairs(widgets) do
        local index = findWidget(stack, widget)
        table.insert(stack, table.remove(stack, index))
    end
    local top = widgets[#widgets]
    if mark_dirty and top then
        if type(top._zen_status_refresh) == "function" then
            pcall(top._zen_status_refresh, top)
        end
        UIManager:setDirty(top, function()
            return "ui", top.dimen, top.dithered
        end)
    end
    return true
end

local function installInputStamp()
    if UIManager._zen_reader_park_input_stamp or type(UIManager.sendEvent) ~= "function" then
        return
    end
    UIManager._zen_reader_park_input_stamp = true
    local original = UIManager.sendEvent
    UIManager.sendEvent = function(self, event, ...)
        local handler = type(event) == "table" and event.handler
        if handler == "onGesture" or handler == "onKeyPress"
                or handler == "onKeyRepeat" then
            last_input = ZenLogger.now()
        end
        return original(self, event, ...)
    end
end

function M.isParked()
    if not parked then return false end
    local reader = currentReader()
    if reader and reader ~= parked.reader then
        clearParked()
        return false
    end
    if not parked.reader.document then
        clearParked()
        return false
    end
    return true
end

function M.isFinishing()
    return finishing
end

function M.parkedFile()
    if not M.isParked() then return nil end
    return parked.file
end

local function discardNewRefreshes(refresh_count, refresh_func_count)
    for i = #(UIManager._refresh_stack or {}), refresh_count + 1, -1 do
        UIManager._refresh_stack[i] = nil
    end
    for i = #(UIManager._refresh_func_stack or {}), refresh_func_count + 1, -1 do
        UIManager._refresh_func_stack[i] = nil
    end
end

function M.finish(reason)
    if not M.isParked() then return false end
    local state = parked
    parked = nil
    cancelProbe()

    local started_at = ZenLogger.now()
    local refresh_count = #(UIManager._refresh_stack or {})
    local refresh_func_count = #(UIManager._refresh_func_stack or {})
    finishing = true
    _G.__ZEN_UI_FAST_RETURN_REBUILDING = true
    _G.__ZEN_UI_FAST_RETURN = state.view

    local ok, err = xpcall(function()
        state.reader:onClose(false)
        if type(state.reader.showFileManager) == "function" then
            state.reader:showFileManager(state.file)
        end
        discardNewRefreshes(refresh_count, refresh_func_count)

        local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
        local fm = ok_fm and FileManager and FileManager.instance
        if fm and UIManager._dirty then UIManager._dirty[fm] = nil end
        if raiseWidgets(state.view.widgets, false) then
            local top = state.view.widgets[#state.view.widgets]
            UIManager:setDirty(top, function()
                return "ui", top.dimen, top.dithered
            end)
        end
    end, debug.traceback)

    _G.__ZEN_UI_FAST_RETURN = nil
    _G.__ZEN_UI_FAST_RETURN_REBUILDING = nil
    _G.__ZEN_UI_RETAIN_LIBRARY_VIEW = nil
    UIManager:nextTick(function() finishing = false end)
    logger.perf("Parked Reader close completed",
        (ZenLogger.now() - started_at) * 1000,
        "reason=", tostring(reason))
    if not ok then error(err, 0) end
    return true
end

local function probe(reader)
    pending_probe = nil
    if not M.isParked() or parked.reader ~= reader then return end
    local stack = UIManager._window_stack
    local top = stack and stack[#stack] and stack[#stack].widget
    local widgets = parked.view.widgets
    if ZenLogger.now() - last_input >= IDLE_FINISH_S
            and top == widgets[#widgets] then
        M.finish("idle")
        return
    end
    pending_probe = function() probe(reader) end
    UIManager:scheduleIn(PROBE_EVERY_S, pending_probe)
end

function M.park(reader, view)
    if M.isParked() or not (reader and reader.document) then return false end
    if type(view) ~= "table" or view.retained ~= true
            or type(view.widgets) ~= "table" or #view.widgets == 0 then
        return false
    end

    pcall(reader.handleEvent, reader, Event:new("CloseReaderMenu"))
    pcall(reader.handleEvent, reader, Event:new("CloseConfigMenu"))
    if reader.highlight and type(reader.highlight.onClose) == "function" then
        pcall(reader.highlight.onClose, reader.highlight)
    end
    if not raiseWidgets(view.widgets, true) then return false end

    parked = {
        reader = reader,
        file = reader.document.file,
        view = view,
    }
    installInputStamp()
    last_input = ZenLogger.now()
    logger.info("Reader parked", parked.file)

    UIManager:nextTick(function()
        if not M.isParked() or parked.reader ~= reader then return end
        pcall(reader.saveSettings, reader)
        pcall(function()
            local BookList = require("ui/widget/booklist")
            BookList.setBookInfoCache(parked.file, reader.doc_settings)
        end)
        if type(view.refresh) == "function" then
            local ok, refresh_err = pcall(view.refresh)
            if not ok then
                logger.warn("Retained library refresh failed", refresh_err)
            end
        end
    end)

    pending_probe = function() probe(reader) end
    UIManager:scheduleIn(PROBE_EVERY_S, pending_probe)
    return true
end

function M.unpark()
    if not M.isParked() then return false end
    local state = parked
    local stack = UIManager._window_stack
    local index = findWidget(stack, state.reader)
    if not index then
        clearParked()
        return false
    end

    parked = nil
    cancelProbe()
    if index ~= #stack then
        table.insert(stack, table.remove(stack, index))
    end
    UIManager:setDirty(state.reader, "full")
    logger.info("Reader unparked", state.file)
    return true
end

function M.open(file)
    if not M.isParked() then return false end
    if parked.file == file then return M.unpark() end
    M.finish("different-book")
    return false
end

function M.ensureFileManager(reason)
    if not M.isParked() then return false end
    return M.finish(reason or "file-manager-action")
end

return M

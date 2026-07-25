local paths = require("common/paths")
local ZenLogger = require("common/zen_logger")
local logger = ZenLogger.new("library_navigation")

local M = {}
local _trace_sequence = 0

local function widgetName(widget)
    if not widget then return "nil" end
    return tostring(widget.name or widget.id or widget)
end

local function stackState(UIManager)
    local items = {}
    for i, entry in ipairs(UIManager._window_stack or {}) do
        local widget = entry and entry.widget
        local flags = ""
        if widget and widget.covers_fullscreen then flags = flags .. "F" end
        if widget and widget.invisible then flags = flags .. "I" end
        if widget and UIManager._dirty and UIManager._dirty[widget] then
            flags = flags .. "D"
        end
        items[#items + 1] = tostring(i) .. ":" .. widgetName(widget) .. "[" .. flags .. "]"
    end
    return table.concat(items, ",")
end

local function refreshState(UIManager)
    local items = {}
    for _i, refresh in ipairs(UIManager._refresh_stack or {}) do
        items[#items + 1] = tostring(refresh.mode)
    end
    return #items > 0 and table.concat(items, ",") or "none"
end

local function framebufferState(Screen)
    local bb = Screen and Screen.bb
    if not bb then return "nil" end

    local id = tostring(bb):gsub("%s+", "")
    local ok, state = pcall(function()
        local width = type(bb.getWidth) == "function" and bb:getWidth() or 0
        local height = type(bb.getHeight) == "function" and bb:getHeight() or 0
        local rotation = type(bb.getRotation) == "function" and bb:getRotation() or "?"
        local inverse = type(bb.getInverse) == "function" and bb:getInverse() or "?"
        local bb_type = type(bb.getType) == "function" and bb:getType() or "?"
        local count, total, minimum, maximum, hash = 0, 0, 255, 0, 0
        if width > 0 and height > 0 and type(bb.getPixel) == "function" then
            for row = 0, 4 do
                local y = math.floor((height - 1) * row / 4)
                for col = 0, 4 do
                    local x = math.floor((width - 1) * col / 4)
                    local pixel = bb:getPixel(x, y)
                    local color = pixel and type(pixel.getColor8) == "function"
                        and pixel:getColor8() or nil
                    local gray = color and tonumber(color.a)
                    if gray then
                        count = count + 1
                        total = total + gray
                        minimum = math.min(minimum, gray)
                        maximum = math.max(maximum, gray)
                        hash = (hash * 131 + gray + row * 17 + col) % 2147483647
                    end
                end
            end
        end
        local average = count > 0 and math.floor(total / count + 0.5) or -1
        return table.concat({
            id,
            tostring(width) .. "x" .. tostring(height),
            "type=" .. tostring(bb_type),
            "rot=" .. tostring(rotation),
            "inv=" .. tostring(inverse),
            "sample=" .. tostring(count) .. "," .. tostring(minimum)
                .. "," .. tostring(maximum) .. "," .. tostring(average)
                .. "," .. tostring(hash),
        }, ";")
    end)
    return ok and state or (id .. ";error=" .. tostring(state):gsub("%s+", "_"))
end

local function fullFramebufferState(Screen)
    if not (Screen and Screen.full_bb) then return "nil" end
    return framebufferState({ bb = Screen.full_bb })
end

local function callsite()
    local info = debug.getinfo(3, "Sl")
    if not info then return "unknown" end
    local source = tostring(info.short_src or info.source or "?")
    return source .. ":" .. tostring(info.currentline or 0)
end

local function traceLog(trace, phase, ...)
    if not trace then return end
    local elapsed = math.floor((trace.now() - trace.started_at) * 1000 + 0.5)
    local parts = {
        "FAST_RETURN_TRACE",
        trace.id,
        phase,
        "elapsed_ms=" .. tostring(elapsed),
    }
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    logger.info(table.concat(parts, " "))
end

local function installRefreshTrace(UIManager, trace)
    local originals = {}

    if type(UIManager.setDirty) == "function" then
        originals.setDirty = UIManager.setDirty
        UIManager.setDirty = function(self, widget, mode, ...)
            local result = originals.setDirty(self, widget, mode, ...)
            traceLog(trace, "setDirty",
                "widget=" .. widgetName(widget),
                "mode=" .. tostring(mode),
                "caller=" .. callsite(),
                "refreshes=" .. refreshState(self))
            return result
        end
    end
    if type(UIManager._refresh) == "function" then
        originals.refresh = UIManager._refresh
        UIManager._refresh = function(self, mode, ...)
            local result = originals.refresh(self, mode, ...)
            traceLog(trace, "queueRefresh",
                "mode=" .. tostring(mode),
                "caller=" .. callsite(),
                "refreshes=" .. refreshState(self))
            return result
        end
    end
    if type(UIManager._repaint) == "function" then
        originals.repaint = UIManager._repaint
        UIManager._repaint = function(self, ...)
            local should_trace = #(self._refresh_stack or {}) > 0
                or #(self._refresh_func_stack or {}) > 0
            if not should_trace then
                local start_idx = 1
                for i = #(self._window_stack or {}), 1, -1 do
                    local widget = self._window_stack[i].widget
                    if widget and widget.covers_fullscreen then
                        start_idx = i
                        break
                    end
                end
                for i = start_idx, #(self._window_stack or {}) do
                    local widget = self._window_stack[i].widget
                    if self._dirty and self._dirty[widget] then
                        should_trace = true
                        break
                    end
                end
            end
            if should_trace then
                traceLog(trace, "repaint:start",
                    "stack=" .. stackState(self),
                    "refreshes=" .. refreshState(self))
            end
            local started_at = trace.now()
            local result = originals.repaint(self, ...)
            if should_trace then
                traceLog(trace, "repaint:end",
                    "duration_ms=" .. tostring(math.floor(
                        (trace.now() - started_at) * 1000 + 0.5)),
                    "stack=" .. stackState(self),
                    "refreshes=" .. refreshState(self))
            end
            return result
        end
    end

    local ok_device, Device = pcall(require, "device")
    local Screen = ok_device and Device and Device.screen
    if type(UIManager.widgetRepaint) == "function" then
        originals.widgetRepaint = UIManager.widgetRepaint
        UIManager.widgetRepaint = function(self, widget, x, y, ...)
            traceLog(trace, "widgetRepaint:start",
                "widget=" .. widgetName(widget),
                "position=" .. tostring(x) .. "," .. tostring(y),
                "caller=" .. callsite(),
                "buffer=" .. framebufferState(Screen))
            local started_at = trace.now()
            local result = originals.widgetRepaint(self, widget, x, y, ...)
            traceLog(trace, "widgetRepaint:end",
                "widget=" .. widgetName(widget),
                "duration_ms=" .. tostring(math.floor(
                    (trace.now() - started_at) * 1000 + 0.5)),
                "buffer=" .. framebufferState(Screen))
            return result
        end
    end
    for _i, name in ipairs({ "show", "close" }) do
        local original = UIManager[name]
        if type(original) == "function" then
            local method_name = name
            local original_method = original
            originals[method_name] = original_method
            UIManager[method_name] = function(self, widget, mode, ...)
                traceLog(trace, "window:" .. method_name .. ":start",
                    "widget=" .. widgetName(widget),
                    "mode=" .. tostring(mode),
                    "caller=" .. callsite(),
                    "stack=" .. stackState(self))
                local result = original_method(self, widget, mode, ...)
                traceLog(trace, "window:" .. method_name .. ":end",
                    "widget=" .. widgetName(widget),
                    "stack=" .. stackState(self),
                    "refreshes=" .. refreshState(self))
                return result
            end
        end
    end
    if Screen and type(Screen.setRotationMode) == "function" then
        originals.setRotationMode = Screen.setRotationMode
        Screen.setRotationMode = function(self, mode, ...)
            local old_mode = type(self.getRotationMode) == "function"
                and self:getRotationMode() or nil
            traceLog(trace, "rotation:start",
                "old=" .. tostring(old_mode),
                "new=" .. tostring(mode),
                "caller=" .. callsite())
            local started_at = trace.now()
            local result = originals.setRotationMode(self, mode, ...)
            traceLog(trace, "rotation:end",
                "duration_ms=" .. tostring(math.floor((trace.now() - started_at) * 1000 + 0.5)),
                "current=" .. tostring(type(self.getRotationMode) == "function"
                    and self:getRotationMode() or nil),
                "size=" .. tostring(self:getWidth()) .. "x" .. tostring(self:getHeight()))
            return result
        end
    end
    if Screen then
        originals.screenRefresh = {}
        local function tracedScreenRefresh(name, original)
            return function(self, x, y, w, h, dither, ...)
                traceLog(trace, "screenCall:start",
                    "method=" .. name,
                    "region=" .. table.concat({
                        tostring(x), tostring(y), tostring(w), tostring(h),
                    }, ","),
                    "dither=" .. tostring(dither),
                    "caller=" .. callsite(),
                    "buffer=" .. framebufferState(self))
                local started_at = trace.now()
                local result = original(self, x, y, w, h, dither, ...)
                traceLog(trace, "screenCall:end",
                    "method=" .. name,
                    "duration_ms=" .. tostring(math.floor(
                        (trace.now() - started_at) * 1000 + 0.5)),
                    "buffer=" .. framebufferState(self))
                return result
            end
        end
        for _i, name in ipairs({
            "clear", "toggleNightMode", "setHWNightmode", "setHWRotation",
            "refreshA2", "refreshFast", "refreshFlashPartial", "refreshFlashUI",
            "refreshFull", "refreshNoMergePartial", "refreshNoMergeUI",
            "refreshPartial", "refreshUI", "refreshWaitForLast",
            "refreshA2Imp", "refreshFastImp", "refreshFlashPartialImp",
            "refreshFlashUIImp", "refreshFullImp", "refreshNoMergePartialImp",
            "refreshNoMergeUIImp", "refreshPartialImp", "refreshUIImp",
            "refreshWaitForLastImp",
        }) do
            local original = Screen[name]
            if type(original) == "function" then
                originals.screenRefresh[name] = {
                    raw = rawget(Screen, name),
                }
                Screen[name] = tracedScreenRefresh(name, original)
            end
        end
    end

    return function()
        if originals.setDirty then UIManager.setDirty = originals.setDirty end
        if originals.refresh then UIManager._refresh = originals.refresh end
        if originals.repaint then UIManager._repaint = originals.repaint end
        if originals.widgetRepaint then
            UIManager.widgetRepaint = originals.widgetRepaint
        end
        for _i, name in ipairs({ "show", "close" }) do
            if originals[name] then UIManager[name] = originals[name] end
        end
        if originals.setRotationMode then Screen.setRotationMode = originals.setRotationMode end
        for name, original in pairs(originals.screenRefresh or {}) do
            Screen[name] = original.raw
        end
    end
end

local function getRakuyomi()
    local Rakuyomi = rawget(_G, "__ZEN_UI_RAKUYOMI")
    if type(Rakuyomi) == "table" then return Rakuyomi end
    local ok, module = pcall(require, "modules/filebrowser/patches/rakuyomi")
    return ok and module or nil
end

local function isRakuyomiChapter(file)
    local Rakuyomi = getRakuyomi()
    if not (Rakuyomi and type(Rakuyomi.isChapterFile) == "function") then
        return false
    end
    local ok, is_chapter = pcall(Rakuyomi.isChapterFile, file)
    return ok and is_chapter == true
end

local function syncBookListCache(ui, file)
    if not (ui and ui.doc_settings and file) then return end
    local ok_bl, BookList = pcall(require, "ui/widget/booklist")
    if ok_bl and BookList and type(BookList.setBookInfoCache) == "function" then
        pcall(BookList.setBookInfoCache, file, ui.doc_settings)
    end
end

function M.restoreEnabled(plugin)
    local features = plugin and plugin.config and plugin.config.features
    return type(features) == "table" and features.restore_library_view == true
end

local function rakuyomiReturnToChapterListEnabled(plugin)
    local rakuyomi = plugin and plugin.config and plugin.config.rakuyomi
    if type(rakuyomi) ~= "table" then return true end
    if rakuyomi.return_to_chapter_list_on_exit ~= nil then
        return rakuyomi.return_to_chapter_list_on_exit ~= false
    end
    return true
end

function M.returnToRakuyomiReader(restore, plugin)
    if not rakuyomiReturnToChapterListEnabled(plugin) then
        return false
    end
    if not restore and not G_reader_settings:isTrue("allow_commaneer_filemanager") then
        return false
    end
    local ok, MangaReader = pcall(require, "MangaReader")
    if not ok or type(MangaReader) ~= "table"
            or MangaReader.is_showing ~= true
            or type(MangaReader.onReturn) ~= "function" then
        return false
    end
    MangaReader:onReturn()
    return true
end

local function raiseWidgets(widgets, mark_dirty)
    local UIManager = require("ui/uimanager")
    local stack = UIManager._window_stack
    if type(stack) ~= "table" then return false end

    local raised = false
    for _i, widget in ipairs(widgets or {}) do
        local found
        for i, entry in ipairs(stack) do
            if entry and entry.widget == widget then
                found = i
                break
            end
        end
        if found then
            local entry = table.remove(stack, found)
            table.insert(stack, entry)
            raised = true
        end
    end

    local top = widgets and widgets[#widgets]
    if raised and top and mark_dirty ~= false then
        if type(top._zen_status_refresh) == "function" then
            pcall(top._zen_status_refresh, top)
        end
        UIManager:setDirty(top, "ui")
    end
    return raised
end

local function withOffscreenBuffer(callback)
    local ok_device, Device = pcall(require, "device")
    local Screen = ok_device and Device and Device.screen
    local original = Screen and Screen.bb
    if not original or type(original.getWidth) ~= "function"
            or type(original.getHeight) ~= "function"
            or type(original.getType) ~= "function" then
        callback()
        return false
    end

    local ok_bb, Blitbuffer = pcall(require, "ffi/blitbuffer")
    if not ok_bb or type(Blitbuffer.new) ~= "function" then
        callback()
        return false
    end

    local function newBufferLike(source)
        local rotation = type(source.getRotation) == "function"
            and source:getRotation() or 0
        local width, height = source:getWidth(), source:getHeight()
        if rotation % 2 == 1 then
            width, height = height, width
        end
        local ok_new, buffer = pcall(Blitbuffer.new, width, height, source:getType())
        if not ok_new or not buffer then return nil end
        if type(buffer.setRotation) == "function" then
            buffer:setRotation(rotation)
        end
        if type(source.getInverse) == "function"
                and type(buffer.setInverse) == "function" then
            buffer:setInverse(source:getInverse())
        end
        return buffer
    end

    local scratch = newBufferLike(original)
    if not scratch then
        callback()
        return false
    end

    local original_full = Screen.full_bb
    local scratch_full
    if original_full then
        scratch_full = newBufferLike(original_full)
        if not scratch_full then
            if type(scratch.free) == "function" then
                pcall(scratch.free, scratch)
            end
            callback()
            return false
        end
    end

    Screen.full_bb = scratch_full
    Screen.bb = scratch
    local ok, err = pcall(callback)
    Screen.bb = original
    Screen.full_bb = original_full
    if type(scratch.free) == "function" then
        pcall(scratch.free, scratch)
    end
    if scratch_full and type(scratch_full.free) == "function" then
        pcall(scratch_full.free, scratch_full)
    end
    if not ok then error(err) end
    return true
end

local function startFastReturn(ui, file, target_tab)
    local open = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_FAST_RETURN")
    if type(open) ~= "function" then return false end

    _trace_sequence = _trace_sequence + 1
    local trace = {
        id = tostring(math.floor(ZenLogger.now() * 1000)) .. "-" .. tostring(_trace_sequence),
        now = ZenLogger.now,
        started_at = ZenLogger.now(),
    }
    local UIManager = require("ui/uimanager")
    local ok_device, Device = pcall(require, "device")
    local Screen = ok_device and Device and Device.screen
    local restore_trace = installRefreshTrace(UIManager, trace)
    traceLog(trace, "request",
        "target=" .. tostring(target_tab),
        "file=" .. tostring(file),
        "stack=" .. stackState(UIManager),
        "refreshes=" .. refreshState(UIManager),
        "buffer=" .. framebufferState(Screen))

    local open_refresh_count = #(UIManager._refresh_stack or {})
    local open_refresh_func_count = #(UIManager._refresh_func_stack or {})
    local ok_open, fast_return = pcall(open, target_tab, trace)
    if not ok_open then
        traceLog(trace, "open:error", tostring(fast_return))
        restore_trace()
        error(fast_return)
    end
    if type(fast_return) ~= "table"
            or type(fast_return.widgets) ~= "table"
            or #fast_return.widgets == 0 then
        traceLog(trace, "open:unsupported", "target=" .. tostring(target_tab))
        restore_trace()
        return false
    end

    fast_return.trace = trace
    traceLog(trace, "open:complete",
        "tab=" .. tostring(fast_return.tab_id),
        "widgets=" .. tostring(#fast_return.widgets),
        "stack=" .. stackState(UIManager),
        "refreshes=" .. refreshState(UIManager),
        "buffer=" .. framebufferState(Screen))
    for _i, widget in ipairs(fast_return.widgets) do
        UIManager._dirty[widget] = nil
    end
    for i = #(UIManager._refresh_stack or {}), open_refresh_count + 1, -1 do
        UIManager._refresh_stack[i] = nil
    end
    for i = #(UIManager._refresh_func_stack or {}), open_refresh_func_count + 1, -1 do
        UIManager._refresh_func_stack[i] = nil
    end
    raiseWidgets(fast_return.widgets, false)
    traceLog(trace, "view:initialPaintSuppressed",
        "stack=" .. stackState(UIManager),
        "refreshes=" .. refreshState(UIManager))
    traceLog(trace, "view:raised",
        "stack=" .. stackState(UIManager),
        "refreshes=" .. refreshState(UIManager),
        "buffer=" .. framebufferState(Screen))
    -- Finish the standalone view and hidden FM setup before one screen repaint.
    local schedule = "nextTick"
    UIManager[schedule](UIManager, function()
        if not (ui and ui.document and ui.document.file == file) then
            traceLog(trace, "rebuild:cancelled")
            restore_trace()
            return
        end
        traceLog(trace, "rebuild:callback",
            "stack=" .. stackState(UIManager),
            "refreshes=" .. refreshState(UIManager),
            "buffer=" .. framebufferState(Screen))
        if type(UIManager.waitForVSync) == "function" then
            local vsync_started_at = trace.now()
            traceLog(trace, "vsync:start")
            UIManager:waitForVSync()
            traceLog(trace, "vsync:end",
                "duration_ms=" .. tostring(math.floor(
                    (trace.now() - vsync_started_at) * 1000 + 0.5)),
                "buffer=" .. framebufferState(Screen))
        end

        _G.__ZEN_UI_FAST_RETURN_REBUILDING = true
        _G.__ZEN_UI_FAST_RETURN = fast_return
        _G.__ZEN_UI_LIBRARY_STATE = nil

        local ok, err = pcall(function()
            local refresh_count = #(UIManager._refresh_stack or {})
            local refresh_func_count = #(UIManager._refresh_func_stack or {})
            local fm_started_at
            local file_manager_isolated = withOffscreenBuffer(function()
                traceLog(trace, "hiddenWork:offscreenStart",
                    "buffer=" .. framebufferState(Screen),
                    "full_buffer=" .. fullFramebufferState(Screen))
                local close_started_at = trace.now()
                traceLog(trace, "readerClose:start",
                    "stack=" .. stackState(UIManager),
                    "refreshes=" .. refreshState(UIManager),
                    "buffer=" .. framebufferState(Screen))
                ui:onClose(false)
                traceLog(trace, "readerClose:end",
                    "duration_ms=" .. tostring(math.floor(
                        (trace.now() - close_started_at) * 1000 + 0.5)),
                    "stack=" .. stackState(UIManager),
                    "refreshes=" .. refreshState(UIManager),
                    "buffer=" .. framebufferState(Screen))
                if type(ui.showFileManager) ~= "function" then return end

                fm_started_at = trace.now()
                traceLog(trace, "fileManager:start",
                    "stack=" .. stackState(UIManager),
                    "refreshes=" .. refreshState(UIManager),
                    "buffer=" .. framebufferState(Screen))
                ui:showFileManager(file)
                traceLog(trace, "fileManager:offscreenEnd",
                    "buffer=" .. framebufferState(Screen),
                    "full_buffer=" .. fullFramebufferState(Screen))
            end)
            traceLog(trace, "hiddenWork:end",
                "offscreen=" .. tostring(file_manager_isolated),
                "buffer=" .. framebufferState(Screen),
                "full_buffer=" .. fullFramebufferState(Screen))
            if fm_started_at then
                traceLog(trace, "fileManager:end",
                    "duration_ms=" .. tostring(math.floor(
                        (trace.now() - fm_started_at) * 1000 + 0.5)),
                    "offscreen=" .. tostring(file_manager_isolated),
                    "stack=" .. stackState(UIManager),
                    "refreshes=" .. refreshState(UIManager),
                    "buffer=" .. framebufferState(Screen),
                    "full_buffer=" .. fullFramebufferState(Screen))
            end
            for i = #(UIManager._refresh_stack or {}), refresh_count + 1, -1 do
                UIManager._refresh_stack[i] = nil
            end
            for i = #(UIManager._refresh_func_stack or {}), refresh_func_count + 1, -1 do
                UIManager._refresh_func_stack[i] = nil
            end
            traceLog(trace, "hiddenWork:refreshesDiscarded",
                "refreshes=" .. refreshState(UIManager),
                "buffer=" .. framebufferState(Screen))
            raiseWidgets(fast_return.widgets, false)
            traceLog(trace, "view:reraised",
                "stack=" .. stackState(UIManager),
                "refreshes=" .. refreshState(UIManager),
                "buffer=" .. framebufferState(Screen),
                "full_buffer=" .. fullFramebufferState(Screen))
            local restore_started_at = trace.now()
            local top = fast_return.widgets[#fast_return.widgets]
            local restored = top ~= nil
            if top then
                UIManager:setDirty(top, "ui")
                if type(UIManager.forceRePaint) == "function" then
                    UIManager:forceRePaint()
                end
            end
            traceLog(trace, "view:bufferRestored",
                "restored=" .. tostring(restored),
                "offscreen=" .. tostring(file_manager_isolated),
                "duration_ms=" .. tostring(math.floor(
                    (trace.now() - restore_started_at) * 1000 + 0.5)),
                "stack=" .. stackState(UIManager),
                "refreshes=" .. refreshState(UIManager),
                "buffer=" .. framebufferState(Screen))
        end)

        _G.__ZEN_UI_FAST_RETURN = nil
        _G.__ZEN_UI_FAST_RETURN_REBUILDING = nil
        if not ok then
            traceLog(trace, "rebuild:error", tostring(err))
            restore_trace()
            error(err)
        end
        traceLog(trace, "rebuild:complete",
            "stack=" .. stackState(UIManager),
            "refreshes=" .. refreshState(UIManager),
            "buffer=" .. framebufferState(Screen))
        if type(UIManager.scheduleIn) == "function" then
            local checkpoints = { 0.25, 0.75, 1.5, 3, 6, 9, 12 }
            for i, checkpoint in ipairs(checkpoints) do
                local delay = checkpoint
                local final = i == #checkpoints
                UIManager:scheduleIn(delay, function()
                    traceLog(trace, final and "postBuildTrace:complete" or "postBuildTrace:checkpoint",
                        "delay_s=" .. tostring(delay),
                        "stack=" .. stackState(UIManager),
                        "refreshes=" .. refreshState(UIManager),
                        "tasks=" .. tostring(#(UIManager._task_queue or {})),
                        "buffer=" .. framebufferState(Screen))
                    if final then restore_trace() end
                end)
            end
        else
            restore_trace()
        end
    end)
    traceLog(trace, "rebuild:scheduled", "scheduler=" .. schedule)
    return true
end

function M.showFromReader(ui, plugin, opts)
    if not ui or not ui.document then return false end

    opts = type(opts) == "table" and opts or {}
    local file = ui.document.file
    local open_home = opts.open_home == true
    local target_tab = opts.target_tab
    local target_folder = opts.target_folder
    local return_to_default = not open_home and target_tab == nil and target_folder == nil
    local restore = M.restoreEnabled(plugin)
    local outside_home = file and not paths.isInHomeDir(file)
    _G.__ZEN_UI_LAST_READ_FILE = file
    syncBookListCache(ui, file)

    ui:handleEvent(require("ui/event"):new("CloseConfigMenu"))
    if M.returnToRakuyomiReader(restore, plugin) then
        return true
    end

    local fast_target
    if open_home then
        fast_target = "home"
    elseif target_tab then
        fast_target = target_tab
    end
    if not target_folder and not outside_home and not isRakuyomiChapter(file)
            and startFastReturn(ui, file, fast_target) then
        return true
    end

    ui:onClose()
    if type(ui.showFileManager) == "function" then
        if open_home then
            _G.__ZEN_UI_OPEN_HOME_AFTER_FILEMANAGER = true
        elseif target_tab then
            _G.__ZEN_UI_OPEN_TARGET_TAB = target_tab
        elseif target_folder then
            _G.__ZEN_UI_OPEN_TARGET_FOLDER = target_folder
        elseif return_to_default and not outside_home then
            _G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB = true
        elseif not restore and not outside_home then
            _G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB = true
        elseif outside_home then
            _G.__ZEN_UI_KEEP_BOOK_LOCATION = true
        end
        ui:showFileManager(file)
    end
    return true
end

return M

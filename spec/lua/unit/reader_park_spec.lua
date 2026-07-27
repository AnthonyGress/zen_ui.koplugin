describe("reader parking", function()
    local Park
    local UIManager
    local ReaderUI
    local FileManager
    local reader
    local home
    local now
    local next_ticks
    local scheduled
    local dirty

    before_each(function()
        now = 0
        next_ticks = {}
        scheduled = {}
        dirty = {}
        home = { name = "home", dimen = { x = 0, y = 0, w = 600, h = 800 } }
        reader = {
            name = "ReaderUI",
            document = { file = "/library/Book.epub" },
            doc_settings = {},
        }
        ReaderUI = { instance = reader }
        FileManager = { instance = nil }
        UIManager = {
            _window_stack = {
                { widget = home },
                { widget = reader },
            },
            _dirty = {},
            _refresh_stack = {},
            _refresh_func_stack = {},
            setDirty = function(_, widget, mode)
                dirty[#dirty + 1] = { widget = widget, mode = mode }
            end,
            nextTick = function(_, callback)
                next_ticks[#next_ticks + 1] = callback
            end,
            scheduleIn = function(_, delay, callback)
                scheduled[#scheduled + 1] = { delay = delay, callback = callback }
            end,
            unschedule = function(_, callback)
                for i = #scheduled, 1, -1 do
                    if scheduled[i].callback == callback then
                        table.remove(scheduled, i)
                    end
                end
            end,
            sendEvent = function() end,
        }
        ZenSpec.replace("ui/uimanager", UIManager)
        ZenSpec.replace("ui/event", {
            new = function(_, name) return { handler = "on" .. name } end,
        })
        ZenSpec.replace("apps/reader/readerui", ReaderUI)
        ZenSpec.replace("apps/filemanager/filemanager", FileManager)
        ZenSpec.replace("ui/widget/booklist", {
            setBookInfoCache = function(file)
                reader.cached_file = file
            end,
        })
        ZenSpec.replace("common/zen_logger", {
            now = function() return now end,
            new = function()
                return {
                    info = function() end,
                    warn = function() end,
                    perf = function() end,
                }
            end,
        })
        ZenSpec.unload("common/reader_park")
        Park = require("common/reader_park")
    end)

    after_each(function()
        for _i, name in ipairs({
            "__ZEN_UI_FAST_RETURN", "__ZEN_UI_FAST_RETURN_REBUILDING",
            "__ZEN_UI_RETAIN_LIBRARY_VIEW",
        }) do
            _G[name] = nil
        end
    end)

    local function retainedView(refresh)
        return {
            tab_id = "home",
            widgets = { home },
            retained = true,
            refresh = refresh,
        }
    end

    it("raises Home immediately and saves progress on the next tick", function()
        local refreshed = 0
        function reader:handleEvent(event)
            self.events = self.events or {}
            self.events[#self.events + 1] = event.handler
        end
        function reader:saveSettings()
            self.saved = true
        end

        assert.is_true(Park.park(reader, retainedView(function()
            refreshed = refreshed + 1
        end)))

        assert.is_true(Park.isParked())
        assert.are.equal(home, UIManager._window_stack[#UIManager._window_stack].widget)
        assert.are.equal(home, dirty[1].widget)
        assert.is_function(dirty[1].mode)
        assert.are.same({ "onCloseReaderMenu", "onCloseConfigMenu" }, reader.events)
        assert.is_nil(reader.closed)
        assert.are.equal(10, scheduled[1].delay)

        next_ticks[1]()
        assert.is_true(reader.saved)
        assert.are.equal("/library/Book.epub", reader.cached_file)
        assert.are.equal(1, refreshed)
    end)

    it("reopens the same live Reader without loading the document again", function()
        function reader:handleEvent() end
        Park.park(reader, retainedView())
        dirty = {}

        assert.is_true(Park.open("/library/Book.epub"))

        assert.is_false(Park.isParked())
        assert.are.equal(reader, UIManager._window_stack[#UIManager._window_stack].widget)
        assert.are.equal(reader, dirty[1].widget)
        assert.are.equal("full", dirty[1].mode)
        assert.are.equal(0, #scheduled)
    end)

    it("closes Reader behind Home when FileManager is needed", function()
        function reader:handleEvent() end
        function reader:onClose(full_refresh)
            assert.is_false(full_refresh)
            self.document = nil
            ReaderUI.instance = nil
            for i = #UIManager._window_stack, 1, -1 do
                if UIManager._window_stack[i].widget == self then
                    table.remove(UIManager._window_stack, i)
                end
            end
            UIManager._refresh_stack[#UIManager._refresh_stack + 1] = { mode = "full" }
        end
        function reader:showFileManager()
            assert.is_table(_G.__ZEN_UI_FAST_RETURN)
            local fm = { name = "FileManager" }
            FileManager.instance = fm
            UIManager._window_stack[#UIManager._window_stack + 1] = { widget = fm }
            UIManager._dirty[fm] = true
            UIManager._refresh_stack[#UIManager._refresh_stack + 1] = { mode = "ui" }
            _G.__ZEN_UI_FAST_RETURN = nil
        end
        _G.__ZEN_UI_RETAIN_LIBRARY_VIEW = retainedView()
        Park.park(reader, _G.__ZEN_UI_RETAIN_LIBRARY_VIEW)
        dirty = {}

        assert.is_true(Park.ensureFileManager("test"))

        assert.is_false(Park.isParked())
        assert.are.equal(home, UIManager._window_stack[#UIManager._window_stack].widget)
        assert.is_nil(UIManager._dirty[FileManager.instance])
        assert.are.same({}, UIManager._refresh_stack)
        assert.are.equal(home, dirty[1].widget)
        assert.is_function(dirty[1].mode)
        assert.is_nil(_G.__ZEN_UI_FAST_RETURN)
        assert.is_nil(_G.__ZEN_UI_FAST_RETURN_REBUILDING)
        assert.is_nil(_G.__ZEN_UI_RETAIN_LIBRARY_VIEW)
        assert.is_true(Park.isFinishing())

        next_ticks[#next_ticks]()
        assert.is_false(Park.isFinishing())
    end)

    it("finishes the parked close after thirty seconds of input idle", function()
        local closed = 0
        function reader:handleEvent() end
        function reader:onClose()
            closed = closed + 1
            self.document = nil
            ReaderUI.instance = nil
        end
        function reader:showFileManager() end
        Park.park(reader, retainedView())

        now = 30
        scheduled[1].callback()

        assert.are.equal(1, closed)
        assert.is_false(Park.isParked())
    end)
end)

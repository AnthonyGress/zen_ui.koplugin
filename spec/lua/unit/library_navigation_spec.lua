local Navigation = require("common/library_navigation")

describe("library navigation", function()
    before_each(function()
        _G.__ZEN_UI_NAVBAR_OPEN_FAST_RETURN = nil
        _G.__ZEN_UI_FAST_RETURN = nil
        _G.__ZEN_UI_FAST_RETURN_REBUILDING = nil
        _G.__ZEN_UI_RAKUYOMI = {
            isChapterFile = function() return false end,
        }
        _G.G_reader_settings = ZenSpec.memorySettings({
            allow_commaneer_filemanager = true,
            home_dir = "/library",
        })
        ZenSpec.replace("ui/event", { new = function(_, name) return { name = name } end })
        ZenSpec.replace("ui/widget/booklist", { setBookInfoCache = function() end })
        ZenSpec.replace("config/manager", { get = function() return {} end })
        ZenSpec.replace("MangaReader", { is_showing = false })
        ZenSpec.unload("common/paths")
        ZenSpec.unload("common/library_navigation")
        Navigation = require("common/library_navigation")
    end)

    after_each(function()
        _G.__ZEN_UI_NAVBAR_OPEN_FAST_RETURN = nil
        _G.__ZEN_UI_FAST_RETURN = nil
        _G.__ZEN_UI_FAST_RETURN_REBUILDING = nil
        _G.__ZEN_UI_RAKUYOMI = nil
    end)

    it("returns to the file manager with a requested target tab", function()
        local closed, shown, event
        local ui = {
            document = { file = "/library/Book.epub" },
            doc_settings = {},
            handleEvent = function(_, value) event = value end,
            onClose = function() closed = true end,
            showFileManager = function(_, file) shown = file end,
        }
        local plugin = { config = { features = { restore_library_view = true } } }

        assert.is_true(Navigation.showFromReader(ui, plugin, { target_tab = "history" }))
        assert.are.equal("CloseConfigMenu", event.name)
        assert.is_true(closed)
        assert.are.equal("/library/Book.epub", shown)
        assert.are.equal("history", _G.__ZEN_UI_OPEN_TARGET_TAB)
    end)

    it("keeps a book outside home instead of forcing the default tab", function()
        local ui = {
            document = { file = "/outside/Book.epub" },
            doc_settings = {},
            handleEvent = function() end,
            onClose = function() end,
            showFileManager = function() end,
        }
        local plugin = { config = { features = { restore_library_view = false } } }
        assert.is_true(Navigation.showFromReader(ui, plugin))
        assert.is_true(_G.__ZEN_UI_KEEP_BOOK_LOCATION)
        assert.is_nil(_G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB)
    end)

    it("uses explicit home and folder targets before restore behavior", function()
        local shown = 0
        local ui = {
            document = { file = "/library/Book.epub" },
            doc_settings = {},
            handleEvent = function() end,
            onClose = function() end,
            showFileManager = function() shown = shown + 1 end,
        }
        local plugin = { config = { features = { restore_library_view = false } } }
        Navigation.showFromReader(ui, plugin, { open_home = true, target_folder = "/library/Series" })
        assert.are.equal(1, shown)
        assert.is_true(_G.__ZEN_UI_OPEN_HOME_AFTER_FILEMANAGER)
        assert.is_nil(_G.__ZEN_UI_OPEN_TARGET_FOLDER)
    end)

    it("returns to Rakuyomi instead of closing the reader when configured and available", function()
        local returns = 0
        ZenSpec.replace("MangaReader", {
            is_showing = true,
            onReturn = function() returns = returns + 1 end,
        })
        local ui = {
            document = { file = "/library/Book.epub" },
            doc_settings = {},
            handleEvent = function() end,
            onClose = function() error("reader should remain open") end,
        }
        local plugin = { config = {
            features = { restore_library_view = true },
            rakuyomi = { return_to_chapter_list_on_exit = true },
        } }
        assert.is_true(Navigation.showFromReader(ui, plugin))
        assert.are.equal(1, returns)
    end)

    it("suppresses the incomplete shell before rebuilding the file manager", function()
        local scheduled, closed, shown, dirty, dirty_calls, refresh_settled
        local silent_paints, forced_repaints, dirty_modes
        local library = {}
        local original_bb = {
            getWidth = function() return 600 end,
            getHeight = function() return 800 end,
            getType = function() return 1 end,
            getRotation = function() return 0 end,
            getInverse = function() return 0 end,
        }
        local original_full_bb = {
            getWidth = function() return 620 end,
            getHeight = function() return 820 end,
            getType = function() return 1 end,
            getRotation = function() return 0 end,
            getInverse = function() return 0 end,
        }
        local scratch_bb = {
            setRotation = function(_, value) assert.are.equal(0, value) end,
            setInverse = function(_, value) assert.are.equal(0, value) end,
            free = function(self) self.freed = true end,
        }
        local scratch_full_bb = {
            setRotation = function(_, value) assert.are.equal(0, value) end,
            setInverse = function(_, value) assert.are.equal(0, value) end,
            free = function(self) self.freed = true end,
        }
        local Screen = { bb = original_bb, full_bb = original_full_bb }
        ZenSpec.replace("device", { screen = Screen })
        ZenSpec.replace("ffi/blitbuffer", {
            new = function(width, height, bb_type)
                assert.are.equal(1, bb_type)
                if width == 600 then
                    assert.are.equal(800, height)
                    return scratch_bb
                end
                assert.are.equal(620, width)
                assert.are.equal(820, height)
                return scratch_full_bb
            end,
        })
        local UIManager
        UIManager = {
            _window_stack = {
                { widget = library },
            },
            _dirty = {},
            _refresh_stack = {},
            _refresh_func_stack = {},
            setDirty = function(_, widget, mode)
                dirty = widget
                dirty_calls = (dirty_calls or 0) + 1
                dirty_modes = dirty_modes or {}
                table.insert(dirty_modes, mode)
            end,
            widgetRepaint = function(_, widget, x, y)
                assert.are.equal(library, widget)
                assert.are.equal(0, x)
                assert.are.equal(0, y)
                silent_paints = (silent_paints or 0) + 1
                UIManager._dirty[widget] = true
                table.insert(UIManager._refresh_stack, { mode = "ui" })
                table.insert(UIManager._refresh_func_stack, function() end)
            end,
            forceRePaint = function()
                forced_repaints = (forced_repaints or 0) + 1
            end,
            waitForVSync = function() refresh_settled = true end,
            nextTick = function(_, callback) scheduled = callback end,
        }
        ZenSpec.replace("ui/uimanager", UIManager)
        _G.__ZEN_UI_NAVBAR_OPEN_FAST_RETURN = function(tab_id)
            assert.is_nil(tab_id)
            UIManager._dirty[library] = true
            table.insert(UIManager._refresh_stack, { mode = "ui" })
            table.insert(UIManager._refresh_func_stack, function() end)
            return { tab_id = "home", widgets = { library } }
        end

        local ui = {
            document = { file = "/library/Book.epub" },
            doc_settings = {},
            handleEvent = function() end,
            onClose = function(_, full_refresh)
                assert.is_false(full_refresh)
                assert.is_true(refresh_settled)
                assert.are.equal(scratch_bb, Screen.bb)
                assert.are.equal(scratch_full_bb, Screen.full_bb)
                closed = true
            end,
            showFileManager = function(_, file)
                shown = file
                assert.are.equal("home", _G.__ZEN_UI_FAST_RETURN.tab_id)
                assert.are.equal(scratch_bb, Screen.bb)
                assert.are.equal(scratch_full_bb, Screen.full_bb)
                table.insert(UIManager._refresh_stack, { mode = "ui" })
                table.insert(UIManager._refresh_func_stack, function() end)
            end,
        }
        assert.is_true(Navigation.showFromReader(ui, {
            config = { features = { restore_library_view = true } },
        }))
        assert.is_false(closed == true)
        assert.is_nil(dirty)
        assert.is_nil(UIManager._dirty[library])
        assert.are.same({}, UIManager._refresh_stack)
        assert.are.same({}, UIManager._refresh_func_stack)
        assert.is_function(scheduled)

        scheduled()
        assert.is_true(closed)
        assert.are.equal("/library/Book.epub", shown)
        assert.is_nil(_G.__ZEN_UI_FAST_RETURN)
        assert.is_nil(_G.__ZEN_UI_FAST_RETURN_REBUILDING)
        assert.are.equal(1, dirty_calls)
        assert.are.same({ "ui" }, dirty_modes)
        assert.are.same({}, UIManager._refresh_stack)
        assert.are.same({}, UIManager._refresh_func_stack)
        assert.is_nil(UIManager._dirty[library])
        assert.are.equal(library, UIManager._window_stack[#UIManager._window_stack].widget)
        assert.are.equal(original_bb, Screen.bb)
        assert.are.equal(original_full_bb, Screen.full_bb)
        assert.is_true(scratch_bb.freed)
        assert.is_true(scratch_full_bb.freed)
        assert.is_nil(silent_paints)
        assert.are.equal(1, forced_repaints)
    end)

    it("does not fast-return Rakuyomi chapters when their own return is disabled", function()
        local closed, fast_calls
        _G.__ZEN_UI_RAKUYOMI.isChapterFile = function() return true end
        _G.__ZEN_UI_NAVBAR_OPEN_FAST_RETURN = function()
            fast_calls = (fast_calls or 0) + 1
        end
        ZenSpec.replace("MangaReader", {
            is_showing = true,
            onReturn = function() error("Rakuyomi return is disabled") end,
        })

        local ui = {
            document = { file = "/library/chapter.cbz" },
            doc_settings = {},
            handleEvent = function() end,
            onClose = function() closed = true end,
            showFileManager = function() end,
        }
        assert.is_true(Navigation.showFromReader(ui, { config = {
            features = { restore_library_view = false },
            rakuyomi = { return_to_chapter_list_on_exit = false },
        } }))
        assert.is_true(closed)
        assert.is_nil(fast_calls)
    end)
end)

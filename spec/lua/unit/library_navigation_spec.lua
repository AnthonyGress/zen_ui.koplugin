local Navigation

describe("library navigation", function()
    before_each(function()
        for _i, name in ipairs({
            "__ZEN_UI_NAVBAR_OPEN_FAST_RETURN", "__ZEN_UI_FAST_RETURN",
            "__ZEN_UI_FAST_RETURN_REBUILDING", "__ZEN_UI_RETAIN_LIBRARY_VIEW",
            "__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB", "__ZEN_UI_OPEN_TARGET_TAB",
            "__ZEN_UI_OPEN_TARGET_FOLDER", "__ZEN_UI_OPEN_HOME_AFTER_FILEMANAGER",
            "__ZEN_UI_KEEP_BOOK_LOCATION", "__ZEN_UI_LAST_READ_FILE",
        }) do
            _G[name] = nil
        end
        _G.__ZEN_UI_RAKUYOMI = {
            isChapterFile = function() return false end,
        }
        _G.G_reader_settings = ZenSpec.memorySettings({
            allow_commaneer_filemanager = true,
            home_dir = "/library",
        })
        ZenSpec.replace("ui/event", {
            new = function(_, name) return { name = name } end,
        })
        ZenSpec.replace("config/manager", { get = function() return {} end })
        ZenSpec.replace("MangaReader", { is_showing = false })
        ZenSpec.unload("common/paths")
        ZenSpec.unload("common/library_navigation")
        Navigation = require("common/library_navigation")
    end)

    after_each(function()
        _G.__ZEN_UI_RAKUYOMI = nil
    end)

    local function reader(file)
        local state = {
            document = { file = file or "/library/Book.epub" },
            doc_settings = {},
            tearing_down = false,
        }
        function state:handleEvent(event)
            assert.is_true(self.tearing_down)
            self.event = event
        end
        function state:onClose()
            assert.is_false(self.tearing_down)
            self.closed = true
        end
        function state:showFileManager(file_path)
            self.shown = file_path
        end
        return state
    end

    it("returns to the file manager with a requested non-retained tab", function()
        local ui = reader()
        local plugin = { config = { features = { restore_library_view = true } } }

        assert.is_true(Navigation.showFromReader(ui, plugin, { target_tab = "history" }))
        assert.are.equal("CloseConfigMenu", ui.event.name)
        assert.is_true(ui.closed)
        assert.are.equal("/library/Book.epub", ui.shown)
        assert.are.equal("history", _G.__ZEN_UI_OPEN_TARGET_TAB)
    end)

    it("keeps a book outside home instead of forcing the default tab", function()
        local ui = reader("/outside/Book.epub")
        local plugin = { config = { features = { restore_library_view = false } } }

        Navigation.showFromReader(ui, plugin)

        assert.is_true(_G.__ZEN_UI_KEEP_BOOK_LOCATION)
        assert.is_nil(_G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB)
    end)

    it("forces a file-manager-backed default when no retained view exists", function()
        _G.__ZEN_UI_NAVBAR_OPEN_FAST_RETURN = function() return false end
        local ui = reader()

        Navigation.showFromReader(ui, {
            config = { features = { restore_library_view = true } },
        })

        assert.is_true(ui.closed)
        assert.are.equal("/library/Book.epub", ui.shown)
        assert.is_true(_G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB)
    end)

    it("uses explicit home before a simultaneous folder target", function()
        local ui = reader()
        Navigation.showFromReader(ui, {
            config = { features = { restore_library_view = false } },
        }, {
            open_home = true,
            target_folder = "/library/Series",
        })

        assert.is_true(_G.__ZEN_UI_OPEN_HOME_AFTER_FILEMANAGER)
        assert.is_nil(_G.__ZEN_UI_OPEN_TARGET_FOLDER)
    end)

    it("returns to Rakuyomi instead of closing Reader when available", function()
        local returns = 0
        ZenSpec.replace("MangaReader", {
            is_showing = true,
            onReturn = function() returns = returns + 1 end,
        })
        local ui = reader()

        Navigation.showFromReader(ui, {
            config = {
                features = { restore_library_view = true },
                rakuyomi = { return_to_chapter_list_on_exit = true },
            },
        })

        assert.are.equal(1, returns)
        assert.is_nil(ui.closed)
    end)

    it("parks Reader under a retained Home without closing it", function()
        local ui = reader()
        local home = {}
        local parked
        _G.__ZEN_UI_NAVBAR_OPEN_FAST_RETURN = function(tab_id)
            assert.is_nil(tab_id)
            return {
                tab_id = "home",
                widgets = { home },
                retained = true,
            }
        end
        ZenSpec.replace("common/reader_park", {
            park = function(received_ui, view)
                assert.are.equal(ui, received_ui)
                assert.are.same({ home }, view.widgets)
                parked = true
                return true
            end,
        })

        assert.is_true(Navigation.showFromReader(ui, {
            config = { features = { restore_library_view = true } },
        }))

        assert.is_true(parked)
        assert.is_nil(ui.closed)
        assert.is_nil(ui.shown)
        assert.are.equal("/library/Book.epub", _G.__ZEN_UI_LAST_READ_FILE)
    end)

    it("falls back when the requested view was not retained", function()
        local ui = reader()
        _G.__ZEN_UI_NAVBAR_OPEN_FAST_RETURN = function()
            return { tab_id = "home", widgets = { {} } }
        end
        ZenSpec.replace("common/reader_park", {
            park = function() error("non-retained view must not park") end,
        })

        Navigation.showFromReader(ui, {
            config = { features = { restore_library_view = true } },
        })

        assert.is_true(ui.closed)
        assert.are.equal("/library/Book.epub", ui.shown)
    end)

    it("does not park Rakuyomi chapters when their own return is disabled", function()
        _G.__ZEN_UI_RAKUYOMI.isChapterFile = function() return true end
        _G.__ZEN_UI_NAVBAR_OPEN_FAST_RETURN = function()
            error("Rakuyomi chapter must not use retained Home")
        end
        ZenSpec.replace("MangaReader", {
            is_showing = true,
            onReturn = function() error("Rakuyomi return is disabled") end,
        })
        local ui = reader("/library/chapter.cbz")

        Navigation.showFromReader(ui, { config = {
            features = { restore_library_view = false },
            rakuyomi = { return_to_chapter_list_on_exit = false },
        } })

        assert.is_true(ui.closed)
    end)
end)

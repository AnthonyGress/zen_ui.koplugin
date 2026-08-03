local Navigation

describe("library navigation", function()
    before_each(function()
        for _i, name in ipairs({
            "__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB", "__ZEN_UI_OPEN_TARGET_TAB",
            "__ZEN_UI_OPEN_TARGET_FOLDER", "__ZEN_UI_OPEN_HOME_AFTER_FILEMANAGER",
            "__ZEN_UI_KEEP_BOOK_LOCATION", "__ZEN_UI_LAST_READ_FILE",
        }) do
            _G[name] = nil
        end
        _G.G_reader_settings = ZenSpec.memorySettings({
            allow_commaneer_filemanager = true,
            home_dir = "/library",
        })
        ZenSpec.replace("ui/event", {
            new = function(_, name) return { name = name } end,
        })
        ZenSpec.replace("config/manager", { get = function() return {} end })
        ZenSpec.replace("MangaReader", { is_showing = false })
        ZenSpec.replace("common/utils", {
            closeWidgetsAbove = function(anchor)
                assert.is_true(anchor.tearing_down)
                anchor.overlays_closed = true
            end,
        })
        ZenSpec.unload("common/paths")
        ZenSpec.unload("common/library_navigation")
        Navigation = require("common/library_navigation")
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
            assert.is_true(self.overlays_closed)
            self.closed = true
        end
        function state:showFileManager(file_path)
            self.shown = file_path
        end
        return state
    end

    it("closes reader overlays before rebuilding the library", function()
        local ui = reader()
        local dialog = {}
        ui.dialog = dialog
        ZenSpec.replace("common/utils", {
            closeWidgetsAbove = function(anchor)
                assert.are.equal(dialog, anchor)
                assert.is_true(ui.tearing_down)
                ui.overlays_closed = true
            end,
        })

        Navigation.showFromReader(ui, {
            config = { features = { restore_library_view = false } },
        })

        assert.is_true(ui.closed)
        assert.is_true(_G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB)
    end)

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

    it("closes Reader and rebuilds the configured default view", function()
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
        assert.is_true(ui.closed)
        assert.are.equal("/library/Book.epub", ui.shown)
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

    it("closes Rakuyomi chapters when their own return is disabled", function()
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

local Navigation = require("common/library_navigation")

describe("library navigation", function()
    before_each(function()
        _G.G_reader_settings = ZenSpec.memorySettings({
            allow_commaneer_filemanager = true,
            home_dir = "/library",
        })
        ZenSpec.replace("ui/event", { new = function(_, name) return { name = name } end })
        ZenSpec.replace("ui/widget/booklist", { setBookInfoCache = function() end })
        ZenSpec.replace("config/manager", { get = function() return {} end })
        ZenSpec.unload("common/paths")
        ZenSpec.unload("common/library_navigation")
        Navigation = require("common/library_navigation")
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
end)

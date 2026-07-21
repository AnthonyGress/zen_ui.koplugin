describe("Rakuyomi reader return", function()
    local original_modules = {}
    local original_plugin
    local original_rakuyomi
    local module_names = {
        "MangaReader",
        "apps/filemanager/filemanager",
        "apps/reader/readerui",
        "ui/geometry",
        "device",
        "ui/uimanager",
        "common/zen_logger",
        "gettext",
    }

    local function apply_patch(return_enabled)
        local opened_chapters, opened_library = 0, 0
        local MangaReader = {
            is_showing = true,
            on_return_callback = function() opened_library = opened_library + 1 end,
            onReturn = function(self) self.on_return_callback() end,
        }
        ZenSpec.replace("MangaReader", MangaReader)
        ZenSpec.replace("apps/filemanager/filemanager", {})
        ZenSpec.replace("apps/reader/readerui", {
            instance = { document = { file = "/library/chapter.cbz" } },
            showReader = function() end,
            onClose = function() end,
        })
        ZenSpec.replace("ui/geometry", {})
        ZenSpec.replace("device", { screen = {} })
        ZenSpec.replace("ui/uimanager", {})
        ZenSpec.replace("common/zen_logger", {
            new = function() return { warn = function() end } end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        _G.__ZEN_UI_PLUGIN = {
            config = { rakuyomi = { return_to_chapter_list_on_exit = return_enabled } },
        }
        ZenSpec.unload("modules/filebrowser/patches/rakuyomi")
        require("modules/filebrowser/patches/rakuyomi")()
        local Rakuyomi = _G.__ZEN_UI_RAKUYOMI
        Rakuyomi.isChapterFile = function() return true end
        Rakuyomi.openChapterListingFromFile = function(path, hide_top_close)
            opened_chapters = opened_chapters + 1
            assert.are.equal("/library/chapter.cbz", path)
            assert.is_true(hide_top_close)
            return true
        end
        return MangaReader, function() return opened_chapters, opened_library end
    end

    before_each(function()
        for _i, name in ipairs(module_names) do
            original_modules[name] = package.loaded[name]
        end
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        original_rakuyomi = rawget(_G, "__ZEN_UI_RAKUYOMI")
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do
            package.loaded[name] = original_modules[name]
        end
        _G.__ZEN_UI_PLUGIN = original_plugin
        _G.__ZEN_UI_RAKUYOMI = original_rakuyomi
        ZenSpec.unload("modules/filebrowser/patches/rakuyomi")
    end)

    it("returns directly to the chapter list when enabled", function()
        local MangaReader, results = apply_patch(true)
        MangaReader:onReturn()
        local opened_chapters, opened_library = results()
        assert.are.equal(1, opened_chapters)
        assert.are.equal(0, opened_library)
    end)

    it("keeps Rakuyomi's library return when disabled", function()
        local MangaReader, results = apply_patch(false)
        MangaReader:onReturn()
        local opened_chapters, opened_library = results()
        assert.are.equal(0, opened_chapters)
        assert.are.equal(1, opened_library)
    end)

    it("does not reopen the chapter list after the file manager restored it", function()
        local MangaReader, results = apply_patch(true)
        _G.__ZEN_UI_RAKUYOMI_CHAPTER_LIST_RESTORED = true
        MangaReader:onReturn()
        local opened_chapters, opened_library = results()
        assert.are.equal(0, opened_chapters)
        assert.are.equal(0, opened_library)
    end)
end)

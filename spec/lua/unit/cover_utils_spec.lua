describe("cover utility policy", function()
    local CoverUtils

    before_each(function()
        _G.G_reader_settings = ZenSpec.memorySettings({ uniform_cover_ratio = "2:3" })
        ZenSpec.replace("ffi/blitbuffer", {})
        ZenSpec.replace("modules/filebrowser/patches/library_font", {})
        ZenSpec.replace("ui/widget/textboxwidget", {})
        ZenSpec.replace("ui/rendertext", {})
        ZenSpec.replace("ui/bidi", {})
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")
    end)

    it("calculates portrait cover dimensions from the configured ratio", function()
        assert.are.same({ 200, 300 }, { CoverUtils.calcDims(300, 300) })
        _G.G_reader_settings:saveSetting("uniform_cover_ratio", "3:4")
        assert.are.same({ 225, 300 }, { CoverUtils.calcDims(300, 300) })
        assert.are.same({ 300, 400 }, { CoverUtils.calcDims(300, 500) })
    end)

    it("enforces and persists the readable files-per-page cap", function()
        local saved
        ZenSpec.replace("bookinfomanager", {
            getSetting = function() return 20 end,
            saveSetting = function(_, _, value) saved = value end,
        })
        ZenSpec.replace("ui/widget/filechooser", { files_per_page = 20 })
        ZenSpec.replace("apps/filemanager/filemanager", { instance = nil })
        assert.are.equal(12, CoverUtils.getFilesPerPage())
        assert.are.equal(12, saved)
    end)

    it("maps configured folder cover modes to cover counts and gallery behavior", function()
        _G.__ZEN_UI_PLUGIN = { config = { browser_folder_cover = { cover_mode = "gallery" } } }
        assert.are.same({ "gallery", 4, true }, { CoverUtils.getMode() })
        _G.__ZEN_UI_PLUGIN.config.browser_folder_cover.cover_mode = "none"
        assert.are.same({ "none", 0, false }, { CoverUtils.getMode() })
    end)
end)

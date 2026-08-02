local Paths = require("common/paths")

describe("paths", function()
    before_each(function()
        _G.G_reader_settings = ZenSpec.memorySettings({ home_dir = "/sdcard/Books/" })
        ZenSpec.replace("config/manager", {
            get = function()
                return { additional_home_dirs = { "/library/extra" } }
            end,
        })
    end)

    it("normalizes Android storage and respects primary/additional home roots", function()
        assert.are.equal("/storage/emulated/0/Books", Paths.getHomeDir())
        assert.is_true(Paths.isInHomeDir("/sdcard/Books/Series"))
        assert.is_true(Paths.isHomeRoot("/library/extra/"))
        assert.is_false(Paths.isPrimaryHomeRoot("/library/extra"))
        assert.is_false(Paths.isInHomeDir("/outside/Book.epub"))
    end)
end)

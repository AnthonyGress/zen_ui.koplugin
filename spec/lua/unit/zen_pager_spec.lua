describe("Zen pager positioning", function()
    local Pager
    local saved_modules
    local module_names = {
        "ffi/blitbuffer",
        "ui/font",
        "ui/widget/iconwidget",
        "ui/rendertext",
        "device",
        "modules/filebrowser/patches/library_font",
        "common/ui/zen_pager",
    }

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(module_names) do
            saved_modules[name] = package.loaded[name] or false
        end
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_DARK_GRAY = "dark_gray",
            COLOR_LIGHT_GRAY = "light_gray",
        })
        ZenSpec.replace("ui/font", {})
        ZenSpec.replace("ui/widget/iconwidget", {})
        ZenSpec.replace("ui/rendertext", {})
        ZenSpec.replace("device", {
            screen = {
                scaleBySize = function(_self, value) return value end,
            },
        })
        ZenSpec.replace("modules/filebrowser/patches/library_font", {})
        ZenSpec.unload("common/ui/zen_pager")
        Pager = require("common/ui/zen_pager")
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("centers a footer in the fixed space after a full page of rows", function()
        assert.are.equal(485, Pager.getCenteredFooterY(220, 750, 40, true))
    end)

    it("keeps full pages and tight layouts at the bottom", function()
        assert.are.equal(750, Pager.getCenteredFooterY(750, 750, 40, false))
        assert.are.equal(750, Pager.getCenteredFooterY(750, 750, 40, true))
    end)

    it("uses a centered footer spanning 92 percent of its container", function()
        local x, width = Pager.getFooterGeometry(0, 1000)

        assert.are.equal(40, x)
        assert.are.equal(920, width)
    end)

    it("widens chevron targets and extends only their bottoms by a bounded amount", function()
        assert.are.equal("left", Pager.getPageNumberZone(180, 250, 100, 200, 400, 40, 500))
        assert.are.equal("right", Pager.getPageNumberZone(420, 250, 100, 200, 400, 40, 500))
        assert.are.equal("center", Pager.getPageNumberZone(300, 220, 100, 200, 400, 40, 500))
        assert.is_nil(Pager.getPageNumberZone(300, 250, 100, 200, 400, 40, 500))
        assert.is_nil(Pager.getPageNumberZone(180, 264, 100, 200, 400, 40, 500))
        assert.are.equal(250, Pager.getChevronHitBottom(200, 40, 250))
    end)
end)

describe("library font", function()
    local saved_modules
    local cfg
    local calls
    local warnings

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs({
            "ui/font",
            "common/zen_logger",
            "config/manager",
            "modules/filebrowser/patches/library_font",
        }) do
            saved_modules[name] = package.loaded[name] or false
        end

        cfg = { font_face = "Custom-Regular.ttf", font_size = 18 }
        calls = {}
        warnings = {}
        rawset(_G, "__ZEN_UI_LIBRARY_FONT_CFG", cfg)
        ZenSpec.replace("ui/font", {
            getFace = function(_self, name, size)
                calls[#calls + 1] = { name, size }
                if name == "Missing-Regular.ttf" then return nil end
                if name == "Broken-Regular.ttf" then error("font loader failed") end
                return { orig_font = name, orig_size = size }
            end,
        })
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return {
                    warn = function(...)
                        warnings[#warnings + 1] = { ... }
                    end,
                }
            end,
        })
        ZenSpec.replace("config/manager", { get = function() return {} end })
        ZenSpec.unload("modules/filebrowser/patches/library_font")
    end)

    after_each(function()
        rawset(_G, "__ZEN_UI_LIBRARY_FONT_CFG", nil)
        for name, original in pairs(saved_modules) do
            package.loaded[name] = original == false and nil or original
        end
    end)

    it("uses and caches a loadable custom font", function()
        local library_font = require("modules/filebrowser/patches/library_font")

        assert.are.equal("Custom-Regular.ttf", library_font.getFontName())
        assert.are.equal("Custom-Regular.ttf", library_font.getFontName())
        assert.are.same({ { "Custom-Regular.ttf", 18 } }, calls)
        assert.are.equal(0, #warnings)
    end)

    it("uses the default alias without probing it as a custom font", function()
        cfg.font_face = "cfont"
        local library_font = require("modules/filebrowser/patches/library_font")

        assert.are.equal("cfont", library_font.getFontName())
        assert.are.equal(0, #calls)
        assert.are.equal(0, #warnings)
    end)

    it("falls back when the configured font file is missing", function()
        cfg.font_face = "Missing-Regular.ttf"
        local library_font = require("modules/filebrowser/patches/library_font")

        assert.are.equal("cfont", library_font.getFontName())
        local face = library_font.getFace(16)

        assert.are.equal("cfont", face.orig_font)
        assert.are.equal("Missing-Regular.ttf", cfg.font_face)
        assert.are.same({
            { "Missing-Regular.ttf", 18 },
            { "cfont", 16 },
        }, calls)
        assert.are.equal(1, #warnings)
    end)

    it("falls back when the font loader raises an error", function()
        cfg.font_face = "Broken-Regular.ttf"
        local library_font = require("modules/filebrowser/patches/library_font")

        assert.are.equal("cfont", library_font.getFontName())
        assert.are.equal(1, #warnings)
    end)
end)

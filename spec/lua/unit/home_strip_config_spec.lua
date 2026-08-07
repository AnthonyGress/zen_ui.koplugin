describe("unified Home strip configuration", function()
    before_each(function()
        ZenSpec.unload("modules/filebrowser/patches/home/home_presets")
    end)

    local function legacy_page(enabled, order, modules)
        return {
            rows = { enabled = enabled or {}, order = order or {} },
            modules = modules or {},
        }
    end

    it("keeps the unified strip disabled when no legacy strip was enabled", function()
        local page = legacy_page({}, { "strip_recent", "quotes" }, {
            strip_recent = { count = 5 },
            strip_tbr = {},
        })
        local Presets = require("modules/filebrowser/patches/home/home_presets")

        assert.is_true(Presets.normalizeStripConfig(page))
        assert.are.same({ "strip", "quotes" }, page.rows.order)
        assert.is_false(page.rows.enabled.strip)
        assert.is_false(page.modules.strip.controls.enabled)
        assert.is_nil(page.modules.strip_recent)
    end)

    it("uses the one enabled legacy strip as the default without controls", function()
        local page = legacy_page({ strip_recent = true }, { "strip_recent" }, {
            strip_recent = {
                count = 5, filter_unread = true,
                filter_tbr = true, filter_finished = false,
            },
            strip_custom = { paths = { "/books/one.epub" } },
            strip_tag = { tag = "Science" },
        })
        local Presets = require("modules/filebrowser/patches/home/home_presets")

        Presets.normalizeStripConfig(page)
        local strip = page.modules.strip
        assert.are.same({ kind = "recent" }, strip.default_source)
        assert.are.equal(5, strip.count)
        assert.is_true(strip.sources.recent.filter_unread)
        assert.is_true(strip.sources.recent.filter_tbr)
        assert.are.same({ "/books/one.epub" }, strip.sources.custom.paths)
        assert.are.equal("Science", strip.sources.tag.tag)
        assert.is_false(strip.controls.enabled)
    end)

    it("turns multiple enabled legacy strips into ordered source buttons", function()
        local page = legacy_page({
            strip_tag = true, strip_custom = true, strip_tbr = true,
        }, { "quotes", "strip_tag", "strip_custom", "strip_tbr" }, {
            strip_tag = { tag = "Fantasy", show_badges = true },
            strip_custom = { paths = { "/books/custom.epub" } },
            strip_tbr = {},
        })
        local Presets = require("modules/filebrowser/patches/home/home_presets")

        Presets.normalizeStripConfig(page)
        local strip = page.modules.strip
        assert.are.same({ kind = "tag", value = "Fantasy" }, strip.default_source)
        assert.is_true(strip.show_badges)
        assert.is_true(strip.controls.enabled)
        assert.are.equal(3, #strip.controls.order)
        assert.are.equal("tag", strip.controls.custom_buttons[1].type)
        assert.are.equal("custom_source", strip.controls.custom_buttons[2].type)
        assert.are.equal("to_be_read", strip.controls.order[3])
    end)

    it("normalizes the seven-button limit and accepts Favorites as a source", function()
        local Presets = require("modules/filebrowser/patches/home/home_presets")
        local page = Presets.defaultHomePage()
        page.modules.strip.default_source = { kind = "favorites" }
        page.modules.strip.controls.order = {
            "recent", "favorites", "to_be_read", "authors", "series",
            "tags", "collections", "books", "search", "recent",
        }
        page.modules.strip.controls.show_buttons = {
            recent = true, favorites = true, to_be_read = true, authors = true,
            series = true, tags = true, collections = true, books = true,
        }

        assert.is_true(Presets.normalizeStripConfig(page))
        assert.are.same({ kind = "favorites" }, page.modules.strip.default_source)
        assert.is_false(page.modules.strip.controls.show_buttons.books)
        assert.are.equal(8, #page.modules.strip.controls.order)
    end)

    it("keeps at least one valid tab visible", function()
        local Presets = require("modules/filebrowser/patches/home/home_presets")
        local page = Presets.defaultHomePage()
        page.modules.strip.controls.order = { "missing", "favorites", "recent" }
        page.modules.strip.controls.show_buttons = {
            missing = true, favorites = false, recent = false,
        }

        assert.is_true(Presets.normalizeStripConfig(page))
        assert.are.same({ "favorites", "recent" }, page.modules.strip.controls.order)
        assert.is_true(page.modules.strip.controls.show_buttons.favorites)
        assert.is_false(page.modules.strip.controls.show_buttons.recent)
    end)
end)

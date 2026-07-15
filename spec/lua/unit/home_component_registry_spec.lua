describe("home component registry", function()
    local module_names = {
        "datetime",
        "featured_custom",
        "featured_tbr",
        "featured_recent",
        "stats_triplet",
        "reading_goals",
        "strip_custom",
        "strip_tbr",
        "strip_recent",
        "quotes",
    }

    before_each(function()
        ZenSpec.unload("modules/filebrowser/patches/home/components/registry")
        for _i, id in ipairs(module_names) do
            ZenSpec.replace("modules/filebrowser/patches/home/widgets/" .. id, {
                id = id,
                label = id .. " widget",
                build = function() return id end,
            })
        end
    end)

    after_each(function()
        _G.__ZEN_UI_REGISTER_HOME_ITEM = nil
        _G.__ZEN_UI_UNREGISTER_HOME_ITEM = nil
    end)

    it("loads every built-in home widget in its stable order", function()
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        local ids = {}
        for _i, component in ipairs(Registry.list()) do
            ids[#ids + 1] = component.id
            assert.is_function(component.build)
        end
        assert.are.same(module_names, ids)
    end)

    it("normalizes duplicate, missing, and dormant row settings", function()
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        local rows = Registry.normalizeRows({
            order = { "quotes", "quotes", "external_missing" },
            enabled = { quotes = true, dormant = true },
            max_rows = 99,
        }, { "datetime", "featured_recent" }, { datetime = true })

        assert.are.equal(5, rows.max_rows)
        assert.are.same({
            "quotes", "external_missing", "datetime", "featured_recent",
            "featured_custom", "featured_tbr", "stats_triplet", "reading_goals",
            "strip_custom", "strip_tbr", "strip_recent", "dormant",
        }, rows.order)
        assert.is_true(rows.enabled.quotes)
        assert.is_true(rows.enabled.dormant)
        assert.is_false(rows.enabled.featured_recent)
    end)

    it("registers external widgets, refreshes, and rejects built-in overrides", function()
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        local refreshes = 0
        Registry.setRefreshCallback(function() refreshes = refreshes + 1 end)
        Registry.install()

        assert.is_false(_G.__ZEN_UI_REGISTER_HOME_ITEM("quotes", function() end))
        assert.is_false(_G.__ZEN_UI_REGISTER_HOME_ITEM("invalid", "not a function"))
        assert.is_true(_G.__ZEN_UI_REGISTER_HOME_ITEM("weather", function() return "sunny" end, {
            label = "Weather",
            size = { preferred_pct = 0.2 },
        }))
        assert.are.equal("Weather", Registry.get("weather").label)
        assert.are.equal("sunny", Registry.get("weather").build())
        assert.are.equal(1, refreshes)

        _G.__ZEN_UI_UNREGISTER_HOME_ITEM("weather")
        assert.is_nil(Registry.get("weather"))
        assert.are.equal(2, refreshes)
    end)
end)

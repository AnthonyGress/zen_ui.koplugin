describe("home component registry", function()
    local module_names = {
        "datetime",
        "featured_custom",
        "featured_tbr",
        "featured_recent",
        "stats_triplet",
        "reading_goals",
        "strip_custom",
        "strip_tag",
        "strip_tbr",
        "strip_recent",
        "quotes",
    }
    local module_sizes = {
        datetime = "s",
        featured_custom = "l",
        featured_tbr = "l",
        featured_recent = "l",
        stats_triplet = "xs",
        reading_goals = "xs",
        strip_custom = { units = 3.5 },
        strip_tag = { units = 3.5 },
        strip_tbr = { units = 3.5 },
        strip_recent = { units = 3.5 },
        quotes = { units = 1.5 },
    }

    before_each(function()
        ZenSpec.unload("modules/filebrowser/patches/home/components/registry")
        for _i, id in ipairs(module_names) do
            ZenSpec.replace("modules/filebrowser/patches/home/widgets/" .. id, {
                id = id,
                label = id .. " widget",
                size = module_sizes[id],
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

        assert.is_nil(rows.max_rows)
        assert.are.equal(10, rows.capacity_units)
        assert.are.same({
            "quotes", "external_missing", "datetime", "featured_recent",
            "featured_custom", "featured_tbr", "stats_triplet", "reading_goals",
            "strip_custom", "strip_tag", "strip_tbr", "strip_recent", "dormant",
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
            size = "m",
        }))
        assert.are.equal("Weather", Registry.get("weather").label)
        assert.are.equal(3, Registry.sizeUnits(Registry.get("weather")))
        assert.are.equal("sunny", Registry.get("weather").build())
        assert.are.equal(1, refreshes)

        _G.__ZEN_UI_UNREGISTER_HOME_ITEM("weather")
        assert.is_nil(Registry.get("weather"))
        assert.are.equal(2, refreshes)
    end)

    it("maps size classes to a 10-unit capacity", function()
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        assert.are.equal(1, Registry.sizeUnits(Registry.get("stats_triplet")))
        assert.are.equal(1.5, Registry.sizeUnits(Registry.get("quotes")))
        assert.are.equal(3.5, Registry.sizeUnits(Registry.get("strip_recent")))
        assert.are.equal(4, Registry.sizeUnits(Registry.get("featured_recent")))
        assert.are.equal(6, Registry.sizeUnits(
            Registry.get("strip_recent"), { two_rows = true }
        ))
        assert.are.equal(10, Registry.sizeUnits({ size = "xl" }))
        assert.are.equal(4, Registry.sizeUnits({
            size = { preferred_pct = 0.36 },
        }))
        assert.are.equal(10, Registry.totalUnits({
            featured_recent = true,
            stats_triplet = true,
            strip_recent = true,
            quotes = true,
        }))
        assert.are.same({ 4, 1, 3.5, 1.5 }, Registry.layoutUnits({
            Registry.get("featured_recent"),
            Registry.get("stats_triplet"),
            Registry.get("strip_recent"),
            Registry.get("quotes"),
        }))
        assert.are.same({ 5, 3.5 }, Registry.layoutUnits({
            Registry.get("featured_recent"),
            Registry.get("strip_recent"),
        }))
        assert.are.same({ 1 }, Registry.layoutUnits({ Registry.get("stats_triplet") }))
        assert.are.same({ 4, 6 }, Registry.layoutUnits({
            setmetatable({ _home_units = 4 }, {
                __index = Registry.get("featured_recent"),
            }),
            setmetatable({ _home_units = 6 }, {
                __index = Registry.get("strip_recent"),
            }),
        }))
    end)

    it("fits the Bookshelf featured and two-row strip widgets", function()
        ZenSpec.unload("modules/filebrowser/patches/home/home_presets")
        local presets = require("modules/filebrowser/patches/home/home_presets").getBuiltinPresets()
        local bookshelf = presets[2].home_page
        local Registry = require("modules/filebrowser/patches/home/components/registry")

        assert.is_true(bookshelf.modules.strip_recent.two_rows)
        assert.are.equal(10, Registry.totalUnits(
            bookshelf.rows.enabled,
            bookshelf.modules
        ))
    end)

    it("fills the 10-track grid with equal widget gaps", function()
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        local heights = Registry.gridHeights({ 4, 1, 3, 2 }, 1000, 10)

        assert.are.same({ 394, 91, 293, 192 }, heights)
        assert.are.equal(1000,
            heights[1] + heights[2] + heights[3] + heights[4] + 30)
        assert.are.same({ 1003 }, Registry.gridHeights({ 10 }, 1003, 10))
        assert.are.equal(303,
            1000 - Registry.gridHeights({ 4, 3 }, 1000, 10)[1]
                - Registry.gridHeights({ 4, 3 }, 1000, 10)[2] - 10)
        assert.are.same({ 394, 91, 344, 141 },
            Registry.gridHeights({ 4, 1, 3.5, 1.5 }, 1000, 10))
    end)

    it("equalizes visible gaps within each widget's available slack", function()
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        local items = {
            { row_y = 0, top = 0, bottom = 100, min_shift = -10, max_shift = 10 },
            { row_y = 165, top = 0, bottom = 100, min_shift = -20, max_shift = 20 },
            { row_y = 298, top = 0, bottom = 100, min_shift = -20, max_shift = 20 },
            { row_y = 465, top = 0, bottom = 100, min_shift = -8, max_shift = 80 },
        }
        local shifts = Registry.equalSpacingShifts(items)
        local gaps = {}
        for i = 1, #items - 1 do
            gaps[i] = items[i + 1].row_y + items[i + 1].top + shifts[i + 1]
                - items[i].row_y - items[i].bottom - shifts[i]
        end

        assert.are.equal(4, #shifts)
        assert.are.equal(gaps[1], gaps[2])
        assert.are.equal(gaps[2], gaps[3])
        for i, shift in ipairs(shifts) do
            assert.is_true(shift >= items[i].min_shift)
            assert.is_true(shift <= items[i].max_shift)
        end
    end)

    it("equalizes gaps when content is taller than its row", function()
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        local items = {
            { row_y = 0, top = 0, bottom = 100, min_shift = 0, max_shift = 20 },
            { row_y = 150, top = 6, bottom = 128, min_shift = -6, max_shift = -28 },
            { row_y = 280, top = 0, bottom = 100, min_shift = -20, max_shift = 20 },
        }
        local shifts = Registry.equalSpacingShifts(items)
        local first_gap = items[2].row_y + items[2].top + shifts[2]
            - items[1].row_y - items[1].bottom - shifts[1]
        local second_gap = items[3].row_y + items[3].top + shifts[3]
            - items[2].row_y - items[2].bottom - shifts[2]

        assert.are.equal(3, #shifts)
        assert.are.equal(first_gap, second_gap)
        assert.is_true(shifts[2] >= -28)
        assert.is_true(shifts[2] <= -6)
    end)

    it("returns the closest spacing when fixed content prevents equality", function()
        local Registry = require("modules/filebrowser/patches/home/components/registry")
        local shifts = Registry.equalSpacingShifts({
            { row_y = 0, top = 0, bottom = 100, min_shift = 0, max_shift = 0 },
            { row_y = 120, top = 0, bottom = 100, min_shift = 0, max_shift = 0 },
            { row_y = 280, top = 0, bottom = 100, min_shift = 0, max_shift = 0 },
        })

        assert.are.same({ 0, 0, 0 }, shifts)
    end)
end)

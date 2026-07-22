describe("startup alert userpatch", function()
    local patch = ZenSpec.root
        .. "/spec/python/userpatches/2-zen-ui-suppress-startup-alerts.lua"

    it("seeds missing color-screen first-run settings", function()
        local values = {}
        _G.G_reader_settings = {
            has = function(_, key) return values[key] ~= nil end,
            saveSetting = function(_, key, value) values[key] = value end,
            makeTrue = function(_, key) values[key] = true end,
        }
        ZenSpec.replace("device", { hasColorScreen = function() return true end })

        dofile(patch)

        assert.are.equal(2021070000, values.quickstart_shown_version)
        assert.is_true(values.color_rendering)
    end)

    it("leaves existing choices unchanged", function()
        local values = {
            quickstart_shown_version = 42,
            color_rendering = false,
        }
        _G.G_reader_settings = {
            has = function(_, key) return values[key] ~= nil end,
            saveSetting = function(_, key, value) values[key] = value end,
            makeTrue = function(_, key) values[key] = true end,
        }
        ZenSpec.replace("device", { hasColorScreen = function() return true end })

        dofile(patch)

        assert.are.equal(42, values.quickstart_shown_version)
        assert.is_false(values.color_rendering)
    end)

    it("does not enable color rendering on grayscale screens", function()
        local values = {}
        _G.G_reader_settings = {
            has = function(_, key) return values[key] ~= nil end,
            saveSetting = function(_, key, value) values[key] = value end,
            makeTrue = function(_, key) values[key] = true end,
        }
        ZenSpec.replace("device", { hasColorScreen = function() return false end })

        dofile(patch)

        assert.is_nil(values.color_rendering)
    end)
end)

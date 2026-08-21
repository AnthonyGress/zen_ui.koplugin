describe("common utils deep merge", function()
    local utils = require("common/utils")

    it("fills an empty map from map defaults", function()
        local target = {}

        utils.deepmerge(target, {
            navbar = true,
            features = { launcher = true },
        })

        assert.are.same({
            navbar = true,
            features = { launcher = true },
        }, target)
    end)

    it("preserves an intentionally empty array", function()
        local target = {}

        utils.deepmerge(target, { "default" })

        assert.are.same({}, target)
    end)
end)

describe("common utils icon sizing", function()
    local utils = require("common/utils")

    it("optically enlarges ZenFM and ZenPM icons", function()
        assert.are.equal(1.25, utils.iconOpticalScale("zenfm"))
        assert.are.equal(1.25, utils.iconOpticalScale("/plugins/zenpm/icons/zenpm.svg"))
    end)

    it("keeps other icons at their requested size", function()
        assert.are.equal(1, utils.iconOpticalScale("quick_wifi"))
        assert.are.equal(1, utils.iconOpticalScale(nil))
    end)
end)

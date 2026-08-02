local Registry = require("common/status_bar_registry")

describe("status bar registry", function()
    it("registers, refreshes, and unregisters external items", function()
        local refreshes = 0
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = { _updateStatusBar = function() refreshes = refreshes + 1 end },
        })
        assert.is_true(Registry.register("sync", function() return "S", "Ready" end, {
            label = "Sync",
            side = "left",
        }))
        assert.are.equal("Sync", Registry.get("sync").label)
        assert.are.equal("left", Registry.get("sync").side)
        Registry.unregister("sync")
        assert.is_nil(Registry.get("sync"))
        assert.are.equal(2, refreshes)
    end)
end)

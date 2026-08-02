describe("shared state", function()
    before_each(function()
        ZenSpec.unload("common/shared_state")
    end)

    it("registers values and restores them after transient state is cleared", function()
        local SharedState = require("common/shared_state")
        local plugin = {}
        local value = { ready = true }

        local shared = SharedState.register(plugin, { home = value })
        assert.are.equal(plugin._zen_shared, shared)
        plugin._zen_shared = {}

        assert.are.equal(value, SharedState.get(plugin, "home"))
        assert.are.equal(value, plugin._zen_shared.home)
    end)

    it("runs a registered loader once for a missing value", function()
        local SharedState = require("common/shared_state")
        local plugin = {}
        local calls = 0
        local key = "unit_loader_value"
        SharedState.registerLoader(key, function(target)
            calls = calls + 1
            SharedState.register(target, { [key] = "loaded" })
        end)

        assert.are.equal("loaded", SharedState.get(plugin, key))
        assert.are.equal("loaded", SharedState.get(plugin, key))
        assert.are.equal(1, calls)
    end)

    it("rejects invalid plugins and ignores loader failures", function()
        local SharedState = require("common/shared_state")
        local key = "unit_failing_loader"
        SharedState.registerLoader(key, function() error("expected") end)

        assert.is_nil(SharedState.register(nil, { value = true }))
        assert.is_nil(SharedState.get({}, key))
    end)
end)

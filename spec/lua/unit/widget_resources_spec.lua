local Resources = require("common/widget_resources")

describe("widget resources", function()
    it("frees replaced children once and invalidates layout", function()
        local frees = 0
        local old = { free = function() frees = frees + 1 end }
        local container = { [1] = old, resetLayout = function(self) self.reset = true end }
        Resources.replaceChild(container, 1, { name = "new" })
        assert.are.equal(1, frees)
        assert.is_true(container.reset)
        assert.are.equal("new", container[1].name)
    end)

    it("wraps free callbacks without losing the original free", function()
        local calls = {}
        local widget = { free = function() calls[#calls + 1] = "original" end }
        Resources.wrapFree(widget, function() calls[#calls + 1] = "cleanup" end)
        widget:free()
        assert.are.same({ "cleanup", "original" }, calls)
    end)
end)

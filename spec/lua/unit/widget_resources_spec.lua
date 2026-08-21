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

    it("repaints rounded frame borders after child content", function()
        local calls = {}
        local frame = {
            width = 100,
            height = 24,
            margin = 1,
            bordersize = 2,
            color = "black",
            radius = 4,
            getSize = function() return { w = 80, h = 20 } end,
            paintTo = function() calls[#calls + 1] = { kind = "content" } end,
        }
        local bb = {
            paintBorder = function(_self, ...)
                calls[#calls + 1] = { kind = "border", args = { ... } }
            end,
        }

        Resources.paintFrameBorderOnTop(frame)
        Resources.paintFrameBorderOnTop(frame)
        frame:paintTo(bb, 10, 20)

        assert.are.equal("content", calls[1].kind)
        assert.are.equal("border", calls[2].kind)
        assert.are.same({ 11, 21, 98, 22, 2, "black", 4, false }, calls[2].args)
        assert.are.equal(2, #calls)
    end)
end)

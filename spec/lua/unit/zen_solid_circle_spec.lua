describe("solid circle", function()
    local Blitbuffer
    local SolidCircle

    before_each(function()
        ZenSpec.unload("common/ui/zen_solid_circle")
        Blitbuffer = require("ffi/blitbuffer")
        SolidCircle = require("common/ui/zen_solid_circle")
    end)

    it("draws its ring without anti-aliasing", function()
        local child = {
            paintTo = function(self, _bb, x, y)
                self.x, self.y = x, y
            end,
        }
        local calls = {}
        local bb = {
            paintRoundedRect = function(_, x, y, w, h, color, radius)
                calls.fill = { x = x, y = y, w = w, h = h, color = color, radius = radius }
            end,
            paintBorder = function(_, x, y, w, h, width, color, radius, anti_alias)
                calls.border = {
                    x = x, y = y, w = w, h = h,
                    width = width, color = color, radius = radius, anti_alias = anti_alias,
                }
            end,
        }
        local circle = SolidCircle:new{
            width = 64,
            height = 64,
            bordersize = 2,
            radius = 32,
            background = Blitbuffer.COLOR_WHITE,
            child,
        }

        circle:paintTo(bb, 10, 20)

        assert.are.equal(10, calls.fill.x)
        assert.are.equal(20, calls.fill.y)
        assert.are.equal(64, calls.fill.w)
        assert.are.equal(64, calls.fill.h)
        assert.are.equal(34, calls.fill.radius)
        assert.is_not_nil(calls.border.color)
        assert.is_false(calls.border.anti_alias)
        assert.are.equal(12, child.x)
        assert.are.equal(22, child.y)
    end)
end)

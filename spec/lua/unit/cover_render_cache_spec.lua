describe("final cover render cache", function()
    local Cache

    local function bb(width, height)
        local out = { w = width, h = height, stride = width, freed = false }
        function out:getWidth() return self.w end
        function out:getHeight() return self.h end
        function out:getType() return 1 end
        function out:copy() return bb(self.w, self.h) end
        function out:scale(w, h) return bb(w, h) end
        function out:blitFrom() end
        function out:free() self.freed = true end
        return out
    end

    before_each(function()
        ZenSpec.replace("ffi/blitbuffer", { new = function(w, h) return bb(w, h) end })
        ZenSpec.unload("common/cover_render_cache")
        Cache = require("common/cover_render_cache")
        Cache:clear()
        Cache:setByteBudget(100)
    end)

    it("reuses a final-size bitmap and frees the redundant source", function()
        local first_source = bb(10, 20)
        local first = Cache:render("/book.epub", first_source, 5, 8)
        local second_source = bb(10, 20)
        local second = Cache:render("/book.epub", second_source, 5, 8)

        assert.are.equal(5, first:getWidth())
        assert.are.equal(8, first:getHeight())
        assert.are.equal(5, second:getWidth())
        assert.is_true(second_source.freed)
        assert.are.equal(1, Cache:stats().hits)
    end)
end)

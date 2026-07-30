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

    it("reuses one larger bitmap across smaller layout sizes", function()
        Cache:put("/book.epub", 8, 12, bb(8, 12))
        local smaller = Cache:get("/book.epub", 5, 8)

        assert.are.equal(5, smaller:getWidth())
        assert.are.equal(8, smaller:getHeight())
        assert.are.equal(1, Cache:stats().hits)
    end)

    it("replaces an undersized bitmap for a larger layout", function()
        Cache:put("/book.epub", 5, 8, bb(5, 8))
        assert.is_nil(Cache:get("/book.epub", 8, 12))

        Cache:put("/book.epub", 8, 12, bb(8, 12))
        local larger = Cache:get("/book.epub", 8, 12)

        assert.are.equal(8, larger:getWidth())
        assert.are.equal(12, larger:getHeight())
        assert.are.equal(1, Cache:stats().hits)
    end)

    it("falls back without retaining a failed resize allocation", function()
        local source = bb(10, 20)
        function source:scale() error("out of memory") end

        assert.is_nil(Cache:render("/book.epub", source, 5, 8))
        assert.is_true(source.freed)
        assert.are.equal(0, Cache:stats().bytes)
    end)
end)

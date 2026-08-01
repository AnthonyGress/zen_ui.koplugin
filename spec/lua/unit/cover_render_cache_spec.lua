describe("final cover render cache", function()
    local Cache
    local scale_calls

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
        scale_calls = 0
        ZenSpec.replace("ffi/blitbuffer", { new = function(w, h) return bb(w, h) end })
        ZenSpec.replace("ui/renderimage", {
            scaleBlitBuffer = function(_self, source, width, height)
                scale_calls = scale_calls + 1
                local scaled = source:scale(width, height)
                source:free()
                return scaled
            end,
        })
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
        assert.are.equal(1, scale_calls)
    end)

    it("shares one immutable final-size bitmap without copying it", function()
        local first_source = bb(5, 8)
        local first, first_owned = Cache:renderShared(
            "/book.epub", first_source, 5, 8)
        local second_source = bb(5, 8)
        local second, second_owned = Cache:renderShared(
            "/book.epub", second_source, 5, 8)

        assert.is_true(first_owned)
        assert.is_true(second_owned)
        assert.are.equal(first, second)
        assert.is_false(first.freed)
        assert.is_true(second_source.freed)
        assert.are.equal(1, Cache:stats().shared_hits)
        assert.are.equal(0, scale_calls)
        assert.is_true(Cache:releaseShared("/book.epub", first))
        assert.is_true(Cache:releaseShared("/book.epub", second))
    end)

    it("frees a shared buffer after its final consumer releases it", function()
        local shared = bb(5, 8)
        Cache:putShared("/book.epub", 5, 8, shared)

        assert.is_true(Cache:drop("/book.epub"))
        assert.is_false(Cache:hasExact("/book.epub", 5, 8))
        assert.is_false(shared.freed)

        assert.is_true(Cache:releaseShared("/book.epub", shared))
        assert.is_true(shared.freed)
    end)

    it("reuses one larger bitmap across smaller layout sizes", function()
        Cache:put("/book.epub", 8, 12, bb(8, 12))

        assert.is_true(Cache:hasReusable("/book.epub", 5, 8))
        local smaller = Cache:get("/book.epub", 5, 8)

        assert.are.equal(5, smaller:getWidth())
        assert.are.equal(8, smaller:getHeight())
        assert.are.equal(1, Cache:stats().hits)
    end)

    it("does not reuse a differently shaped crop", function()
        Cache:put("/book.epub", 8, 12, bb(8, 12))

        assert.is_false(Cache:hasReusable("/book.epub", 8, 10))
        assert.is_nil(Cache:get("/book.epub", 8, 10))
        assert.are.equal(0, Cache:stats().hits)
    end)

    it("prioritizes a touched exact bitmap without copying it", function()
        Cache:put("gallery", 5, 10, bb(5, 10))
        Cache:put("book", 5, 10, bb(5, 10))

        assert.is_true(Cache:touchExact("gallery", 5, 10))
        assert.are.equal(0, Cache:stats().hits)
        Cache:put("next", 5, 10, bb(5, 10))

        assert.is_true(Cache:hasExact("gallery", 5, 10))
        assert.is_false(Cache:hasExact("book", 5, 10))
        assert.is_true(Cache:hasExact("next", 5, 10))
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

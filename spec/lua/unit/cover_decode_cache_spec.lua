describe("decoded cover cache", function()
    local Cache

    local function fake_bb(bytes, id)
        local bb = {
            stride = bytes,
            h = 1,
            id = id,
            freed = false,
        }
        function bb:getHeight() return self.h end
        function bb:copy() return fake_bb(bytes, id .. ":copy") end
        function bb:free() self.freed = true end
        return bb
    end

    before_each(function()
        ZenSpec.unload("common/cover_decode_cache")
        Cache = require("common/cover_decode_cache")
        Cache:clear()
        Cache:setByteBudget(10)
    end)

    after_each(function()
        Cache:clear()
    end)

    it("returns caller-owned copies without exposing its stored buffer", function()
        local source = fake_bb(4, "source")
        assert.is_true(Cache:put("/book.epub", "v1", source, { title = "Book" }, 100))

        local first = Cache:get("/book.epub", "v1")
        local fresh = Cache:getFresh("/book.epub", 110, 30)

        assert.are_not.equal(source, first)
        assert.are_not.equal(first, fresh.cover_bb)
        assert.are.equal("Book", fresh.title)
        assert.is_false(source.freed)
        local stats = Cache:stats()
        assert.are.equal(4, stats.bytes)
        assert.are.equal(10, stats.byte_budget)
        assert.are.equal(1, stats.count)
        assert.are.equal(2, stats.hits)
        assert.are.equal(1, stats.fast_hits)
        assert.are.equal(0, stats.misses)
        assert.are.equal(0, stats.evictions)
    end)

    it("evicts the least-recently-used cover to honor the byte budget", function()
        Cache:put("/one.epub", "v1", fake_bb(6, "one"))
        Cache:put("/two.epub", "v1", fake_bb(6, "two"))

        assert.is_nil(Cache:get("/one.epub", "v1"))
        assert.is_not_nil(Cache:get("/two.epub", "v1"))
        local stats = Cache:stats()
        assert.are.equal(1, stats.count)
        assert.are.equal(6, stats.bytes)
        assert.are.equal(1, stats.evictions)
    end)

    it("drops stale entries when the metadata signature changes", function()
        Cache:put("/book.epub", "v1", fake_bb(4, "source"))

        assert.is_nil(Cache:get("/book.epub", "v2"))
        assert.is_false(Cache:has("/book.epub"))
        assert.are.equal(0, Cache:stats().bytes)
    end)
end)

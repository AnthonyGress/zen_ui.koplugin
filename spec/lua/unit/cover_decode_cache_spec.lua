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

    it("returns fresh metadata without copying the cover bitmap", function()
        local source = fake_bb(4, "source")
        Cache:put("/book.epub", "v1", source, {
            title = "Book",
            has_cover = true,
            cover_w = 600,
            cover_h = 900,
        }, 100)

        local metadata = Cache:getFreshMetadata("/book.epub", 110, 30)

        assert.are.equal("Book", metadata.title)
        assert.are.equal(600, metadata.cover_w)
        assert.is_nil(metadata.cover_bb)
        assert.are.equal(1, Cache:stats().metadata_hits)
    end)

    it("retains bounded metadata for generated covers without bitmap bytes", function()
        assert.is_true(Cache:putMetadata("/placeholder.epub", {
            title = "Placeholder",
            cover_fetched = "Y",
            has_cover = false,
        }, 100))

        local metadata = Cache:getFreshMetadata("/placeholder.epub", 110, 30)

        assert.are.equal("Placeholder", metadata.title)
        assert.is_false(metadata.has_cover)
        local stats = Cache:stats()
        assert.are.equal(0, stats.bytes)
        assert.are.equal(1, stats.metadata_count)
        assert.are.equal(1, stats.metadata_puts)
    end)

    it("evicts least-recent metadata entries at the count limit", function()
        Cache.MAX_METADATA_ENTRIES = 2
        Cache:putMetadata("/one.epub", { title = "One" }, 100)
        Cache:putMetadata("/two.epub", { title = "Two" }, 100)
        Cache:putMetadata("/three.epub", { title = "Three" }, 100)

        assert.is_nil(Cache:getFreshMetadata("/one.epub", 100, 30))
        assert.is_not_nil(Cache:getFreshMetadata("/two.epub", 100, 30))
        assert.are.equal(1, Cache:stats().metadata_evictions)
    end)

    it("evicts the least-recently-used cover to honor the byte budget", function()
        Cache:put("/one.epub", "v1", fake_bb(6, "one"), { title = "One" }, 100)
        Cache:put("/two.epub", "v1", fake_bb(6, "two"))

        assert.is_nil(Cache:get("/one.epub", "v1"))
        assert.are.equal("One", Cache:getFreshMetadata("/one.epub", 110, 30).title)
        assert.is_not_nil(Cache:get("/two.epub", "v1"))
        local stats = Cache:stats()
        assert.are.equal(1, stats.count)
        assert.are.equal(1, stats.metadata_count)
        assert.are.equal(6, stats.bytes)
        assert.are.equal(1, stats.evictions)
    end)

    it("removes retained metadata on an explicit drop", function()
        Cache:put("/book.epub", "v1", fake_bb(6, "book"), { title = "Book" }, 100)
        Cache:put("/other.epub", "v1", fake_bb(6, "other"))

        Cache:drop("/book.epub")

        assert.is_nil(Cache:getFreshMetadata("/book.epub", 110, 30))
    end)

    it("drops stale entries when the metadata signature changes", function()
        Cache:put("/book.epub", "v1", fake_bb(4, "source"))

        assert.is_nil(Cache:get("/book.epub", "v2"))
        assert.is_false(Cache:has("/book.epub"))
        assert.are.equal(0, Cache:stats().bytes)
    end)
end)

describe("book info grouping cache", function()
    local exec_calls
    local DbBookInfo
    local now_value
    local limit_group_cache
    local original_memory_policy

    before_each(function()
        exec_calls = 0
        now_value = 0
        limit_group_cache = false
        original_memory_policy = package.loaded["common/memory_policy"]
        ZenSpec.replace("common/memory_policy", {
            limitGroupCache = function() return limit_group_cache end,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, key)
                local attr
                if path == "/settings/bookinfo.sqlite3" then
                    attr = { size = 100, modification = 200, mode = "file" }
                elseif path == "/settings/bookinfo.sqlite3-wal" then
                    attr = nil
                else
                    attr = { size = 10, modification = 20, mode = "file" }
                end
                return key and attr and attr[key] or attr
            end,
        })
        ZenSpec.replace("common/paths", {
            getHomeDir = function() return "/books" end,
            normPath = function(path) return path end,
            isInHomeDir = function() return true end,
        })
        ZenSpec.replace("bookinfomanager", {
            db_location = "/settings/bookinfo.sqlite3",
            db_conn = {
                exec = function()
                    exec_calls = exec_calls + 1
                    return {
                        { "/books/", "/books/" },
                        { "a.epub", "b.epub" },
                        { "Author A", "Author B" },
                    }
                end,
            },
            openDbConnection = function() end,
        })
        ZenSpec.replace("readhistory", {
            hist = { { file = "/books/b.epub" } },
        })
        ZenSpec.replace("common/zen_logger", {
            now = function() return now_value end,
            new = function()
                return {
                    measure = function() end,
                    warn = function() end,
                    info = function() end,
                    dbg = function() end,
                }
            end,
        })
        ZenSpec.unload("common/db_bookinfo")
        DbBookInfo = require("common/db_bookinfo")
    end)

    after_each(function()
        package.loaded["common/memory_policy"] = original_memory_policy
    end)

    it("reuses group shapes until explicitly invalidated", function()
        local first = DbBookInfo.getGroupedByAuthor()
        local second = DbBookInfo.getGroupedByAuthor()

        assert.are.equal(1, exec_calls)
        assert.are.equal(first, second)
        assert.are.same({ hits = 1, misses = 1 }, DbBookInfo.getCacheStats())

        DbBookInfo.invalidate()
        DbBookInfo.getGroupedByAuthor()

        assert.are.equal(2, exec_calls)
        assert.are.same({ hits = 1, misses = 2 }, DbBookInfo.getCacheStats())
    end)

    it("keeps unchanged group shapes warm across normal tab-switch intervals", function()
        local first = DbBookInfo.getGroupedByAuthor()
        now_value = 31
        local after_thirty_seconds = DbBookInfo.getGroupedByAuthor()

        assert.are.equal(first, after_thirty_seconds)
        assert.are.equal(1, exec_calls)

        now_value = 301
        DbBookInfo.getGroupedByAuthor()
        assert.are.equal(2, exec_calls)
    end)

    it("retains only the most recent full grouping on constrained devices", function()
        limit_group_cache = true
        DbBookInfo.getGroupedByAuthor()
        DbBookInfo.getGroupedBySeries()
        DbBookInfo.getGroupedByAuthor()

        assert.are.equal(3, exec_calls)
    end)

    it("returns one tag's books from the cached tag groups", function()
        local groups = DbBookInfo.getGroupedByTags()
        local files = DbBookInfo.getTagBooks(groups[1].tag)

        assert.are.same(groups[1].files, files)
        assert.are.equal(1, exec_calls)
    end)

    it("builds a sidecar-free TBR candidate list with history first", function()
        local candidates = DbBookInfo.getTBRIndexCandidates()

        assert.are.equal(2, #candidates)
        assert.are.equal("/books/b.epub", candidates[1].path)
        assert.are.equal("Author B", candidates[1].title)
        assert.are.equal("/books/a.epub", candidates[2].path)
    end)
end)

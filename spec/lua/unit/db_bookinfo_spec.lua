describe("book info grouping cache", function()
    local exec_calls
    local DbBookInfo

    before_each(function()
        exec_calls = 0
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
        local tick = 0
        ZenSpec.replace("common/zen_logger", {
            now = function()
                tick = tick + 0.001
                return tick
            end,
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
end)

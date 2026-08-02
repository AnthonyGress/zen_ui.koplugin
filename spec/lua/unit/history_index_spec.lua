local HistoryIndex = require("common/history_index")

describe("history index", function()
    it("maps raw and normalized paths and derives descendant directory times", function()
        ZenSpec.replace("readhistory", {
            hist = {
                { file = "/sdcard/Books/Series/book.epub", time = 100 },
                { file = "/sdcard/Books/other.epub", time = 90 },
            },
            reload = function() end,
        })
        local normalize = function(path)
            return path:gsub("^/sdcard", "/storage/emulated/0")
        end
        local index = HistoryIndex.load(normalize)
        assert.are.equal(100, HistoryIndex.fileTime(index, "/sdcard/Books/Series/book.epub", normalize))
        assert.are.same({
            ["/storage/emulated/0/Books"] = 100,
            ["/storage/emulated/0/Books/Series"] = 100,
        }, HistoryIndex.maxDescendantTimes(index, {
            "/storage/emulated/0/Books",
            "/storage/emulated/0/Books/Series",
        }))
    end)
end)

describe("library statistics", function()
    before_each(function()
        local today = os.date("%Y-%m-%d")
        local old_day = os.date("%Y-%m-%d", os.time() - 400 * 86400)
        local summaries = {
            ["/books/complete.epub"] = { status = "complete", modified = today },
            ["/books/old.epub"] = { status = "complete", modified = old_day },
            ["/books/reading.epub"] = { status = "reading" },
        }

        ZenSpec.replace("common/zen_logger", {
            new = function() return { info = function() end, warn = function() end } end,
        })
        ZenSpec.replace("common/paths", {
            getHomeDir = function() return "/books" end,
            isInHomeDir = function() return true end,
        })
        ZenSpec.replace("readhistory", {
            hist = {
                { file = "/books/complete.epub" },
                { file = "/books/old.epub" },
                { file = "/books/reading.epub" },
            },
            reload = function() end,
        })
        ZenSpec.replace("docsettings", {
            hasSidecarFile = function() return true end,
            open = function(_, file)
                return { readSetting = function() return summaries[file] end }
            end,
        })
        ZenSpec.unload("common/db_library")
    end)

    it("counts completed books by their completion date", function()
        local counts = require("common/db_library").getBookCounts()

        assert.are.equal(2, counts.finished)
        assert.are.equal(1, counts.finished_this_month)
        assert.are.equal(1, counts.finished_this_year)
    end)
end)

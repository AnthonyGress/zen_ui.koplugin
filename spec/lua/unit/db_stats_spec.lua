describe("statistics database", function()
    local conn
    local row_values
    local sqls
    local flushes

    before_each(function()
        row_values = {}
        sqls = {}
        flushes = 0
        conn = {
            rowexec = function(_self, sql)
                sqls[#sqls + 1] = sql
                return unpack(row_values)
            end,
            close = function() end,
        }
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return { warn = function() end }
            end,
        })
        ZenSpec.replace("common/db_connection", {
            getStatsDbPath = function() return "/stats.sqlite3" end,
            open = function() return conn end,
        })
        ZenSpec.unload("common/db_stats")
    end)

    after_each(function()
        ZenSpec.unload("common/db_stats")
    end)

    it("builds one query containing only the requested book details", function()
        local StatsDB = require("common/db_stats")
        local stats_plugin = {
            settings = { is_enabled = true },
            id_curr_book = 42,
            insertDB = function() flushes = flushes + 1 end,
        }

        row_values = { 7260, 12, 1800 }
        local all = StatsDB.queryBookDetails(stats_plugin, {
            read_time = true,
            time_remaining = true,
            pages_today = true,
            time_today = true,
        })

        assert.are.equal(1, flushes)
        assert.are.equal(1, #sqls)
        assert.is_truthy(sqls[1]:find("book_stats AS", 1, true))
        assert.is_truthy(sqls[1]:find("today_stats AS", 1, true))
        assert.are.same({ read_time = 7260, pages_today = 12, time_today = 1800 }, all)

        row_values = { 9 }
        local daily_pages = StatsDB.queryBookDetails(stats_plugin, {
            time_remaining = true,
            pages_today = true,
        })

        assert.are.equal(2, flushes)
        assert.are.equal(2, #sqls)
        assert.is_nil(sqls[2]:find("book_stats AS", 1, true))
        assert.is_nil(sqls[2]:find("sum(duration) AS duration", 1, true))
        assert.are.same({ pages_today = 9 }, daily_pages)
    end)

    it("starts weekly home stats at local Sunday midnight", function()
        local StatsDB = require("common/db_stats")
        local period_starts
        for i = 1, 20 do
            local name, value = debug.getupvalue(StatsDB.queryHomeStats, i)
            if not name then break end
            if name == "period_starts" then period_starts = value end
        end
        local expected = os.time({
            year = 2026, month = 8, day = 30,
            hour = 0, min = 0, sec = 0,
        })

        assert.are.equal(expected, period_starts({
            year = 2026, month = 8, day = 31, wday = 2,
        }).period_begin)
    end)
end)

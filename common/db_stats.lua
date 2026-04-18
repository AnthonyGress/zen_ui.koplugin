-- common/db_stats.lua
-- Queries KOReader's statistics.sqlite3 database.
-- Returns aggregated reading stats without touching library status,
-- which is handled by db_library.lua.

local logger = require("logger")
local DBConn = require("common/db_connection")

local StatsDB = {}

-- Returns a stats table:
-- {
--   today_pages        number
--   today_duration     number  (seconds)
--   week_pages         number
--   week_duration      number  (seconds)
--   week_daily         list of { date, pages, duration }
--   streak             number  (consecutive reading days)
--   total_books        number  (distinct books with any page_stat row)
-- }
function StatsDB.queryStats()
    local stats = {
        today_pages         = 0,
        today_duration      = 0,
        week_pages          = 0,
        week_duration       = 0,
        streak              = 0,
        total_books         = 0,
        week_daily          = {},
        -- lifetime aggregates (from book table)
        lifetime_read_time  = 0,
        lifetime_pages      = 0,
        books_read          = 0,
        avg_time_per_book   = 0,
        -- personal records (peak durations + representative timestamps for date labels)
        peak_day_duration   = 0,
        peak_day_ts         = nil,
        peak_week_duration  = 0,
        peak_week_ts        = nil,
        peak_month_duration = 0,
        peak_month_ts       = nil,
        -- this-month and this-year aggregates
        month_pages         = 0,
        month_duration      = 0,
        year_pages          = 0,
        year_duration       = 0,
        -- distinct books with any session in each period
        books_this_week     = 0,
        books_this_month    = 0,
        books_this_year     = 0,
    }

    local db_path = DBConn.getStatsDbPath()
    local conn, err = DBConn.open(db_path)
    if not conn then
        logger.warn("zen-ui db_stats: cannot open DB:", err)
        return stats
    end

    local one_day = 86400

    local ok, query_err = pcall(function()
        -- Time boundaries
        local now_t = os.date("*t")
        local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
        local start_today    = os.time() - from_begin_day
        local period_begin   = os.time() - 6 * one_day - from_begin_day

        -- Today
        local sql_today = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local p, d = conn:rowexec(string.format(sql_today, start_today))
        stats.today_pages    = tonumber(p) or 0
        stats.today_duration = tonumber(d) or 0
        logger.info("zen-ui db_stats: today pages=", stats.today_pages,
                    "duration=", stats.today_duration)

        -- Last 7 days (totals)
        local sql_week = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local wp, wd = conn:rowexec(string.format(sql_week, period_begin))
        stats.week_pages    = tonumber(wp) or 0
        stats.week_duration = tonumber(wd) or 0
        logger.info("zen-ui db_stats: week pages=", stats.week_pages,
                    "duration=", stats.week_duration)

        -- Last 7 days (daily breakdown)
        -- NOTE: %% in the format string becomes % after string.format(); SQLite
        -- then receives strftime('%Y-%m-%d', …) which is what it expects.
        local sql_daily = [[
            SELECT dates, count(*) AS pages, sum(sum_duration) AS durations
            FROM (
                SELECT strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                       sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page, dates
            )
            GROUP BY dates
            ORDER BY dates DESC;
        ]]
        local result = conn:exec(string.format(sql_daily, period_begin))
        if result then
            for i = 1, #result.dates do
                table.insert(stats.week_daily, {
                    date     = result.dates[i],
                    pages    = tonumber(result[2][i]) or 0,
                    duration = tonumber(result[3][i]) or 0,
                })
            end
        end

        -- Total books with reading sessions
        local sql_total = "SELECT count(DISTINCT id_book) FROM page_stat;"
        local ok_tot, total = pcall(conn.rowexec, conn, sql_total)
        if not ok_tot then
            logger.warn("zen-ui db_stats: total_books query error:", total)
        end
        stats.total_books = tonumber(total) or 0
        logger.info("zen-ui db_stats: total_books=", stats.total_books)

        -- ── Reading streak ───────────────────────────────────────────────────
        -- Static SQL — no string.format(), so % is passed to SQLite directly.
        local sql_streak = [[
            SELECT DISTINCT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS day
            FROM page_stat
            WHERE duration > 0
            ORDER BY day DESC;
        ]]
        local ok_streak, streak_result = pcall(conn.exec, conn, sql_streak)
        if not ok_streak then
            logger.warn("zen-ui db_stats: streak query error:", streak_result)
            streak_result = nil
        end
        if streak_result and streak_result.day then
            local today_str     = os.date("%Y-%m-%d")
            local yesterday_str = os.date("%Y-%m-%d", os.time() - one_day)
            local most_recent   = streak_result.day[1]
            if most_recent == today_str or most_recent == yesterday_str then
                local streak   = 0
                local expected = most_recent
                for i = 1, #streak_result.day do
                    if streak_result.day[i] == expected then
                        streak = streak + 1
                        local y, mo, dd = expected:match("(%d+)-(%d+)-(%d+)")
                        local noon = os.time({
                            year  = tonumber(y),
                            month = tonumber(mo),
                            day   = tonumber(dd),
                            hour  = 12, min = 0, sec = 0,
                        })
                        expected = os.date("%Y-%m-%d", noon - one_day)
                    else
                        break
                    end
                end
                stats.streak = streak
            end
        end
        logger.info("zen-ui db_stats: streak=", stats.streak)

        -- ── Lifetime aggregates (book table) ─────────────────────────────────
        -- Four columns in one query: total_read_time sum, total_read_pages sum,
        -- book count, average read time (only for books with recorded time).
        -- Wrapped in its own pcall so a missing book table doesn't break the rest.
        local sql_lifetime = [[
            SELECT
                COALESCE(SUM(total_read_time), 0),
                COALESCE(SUM(total_read_pages), 0),
                COUNT(*),
                COALESCE(AVG(CASE WHEN total_read_time > 0
                                 THEN total_read_time END), 0)
            FROM book;
        ]]
        local ok_lt, lt1, lt2, lt3, lt4 = pcall(conn.rowexec, conn, sql_lifetime)
        if ok_lt then
            stats.lifetime_read_time = tonumber(lt1) or 0
            stats.lifetime_pages     = tonumber(lt2) or 0
            stats.books_read         = tonumber(lt3) or 0
            stats.avg_time_per_book  = math.floor(tonumber(lt4) or 0)
        else
            logger.warn("zen-ui db_stats: lifetime query error:", lt1)
        end
        logger.info("zen-ui db_stats: lifetime_read_time=", stats.lifetime_read_time,
                    "books_read=", stats.books_read)

        -- ── Personal records (peak daily / weekly / monthly duration) ─────────
        -- Queries run directly against page_stat_data (indexed on start_time)
        -- rather than the page_stat view, since only durations matter here.
        -- Each query returns (total_duration, rep_ts) for the peak period.
        -- ORDER BY + LIMIT 1 replaces COALESCE(MAX(...)) so we also get a
        -- representative timestamp that can be formatted into a date label.
        -- When the table is empty, rowexec returns nil for both columns.
        local sql_peak_day = [[
            SELECT day_total, rep_ts
            FROM (
                SELECT SUM(duration) AS day_total, MIN(start_time) AS rep_ts
                FROM page_stat_data
                GROUP BY strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime')
            )
            ORDER BY day_total DESC
            LIMIT 1;
        ]]
        local ok_pd, pd_dur, pd_ts = pcall(conn.rowexec, conn, sql_peak_day)
        stats.peak_day_duration = ok_pd and (tonumber(pd_dur) or 0) or 0
        stats.peak_day_ts       = ok_pd and tonumber(pd_ts) or nil

        local sql_peak_week = [[
            SELECT week_total, rep_ts
            FROM (
                SELECT SUM(duration) AS week_total, MIN(start_time) AS rep_ts
                FROM page_stat_data
                GROUP BY strftime('%Y-%W', start_time, 'unixepoch', 'localtime')
            )
            ORDER BY week_total DESC
            LIMIT 1;
        ]]
        local ok_pw, pw_dur, pw_ts = pcall(conn.rowexec, conn, sql_peak_week)
        stats.peak_week_duration = ok_pw and (tonumber(pw_dur) or 0) or 0
        stats.peak_week_ts       = ok_pw and tonumber(pw_ts) or nil

        local sql_peak_month = [[
            SELECT month_total, rep_ts
            FROM (
                SELECT SUM(duration) AS month_total, MIN(start_time) AS rep_ts
                FROM page_stat_data
                GROUP BY strftime('%Y-%m', start_time, 'unixepoch', 'localtime')
            )
            ORDER BY month_total DESC
            LIMIT 1;
        ]]
        local ok_pm, pm_dur, pm_ts = pcall(conn.rowexec, conn, sql_peak_month)
        stats.peak_month_duration = ok_pm and (tonumber(pm_dur) or 0) or 0
        stats.peak_month_ts       = ok_pm and tonumber(pm_ts) or nil
        logger.info("zen-ui db_stats: peak_day=", stats.peak_day_duration,
                    "peak_week=", stats.peak_week_duration,
                    "peak_month=", stats.peak_month_duration)

        -- ── Month and Year aggregates ─────────────────────────────────────────
        local now_t_my = os.date("*t")
        local start_month = os.time({
            year = now_t_my.year, month = now_t_my.month, day = 1,
            hour = 0, min = 0, sec = 0,
        })
        local start_year = os.time({
            year = now_t_my.year, month = 1, day = 1,
            hour = 0, min = 0, sec = 0,
        })

        local sql_month_agg = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local ok_mo, mo_p, mo_d = pcall(conn.rowexec, conn,
            string.format(sql_month_agg, start_month))
        stats.month_pages    = ok_mo and (tonumber(mo_p) or 0) or 0
        stats.month_duration = ok_mo and (tonumber(mo_d) or 0) or 0

        local sql_year_agg = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local ok_yr, yr_p, yr_d = pcall(conn.rowexec, conn,
            string.format(sql_year_agg, start_year))
        stats.year_pages    = ok_yr and (tonumber(yr_p) or 0) or 0
        stats.year_duration = ok_yr and (tonumber(yr_d) or 0) or 0

        -- Distinct books with reading sessions in each period
        local ok_bw, bw_v = pcall(conn.rowexec, conn, string.format(
            "SELECT count(DISTINCT id_book) FROM page_stat_data WHERE start_time >= %d;",
            period_begin))
        stats.books_this_week = ok_bw and (tonumber(bw_v) or 0) or 0

        local ok_bm, bm_v = pcall(conn.rowexec, conn, string.format(
            "SELECT count(DISTINCT id_book) FROM page_stat_data WHERE start_time >= %d;",
            start_month))
        stats.books_this_month = ok_bm and (tonumber(bm_v) or 0) or 0

        local ok_by, by_v = pcall(conn.rowexec, conn, string.format(
            "SELECT count(DISTINCT id_book) FROM page_stat_data WHERE start_time >= %d;",
            start_year))
        stats.books_this_year = ok_by and (tonumber(by_v) or 0) or 0
        logger.info("zen-ui db_stats: month_pages=", stats.month_pages,
                    "year_pages=", stats.year_pages,
                    "books_this_week=", stats.books_this_week,
                    "books_this_month=", stats.books_this_month,
                    "books_this_year=", stats.books_this_year)
    end)

    if not ok then
        logger.warn("zen-ui db_stats: query failed:", query_err)
    end

    conn:close()
    return stats
end

return StatsDB

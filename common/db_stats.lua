-- common/db_stats.lua
-- Queries KOReader's statistics.sqlite3 database.
-- Returns aggregated reading stats without touching library status,
-- which is handled by db_library.lua.

local logger = require("common/zen_logger").new("db_stats")
local DBConn = require("common/db_connection")

local StatsDB = {}

local function get_stats_plugin()
    local ok_loader, PluginLoader = pcall(require, "pluginloader")
    if not ok_loader or not PluginLoader or type(PluginLoader.getPluginInstance) ~= "function" then
        return nil
    end
    local stats_plugin = PluginLoader:getPluginInstance("statistics")
    if type(stats_plugin) ~= "table" then return nil end
    return stats_plugin
end

local function flush_pending_stats()
    local stats_plugin = get_stats_plugin()
    if not stats_plugin or type(stats_plugin.insertDB) ~= "function" then return end
    if type(stats_plugin.isEnabled) == "function" and not stats_plugin:isEnabled() then return end
    pcall(stats_plugin.insertDB, stats_plugin)
end

local function period_starts()
    local one_day = 86400
    local now_t = os.date("*t")
    local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
    local now_ts = os.time()
    return {
        one_day = one_day,
        start_today = now_ts - from_begin_day,
        period_begin = now_ts - 6 * one_day - from_begin_day,
        start_month = os.time({
            year = now_t.year, month = now_t.month, day = 1,
            hour = 0, min = 0, sec = 0,
        }),
        start_year = os.time({
            year = now_t.year, month = 1, day = 1,
            hour = 0, min = 0, sec = 0,
        }),
    }
end

local function query_period_stats(conn, start_time, need_pages, need_duration)
    if need_pages and need_duration then
        local sql = [[
            SELECT count(*), sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        local pages, duration = conn:rowexec(string.format(sql, start_time))
        return tonumber(pages) or 0, tonumber(duration) or 0
    end
    if need_pages then
        local sql = [[
            SELECT count(*)
            FROM (
                SELECT 1
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        return tonumber(conn:rowexec(string.format(sql, start_time))) or 0, 0
    end
    if need_duration then
        local sql = [[
            SELECT sum(sum_duration)
            FROM (
                SELECT sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page
            );
        ]]
        return 0, tonumber(conn:rowexec(string.format(sql, start_time))) or 0
    end
    return 0, 0
end

local function query_streak(conn, one_day)
    local sql_streak = [[
        SELECT DISTINCT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS day
        FROM page_stat
        WHERE duration > 0
        ORDER BY day DESC;
    ]]
    local ok_streak, streak_result = pcall(conn.exec, conn, sql_streak)
    if not ok_streak then
        logger.warn("streak query error:", streak_result)
        return 0
    end
    if not (streak_result and streak_result.day) then return 0 end

    local today_str = os.date("%Y-%m-%d")
    local yesterday_str = os.date("%Y-%m-%d", os.time() - one_day)
    local most_recent = streak_result.day[1]
    if most_recent ~= today_str and most_recent ~= yesterday_str then return 0 end

    local streak = 0
    local expected = most_recent
    for i = 1, #streak_result.day do
        if streak_result.day[i] ~= expected then break end
        streak = streak + 1
        local y, mo, dd = expected:match("(%d+)-(%d+)-(%d+)")
        local noon = os.time({
            year = tonumber(y),
            month = tonumber(mo),
            day = tonumber(dd),
            hour = 12, min = 0, sec = 0,
        })
        expected = os.date("%Y-%m-%d", noon - one_day)
    end
    return streak
end

local function field_set(fields)
    local set = {}
    if type(fields) == "table" then
        for key, value in pairs(fields) do
            if type(key) == "string" and value == true then
                set[key] = true
            elseif type(value) == "string" then
                set[value] = true
            end
        end
    end
    if next(set) == nil then
        set.today_pages = true
        set.today_duration = true
        set.week_pages = true
        set.week_duration = true
        set.streak = true
    end
    return set
end

function StatsDB.queryBookAveragePageTime(path, md5)
    if type(md5) ~= "string" or md5 == "" then
        local ok_util, util = pcall(require, "util")
        if not ok_util or not util or type(util.partialMD5) ~= "function" then return nil end
        local ok_md5, computed_md5 = pcall(util.partialMD5, path)
        if not ok_md5 then return nil end
        md5 = computed_md5
    end
    if type(md5) ~= "string" or md5 == "" then return nil end

    flush_pending_stats()

    local db_path = DBConn.getStatsDbPath()
    local conn, err = DBConn.open(db_path)
    if not conn then
        logger.warn("cannot open DB:", err)
        return nil
    end

    local settings = G_reader_settings:readSetting("statistics")
    local max_sec = type(settings) == "table" and tonumber(settings.max_sec) or 120
    local stmt
    local ok, result = pcall(function()
        stmt = conn:prepare([[
            SELECT count(*), sum(page_duration), (
                SELECT pages FROM book
                WHERE md5 = ?
                ORDER BY last_open DESC
                LIMIT 1
            )
            FROM (
                SELECT min(sum(duration), ?) AS page_duration
                FROM page_stat
                WHERE id_book = (
                    SELECT id FROM book
                    WHERE md5 = ?
                    ORDER BY last_open DESC
                    LIMIT 1
                )
                GROUP BY page
            );
        ]])
        return stmt:reset():bind(md5, max_sec, md5):step()
    end)
    if stmt then stmt:close() end
    conn:close()

    if not ok then
        logger.warn("book timing query failed:", result)
        return nil
    end
    local pages = result and tonumber(result[1]) or 0
    local duration = result and tonumber(result[2]) or 0
    local total_pages = result and tonumber(result[3]) or nil
    if pages <= 0 or duration <= 0 then return nil, total_pages end
    return duration / pages, total_pages
end

function StatsDB.queryHomeStats(fields)
    local stats = {
        today_pages = 0,
        today_duration = 0,
        week_pages = 0,
        week_duration = 0,
        month_pages = 0,
        month_duration = 0,
        year_pages = 0,
        year_duration = 0,
        streak = 0,
    }
    local requested = field_set(fields)

    flush_pending_stats()

    local db_path = DBConn.getStatsDbPath()
    local conn, err = DBConn.open(db_path)
    if not conn then
        logger.warn("cannot open DB:", err)
        return stats
    end

    local starts = period_starts()
    local ok, query_err = pcall(function()
        if requested.today_pages or requested.today_duration then
            stats.today_pages, stats.today_duration =
                query_period_stats(conn, starts.start_today,
                    requested.today_pages, requested.today_duration)
        end
        if requested.week_pages or requested.week_duration then
            stats.week_pages, stats.week_duration =
                query_period_stats(conn, starts.period_begin,
                    requested.week_pages, requested.week_duration)
        end
        if requested.month_pages or requested.month_duration then
            stats.month_pages, stats.month_duration =
                query_period_stats(conn, starts.start_month,
                    requested.month_pages, requested.month_duration)
        end
        if requested.year_pages or requested.year_duration then
            stats.year_pages, stats.year_duration =
                query_period_stats(conn, starts.start_year,
                    requested.year_pages, requested.year_duration)
        end
        if requested.streak then
            stats.streak = query_streak(conn, starts.one_day)
        end
    end)
    if not ok then
        logger.warn("home query failed:", query_err)
    end

    conn:close()
    return stats
end

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

    flush_pending_stats()

    local db_path = DBConn.getStatsDbPath()
    local conn, err = DBConn.open(db_path)
    if not conn then
        logger.warn("cannot open DB:", err)
        return stats
    end

    local one_day = 86400

    local ok, query_err = pcall(function()
        -- Time boundaries
        local now_t = os.date("*t")
        local from_begin_day = now_t.hour * 3600 + now_t.min * 60 + now_t.sec
        local now_ts = os.time()
        local start_today = now_ts - from_begin_day
        local period_begin = now_ts - 6 * one_day - from_begin_day
        local start_month = os.time({
            year = now_t.year, month = now_t.month, day = 1,
            hour = 0, min = 0, sec = 0,
        })
        local start_year = os.time({
            year = now_t.year, month = 1, day = 1,
            hour = 0, min = 0, sec = 0,
        })

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
        logger.info("today pages=", stats.today_pages,
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
        logger.info("week pages=", stats.week_pages,
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
            logger.warn("total_books query error:", total)
        end
        stats.total_books = tonumber(total) or 0
        logger.info("total_books=", stats.total_books)

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
            logger.warn("streak query error:", streak_result)
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
        logger.info("streak=", stats.streak)

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
            logger.warn("lifetime query error:", lt1)
        end
        logger.info("lifetime_read_time=", stats.lifetime_read_time,
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
        logger.info("peak_day=", stats.peak_day_duration,
                    "peak_week=", stats.peak_week_duration,
                    "peak_month=", stats.peak_month_duration)

        -- ── Month and Year aggregates ─────────────────────────────────────────

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

        logger.info("page totals:",
            "today=", stats.today_pages,
            "week=", stats.week_pages)
        logger.info("month_pages=", stats.month_pages,
                    "year_pages=", stats.year_pages,
                    "books_this_week=", stats.books_this_week,
                    "books_this_month=", stats.books_this_month,
                    "books_this_year=", stats.books_this_year)
    end)

    if not ok then
        logger.warn("query failed:", query_err)
    end

    conn:close()
    return stats
end

local function start_of_day(ts)
    local t = os.date("*t", ts or os.time())
    return os.time({
        year = t.year, month = t.month, day = t.day,
        hour = 0, min = 0, sec = 0,
    })
end

local function valid_series_days(days)
    days = tonumber(days) or 14
    if days == 7 or days == 14 or days == 30 or days == 90 then
        return days
    end
    return 14
end

function StatsDB.queryDailySeries(days)
    days = valid_series_days(days)
    local today_start = start_of_day()
    local start_time = today_start - (days - 1) * 86400
    local series = {}
    local by_date = {}

    for offset = days - 1, 0, -1 do
        local date = os.date("%Y-%m-%d", today_start - offset * 86400)
        local row = { date = date, pages = 0, duration = 0, books = 0 }
        series[#series + 1] = row
        by_date[date] = row
    end

    flush_pending_stats()

    local db_path = DBConn.getStatsDbPath()
    local conn, err = DBConn.open(db_path)
    if not conn then
        logger.warn("zen-ui db_stats: cannot open DB:", err)
        return series
    end

    local ok, query_err = pcall(function()
        local sql = [[
            SELECT dates, count(*) AS pages, sum(sum_duration) AS durations,
                   count(DISTINCT id_book) AS books
            FROM (
                SELECT id_book, page,
                       strftime('%%Y-%%m-%%d', start_time, 'unixepoch', 'localtime') AS dates,
                       sum(duration) AS sum_duration
                FROM page_stat
                WHERE start_time >= %d
                GROUP BY id_book, page, dates
            )
            GROUP BY dates
            ORDER BY dates;
        ]]
        local result = conn:exec(string.format(sql, start_time))
        if not (result and result.dates) then return end
        for i = 1, #result.dates do
            local row = by_date[result.dates[i]]
            if row then
                row.pages = tonumber(result.pages and result.pages[i] or result[2] and result[2][i]) or 0
                row.duration = tonumber(result.durations and result.durations[i] or result[3] and result[3][i]) or 0
                row.books = tonumber(result.books and result.books[i] or result[4] and result[4][i]) or 0
            end
        end
    end)
    if not ok then
        logger.warn("zen-ui db_stats: daily series query failed:", query_err)
    end

    conn:close()
    return series
end

function StatsDB.queryBooksForPeriod(period_begin, period_end)
    period_begin = tonumber(period_begin) or 0
    period_end = tonumber(period_end) or period_begin

    flush_pending_stats()

    local db_path = DBConn.getStatsDbPath()
    local conn, err = DBConn.open(db_path)
    if not conn then
        logger.warn("zen-ui db_stats: cannot open DB:", err)
        return {}
    end

    local books = {}
    local ok, query_err = pcall(function()
        local sql = [[
            SELECT book_tbl.title AS title,
                   count(DISTINCT page_stat_tbl.page) AS pages,
                   sum(page_stat_tbl.duration) AS duration,
                   book_tbl.id AS book_id
            FROM page_stat AS page_stat_tbl, book AS book_tbl
            WHERE page_stat_tbl.id_book = book_tbl.id
              AND page_stat_tbl.start_time BETWEEN %d AND %d
            GROUP BY book_tbl.id
            ORDER BY duration DESC, title;
        ]]
        local result = conn:exec(string.format(sql, period_begin + 1, period_end))
        if not (result and result.title) then return end
        for i = 1, #result.title do
            books[#books + 1] = {
                title = tostring(result.title[i] or ""),
                pages = tonumber(result.pages and result.pages[i] or result[2] and result[2][i]) or 0,
                duration = tonumber(result.duration and result.duration[i] or result[3] and result[3][i]) or 0,
                book_id = tonumber(result.book_id and result.book_id[i] or result[4] and result[4][i]) or nil,
            }
        end
    end)
    if not ok then
        logger.warn("zen-ui db_stats: books for period query failed:", query_err)
    end

    conn:close()
    return books
end

return StatsDB

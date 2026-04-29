-- common/db_bookinfo.lua
-- Queries KOReader's bookinfo_cache.sqlite3 to group books by author or series.
-- Used by the Authors and Series navbar tabs.

local logger = require("logger")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")

local M = {}

-- Returns the path to bookinfo_cache.sqlite3, or nil if not found.
local function getDbPath()
    local ok, DataStorage = pcall(require, "datastorage")
    if not ok then return nil end
    local path = DataStorage:getSettingsDir() .. "/bookinfo_cache.sqlite3"
    if lfs.attributes(path, "mode") == "file" then return path end
    return nil
end

-- Returns the user's home dir (library root), stripped of trailing slash.
local function getHomeDir()
    local g = rawget(_G, "G_reader_settings")
    local d = g and g:readSetting("home_dir")
    if d and d ~= "" then
        return d:gsub("/*$", "")
    end
    return nil
end

-- Returns the authors string as-is (no splitting) so multi-author books
-- are grouped under their combined author string.
local function splitAuthors(authors_str)
    if not authors_str or authors_str == "" then return {} end
    local trimmed = authors_str:match("^%s*(.-)%s*$")
    if trimmed == "" then return {} end
    return { trimmed }
end

-- Returns a sorted list of author groups:
--   { { author="Name", files={"/abs/path", ...} }, ... }
-- Only includes books within home_dir that still exist on disk.
-- Each book appears under every author it has (multi-author support).
function M.getGroupedByAuthor()
    local db_path = getDbPath()
    if not db_path then
        logger.warn("zen-ui db_bookinfo: bookinfo_cache.sqlite3 not found")
        return {}
    end

    local home_dir = getHomeDir()
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then
        logger.warn("zen-ui db_bookinfo: failed to open DB:", conn)
        return {}
    end
    conn:set_busy_timeout(3000)

    local author_map = {}  -- author -> { files }

    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, authors
            FROM bookinfo
            WHERE in_progress = 0
              AND authors IS NOT NULL
              AND authors != ''
            ORDER BY authors
        ]]
        local res = conn:exec(sql)
        if not res then return end

        local dirs      = res[1] or {}
        local filenames = res[2] or {}
        local authors_col = res[3] or {}
        logger.info("zen-ui db_bookinfo: getGroupedByAuthor rows from SQL:", #dirs)

        for i = 1, #dirs do
            local dir    = dirs[i]
            local fname  = filenames[i]
            local authors_str = authors_col[i]

            if not dir or not fname or not authors_str then goto continue end

            local filepath = dir .. fname

            -- Skip if outside home_dir
            if home_dir and filepath:sub(1, #home_dir) ~= home_dir then
                goto continue
            end

            -- Skip if file no longer exists
            if lfs.attributes(filepath, "mode") ~= "file" then
                goto continue
            end

            local author_list = splitAuthors(authors_str)
            for _, author in ipairs(author_list) do
                if not author_map[author] then
                    author_map[author] = {}
                end
                table.insert(author_map[author], filepath)
            end

            ::continue::
        end
    end)

    conn:close()

    if not ok2 then
        logger.warn("zen-ui db_bookinfo: query error:", err)
        return {}
    end

    -- Build sorted list
    local groups = {}
    for author, files in pairs(author_map) do
        table.insert(groups, { author = author, files = files })
    end
    table.sort(groups, function(a, b)
        return a.author:lower() < b.author:lower()
    end)

    logger.dbg("zen-ui db_bookinfo: getGroupedByAuthor result:", #groups, "authors")
    return groups
end

-- Returns a sorted list of series groups:
--   { { series="Name", items={ {file="/abs/path", series_index=N}, ... } }, ... }
-- Items within each series are sorted by series_index (then filename as tiebreak).
-- Only includes books within home_dir that still exist on disk.
function M.getGroupedBySeries()
    local db_path = getDbPath()
    if not db_path then
        logger.warn("zen-ui db_bookinfo: bookinfo_cache.sqlite3 not found")
        return {}
    end

    local home_dir = getHomeDir()
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then
        logger.warn("zen-ui db_bookinfo: failed to open DB:", conn)
        return {}
    end
    conn:set_busy_timeout(3000)

    local series_map = {}  -- series_name -> { {file, series_index, filename} }

    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, series, series_index
            FROM bookinfo
            WHERE in_progress = 0
              AND series IS NOT NULL
              AND series != ''
            ORDER BY series, series_index
        ]]
        local res = conn:exec(sql)
        if not res then return end

        local dirs         = res[1] or {}
        local filenames    = res[2] or {}
        local series_col   = res[3] or {}
        local idx_col      = res[4] or {}
        logger.dbg("zen-ui db_bookinfo: getGroupedBySeries rows from SQL:", #dirs)

        for i = 1, #dirs do
            local dir    = dirs[i]
            local fname  = filenames[i]
            local series = series_col[i]
            local sidx   = tonumber(idx_col[i])

            if not dir or not fname or not series then goto continue end

            local filepath = dir .. fname

            if home_dir and filepath:sub(1, #home_dir) ~= home_dir then
                goto continue
            end

            if lfs.attributes(filepath, "mode") ~= "file" then
                goto continue
            end

            if not series_map[series] then
                series_map[series] = {}
            end
            table.insert(series_map[series], {
                file         = filepath,
                series_index = sidx,
                filename     = fname,
            })

            ::continue::
        end
    end)

    conn:close()

    if not ok2 then
        logger.warn("zen-ui db_bookinfo: query error:", err)
        return {}
    end

    local groups = {}
    for series, items in pairs(series_map) do
        -- Sort by series_index, then by filename as tiebreak
        table.sort(items, function(a, b)
            local ia = a.series_index or 0
            local ib = b.series_index or 0
            if ia ~= ib then return ia < ib end
            return (a.filename or "") < (b.filename or "")
        end)
        table.insert(groups, { series = series, items = items })
    end
    table.sort(groups, function(a, b)
        return a.series:lower() < b.series:lower()
    end)

    logger.dbg("zen-ui db_bookinfo: getGroupedBySeries result:", #groups, "series")
    return groups
end

-- Returns a flat list of file paths whose sidecar summary.status == "abandoned"
-- (displayed in the UI as "To Be Read").
function M.getTBRBooks()
    local db_path = getDbPath()
    if not db_path then
        logger.warn("zen-ui db_bookinfo: getTBRBooks: bookinfo_cache.sqlite3 not found")
        return {}
    end

    local home_dir = getHomeDir()
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then
        logger.warn("zen-ui db_bookinfo: getTBRBooks: failed to open DB:", conn)
        return {}
    end
    conn:set_busy_timeout(3000)

    local candidates = {}

    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename
            FROM bookinfo
            WHERE in_progress = 0
            ORDER BY filename
        ]]
        local res = conn:exec(sql)
        if not res then return end

        local dirs      = res[1] or {}
        local filenames = res[2] or {}

        for i = 1, #dirs do
            local dir   = dirs[i]
            local fname = filenames[i]
            if not dir or not fname then goto continue end
            local filepath = dir .. fname
            if home_dir and filepath:sub(1, #home_dir) ~= home_dir then
                goto continue
            end
            if lfs.attributes(filepath, "mode") ~= "file" then
                goto continue
            end
            table.insert(candidates, filepath)
            ::continue::
        end
    end)

    conn:close()

    if not ok2 then
        logger.warn("zen-ui db_bookinfo: getTBRBooks query error:", err)
        return {}
    end

    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not ok_ds then return {} end

    local result = {}
    for _, filepath in ipairs(candidates) do
        if DocSettings:hasSidecarFile(filepath) then
            local ok3, doc = pcall(DocSettings.open, DocSettings, filepath)
            if ok3 and doc then
                local summary = doc:readSetting("summary")
                if summary and summary.status == "abandoned" then
                    table.insert(result, filepath)
                end
            end
        end
    end

    logger.dbg("zen-ui db_bookinfo: getTBRBooks result:", #result, "books")
    return result
end

-- Returns the total number of fully-indexed books in the bookinfo cache
-- that live under home_dir. Uses a SQL COUNT so no lfs calls are made.
function M.getTotalBookCount()
    local db_path = getDbPath()
    if not db_path then return 0 end

    local home_dir = getHomeDir()
    local ok, conn = pcall(SQ3.open, db_path)
    if not ok then return 0 end
    conn:set_busy_timeout(3000)

    local count = 0
    local ok2, err = pcall(function()
        local sql, row
        if home_dir then
            -- directory values include a trailing slash, e.g. "/storage/books/"
            -- LIKE prefix match covers all subdirectories too
            sql = string.format(
                "SELECT COUNT(*) FROM bookinfo WHERE in_progress = 0 AND directory LIKE %q;",
                home_dir .. "%")
        else
            sql = "SELECT COUNT(*) FROM bookinfo WHERE in_progress = 0;"
        end
        row = conn:rowexec(sql)
        count = tonumber(row) or 0
    end)
    conn:close()
    if not ok2 then
        logger.warn("zen-ui db_bookinfo: getTotalBookCount error:", err)
    end
    logger.info("zen-ui db_bookinfo: total_book_count=", count)
    return count
end

return M

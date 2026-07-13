-- common/db_bookinfo.lua
-- Queries KOReader's bookinfo_cache.sqlite3 to group books by author or series.
-- Used by the Authors and Series navbar tabs.

local logger = require("common/zen_logger").new("db_bookinfo")
local lfs = require("libs/libkoreader-lfs")
local paths = require("common/paths")
local bimOk, BookInfoManager = pcall(require, "bookinfomanager")

local M = {}

-- Returns the authors string as-is (no splitting) so multi-author books
-- are grouped under their combined author string.
local function splitAuthors(authors_str)
    if not authors_str or authors_str == "" then return {} end
    local trimmed = authors_str:match("^%s*(.-)%s*$")
    if trimmed == "" then return {} end
    return { trimmed }
end

local function get_valid_book_path(home_dir, directory, filename)
    if not directory or not filename then return nil end
    local raw_filepath = directory .. filename
    local normalized_filepath = paths.normPath(raw_filepath)
    if home_dir and not paths.isInHomeDir(normalized_filepath) then return nil end
    if lfs.attributes(normalized_filepath, "mode") ~= "file" then return nil end
    -- Keep the database key: BookInfoManager and DocSettings may not use the
    -- normalized path on Android symlinked storage.
    return raw_filepath
end

local function for_each_valid_book_row(conn, sql, callback)
    local result = conn:exec(sql)
    if not result then return 0 end
    local directories = result[1] or {}
    local filenames = result[2] or {}
    local home_dir = paths.getHomeDir()
    for index = 1, #directories do
        local raw_filepath = get_valid_book_path(home_dir, directories[index], filenames[index])
        if raw_filepath then
            callback(raw_filepath, filenames[index], result, index)
        end
    end
    return #directories
end

local function sorted_groups(group_map, group_key, files_key)
    local groups = {}
    for name, files in pairs(group_map) do
        groups[#groups + 1] = { [group_key] = name, [files_key] = files }
    end
    table.sort(groups, function(a, b) return a[group_key] < b[group_key] end)
    return groups
end

-- Returns a sorted list of author groups:
--   { { author="Name", files={"/abs/path", ...} }, ... }
-- Only includes books within home_dir that still exist on disk.
-- Each book appears under every author it has (multi-author support).
function M.getGroupedByAuthor()
    if not bimOk then
        logger.warn("BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn

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
        local row_count = for_each_valid_book_row(conn, sql, function(raw_filepath, _filename, result, index)
            local authors_str = result[3] and result[3][index]
            if authors_str then
                local author_list = splitAuthors(authors_str)
                for _i, author in ipairs(author_list) do
                    if not author_map[author] then
                        author_map[author] = {}
                    end
                    table.insert(author_map[author], raw_filepath)
                end
            end
        end)
        logger.info("getGroupedByAuthor rows from SQL:", row_count)
    end)

    if not ok2 then
        logger.warn("query error:", err)
        return {}
    end

    -- Build sorted list
    local groups = sorted_groups(author_map, "author", "files")

    logger.dbg("getGroupedByAuthor result:", #groups, "authors")
    return groups
end

-- Returns a sorted list of series groups:
--   { { series="Name", items={ {file="/abs/path", series_index=N}, ... } }, ... }
-- Items within each series are sorted by series_index (then filename as tiebreak).
-- Only includes books within home_dir that still exist on disk.
function M.getGroupedBySeries()
    if not bimOk then
        logger.warn("BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn
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
        local row_count = for_each_valid_book_row(conn, sql, function(raw_filepath, filename, result, index)
            local series = result[3] and result[3][index]
            if not series then return end
            if not series_map[series] then series_map[series] = {} end
            table.insert(series_map[series], {
                file = raw_filepath,
                series_index = tonumber(result[4] and result[4][index]),
                filename = filename,
            })
        end)
        logger.dbg("getGroupedBySeries rows from SQL:", row_count)
    end)

    if not ok2 then
        logger.warn("query error:", err)
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
        return a.series < b.series
    end)

    logger.dbg("getGroupedBySeries result:", #groups, "series")
    return groups
end

-- Returns explicit TBR books plus computed-New books when configured.
function M.getTBRBooks()
    if not bimOk then
        logger.warn("BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn
    local candidates = {}

    local ok2, err = pcall(function()
        -- Query all books, not just in_progress=0.  Bookshelf (and other
        -- plugins) can set DocSettings status to "abandoned" without
        -- updating the CoverBrowser cache, so a previously-in-progress
        -- book may still have in_progress=1 here.  The authoritative
        -- filter is the sidecar check below.
        local sql = [[
            SELECT directory, filename
            FROM bookinfo
            ORDER BY filename
        ]]
        for_each_valid_book_row(conn, sql, function(raw_filepath)
            table.insert(candidates, raw_filepath)
        end)
    end)


    if not ok2 then
        logger.warn("getTBRBooks query error:", err)
        return {}
    end

    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not ok_ds then return {} end

    local BookStatus = require("common/book_status")
    local include_new = BookStatus.includeNewInTBREnabled()
    local result = {}
    for _i, filepath in ipairs(candidates) do
        if DocSettings:hasSidecarFile(filepath) then
            local ok3, doc = pcall(DocSettings.open, DocSettings, filepath)
            if ok3 and doc then
                local summary = doc:readSetting("summary")
                local status = summary and summary.status
                status = BookStatus.migrateLegacyMarker(filepath, status, doc)
                local effective_status = BookStatus.getComputedStatus(
                    filepath, status, doc:readSetting("percent_finished"), doc
                )
                if status == "abandoned"
                        or (include_new and effective_status == "new"
                            and not BookStatus.isImageFile(filepath)) then
                    table.insert(result, filepath)
                end
            end
        elseif include_new and not BookStatus.isImageFile(filepath) then
            table.insert(result, filepath)
        end
    end

    logger.dbg("getTBRBooks result:", #result, "books")
    return result
end

-- Returns a sorted list of tag groups from the keywords (Calibre tags) column:
--   { { tag="Name", files={"/abs/path", ...} }, ... }
-- Books may appear under multiple tags. Tags are split by comma and trimmed.
-- Only includes books within home_dir that still exist on disk.
function M.getGroupedByTags()
    if not bimOk then
        logger.warn("BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn
    local tag_map = {}  -- tag_name -> { file_paths }

    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, keywords
            FROM bookinfo
            WHERE keywords IS NOT NULL
              AND keywords != ''
            ORDER BY filename
        ]]
        for_each_valid_book_row(conn, sql, function(raw_filepath, _filename, result, index)
            local kw = result[3] and result[3][index]
            if kw then
                -- Split newline-separated tags (KOReader default) and also handle comma-separated.
                -- Replace commas with newlines so one gmatch handles both formats.
                local normalized = kw:gsub(",", "\n")
                for tag in normalized:gmatch("[^\n]+") do
                    local trimmed = tag:match("^%s*(.-)%s*$")
                    if trimmed and trimmed ~= "" then
                        if not tag_map[trimmed] then
                            tag_map[trimmed] = {}
                        end
                        table.insert(tag_map[trimmed], raw_filepath)
                    end
                end
            end
        end)
    end)


    if not ok2 then
        logger.warn("getGroupedByTags query error:", err)
        return {}
    end

    local groups = sorted_groups(tag_map, "tag", "files")

    logger.dbg("getGroupedByTags result:", #groups, "tags")
    return groups
end

-- Returns the total number of fully-indexed books in the bookinfo cache,
-- across all directories. Uses a SQL COUNT so no lfs calls are made.
function M.getTotalBookCount()
    if not bimOk then
        logger.warn("BookInfoManager not available")
        return {}
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn

    local count = 0
    local ok2, err = pcall(function()
        local row = conn:rowexec("SELECT COUNT(*) FROM bookinfo WHERE in_progress = 0;")
        count = tonumber(row) or 0
    end)
    if not ok2 then
        logger.warn("getTotalBookCount error:", err)
    end
    logger.info("total_book_count=", count)
    return count
end

return M

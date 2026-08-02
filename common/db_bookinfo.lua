-- common/db_bookinfo.lua
-- Queries KOReader's bookinfo_cache.sqlite3 to group books by author or series.
-- Used by the Authors and Series navbar tabs.

local zen_logger = require("common/zen_logger")
local logger = zen_logger.new("db_bookinfo")
local now = zen_logger.now
local lfs = require("libs/libkoreader-lfs")
local paths = require("common/paths")
local MemoryPolicy = require("common/memory_policy")
local bimOk, BookInfoManager = pcall(require, "bookinfomanager")

local M = {}
local GROUP_CACHE_TTL_S = 300
local group_cache = {}
local cache_hits = 0
local cache_misses = 0

local function file_signature(path)
    if not path then return "nil" end
    local attr = lfs.attributes(path)
    return table.concat({
        tostring(attr and attr.size),
        tostring(attr and attr.modification),
    }, ":")
end

local function cache_generation()
    local db_path = BookInfoManager and BookInfoManager.db_location
    return table.concat({
        tostring(paths.getHomeDir()),
        file_signature(db_path),
        file_signature(db_path and (db_path .. "-wal")),
    }, "|")
end

local function get_cached(kind)
    if MemoryPolicy.limitGroupCache() then
        for cached_kind in pairs(group_cache) do
            if cached_kind ~= kind then group_cache[cached_kind] = nil end
        end
    end
    local entry = group_cache[kind]
    if entry and entry.generation == cache_generation() and entry.expires_at > now() then
        cache_hits = cache_hits + 1
        return entry.value
    end
    group_cache[kind] = nil
    cache_misses = cache_misses + 1
end

local function save_cached(kind, value)
    if MemoryPolicy.limitGroupCache() then
        group_cache = {}
    end
    group_cache[kind] = {
        generation = cache_generation(),
        expires_at = now() + GROUP_CACHE_TTL_S,
        value = value,
    }
end

function M.invalidate()
    group_cache = {}
end

function M.getCacheStats()
    return { hits = cache_hits, misses = cache_misses }
end

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
    local started_at = now()
    if not bimOk then
        logger.warn("BookInfoManager not available")
        return {}
    end
    local cached = get_cached("authors")
    if cached then
        logger.measure("Author groups loaded", (now() - started_at) * 1000,
            "cache=hit", "groups=", #cached)
        return cached
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn

    local author_map = {}  -- author -> { files }

    local row_count = 0
    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, authors
            FROM bookinfo
            WHERE in_progress = 0
              AND authors IS NOT NULL
              AND authors != ''
            ORDER BY authors
        ]]
        row_count = for_each_valid_book_row(conn, sql, function(raw_filepath, _filename, result, index)
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
    end)

    if not ok2 then
        logger.warn("query error:", err)
        return {}
    end

    -- Build sorted list
    local groups = sorted_groups(author_map, "author", "files")
    save_cached("authors", groups)
    logger.measure("Author groups loaded", (now() - started_at) * 1000,
        "cache=miss", "rows=", row_count, "groups=", #groups)
    return groups
end

-- Returns a sorted list of series groups:
--   { { series="Name", items={ {file="/abs/path", series_index=N}, ... } }, ... }
-- Items within each series are sorted by series_index (then filename as tiebreak).
-- Only includes books within home_dir that still exist on disk.
function M.getGroupedBySeries()
    local started_at = now()
    if not bimOk then
        logger.warn("BookInfoManager not available")
        return {}
    end
    local cached = get_cached("series")
    if cached then
        logger.measure("Series groups loaded", (now() - started_at) * 1000,
            "cache=hit", "groups=", #cached)
        return cached
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn
    local series_map = {}  -- series_name -> { {file, series_index, filename} }

    local row_count = 0
    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, series, series_index
            FROM bookinfo
            WHERE in_progress = 0
              AND series IS NOT NULL
              AND series != ''
            ORDER BY series, series_index
        ]]
        row_count = for_each_valid_book_row(conn, sql, function(raw_filepath, filename, result, index)
            local series = result[3] and result[3][index]
            if not series then return end
            if not series_map[series] then series_map[series] = {} end
            table.insert(series_map[series], {
                file = raw_filepath,
                series_index = tonumber(result[4] and result[4][index]),
                filename = filename,
            })
        end)
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

    save_cached("series", groups)
    logger.measure("Series groups loaded", (now() - started_at) * 1000,
        "cache=miss", "rows=", row_count, "groups=", #groups)
    return groups
end

-- Lightweight metadata for path-list sorting. This is one batched SQLite
-- query and never asks BookInfoManager to decode covers or open documents.
function M.getLightMetadata()
    if not bimOk then return {} end
    local cached = get_cached("light_metadata")
    if cached then return cached end

    BookInfoManager:openDbConnection()
    local metadata = {}
    local ok_query, err = pcall(function()
        local sql = [[
            SELECT directory, filename, title, series, series_index
            FROM bookinfo
        ]]
        for_each_valid_book_row(BookInfoManager.db_conn, sql,
            function(filepath, _filename, result, index)
                local info = {
                    title = result[3] and result[3][index],
                    series = result[4] and result[4][index],
                    series_index = tonumber(result[5] and result[5][index]),
                }
                metadata[filepath] = info
                metadata[paths.normPath(filepath)] = info
            end)
    end)
    if not ok_query then
        logger.warn("light metadata query error:", err)
        return {}
    end
    save_cached("light_metadata", metadata)
    return metadata
end

-- Returns a sorted list of tag groups from the keywords (Calibre tags) column:
--   { { tag="Name", files={"/abs/path", ...} }, ... }
-- Books may appear under multiple tags. Tags are split by comma and trimmed.
-- Only includes books within home_dir that still exist on disk.
function M.getGroupedByTags()
    local started_at = now()
    if not bimOk then
        logger.warn("BookInfoManager not available")
        return {}
    end
    local cached = get_cached("tags")
    if cached then
        logger.measure("Tag groups loaded", (now() - started_at) * 1000,
            "cache=hit", "groups=", #cached)
        return cached
    end
    BookInfoManager:openDbConnection()
    local conn = BookInfoManager.db_conn
    local tag_map = {}  -- tag_name -> { file_paths }

    local row_count = 0
    local ok2, err = pcall(function()
        local sql = [[
            SELECT directory, filename, keywords
            FROM bookinfo
            WHERE keywords IS NOT NULL
              AND keywords != ''
            ORDER BY filename
        ]]
        row_count = for_each_valid_book_row(conn, sql, function(raw_filepath, _filename, result, index)
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
    save_cached("tags", groups)
    logger.measure("Tag groups loaded", (now() - started_at) * 1000,
        "cache=miss", "rows=", row_count, "groups=", #groups)
    return groups
end

-- Returns the books for one exact Calibre tag. Reuses the cached tag groups so
-- Home widgets and tag tabs do not issue a second database query.
function M.getTagBooks(tag_name)
    if type(tag_name) ~= "string" or tag_name == "" then return {} end
    for _i, group in ipairs(M.getGroupedByTags()) do
        if group.tag == tag_name then
            return group.files or {}
        end
    end
    return {}
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

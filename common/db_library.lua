-- common/db_library.lua
-- Determines book completion status from KOReader's actual library state.
--
-- KOReader stores book status ("reading", "complete", "abandoned") in per-book
-- sidecar directories (.sdr/), NOT in any SQL database.  The correct way to
-- query this is:
--   ReadHistory  →  gives all historically opened books (file paths)
--   DocSettings  →  reads the .sdr/ sidecar and exposes summary.status
--
-- This module iterates ReadHistory, checks each book's DocSettings sidecar,
-- and counts entries whose summary.status == "complete".

local logger = require("common/zen_logger").new("db_library")
local paths = require("common/paths")

local LibraryDB = {}

-- In-memory cache so the expensive sidecar scan only runs once per cache
-- window (default 5 minutes).  Call LibraryDB.invalidateCache() to force a
-- rescan on the next getBookCounts() call.
local _cache = { book_counts = nil, cache_time = 0 }
local CACHE_TTL = 300  -- seconds

-- Invalidate the cache so the next getBookCounts() call forces a fresh scan.
function LibraryDB.invalidateCache()
    _cache.book_counts = nil
    _cache.cache_time  = 0
end

-- Returns { finished = N, reading = N, total = N }
--   finished  books whose sidecar summary.status is "complete"
--   reading   books whose sidecar summary.status is "reading"
--   total     all books in ReadHistory that have a sidecar file
-- All three counts come from the same ReadHistory walk so reading + finished
-- is always <= total.
-- Results are cached for CACHE_TTL seconds to avoid rescanning on every open.
function LibraryDB.getBookCounts()
    local now = os.time()
    if _cache.book_counts and (now - _cache.cache_time) < CACHE_TTL then
        logger.info("returning cached book counts")
        return _cache.book_counts
    end

    local counts = { finished = 0, reading = 0, total = 0 }

    -- Count finished books from sidecar status
    local ok, err = pcall(function()
        local ReadHistory = require("readhistory")
        local DocSettings = require("docsettings")

        -- ReadHistory.hist may not be populated until the history module has
        -- been initialised.  Calling reload() ensures the list is current.
        if ReadHistory.reload then
            ReadHistory:reload(false)
        end

        local home_dir = paths.getHomeDir()

        local hist = ReadHistory.hist or {}
        for _i, entry in ipairs(hist) do
            local file = entry.file
            -- Skip books outside home_dir (SD card, other folders, etc.)
            if file and home_dir and not paths.isInHomeDir(file) then
                file = nil
            end
            if file and DocSettings:hasSidecarFile(file) then
                counts.total = counts.total + 1
                local doc_settings = DocSettings:open(file)
                local summary = doc_settings:readSetting("summary") or {}
                local status  = summary.status
                if status == "complete" then
                    counts.finished = counts.finished + 1
                elseif status == "reading" then
                    counts.reading = counts.reading + 1
                end
                -- NOTE: do NOT call doc_settings:close() — LuaSettings:close()
                -- unconditionally calls flush(), which rewrites the sidecar to
                -- disk even when nothing was changed. Let the object be GC'd.
            end
        end
    end)

    if not ok then
        logger.warn("finished count failed:", err)
    end

    logger.info("finished=", counts.finished,
                "reading=", counts.reading,
                "total=", counts.total)
    _cache.book_counts = counts
    _cache.cache_time  = now
    return counts
end

return LibraryDB

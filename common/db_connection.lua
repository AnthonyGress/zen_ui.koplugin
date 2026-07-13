-- common/db_connection.lua
-- Shared SQLite connection utilities for Zen UI.
-- Centralises path resolution and connection management so that each
-- database module (db_stats, db_library, …) does not duplicate this logic.

local SQ3 = require("lua-ljsqlite3/init")
local logger = require("common/zen_logger").new("db_connection")

local M = {}

-- Path helpers

-- Returns the filesystem path to statistics.sqlite3.
-- Tries the primary location first; falls back to the settings subdir.
function M.getStatsDbPath()
    local DataStorage = require("datastorage")
    local lfs = require("libs/libkoreader-lfs")
    local primary = DataStorage:getDataDir() .. "/statistics.sqlite3"
    if lfs.attributes(primary, "mode") == "file" then return primary end
    local fallback = DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    if lfs.attributes(fallback, "mode") == "file" then return fallback end
    return primary
end

-- Connection helpers

-- Returns true when a readable SQLite file exists at path.
function M.isAvailable(path)
    local lfs = require("libs/libkoreader-lfs")
    return lfs.attributes(path, "mode") == "file"
end

-- Opens a SQLite connection to path.
-- Returns (conn, nil) on success, (nil, errmsg) on failure.
function M.open(path)
    if not M.isAvailable(path) then
        return nil, "file not found: " .. tostring(path)
    end
    local ok, conn = pcall(SQ3.open, path)
    if not ok then
        logger.warn("failed to open", path, ":", conn)
        return nil, tostring(conn)
    end
    return conn, nil
end

return M

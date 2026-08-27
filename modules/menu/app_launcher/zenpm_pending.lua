local DBConnection = require("common/db_connection")

local M = {}

local function add_path(paths, seen, path)
    if type(path) == "string" and path ~= "" and not seen[path] then
        seen[path] = true
        paths[#paths + 1] = path
    end
end

local function candidate_paths()
    local paths, seen = {}, {}
    local DataStorage = require("datastorage")
    add_path(paths, seen, DataStorage:getSettingsDir() .. "/ZenPM/state/zenpm.sqlite3")

    local ok_android, android = pcall(require, "android")
    if ok_android and type(android) == "table"
            and type(android.getExternalStoragePath) == "function" then
        local ok_path, path = pcall(android.getExternalStoragePath)
        if ok_path and type(path) == "string" then
            add_path(paths, seen, path .. "/ZenPM/state/zenpm.sqlite3")
        end
    end

    add_path(paths, seen, "/mnt/us/.ZenPM/zenpm.sqlite3")
    add_path(paths, seen, "/mnt/onboard/.adds/.ZenPM/zenpm.sqlite3")
    return paths
end

function M.path()
    for _i, path in ipairs(candidate_paths()) do
        if DBConnection.isAvailable(path) then return path end
    end
end

local function close_sqlite(conn, stmt)
    if stmt then pcall(stmt.close, stmt) end
    if conn then pcall(conn.close, conn) end
end

function M.read(path)
    path = path or M.path()
    if not path then return {}, nil end
    local conn = DBConnection.open(path)
    if not conn then return {}, path end

    local stmt
    local ok, pending = pcall(function()
        pcall(conn.exec, conn, "PRAGMA busy_timeout = 1000")
        stmt = assert(conn:prepare([[
            SELECT id, install_path
            FROM installed_packages
            WHERE launcher_add_pending = 1 AND install_path <> ''
        ]]))
        local rows = {}
        while true do
            local row = stmt:step()
            if not row then break end
            if type(row[1]) == "string" and row[1] ~= ""
                    and type(row[2]) == "string" and row[2] ~= "" then
                rows[#rows + 1] = { id = row[1], install_path = row[2] }
            end
        end
        return rows
    end)
    close_sqlite(conn, stmt)
    return ok and pending or {}, path
end

function M.clear(ids, path)
    if type(ids) ~= "table" or next(ids) == nil then return true end
    path = path or M.path()
    if not path then return false end
    local conn = DBConnection.open(path)
    if not conn then return false end

    local stmt
    local ok = pcall(function()
        pcall(conn.exec, conn, "PRAGMA busy_timeout = 1000")
        stmt = assert(conn:prepare([[
            UPDATE installed_packages
            SET launcher_add_pending = 0
            WHERE id = ? AND launcher_add_pending = 1
        ]]))
        for id, selected in pairs(ids) do
            if selected and type(id) == "string" and id ~= "" then
                stmt:bind(id):step()
                stmt:clearbind():reset()
            end
        end
    end)
    close_sqlite(conn, stmt)
    return ok
end

return M

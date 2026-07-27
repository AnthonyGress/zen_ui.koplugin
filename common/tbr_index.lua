local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local UIManager = require("ui/uimanager")
local BookStatus = require("common/book_status")
local lfs = require("libs/libkoreader-lfs")
local sqlite3 = require("lua-ljsqlite3/init")
local paths = require("common/paths")
local title_sort = require("common/title_sort")
local zen_logger = require("common/zen_logger")

local logger = zen_logger.new("tbr_index")
local now = zen_logger.now
local M = {}

local DB_PATH = DataStorage:getSettingsDir() .. "/docprops_cache.sqlite"
local AUDIT_CHUNK = 8
local AUDIT_BUDGET_S = 0.02
local AUDIT_TICK_S = 0.05
local db
local audit
local revision = 0
local audited_roots = {}

local function add_callback(callbacks, callback)
    if type(callback) == "function" then callbacks[#callbacks + 1] = callback end
end

local function run_callbacks(callbacks)
    for _i, callback in ipairs(callbacks) do
        local ok_callback, err = pcall(callback)
        if not ok_callback then logger.warn("TBR audit callback failed", tostring(err)) end
    end
end

local function open_db()
    if db then return db end
    db = sqlite3.open(DB_PATH)
    db:exec([[
        CREATE TABLE IF NOT EXISTS zen_doc_status_cache (
            path TEXT PRIMARY KEY,
            signature TEXT NOT NULL,
            home_root TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT '',
            percent_finished REAL NOT NULL DEFAULT -1,
            effective_status TEXT NOT NULL DEFAULT 'new',
            sort_title TEXT NOT NULL DEFAULT '',
            series_index REAL NOT NULL DEFAULT -1,
            access_time INTEGER NOT NULL DEFAULT 0,
            updated_at INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS zen_doc_status_home_tbr
            ON zen_doc_status_cache(home_root, status, effective_status);
    ]])
    return db
end

local function statement_row(sql, ...)
    local stmt = open_db():prepare(sql)
    if not stmt then return nil end
    if select("#", ...) > 0 then stmt:bind(...) end
    local row = stmt:step()
    stmt:clearbind():reset()
    return row
end

local function get_row(path)
    local row = statement_row([[
        SELECT signature, status, percent_finished, effective_status,
               sort_title, series_index, access_time
        FROM zen_doc_status_cache WHERE path = ?
    ]], path)
    if not row then return nil end
    return {
        signature = row[1],
        status = row[2] ~= "" and row[2] or nil,
        percent_finished = tonumber(row[3]) and tonumber(row[3]) >= 0
            and tonumber(row[3]) or nil,
        effective_status = row[4],
        sort_title = row[5],
        series_index = tonumber(row[6]),
        access_time = tonumber(row[7]),
    }
end

local function is_tbr(row, include_new)
    return row and (row.status == "abandoned"
        or (include_new and row.effective_status == "new"))
end

local function file_signature(path)
    local attr = lfs.attributes(path)
    if not attr or attr.mode ~= "file" then return nil end
    local sidecar_path
    if type(DocSettings.findSidecarFile) == "function" then
        local ok_sidecar, found = pcall(DocSettings.findSidecarFile, DocSettings, path)
        if ok_sidecar then sidecar_path = found end
    end
    local sidecar_attr = sidecar_path and lfs.attributes(sidecar_path) or nil
    return table.concat({
        tostring(attr.size or 0),
        tostring(attr.modification or 0),
        tostring(sidecar_path or ""),
        tostring(sidecar_attr and sidecar_attr.size or 0),
        tostring(sidecar_attr and sidecar_attr.modification or 0),
    }, "\31"), sidecar_path, attr
end

local function candidate_metadata(path, candidate, attr)
    local title = candidate and candidate.title
    local series_index = candidate and tonumber(candidate.series_index)
    if not candidate and (not title or title == "") then
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        local info = ok_bim and BookInfoManager:getBookInfo(path, false) or nil
        title = info and info.title
        if not series_index then series_index = info and tonumber(info.series_index) end
    end
    if not title or title == "" then
        title = (path:match("([^/]+)$") or path):gsub("%.[^%.]+$", "")
    end
    return title_sort.key(title):lower(), series_index or -1,
        tonumber(attr and attr.access) or 0
end

local function delete_path(path)
    local stmt = open_db():prepare("DELETE FROM zen_doc_status_cache WHERE path = ?")
    if not stmt then return end
    stmt:bind(path):step()
    stmt:clearbind():reset()
    revision = revision + 1
end

local function write_row(path, signature, status, percent_finished, effective_status,
        sort_title, series_index, access_time)
    local stmt = open_db():prepare([[
        INSERT OR REPLACE INTO zen_doc_status_cache
            (path, signature, home_root, status, percent_finished, effective_status,
             sort_title, series_index, access_time, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]])
    if not stmt then return false end
    stmt:bind(
        path,
        signature,
        paths.getHomeDir() or "",
        status or "",
        tonumber(percent_finished) or -1,
        effective_status or "new",
        sort_title or "",
        tonumber(series_index) or -1,
        tonumber(access_time) or 0,
        os.time()
    ):step()
    stmt:clearbind():reset()
    revision = revision + 1
    return true
end

local function read_status(path, sidecar_path, doc_settings)
    if not sidecar_path and not doc_settings then
        return nil, nil, "new", true
    end
    local doc = doc_settings
    if not doc then
        local ok_doc, opened = pcall(DocSettings.open, DocSettings, path)
        if not ok_doc or not opened then return nil, nil, nil, false end
        doc = opened
    end
    if not doc then return nil, nil, nil, false end
    local summary = doc:readSetting("summary") or {}
    local status = summary.status
    status = BookStatus.migrateLegacyMarker(path, status, doc)
    local percent_finished = doc:readSetting("percent_finished")
    local effective_status = BookStatus.getComputedStatus(
        path, status, percent_finished, doc)
    return status, percent_finished, effective_status, true
end

local function refresh(path, candidate, doc_settings)
    local include_new = BookStatus.includeNewInTBREnabled()
    local previous = get_row(path)
    local signature, sidecar_path, attr = file_signature(path)
    if not signature then
        if previous then delete_path(path) end
        return previous ~= nil and is_tbr(previous, include_new), false
    end
    local sort_title, series_index, access_time = candidate_metadata(path, candidate, attr)
    if not doc_settings and previous and previous.signature == signature then
        local metadata_changed = previous.sort_title ~= sort_title
            or previous.series_index ~= series_index
            or previous.access_time ~= access_time
        if metadata_changed then
            write_row(path, signature, previous.status, previous.percent_finished,
                previous.effective_status, sort_title, series_index, access_time)
        end
        return metadata_changed and is_tbr(previous, include_new), false
    end
    local status, percent_finished, effective_status, read_ok
    local sidecar_read = false
    if doc_settings or sidecar_path then
        status, percent_finished, effective_status, read_ok =
            read_status(path, sidecar_path, doc_settings)
        sidecar_read = true
        if not read_ok then return false, sidecar_read end
    else
        status, percent_finished, effective_status = nil, nil, "new"
    end
    if effective_status == "new" and BookStatus.isImageFile(path) then
        effective_status = "image"
    end
    write_row(path, signature, status, percent_finished, effective_status,
        sort_title, series_index, access_time)
    local current = {
        status = status,
        effective_status = effective_status,
    }
    return is_tbr(previous, include_new) ~= is_tbr(current, include_new), sidecar_read
end

function M.refreshPath(path, doc_settings, candidate)
    if type(path) ~= "string" or path == "" then return false end
    local ok_refresh, changed = pcall(refresh, path, candidate, doc_settings)
    if not ok_refresh then
        logger.warn("TBR index refresh failed", path, tostring(changed))
        return false
    end
    return changed == true
end

function M.removePath(path)
    if type(path) ~= "string" or path == "" then return end
    if get_row(path) then delete_path(path) end
end

local function query_parts(options)
    options = type(options) == "table" and options or {}
    local status_where = options.include_new == true
        and "(status = 'abandoned' OR effective_status = 'new')"
        or "status = 'abandoned'"
    local where = "home_root = ? AND " .. status_where
    if type(options.exclude_path) == "string" and options.exclude_path ~= "" then
        where = where .. " AND path != ?"
    end
    local collate = options.collate
    local reverse = options.reverse == true
    local order
    if collate == "access" then
        order = "access_time " .. (reverse and "ASC" or "DESC") .. ", path COLLATE NOCASE ASC"
    elseif collate == "series_index" then
        order = "series_index " .. (reverse and "DESC" or "ASC") .. ", sort_title COLLATE NOCASE ASC"
    else
        order = "sort_title COLLATE NOCASE " .. (reverse and "DESC" or "ASC")
            .. ", path COLLATE NOCASE " .. (reverse and "DESC" or "ASC")
    end
    return where, order
end

function M.getCount(options)
    local where = query_parts(options)
    local sql = "SELECT COUNT(*) FROM zen_doc_status_cache WHERE " .. where
    local row
    local home_root = paths.getHomeDir() or ""
    if options and options.exclude_path then
        row = statement_row(sql, home_root, options.exclude_path)
    else
        row = statement_row(sql, home_root)
    end
    return tonumber(row and row[1]) or 0
end

function M.getPage(offset, limit, options)
    offset = math.max(0, math.floor(tonumber(offset) or 0))
    limit = math.max(1, math.floor(tonumber(limit) or 1))
    local where, order = query_parts(options)
    local sql = "SELECT path FROM zen_doc_status_cache WHERE " .. where
        .. " ORDER BY " .. order .. " LIMIT ? OFFSET ?"
    local stmt = open_db():prepare(sql)
    if not stmt then return {}, 0 end
    local home_root = paths.getHomeDir() or ""
    if options and options.exclude_path then
        stmt:bind(home_root, options.exclude_path, limit, offset)
    else
        stmt:bind(home_root, limit, offset)
    end
    local paths_out = {}
    local stale = {}
    while true do
        local row = stmt:step()
        if not row then break end
        local path = row[1]
        local attr = path and lfs.attributes(path)
        if attr and attr.mode == "file" then
            paths_out[#paths_out + 1] = path
        elseif path then
            stale[#stale + 1] = path
        end
    end
    stmt:clearbind():reset()
    for _i, path in ipairs(stale) do delete_path(path) end
    return paths_out
end

function M.getAll(options)
    local count = M.getCount(options)
    if count == 0 then return {} end
    return M.getPage(0, count, options)
end

function M.getRevision()
    return revision
end

function M.isAuditRunning()
    return audit ~= nil
end

function M.isAuditComplete()
    return audited_roots[paths.getHomeDir() or ""] == true
end

function M.invalidateAudit()
    M.cancelAudit()
    audited_roots[paths.getHomeDir() or ""] = nil
end

function M.scheduleAudit(candidates, on_change, on_complete)
    if audit then
        add_callback(audit.on_change, on_change)
        add_callback(audit.on_complete, on_complete)
        return false
    end
    if type(candidates) ~= "table" or #candidates == 0 then
        audited_roots[paths.getHomeDir() or ""] = true
        if type(on_complete) == "function" then on_complete() end
        return false
    end
    audit = {
        candidates = candidates,
        index = 1,
        checked = 0,
        changed = 0,
        sidecar_reads = 0,
        started_at = now(),
        work_ms = 0,
        home_root = paths.getHomeDir() or "",
        on_change = {},
        on_complete = {},
    }
    add_callback(audit.on_change, on_change)
    add_callback(audit.on_complete, on_complete)
    local step
    step = function()
        local current = audit
        if not current or current.step ~= step then return end
        local chunk_started_at = now()
        local deadline = chunk_started_at + AUDIT_BUDGET_S
        local processed = 0
        local membership_changed = false
        local connection = open_db()
        local transaction_started = pcall(connection.exec, connection, "BEGIN")
        while current.index <= #current.candidates and processed < AUDIT_CHUNK
                and (processed == 0 or now() < deadline) do
            local candidate = current.candidates[current.index]
            current.index = current.index + 1
            processed = processed + 1
            current.checked = current.checked + 1
            local path = type(candidate) == "table" and candidate.path or candidate
            local ok_refresh, changed, sidecar_read = pcall(refresh, path, candidate)
            if ok_refresh then
                if changed then
                    current.changed = current.changed + 1
                    membership_changed = true
                end
                if sidecar_read then current.sidecar_reads = current.sidecar_reads + 1 end
            else
                logger.warn("TBR audit failed", tostring(path), tostring(changed))
            end
        end
        if transaction_started then pcall(connection.exec, connection, "COMMIT") end
        current.work_ms = current.work_ms + (now() - chunk_started_at) * 1000
        if membership_changed then run_callbacks(current.on_change) end
        if current.index <= #current.candidates then
            UIManager:scheduleIn(AUDIT_TICK_S, step)
            return
        end
        audit = nil
        audited_roots[current.home_root] = true
        logger.measure("TBR index audit completed", current.work_ms,
            "candidates=", #current.candidates,
            "changed=", current.changed,
            "sidecar_reads=", current.sidecar_reads,
            "wall_ms=", math.floor((now() - current.started_at) * 1000 + 0.5))
        run_callbacks(current.on_complete)
    end
    audit.step = step
    UIManager:scheduleIn(AUDIT_TICK_S, step)
    return true
end

function M.cancelAudit()
    if not audit then return end
    UIManager:unschedule(audit.step)
    audit = nil
end

function M.close()
    M.cancelAudit()
    if db then
        db:close()
        db = nil
    end
end

return M

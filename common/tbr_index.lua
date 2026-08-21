local BookStatus = require("common/book_status")
local ConfigManager = require("config/manager")
local DataStorage = require("datastorage")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local ReadCollection = require("readcollection")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local paths = require("common/paths")
local sqlite3 = require("lua-ljsqlite3/init")
local title_sort = require("common/title_sort")
local zen_logger = require("common/zen_logger")

local logger = zen_logger.new("tbr_index")
local now = zen_logger.now
local M = {}

local COLLECTION_NAME = "To Be Read"
local DB_PATH = DataStorage:getSettingsDir() .. "/docprops_cache.sqlite"
local STATUS_TABLE = "zen_doc_status_cache"

local db
local status_rows
local inventory
local result_cache = {}
local revision = 0
local audit
local reconciled_scope
local collection_signature

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

local function load_status_rows()
    if status_rows then return status_rows end
    status_rows = {}
    local stmt = open_db():prepare(([[
        SELECT path, signature, status, percent_finished, effective_status
        FROM %s
    ]]):format(STATUS_TABLE))
    if not stmt then return status_rows end
    while true do
        local row = stmt:step()
        if not row then break end
        status_rows[row[1]] = {
            signature = row[2],
            status = row[3] ~= "" and row[3] or nil,
            percent_finished = tonumber(row[4]) and tonumber(row[4]) >= 0
                and tonumber(row[4]) or nil,
            effective_status = row[5],
        }
    end
    stmt:clearbind():reset()
    return status_rows
end

local function get_status_row(path)
    return load_status_rows()[path]
end

local function write_status_row(path, signature, status, percent_finished, effective_status)
    local stmt = open_db():prepare(([[
        INSERT OR REPLACE INTO %s
            (path, signature, home_root, status, percent_finished,
             effective_status, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]]):format(STATUS_TABLE))
    if not stmt then return false end
    stmt:bind(
        path,
        signature,
        paths.getHomeDir() or "",
        status or "",
        tonumber(percent_finished) or -1,
        effective_status or "unknown",
        os.time()
    ):step()
    stmt:clearbind():reset()
    if status_rows then
        status_rows[path] = {
            signature = signature,
            status = status,
            percent_finished = percent_finished,
            effective_status = effective_status,
        }
    end
    return true
end

local function delete_status_row(path)
    local stmt = open_db():prepare("DELETE FROM " .. STATUS_TABLE .. " WHERE path = ?")
    if not stmt then return end
    stmt:bind(path):step()
    stmt:clearbind():reset()
    if status_rows then status_rows[path] = nil end
end

local function status_transaction(callback)
    local connection = open_db()
    local started = pcall(connection.exec, connection, "BEGIN")
    local ok_callback, result = pcall(callback)
    if started then
        pcall(connection.exec, connection, ok_callback and "COMMIT" or "ROLLBACK")
    end
    if not ok_callback then
        status_rows = nil
        error(result)
    end
    return result
end

local function clear_results(bump_revision)
    result_cache = {}
    if bump_revision then revision = revision + 1 end
end

local function configured_scope()
    local candidates = {}
    local function add_root(root)
        if type(root) ~= "string" or root == "" then return end
        root = paths.normPath(root:gsub("/*$", ""))
        if root ~= "" then candidates[#candidates + 1] = root end
    end
    add_root(paths.getHomeDir())
    local config = ConfigManager.get() or {}
    for _i, root in ipairs(type(config.additional_home_dirs) == "table"
            and config.additional_home_dirs or {}) do
        add_root(root)
    end
    table.sort(candidates, function(a, b)
        if #a ~= #b then return #a < #b end
        return a < b
    end)
    local roots = {}
    for _i, candidate in ipairs(candidates) do
        local nested = false
        for _j, root in ipairs(roots) do
            if candidate == root or candidate:sub(1, #root + 1) == root .. "/" then
                nested = true
                break
            end
        end
        if not nested then roots[#roots + 1] = candidate end
    end
    return {
        roots = roots,
        key = table.concat(roots, "\31"),
    }
end

local function is_visible_name(name)
    return FileChooser.show_hidden == true or name:sub(1, 1) ~= "."
end

local function is_visible_dir(name)
    if not is_visible_name(name) or name == "." or name == ".." then return false end
    if type(FileChooser.show_dir) ~= "function" then return true end
    local ok_show, shown = pcall(FileChooser.show_dir, FileChooser, name)
    return ok_show and shown == true
end

local function is_supported_file(name, path)
    if not is_visible_name(name) or name:sub(1, 2) == "._" then return false end
    for _i, pattern in ipairs(FileChooser.exclude_files or {}) do
        if name:match(pattern) then return false end
    end
    if BookStatus.isImageFile(path) then return false end
    local ok_provider, supported = pcall(DocumentRegistry.hasProvider, DocumentRegistry, path)
    return ok_provider and supported == true
end

local function scan_scope(scope)
    local books = {}
    local dirs = {}
    local readable_root = false
    local stack = {}
    for root_index = #scope.roots, 1, -1 do stack[#stack + 1] = scope.roots[root_index] end

    while #stack > 0 do
        local directory = table.remove(stack)
        local dir_attr = lfs.attributes(directory)
        if dir_attr and dir_attr.mode == "directory" then
            dirs[directory] = dir_attr.modification or 0
            local ok_dir, iter, dir_obj = pcall(lfs.dir, directory)
            if ok_dir and type(iter) == "function" then
                readable_root = true
                while true do
                    local ok_next, name = pcall(iter, dir_obj)
                    if not ok_next or not name then break end
                    if name ~= "." and name ~= ".." then
                        local path = directory .. "/" .. name
                        local attr = lfs.attributes(path)
                        if attr and attr.mode == "directory" and is_visible_dir(name) then
                            stack[#stack + 1] = path
                        elseif attr and attr.mode == "file" and is_supported_file(name, path) then
                            books[#books + 1] = {
                                path = path,
                                name = name,
                                attr = attr,
                            }
                        end
                    end
                end
                if dir_obj and type(dir_obj.close) == "function" then
                    pcall(dir_obj.close, dir_obj)
                end
            end
        end
    end

    table.sort(books, function(a, b) return a.path < b.path end)
    return books, dirs, readable_root or #scope.roots == 0
end

local function dirs_changed(cached, scope)
    if not cached or cached.scope_key ~= scope.key then return true end
    if cached.complete ~= true then return true end
    for directory, old_mtime in pairs(cached.dirs) do
        local current_mtime = lfs.attributes(directory, "modification")
        if current_mtime == nil or current_mtime ~= old_mtime then return true end
    end
    return false
end

local function same_books(first, second)
    if not first or #first ~= #second then return false end
    for index = 1, #second do
        if first[index].path ~= second[index].path then return false end
    end
    return true
end

local function ensure_inventory(force)
    local scope = configured_scope()
    if not force and not dirs_changed(inventory, scope) then
        reconciled_scope = scope.key
        return inventory.list, scope, inventory.complete == true
    end

    local started_at = now()
    local books, dirs, complete = scan_scope(scope)
    if not complete and inventory and inventory.scope_key == scope.key then
        logger.warn("TBR path refresh kept the previous inventory")
        reconciled_scope = scope.key
        return inventory.list, scope, false
    end
    local changed = not inventory or inventory.scope_key ~= scope.key
        or not same_books(inventory.list, books)
    inventory = {
        scope_key = scope.key,
        list = books,
        dirs = dirs,
        complete = complete,
    }
    reconciled_scope = scope.key
    -- A directory-only change may be a new or changed sidecar.
    clear_results(changed)
    logger.measure("TBR paths refreshed", (now() - started_at) * 1000,
        "books=", #books, "changed=", changed)
    return books, scope, complete
end

local function ensure_collection()
    if type(ReadCollection.coll) ~= "table" then return false end
    if ReadCollection.coll[COLLECTION_NAME] then return true end
    ReadCollection:addCollection(COLLECTION_NAME)
    ReadCollection:write({ [COLLECTION_NAME] = true })
    collection_signature = nil
    clear_results(true)
    return true
end

local function explicit_paths()
    if type(ReadCollection._read) == "function" then pcall(ReadCollection._read, ReadCollection) end
    ensure_collection()
    local files = {}
    local coll = ReadCollection.coll and ReadCollection.coll[COLLECTION_NAME] or {}
    for filepath, entry in pairs(coll) do
        local path = type(entry) == "table" and entry.file or filepath
        if type(path) == "string" and paths.isInHomeDir(path)
                and lfs.attributes(path, "mode") == "file" then
            files[#files + 1] = path
        end
    end
    table.sort(files)
    local signature = table.concat(files, "\31")
    if collection_signature ~= nil and collection_signature ~= signature then
        clear_results(true)
    end
    collection_signature = signature
    return files
end

local function sidecar_signature(path, attr)
    if type(DocSettings.findSidecarFile) ~= "function" then return nil end
    local ok_sidecar, sidecar = pcall(DocSettings.findSidecarFile, DocSettings, path)
    if not ok_sidecar or not sidecar then return nil end
    local sidecar_attr = lfs.attributes(sidecar)
    if not sidecar_attr or sidecar_attr.mode ~= "file" then return nil end
    return table.concat({
        tostring(attr and attr.size or 0),
        tostring(attr and attr.modification or 0),
        sidecar,
        tostring(sidecar_attr.size or 0),
        tostring(sidecar_attr.modification or 0),
    }, "\31")
end

local function read_status(path, doc_settings)
    local doc = doc_settings
    if not doc then
        local ok_doc, opened = pcall(DocSettings.open, DocSettings, path)
        if not ok_doc or not opened then return nil end
        doc = opened
    end
    local summary = doc:readSetting("summary") or {}
    local status = summary.status
    status = BookStatus.migrateLegacyMarker(path, status, doc)
    local percent_finished = doc:readSetting("percent_finished")
    return {
        status = status,
        percent_finished = percent_finished,
        effective_status = BookStatus.getComputedStatus(
            path, status, percent_finished, doc),
    }
end

local function status_for(path, attr, doc_settings)
    local signature = sidecar_signature(path, attr)
    if not signature and not doc_settings then
        return { effective_status = "new" }
    end
    if not signature then
        signature = table.concat({
            tostring(attr and attr.size or 0),
            tostring(attr and attr.modification or 0),
            "open-doc",
        }, "\31")
    end
    local cached = get_status_row(path)
    if not doc_settings and cached and cached.signature == signature then return cached end
    local status = read_status(path, doc_settings)
    if not status then return cached or { effective_status = "unknown" } end
    write_status_row(path, signature, status.status, status.percent_finished,
        status.effective_status)
    return status
end

local function migration_needed()
    local config = ConfigManager.get()
    return not (config and config._meta and config._meta.tbr_collection_migrated == true)
end

local function migrate_legacy_tbr()
    if not migration_needed() then return end
    local inventory_result = { ensure_inventory() }
    local books = inventory_result[1]
    local complete = inventory_result[3]
    if not complete then return end
    if not ensure_collection() then return end

    local migrated = 0
    local collection_changed = false
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local BookList = require("ui/widget/booklist")
    status_transaction(function()
        for _i, book in ipairs(books) do
            local signature = sidecar_signature(book.path, book.attr)
            if signature then
                local cached = get_status_row(book.path)
                if not cached or cached.signature ~= signature or cached.status == "abandoned" then
                    local ok_doc, doc = pcall(DocSettings.open, DocSettings, book.path)
                    if ok_doc and doc then
                        local summary = doc:readSetting("summary") or {}
                        local status = BookStatus.migrateLegacyMarker(
                            book.path, summary.status, doc)
                        if status == "abandoned" then
                            if not ReadCollection:isFileInCollection(book.path, COLLECTION_NAME) then
                                ReadCollection:addItem(book.path, COLLECTION_NAME, book.attr)
                                collection_changed = true
                            end
                            summary.status = nil
                            filemanagerutil.saveSummary(doc, summary)
                            BookList.setBookInfoCacheProperty(book.path, "status", nil)
                            delete_status_row(book.path)
                            migrated = migrated + 1
                        else
                            local percent_finished = doc:readSetting("percent_finished")
                            write_status_row(book.path, signature, status, percent_finished,
                                BookStatus.getComputedStatus(
                                    book.path, status, percent_finished, doc))
                        end
                    end
                end
            end
        end
    end)
    if collection_changed then ReadCollection:write({ [COLLECTION_NAME] = true }) end

    local config = ConfigManager.get()
    if type(config) == "table" then
        config._meta = type(config._meta) == "table" and config._meta or {}
        config._meta.tbr_collection_migrated = true
        ConfigManager.save(config)
    end
    collection_signature = nil
    clear_results(migrated > 0)
    logger.info("legacy TBR statuses migrated", migrated)
end

local function sync_sources(include_new)
    ensure_collection()
    if migration_needed() then migrate_legacy_tbr() end
    local books, scope
    if include_new then
        books, scope = ensure_inventory()
    else
        scope = configured_scope()
        reconciled_scope = scope.key
    end
    local explicit = explicit_paths()
    return books or {}, explicit, scope
end

local function filename_title(path)
    return (path:match("([^/]+)$") or path):gsub("%.[^%.]+$", "")
end

local function sort_paths(files, collate, reverse)
    collate = collate or "title"
    local metadata = {}
    if collate == "title" or collate == "title_natural"
            or collate == "series" or collate == "series_index" then
        local ok_meta, db_bookinfo = pcall(require, "common/db_bookinfo")
        if ok_meta and type(db_bookinfo.getLightMetadata) == "function" then
            metadata = db_bookinfo.getLightMetadata()
        end
    end
    local items = {}
    for _i, path in ipairs(files) do
        local info = metadata[path] or {}
        local value
        if collate == "access" then
            value = lfs.attributes(path, "access") or 0
        elseif collate == "series_index" then
            value = tonumber(info.series_index) or math.huge
        elseif collate == "series" then
            value = info.series or ""
        else
            value = info.title or filename_title(path)
        end
        items[#items + 1] = { path = path, value = value }
    end

    local natural_sort
    if collate == "title_natural" then
        local ok_booklist, BookList = pcall(require, "ui/widget/booklist")
        local natural = ok_booklist and BookList.collates and BookList.collates.title_natural
        natural_sort = natural and natural.init_sort_func and natural.init_sort_func()
    end
    table.sort(items, function(a, b)
        if a.value == b.value then return a.path < b.path end
        if collate == "access" then
            if reverse then return a.value < b.value end
            return a.value > b.value
        end
        if collate == "series_index" then
            if reverse then return a.value > b.value end
            return a.value < b.value
        end
        if natural_sort then
            local first = { doc_props = { display_title = a.value } }
            local second = { doc_props = { display_title = b.value } }
            if reverse then return natural_sort(second, first) end
            return natural_sort(first, second)
        end
        local first = collate == "title" and title_sort.key(a.value) or tostring(a.value)
        local second = collate == "title" and title_sort.key(b.value) or tostring(b.value)
        first, second = first:lower(), second:lower()
        if reverse then return first > second end
        return first < second
    end)

    local sorted = {}
    for _i, item in ipairs(items) do sorted[#sorted + 1] = item.path end
    return sorted
end

local function result_key(options, scope_key)
    return table.concat({
        scope_key or "",
        options.include_new == true and "new" or "explicit",
        tostring(options.collate or "title"),
        options.reverse == true and "reverse" or "forward",
        tostring(options.exclude_path or ""),
    }, "\30")
end

local function build_result(options)
    options = type(options) == "table" and options or {}
    local books, explicit, scope = sync_sources(options.include_new == true)
    local key = result_key(options, scope.key)
    if result_cache[key] then return result_cache[key] end

    local included = {}
    local files = {}
    for _i, path in ipairs(explicit) do
        if path ~= options.exclude_path then
            included[path] = true
            files[#files + 1] = path
        end
    end
    if options.include_new == true then
        status_transaction(function()
            for _i, book in ipairs(books) do
                if not included[book.path] and book.path ~= options.exclude_path then
                    local status = status_for(book.path, book.attr)
                    if status.effective_status == "new" then
                        included[book.path] = true
                        files[#files + 1] = book.path
                    end
                end
            end
        end)
    end
    files = sort_paths(files, options.collate, options.reverse == true)
    result_cache[key] = files
    return files
end

function M.ensureCollection()
    return ensure_collection()
end

function M.collectionName()
    return COLLECTION_NAME
end

function M.isExplicit(path)
    ensure_collection()
    return ReadCollection:isFileInCollection(path, COLLECTION_NAME) == true
end

function M.setExplicit(path, enabled)
    if type(path) ~= "string" or path == "" or not ensure_collection() then return false end
    local present = ReadCollection:isFileInCollection(path, COLLECTION_NAME) == true
    if enabled == true and not present then
        ReadCollection:addItem(path, COLLECTION_NAME)
        ReadCollection:write({ [COLLECTION_NAME] = true })
    elseif enabled ~= true and present then
        ReadCollection:removeItem(path, COLLECTION_NAME)
        ReadCollection:write({ [COLLECTION_NAME] = true })
    else
        return false
    end
    collection_signature = nil
    clear_results(true)
    return true
end

function M.collectionChanged(name)
    if name and name ~= COLLECTION_NAME then return end
    collection_signature = nil
    clear_results(true)
end

function M.refreshPath(path, doc_settings, candidate)
    if type(path) ~= "string" or path == "" then return false end
    local attr = candidate and candidate.attr or lfs.attributes(path)
    if not attr or attr.mode ~= "file" then
        delete_status_row(path)
        inventory = nil
        clear_results(true)
        return true
    end
    local previous = get_status_row(path)
    local current = status_for(path, attr, doc_settings)
    clear_results(true)
    return not previous or previous.status ~= current.status
        or previous.effective_status ~= current.effective_status
end

function M.removePath(path)
    if type(path) ~= "string" or path == "" then return end
    delete_status_row(path)
    inventory = nil
    clear_results(true)
end

function M.getCount(options)
    return #build_result(options)
end

function M.getPage(offset, limit, options)
    offset = math.max(0, math.floor(tonumber(offset) or 0))
    limit = math.max(1, math.floor(tonumber(limit) or 1))
    local all = build_result(options)
    local page = {}
    for index = offset + 1, math.min(#all, offset + limit) do
        page[#page + 1] = all[index]
    end
    return page
end

function M.getAll(options)
    local all = build_result(options)
    local copy = {}
    for index = 1, #all do copy[index] = all[index] end
    return copy
end

function M.getRevision()
    explicit_paths()
    return revision
end

function M.isAuditRunning()
    return audit ~= nil
end

function M.isAuditComplete()
    return reconciled_scope == configured_scope().key
end

function M.isPreparing()
    return false
end

function M.invalidateStatusCache()
    clear_results(true)
end

function M.invalidateAudit()
    M.cancelAudit()
    inventory = nil
    reconciled_scope = nil
    clear_results(true)
end

local function add_callback(callbacks, callback)
    if type(callback) == "function" then callbacks[#callbacks + 1] = callback end
end

local function run_callbacks(callbacks)
    for _i, callback in ipairs(callbacks) do
        local ok_callback, err = pcall(callback)
        if not ok_callback then logger.warn("TBR refresh callback failed", tostring(err)) end
    end
end

function M.scheduleAudit(first, second, third)
    local on_change, on_complete
    if type(first) == "table" then
        on_change, on_complete = second, third
    else
        on_change, on_complete = first, second
    end
    if audit then
        add_callback(audit.on_change, on_change)
        add_callback(audit.on_complete, on_complete)
        return false
    end
    audit = { on_change = {}, on_complete = {} }
    add_callback(audit.on_change, on_change)
    add_callback(audit.on_complete, on_complete)
    audit.step = function()
        local current = audit
        if not current then return end
        local before = revision
        ensure_inventory()
        audit = nil
        if revision ~= before then run_callbacks(current.on_change) end
        run_callbacks(current.on_complete)
    end
    UIManager:nextTick(audit.step)
    return true
end

function M.cancelAudit()
    if not audit then return end
    if type(UIManager.unschedule) == "function" then UIManager:unschedule(audit.step) end
    audit = nil
end

function M.close()
    M.cancelAudit()
    if db then
        db:close()
        db = nil
    end
    status_rows = nil
end

return M

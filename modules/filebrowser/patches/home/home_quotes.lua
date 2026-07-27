local lfs = require("libs/libkoreader-lfs")
local PresetStore = require("config/preset_store")

local M = {}

local DEFAULT_QUOTES = require("modules/filebrowser/patches/home/quote_list")

local TEMPLATE = [[return {
    -- Add your quotes here, then enable Custom quotes in the Quotes widget settings.
    -- { text = "Quote text", author = "Author" },
    -- { text = "Quote text", author = "Author", title = "Book title" },
    -- "Plain quote without author",
}
]]

local annotation_cache
local quote_state
local hold_current_once = false

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function ensure_dir(path)
    if lfs.attributes(path, "mode") == "directory" then return true end
    return lfs.mkdir(path) == true or lfs.attributes(path, "mode") == "directory"
end

local function quotes_path()
    local root = PresetStore.rootDir()
    ensure_dir(root)
    return root .. "/quotes.lua"
end

local function state_store()
    if not quote_state then
        local LuaSettings = require("luasettings")
        quote_state = LuaSettings:open(PresetStore.rootDir() .. "/quote_state.lua")
    end
    return quote_state
end

local function ensure_template(path)
    if lfs.attributes(path, "mode") == "file" then return false end
    local f = io.open(path, "w")
    if not f then return false end
    f:write(TEMPLATE)
    f:close()
    return true
end

local function normalize(raw)
    local src = raw
    if type(raw) == "table" and type(raw.quotes) == "table" then src = raw.quotes end
    if type(src) ~= "table" then return {} end

    local out = {}
    for _i, item in ipairs(src) do
        local text, author, title
        if type(item) == "string" then
            text = item
            author = ""
        elseif type(item) == "table" then
            text = item.text or item[1]
            author = item.author or item[2] or ""
            title = item.title or item[3] or ""
        end
        if type(text) == "string" then
            text = trim(text)
            if text ~= "" then
                author = trim(type(author) == "string" and author or tostring(author or ""))
                title = trim(type(title) == "string" and title or tostring(title or ""))
                local attribution = author
                if title ~= "" then
                    attribution = attribution .. (attribution ~= "" and ",  " or "") .. title
                end
                out[#out + 1] = {
                    text = text,
                    author = author,
                    title = title,
                    attribution = attribution,
                }
            end
        end
    end
    return out
end

local function book_info(data, path)
    local props = type(data.doc_props) == "table" and data.doc_props or {}
    local filename = path:match("([^/\\]+)$") or path
    local title = trim(props.title)
    local authors = trim(props.authors)
    if title == "" then title = filename:gsub("%.[^.]+$", "") end
    return title, authors
end

local function append_annotations(quotes, path, seen_quotes)
    if type(path) ~= "string" or lfs.attributes(path, "mode") ~= "file" then return end
    local DocSettings = require("docsettings")
    local ok, doc_settings = pcall(DocSettings.open, DocSettings, path)
    if not ok or not doc_settings or type(doc_settings.data) ~= "table" then return end

    local data = doc_settings.data
    local title, authors = book_info(data, path)
    local attribution = title
    if authors ~= "" then
        attribution = attribution .. (attribution ~= "" and ",  " or "") .. authors
    end

    local function add(item, fallback_page)
        if type(item) ~= "table" or not item.drawer then return end
        local text = trim(item.text)
        if text == "" then return end
        local key = path .. "\0" .. text
        if seen_quotes[key] then return end
        seen_quotes[key] = true
        quotes[#quotes + 1] = {
            text = text,
            author = authors,
            title = title,
            attribution = attribution,
            is_annotation = true,
            filepath = path,
            pos0 = item.pos0,
            page = item.page or item.pageno or tonumber(fallback_page),
        }
    end

    if type(data.annotations) == "table" and #data.annotations > 0 then
        for _i, item in ipairs(data.annotations) do add(item) end
    else
        for page, page_items in pairs(type(data.highlight) == "table" and data.highlight or {}) do
            if type(page_items) == "table" then
                for _i, item in ipairs(page_items) do add(item, page) end
            end
        end
    end
end

local function annotation_quotes()
    if annotation_cache then return annotation_cache end
    local quotes, seen_books, seen_quotes = {}, {}, {}

    local function add_book(path)
        if type(path) ~= "string" or seen_books[path] then return end
        seen_books[path] = true
        append_annotations(quotes, path, seen_quotes)
    end

    local ReadHistory = require("readhistory")
    for _i, item in ipairs(ReadHistory.hist or {}) do
        add_book(item.file)
    end

    local DataStorage = require("datastorage")
    local ok_sq, SQ3 = pcall(require, "lua-ljsqlite3/init")
    local db_path = DataStorage:getDataDir() .. "/bookinfo_cache.db"
    if ok_sq and lfs.attributes(db_path, "mode") == "file" then
        local ok_db, db = pcall(SQ3.open, db_path)
        if ok_db and db then
            local ok_stmt, stmt = pcall(function()
                return db:prepare(
                    "SELECT directory, filename FROM bookinfo "
                    .. "WHERE directory IS NOT NULL AND filename IS NOT NULL"
                )
            end)
            if ok_stmt and stmt then
                pcall(function()
                    for row in stmt:nrows() do
                        local separator = row.directory:sub(-1) == "/" and "" or "/"
                        add_book(row.directory .. separator .. row.filename)
                    end
                end)
                pcall(function() stmt:close() end)
            end
            pcall(function() db:close() end)
        end
    end

    table.sort(quotes, function(a, b)
        if a.filepath ~= b.filepath then return a.filepath < b.filepath end
        local a_page, b_page = tonumber(a.page) or 0, tonumber(b.page) or 0
        if a_page ~= b_page then return a_page < b_page end
        return a.text < b.text
    end)
    annotation_cache = quotes
    return quotes
end

local function selected_sources(config)
    local sources = type(config) == "table" and config.sources or nil
    if type(sources) ~= "table" then
        return true, false, false
    end
    local use_defaults = sources.default == true
    local use_custom = sources.custom == true
    local use_annotations = sources.annotations == true
    if not use_defaults and not use_custom and not use_annotations then
        use_defaults = true
    end
    return use_defaults, use_custom, use_annotations
end

function M.getQuotes(config)
    local use_defaults, use_custom, use_annotations = selected_sources(config)
    local quotes = {}
    local function append(items)
        for _i, quote in ipairs(items) do quotes[#quotes + 1] = quote end
    end

    if use_defaults then append(DEFAULT_QUOTES) end

    local path = quotes_path()
    ensure_template(path)
    if use_custom then
        local ok, raw = pcall(dofile, path)
        if ok then append(normalize(raw)) end
    end

    if use_annotations then append(annotation_quotes()) end
    if #quotes == 0 then append(DEFAULT_QUOTES) end
    return quotes
end

function M.hasCustomQuotes()
    local path = quotes_path()
    if lfs.attributes(path, "mode") ~= "file" then return false end
    local ok, raw = pcall(dofile, path)
    return ok and #normalize(raw) > 0
end

local function quotes_signature(quotes)
    local hash = 5381
    for _i, quote in ipairs(quotes) do
        local value = table.concat({
            quote.text or "",
            quote.author or "",
            quote.title or "",
            quote.filepath or "",
            tostring(quote.pos0 or quote.page or ""),
        }, "\0")
        for i = 1, #value do
            hash = (hash * 33 + value:byte(i)) % 2147483647
        end
    end
    return tostring(#quotes) .. ":" .. tostring(hash)
end

local function shuffled_order(count)
    local order = {}
    for i = 1, count do order[i] = i end
    for i = count, 2, -1 do
        local j = math.random(i)
        order[i], order[j] = order[j], order[i]
    end
    return order
end

local function load_deck(quotes)
    local count = #quotes
    if count == 0 then return nil, nil, false end
    local store = state_store()
    local signature = quotes_signature(quotes)
    local raw = store:readSetting("deck_order")
    local position = tonumber(store:readSetting("deck_position"))
    local order, seen = {}, {}
    if type(raw) == "string" then
        for value in raw:gmatch("%d+") do
            local index = tonumber(value)
            if index and index >= 1 and index <= count and not seen[index] then
                seen[index] = true
                order[#order + 1] = index
            end
        end
    end
    local created = store:readSetting("deck_signature") ~= signature
        or #order ~= count or not position or position < 1 or position > count
    if created then
        order = shuffled_order(count)
        position = 1
    end
    return order, position, created, signature
end

local function save_deck(store, order, position, signature)
    store:saveSetting("deck_order", table.concat(order, ","))
    store:saveSetting("deck_position", position)
    store:saveSetting("deck_signature", signature)
    store:flush()
end

local function advance(order, position)
    position = position + 1
    if position <= #order then return order, position end
    local previous = order[#order]
    order = shuffled_order(#order)
    if #order > 1 and order[1] == previous then
        order[1], order[2] = order[2], order[1]
    end
    return order, 1
end

function M.selectQuote(config, rotation)
    local quotes = M.getQuotes(config)
    local order, position, created, signature = load_deck(quotes)
    if not order then return nil end
    local store = state_store()
    local today = os.date("%Y-%j")

    if hold_current_once then
        hold_current_once = false
    elseif rotation == "refresh" then
        if not created then order, position = advance(order, position) end
    elseif store:readSetting("quote_day") ~= today then
        if not created then order, position = advance(order, position) end
    end

    store:saveSetting("quote_day", today)
    save_deck(store, order, position, signature)
    return quotes[order[position]]
end

function M.stepQuote(config, delta)
    local quotes = M.getQuotes(config)
    local order, position, _created, signature = load_deck(quotes)
    if not order then return nil end
    if delta < 0 then
        position = position - 1
        if position < 1 then position = #order end
    else
        order, position = advance(order, position)
    end
    local store = state_store()
    store:saveSetting("quote_day", os.date("%Y-%j"))
    save_deck(store, order, position, signature)
    hold_current_once = true
    return quotes[order[position]]
end

function M.invalidateAnnotations()
    annotation_cache = nil
end

function M.ensureFile()
    return ensure_template(quotes_path())
end

function M.path()
    return quotes_path()
end

return M

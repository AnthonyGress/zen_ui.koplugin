local json = require("json")
local logger = require("common/zen_logger").new("hardcover")

local M = {}

local API_URL = "https://api.hardcover.app/v1/graphql"
local API_HOST = "api.hardcover.app"
local COVER_HOST = "assets.hardcover.app"
local USER_AGENT = "ZenOS metadata (https://github.com/xZenLabs/zen-os)"
local SEARCH_LIMIT = 10
local EDITION_LIMIT = 30
local MAX_QUERY_LENGTH = 512
local BLOCK_TIMEOUT = 6
local TOTAL_TIMEOUT = 12
local MAX_COVER_BYTES = 12 * 1024 * 1024
local MODULE_CA_BUNDLE
do
    local source = (debug.getinfo(1, "S").source or "")
    if source:sub(1, 1) == "@" then
        local directory = source:sub(2):match("^(.*[/\\])hardcover%.lua$")
        if directory then MODULE_CA_BUNDLE = directory .. "ca-bundle.crt" end
    end
end

local SEARCH_QUERY = [[
query ZenMetadataSearch($query: String!, $page: Int!, $perPage: Int!) {
  search(query: $query, query_type: "Book", page: $page, per_page: $perPage) {
    ids
  }
}
]]

local ISBN_QUERY = [[
query ZenMetadataISBN($isbn: String!, $limit: Int!) {
  editions(
    where: {
      _or: [
        { isbn_10: { _eq: $isbn } }
        { isbn_13: { _eq: $isbn } }
      ]
    }
    order_by: { users_count: desc_nulls_last }
    limit: $limit
  ) {
    id
    book_id
    title
    isbn_10
    isbn_13
    edition_format
    physical_format
    reading_format_id
    pages
    release_date
    release_year
    users_count
    cached_image
    image { url width height }
    language { code2 code3 language }
    publisher { name }
  }
}
]]

local WORKS_QUERY = [[
query ZenMetadataWorks($ids: [Int!]!) {
  books(where: { id: { _in: $ids } }) {
    id
    title
    description
    release_year
    pages
    editions_count
    users_count
    cached_image
    image { url width height }
    cached_tags(path: "Genre")
    contributions {
      contribution
      author { name }
    }
    book_series(order_by: { featured: desc }, limit: 1) {
      featured
      position
      series { name }
    }
  }
}
]]

local EDITIONS_QUERY = [[
query ZenMetadataEditions($bookId: Int!, $limit: Int!) {
  editions(
    where: {
      book_id: { _eq: $bookId }
    }
    order_by: { users_count: desc_nulls_last }
    limit: $limit
  ) {
    id
    book_id
    title
    isbn_10
    isbn_13
    edition_format
    physical_format
    reading_format_id
    pages
    release_date
    release_year
    users_count
    cached_image
    image { url width height }
    language { code2 code3 language }
    publisher { name }
  }
}
]]

local ERROR_KINDS = {
    offline = true,
    unauthorized = true,
    forbidden = true,
    rate_limited = true,
    server = true,
    malformed = true,
    no_match = true,
    network = true,
}

local READING_FORMATS = {
    [1] = "Physical Book",
    [2] = "Audiobook",
    [4] = "E-Book",
}

local function failure(kind, status, retry_after)
    local err = { kind = kind }
    if status then err.status = status end
    if retry_after then err.retry_after = retry_after end
    return err
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function token_value(token)
    token = trim(token)
    if token:sub(1, 7):lower() == "bearer " then
        token = trim(token:sub(8))
    end
    if token == "" then return nil end
    return token
end

local function header_value(headers, wanted)
    if type(headers) ~= "table" then return nil end
    wanted = wanted:lower()
    for key, value in pairs(headers) do
        if type(key) == "string" and key:lower() == wanted then return value end
    end
end

local function ca_bundle(https)
    local candidates = {
        MODULE_CA_BUNDLE or "",
        "data/ca-bundle.crt",
        "./data/ca-bundle.crt",
        "/etc/ssl/certs/ca-certificates.crt",
        "/etc/ssl/cert.pem",
        "/etc/pki/tls/certs/ca-bundle.crt",
    }
    local info = type(https.request) == "function"
        and debug.getinfo(https.request, "S") or nil
    local source = info and info.source or ""
    if source:sub(1, 1) == "@" then
        local root = source:sub(2):match("^(.*[/\\])common[/\\]ssl[/\\]https%.lua$")
        if root then table.insert(candidates, 1, root .. "data/ca-bundle.crt") end
    end
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok_lfs then return nil end
    for _i, path in ipairs(candidates) do
        if lfs.attributes(path, "mode") == "file" then return path end
    end
end

local function hostname_matches(pattern, hostname)
    if type(pattern) ~= "string" or pattern:find("%z") then return false end
    pattern = pattern:lower()
    hostname = hostname:lower()
    if pattern == hostname then return true end
    if pattern:sub(1, 2) ~= "*." then return false end
    local suffix = pattern:sub(2)
    if hostname:sub(-#suffix) ~= suffix then return false end
    local label = hostname:sub(1, #hostname - #suffix)
    return label ~= "" and not label:find(".", 1, true)
end

local function certificate_matches(certificate, hostname)
    if type(certificate) ~= "userdata" and type(certificate) ~= "table" then return false end
    local ok, extensions = pcall(certificate.extensions, certificate)
    if not ok or type(extensions) ~= "table" then return false end
    local function find_dns(value)
        if type(value) ~= "table" then return false end
        for key, child in pairs(value) do
            if key == "dNSName" and type(child) == "table" then
                for _i, name in ipairs(child) do
                    if hostname_matches(name, hostname) then return true end
                end
            elseif type(child) == "table" and find_dns(child) then
                return true
            end
        end
        return false
    end
    return find_dns(extensions)
end

local function verified_create(https, cafile, expected_host)
    local base_create = https.tcp({
        protocol = "any",
        options = { "all", "no_sslv2", "no_sslv3", "no_tlsv1" },
        verify = { "peer", "fail_if_no_peer_cert" },
        cafile = cafile,
    })
    if type(base_create) ~= "function" then return nil end
    return function()
        local connection = base_create()
        if type(connection) ~= "table" or type(connection.connect) ~= "function" then
            return connection
        end
        local connect = connection.connect
        function connection:connect(host, port)
            local connected, err = connect(self, host, port)
            if not connected then return nil, err end
            local certificate = self.sock and self.sock:getpeercertificate()
            if host ~= expected_host or not certificate_matches(certificate, host) then
                pcall(self.close, self)
                return nil, "TLS hostname verification failed"
            end
            return connected
        end
        return connection
    end
end

local function default_transport(token, query, variables)
    local ok_network, NetworkManager = pcall(require, "ui/network/manager")
    if ok_network and NetworkManager and type(NetworkManager.isConnected) == "function" then
        local ok_connected, connected = pcall(NetworkManager.isConnected, NetworkManager)
        if ok_connected and not connected then return nil, failure("offline") end
    end

    local ok_https, https = pcall(require, "ssl.https")
    local ok_http, http = pcall(require, "socket.http")
    local ok_ltn12, ltn12 = pcall(require, "ltn12")
    local ok_socketutil, socketutil = pcall(require, "socketutil")
    if not ok_https or not ok_http or not ok_ltn12 or not ok_socketutil
            or type(https.tcp) ~= "function"
            or type(http.request) ~= "function"
            or type(ltn12.source) ~= "table"
            or type(ltn12.source.string) ~= "function"
            or type(socketutil.set_timeout) ~= "function"
            or type(socketutil.reset_timeout) ~= "function"
            or type(socketutil.table_sink) ~= "function" then
        logger.warn("API transport unavailable ssl=", tostring(ok_https),
            " http=", tostring(ok_http), " ltn12=", tostring(ok_ltn12),
            " socketutil=", tostring(ok_socketutil))
        return nil, failure("network")
    end

    local ok_payload, payload = pcall(json.encode, {
        query = query,
        variables = variables,
    })
    if not ok_payload then return nil, failure("malformed") end
    local cafile = ca_bundle(https)
    local create = cafile and verified_create(https, cafile, API_HOST)
    if not create then
        logger.warn("API TLS setup failed ca_bundle=", tostring(cafile))
        return nil, failure("network")
    end
    logger.dbg("API request start payload_bytes=", #payload,
        " ca_bundle=", cafile)

    local chunks = {}
    local ok_source, source = pcall(ltn12.source.string, payload)
    if not ok_source then
        logger.warn("API request source setup failed")
        return nil, failure("network")
    end
    local ok_timeout = pcall(socketutil.set_timeout, socketutil, BLOCK_TIMEOUT, TOTAL_TIMEOUT)
    if not ok_timeout then
        logger.warn("API timeout setup failed")
        return nil, failure("network")
    end
    local ok_sink, sink = pcall(socketutil.table_sink, chunks)
    if not ok_sink then
        logger.warn("API response sink setup failed")
        pcall(socketutil.reset_timeout, socketutil)
        return nil, failure("network")
    end
    local ok_request, request_result, status, headers = pcall(http.request, {
        url = API_URL,
        method = "POST",
        redirect = false,
        headers = {
            ["Accept"] = "application/json",
            ["Authorization"] = "Bearer " .. token,
            ["Content-Length"] = tostring(#payload),
            ["Content-Type"] = "application/json",
            ["User-Agent"] = USER_AGENT,
        },
        source = source,
        sink = sink,
        create = create,
    })
    pcall(socketutil.reset_timeout, socketutil)
    if not ok_request or request_result == nil or tonumber(status) == nil then
        logger.warn("API request failed error=",
            tostring(ok_request and status or request_result))
        return nil, failure("network")
    end
    logger.dbg("API response status=", tostring(status),
        " body_bytes=", #table.concat(chunks))
    return {
        status = tonumber(status),
        headers = headers,
        body = table.concat(chunks),
    }
end

local function valid_cover_url(url)
    return type(url) == "string"
        and url:match("^https://assets%.hardcover%.app/[^%s]+$") ~= nil
end

local function image_url(row)
    local image = type(row.image) == "table" and row.image or row.cached_image
    local url = type(image) == "table" and trim(image.url) or ""
    return valid_cover_url(url) and url or ""
end

local function default_cover_transport(url, destination)
    local ok_network, NetworkManager = pcall(require, "ui/network/manager")
    if ok_network and NetworkManager and type(NetworkManager.isConnected) == "function" then
        local ok_connected, connected = pcall(NetworkManager.isConnected, NetworkManager)
        if ok_connected and not connected then return nil, failure("offline") end
    end

    local ok_https, https = pcall(require, "ssl.https")
    local ok_http, http = pcall(require, "socket.http")
    local ok_socketutil, socketutil = pcall(require, "socketutil")
    if not ok_https or not ok_http or not ok_socketutil
            or type(https.tcp) ~= "function"
            or type(http.request) ~= "function"
            or type(socketutil.set_timeout) ~= "function"
            or type(socketutil.reset_timeout) ~= "function" then
        logger.warn("cover transport unavailable ssl=", tostring(ok_https),
            " http=", tostring(ok_http), " socketutil=", tostring(ok_socketutil))
        return nil, failure("network")
    end
    local cafile = ca_bundle(https)
    local create = cafile and verified_create(https, cafile, COVER_HOST)
    if not create then
        logger.warn("cover TLS setup failed ca_bundle=", tostring(cafile))
        return nil, failure("network")
    end
    local file = io.open(destination, "wb")
    if not file then
        logger.warn("cover destination could not be opened")
        return nil, failure("network")
    end
    local bytes, sink_error = 0, false
    local function sink(chunk)
        if not chunk then return 1 end
        bytes = bytes + #chunk
        if bytes > MAX_COVER_BYTES then
            sink_error = true
            return nil, "cover too large"
        end
        local written = file:write(chunk)
        if not written then
            sink_error = true
            return nil, "cover write failed"
        end
        return 1
    end
    pcall(socketutil.set_timeout, socketutil, BLOCK_TIMEOUT, TOTAL_TIMEOUT)
    local ok_request, result, status = pcall(http.request, {
        url = url,
        method = "GET",
        redirect = false,
        headers = {
            ["Accept"] = "image/jpeg, image/png, image/webp, image/gif",
            ["User-Agent"] = USER_AGENT,
        },
        sink = sink,
        create = create,
    })
    pcall(socketutil.reset_timeout, socketutil)
    pcall(file.close, file)
    local response_status = status
    status = tonumber(response_status)
    if not ok_request or result == nil or status ~= 200
            or sink_error or bytes == 0 then
        logger.warn("cover request failed status=", tostring(status),
            " error=", tostring(ok_request and response_status or result),
            " bytes=", bytes)
        os.remove(destination)
        if status == 429 then return nil, failure("rate_limited", status) end
        if status and status >= 500 then return nil, failure("server", status) end
        return nil, failure("network", status)
    end
    logger.dbg("cover download complete bytes=", bytes)
    return destination
end

local function transport_failure(err)
    if type(err) ~= "table" or not ERROR_KINDS[err.kind] then
        return failure("network")
    end
    return failure(err.kind, tonumber(err.status), tonumber(err.retry_after))
end

local function decode_response(response)
    if type(response) ~= "table" then return nil, failure("malformed") end
    local status = tonumber(response.status)
    if status == 401 then return nil, failure("unauthorized", status) end
    if status == 403 then return nil, failure("forbidden", status) end
    if status == 429 then
        local retry_after = tonumber(header_value(response.headers, "retry-after"))
        return nil, failure("rate_limited", status, retry_after)
    end
    if status and status >= 500 and status <= 599 then
        return nil, failure("server", status)
    end
    if status == 400 then return nil, failure("malformed", status) end
    if not status or status < 200 or status > 299 then
        return nil, failure("network", status)
    end
    if type(response.body) ~= "string" or response.body == "" then
        return nil, failure("malformed", status)
    end

    local ok, decoded = pcall(json.decode, response.body)
    if not ok or type(decoded) ~= "table"
            or decoded.errors ~= nil or type(decoded.data) ~= "table" then
        return nil, failure("malformed", status)
    end
    return decoded.data
end

local function request(token, query, variables, transport)
    local operation = query:match("query%s+([%w_]+)") or "unknown"
    token = token_value(token)
    if not token then return nil, failure("unauthorized") end
    if transport ~= nil and type(transport) ~= "function" then
        return nil, failure("malformed")
    end

    logger.dbg("request operation=", operation)
    local ok, response, err = pcall(transport or default_transport, token, query, variables)
    if not ok then
        logger.warn("transport crashed operation=", operation)
        return nil, failure("network")
    end
    if not response then
        err = transport_failure(err)
        logger.warn("transport failed operation=", operation,
            " kind=", err.kind, " status=", tostring(err.status))
        return nil, err
    end
    local data, decode_err = decode_response(response)
    if not data then
        logger.warn("response rejected operation=", operation,
            " kind=", decode_err.kind, " status=", tostring(decode_err.status))
        return nil, decode_err
    end
    logger.dbg("request complete operation=", operation)
    return data
end

local function unique_ids(values)
    local ids, seen = {}, {}
    if type(values) ~= "table" then return ids end
    for _i, value in ipairs(values) do
        local id = tonumber(type(value) == "table" and value.book_id or value)
        if id and id > 0 and id == math.floor(id) and not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    return ids
end

local function string_list(values, field)
    local result, seen = {}, {}
    if type(values) ~= "table" then return result end
    for _i, value in ipairs(values) do
        if type(value) == "table" then
            value = field and value[field] or value.name or value.tag
        end
        value = trim(value)
        if value ~= "" and not seen[value] then
            seen[value] = true
            result[#result + 1] = value
        end
    end
    return result
end

local function authors(contributions)
    local result, seen = {}, {}
    if type(contributions) ~= "table" then return result end
    for _i, contribution in ipairs(contributions) do
        if type(contribution) == "table" then
            local role = trim(contribution.contribution):lower()
            local author = contribution.author
            local name = type(author) == "table" and author.name or author
            name = trim(name)
            if (role == "" or role == "author") and name ~= "" and not seen[name] then
                seen[name] = true
                result[#result + 1] = name
            end
        end
    end
    return result
end

local function series(book_series)
    if type(book_series) ~= "table" then return nil, nil end
    local selected = book_series[1]
    for _i, entry in ipairs(book_series) do
        if type(entry) == "table" and entry.featured == true then
            selected = entry
            break
        end
    end
    if type(selected) ~= "table" then return nil, nil end
    local name = type(selected.series) == "table" and trim(selected.series.name) or ""
    return name ~= "" and name or nil, tonumber(selected.position)
end

local function normalize_work(row)
    if type(row) ~= "table" then return nil end
    local id = tonumber(row.id)
    local title = trim(row.title)
    if not id or id <= 0 or title == "" then return nil end
    local series_name, series_index = series(row.book_series)
    return {
        id = id,
        title = title,
        authors = authors(row.contributions),
        series_name = series_name,
        series_index = series_index,
        genres = string_list(row.cached_tags, "tag"),
        description = trim(row.description),
        release_year = tonumber(row.release_year),
        pages = tonumber(row.pages),
        editions_count = tonumber(row.editions_count),
        users_count = tonumber(row.users_count),
        image_url = image_url(row),
    }
end

local function hydrate_works(token, ids, transport)
    local data, err = request(token, WORKS_QUERY, { ids = ids }, transport)
    if not data then return nil, err end
    if type(data.books) ~= "table" then return nil, failure("malformed") end

    local by_id = {}
    for _i, row in ipairs(data.books) do
        local work = normalize_work(row)
        if work then by_id[work.id] = work end
    end
    local works = {}
    for _i, id in ipairs(ids) do
        if by_id[id] then works[#works + 1] = by_id[id] end
    end
    if #works == 0 then return nil, failure("no_match") end
    return works
end

local function isbn_value(input)
    local isbn = input.isbn_13 or input.isbn_10 or input.isbn
    if type(isbn) ~= "string" then return nil end
    isbn = isbn:gsub("[^%dXx]", ""):upper()
    if isbn:match("^%d%d%d%d%d%d%d%d%d[%dX]$") then
        local sum = 0
        for index = 1, 10 do
            local character = isbn:sub(index, index)
            local digit = character == "X" and 10 or tonumber(character)
            sum = sum + digit * (11 - index)
        end
        if sum % 11 == 0 then return isbn end
    elseif isbn:match("^%d%d%d%d%d%d%d%d%d%d%d%d%d$") then
        local sum = 0
        for index = 1, 12 do
            local weight = index % 2 == 0 and 3 or 1
            sum = sum + tonumber(isbn:sub(index, index)) * weight
        end
        if (10 - sum % 10) % 10 == tonumber(isbn:sub(13, 13)) then return isbn end
    end
end

local function search_text(input)
    local title = trim(input.title)
    local author = trim(input.author)
    if author == "" and type(input.authors) == "table" then
        author = trim(input.authors[1])
    end
    if title == "" then return nil end
    local value = author == "" and title or title .. " " .. author
    if #value > MAX_QUERY_LENGTH then return nil end
    return value
end

local normalize_edition

local function is_audio_edition(row)
    if type(row) ~= "table" then return false end
    if tonumber(row.reading_format_id) == 2 then return true end
    local format = (trim(row.edition_format) .. " " .. trim(row.physical_format)):lower()
    return format:find("audio", 1, true) ~= nil
        or format:find("compact disc", 1, true) ~= nil
        or format:match("%f[%w]cd%f[%W]") ~= nil
end

local function prioritize_editions(editions)
    table.sort(editions, function(left, right)
        local left_audio = is_audio_edition(left)
        local right_audio = is_audio_edition(right)
        if left_audio ~= right_audio then return not left_audio end
        local left_count = tonumber(left.users_count) or -1
        local right_count = tonumber(right.users_count) or -1
        if left_count ~= right_count then return left_count > right_count end
        return (tonumber(left.id) or math.huge) < (tonumber(right.id) or math.huge)
    end)
end

function M.search(token, input, transport)
    if type(input) ~= "table" then return nil, failure("malformed") end
    local isbn = isbn_value(input)
    logger.dbg("search start isbn=", isbn and "yes" or "no")
    if isbn then
        local data, err = request(token, ISBN_QUERY, {
            isbn = isbn,
            limit = SEARCH_LIMIT,
        }, transport)
        if not data then return nil, err end
        if type(data.editions) ~= "table" then return nil, failure("malformed") end
        prioritize_editions(data.editions)
        local print_editions = {}
        for _i, row in ipairs(data.editions) do
            if not is_audio_edition(row) then
                print_editions[#print_editions + 1] = row
            end
        end
        if #data.editions > 0 and #print_editions == 0 then
            logger.dbg("ISBN match was audio-only; falling back to title search")
        end
        local ids = unique_ids(print_editions)
        if #ids > 0 then
            local works, hydrate_err = hydrate_works(token, ids, transport)
            if works then
                local exact_by_work = {}
                for _i, row in ipairs(print_editions) do
                    local edition = normalize_edition(row)
                    if edition and not exact_by_work[edition.work_id] then
                        exact_by_work[edition.work_id] = edition
                    end
                end
                for _i, work in ipairs(works) do
                    work.exact_edition = exact_by_work[work.id]
                end
                logger.dbg("ISBN search complete works=", #works)
                return works
            elseif not hydrate_err or hydrate_err.kind ~= "no_match" then
                return nil, hydrate_err
            end
        end
    end

    local query = search_text(input)
    if not query then
        return nil, failure(isbn and "no_match" or "malformed")
    end
    local limit = math.max(1, math.min(25, math.floor(tonumber(input.limit) or SEARCH_LIMIT)))
    local data, err = request(token, SEARCH_QUERY, {
        query = query,
        page = 1,
        perPage = limit,
    }, transport)
    if not data then return nil, err end
    if type(data.search) ~= "table" or type(data.search.ids) ~= "table" then
        return nil, failure("malformed")
    end
    local ids = unique_ids(data.search.ids)
    if #ids == 0 then return nil, failure("no_match") end
    local works, hydrate_err = hydrate_works(token, ids, transport)
    if works then logger.dbg("title search complete works=", #works) end
    return works, hydrate_err
end

local function language_code(language)
    if type(language) ~= "table" then return "" end
    for _i, key in ipairs({ "code2", "code3", "language" }) do
        local value = trim(language[key])
        if value ~= "" then return value end
    end
    return ""
end

normalize_edition = function(row)
    if type(row) ~= "table" then return nil end
    local id, work_id = tonumber(row.id), tonumber(row.book_id)
    if not id or not work_id then return nil end
    local publisher = type(row.publisher) == "table" and trim(row.publisher.name) or ""
    local format = trim(row.edition_format)
    if format == "" then format = trim(row.physical_format) end
    if format == "" then format = READING_FORMATS[tonumber(row.reading_format_id)] or "" end
    local release_year = tonumber(row.release_year)
    if not release_year and type(row.release_date) == "string" then
        release_year = tonumber(row.release_date:match("^(%d%d%d%d)"))
    end
    return {
        id = id,
        work_id = work_id,
        title = trim(row.title),
        isbn_10 = trim(row.isbn_10),
        isbn_13 = trim(row.isbn_13),
        language = language_code(row.language),
        publisher = publisher,
        edition_format = format,
        release_year = release_year,
        pages = tonumber(row.pages),
        users_count = tonumber(row.users_count),
        image_url = image_url(row),
        is_audio = is_audio_edition(row),
    }
end

function M.editions(token, work_or_id, transport)
    local work_id = tonumber(type(work_or_id) == "table" and work_or_id.id or work_or_id)
    if not work_id or work_id <= 0 or work_id ~= math.floor(work_id) then
        return nil, failure("malformed")
    end
    local data, err = request(token, EDITIONS_QUERY, {
        bookId = work_id,
        limit = EDITION_LIMIT,
    }, transport)
    if not data then return nil, err end
    if type(data.editions) ~= "table" then return nil, failure("malformed") end
    prioritize_editions(data.editions)

    local editions = {}
    for _i, row in ipairs(data.editions) do
        local edition = normalize_edition(row)
        if edition then editions[#editions + 1] = edition end
    end
    if #editions == 0 then return nil, failure("no_match") end
    logger.dbg("edition lookup complete work_id=", work_id, " editions=", #editions)
    return editions
end

function M.downloadCover(url, destination, transport)
    if not valid_cover_url(url) or type(destination) ~= "string" or destination == ""
            or (transport ~= nil and type(transport) ~= "function") then
        return nil, failure("malformed")
    end
    logger.dbg("cover download start")
    local ok, path, err = pcall(transport or default_cover_transport, url, destination)
    if not ok then return nil, failure("network") end
    if not path then return nil, transport_failure(err) end
    return path
end

local function copy_list(values)
    local result = {}
    if type(values) == "table" then
        for _i, value in ipairs(values) do result[#result + 1] = value end
    end
    return result
end

function M.draft(work, edition)
    if type(work) ~= "table" or (edition ~= nil and type(edition) ~= "table") then
        return nil, failure("malformed")
    end
    edition = edition or {}
    local title = trim(edition.title)
    if title == "" then title = trim(work.title) end
    return {
        title = title,
        authors = copy_list(work.authors),
        series_name = trim(work.series_name),
        series_index = work.series_index,
        genres = copy_list(work.genres),
        language = trim(edition.language),
        publisher = trim(edition.publisher),
        description = trim(work.description),
        isbn = trim(edition.isbn_13) ~= "" and trim(edition.isbn_13) or trim(edition.isbn_10),
    }
end

return M

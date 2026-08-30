local JSON = require("json")

local function response(data, status, headers)
    return {
        status = status or 200,
        headers = headers or {},
        body = type(data) == "string" and data or JSON.encode(data),
    }
end

local function queued(responses)
    local calls = {}
    local index = 0
    return function(token, query, variables)
        index = index + 1
        calls[index] = { token = token, query = query, variables = variables }
        local item = responses[index]
        if type(item) == "function" then return item() end
        return item
    end, calls
end

describe("Hardcover metadata client", function()
    local Hardcover

    before_each(function()
        ZenSpec.unload("modules/filebrowser/metadata/hardcover")
        Hardcover = require("modules/filebrowser/metadata/hardcover")
    end)

    it("searches with variables and normalizes works in result order", function()
        local transport, calls = queued({
            response({ data = { search = { ids = { 2, 1, 2 } } } }),
            response({ data = { books = {
                {
                    id = 1,
                    title = "Second",
                    contributions = {},
                    book_series = {},
                    cached_tags = {},
                },
                {
                    id = 2,
                    title = "Dune",
                    description = "Spice.",
                    release_year = 1965,
                    pages = 412,
                    editions_count = 84,
                    users_count = 1000,
                    image = {
                        url = "https://assets.hardcover.app/book/2/cover.jpeg",
                    },
                    contributions = {
                        { author = { name = "Frank Herbert" } },
                        { author = { name = "Frank Herbert" } },
                        { contribution = "Narrator", author = { name = "George Guidall" } },
                        { contribution = "translator", author = { name = "Translator" } },
                    },
                    book_series = {
                        { featured = true, position = 1, series = { name = "Dune" } },
                    },
                    cached_tags = {
                        { tag = "Science Fiction" },
                        { tag = "Adventure" },
                    },
                },
            } } }),
        })

        local works = assert(Hardcover.search("Bearer secret-token", {
            title = "Dune",
            authors = { "Frank Herbert" },
            limit = 7,
        }, transport))

        assert.are.equal(2, #works)
        assert.are.equal(2, works[1].id)
        assert.are.same({ "Frank Herbert" }, works[1].authors)
        assert.are.equal("Dune", works[1].series_name)
        assert.are.equal(1, works[1].series_index)
        assert.are.same({ "Science Fiction", "Adventure" }, works[1].genres)
        assert.are.equal("Spice.", works[1].description)
        assert.are.equal("https://assets.hardcover.app/book/2/cover.jpeg",
            works[1].image_url)
        assert.are.equal(1, works[2].id)
        assert.are.equal("secret-token", calls[1].token)
        assert.are.same({ query = "Dune Frank Herbert", page = 1, perPage = 7 }, calls[1].variables)
        assert.is_truthy(calls[1].query:find("$query", 1, true))
        assert.is_nil(calls[1].query:find("Dune Frank Herbert", 1, true))
        assert.are.same({ ids = { 2, 1 } }, calls[2].variables)
        assert.is_truthy(calls[2].query:find("contribution", 1, true))
        assert.is_truthy(calls[2].query:find("cached_image", 1, true))
    end)

    it("uses an exact ISBN variable before title search", function()
        local transport, calls = queued({
            response({ data = { editions = {
                {
                    id = 90,
                    book_id = 7,
                    title = "Dune",
                    isbn_13 = "9780441013593",
                    edition_format = "Paperback",
                    reading_format_id = 1,
                    pages = 535,
                    release_year = 2005,
                    language = { code2 = "en" },
                    publisher = { name = "Ace" },
                },
                { id = 91, book_id = 7, reading_format_id = 1 },
            } } }),
            response({ data = { books = {
                {
                    id = 7,
                    title = "Dune",
                    contributions = {},
                    book_series = {},
                    cached_tags = {},
                },
            } } }),
        })

        local works = assert(Hardcover.search("secret-token", {
            isbn = "978-0-441-01359-3",
            title = "ignored",
        }, transport))

        assert.are.equal(1, #works)
        assert.are.equal(7, works[1].id)
        assert.are.equal(90, works[1].exact_edition.id)
        assert.are.equal("9780441013593", works[1].exact_edition.isbn_13)
        assert.are.equal("Paperback", works[1].exact_edition.edition_format)
        assert.are.equal("en", works[1].exact_edition.language)
        assert.are.equal("Ace", works[1].exact_edition.publisher)
        assert.are.same({ isbn = "9780441013593", limit = 10 }, calls[1].variables)
        assert.is_nil(calls[1].query:find("9780441013593", 1, true))
        assert.are.same({ ids = { 7 } }, calls[2].variables)
    end)

    it("puts exact ISBN works before all deduplicated title results", function()
        local transport, calls = queued({
            response({ data = { editions = {{
                id = 90,
                book_id = 7,
                isbn_13 = "9780441013593",
                reading_format_id = 1,
            }} } }),
            response({ data = { books = {{
                id = 7,
                title = "Exact",
                contributions = {},
                book_series = {},
                cached_tags = {},
            }} } }),
            response({ data = { search = { ids = { 8, 7, 9 } } } }),
            response({ data = { books = {
                { id = 9, title = "Third", contributions = {}, book_series = {}, cached_tags = {} },
                { id = 7, title = "Exact", contributions = {}, book_series = {}, cached_tags = {} },
                { id = 8, title = "Second", contributions = {}, book_series = {}, cached_tags = {} },
            } } }),
        })

        local works, err = Hardcover.search("secret-token", {
            isbn = "9780441013593",
            title = "Dune",
            author = "Frank Herbert",
            include_title_results = true,
        }, transport)
        if not works then
            error("combined search failed: " .. tostring(err and err.kind)
                .. " after " .. tostring(#calls) .. " calls")
        end

        assert.are.same({ 7, 8, 9 }, { works[1].id, works[2].id, works[3].id })
        assert.are.equal(90, works[1].exact_edition.id)
        assert.is_nil(works[2].exact_edition)
        assert.are.equal("Dune Frank Herbert", calls[3].variables.query)
        assert.are.same({ ids = { 8, 7, 9 } }, calls[4].variables)
    end)

    it("falls back to title search for an audio-only ISBN match", function()
        local transport, calls = queued({
            response({ data = { editions = {{
                id = 90,
                book_id = 7,
                edition_format = "Audio CD",
                reading_format_id = 2,
            }} } }),
            response({ data = { search = { ids = { 8 } } } }),
            response({ data = { books = {{
                id = 8,
                title = "Never Split the Difference",
                contributions = {},
                book_series = {},
                cached_tags = {},
            }} } }),
        })

        local works = assert(Hardcover.search("secret-token", {
            isbn = "9780441013593",
            title = "Never Split the Difference",
            author = "Chris Voss",
        }, transport))

        assert.are.equal(8, works[1].id)
        assert.is_nil(works[1].exact_edition)
        assert.are.equal("9780441013593", calls[1].variables.isbn)
        assert.are.equal("Never Split the Difference Chris Voss",
            calls[2].variables.query)
    end)

    it("falls back to title and author when normalized ISBN is empty", function()
        local transport, calls = queued({
            response({ data = { search = { ids = { 7 } } } }),
            response({ data = { books = {{
                id = 7,
                title = "Dune",
                contributions = { { author = { name = "Frank Herbert" } } },
                book_series = {},
                cached_tags = {},
            }} } }),
        })

        local works = assert(Hardcover.search("secret-token", {
            isbn = "",
            title = "Dune",
            authors = { "Frank Herbert" },
        }, transport))

        assert.are.equal("Dune", works[1].title)
        assert.are.same({
            query = "Dune Frank Herbert",
            page = 1,
            perPage = 10,
        }, calls[1].variables)
    end)

    it("falls back to title and author when the ISBN is invalid", function()
        local transport, calls = queued({
            response({ data = { search = { ids = { 7 } } } }),
            response({ data = { books = {{
                id = 7,
                title = "Dune",
                contributions = {},
                book_series = {},
                cached_tags = {},
            }} } }),
        })

        assert(Hardcover.search("secret-token", {
            isbn = "invalid",
            title = "Dune",
            author = "Frank Herbert",
        }, transport))

        assert.are.equal("Dune Frank Herbert", calls[1].variables.query)
    end)

    it("does not query a shape-valid ISBN with a bad checksum", function()
        local transport, calls = queued({
            response({ data = { search = { ids = { 7 } } } }),
            response({ data = { books = {{
                id = 7,
                title = "Dune",
                contributions = {},
                book_series = {},
                cached_tags = {},
            }} } }),
        })

        assert(Hardcover.search("secret-token", {
            isbn = "9780441013594",
            title = "Dune",
        }, transport))

        assert.are.equal("Dune", calls[1].variables.query)
    end)

    it("falls back to title and author when a valid ISBN has no match", function()
        local transport, calls = queued({
            response({ data = { editions = {} } }),
            response({ data = { search = { ids = { 7 } } } }),
            response({ data = { books = {{
                id = 7,
                title = "Dune",
                contributions = {},
                book_series = {},
                cached_tags = {},
            }} } }),
        })

        local works = assert(Hardcover.search("secret-token", {
            isbn = "9780441013593",
            title = "Dune",
            authors = { "Frank Herbert" },
        }, transport))

        assert.are.equal("Dune", works[1].title)
        assert.are.equal("9780441013593", calls[1].variables.isbn)
        assert.are.equal("Dune Frank Herbert", calls[2].variables.query)
    end)

    it("normalizes editions and ranks audio formats last", function()
        local transport, calls = queued({
            response({ data = { editions = {
                {
                    id = 9,
                    book_id = 7,
                    title = "Dune",
                    isbn_10 = "0441172717",
                    isbn_13 = "9780441172719",
                    reading_format_id = 4,
                    pages = 412,
                    release_date = "2010-09-14",
                    users_count = 20,
                    image = {
                        url = "https://assets.hardcover.app/edition/9/cover.jpeg",
                    },
                    language = { code2 = "en", language = "English" },
                    publisher = { name = "Ace" },
                },
                {
                    id = 10,
                    book_id = 7,
                    edition_format = "Audio CD",
                    reading_format_id = 2,
                    users_count = 200,
                },
                {
                    id = 11,
                    book_id = 7,
                    physical_format = "CD",
                    reading_format_id = 1,
                    users_count = 100,
                },
            } } }),
        })

        local editions = assert(Hardcover.editions("secret-token", { id = 7 }, transport))

        assert.are.equal(3, #editions)
        assert.are.equal(9, editions[1].id)
        assert.are.equal(7, editions[1].work_id)
        assert.are.equal("E-Book", editions[1].edition_format)
        assert.are.equal(2010, editions[1].release_year)
        assert.are.equal("en", editions[1].language)
        assert.are.equal("Ace", editions[1].publisher)
        assert.are.equal("https://assets.hardcover.app/edition/9/cover.jpeg",
            editions[1].image_url)
        assert.is_false(editions[1].is_audio)
        assert.are.equal(10, editions[2].id)
        assert.is_true(editions[2].is_audio)
        assert.are.equal(11, editions[3].id)
        assert.is_true(editions[3].is_audio)
        assert.are.same({ bookId = 7, limit = 30 }, calls[1].variables)
        assert.is_nil(calls[1].query:find("secret-token", 1, true))
    end)

    it("downloads only trusted Hardcover cover URLs", function()
        local calls = 0
        local transport = function(url, destination)
            calls = calls + 1
            assert.are.equal("https://assets.hardcover.app/edition/9/cover.jpeg", url)
            assert.are.equal("/tmp/cover.jpg", destination)
            return destination
        end

        assert.are.equal("/tmp/cover.jpg", Hardcover.downloadCover(
            "https://assets.hardcover.app/edition/9/cover.jpeg",
            "/tmp/cover.jpg", transport))
        local path, err = Hardcover.downloadCover(
            "https://example.com/cover.jpg", "/tmp/cover.jpg", transport)
        assert.is_nil(path)
        assert.are.equal("malformed", err.kind)
        assert.are.equal(1, calls)
    end)

    it("builds a metadata service draft without sharing list tables", function()
        local work = {
            title = "Work title",
            authors = { "Author" },
            series_name = "Series",
            series_index = 2,
            genres = { "Fantasy" },
            description = "Description",
        }
        local edition = {
            title = "Edition title",
            language = "en",
            publisher = "Publisher",
            isbn_13 = "9780000000002",
        }

        local draft = assert(Hardcover.draft(work, edition))

        assert.are.same({
            title = "Edition title",
            authors = { "Author" },
            series_name = "Series",
            series_index = 2,
            genres = { "Fantasy" },
            language = "en",
            publisher = "Publisher",
            description = "Description",
            isbn = "9780000000002",
        }, draft)
        draft.authors[1] = "Changed"
        draft.genres[1] = "Changed"
        assert.are.equal("Author", work.authors[1])
        assert.are.equal("Fantasy", work.genres[1])
    end)

    it("classifies HTTP failures without exposing response content", function()
        local cases = {
            { status = 401, kind = "unauthorized" },
            { status = 403, kind = "forbidden" },
            { status = 429, kind = "rate_limited", retry_after = 17 },
            { status = 503, kind = "server" },
        }
        for _i, item in ipairs(cases) do
            local headers = item.status == 429 and { ["Retry-After"] = "17" } or {}
            local transport = queued({ response("token=must-not-escape", item.status, headers) })
            local works, err = Hardcover.search("secret-token", { title = "Dune" }, transport)
            assert.is_nil(works)
            assert.are.equal(item.kind, err.kind)
            assert.are.equal(item.status, err.status)
            assert.are.equal(item.retry_after, err.retry_after)
            assert.is_nil(err.message)
        end
    end)

    it("classifies offline, malformed, and no-match results", function()
        local offline = function()
            return nil, { kind = "offline", message = "secret-token" }
        end
        local works, err = Hardcover.search("secret-token", { title = "Dune" }, offline)
        assert.is_nil(works)
        assert.are.same({ kind = "offline" }, err)

        local throws = function() error("secret-token") end
        works, err = Hardcover.search("secret-token", { title = "Dune" }, throws)
        assert.is_nil(works)
        assert.are.same({ kind = "network" }, err)

        local malformed = queued({ response("not json") })
        works, err = Hardcover.search("secret-token", { title = "Dune" }, malformed)
        assert.is_nil(works)
        assert.are.equal("malformed", err.kind)

        local no_match = queued({ response({ data = { search = { ids = {} } } }) })
        works, err = Hardcover.search("secret-token", { title = "Dune" }, no_match)
        assert.is_nil(works)
        assert.are.equal("no_match", err.kind)
    end)

    it("rejects missing tokens and invalid search input before transport", function()
        local calls = 0
        local transport = function()
            calls = calls + 1
            return response({})
        end

        local works, err = Hardcover.search("", { title = "Dune" }, transport)
        assert.is_nil(works)
        assert.are.equal("unauthorized", err.kind)
        works, err = Hardcover.search("secret-token", { isbn = "bad" }, transport)
        assert.is_nil(works)
        assert.are.equal("malformed", err.kind)
        assert.are.equal(0, calls)
    end)
end)

describe("Hardcover metadata HTTPS transport", function()
    local originals
    local captured
    local timeout_calls
    local certificate_name
    local tls_options

    before_each(function()
        originals = {}
        for _i, name in ipairs({
            "ui/network/manager", "ssl.https", "socket.http", "ltn12",
            "socketutil", "libs/libkoreader-lfs",
        }) do
            originals[name] = package.loaded[name]
        end
        captured = nil
        timeout_calls = {}
        certificate_name = "api.hardcover.app"
        tls_options = nil
        ZenSpec.replace("ui/network/manager", {
            isConnected = function() return true end,
        })
        ZenSpec.replace("ltn12", {
            source = { string = function(value) return value end },
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path)
                return path:sub(-#"/modules/filebrowser/metadata/ca-bundle.crt")
                    == "/modules/filebrowser/metadata/ca-bundle.crt"
                    and "file" or nil
            end,
        })
        ZenSpec.replace("socketutil", {
            set_timeout = function(_self, block_timeout, total_timeout)
                timeout_calls[#timeout_calls + 1] = { block_timeout, total_timeout }
            end,
            reset_timeout = function()
                timeout_calls[#timeout_calls + 1] = "reset"
            end,
            table_sink = function(target)
                return function(chunk)
                    if chunk then target[#target + 1] = chunk end
                    return 1
                end
            end,
        })
        ZenSpec.replace("ssl.https", {
            request = function() end,
            tcp = function(options)
                tls_options = options
                return function()
                    return {
                        sock = {
                            getpeercertificate = function()
                                return {
                                    extensions = function()
                                        return { subjectAltName = {
                                            dNSName = { certificate_name },
                                        } }
                                    end,
                                }
                            end,
                        },
                        connect = function() return 1 end,
                        close = function() end,
                    }
                end
            end,
        })
        ZenSpec.replace("socket.http", {
            request = function(request)
                captured = request
                local connection = request.create()
                local host = request.url:find("assets.hardcover.app", 1, true)
                    and "assets.hardcover.app" or "api.hardcover.app"
                local connected = connection:connect(host, 443)
                if not connected then return nil, "TLS failure" end
                if host == "assets.hardcover.app" then
                    request.sink("\255\216fixture")
                else
                    request.sink(JSON.encode({ data = { search = { ids = {} } } }))
                end
                return 1, 200, {}, "HTTP/1.1 200 OK"
            end,
        })
        ZenSpec.unload("modules/filebrowser/metadata/hardcover")
    end)

    after_each(function()
        for name, original in pairs(originals) do package.loaded[name] = original end
        ZenSpec.unload("modules/filebrowser/metadata/hardcover")
    end)

    it("keeps the token only in the authorization header", function()
        local Hardcover = require("modules/filebrowser/metadata/hardcover")
        local works, err = Hardcover.search("Bearer secret-token", { title = "Dune" })

        assert.is_nil(works)
        assert.are.equal("no_match", err.kind)
        assert.are.equal("Bearer secret-token", captured.headers.Authorization)
        assert.is_false(captured.redirect)
        assert.are.equal("application/json", captured.headers.Accept)
        assert.is_nil(captured.source:find("secret-token", 1, true))
        assert.are.same({ 6, 12 }, timeout_calls[1])
        assert.are.equal("reset", timeout_calls[2])
        assert.are.same({ "peer", "fail_if_no_peer_cert" }, tls_options.verify)
        assert.matches("/modules/filebrowser/metadata/ca%-bundle%.crt$",
            tls_options.cafile)
        local payload = JSON.decode(captured.source)
        assert.are.equal("Dune", payload.variables.query)
        assert.is_truthy(payload.query:find("$query", 1, true))
    end)

    it("rejects a valid chain for the wrong hostname", function()
        certificate_name = "attacker.example"
        local Hardcover = require("modules/filebrowser/metadata/hardcover")
        local works, err = Hardcover.search("secret-token", { title = "Dune" })
        assert.is_nil(works)
        assert.are.equal("network", err.kind)
    end)

    it("downloads supported image bytes from the cover host", function()
        certificate_name = "assets.hardcover.app"
        local destination = os.tmpname() .. ".img"
        local Hardcover = require("modules/filebrowser/metadata/hardcover")

        assert.are.equal(destination, Hardcover.downloadCover(
            "https://assets.hardcover.app/edition/9/cover.jpeg", destination))
        assert.are.equal("image/jpeg, image/png, image/webp, image/gif",
            captured.headers.Accept)
        local file = assert(io.open(destination, "rb"))
        assert.are.equal("\255\216fixture", file:read("*a"))
        file:close()
        os.remove(destination)
    end)
end)

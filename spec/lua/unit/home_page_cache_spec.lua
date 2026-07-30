describe("home data and book caches", function()
    local doc_open_count
    local history_reload_count
    local status_lookup_count
    local stable_contexts
    local favorite_lookup_count
    local history_items

    before_each(function()
        _G.__ZEN_UI_LAST_READ_FILE = nil
        doc_open_count = 0
        history_reload_count = 0
        status_lookup_count = 0
        stable_contexts = {}
        favorite_lookup_count = 0
        history_items = { { file = "/library/alpha.epub" } }

        ZenSpec.replace("config/manager", { get = function() return {} end })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_WHITE = "white", COLOR_BLACK = "black" })
        ZenSpec.replace("modules/filebrowser/patches/home/home_quotes", {})
        ZenSpec.replace("modules/filebrowser/patches/home/home_presets", {})
        ZenSpec.replace("common/reading_goals", {})
        ZenSpec.replace("config/preset_store", {})
        ZenSpec.replace("modules/filebrowser/patches/home/components/registry", {
            get = function(id) return { id = id } end,
            list = function() return {} end,
            setRefreshCallback = function() end,
        })
        ZenSpec.replace("modules/filebrowser/patches/standalone_page", {})
        ZenSpec.replace("common/shared_state", {
            register = function() return {} end,
            registerLoader = function() end,
        })
        ZenSpec.replace("common/title_sort", { key = function(value) return tostring(value) end })
        ZenSpec.replace("common/widget_resources", {})
        ZenSpec.replace("common/ui/background", { tile_bg = function(color) return color end })

        local doc = {
            readSetting = function(_, key)
                if key == "percent_finished" then return 0.25 end
                if key == "summary" then return { status = "reading" } end
                if key == "stats" then return { pages = 400 } end
            end,
        }
        ZenSpec.replace("docsettings", {
            findSidecarFile = function(_, path) return path .. ".sdr/metadata.lua" end,
            hasSidecarFile = function() return true end,
            open = function()
                doc_open_count = doc_open_count + 1
                return doc
            end,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(_path, key)
                if key == "mode" then return "file" end
                if key == "modification" then return 1 end
                return { mode = "file", modification = 1 }
            end,
        })
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function()
                return {
                    title = "Alpha", authors = "Author", pages = 400,
                    cover_fetched = true, ignore_cover = true,
                }
            end,
        })
        ZenSpec.replace("modules/filebrowser/patches/rakuyomi", {
            getMetadata = function() end,
        })
        ZenSpec.replace("readhistory", {
            hist = history_items,
            reload = function() history_reload_count = history_reload_count + 1 end,
        })
        ZenSpec.replace("readcollection", {
            isFileInCollections = function()
                favorite_lookup_count = favorite_lookup_count + 1
                return true
            end,
        })
        ZenSpec.replace("common/paths", {
            getHomeDir = function() return "/library" end,
            normPath = function(path) return path end,
            isInHomeDir = function() return true end,
        })
        ZenSpec.replace("common/book_status", {
            isImageFile = function() return false end,
            includeNewInTBREnabled = function() return false end,
            getComputedStatus = function() return "reading" end,
            getEffectiveStatusFromFile = function()
                status_lookup_count = status_lookup_count + 1
                return "reading"
            end,
        })
        ZenSpec.replace("common/tbr_index", {
            refreshPath = function() end,
        })
        ZenSpec.replace("common/utils", {
            getStablePageCount = function(_path, fallback, context)
                stable_contexts[#stable_contexts + 1] = context
                return fallback
            end,
        })
        ZenSpec.unload("modules/filebrowser/patches/home_page")
    end)

    after_each(function()
        _G.__ZEN_UI_LAST_READ_FILE = nil
    end)

    local function get_home_module(apply)
        for i = 1, 20 do
            local name, value = debug.getupvalue(apply, i)
            if not name then break end
            if name == "register_home_api" then
                for j = 1, 20 do
                    local child_name, child_value = debug.getupvalue(value, j)
                    if not child_name then break end
                    if child_name == "M" then return child_value end
                end
            end
        end
        error("home module upvalue not found")
    end

    local function get_build_data_provider(Home)
        for i = 1, 80 do
            local name, value = debug.getupvalue(Home.showHomeView, i)
            if not name then break end
            if name == "build_data_provider" then return value end
        end
        error("build_data_provider upvalue not found")
    end

    it("reuses history/status data across providers and opens one sidecar per book miss", function()
        local Home = get_home_module(require("modules/filebrowser/patches/home_page"))
        local build_data_provider = get_build_data_provider(Home)
        local cfg = { browser_cover_badges = {} }
        local dcfg = {
            rows = {
                order = { "strip_recent" },
                enabled = { strip_recent = true },
                max_rows = 1,
            },
            modules = { strip_recent = {} },
        }

        local first = build_data_provider(cfg, dcfg)
        local second = build_data_provider(cfg, dcfg)
        assert.are.equal(1, #first:getBooksForStrip("recently_read", 4, "default", "strip_recent"))
        assert.are.equal(1, #second:getBooksForStrip("recently_read", 4, "default", "strip_recent"))

        assert.are.equal(1, history_reload_count)
        assert.are.equal(1, status_lookup_count)
        assert.are.equal(1, doc_open_count)
        assert.are.equal(1, #stable_contexts)
        assert.is_true(stable_contexts[1].sidecar_checked)
        assert.is_table(stable_contexts[1].doc_settings)
        assert.is_true(stable_contexts[1].book_info_checked)
        assert.is_table(stable_contexts[1].book_info)
        assert.are.equal(0, favorite_lookup_count)

        table.remove(history_items, 1)
        Home.invalidateBookCache("/library/alpha.epub", true)
        local after_removal = build_data_provider(cfg, dcfg)
        assert.are.equal(0,
            #after_removal:getBooksForStrip("recently_read", 4, "default", "strip_recent"))
        assert.are.equal(2, history_reload_count)
    end)

    it("loads a tag strip from the tag index without consulting reading history", function()
        local requested_tag
        ZenSpec.replace("common/db_bookinfo", {
            getTagBooks = function(tag)
                requested_tag = tag
                return { "/library/alpha.epub" }
            end,
        })
        local Home = get_home_module(require("modules/filebrowser/patches/home_page"))
        local build_data_provider = get_build_data_provider(Home)
        local provider = build_data_provider({ browser_cover_badges = {} }, {
            rows = {
                order = { "strip_tag" },
                enabled = { strip_tag = true },
                max_rows = 1,
            },
            modules = { strip_tag = { tag = "Science" } },
        })

        local books = provider:getBooksForStrip("tag", 4, "default", "strip_tag")

        assert.are.equal("Science", requested_tag)
        assert.are.equal("/library/alpha.epub", books[1].path)
        assert.are.equal(0, history_reload_count)
    end)

    it("caps recent strip candidates at 40 without a library fallback walk", function()
        for i = #history_items, 1, -1 do
            table.remove(history_items, i)
        end
        for i = 1, 45 do
            history_items[#history_items + 1] = {
                file = string.format("/library/book-%02d.epub", i),
            }
        end
        ZenSpec.replace("common/book_walker", {
            walk = function()
                error("Recent strips must not walk the library")
            end,
        })
        ZenSpec.unload("modules/filebrowser/patches/home_page")
        local Home = get_home_module(require("modules/filebrowser/patches/home_page"))
        local build_data_provider = get_build_data_provider(Home)
        local provider = build_data_provider({ browser_cover_badges = {} }, {
            rows = {
                order = { "strip_recent" },
                enabled = { strip_recent = true },
                max_rows = 1,
            },
            modules = { strip_recent = {} },
        })

        local books = provider:getBooksForStripPage(
            "recently_read", 4, "default", "strip_recent", 10)

        assert.are.equal("/library/book-01.epub", books[1].path)
        assert.are.equal(40, status_lookup_count)
    end)

    it("requests only visible TBR rows from the persistent index", function()
        local indexed = {
            "/library/tbr-1.epub", "/library/tbr-2.epub", "/library/tbr-3.epub",
            "/library/tbr-4.epub", "/library/tbr-5.epub", "/library/tbr-6.epub",
        }
        local page_calls = {}
        local all_calls = 0
        ZenSpec.replace("common/tbr_index", {
            refreshPath = function() end,
            getRevision = function() return 1 end,
            getCount = function() return #indexed end,
            getPage = function(offset, limit)
                page_calls[#page_calls + 1] = { offset = offset, limit = limit }
                local out = {}
                for index = offset + 1, math.min(#indexed, offset + limit) do
                    out[#out + 1] = indexed[index]
                end
                return out, #indexed
            end,
            getAll = function()
                all_calls = all_calls + 1
                return indexed
            end,
            isAuditRunning = function() return false end,
            scheduleAudit = function() return true end,
            cancelAudit = function() end,
        })
        ZenSpec.replace("common/db_bookinfo", {
            getTBRIndexCandidates = function() return {} end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, fn) fn() end,
            scheduleIn = function() end,
        })
        ZenSpec.unload("modules/filebrowser/patches/home_page")

        local Home = get_home_module(require("modules/filebrowser/patches/home_page"))
        local build_data_provider = get_build_data_provider(Home)
        local provider = build_data_provider({
            browser_cover_badges = {},
            group_view = {
                detail_collate = { to_be_read = { to_be_read = "title" } },
                detail_reverse = { to_be_read = { to_be_read = false } },
            },
        }, {
            rows = {
                order = { "strip_tbr" },
                enabled = { strip_tbr = true },
                max_rows = 1,
            },
            modules = { strip_tbr = {} },
        })

        local featured = provider:getFeaturedBook("to_be_read", "default")
        local first = provider:getBooksForStripPage(
            "to_be_read", 2, "default", "strip_tbr", 0)
        local adjacent = provider:getBooksForStripPage(
            "to_be_read", 2, "default", "strip_tbr", 1)

        assert.are.equal("/library/tbr-1.epub", featured.path)
        assert.are.equal("/library/tbr-1.epub", first[1].path)
        assert.are.equal("/library/tbr-2.epub", first[2].path)
        assert.are.equal("/library/tbr-3.epub", adjacent[1].path)
        assert.are.same({
            { offset = 0, limit = 1 },
            { offset = 0, limit = 2 },
            { offset = 2, limit = 2 },
        }, page_calls)
        assert.are.equal(0, all_calls)
    end)

    it("caps TBR strip pages to the first 40 indexed books", function()
        local indexed = {}
        for i = 1, 45 do
            indexed[#indexed + 1] = string.format("/library/tbr-%02d.epub", i)
        end
        ZenSpec.replace("common/tbr_index", {
            refreshPath = function() end,
            getCount = function() return #indexed end,
            getPage = function(offset, limit)
                local out = {}
                for i = offset + 1, math.min(#indexed, offset + limit) do
                    out[#out + 1] = indexed[i]
                end
                return out
            end,
            isAuditRunning = function() return false end,
            scheduleAudit = function() return true end,
            cancelAudit = function() end,
        })
        ZenSpec.replace("common/db_bookinfo", {
            getTBRIndexCandidates = function() return {} end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_, fn) fn() end,
            scheduleIn = function() end,
        })
        ZenSpec.unload("modules/filebrowser/patches/home_page")

        local Home = get_home_module(require("modules/filebrowser/patches/home_page"))
        local build_data_provider = get_build_data_provider(Home)
        local provider = build_data_provider({
            browser_cover_badges = {},
            group_view = {
                detail_collate = { to_be_read = { to_be_read = "title" } },
                detail_reverse = { to_be_read = { to_be_read = false } },
            },
        }, {
            rows = {
                order = { "strip_tbr" },
                enabled = { strip_tbr = true },
                max_rows = 1,
            },
            modules = { strip_tbr = {} },
        })

        local books = provider:getBooksForStripPage(
            "to_be_read", 2, "default", "strip_tbr", 20)

        assert.are.equal("/library/tbr-01.epub", books[1].path)
    end)

    it("resolves favorite state only for strips that display badges", function()
        local Home = get_home_module(require("modules/filebrowser/patches/home_page"))
        local build_data_provider = get_build_data_provider(Home)
        local cfg = { browser_cover_badges = { show_favorite_badge = true } }
        local dcfg = {
            rows = {
                order = { "strip_recent" },
                enabled = { strip_recent = true },
                max_rows = 1,
            },
            modules = { strip_recent = { show_badges = true } },
        }

        local provider = build_data_provider(cfg, dcfg)
        local books = provider:getBooksForStrip("recently_read", 4, "default", "strip_recent")
        assert.is_true(books[1].is_fav)
        assert.are.equal(1, favorite_lookup_count)
    end)

end)

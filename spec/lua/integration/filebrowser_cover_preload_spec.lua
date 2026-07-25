describe("filebrowser cover preloading", function()
    local scheduled
    local warmed
    local measurements
    local extracting
    local update_items
    local dirty
    local extraction_launches

    before_each(function()
        scheduled = {}
        warmed = {}
        measurements = {}
        extracting = false
        update_items = function() end
        dirty = {}
        extraction_launches = {}

        ZenSpec.replace("covermenu", {
            updateItems = function(menu, ...)
                return update_items(menu, ...)
            end,
            onCloseWidget = function() end,
        })
        ZenSpec.replace("ui/widget/filechooser", {
            updateItems = function(menu, ...)
                return update_items(menu, ...)
            end,
            onCloseWidget = function() end,
        })
        ZenSpec.replace("ui/widget/menu", {
            onNextPage = function() return true end,
            onPrevPage = function() return true end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, fn)
                fn()
            end,
            scheduleIn = function(_self, _delay, fn)
                scheduled[#scheduled + 1] = fn
            end,
            unschedule = function(_self, fn)
                for index = #scheduled, 1, -1 do
                    if scheduled[index] == fn then table.remove(scheduled, index) end
                end
            end,
            setDirty = function(_self, widget, mode)
                dirty[#dirty + 1] = { widget = widget, mode = mode }
            end,
        })
        ZenSpec.replace("bookinfomanager", {
            subprocesses_collect_interval = 10,
            isExtractingInBackground = function() return extracting end,
            extractInBackground = function(_self, files)
                extraction_launches[#extraction_launches + 1] = files
                extracting = true
                return true
            end,
            terminateBackgroundJobs = function() end,
            getBookInfo = function(_self, path)
                warmed[#warmed + 1] = path
                return {
                    cover_bb = {
                        free = function() end,
                    },
                }
            end,
        })
        ZenSpec.replace("common/cover_decode_cache", {
            has = function() return false end,
            stats = function()
                return {
                    bytes = 0,
                    hits = 0,
                    misses = 0,
                    full_reads = 0,
                    decode_reads = 0,
                    decode_read_ms = 0,
                    validation_ms = 0,
                }
            end,
        })
        ZenSpec.replace("common/cover_render_cache", {
            stats = function()
                return { bytes = 0, hits = 0, misses = 0 }
            end,
        })
        local tick = 0
        ZenSpec.replace("common/zen_logger", {
            now = function()
                tick = tick + 0.001
                return tick
            end,
            new = function()
                return {
                    measure = function(...)
                        measurements[#measurements + 1] = { ... }
                    end,
                }
            end,
        })
        ZenSpec.unload("modules/filebrowser/patches/cover_preload")
    end)

    it("warms only the next page and reports page and preload measurements", function()
        local CoverMenu = require("covermenu")
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current-1.epub" },
                { is_file = true, path = "/current-2.epub" },
                { is_file = true, path = "/next.epub" },
                { _zen_files = { "/group-1.epub", "/group-2.epub" } },
            },
            page = 1,
            page_num = 2,
            perpage = 2,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        local iterations = 0
        while #scheduled > 0 and iterations < 10 do
            iterations = iterations + 1
            local fn = table.remove(scheduled, 1)
            fn()
        end

        assert.are.same({
            "/next.epub",
            "/group-1.epub",
            "/group-2.epub",
        }, warmed)
        assert.are.equal(2, #measurements)
        assert.are.equal("Cover page updated", measurements[1][1])
        assert.are.equal("Cover preload completed", measurements[2][1])
    end)

    it("does not compete with extraction that starts during its delay", function()
        local CoverMenu = require("covermenu")
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current.epub" },
                { is_file = true, path = "/next.epub" },
            },
            page = 1,
            page_num = 2,
            perpage = 1,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        extracting = true
        table.remove(scheduled, 1)()

        assert.are.same({}, warmed)
        assert.are.equal("Cover preload skipped", measurements[2][1])
        assert.are.equal("reason=background_extraction_after_delay", measurements[2][3])
    end)

    it("polls a visible extraction before CoverMenu's one-second interval", function()
        update_items = function(menu)
            menu.items_to_update = { { filepath = "/next.epub" } }
            menu.items_update_action = function()
                require("ui/uimanager"):setDirty(menu.show_parent, "fast")
                table.remove(menu.items_to_update, 1)
            end
        end
        local CoverMenu = require("covermenu")
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = { { is_file = true, path = "/current.epub" } },
            page = 1,
            page_num = 1,
            perpage = 1,
            display_mode_type = "mosaic",
            show_parent = {},
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        table.remove(scheduled, 1)()

        assert.are.equal(0, #menu.items_to_update)
        assert.are.equal("Cover extraction poll", measurements[2][1])
        assert.are.equal("ui", dirty[1].mode)
    end)

    it("coalesces rapid page changes before starting extraction", function()
        local launches = 0
        local UIManager = require("ui/uimanager")
        update_items = function()
            UIManager:nextTick(function()
                launches = launches + 1
            end)
        end
        local CoverMenu = require("covermenu")
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = { { is_file = true, path = "/current.epub" } },
            page = 1,
            page_num = 1,
            perpage = 1,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        CoverMenu.updateItems(menu)
        assert.are.equal(1, #scheduled)
        table.remove(scheduled, 1)()

        assert.are.equal(1, launches)
    end)

    it("keeps the active extraction and replaces stale queued pages", function()
        local BookInfoManager = require("bookinfomanager")
        local UIManager = require("ui/uimanager")
        update_items = function(menu)
            UIManager:nextTick(function()
                BookInfoManager:extractInBackground({ {
                    filepath = menu.path,
                    cover_specs = menu.cover_specs,
                } })
            end)
        end
        local CoverMenu = require("covermenu")
        require("modules/filebrowser/patches/cover_preload")()
        assert.are.equal(0.4, BookInfoManager.subprocesses_collect_interval)
        local first = {
            item_table = {}, page = 1, page_num = 1, perpage = 1,
            display_mode_type = "mosaic", path = "/first.epub",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }
        local last = {
            item_table = {}, page = 1, page_num = 1, perpage = 1,
            display_mode_type = "mosaic", path = "/last.epub",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(first)
        table.remove(scheduled, 1)()
        CoverMenu.updateItems(last)
        table.remove(scheduled, #scheduled)()

        assert.are.equal(1, #extraction_launches)
        assert.are.equal("/first.epub", extraction_launches[1][1].filepath)

        extracting = false
        table.remove(scheduled, 1)()
        assert.are.equal(2, #extraction_launches)
        assert.are.equal("/last.epub", extraction_launches[2][1].filepath)
    end)
end)

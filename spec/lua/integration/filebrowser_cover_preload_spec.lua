describe("filebrowser cover preloading", function()
    local scheduled
    local scheduled_delays
    local warmed
    local measurements
    local extracting
    local update_items
    local dirty
    local extraction_launches
    local generated
    local decoded
    local book_infos
    local render_entries
    local render_hits
    local render_misses
    local render_puts
    local render_calls
    local render_scalings
    local next_page
    local previous_page
    local mosaic_item
    local memory_pressure
    local original_memory_policy

    local function bitmap(path)
        return {
            path = path,
            free = function() end,
        }
    end

    local function render_key(path, width, height)
        return table.concat({ path, width, height }, "\31")
    end

    local function metric_value(measurement, name)
        for index = 3, #measurement - 1 do
            if measurement[index] == name then return measurement[index + 1] end
        end
    end

    before_each(function()
        scheduled = {}
        scheduled_delays = {}
        warmed = {}
        measurements = {}
        extracting = false
        update_items = function() end
        dirty = {}
        extraction_launches = {}
        generated = {}
        decoded = {}
        book_infos = {}
        render_entries = {}
        render_hits = 0
        render_misses = 0
        render_puts = 0
        render_calls = {}
        render_scalings = 0
        next_page = function() return true end
        previous_page = function() return true end
        mosaic_item = {
            update = function() end,
            paintTo = function() end,
        }
        memory_pressure = "normal"
        original_memory_policy = package.loaded["common/memory_policy"]

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
            onNextPage = function(menu, ...) return next_page(menu, ...) end,
            onPrevPage = function(menu, ...) return previous_page(menu, ...) end,
            onCloseWidget = function() end,
        })
        ZenSpec.replace("ui/widget/menu", {
            onNextPage = function(menu, ...) return next_page(menu, ...) end,
            onPrevPage = function(menu, ...) return previous_page(menu, ...) end,
        })
        ZenSpec.replace("mosaicmenu", {
            _zen_mosaic_item_class = mosaic_item,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, fn)
                fn()
            end,
            scheduleIn = function(_self, delay, fn)
                scheduled[#scheduled + 1] = fn
                scheduled_delays[#scheduled_delays + 1] = delay
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
                local configured = book_infos[path]
                if configured == false then return nil end
                if configured and configured.has_cover == false then
                    return {
                        has_cover = false,
                        title = configured.title,
                        authors = configured.authors,
                    }
                end
                return {
                    has_cover = true,
                    cover_bb = bitmap(path),
                }
            end,
        })
        ZenSpec.replace("common/cover_decode_cache", {
            has = function(_self, path) return decoded[path] == true end,
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
            get = function(_self, path, width, height)
                if render_entries[render_key(path, width, height)] then
                    render_hits = render_hits + 1
                    return bitmap(path)
                end
                render_misses = render_misses + 1
            end,
            put = function(_self, path, width, height, bb)
                render_entries[render_key(path, width, height)] = true
                render_puts = render_puts + 1
                return bb
            end,
            render = function(self, path, source, width, height)
                render_calls[#render_calls + 1] = {
                    path = path, width = width, height = height,
                }
                local cached = self:get(path, width, height)
                if source then source:free() end
                if cached then return cached end
                render_scalings = render_scalings + 1
                local final = bitmap(path)
                self:put(path, width, height, final)
                return final
            end,
            stats = function()
                return {
                    bytes = 0,
                    hits = render_hits,
                    misses = render_misses,
                    puts = render_puts,
                }
            end,
        })
        ZenSpec.replace("common/memory_policy", {
            applyCoverBudgets = function()
                return { pressure = memory_pressure }
            end,
            canPreload = function(profile)
                return profile.pressure == "normal"
            end,
        })
        ZenSpec.replace("common/cover_utils", {
            calcDims = function(width, height)
                local aspect = 2 / 3
                if height * aspect <= width then
                    return math.floor(height * aspect), height
                end
                return width, math.floor(width / aspect)
            end,
            genCover = function(path, width, height)
                local aspect = 2 / 3
                local cached_width, cached_height
                if height * aspect <= width then
                    cached_width, cached_height = math.floor(height * aspect), height
                else
                    cached_width, cached_height = width, math.floor(width / aspect)
                end
                generated[#generated + 1] = {
                    path = path, width = width, height = height,
                    cached_width = cached_width, cached_height = cached_height,
                }
                local RenderCache = require("common/cover_render_cache")
                local key = "generated:" .. path
                local cached = RenderCache:get(key, cached_width, cached_height)
                if cached then return cached end
                local final = bitmap(path)
                RenderCache:put(key, cached_width, cached_height, final)
                return final
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

    after_each(function()
        package.loaded["common/memory_policy"] = original_memory_policy
    end)

    it("warms only the next page and reports page and preload measurements", function()
        local CoverMenu = require("covermenu")
        book_infos["/group-2.epub"] = { has_cover = false, title = "Grouped" }
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
        assert.are.equal(0.08, scheduled_delays[1])
        local iterations = 0
        while #scheduled > 0 and iterations < 10 do
            iterations = iterations + 1
            local fn = table.remove(scheduled, 1)
            fn()
        end

        assert.are.equal(1, iterations)
        assert.are.same({
            "/next.epub",
            "/group-1.epub",
            "/group-2.epub",
        }, warmed)
        assert.are.equal(2, #measurements)
        assert.are.equal("Cover page updated", measurements[1][1])
        assert.are.equal("Cover preload completed", measurements[2][1])
        assert.are.equal(2, metric_value(measurements[2], "decoded_warmed="))
        assert.are.equal(1, metric_value(measurements[2], "final_render_warmed="))
        assert.are.equal(0, metric_value(measurements[2], "generated_warmed="))
        assert.are.equal(1, metric_value(measurements[2], "failed="))
        assert.are.same({
            { path = "/next.epub", width = 100, height = 150 },
        }, render_calls)
    end)

    it("does not warm covers while available memory is low", function()
        local CoverMenu = require("covermenu")
        memory_pressure = "low"
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

        assert.are.equal(0, #scheduled)
        assert.are.same({}, warmed)
        assert.are.equal("Cover preload skipped", measurements[2][1])
        assert.are.equal("reason=memory_low", measurements[2][3])
    end)

    it("turns adjacent real and generated covers into final-render hits", function()
        local CoverMenu = require("covermenu")
        local RenderCache = require("common/cover_render_cache")
        local CoverUtils = require("common/cover_utils")
        local BookInfoManager = require("bookinfomanager")
        local function set_zen_specs(active_menu)
            active_menu._zen_file_cover_specs = {
                max_cover_w = 93,
                max_cover_h = 137,
                uniform = true,
            }
        end
        update_items = set_zen_specs
        book_infos["/placeholder.epub"] = {
            has_cover = false,
            title = "Placeholder",
            authors = "Author",
        }
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current-1.epub" },
                { is_file = true, path = "/current-2.epub" },
                { is_file = true, path = "/real.epub" },
                { is_file = true, path = "/placeholder.epub" },
            },
            page = 1,
            page_num = 2,
            perpage = 2,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 93, max_cover_h = 137 },
        }

        CoverMenu.updateItems(menu)
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        local preload = measurements[2]
        assert.are.equal(1, metric_value(preload, "final_render_warmed="))
        assert.are.equal(1, metric_value(preload, "generated_warmed="))
        assert.are.same({
            {
                path = "/placeholder.epub", width = 93, height = 137,
                cached_width = 91, cached_height = 137,
            },
        }, generated)
        local scalings_after_preload = render_scalings

        update_items = function(active_menu)
            set_zen_specs(active_menu)
            if active_menu.page ~= 2 then return end
            local real = BookInfoManager:getBookInfo("/real.epub", true)
            local real_cover = RenderCache:render(
                "/real.epub", real.cover_bb,
                CoverUtils.calcDims(
                    active_menu._zen_file_cover_specs.max_cover_w,
                    active_menu._zen_file_cover_specs.max_cover_h
                )
            )
            real_cover:free()
            local placeholder = CoverUtils.genCover(
                "/placeholder.epub",
                active_menu.cover_specs.max_cover_w,
                active_menu.cover_specs.max_cover_h
            )
            placeholder:free()
        end
        menu.page = 2
        CoverMenu.updateItems(menu)

        local page_update = measurements[3]
        assert.are.equal("Cover page updated", page_update[1])
        assert.are.equal(2, metric_value(page_update, "render_cache_hits="))
        assert.are.equal(0, metric_value(page_update, "render_cache_misses="))
        assert.are.equal(scalings_after_preload, render_scalings)
    end)

    it("uses exact Zen book dimensions and warms one page ahead", function()
        local CoverMenu = require("covermenu")
        update_items = function(menu)
            menu._zen_file_cover_specs = {
                max_cover_w = 93,
                max_cover_h = 137,
                uniform = true,
            }
            -- A folder tile built later may overwrite CoverBrowser's shared specs.
            menu.cover_specs = { max_cover_w = 100, max_cover_h = 150 }
        end
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current.epub" },
                { is_file = true, path = "/next.epub" },
                { is_file = true, path = "/after-next.epub" },
            },
            page = 1,
            page_num = 3,
            perpage = 1,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        assert.are.same({ "/next.epub" }, warmed)
        assert.are.same({
            { path = "/next.epub", width = 91, height = 137 },
        }, render_calls)
        assert.are.equal(1, metric_value(measurements[2], "lookahead_pages="))
    end)

    it("matches generated-cover cache dimensions in uniform and non-uniform layouts", function()
        local CoverMenu = require("covermenu")
        local CoverUtils = require("common/cover_utils")
        require("modules/filebrowser/patches/cover_preload")()
        local cases = {
            {
                path = "/uniform-placeholder.epub",
                width = 90,
                height = 135,
                cached_width = 90,
                cached_height = 135,
            },
            {
                path = "/nonuniform-placeholder.epub",
                width = 120,
                height = 137,
                cached_width = 91,
                cached_height = 137,
            },
        }

        for case_index = 1, #cases do
            local case = cases[case_index]
            book_infos[case.path] = { has_cover = false, title = "Title", authors = "Author" }
            local menu = {
                item_table = {
                    { is_file = true, path = "/current-" .. case_index .. ".epub" },
                    { is_file = true, path = case.path },
                },
                page = 1,
                page_num = 2,
                perpage = 1,
                display_mode_type = "mosaic",
                cover_specs = { max_cover_w = case.width, max_cover_h = case.height },
            }

            CoverMenu.updateItems(menu)
            while #scheduled > 0 do table.remove(scheduled, 1)() end

            local warmed_cover = generated[#generated]
            assert.are.equal(case.width, warmed_cover.width)
            assert.are.equal(case.height, warmed_cover.height)
            assert.are.equal(case.cached_width, warmed_cover.cached_width)
            assert.are.equal(case.cached_height, warmed_cover.cached_height)
            local hits_before = render_hits
            local cover = CoverUtils.genCover(case.path, case.width, case.height)
            cover:free()
            assert.are.equal(hits_before + 1, render_hits)
        end
    end)

    it("reports cached decode and final-render outcomes independently", function()
        local CoverMenu = require("covermenu")
        local RenderCache = require("common/cover_render_cache")
        decoded["/next.epub"] = true
        RenderCache:put("/next.epub", 100, 150, bitmap("/next.epub"))
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
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        assert.are.equal(1, metric_value(measurements[2], "decoded_cached="))
        assert.are.equal(1, metric_value(measurements[2], "final_render_cached="))
        assert.are.equal(0, metric_value(measurements[2], "final_render_warmed="))
    end)

    it("measures page-turn input through update and the last painted tile", function()
        local CoverMenu = require("covermenu")
        local Menu = require("ui/widget/menu")
        next_page = function(menu)
            menu.page = menu.page + 1
            return CoverMenu.updateItems(menu)
        end
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

        Menu.onNextPage(menu)
        mosaic_item.paintTo({ menu = menu }, {}, 0, 0)

        assert.are.equal("Cover page updated", measurements[1][1])
        assert.are.equal("next", metric_value(measurements[1], "page_turn_direction="))
        assert.is_true(metric_value(measurements[1], "input_to_update_ms=") > 0)
        assert.are.equal("Cover page painted", measurements[2][1])
        assert.are.equal("next", metric_value(measurements[2], "page_turn_direction="))
        assert.is_true(metric_value(measurements[2], "input_to_last_tile_ms=") > 0)
    end)

    it("measures FileChooser's concrete page-turn handler", function()
        local CoverMenu = require("covermenu")
        local FileChooser = require("ui/widget/filechooser")
        next_page = function(menu)
            menu.page = menu.page + 1
            return CoverMenu.updateItems(menu)
        end
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

        FileChooser.onNextPage(menu)

        assert.are.equal("next", metric_value(measurements[1], "page_turn_direction="))
        assert.is_true(metric_value(measurements[1], "input_to_update_ms=") > 0)
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

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
    local goto_page
    local mosaic_item
    local memory_pressure
    local folder_cover_mode
    local folder_preview_entries
    local folder_preview_limits
    local gallery_warms
    local preload_order
    local decode_drops
    local render_drops
    local db_closes
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
        goto_page = function(menu, page)
            menu.page = page
            return true
        end
        mosaic_item = {
            update = function() end,
            paintTo = function() end,
        }
        memory_pressure = "normal"
        folder_cover_mode = "normal"
        folder_preview_entries = {}
        folder_preview_limits = {}
        gallery_warms = {}
        preload_order = {}
        decode_drops = {}
        render_drops = {}
        db_closes = 0
        original_memory_policy = package.loaded["common/memory_policy"]

        ZenSpec.replace("covermenu", {
            updateItems = function(menu, ...)
                return update_items(menu, ...)
            end,
            onCloseWidget = function() end,
            onGotoPage = function(menu, page, ...) return goto_page(menu, page, ...) end,
        })
        ZenSpec.replace("ui/widget/filechooser", {
            updateItems = function(menu, ...)
                return update_items(menu, ...)
            end,
            onNextPage = function(menu, ...) return next_page(menu, ...) end,
            onPrevPage = function(menu, ...) return previous_page(menu, ...) end,
            onGotoPage = function(menu, page, ...) return goto_page(menu, page, ...) end,
            onCloseWidget = function() end,
        })
        ZenSpec.replace("ui/widget/menu", {
            onNextPage = function(menu, ...) return next_page(menu, ...) end,
            onPrevPage = function(menu, ...) return previous_page(menu, ...) end,
            onGotoPage = function(menu, page, ...) return goto_page(menu, page, ...) end,
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
            setDirty = function(_self, widget, mode, region, dither)
                if type(mode) == "function" then
                    mode, region, dither = mode()
                end
                dirty[#dirty + 1] = {
                    widget = widget, mode = mode, region = region, dither = dither,
                }
            end,
        })
        local geometry = {}
        geometry.__index = geometry
        function geometry:combine(other)
            local x = math.min(self.x, other.x)
            local y = math.min(self.y, other.y)
            local right = math.max(self.x + self.w, other.x + other.w)
            local bottom = math.max(self.y + self.h, other.y + other.h)
            return setmetatable({ x = x, y = y, w = right - x, h = bottom - y }, geometry)
        end
        ZenSpec.replace("ui/geometry", {
            new = function(_self, values) return setmetatable(values, geometry) end,
        })
        ZenSpec.replace("common/ui/background", {
            library_active = function() return false end,
        })
        ZenSpec.replace("bookinfomanager", {
            subprocesses_collect_interval = 10,
            getSetting = function() return false end,
            isExtractingInBackground = function() return extracting end,
            extractInBackground = function(_self, files)
                extraction_launches[#extraction_launches + 1] = files
                extracting = true
                return true
            end,
            terminateBackgroundJobs = function() end,
            closeDbConnection = function() db_closes = db_closes + 1 end,
            getBookInfo = function(_self, path)
                warmed[#warmed + 1] = path
                preload_order[#preload_order + 1] = "cover:" .. path
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
                    cover_w = configured and configured.cover_w,
                    cover_h = configured and configured.cover_h,
                }
            end,
        })
        ZenSpec.replace("common/cover_decode_cache", {
            has = function(_self, path) return decoded[path] == true end,
            drop = function(_self, path) decode_drops[#decode_drops + 1] = path end,
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
            drop = function(_self, path) render_drops[#render_drops + 1] = path end,
            hasExact = function(_self, path, width, height)
                return render_entries[render_key(path, width, height)] == true
            end,
            get = function(_self, path, width, height)
                if render_entries[render_key(path, width, height)] then
                    render_hits = render_hits + 1
                    return bitmap(path)
                end
                render_misses = render_misses + 1
            end,
            getShared = function(_self, path, width, height)
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
            putShared = function(_self, path, width, height, bb)
                render_entries[render_key(path, width, height)] = true
                render_puts = render_puts + 1
                return bb, true
            end,
            releaseShared = function() return true end,
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
            renderShared = function(self, path, source, width, height)
                render_calls[#render_calls + 1] = {
                    path = path, width = width, height = height,
                }
                local cached = self:getShared(path, width, height)
                if source then source:free() end
                if cached then return cached, true end
                render_scalings = render_scalings + 1
                local final = bitmap(path)
                return self:putShared(path, width, height, final)
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
            getMode = function()
                if folder_cover_mode == "normal" then return "normal", 1, false end
                return folder_cover_mode, 4, true
            end,
            calcDims = function(width, height)
                local aspect = 2 / 3
                if height * aspect <= width then
                    return math.floor(height * aspect), height
                end
                return width, math.floor(width / aspect)
            end,
            getFolderPreviewBounds = function(mode, width, height, cover_count, slot)
                local aspect = 2 / 3
                local function calc(max_w, max_h)
                    if max_h * aspect <= max_w then
                        return math.floor(max_h * aspect), max_h
                    end
                    return max_w, math.floor(max_w / aspect)
                end
                local portrait_w, portrait_h = calc(width, height)
                if mode == "gallery" then
                    local left_w = math.floor((portrait_w - 1) / 2)
                    local top_h = math.floor((portrait_h - 1) / 2)
                    local cell_w = (slot == 2 or slot == 4)
                        and portrait_w - 1 - left_w or left_w
                    local cell_h = slot > 2 and portrait_h - 1 - top_h or top_h
                    return math.max(1, cell_w), math.max(1, cell_h)
                end
                if mode == "stack" and cover_count > 1 then
                    local book_w = math.max(1, math.floor(portrait_w * 0.72))
                    local book_h = math.max(1, math.floor(book_w * portrait_h / portrait_w))
                    return book_w, book_h
                end
                return portrait_w, portrait_h
            end,
            fitDims = function(max_w, max_h, source_w, source_h)
                local scale = math.min(max_w / source_w, max_h / source_h)
                return math.floor(source_w * scale + 0.5),
                    math.floor(source_h * scale + 0.5)
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
            genCoverShared = function(path, width, height)
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
                local cached = RenderCache:getShared(key, cached_width, cached_height)
                if cached then
                    return cached, cached_width, cached_height, true, key
                end
                local final = bitmap(path)
                local stored, owned = RenderCache:putShared(
                    key, cached_width, cached_height, final)
                return stored, cached_width, cached_height, owned, key
            end,
        })
        ZenSpec.replace("modules/filebrowser/folder_cover", {
            isSupported = function(entry, menu)
                return entry and (entry._zen_files or entry.series_items
                    or entry.is_directory == true or entry.mode == "directory"
                    or (entry.attr and entry.attr.mode == "directory")
                    or (menu and menu._zen_coll_list and entry.name)) and true or false
            end,
            previewEntries = function(menu, entry, limit)
                folder_preview_limits[#folder_preview_limits + 1] = limit
                local values = folder_preview_entries[entry.path]
                    or entry._zen_files or entry.series_items
                if not values and menu and menu._zen_coll_list and entry.name
                        and type(menu._zen_get_collection_files) == "function" then
                    values = menu._zen_get_collection_files(entry.name)
                end
                local entries = {}
                for index = 1, math.min(limit, #(values or {})) do
                    local value = values[index]
                    entries[index] = type(value) == "table" and value
                        or { is_file = true, path = value }
                end
                return entries
            end,
            warmGallery = function(menu, entry, menu_text, width, height, options)
                preload_order[#preload_order + 1] = "gallery:" .. tostring(entry.path)
                gallery_warms[#gallery_warms + 1] = {
                    menu = menu,
                    entry = entry,
                    menu_text = menu_text,
                    width = width,
                    height = height,
                    options = options,
                }
                return true, false
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
        ZenSpec.replace("dbg", { is_on = true })
        ZenSpec.unload("modules/filebrowser/patches/cover_preload")
    end)

    after_each(function()
        package.loaded["common/memory_policy"] = original_memory_policy
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
        assert.are.equal(0.35, scheduled_delays[1])
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
        }, warmed)
        assert.are.same({ 1 }, folder_preview_limits)
        assert.are.equal(2, #measurements)
        assert.are.equal("Cover page updated", measurements[1][1])
        assert.are.equal("Cover preload completed", measurements[2][1])
        assert.are.equal(2, metric_value(measurements[2], "decoded_warmed="))
        assert.are.equal(2, metric_value(measurements[2], "final_render_warmed="))
        assert.are.equal(0, metric_value(measurements[2], "generated_warmed="))
        assert.are.equal(0, metric_value(measurements[2], "failed="))
        assert.are.same({
            { path = "/next.epub", width = 100, height = 150 },
            { path = "/group-1.epub", width = 100, height = 150 },
        }, render_calls)
    end)

    it("preloads one physical-folder candidate for single-cover mode", function()
        local CoverMenu = require("covermenu")
        folder_preview_entries["/folder"] = {
            "/folder/first.epub", "/folder/second.epub",
            "/folder/third.epub", "/folder/fourth.epub",
        }
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current.epub" },
                { path = "/folder", attr = { mode = "directory" } },
            },
            page = 1, page_num = 2, perpage = 1,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        assert.are.same({ "/folder/first.epub" }, warmed)
        assert.are.same({ 1 }, folder_preview_limits)
        assert.are.same({
            { path = "/folder/first.epub", width = 100, height = 150 },
        }, render_calls)
    end)

    it("pre-renders one gallery bitmap instead of warming four child jobs", function()
        local CoverMenu = require("covermenu")
        folder_cover_mode = "gallery"
        folder_preview_entries["/folder"] = {
            "/folder/first.epub", "/folder/second.epub",
            "/folder/third.epub", "/folder/fourth.epub",
        }
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current.epub" },
                { path = "/folder", attr = { mode = "directory" } },
            },
            page = 1, page_num = 2, perpage = 1,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        assert.are.same({}, warmed)
        assert.are.same({ 4 }, folder_preview_limits)
        assert.are.same({}, render_calls)
        assert.are.equal(1, #gallery_warms)
        assert.are.equal(1, metric_value(measurements[#measurements], "cover_jobs="))
        assert.are.equal(1, metric_value(measurements[#measurements], "warmed="))
        assert.are.equal(1, metric_value(measurements[#measurements], "gallery_warmed="))
    end)

    it("warms ordinary page covers before prioritizing gallery composites", function()
        local CoverMenu = require("covermenu")
        folder_cover_mode = "gallery"
        folder_preview_entries["/folder"] = {
            "/folder/first.epub", "/folder/second.epub",
        }
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current-1.epub" },
                { is_file = true, path = "/current-2.epub" },
                { path = "/folder", attr = { mode = "directory" } },
                { is_file = true, path = "/next.epub" },
            },
            page = 1, page_num = 2, perpage = 2,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        assert.are.same({ "cover:/next.epub", "gallery:/folder" }, preload_order)
    end)

    it("delegates generated gallery covers to the composite warmer", function()
        local CoverMenu = require("covermenu")
        folder_cover_mode = "gallery"
        folder_preview_entries["/folder"] = {
            "/folder/first.epub", "/folder/second.epub",
            "/folder/third.epub", "/folder/fourth.epub",
        }
        for _i, path in ipairs(folder_preview_entries["/folder"]) do
            book_infos[path] = { has_cover = false, title = path, authors = "Author" }
        end
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current.epub" },
                { path = "/folder", attr = { mode = "directory" } },
            },
            page = 1, page_num = 2, perpage = 1,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        assert.are.same({}, generated)
        assert.are.equal(0, metric_value(measurements[#measurements], "generated_warmed="))
        assert.are.equal(1, metric_value(measurements[#measurements], "gallery_warmed="))
        assert.are.equal(0, metric_value(measurements[#measurements], "failed="))
    end)

    it("preloads every cover source required by a gallery page", function()
        local CoverMenu = require("covermenu")
        folder_cover_mode = "gallery"
        local items = {}
        for index = 1, 7 do
            items[#items + 1] = { is_file = true, path = "/current-" .. index .. ".epub" }
        end
        for folder_index = 1, 7 do
            local path = "/folder-" .. folder_index
            local entries = {}
            for cover_index = 1, 4 do
                entries[cover_index] = path .. "/book-" .. cover_index .. ".epub"
            end
            folder_preview_entries[path] = entries
            items[#items + 1] = { path = path, attr = { mode = "directory" } }
        end
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = items,
            page = 1, page_num = 2, perpage = 7,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        assert.are.equal(0, #warmed)
        assert.are.equal(7, #folder_preview_limits)
        for _i, limit in ipairs(folder_preview_limits) do
            assert.are.equal(4, limit)
        end
        assert.are.equal(7, #gallery_warms)
        assert.are.equal(7, metric_value(measurements[#measurements], "cover_jobs="))
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

    it("warms non-uniform real covers at their natural aspect ratio", function()
        local CoverMenu = require("covermenu")
        update_items = function(menu)
            menu._zen_file_cover_specs = {
                max_cover_w = 100,
                max_cover_h = 150,
                uniform = false,
            }
        end
        book_infos["/landscape.epub"] = { cover_w = 120, cover_h = 80 }
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/current.epub" },
                { is_file = true, path = "/landscape.epub" },
            },
            page = 1,
            page_num = 2,
            perpage = 1,
            display_mode_type = "mosaic",
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        while #scheduled > 0 do table.remove(scheduled, 1)() end

        assert.are.same({
            { path = "/landscape.epub", width = 100, height = 67 },
        }, render_calls)
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

        assert.are.equal(0, metric_value(measurements[2], "decoded_cached="))
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

    it("tracks direct page jumps and scopes full-page mosaic refreshes", function()
        local CoverMenu = require("covermenu")
        local Menu = require("ui/widget/menu")
        local UIManager = require("ui/uimanager")
        goto_page = function(menu, page)
            menu.page = page
            return CoverMenu.updateItems(menu)
        end
        update_items = function(menu)
            UIManager:setDirty(menu.show_parent, function()
                return "ui", menu.dimen, true
            end)
        end
        require("modules/filebrowser/patches/cover_preload")()
        local parent = {}
        local menu = {
            item_table = {
                { is_file = true, path = "/one.epub" },
                { is_file = true, path = "/two.epub" },
            },
            page = 1,
            page_num = 2,
            perpage = 1,
            display_mode_type = "mosaic",
            show_parent = parent,
            dimen = { x = 0, y = 0, w = 600, h = 800 },
            title_bar = { dimen = { h = 50 } },
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        Menu.onGotoPage(menu, 2)

        assert.are.equal("jump_forward",
            metric_value(measurements[1], "page_turn_direction="))
        assert.are.equal("ui", dirty[1].mode)
        assert.are.same({ x = 0, y = 50, w = 600, h = 750 }, dirty[1].region)
        assert.is_true(dirty[1].dither)
        assert.are.equal(93.8, metric_value(measurements[1], "refresh_region_pct="))
    end)

    it("hydrates only the current page without waiting for unrelated extraction", function()
        local CoverMenu = require("covermenu")
        local Geom = require("ui/geometry")
        local hydrated_pages = {}
        update_items = function(menu)
            local item = {
                menu = menu,
                [1] = { dimen = Geom:new{
                    x = 20, y = menu.page * 100, w = 200, h = 90,
                } },
            }
            item.update = function(self)
                assert.is_true(self._zen_cover_hydrating)
                hydrated_pages[#hydrated_pages + 1] = self.menu.page
                self._has_cover_image = true
            end
            item._zen_cover_hydration_queued = true
            menu._zen_cover_hydration_items[#menu._zen_cover_hydration_items + 1] = item
            menu:_zen_request_cover_hydration()
        end
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = {
                { is_file = true, path = "/one.epub" },
                { is_file = true, path = "/two.epub" },
            },
            page = 1,
            page_num = 2,
            perpage = 1,
            nb_cols = 1,
            display_mode_type = "mosaic",
            show_parent = {},
            no_refresh_covers = true,
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        menu.page = 2
        CoverMenu.updateItems(menu)

        assert.are.equal(1, #scheduled)
        assert.are.equal(0.05, scheduled_delays[#scheduled_delays])
        extracting = true
        table.remove(scheduled, 1)()

        assert.are.same({ 2 }, hydrated_pages)
        assert.are.equal(0, #scheduled)
        assert.are.same({ x = 20, y = 200, w = 200, h = 90 }, dirty[1].region)
        assert.is_true(dirty[1].dither)
        assert.are.equal("Cover hydration completed", measurements[#measurements][1])
        assert.are.equal(1, metric_value(measurements[#measurements], "hydrated="))
    end)

    it("hydrates at most one cold folder per scheduled tick", function()
        local CoverMenu = require("covermenu")
        local Geom = require("ui/geometry")
        local hydrated = {}
        update_items = function(menu)
            for index = 1, 2 do
                local item = {
                    menu = menu,
                    _zen_cover_hydration_queued = true,
                    _zen_cover_hydration_kind = "folder",
                    [1] = { dimen = Geom:new{
                        x = index * 100, y = 100, w = 90, h = 120,
                    } },
                }
                item.update = function(self)
                    assert.is_true(self._zen_folder_hydrating)
                    hydrated[#hydrated + 1] = index
                    self._has_cover_image = true
                end
                menu._zen_cover_hydration_items[#menu._zen_cover_hydration_items + 1] = item
            end
            menu:_zen_request_cover_hydration()
        end
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = { { path = "/folder", attr = { mode = "directory" } } },
            page = 1, page_num = 1, perpage = 1, nb_cols = 2,
            display_mode_type = "mosaic", show_parent = {},
            no_refresh_covers = true,
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        assert.are.equal(1, #scheduled)

        table.remove(scheduled, 1)()
        assert.are.same({ 1 }, hydrated)
        assert.are.equal(1, #scheduled)
        assert.are.equal(0.05, scheduled_delays[#scheduled_delays])
        assert.are.same({ x = 100, y = 100, w = 90, h = 120 }, dirty[1].region)

        table.remove(scheduled, 1)()
        assert.are.same({ 1, 2 }, hydrated)
        assert.are.same({ x = 200, y = 100, w = 90, h = 120 }, dirty[2].region)
        assert.are.equal(2, metric_value(measurements[#measurements], "chunks="))
    end)

    it("bounds ordinary cover hydration across scheduled ticks", function()
        local CoverMenu = require("covermenu")
        local Geom = require("ui/geometry")
        local hydrated = {}
        update_items = function(menu)
            for index = 1, 5 do
                local item = {
                    menu = menu,
                    _zen_cover_hydration_queued = true,
                    [1] = { dimen = Geom:new{
                        x = index * 20, y = 100, w = 18, h = 120,
                    } },
                }
                item.update = function(self)
                    assert.is_true(self._zen_cover_hydrating)
                    hydrated[#hydrated + 1] = index
                    self._has_cover_image = true
                end
                menu._zen_cover_hydration_items[#menu._zen_cover_hydration_items + 1] = item
            end
            menu:_zen_request_cover_hydration()
        end
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = { { is_file = true, path = "/book.epub" } },
            page = 1, page_num = 1, perpage = 1, nb_cols = 2,
            display_mode_type = "mosaic", show_parent = {},
            no_refresh_covers = true,
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        assert.are.equal(1, #scheduled)

        table.remove(scheduled, 1)()
        assert.are.same({ 1, 2, 3, 4 }, hydrated)
        assert.are.equal(1, #scheduled)
        assert.are.equal(0.05, scheduled_delays[#scheduled_delays])

        table.remove(scheduled, 1)()
        assert.are.same({ 1, 2, 3, 4, 5 }, hydrated)
        assert.are.equal(2, metric_value(measurements[#measurements], "chunks="))
    end)

    it("cancels cover work while FileManager is hidden under startup Home", function()
        local CoverMenu = require("covermenu")
        update_items = function(menu)
            local item = {
                menu = menu,
                _zen_cover_hydration_queued = true,
                update = function() error("hidden hydration ran") end,
            }
            menu._zen_cover_hydration_items[1] = item
            menu:_zen_request_cover_hydration()
        end
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            _zen_hidden_home_startup = true,
            item_table = { { is_file = true, path = "/book.epub" } },
            page = 1, page_num = 2, perpage = 1,
            display_mode_type = "mosaic", show_parent = {},
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)

        assert.are.same({}, scheduled)
        assert.are.same({}, menu._zen_cover_hydration_items)
        assert.are.equal("Cover preload skipped", measurements[#measurements][1])
        assert.are.equal("reason=hidden_home_startup", measurements[#measurements][3])
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

    it("keeps polling the current page briefly after extraction stops", function()
        local polls = 0
        update_items = function(menu)
            menu.items_to_update = { { filepath = "/next.epub" } }
            menu.items_update_action = function()
                polls = polls + 1
                if polls == 2 then table.remove(menu.items_to_update, 1) end
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

        assert.are.equal(1, polls)
        assert.are.equal(1, #menu.items_to_update)
        assert.are.equal(menu.items_update_action, menu._zen_cover_poll_action)
        assert.are.equal(1, #scheduled)

        table.remove(scheduled, 1)()

        assert.are.equal(2, polls)
        assert.are.equal(0, #menu.items_to_update)
        assert.is_nil(menu._zen_cover_poll_action)
    end)

    it("reconciles completed extraction before polling the final page", function()
        local BookInfoManager = require("bookinfomanager")
        local CoverMenu = require("covermenu")
        local UIManager = require("ui/uimanager")
        update_items = function(menu)
            local item = { filepath = "/final.epub" }
            menu.items_to_update = { item }
            UIManager:nextTick(function()
                BookInfoManager:extractInBackground({ {
                    filepath = item.filepath,
                    cover_specs = menu.cover_specs,
                } })
            end)
            menu.items_update_action = function()
                assert.are.same({ item.filepath }, decode_drops)
                assert.are.same({ item.filepath }, render_drops)
                assert.are.equal(1, db_closes)
                table.remove(menu.items_to_update, 1)
                UIManager:setDirty(menu.show_parent, "ui")
            end
        end
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = { { is_file = true, path = "/final.epub" } },
            page = 1,
            page_num = 1,
            perpage = 1,
            display_mode_type = "mosaic",
            show_parent = {},
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        assert.are.same({ 0.15, 0.4 }, scheduled_delays)
        table.remove(scheduled, 1)()
        assert.are.equal(1, #extraction_launches)

        extracting = false
        table.remove(scheduled, 1)()

        assert.are.equal(0, #menu.items_to_update)
        assert.is_nil(menu._zen_cover_poll_action)
        assert.are.equal("ui", dirty[1].mode)
        table.remove(scheduled, 1)()
        assert.are.equal(0, #scheduled)
    end)

    it("stops polling a permanently unresolved page after the settle limit", function()
        local polls = 0
        update_items = function(menu)
            menu.items_to_update = { { filepath = "/missing.epub" } }
            menu.items_update_action = function() polls = polls + 1 end
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
        while #scheduled > 0 and polls < 20 do table.remove(scheduled, 1)() end

        assert.are.equal(5, polls)
        assert.are.equal(1, #menu.items_to_update)
        assert.is_nil(menu._zen_cover_poll_action)
        assert.are.equal("Cover extraction poll stopped", measurements[#measurements][1])
        assert.are.equal("reason=settle_timeout", measurements[#measurements][3])
    end)

    it("replaces superseded extraction polls without letting stale callbacks interfere", function()
        local raw_actions = {}
        local polled_pages = {}
        update_items = function(menu)
            local page = menu.page
            menu.items_to_update = { { filepath = "/page-" .. page .. ".epub" } }
            local action = function()
                polled_pages[#polled_pages + 1] = page
                table.remove(menu.items_to_update, 1)
            end
            raw_actions[#raw_actions + 1] = action
            menu.items_update_action = action
        end
        local CoverMenu = require("covermenu")
        require("modules/filebrowser/patches/cover_preload")()
        local menu = {
            item_table = { { is_file = true, path = "/current.epub" } },
            page = 1,
            page_num = 2,
            perpage = 1,
            display_mode_type = "mosaic",
            show_parent = {},
            cover_specs = { max_cover_w = 100, max_cover_h = 150 },
        }

        CoverMenu.updateItems(menu)
        local stale_poll = menu.items_update_action
        menu.page = 2
        CoverMenu.updateItems(menu)
        local current_poll = menu.items_update_action

        assert.are_not.equal(stale_poll, current_poll)
        assert.are_not.equal(raw_actions[2], current_poll)
        assert.are.equal(current_poll, menu._zen_cover_poll_action)
        assert.are.equal(1, #scheduled)

        stale_poll()
        assert.are.same({}, polled_pages)
        assert.are.equal(current_poll, menu._zen_cover_poll_action)
        assert.are.equal(1, #menu.items_to_update)

        current_poll()
        assert.are.same({ 2 }, polled_pages)
        assert.are.equal(0, #menu.items_to_update)
        assert.is_nil(menu._zen_cover_poll_action)
        assert.are.equal(raw_actions[2], menu.items_update_action)
    end)

    it("cancels the active extraction poll when the menu closes", function()
        update_items = function(menu)
            menu.items_to_update = { { filepath = "/next.epub" } }
            menu.items_update_action = function() end
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
        local original = menu._zen_cover_poll_original
        CoverMenu.onCloseWidget(menu)

        assert.are.same({}, scheduled)
        assert.is_nil(menu._zen_cover_poll_action)
        assert.is_nil(menu._zen_cover_poll_generation)
        assert.are.equal(original, menu.items_update_action)
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

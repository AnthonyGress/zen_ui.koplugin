-- Measure cover-page work and warm the adjacent page in bounded idle chunks.
local function apply_cover_preload()
    local CoverMenu = require("covermenu")
    if CoverMenu.__zen_cover_preload_patched then return end
    CoverMenu.__zen_cover_preload_patched = true

    local BookInfoManager = require("bookinfomanager")
    local FileChooser = require("ui/widget/filechooser")
    local Menu = require("ui/widget/menu")
    local UIManager = require("ui/uimanager")
    local cache = require("common/cover_decode_cache")
    local render_cache = require("common/cover_render_cache")
    local zen_logger = require("common/zen_logger")
    local logger = zen_logger.new("cover_preload")
    local now = zen_logger.now

    local PRELOAD_DELAY_S = 0.35
    local PRELOAD_TICK_S = 0.05
    local PRELOAD_CHUNK = 2
    local PRELOAD_BUDGET_S = 0.03
    local PRELOAD_MAX_JOBS = 24
    local COVER_POLL_S = 0.4
    local EXTRACTION_DEBOUNCE_S = 0.15

    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then return nil end
        for index = 1, 128 do
            local upvalue_name, value = debug.getupvalue(fn, index)
            if not upvalue_name then break end
            if upvalue_name == name then return value end
        end
    end

    -- Keep page-build and tile-paint timing separate: page updates include the
    -- former, while e-ink refresh traces make the latter visible to the user.
    local function install_tile_measurements()
        local ok, MosaicMenu = pcall(require, "mosaicmenu")
        if not ok then return end
        local stock_item = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        local zen_item = MosaicMenu._zen_mosaic_item_class
        local function patch_item(MosaicMenuItem)
            if not MosaicMenuItem or MosaicMenuItem._zen_cover_measure_patched then return end
            MosaicMenuItem._zen_cover_measure_patched = true

            local original_update = MosaicMenuItem.update
            function MosaicMenuItem:update(...)
                local measure = self.menu and self.menu._zen_cover_build_measure
                if not measure then return original_update(self, ...) end
                local started_at = now()
                local result = original_update(self, ...)
                measure.tile_count = measure.tile_count + 1
                measure.tile_ms = measure.tile_ms + (now() - started_at) * 1000
                return result
            end

            local original_paintTo = MosaicMenuItem.paintTo
            function MosaicMenuItem:paintTo(bb, x, y)
                local measure = self.menu and self.menu._zen_cover_paint_measure
                if not measure then return original_paintTo(self, bb, x, y) end
                local started_at = now()
                local result = original_paintTo(self, bb, x, y)
                measure.tile_count = measure.tile_count + 1
                measure.tile_ms = measure.tile_ms + (now() - started_at) * 1000
                if not measure.logged and measure.tile_count >= measure.expected then
                    measure.logged = true
                    logger.measure("Cover page painted", measure.tile_ms,
                        "page=", measure.page,
                        "tiles=", measure.tile_count,
                        "wall_ms=", math.floor((now() - measure.started_at) * 1000 + 0.5))
                end
                return result
            end
        end
        patch_item(stock_item)
        patch_item(zen_item)
    end

    install_tile_measurements()

    local function delta(after, before, key)
        return (after[key] or 0) - (before[key] or 0)
    end

    local function is_extracting()
        return type(BookInfoManager.isExtractingInBackground) == "function"
            and BookInfoManager:isExtractingInBackground()
    end

    -- CoverBrowser kills its active subprocess whenever a new page requests
    -- covers. Keep the active batch intact and retain only the newest pending
    -- page, so fast paging cannot turn normal navigation into failed attempts.
    local function serialize_extraction()
        if BookInfoManager.__zen_cover_extraction_queue_patched
                or type(BookInfoManager.extractInBackground) ~= "function" then
            return
        end
        BookInfoManager.__zen_cover_extraction_queue_patched = true
        local original_extract = BookInfoManager.extractInBackground
        local original_terminate = BookInfoManager.terminateBackgroundJobs
        if type(BookInfoManager.subprocesses_collect_interval) == "number" then
            BookInfoManager.subprocesses_collect_interval = math.min(
                BookInfoManager.subprocesses_collect_interval,
                COVER_POLL_S
            )
        end

        local function copy_files(files)
            local copied = {}
            for index = 1, #(files or {}) do
                local item = files[index]
                if item and item.filepath then
                    copied[#copied + 1] = {
                        filepath = item.filepath,
                        cover_specs = item.cover_specs,
                    }
                end
            end
            return copied
        end

        local function watch_queue()
            if BookInfoManager._zen_cover_extract_watch then return end
            local watch
            watch = function()
                if BookInfoManager._zen_cover_extract_watch ~= watch then return end
                if is_extracting() then
                    UIManager:scheduleIn(COVER_POLL_S, watch)
                    return
                end
                BookInfoManager._zen_cover_extract_watch = nil
                local pending = BookInfoManager._zen_cover_extract_pending
                BookInfoManager._zen_cover_extract_pending = nil
                if not pending then return end
                logger.measure("Cover extraction dequeued", 0,
                    "files=", #pending)
                local launched = original_extract(BookInfoManager, pending)
                if launched then watch_queue() end
            end
            BookInfoManager._zen_cover_extract_watch = watch
            UIManager:scheduleIn(COVER_POLL_S, watch)
        end

        function BookInfoManager:extractInBackground(files, ...)
            local copied = copy_files(files)
            if #copied == 0 then return original_extract(self, files, ...) end
            if is_extracting() then
                self._zen_cover_extract_pending = copied
                logger.measure("Cover extraction queued", 0,
                    "files=", #copied,
                    "replaces_pending=", 1)
                watch_queue()
                return true
            end
            local launched = original_extract(self, copied, ...)
            if launched then watch_queue() end
            return launched
        end

        if type(original_terminate) == "function" then
            function BookInfoManager:terminateBackgroundJobs(...)
                self._zen_cover_extract_pending = nil
                return original_terminate(self, ...)
            end
        end
    end

    serialize_extraction()

    local function cancel(menu)
        if menu._zen_cover_preload_fn then
            UIManager:unschedule(menu._zen_cover_preload_fn)
            menu._zen_cover_preload_fn = nil
        end
        menu._zen_cover_preload_jobs = nil
    end

    -- CoverBrowser starts its extraction from nextTick and kills any existing
    -- batch first. A swipe through several pages therefore used to kill each
    -- batch before it could finish. Delay only that launch callback, coalescing
    -- rapid page changes into one batch for the page where the user stops.
    local function defer_extraction_launch(menu, original, ...)
        local original_nextTick = UIManager.nextTick
        UIManager.nextTick = function(ui, fn, ...)
            local args = { ... }
            return original_nextTick(ui, function()
                local queued_at = now()
                if menu._zen_cover_extract_delay_fn then
                    UIManager:unschedule(menu._zen_cover_extract_delay_fn)
                end
                local delayed
                delayed = function()
                    if menu._zen_cover_extract_delay_fn ~= delayed then return end
                    menu._zen_cover_extract_delay_fn = nil
                    logger.measure("Cover extraction launched", 0,
                        "page=", menu.page,
                        "debounce_ms=", math.floor((now() - queued_at) * 1000 + 0.5))
                    fn(unpack(args))
                end
                menu._zen_cover_extract_delay_fn = delayed
                UIManager:scheduleIn(EXTRACTION_DEBOUNCE_S, delayed)
            end, ...)
        end
        local result = original(menu, ...)
        UIManager.nextTick = original_nextTick
        return result
    end

    -- CoverMenu only checks its extraction batch once a second. Polling at the
    -- same initial cadence as Bookshelf makes each committed cover visible
    -- promptly, without changing extraction order or adding a second process.
    local function accelerate_cover_poll(menu)
        local original = menu.items_update_action
        if type(original) ~= "function" or menu._zen_cover_poll_action then return end

        UIManager:unschedule(original)
        local poll
        poll = function()
            if menu.items_update_action ~= poll then return end
            local before = #(menu.items_to_update or {})
            local started_at = now()
            local original_setDirty = UIManager.setDirty
            local held_paint = false
            UIManager.setDirty = function(ui, widget, ...)
                if widget == menu.show_parent then
                    held_paint = true
                    return
                end
                return original_setDirty(ui, widget, ...)
            end
            original()
            UIManager.setDirty = original_setDirty
            local remaining = #(menu.items_to_update or {})
            UIManager:unschedule(poll)
            if before ~= remaining then
                logger.measure("Cover extraction poll", (now() - started_at) * 1000,
                    "page=", menu.page,
                    "updated=", before - remaining,
                    "remaining=", remaining)
            end
            if held_paint then menu._zen_cover_pending_refresh = true end
            local still_extracting = is_extracting()
            if menu._zen_cover_pending_refresh and (remaining == 0 or not still_extracting) then
                menu._zen_cover_pending_refresh = nil
                original_setDirty(UIManager, menu.show_parent, "ui")
            end
            if menu.items_update_action == poll and remaining > 0 and still_extracting then
                UIManager:scheduleIn(COVER_POLL_S, poll)
            else
                menu._zen_cover_poll_action = nil
            end
        end
        menu._zen_cover_poll_action = poll
        menu.items_update_action = poll
        UIManager:scheduleIn(COVER_POLL_S, poll)
    end

    local function add_path(jobs, seen, path, already)
        if not path or path == "" or seen[path] or #jobs >= PRELOAD_MAX_JOBS then
            return already
        end
        seen[path] = true
        if cache:has(path) then return already + 1 end
        jobs[#jobs + 1] = path
        return already
    end

    local function collect_jobs(menu, direction)
        local items = menu.item_table
        local perpage = tonumber(menu.perpage)
        local page = tonumber(menu.page)
        if type(items) ~= "table" or not perpage or perpage < 1 or not page then
            return {}, 0, nil
        end
        local page_count = tonumber(menu.page_num) or math.max(1, math.ceil(#items / perpage))
        local target_page = page + direction
        if target_page < 1 or target_page > page_count then return {}, 0, nil end

        local jobs = {}
        local seen = {}
        local already = 0
        local first = (target_page - 1) * perpage + 1
        local last = math.min(#items, first + perpage - 1)
        for index = first, last do
            local item = items[index]
            if type(item) == "table" then
                local is_file = item.is_file or item.file
                    or (item.attr and item.attr.mode == "file")
                if is_file then
                    already = add_path(jobs, seen, item.path or item.file, already)
                end
                local grouped = item._zen_files or item.series_items
                if type(grouped) == "table" then
                    for grouped_index = 1, math.min(4, #grouped) do
                        local grouped_item = grouped[grouped_index]
                        local path = type(grouped_item) == "table"
                            and (grouped_item.path or grouped_item.file) or grouped_item
                        already = add_path(jobs, seen, path, already)
                    end
                end
            end
            if #jobs >= PRELOAD_MAX_JOBS then break end
        end
        return jobs, already, target_page
    end

    local function schedule(menu)
        cancel(menu)
        if menu.no_refresh_covers == true or menu.cover_specs == false
                or menu._do_cover_images == false then
            return
        end
        local direction = menu._zen_cover_preload_direction or 1
        menu._zen_cover_preload_direction = nil
        local jobs, already, target_page = collect_jobs(menu, direction)
        if #jobs == 0 then return end
        if is_extracting() then
            logger.measure("Cover preload skipped", 0,
                "reason=background_extraction",
                "target_page=", target_page,
                "queued=", #jobs)
            return
        end

        menu._zen_cover_preload_jobs = jobs
        local started_at = now()
        local work_ms = 0
        local warmed = 0
        local failed = 0

        local step
        step = function()
            if menu._zen_cover_preload_fn ~= step then return end
            if is_extracting() then
                menu._zen_cover_preload_fn = nil
                menu._zen_cover_preload_jobs = nil
                logger.measure("Cover preload skipped", work_ms,
                    "reason=background_extraction_after_delay",
                    "target_page=", target_page,
                    "queued=", #jobs,
                    "wall_ms=", math.floor((now() - started_at) * 1000 + 0.5))
                return
            end
            local chunk_started_at = now()
            local deadline = chunk_started_at + PRELOAD_BUDGET_S
            local processed = 0
            while processed < PRELOAD_CHUNK and #jobs > 0
                    and (processed == 0 or now() < deadline) do
                local path = table.remove(jobs, 1)
                processed = processed + 1
                if cache:has(path) then
                    already = already + 1
                else
                    local previous = rawget(_G, "__ZEN_COVER_PRELOAD_ACTIVE")
                    _G.__ZEN_COVER_PRELOAD_ACTIVE = true
                    local ok, info = pcall(BookInfoManager.getBookInfo,
                        BookInfoManager, path, true)
                    _G.__ZEN_COVER_PRELOAD_ACTIVE = previous
                    if ok and info and info.cover_bb then
                        info.cover_bb:free()
                        warmed = warmed + 1
                    else
                        failed = failed + 1
                    end
                end
            end
            work_ms = work_ms + (now() - chunk_started_at) * 1000
            if #jobs > 0 then
                UIManager:scheduleIn(PRELOAD_TICK_S, step)
                return
            end
            menu._zen_cover_preload_fn = nil
            menu._zen_cover_preload_jobs = nil
            logger.measure("Cover preload completed", work_ms,
                "target_page=", target_page,
                "warmed=", warmed,
                "already_cached=", already,
                "failed=", failed,
                "wall_ms=", math.floor((now() - started_at) * 1000 + 0.5))
        end
        menu._zen_cover_preload_fn = step
        UIManager:scheduleIn(PRELOAD_DELAY_S, step)
    end

    local function measured_updateItems(menu, original, ...)
        if menu._zen_cover_measure_active then return original(menu, ...) end
        menu._zen_cover_measure_active = true
        menu._zen_cover_build_measure = { tile_count = 0, tile_ms = 0 }
        local before = cache:stats()
        local before_render = render_cache:stats()
        local started_at = now()
        local result = defer_extraction_launch(menu, original, ...)
        accelerate_cover_poll(menu)
        local elapsed_ms = (now() - started_at) * 1000
        local after = cache:stats()
        local after_render = render_cache:stats()
        local build_measure = menu._zen_cover_build_measure
        menu._zen_cover_build_measure = nil
        menu._zen_cover_measure_active = nil
        local hits = delta(after, before, "hits")
        local misses = delta(after, before, "misses")
        local requests = hits + misses
        local hit_rate = requests > 0 and math.floor(hits * 1000 / requests + 0.5) / 10 or 0
        local perpage = tonumber(menu.perpage) or 0
        local first = ((tonumber(menu.page) or 1) - 1) * perpage + 1
        local visible = math.max(0, math.min(perpage, #(menu.item_table or {}) - first + 1))
        menu._zen_cover_paint_measure = {
            expected = visible,
            page = menu.page,
            started_at = now(),
            tile_count = 0,
            tile_ms = 0,
        }
        logger.measure("Cover page updated", elapsed_ms,
            "mode=", tostring(menu.display_mode_type),
            "page=", tostring(menu.page),
            "visible_items=", visible,
            "total_items=", #(menu.item_table or {}),
            "cache_hits=", hits,
            "cache_misses=", misses,
            "hit_rate_pct=", hit_rate,
            "avoided_decompressions=", hits,
            "avoided_db_reads=", delta(after, before, "fast_hits"),
            "full_reads=", delta(after, before, "full_reads"),
            "decode_reads=", delta(after, before, "decode_reads"),
            "decode_ms=", math.floor(delta(after, before, "decode_read_ms") * 10 + 0.5) / 10,
            "validation_ms=", math.floor(delta(after, before, "validation_ms") * 10 + 0.5) / 10,
            "tile_builds=", build_measure.tile_count,
            "tile_build_ms=", math.floor(build_measure.tile_ms * 10 + 0.5) / 10,
            "render_cache_hits=", delta(after_render, before_render, "hits"),
            "render_cache_misses=", delta(after_render, before_render, "misses"),
            "render_cache_mb=", math.floor((after_render.bytes or 0) / 1024 / 1024 * 10 + 0.5) / 10,
            "cache_mb=", math.floor((after.bytes or 0) / 1024 / 1024 * 10 + 0.5) / 10)
        schedule(menu)
        return result
    end

    local original_updateItems = CoverMenu.updateItems
    CoverMenu.updateItems = function(menu, ...)
        return measured_updateItems(menu, original_updateItems, ...)
    end

    local original_filechooser_updateItems = FileChooser.updateItems
    if original_filechooser_updateItems ~= original_updateItems then
        FileChooser.updateItems = function(menu, ...)
            if menu._updateItemsBuildUI and menu.display_mode_type then
                return measured_updateItems(menu, original_filechooser_updateItems, ...)
            end
            return original_filechooser_updateItems(menu, ...)
        end
    else
        FileChooser.updateItems = CoverMenu.updateItems
    end

    if not Menu.__zen_cover_preload_direction_patched then
        Menu.__zen_cover_preload_direction_patched = true
        local original_next = Menu.onNextPage
        function Menu:onNextPage(...)
            self._zen_cover_preload_direction = 1
            return original_next(self, ...)
        end
        local original_prev = Menu.onPrevPage
        function Menu:onPrevPage(...)
            self._zen_cover_preload_direction = -1
            return original_prev(self, ...)
        end
    end

    local original_onCloseWidget = CoverMenu.onCloseWidget
    local function onCloseWidget(menu, ...)
        cancel(menu)
        if menu._zen_cover_extract_delay_fn then
            UIManager:unschedule(menu._zen_cover_extract_delay_fn)
            menu._zen_cover_extract_delay_fn = nil
        end
        return original_onCloseWidget(menu, ...)
    end
    CoverMenu.onCloseWidget = onCloseWidget
    if FileChooser.onCloseWidget == original_onCloseWidget then
        FileChooser.onCloseWidget = onCloseWidget
    end
end

return apply_cover_preload

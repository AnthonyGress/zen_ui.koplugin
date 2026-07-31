-- Measure cover-page work and warm adjacent pages in bounded idle chunks.
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
    local memory_policy = require("common/memory_policy")
    local CoverUtils = require("common/cover_utils")
    local zen_logger = require("common/zen_logger")
    local logger = zen_logger.new("cover_preload")
    local now = zen_logger.now

    memory_policy.applyCoverBudgets(render_cache, cache)

    local PRELOAD_DELAY_S = 0.08
    local PRELOAD_TICK_S = 0.03
    local PRELOAD_CHUNK = 9
    local PRELOAD_BUDGET_S = 0.03
    local PRELOAD_MAX_JOBS = 24
    local PRELOAD_LOOKAHEAD_PAGES = 1
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
                    local input_to_last_tile_ms = measure.input_started_at
                        and (now() - measure.input_started_at) * 1000 or 0
                    logger.measure("Cover page painted", measure.tile_ms,
                        "page=", measure.page,
                        "tiles=", measure.tile_count,
                        "wall_ms=", math.floor((now() - measure.started_at) * 1000 + 0.5),
                        "page_turn_direction=", measure.direction or "none",
                        "input_to_last_tile_ms=", math.floor(input_to_last_tile_ms * 10 + 0.5) / 10)
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

    local function add_path(jobs, seen, path, width, height, render_width, render_height, final_render)
        if not path or path == "" then
            return
        end
        local existing = seen[path]
        if existing then
            if final_render then existing.final_render = true end
            return
        end
        if #jobs >= PRELOAD_MAX_JOBS then return end
        local job = {
            path = path,
            width = width,
            height = height,
            render_width = render_width,
            render_height = render_height,
            final_render = final_render == true,
        }
        seen[path] = job
        jobs[#jobs + 1] = job
    end

    local function collect_jobs(menu, direction)
        local items = menu.item_table
        local perpage = tonumber(menu.perpage)
        local page = tonumber(menu.page)
        local specs = menu.display_mode_type == "mosaic"
            and menu._zen_file_cover_specs or menu.cover_specs
        if type(specs) ~= "table" then specs = menu.cover_specs end
        local width = type(specs) == "table" and tonumber(specs.max_cover_w)
        local height = type(specs) == "table" and tonumber(specs.max_cover_h)
        local render_width, render_height = width, height
        if type(specs) == "table" and specs.uniform == true and width and height then
            render_width, render_height = CoverUtils.calcDims(width, height)
        end
        if type(items) ~= "table" or not perpage or perpage < 1 or not page then
            return {}, nil
        end
        if not width or width < 1 or not height or height < 1 then
            return {}, nil
        end
        local page_count = tonumber(menu.page_num) or math.max(1, math.ceil(#items / perpage))
        local jobs = {}
        local seen = {}
        local target_pages = {}
        for page_offset = 1, PRELOAD_LOOKAHEAD_PAGES do
            local target_page = page + direction * page_offset
            if target_page < 1 or target_page > page_count then break end
            target_pages[#target_pages + 1] = target_page
            local first = (target_page - 1) * perpage + 1
            local last = math.min(#items, first + perpage - 1)
            for index = first, last do
                local item = items[index]
                if type(item) == "table" then
                    local is_file = item.is_file or item.file
                        or (item.attr and item.attr.mode == "file")
                    if is_file then
                        add_path(jobs, seen, item.path or item.file,
                            width, height, render_width, render_height, true)
                    end
                    local grouped = item._zen_files or item.series_items
                    if type(grouped) == "table" then
                        -- Group/gallery renderers scale these through their own path.
                        for grouped_index = 1, math.min(4, #grouped) do
                            local grouped_item = grouped[grouped_index]
                            local path = type(grouped_item) == "table"
                                and (grouped_item.path or grouped_item.file) or grouped_item
                            add_path(jobs, seen, path,
                                width, height, render_width, render_height, false)
                        end
                    end
                end
                if #jobs >= PRELOAD_MAX_JOBS then break end
            end
            if #jobs >= PRELOAD_MAX_JOBS then break end
        end
        return jobs, target_pages
    end

    local function free_bitmap(bb)
        if bb and type(bb.free) == "function" then pcall(bb.free, bb) end
    end

    local function warm_job(job, outcomes)
        local decoded_cached = cache:has(job.path)
        local previous = rawget(_G, "__ZEN_COVER_PRELOAD_ACTIVE")
        _G.__ZEN_COVER_PRELOAD_ACTIVE = true
        local ok_info, info = pcall(BookInfoManager.getBookInfo,
            BookInfoManager, job.path, true)
        _G.__ZEN_COVER_PRELOAD_ACTIVE = previous

        local has_real_cover = ok_info and info and info.cover_bb
            and info.has_cover and not info.ignore_cover
        if not job.final_render then
            if has_real_cover then
                if decoded_cached then
                    outcomes.decoded_cached = outcomes.decoded_cached + 1
                else
                    outcomes.decoded_warmed = outcomes.decoded_warmed + 1
                end
            else
                outcomes.failed = outcomes.failed + 1
            end
            if info and info.cover_bb then
                free_bitmap(info.cover_bb)
                info.cover_bb = nil
            end
            return
        end
        if has_real_cover then
            if decoded_cached then
                outcomes.decoded_cached = outcomes.decoded_cached + 1
            else
                outcomes.decoded_warmed = outcomes.decoded_warmed + 1
            end
            local source = info.cover_bb
            info.cover_bb = nil
            local before = render_cache:stats()
            local ok_render, final = pcall(render_cache.render, render_cache,
                job.path, source, job.render_width, job.render_height)
            local after = render_cache:stats()
            if ok_render and final then
                free_bitmap(final)
                if delta(after, before, "puts") > 0 then
                    outcomes.final_render_warmed = outcomes.final_render_warmed + 1
                elseif delta(after, before, "hits") > 0 then
                    outcomes.final_render_cached = outcomes.final_render_cached + 1
                else
                    outcomes.failed = outcomes.failed + 1
                end
                return
            end
            outcomes.failed = outcomes.failed + 1
            return
        end

        if info and info.cover_bb then
            free_bitmap(info.cover_bb)
            info.cover_bb = nil
        end
        local before = render_cache:stats()
        local ok_generated, generated = pcall(CoverUtils.genCover,
            job.path, job.width, job.height, nil, info or false)
        local after = render_cache:stats()
        if ok_generated and generated then
            free_bitmap(generated)
            if delta(after, before, "puts") > 0 then
                outcomes.generated_warmed = outcomes.generated_warmed + 1
            elseif delta(after, before, "hits") > 0 then
                outcomes.generated_cached = outcomes.generated_cached + 1
            else
                outcomes.failed = outcomes.failed + 1
            end
            return
        end
        outcomes.failed = outcomes.failed + 1
    end

    local function schedule(menu, memory_profile)
        cancel(menu)
        if menu.no_refresh_covers == true or menu.cover_specs == false
                or menu._do_cover_images == false then
            return
        end
        local direction = menu._zen_cover_preload_direction or 1
        menu._zen_cover_preload_direction = nil
        local jobs, target_pages = collect_jobs(menu, direction)
        if #jobs == 0 then return end
        local target_page = target_pages[1]
        memory_profile = memory_profile
            or memory_policy.applyCoverBudgets(render_cache, cache)
        if not memory_policy.canPreload(memory_profile) then
            logger.measure("Cover preload skipped", 0,
                "reason=memory_" .. tostring(memory_profile.pressure),
                "target_page=", target_page,
                "lookahead_pages=", #target_pages,
                "queued=", #jobs)
            return
        end
        if is_extracting() then
            logger.measure("Cover preload skipped", 0,
                "reason=background_extraction",
                "target_page=", target_page,
                "lookahead_pages=", #target_pages,
                "queued=", #jobs)
            return
        end

        menu._zen_cover_preload_jobs = jobs
        local started_at = now()
        local work_ms = 0
        local cover_w, cover_h = jobs[1].width, jobs[1].height
        local outcomes = {
            decoded_warmed = 0,
            decoded_cached = 0,
            final_render_warmed = 0,
            final_render_cached = 0,
            generated_warmed = 0,
            generated_cached = 0,
            failed = 0,
        }

        local step
        step = function()
            if menu._zen_cover_preload_fn ~= step then return end
            local current_memory = memory_policy.applyCoverBudgets(render_cache, cache)
            if not memory_policy.canPreload(current_memory) then
                menu._zen_cover_preload_fn = nil
                menu._zen_cover_preload_jobs = nil
                logger.measure("Cover preload skipped", work_ms,
                    "reason=memory_" .. tostring(current_memory.pressure),
                    "target_page=", target_page,
                    "lookahead_pages=", #target_pages,
                    "queued=", #jobs,
                    "wall_ms=", math.floor((now() - started_at) * 1000 + 0.5))
                return
            end
            if is_extracting() then
                menu._zen_cover_preload_fn = nil
                menu._zen_cover_preload_jobs = nil
                logger.measure("Cover preload skipped", work_ms,
                    "reason=background_extraction_after_delay",
                    "target_page=", target_page,
                    "lookahead_pages=", #target_pages,
                    "queued=", #jobs,
                    "wall_ms=", math.floor((now() - started_at) * 1000 + 0.5))
                return
            end
            local chunk_started_at = now()
            local deadline = chunk_started_at + PRELOAD_BUDGET_S
            local processed = 0
            while processed < PRELOAD_CHUNK and #jobs > 0
                    and (processed == 0 or now() < deadline) do
                local job = table.remove(jobs, 1)
                processed = processed + 1
                warm_job(job, outcomes)
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
                "lookahead_pages=", #target_pages,
                "cover_w=", cover_w,
                "cover_h=", cover_h,
                "warmed=", outcomes.final_render_warmed + outcomes.generated_warmed,
                "already_cached=", outcomes.final_render_cached + outcomes.generated_cached,
                "decoded_warmed=", outcomes.decoded_warmed,
                "decoded_cached=", outcomes.decoded_cached,
                "final_render_warmed=", outcomes.final_render_warmed,
                "final_render_cached=", outcomes.final_render_cached,
                "generated_warmed=", outcomes.generated_warmed,
                "generated_cached=", outcomes.generated_cached,
                "failed=", outcomes.failed,
                "wall_ms=", math.floor((now() - started_at) * 1000 + 0.5))
        end
        menu._zen_cover_preload_fn = step
        UIManager:scheduleIn(PRELOAD_DELAY_S, step)
    end

    local function measured_updateItems(menu, original, ...)
        if menu._zen_cover_measure_active then return original(menu, ...) end
        local turn_measure = menu._zen_cover_turn_measure
        menu._zen_cover_turn_measure = nil
        menu._zen_cover_measure_active = true
        menu._zen_cover_build_measure = { tile_count = 0, tile_ms = 0 }
        local memory_profile = memory_policy.applyCoverBudgets(render_cache, cache)
        local before = cache:stats()
        local before_render = render_cache:stats()
        local started_at = now()
        if menu.display_mode_type == "mosaic" then
            menu._zen_file_cover_specs = nil
        end
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
            input_started_at = turn_measure and turn_measure.started_at,
            direction = turn_measure and turn_measure.direction,
            tile_count = 0,
            tile_ms = 0,
        }
        local input_to_update_ms = turn_measure
            and (now() - turn_measure.started_at) * 1000 or 0
        local file_specs = menu._zen_file_cover_specs
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
            "cache_mb=", math.floor((after.bytes or 0) / 1024 / 1024 * 10 + 0.5) / 10,
            "memory_pressure=", memory_profile.pressure,
            "memory_available_mb=", memory_profile.available_bytes
                and math.floor(memory_profile.available_bytes / 1024 / 1024 + 0.5) or -1,
            "render_budget_mb=",
                math.floor((after_render.byte_budget or 0) / 1024 / 1024 * 10 + 0.5) / 10,
            "decode_budget_mb=",
                math.floor((after.byte_budget or 0) / 1024 / 1024 * 10 + 0.5) / 10,
            "cover_w=", type(file_specs) == "table" and file_specs.max_cover_w or 0,
            "cover_h=", type(file_specs) == "table" and file_specs.max_cover_h or 0,
            "page_turn_direction=", turn_measure and turn_measure.direction or "none",
            "input_to_update_ms=", math.floor(input_to_update_ms * 10 + 0.5) / 10)
        schedule(menu, memory_profile)
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

    local function patch_page_turn(owner, method, direction, label)
        local marker = "__zen_cover_preload_" .. method .. "_patched"
        if rawget(owner, marker) or type(owner[method]) ~= "function" then return end
        owner[marker] = true
        local original = owner[method]
        owner[method] = function(menu, ...)
            if menu._zen_cover_turn_active then return original(menu, ...) end
            menu._zen_cover_turn_active = true
            menu._zen_cover_preload_direction = direction
            local turn_measure = { direction = label, started_at = now() }
            menu._zen_cover_turn_measure = turn_measure
            local result = original(menu, ...)
            if menu._zen_cover_turn_measure == turn_measure then
                menu._zen_cover_turn_measure = nil
            end
            menu._zen_cover_turn_active = nil
            return result
        end
    end
    patch_page_turn(Menu, "onNextPage", 1, "next")
    patch_page_turn(Menu, "onPrevPage", -1, "previous")
    patch_page_turn(CoverMenu, "onNextPage", 1, "next")
    patch_page_turn(CoverMenu, "onPrevPage", -1, "previous")
    patch_page_turn(FileChooser, "onNextPage", 1, "next")
    patch_page_turn(FileChooser, "onPrevPage", -1, "previous")

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

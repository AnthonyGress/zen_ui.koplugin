local logger = require("logger")
local ConfigManager = require("config/manager")
local book_status = require("common/book_status")
local Blitbuffer = require("ffi/blitbuffer")
local HomeQuotes = require("modules/filebrowser/patches/home/home_quotes")
local HomePresets = require("modules/filebrowser/patches/home/home_presets")
local PresetStore = require("config/preset_store")
local Registry = require("modules/filebrowser/patches/home/components/registry")
local StandalonePage = require("modules/filebrowser/patches/standalone_page")
local SharedState = require("common/shared_state")
local WidgetResources = require("common/widget_resources")

local M = {}

-- When a library background image is configured, home module frames must be
-- transparent (nil fill) instead of opaque COLOR_WHITE, or they paint over the
-- background painted behind the page. Returns the fill color to use.
local Background = require("common/ui/background")
local function home_frame_bg()
    return Background.tile_bg(Blitbuffer.COLOR_WHITE)
end

local _home_menu = nil
local _home_inject_navbar = nil
local _zen_shared = nil
local _zen_plugin = nil
local _home_book_cache = {}
local _home_book_cache_order = {}
local HOME_BOOK_CACHE_MAX = 32

local function free_cached_book(book)
    if book and book.cover_bb and book.cover_bb.free then
        pcall(function() book.cover_bb:free() end)
    end
end

local function clone_cached_book(book)
    if type(book) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(book) do
        if k ~= "cover_bb" then out[k] = v end
    end
    if book.cover_bb and book.cover_bb.copy then
        out.cover_bb = book.cover_bb:copy()
    end
    return out
end

local function get_home_book_cache_key(path)
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    local file_mtime = ok_lfs and lfs.attributes(path, "modification") or 0
    local sidecar_mtime = 0
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if ok_lfs and ok_ds and DocSettings and type(DocSettings.findSidecarFile) == "function" then
        local ok_sidecar, sidecar_file = pcall(DocSettings.findSidecarFile, DocSettings, path)
        if ok_sidecar and sidecar_file then
            sidecar_mtime = lfs.attributes(sidecar_file, "modification") or 0
        end
    end
    return table.concat({
        path,
        tostring(file_mtime or 0),
        tostring(sidecar_mtime or 0),
    }, "|")
end

local function invalidate_home_book_cache(path)
    if type(path) ~= "string" or path == "" then return end
    local prefix = path .. "|"
    for key, book in pairs(_home_book_cache) do
        if key:sub(1, #prefix) == prefix then
            free_cached_book(book)
            _home_book_cache[key] = nil
        end
    end
    for i = #_home_book_cache_order, 1, -1 do
        if _home_book_cache_order[i]:sub(1, #prefix) == prefix then
            table.remove(_home_book_cache_order, i)
        end
    end
end

local function cache_home_book(key, book)
    local old = _home_book_cache[key]
    if old then free_cached_book(old) end
    _home_book_cache[key] = clone_cached_book(book)
    _home_book_cache_order[#_home_book_cache_order + 1] = key
    while #_home_book_cache_order > HOME_BOOK_CACHE_MAX do
        local evict = table.remove(_home_book_cache_order, 1)
        if evict and evict ~= key then
            free_cached_book(_home_book_cache[evict])
            _home_book_cache[evict] = nil
        end
    end
end

-- Home-screen widgets (featured/strip) can render covers much larger than the
-- file browser's list/mosaic cells. BookInfoManager's cache only ever grows a
-- cached cover, never shrinks it, so a cover first cached for a small list row
-- stays small (and gets pixelated when upscaled here) until something asks for
-- bigger. A third of the screen's linear size comfortably covers the largest
-- home-screen cover (the featured widget); extraction is still bounded by the
-- source cover's own resolution, so this never costs more than the book has.
-- Returns the {max_cover_w, max_cover_h} spec table to extract/cache covers at
-- for home-screen display, derived from the current screen size.
local function home_cover_specs()
    local Screen = require("device").screen
    return { max_cover_w = math.floor(Screen:getWidth() / 3), max_cover_h = math.floor(Screen:getHeight() / 3) }
end

-- cover_sizetag stores the native (original) image dimensions, e.g. "600x900".
-- cover_w/cover_h are the actual cached bitmap size after scaling to fit whatever
-- spec was used at extraction time. To decide whether a larger home-screen spec
-- would produce a bigger result: compute what getCachedCoverSize would yield at
-- our spec, then compare that against what is currently cached.
local function home_cover_too_small(bi, specs)
    if not bi.cover_w or not bi.cover_h then return true end
    local img_w, img_h = tostring(bi.cover_sizetag or ""):match("(%d+)x(%d+)")
    if not img_w then return true end
    img_w, img_h = tonumber(img_w), tonumber(img_h)
    local max_w, max_h = specs.max_cover_w, specs.max_cover_h
    local target_w, target_h
    if img_w > max_w or img_h > max_h then
        local scale = math.min(max_w / img_w, max_h / img_h)
        target_w = math.floor(img_w * scale)
        target_h = math.floor(img_h * scale)
    else
        target_w, target_h = img_w, img_h
    end
    return target_w > bi.cover_w or target_h > bi.cover_h
end

local _pending_cover_upgrade_paths = {}
local _cover_upgrade_scheduled = false
-- Paths currently being processed by an extractInBackground() subprocess we
-- launched. A book mid-extraction still reads as "invalid" from the DB (its
-- row isn't written until its turn in the batch completes), so a rebuild that
-- runs while a batch is still in flight must not re-queue books already in
-- that batch -- extractInBackground() unconditionally kills any previous
-- subprocess before starting a new one, so requeuing one slow book partway
-- through a batch was terminating the whole batch and orphaning the rest.
local _inflight_cover_upgrade_paths = {}

-- Takes everything queued in _pending_cover_upgrade_paths and launches a
-- single extractInBackground() batch for them at home-screen cover size, then
-- polls until each path's extraction completes (or the subprocess dies),
-- invalidating that book's home-cache entry and triggering a home rebuild as
-- results land.
local function flush_cover_upgrade_queue()
    _cover_upgrade_scheduled = false
    local paths = {}
    for path in pairs(_pending_cover_upgrade_paths) do
        paths[#paths + 1] = path
    end
    _pending_cover_upgrade_paths = {}
    if #paths == 0 then return end

    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim or not BookInfoManager then
        logger.warn("zen-ui home: bookinfomanager require failed, cannot upgrade covers")
        return
    end

    local specs = home_cover_specs()
    local files = {}
    for _i, path in ipairs(paths) do
        files[#files + 1] = { filepath = path, cover_specs = specs }
        _inflight_cover_upgrade_paths[path] = true
    end

    local UIManager = require("ui/uimanager")
    local launched = BookInfoManager:extractInBackground(files)
    if not launched then
        for _i, path in ipairs(paths) do
            _inflight_cover_upgrade_paths[path] = nil
        end
        return
    end

    local waiting = {}
    for _i, path in ipairs(paths) do
        waiting[path] = true
    end

    -- Poll per-path completion (mirrors covermenu.lua's items_update_action)
    -- rather than waiting for the whole subprocess to exit: a single batch can
    -- contain several books, and if one of them crashes the subprocess, the
    -- books already extracted before the crash must still get picked up
    -- instead of being stuck waiting on the ones that never finished.
    local function poll()
        local is_still_extracting = BookInfoManager:isExtractingInBackground()
        local any_done = false
        for path in pairs(waiting) do
            local bi = BookInfoManager:getBookInfo(path, false)
            if bi and bi.cover_fetched then
                waiting[path] = nil
                _inflight_cover_upgrade_paths[path] = nil
                invalidate_home_book_cache(path)
                any_done = true
            end
        end
        if any_done and M.isActiveOnTop() and _home_menu and _home_menu._home_rebuild then
            _home_menu:_home_rebuild()
        end
        if next(waiting) and is_still_extracting then
            UIManager:scheduleIn(1, poll)
        else
            -- Either fully done, or the subprocess is gone and some paths
            -- never got their turn (crashed/killed). Release those so a
            -- future visit to the home screen can requeue and retry them.
            for path in pairs(waiting) do
                _inflight_cover_upgrade_paths[path] = nil
            end
        end
    end
    UIManager:scheduleIn(1, poll)
end

-- Adds `path` to the pending cover-upgrade queue (unless it's already
-- pending or mid-extraction) and schedules a debounced
-- flush_cover_upgrade_queue() call so several books queued in quick
-- succession are batched into one extraction run.
local function queue_cover_upgrade(path)
    if type(path) ~= "string" or path == "" then return end
    if _pending_cover_upgrade_paths[path] or _inflight_cover_upgrade_paths[path] then return end
    _pending_cover_upgrade_paths[path] = true
    if not _cover_upgrade_scheduled then
        _cover_upgrade_scheduled = true
        require("ui/uimanager"):scheduleIn(0.3, flush_cover_upgrade_queue)
    end
end

local function refresh_shared_state()
    if _zen_plugin then
        _zen_shared = SharedState.restore(_zen_plugin) or _zen_shared
    end
    return _zen_shared
end

local DEFAULT_ROW_ORDER = {
    "datetime",
    "featured_recent",
    "featured_custom",
    "featured_tbr",
    "stats_triplet",
    "reading_goals",
    "strip_recent",
    "strip_custom",
    "strip_tbr",
    "quotes",
}

local DEFAULT_ROW_ENABLED = {
    datetime = true,
    featured_recent = true,
    quotes = true,
    strip_recent = true,
}

local DEFAULT_FEATURED_PROGRESS_META = {
    left = "percent",
    right = "total_pages",
}

local FEATURED_TEXT_STYLE_DEFAULTS = {
    title = { font_face = "default", font_size = 11, bold = true },
    author = { font_face = "default", font_size = 9, bold = false },
    description = { font_face = "default", font_size = 16, bold = false },
}

local MODULE_TITLES = {
    datetime = "Today",
    featured_custom = "Featured Book",
    featured_tbr = "To be Read",
    featured_recent = "Recently read",
    reading_goals = "Reading goals",
    strip_custom = "Featured Books",
    strip_tbr = "To be Read",
    strip_recent = "Recently read",
    stats_triplet = "Reading stats",
    quotes = "Quote",
}

local function normalize_order(order)
    if order == "reverse" then return "reverse" end
    return "default"
end

local function ensure_featured_text_style(mcfg, key)
    if type(mcfg.text_styles) ~= "table" then mcfg.text_styles = {} end
    local defaults = FEATURED_TEXT_STYLE_DEFAULTS[key]
    if type(defaults) ~= "table" then return nil end
    if type(mcfg.text_styles[key]) ~= "table" then mcfg.text_styles[key] = {} end
    local style = mcfg.text_styles[key]
    if type(style.font_face) ~= "string" or style.font_face == "" then
        style.font_face = defaults.font_face
    end
    local size = tonumber(style.font_size)
    if not size then
        style.font_size = defaults.font_size
    else
        style.font_size = math.max(6, math.min(40, math.floor(size + 0.5)))
    end
    if style.bold == nil then
        style.bold = defaults.bold
    else
        style.bold = style.bold == true
    end
    return style
end

local function ensure_featured_text_styles(mcfg)
    for key, defaults in pairs(FEATURED_TEXT_STYLE_DEFAULTS) do
        if defaults then ensure_featured_text_style(mcfg, key) end
    end
end

local function ensure_module_cfg(dcfg, module_id)
    if type(dcfg.modules) ~= "table" then dcfg.modules = {} end
    if type(dcfg.modules[module_id]) ~= "table" then dcfg.modules[module_id] = {} end
    local mcfg = dcfg.modules[module_id]
    if module_id == "datetime" then
        mcfg.show_module_title = false
    elseif mcfg.show_module_title == nil then
        mcfg.show_module_title = false
    end
    return mcfg
end

local function ensure_featured_module_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if mcfg.show_description == nil then mcfg.show_description = true end
    if mcfg.interactive == nil then mcfg.interactive = true end
    if mcfg.show_status_bar == nil then mcfg.show_status_bar = false end
    if mcfg.status_bar_show_bottom_border == nil then mcfg.status_bar_show_bottom_border = true end
    if mcfg.status_bar_bold_text == nil then mcfg.status_bar_bold_text = true end
    ensure_featured_text_styles(mcfg)
    if type(mcfg.progress_meta) ~= "table" then mcfg.progress_meta = {} end
    if mcfg.progress_meta.left == nil and mcfg.progress_meta.right == nil then
        for key, side in pairs(mcfg.progress_meta) do
            if side == "left" and mcfg.progress_meta.left == nil then
                mcfg.progress_meta.left = key
            elseif side == "right" and mcfg.progress_meta.right == nil then
                mcfg.progress_meta.right = key
            end
        end
    end
    for side, metric in pairs(DEFAULT_FEATURED_PROGRESS_META) do
        if mcfg.progress_meta[side] ~= "total_pages"
                and mcfg.progress_meta[side] ~= "current_total"
                and mcfg.progress_meta[side] ~= "percent"
                and mcfg.progress_meta[side] ~= "time_left"
                and mcfg.progress_meta[side] ~= "off" then
            mcfg.progress_meta[side] = metric
        end
    end
    return mcfg
end

local function ensure_strip_module_cfg(dcfg, module_id)
    local mcfg = ensure_module_cfg(dcfg, module_id)
    mcfg.order = normalize_order(mcfg.order)
    if mcfg.interactive == nil then mcfg.interactive = true end
    if module_id == "strip_recent" then
        if mcfg.filter_unread == nil then mcfg.filter_unread = false end
        if mcfg.filter_tbr == nil then mcfg.filter_tbr = false end
        if mcfg.filter_finished == nil then mcfg.filter_finished = false end
    end
    if mcfg.two_rows == nil then mcfg.two_rows = false end
    if type(mcfg.count) ~= "number" then mcfg.count = mcfg.two_rows and 8 or 4 end
    if mcfg.two_rows then
        if mcfg.count < 2 then mcfg.count = 2 end
        if mcfg.count > 10 then mcfg.count = 10 end
    else
        if mcfg.count < 3 then mcfg.count = 3 end
        if mcfg.count > 5 then mcfg.count = 5 end
    end
    if mcfg.show_strip_titles == nil then mcfg.show_strip_titles = false end
    return mcfg
end

local function ensure_home_widget_cfg(dcfg)
    local featured_custom = ensure_featured_module_cfg(dcfg, "featured_custom")
    if type(featured_custom.path) ~= "string" then featured_custom.path = nil end
    ensure_featured_module_cfg(dcfg, "featured_tbr")
    ensure_featured_module_cfg(dcfg, "featured_recent")
    local stats_triplet = ensure_module_cfg(dcfg, "stats_triplet")
    if stats_triplet.stat_style ~= "outline" and stats_triplet.stat_style ~= "none" then
        stats_triplet.stat_style = "divider"
    end
    local strip_custom = ensure_strip_module_cfg(dcfg, "strip_custom")
    if type(strip_custom.paths) ~= "table" then strip_custom.paths = {} end
    ensure_strip_module_cfg(dcfg, "strip_tbr")
    ensure_strip_module_cfg(dcfg, "strip_recent")
end

local function load_zen_config()
    if _zen_plugin and type(_zen_plugin.config) == "table" then
        return _zen_plugin.config
    end
    local ok, cfg = pcall(ConfigManager.load)
    if ok and type(cfg) == "table" then
        return cfg
    end
end

local function unique_user_preset_name(base)
    if not PresetStore.find("home", base) then return base end
    local i = 2
    while PresetStore.find("home", base .. " " .. i) do
        i = i + 1
    end
    return base .. " " .. i
end

local function editable_name_for_builtin(preset_name)
    if preset_name == HomePresets.DEFAULT_PRESET_NAME then
        return HomePresets.CUSTOM_PRESET_NAME
    end
    return tostring(preset_name or HomePresets.CUSTOM_PRESET_NAME) .. " custom"
end

local function ensure_home_cfg()
    local dcfg = PresetStore.getSettings("home")
    if type(dcfg) ~= "table" or next(dcfg) == nil then
        dcfg = HomePresets.defaultHomePage()
    end
    HomePresets.ensurePresetState(dcfg)

    dcfg.rows = Registry.normalizeRows(dcfg.rows, DEFAULT_ROW_ORDER, DEFAULT_ROW_ENABLED)

    if dcfg.show_status_bar == nil then dcfg.show_status_bar = true end

    if type(dcfg.middle_stats_triplet) ~= "table" then
        dcfg.middle_stats_triplet = { "today_pages", "today_duration", "streak" }
    end

    if type(dcfg.goals) ~= "table" then dcfg.goals = {} end
    if dcfg.goals.metric ~= "time" and dcfg.goals.metric ~= "pages" then
        dcfg.goals.metric = "pages"
    end
    if dcfg.goals.period ~= "weekly" and dcfg.goals.period ~= "daily" then
        dcfg.goals.period = "daily"
    end
    if type(dcfg.goals.daily_pages_target) ~= "number" then dcfg.goals.daily_pages_target = 30 end
    if type(dcfg.goals.weekly_pages_target) ~= "number" then dcfg.goals.weekly_pages_target = 210 end
    if type(dcfg.goals.daily_time_target_min) ~= "number" then dcfg.goals.daily_time_target_min = 30 end
    if type(dcfg.goals.weekly_time_target_min) ~= "number" then dcfg.goals.weekly_time_target_min = 210 end

    if type(dcfg.quotes) ~= "table" then dcfg.quotes = {} end
    if dcfg.quotes.show_author == nil then dcfg.quotes.show_author = true end

    if type(dcfg.quotes.manual_index) ~= "number" then dcfg.quotes.manual_index = 1 end

    -- Per-widget home settings.
    for _i, comp in ipairs(Registry.list()) do
        ensure_module_cfg(dcfg, comp.id)
    end
    ensure_home_widget_cfg(dcfg)

    return dcfg
end

local function save_home_settings(dcfg)
    if type(dcfg) == "table" and HomePresets.isBuiltinPresetName(dcfg.active_preset) then
        local name = unique_user_preset_name(editable_name_for_builtin(dcfg.active_preset))
        dcfg.active_preset = name
        dcfg.title = name
        local state = HomePresets.captureHomePage(dcfg)
        state.title = name
        PresetStore.save("home", name, state)
        PresetStore.setActivePreset("home", name)
    end
    PresetStore.saveSettings("home", dcfg)
end

local function resolve_rows(dcfg)
    local rows_cfg = dcfg.rows or {}
    local order = rows_cfg.order or DEFAULT_ROW_ORDER
    local enabled = rows_cfg.enabled or {}
    local max_rows = tonumber(rows_cfg.max_rows) or 5
    if max_rows < 1 then max_rows = 1 end
    if max_rows > 5 then max_rows = 5 end

    local seen = {}
    local out = {}
    local selected_count = 0

    local function try_push(id)
        if seen[id] then return end
        if enabled[id] ~= true then return end
        seen[id] = true
        selected_count = selected_count + 1
        local comp = Registry.get(id)
        if not comp then return end
        -- for strip widgets with two_rows enabled, double the size allocation
        local mcfg = type(dcfg.modules) == "table" and dcfg.modules[id] or nil
        if mcfg and mcfg.two_rows == true and comp.size then
            local s = comp.size
            comp = setmetatable({
                size = {
                    preferred_pct = (s.preferred_pct or 0.20) * 2,
                    min_pct       = (s.min_pct       or 0.12) * 2,
                    max_pct       = (s.max_pct       or 0.30) * 2,
                    grow_priority = s.grow_priority,
                },
            }, { __index = comp })
        end
        table.insert(out, comp)
    end

    for _i, id in ipairs(order) do
        try_push(id)
        if selected_count >= max_rows then break end
    end

    if selected_count < max_rows then
        for _i, comp in ipairs(Registry.list()) do
            try_push(comp.id)
            if selected_count >= max_rows then break end
        end
    end

    if #out == 0 and selected_count == 0 then
        for _i, id in ipairs(DEFAULT_ROW_ORDER) do
            local comp = Registry.get(id)
            if comp then table.insert(out, comp) end
            if #out >= max_rows then break end
        end
    end

    while #out > max_rows do
        table.remove(out)
    end

    return out
end

local function get_quote_day_index()
    local now = os.date("*t")
    return ((now.year * 366) + now.yday)
end

local function get_daily_quote_index()
    local quotes = HomeQuotes.getQuotes()
    if #quotes == 0 then return 1 end
    return (get_quote_day_index() % #quotes) + 1
end

local function collect_stats_fields(rows, dcfg)
    local fields = {}
    local needs_stats = false

    local function add(name)
        fields[name] = true
        needs_stats = true
    end

    for _i, comp in ipairs(rows or {}) do
        local id = comp and comp.id
        if id == "stats_triplet" then
            local triplet = dcfg.middle_stats_triplet or { "today_pages", "today_duration", "streak" }
            local added = false
            for _j, field in ipairs(triplet) do
                if field == "today_pages" or field == "today_duration"
                        or field == "week_pages" or field == "week_duration"
                        or field == "streak" then
                    add(field)
                    added = true
                else
                    add("today_pages")
                    added = true
                end
            end
            if not added then add("today_pages") end
        elseif id == "reading_goals" then
            local goals = dcfg.goals or {}
            local metric = goals.metric == "time" and "time" or "pages"
            local period = goals.period == "weekly" and "weekly" or "daily"
            if metric == "time" then
                add(period == "weekly" and "week_duration" or "today_duration")
            else
                add(period == "weekly" and "week_pages" or "today_pages")
            end
        end
    end

    if not needs_stats then return nil end
    return fields
end

local function stats_fields_key(fields)
    if type(fields) ~= "table" then return "" end
    local order = { "today_pages", "today_duration", "week_pages", "week_duration", "streak" }
    local out = {}
    for _i, key in ipairs(order) do
        if fields[key] then out[#out + 1] = key end
    end
    return table.concat(out, ",")
end

local function build_data_provider(cfg, dcfg)
    local provider = {}
    local stats_cached = nil
    local stats_cached_key = nil
    local history_cached = nil
    local tbr_cached = nil
    local strip_offsets = {}

    local function is_widget_visible(widget_id)
        if type(widget_id) ~= "string" or widget_id == "" then return false end
        local rows_cfg = dcfg and dcfg.rows or {}
        local order = type(rows_cfg.order) == "table" and rows_cfg.order or DEFAULT_ROW_ORDER
        local enabled = type(rows_cfg.enabled) == "table" and rows_cfg.enabled or {}
        local max_rows = tonumber(rows_cfg.max_rows) or 5
        if max_rows < 1 then max_rows = 1 end
        if max_rows > 5 then max_rows = 5 end

        local seen = {}
        local shown = 0

        local function try_mark(id)
            if seen[id] then return false end
            if enabled[id] ~= true then return false end
            seen[id] = true
            shown = shown + 1
            local comp = Registry.get(id)
            if not comp then return false end
            return id == widget_id
        end

        for _i, id in ipairs(order) do
            if try_mark(id) then return true end
            if shown >= max_rows then return false end
        end

        for _i, comp in ipairs(Registry.list()) do
            if try_mark(comp.id) then return true end
            if shown >= max_rows then return false end
        end

        return false
    end

    local function featured_widget_for_source(source)
        if source == "custom_featured" then return "featured_custom" end
        if source == "custom_strip" then return "featured_custom" end
        if source == "to_be_read" then return "featured_tbr" end
        return "featured_recent"
    end

    local function get_stats(fields)
        if stats_cached then return stats_cached end
        local ok_stats, StatsDB = pcall(require, "common/db_stats")
        if ok_stats and StatsDB and type(StatsDB.queryHomeStats) == "function" then
            stats_cached = StatsDB.queryHomeStats(fields) or {}
        elseif ok_stats and StatsDB and type(StatsDB.queryStats) == "function" then
            stats_cached = StatsDB.queryStats() or {}
        else
            stats_cached = {}
        end
        return stats_cached
    end

    local function get_history()
        if history_cached then
            return history_cached
        end
        history_cached = {}
        local ok_rh, ReadHistory = pcall(require, "readhistory")
        if not ok_rh or not ReadHistory then
            return history_cached
        end

        if type(ReadHistory.reload) == "function" then
            pcall(ReadHistory.reload, ReadHistory, false)
        end

        local hist = ReadHistory.hist or {}
        local lfs = require("libs/libkoreader-lfs")
        local paths = require("common/paths")

        for _i, entry in ipairs(hist) do
            local path = entry and entry.file
            if type(path) == "string"
                    and path ~= ""
                    and paths.isInHomeDir(path)
                    and lfs.attributes(path, "mode") == "file" then
                table.insert(history_cached, path)
            end
        end

        return history_cached
    end

    local function get_book(path, need_time_left)
        if not path then return nil end
        local cache_key = get_home_book_cache_key(path)
            .. (need_time_left and "|time_left" or "")
        local cached = _home_book_cache[cache_key]
        if cached then
            return clone_cached_book(cached)
        end
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        local cover_bb, title, authors, pages, description
        if ok_bim and BookInfoManager then
            -- get_cover=true also matches a directory/unsupported-file placeholder
            -- object (ignore_cover='Y', _no_provider/_is_directory set) that's never
            -- queueable; real books fall through to the branches below.
            local bi = BookInfoManager:getBookInfo(path, true)
            if bi then
                title = bi.title
                authors = bi.authors
                pages = bi.pages
                description = bi.description
            end
            if bi and bi.cover_bb and bi.has_cover and bi.cover_fetched and not bi.ignore_cover then
                cover_bb = bi.cover_bb:copy()
                -- Cached cover may be too small (e.g. extracted for a small
                -- list row); queue a background re-extraction at full size
                -- and use today's (possibly upscaled) cover in the meantime.
                if home_cover_too_small(bi, home_cover_specs()) then
                    queue_cover_upgrade(path)
                end
            elseif bi and (bi.cover_fetched or bi.ignore_cover) then -- luacheck: ignore 542
                -- Extraction was already tried and found no usable cover (or the
                -- user chose to ignore it): nothing to gain from retrying.
            else
                -- Never extracted at all (fresh cache, or only metadata was ever
                -- fetched): queue a first extraction at home-screen size instead
                -- of waiting for the file browser to stumble onto this book.
                queue_cover_upgrade(path)
            end
        end

        local pct = nil
        local status = nil
        local current_page = nil
        local time_left_secs = nil
        local stable_pages = nil
        local stable_current_page = nil
        local stable_current_label = nil
        local stable_last_label = nil
        local doc_settings = nil
        local ok_ds, DocSettings = pcall(require, "docsettings")
        if ok_ds and DocSettings and DocSettings:hasSidecarFile(path) then
            local ok_doc, doc = pcall(DocSettings.open, DocSettings, path)
            if ok_doc and doc then
                doc_settings = doc
                pct = doc:readSetting("percent_finished")
                local summary = doc:readSetting("summary")
                status = summary and summary.status
                local stats = doc:readSetting("stats")
                if not pages then
                    pages = stats and stats.pages
                end
                local total_pages = tonumber(pages)
                if total_pages and pct then
                    current_page = math.floor(total_pages * pct + 0.5)
                    if pct > 0 and current_page < 1 then current_page = 1 end
                    if current_page > total_pages then current_page = total_pages end
                end
                local avg_time
                if need_time_left then
                    local ok_stats, StatsDB = pcall(require, "common/db_stats")
                    if ok_stats and StatsDB and type(StatsDB.queryBookAveragePageTime) == "function" then
                        local db_avg_time, db_pages = StatsDB.queryBookAveragePageTime(
                            path, doc:readSetting("partial_md5_checksum"))
                        avg_time = db_avg_time
                        if not total_pages and db_pages and db_pages > 0 then
                            pages = db_pages
                            total_pages = db_pages
                            if pct then
                                current_page = math.floor(total_pages * pct + 0.5)
                                if pct > 0 and current_page < 1 then current_page = 1 end
                                if current_page > total_pages then current_page = total_pages end
                            end
                        end
                    end
                end
                if avg_time and avg_time > 0 and total_pages and current_page and current_page < total_pages then
                    time_left_secs = math.floor((total_pages - current_page) * avg_time)
                end
                if doc:readSetting("pagemap_use_page_labels") == true then
                    stable_current_label = doc:readSetting("pagemap_current_page_label")
                    stable_last_label = doc:readSetting("pagemap_last_page_label")
                    stable_pages = tonumber(doc:readSetting("pagemap_doc_pages"))
                        or tonumber(stable_last_label)
                    stable_current_page = tonumber(stable_current_label)
                    if not stable_current_page and stable_pages and pct then
                        stable_current_page = math.floor(stable_pages * pct + 0.5)
                    end
                    if stable_current_page and stable_pages then
                        if pct and pct > 0 and stable_current_page < 1 then stable_current_page = 1 end
                        if stable_current_page > stable_pages then stable_current_page = stable_pages end
                    end
                end
            end
        end
        local computed_status = book_status.getComputedStatus(
            path, status, pct, doc_settings
        )

        if not title or title == "" then
            title = (path:match("([^/]+)$") or path):gsub("%.[^%.]+$", "")
        end

        local book = {
            path = path,
            title = title,
            authors = authors or "",
            cover_bb = cover_bb,
            percent = pct or 0,
            percent_finished = pct,
            status = computed_status,
            pages = pages,
            current_page = current_page,
            time_left_secs = time_left_secs,
            stable_pages = stable_pages,
            stable_current_page = stable_current_page,
            stable_current_label = stable_current_label,
            stable_last_label = stable_last_label,
            description = description,
        }
        cache_home_book(cache_key, book)
        return book
    end

    local function sort_files_like_tbr(files)
        local group_view = cfg and cfg.group_view or {}
        local detail_collate = group_view.detail_collate or {}
        local detail_reverse = group_view.detail_reverse or {}
        local collate_tbl = detail_collate.to_be_read or {}
        local reverse_tbl = detail_reverse.to_be_read or {}

        local collate = collate_tbl.to_be_read or "title"
        local reverse = reverse_tbl.to_be_read == true

        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        local lfs = require("libs/libkoreader-lfs")

        local items = {}
        for _i, fpath in ipairs(files) do
            local key
            if collate == "access" then
                key = lfs.attributes(fpath, "access") or 0
            elseif collate == "series_index" then
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and tonumber(bi.series_index)) or math.huge
            elseif collate == "title" then
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and bi.title) or (fpath:match("([^/]+)$") or fpath)
            else
                local bi = ok_bim and BookInfoManager:getBookInfo(fpath, false) or nil
                key = (bi and bi.title) or (fpath:match("([^/]+)$") or fpath)
            end
            table.insert(items, { path = fpath, key = key })
        end

        table.sort(items, function(a, b)
            if collate == "access" or collate == "series_index" then
                local ka = type(a.key) == "number" and a.key or 0
                local kb = type(b.key) == "number" and b.key or 0
                if collate == "access" then
                    if reverse then return ka < kb else return ka > kb end
                end
                if reverse then return ka > kb else return ka < kb end
            end
            local sa = tostring(a.key):lower()
            local sb = tostring(b.key):lower()
            if reverse then return sa > sb else return sa < sb end
        end)

        local sorted = {}
        for _i, item in ipairs(items) do
            table.insert(sorted, item.path)
        end
        return sorted
    end

    local function get_tbr_paths()
        if tbr_cached then
            return tbr_cached
        end
        tbr_cached = {}
        local ok_db, db = pcall(require, "common/db_bookinfo")
        if ok_db and db and type(db.getTBRBooks) == "function" then
            local raw_tbr = db.getTBRBooks() or {}
            local normalized = {}
            for _i, item in ipairs(raw_tbr) do
                local path = item
                if type(item) == "table" then
                    path = item.path or item.file
                end
                if type(path) == "string" and path ~= "" then
                    table.insert(normalized, path)
                end
            end
            tbr_cached = normalized
            tbr_cached = sort_files_like_tbr(tbr_cached)
        end
        return tbr_cached
    end

    local function get_paths_by_statuses(statuses, limit)
        local hist = get_history()
        local out = {}
        for _i, path in ipairs(hist) do
            local eff = book_status.getEffectiveStatusFromFile(path)
            if statuses[eff] then
                table.insert(out, path)
                if #out >= limit then break end
            end
        end
        return out
    end

    local function get_paths_by_status(status_key, limit)
        return get_paths_by_statuses({ [status_key] = true }, limit)
    end

    local function append_unique_paths(dst, src, limit)
        if type(src) ~= "table" then return end
        local seen = {}
        for _i, path in ipairs(dst) do
            if type(path) == "string" and path ~= "" then
                seen[path] = true
            end
        end
        for _i, path in ipairs(src) do
            if type(path) == "string" and path ~= "" and not seen[path] then
                seen[path] = true
                table.insert(dst, path)
                if #dst >= limit then break end
            end
        end
    end

    local function reverse_copy(paths)
        local out = {}
        for i = #paths, 1, -1 do
            out[#out + 1] = paths[i]
        end
        return out
    end

    local function collect_paths_for_source(source_key, limit, opts)
        opts = type(opts) == "table" and opts or {}
        local source = source_key
        if source ~= "custom_featured"
                and source ~= "custom_strip"
                and source ~= "currently_reading"
                and source ~= "to_be_read" then
            source = "recently_read"
        end
        local lim = tonumber(limit) or 5000
        if source == "custom_featured" then
            local mcfg = dcfg and dcfg.modules and dcfg.modules.featured_custom or {}
            local path = type(mcfg.path) == "string" and mcfg.path or nil
            return path and { path } or {}
        end
        if source == "custom_strip" then
            local mcfg = dcfg and dcfg.modules and dcfg.modules.strip_custom or {}
            local paths = type(mcfg.paths) == "table" and mcfg.paths or {}
            local out = {}
            for _i, path in ipairs(paths) do
                if type(path) == "string" and path ~= "" then
                    out[#out + 1] = path
                    if #out >= lim then break end
                end
            end
            return out
        end
        if source == "currently_reading" then
            return get_paths_by_status("reading", lim)
        end
        if source == "to_be_read" then
            local tbr = get_tbr_paths()
            local out = {}
            for _i, path in ipairs(tbr) do
                table.insert(out, path)
                if #out >= lim then break end
            end
            return out
        end
        local statuses = { reading = true }
        if opts.filter_unread ~= true then statuses.new = true end
        if opts.filter_tbr ~= true then statuses.abandoned = true end
        if opts.filter_finished ~= true then statuses.complete = true end
        return get_paths_by_statuses(statuses, lim)
    end

    function provider:getFeaturedBook(source_key, order_key)
        local paths = collect_paths_for_source(source_key)
        if source_key ~= "custom_featured" and normalize_order(order_key) == "reverse" then
            paths = reverse_copy(paths)
        end
        local path = paths[1]
        local module_id = featured_widget_for_source(source_key)
        local featured_cfg = dcfg and dcfg.modules and dcfg.modules[module_id] or {}
        local progress_meta = featured_cfg.progress_meta or {}
        local need_time_left = progress_meta.left == "time_left"
            or progress_meta.right == "time_left"
        return get_book(path, need_time_left)
    end

    local function get_strip_paths(source_key, count, order_key, component_id)
        local n = tonumber(count) or 5
        if n < 1 then n = 1 end
        local source = source_key
        if source ~= "custom_strip" and source ~= "currently_reading" and source ~= "to_be_read" then
            source = "recently_read"
        end
        local mcfg = dcfg and dcfg.modules and dcfg.modules[component_id] or {}
        local paths = collect_paths_for_source(source, 5000, {
            filter_unread = source == "recently_read" and mcfg.filter_unread == true,
            filter_tbr = source == "recently_read" and mcfg.filter_tbr == true,
            filter_finished = source == "recently_read" and mcfg.filter_finished == true,
        })

        if source ~= "custom_strip" and normalize_order(order_key) == "reverse" then
            paths = reverse_copy(paths)
        end

        -- Keep strip distinct from featured only when that featured widget is visible.
        local featured_widget_id = featured_widget_for_source(source)
        local should_dedupe_featured = source ~= "custom_strip" and is_widget_visible(featured_widget_id)
        if should_dedupe_featured and #paths > 0 then
            local featured_path = paths[1]
            if featured_path and featured_path ~= "" then
                local filtered = {}
                for _i, path in ipairs(paths) do
                    if path ~= featured_path then
                        filtered[#filtered + 1] = path
                    end
                end
                paths = filtered
            end
        end

        -- Keep strip density stable: when a source has too few items, backfill
        -- with recent valid history so the row can still show 3-5 covers.
        if source == "currently_reading" and #paths < n then
            append_unique_paths(paths, get_history(), n)
        end

        return source, paths, n
    end

    function provider:getBooksForStrip(source_key, count, order_key, component_id)
        local source, paths, n = get_strip_paths(source_key, count, order_key, component_id)

        local offset_key = tostring(component_id or source) .. ":" .. source .. ":" .. normalize_order(order_key)
        local offset = tonumber(strip_offsets[offset_key]) or 0
        if #paths > 0 then
            offset = offset % #paths
            strip_offsets[offset_key] = offset
        else
            offset = 0
        end

        local books = {}
        for i = 1, math.min(n, #paths) do
            local idx = ((offset + i - 1) % #paths) + 1
            local path = paths[idx]
            local book = get_book(path)
            if book then
                table.insert(books, book)
                if #books >= n then break end
            end
        end
        return books
    end

    function provider:shiftStrip(source_key, count, order_key, direction, component_id)
        local source, paths, n = get_strip_paths(source_key, count, order_key, component_id)
        if #paths <= n then return false end
        local offset_key = tostring(component_id or source) .. ":" .. source .. ":" .. normalize_order(order_key)
        local cur = tonumber(strip_offsets[offset_key]) or 0
        local step = direction == "previous" and -n or n
        strip_offsets[offset_key] = (cur + step) % #paths
        if _home_menu and _home_menu._home_rebuild then
            _home_menu:_home_rebuild()
        end
        return true
    end

    function provider:getCurrentQuote()
        local quotes = HomeQuotes.getQuotes()
        local quote_count = #quotes
        if quote_count == 0 then return nil end
        local idx
        local quote_cfg = dcfg.quotes or {}
        if quote_cfg.day_seed == get_quote_day_index() and type(quote_cfg.manual_index) == "number" then
            idx = quote_cfg.manual_index
        else
            idx = get_daily_quote_index()
        end
        if idx < 1 then idx = 1 end
        if idx > quote_count then idx = ((idx - 1) % quote_count) + 1 end
        return quotes[idx]
    end

    local function step_quote(delta)
        local quotes = HomeQuotes.getQuotes()
        local quote_count = #quotes
        if quote_count == 0 then return end
        local quote_cfg = dcfg.quotes or {}
        local current
        if quote_cfg.day_seed == get_quote_day_index() and type(quote_cfg.manual_index) == "number" then
            current = quote_cfg.manual_index
        else
            current = get_daily_quote_index()
        end
        local next_idx = ((current - 1 + delta) % quote_count) + 1
        quote_cfg.manual_index = next_idx
        quote_cfg.day_seed = get_quote_day_index()
        dcfg.quotes = quote_cfg
        save_home_settings(dcfg)
        if _home_menu and _home_menu._home_rebuild then
            _home_menu:_home_rebuild()
        end
    end

    function provider:nextQuote()
        step_quote(1)
    end

    function provider:prevQuote()
        step_quote(-1)
    end

    provider.stats = {}

    function provider:prepareStats(rows, force)
        local fields = collect_stats_fields(rows, dcfg)
        local key = stats_fields_key(fields)
        if key == "" then
            stats_cached = {}
            stats_cached_key = key
            self.stats = stats_cached
            return self.stats
        end
        if force or key ~= stats_cached_key then
            stats_cached = nil
            stats_cached_key = key
        end
        self.stats = get_stats(fields)
        return self.stats
    end

    function provider:refreshStats(rows)
        return self:prepareStats(rows, true)
    end

    function provider:getStats(rows)
        return self:prepareStats(rows, false)
    end

    function provider:clearStats()
        stats_cached = nil
        stats_cached_key = nil
        self.stats = {}
        return self.stats
    end

    return provider
end

local function size_to_px(size, key, pct_key, body_h, fallback)
    local pct = tonumber(size[pct_key])
    if pct then
        return math.max(1, math.floor(body_h * pct + 0.5))
    end
    return tonumber(size[key]) or fallback
end

local function compute_row_heights(rows, body_h)
    local specs = {}
    local total_min = 0

    for _i, comp in ipairs(rows) do
        local size = comp.size or {}
        local pref = size_to_px(size, "preferred", "preferred_pct", body_h, math.floor(body_h * 0.20))
        local min_h = size_to_px(size, "min", "min_pct", body_h, math.max(1, math.floor(pref * 0.55)))
        local max_h = size_to_px(size, "max", "max_pct", body_h, math.max(pref, min_h))
        if max_h < min_h then max_h = min_h end
        if pref < min_h then pref = min_h end
        if pref > max_h then pref = max_h end
        local id = comp.id or ""
        table.insert(specs, {
            id = id,
            is_strip = id == "strip" or id:match("^strip_") ~= nil,
            is_featured = id == "featured" or id:match("^featured_") ~= nil,
            is_datetime = id == "datetime",
            pref = pref,
            min = min_h,
            max = max_h,
            grow_priority = tonumber(size.grow_priority) or 10,
            h = pref,
        })
        total_min = total_min + min_h
    end

    if #specs == 0 then return specs end
    if body_h < #specs then body_h = #specs end

    if total_min > body_h then
        -- When strict mins cannot fit, shrink proportionally so rows stay contained.
        local scale = body_h / total_min
        local total = 0
        for _i, sp in ipairs(specs) do
            sp.h = math.max(1, math.floor(sp.min * scale))
            total = total + sp.h
        end
        local remaining = body_h - total
        local i = 1
        while remaining > 0 and #specs > 0 do
            specs[i].h = specs[i].h + 1
            remaining = remaining - 1
            i = i + 1
            if i > #specs then i = 1 end
        end
        return specs
    end

    local total = 0
    for _i, sp in ipairs(specs) do
        sp.h = sp.pref
        if sp.h < sp.min then sp.h = sp.min end
        if sp.h > sp.max then sp.h = sp.max end
        total = total + sp.h
    end

    local function pick_shrink_candidate(strip_only)
        local best_i = nil
        local best_room = 0
        for i, sp in ipairs(specs) do
            if not strip_only or sp.is_strip then
                local room = sp.h - sp.min
                if room > best_room then
                    best_room = room
                    best_i = i
                end
            end
        end
        return best_i, best_room
    end

    while total > body_h do
        local best_i, best_room = pick_shrink_candidate(true)
        if not best_i or best_room <= 0 then
            best_i, best_room = pick_shrink_candidate(false)
        end
        if not best_i or best_room <= 0 then break end
        specs[best_i].h = specs[best_i].h - 1
        total = total - 1
    end

    local grow_priorities = {}
    local seen_priority = {}
    for _i, sp in ipairs(specs) do
        local pri = tonumber(sp.grow_priority) or 10
        if not seen_priority[pri] then
            seen_priority[pri] = true
            grow_priorities[#grow_priorities + 1] = pri
        end
    end
    table.sort(grow_priorities)
    for _i, pri in ipairs(grow_priorities) do
        if total >= body_h then break end
        while total < body_h do
            local grew = false
            for _j, sp in ipairs(specs) do
                if total >= body_h then break end
                if (tonumber(sp.grow_priority) or 10) == pri and sp.h < sp.max then
                    sp.h = sp.h + 1
                    total = total + 1
                    grew = true
                end
            end
            if not grew then break end
        end
    end

    return specs
end

local function grow_row_heights_by_priority(row_heights, extra_px)
    local remaining = tonumber(extra_px) or 0
    local grown = 0
    if remaining <= 0 then
        return grown
    end
    local priorities = {}
    local seen = {}
    for _i, row in ipairs(row_heights) do
        local pri = tonumber(row.grow_priority) or 10
        if not seen[pri] then
            seen[pri] = true
            priorities[#priorities + 1] = pri
        end
    end
    table.sort(priorities)
    for _i, pri in ipairs(priorities) do
        if remaining <= 0 then break end
        while remaining > 0 do
            local grew = false
            for _j, row in ipairs(row_heights) do
                if remaining <= 0 then break end
                if (tonumber(row.grow_priority) or 10) == pri then
                    local max_h = tonumber(row.max) or tonumber(row.h) or 0
                    local cur_h = tonumber(row.h) or 0
                    if cur_h < max_h then
                        row.h = cur_h + 1
                        remaining = remaining - 1
                        grown = grown + 1
                        grew = true
                    end
                end
            end
            if not grew then break end
        end
    end
    return grown
end

local function paint_focus_rect(bb, x, y, w, h)
    if not (bb and x and y and w and h and w > 2 and h > 2) then return end
    local t = 2
    for i = 0, t - 1 do
        bb:paintRect(x + i, y + i, w - i * 2, 1, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x + i, y + h - 1 - i, w - i * 2, 1, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x + i, y + i, 1, h - i * 2, Blitbuffer.COLOR_BLACK)
        bb:paintRect(x + w - 1 - i, y + i, 1, h - i * 2, Blitbuffer.COLOR_BLACK)
    end
end

local function sort_home_focus_targets(menu)
    local targets = menu and menu._zen_home_focus_targets
    if type(targets) ~= "table" then return end
    table.sort(targets, function(a, b)
        local ar = tonumber(a.row_order) or 0
        local br = tonumber(b.row_order) or 0
        if ar ~= br then return ar < br end
        local ac = tonumber(a.col) or 0
        local bc = tonumber(b.col) or 0
        if ac ~= bc then return ac < bc end
        return (tonumber(a.seq) or 0) < (tonumber(b.seq) or 0)
    end)
    for i, target in ipairs(targets) do
        target.index = i
    end
end

local function register_home_focus_target(menu, target)
    if not (menu and type(target) == "table") then return target end
    menu._zen_home_focus_targets = menu._zen_home_focus_targets or {}
    menu._zen_home_focus_seq = (menu._zen_home_focus_seq or 0) + 1
    target.seq = menu._zen_home_focus_seq
    target.id = target.id or target.seq
    target.key = target.key or ("target:" .. tostring(target.id))
    table.insert(menu._zen_home_focus_targets, target)
    return target
end

local function wrap_home_focus_target(menu, target, widget)
    if not (menu and target and widget) then return widget end
    local FrameContainer = require("ui/widget/container/framecontainer")
    local size = widget.getSize and widget:getSize() or nil
    local width = tonumber(target.width) or (size and size.w) or 1
    local height = tonumber(target.height) or (size and size.h) or 1
    target.width = width
    target.height = height
    register_home_focus_target(menu, target)

    local frame = FrameContainer:new{
        width = width,
        height = height,
        padding = 0,
        bordersize = 0,
        background = home_frame_bg(),
        widget,
    }
    local orig_paintTo = frame.paintTo
    frame.paintTo = function(self, bb, x, y)
        orig_paintTo(self, bb, x, y)
        if menu._zen_home_focus_id == target.id then
            paint_focus_rect(bb, x, y, self:getSize().w, self:getSize().h)
        end
    end
    target.widget = frame
    return frame
end

local function find_home_focus_index(menu, key)
    if not (menu and key and type(menu._zen_home_focus_targets) == "table") then return nil end
    for i, target in ipairs(menu._zen_home_focus_targets) do
        if target.key == key then return i end
    end
end

local function set_home_focus(menu, index)
    local targets = menu and menu._zen_home_focus_targets
    if type(targets) ~= "table" or #targets == 0 then return false end
    if index < 1 then index = 1 end
    if index > #targets then index = #targets end
    local target = targets[index]
    if not target then return false end
    menu._zen_home_focus_suspended = false
    menu._zen_home_focus_index = index
    menu._zen_home_focus_id = target.id
    menu._zen_home_focus_key = target.key
    require("ui/uimanager"):setDirty(menu, "ui")
    return true
end

local function clear_home_focus(menu, suspended)
    if not menu then return end
    menu._zen_home_focus_index = nil
    menu._zen_home_focus_id = nil
    menu._zen_home_focus_suspended = suspended == true
    require("ui/uimanager"):setDirty(menu, "ui")
end

local function get_home_focus_target(menu)
    local targets = menu and menu._zen_home_focus_targets
    local index = menu and menu._zen_home_focus_index
    if type(targets) ~= "table" or type(index) ~= "number" then return nil end
    return targets[index]
end

local function move_home_focus(menu, dx, dy)
    local targets = menu and menu._zen_home_focus_targets
    if type(targets) ~= "table" or #targets == 0 then return false end
    if menu._zen_home_focus_suspended then return false end
    local current = get_home_focus_target(menu)
    if not current then
        return set_home_focus(menu, dy and dy < 0 and #targets or 1)
    end

    local best_i, best_score
    local cur_row = tonumber(current.row_order) or 0
    local cur_col = tonumber(current.col) or 0
    if dy and dy ~= 0 then
        for i, target in ipairs(targets) do
            local row = tonumber(target.row_order) or 0
            if (dy > 0 and row > cur_row) or (dy < 0 and row < cur_row) then
                local col = tonumber(target.col) or 0
                local score = math.abs(col - cur_col) + math.abs(row - cur_row) * 100
                if not best_score or score < best_score then
                    best_i, best_score = i, score
                end
            end
        end
    elseif dx and dx ~= 0 then
        for i, target in ipairs(targets) do
            local row = tonumber(target.row_order) or 0
            local col = tonumber(target.col) or 0
            if row == cur_row and ((dx > 0 and col > cur_col) or (dx < 0 and col < cur_col)) then
                local score = math.abs(col - cur_col)
                if not best_score or score < best_score then
                    best_i, best_score = i, score
                end
            end
        end
        if not best_i then
            best_i = current.index + dx
            if best_i < 1 or best_i > #targets then best_i = nil end
        end
    end
    if best_i then return set_home_focus(menu, best_i) end
    return false
end

local function activate_home_focus(menu)
    local target = get_home_focus_target(menu)
    if not target then return false end
    if type(target.activate) == "function" then
        target.activate()
    end
    return true
end

local function context_home_focus(menu)
    local target = get_home_focus_target(menu)
    if not target then return false end
    if type(target.context) == "function" then
        target.context()
    end
    return true
end

local function install_home_key_handlers(menu)
    if not menu or menu._zen_home_key_patched then return end
    menu._zen_home_key_patched = true
    local UIManager = require("ui/uimanager")
    local HOLD_DELAY = 0.4
    local hold_fn = nil
    local hold_key = nil

    local function cancel_hold()
        if hold_fn then
            UIManager:unschedule(hold_fn)
            hold_fn = nil
            local key = hold_key
            hold_key = nil
            return key
        end
        hold_key = nil
    end

    local function start_hold(m, key)
        cancel_hold()
        hold_key = key
        hold_fn = function()
            hold_fn = nil
            hold_key = nil
            context_home_focus(m)
        end
        UIManager:scheduleIn(HOLD_DELAY, hold_fn)
    end

    local function home_move_or_focus(m, dx, dy)
        if move_home_focus(m, dx, dy) then return true end
        return false
    end

    local function delegate_to_navbar(m, callback, ...)
        local handled = callback and callback(m, ...)
        if handled then
            clear_home_focus(m, true)
        end
        return handled
    end

    menu.key_events = menu.key_events or {}
    menu.key_events.LeftButtonTap = {
        { "Menu" },
        event = "ZenHomeContext",
    }
    menu.key_events.ZenHomeContext = {
        { "Menu" },
        event = "ZenHomeContext",
    }

    function menu:onZenHomeContext()
        if not get_home_focus_target(self) then
            return set_home_focus(self, 1)
        end
        return context_home_focus(self)
    end

    local orig_left = menu.onZenNavbarFocusLeft
    function menu:onZenNavbarFocusLeft()
        if self._zen_home_focus_suspended then
            return orig_left and orig_left(self)
        end
        if home_move_or_focus(self, -1, 0) then return true end
        return delegate_to_navbar(self, orig_left)
    end

    local orig_right = menu.onZenNavbarFocusRight
    function menu:onZenNavbarFocusRight()
        if self._zen_home_focus_suspended then
            return orig_right and orig_right(self)
        end
        if home_move_or_focus(self, 1, 0) then return true end
        return delegate_to_navbar(self, orig_right)
    end

    local orig_up = menu.onZenNavbarFocusUp
    function menu:onZenNavbarFocusUp()
        if self._zen_home_focus_suspended then
            local handled = orig_up and orig_up(self)
            if handled then
                self._zen_home_focus_suspended = false
                return set_home_focus(self, #(self._zen_home_focus_targets or {}))
            end
            return handled
        end
        if home_move_or_focus(self, 0, -1) then return true end
        return delegate_to_navbar(self, orig_up)
    end

    local orig_down = menu.onZenNavbarFocusDown
    function menu:onZenNavbarFocusDown()
        if self._zen_home_focus_suspended then
            return orig_down and orig_down(self)
        end
        if home_move_or_focus(self, 0, 1) then return true end
        return delegate_to_navbar(self, orig_down)
    end

    local orig_confirm = menu.onZenNavbarConfirm
    function menu:onZenNavbarConfirm()
        if self._zen_home_focus_suspended then
            return orig_confirm and orig_confirm(self)
        end
        if activate_home_focus(self) then return true end
        return orig_confirm and orig_confirm(self)
    end

    local orig_focus_move = menu.onFocusMove
    menu.onFocusMove = function(m, args)
        local dx = args and args[1] or 0
        local dy = args and args[2] or 0
        if m._zen_home_focus_suspended and dy == -1 then
            local handled = orig_focus_move and orig_focus_move(m, args)
            if handled then
                m._zen_home_focus_suspended = false
                return set_home_focus(m, #(m._zen_home_focus_targets or {}))
            end
            return handled
        end
        if not m._zen_home_focus_suspended and home_move_or_focus(m, dx, dy) then return true end
        local handled = orig_focus_move and orig_focus_move(m, args)
        if handled and dy == 1 then clear_home_focus(m, true) end
        return handled
    end

    local orig_key_press = menu.onKeyPress
    menu.onKeyPress = function(m, key)
        if m._zen_home_focus_suspended and key == "Up" then
            local handled = orig_key_press and orig_key_press(m, key)
            if handled then
                m._zen_home_focus_suspended = false
                return set_home_focus(m, #(m._zen_home_focus_targets or {}))
            end
            return handled
        end
        if key == "Left" and home_move_or_focus(m, -1, 0) then return true end
        if key == "Right" and home_move_or_focus(m, 1, 0) then return true end
        if key == "Up" and home_move_or_focus(m, 0, -1) then return true end
        if key == "Down" and home_move_or_focus(m, 0, 1) then return true end
        if (key == "Press" or key == "Return") and get_home_focus_target(m) then
            start_hold(m, key)
            return true
        end
        local handled = orig_key_press and orig_key_press(m, key)
        if handled and key == "Down" then clear_home_focus(m, true) end
        return handled
    end

    local orig_key_release = menu.onKeyRelease
    menu.onKeyRelease = function(m, key)
        if (key == "Press" or key == "Return") and hold_key == key then
            cancel_hold()
            activate_home_focus(m)
            return true
        end
        return orig_key_release and orig_key_release(m, key)
    end
end

local function build_home_content(menu, dcfg, rows, data_provider)
    local Device = require("device")
    local Screen = Device.screen
    local Geom = require("ui/geometry")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local TextWidget = require("ui/widget/textwidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local Font = require("ui/font")

    local prev_focus_key = menu._zen_home_focus_key
    menu._zen_home_focus_targets = {}
    menu._zen_home_focus_seq = 0
    menu._zen_home_focus_index = nil
    menu._zen_home_focus_id = nil

    local show_status_bar = dcfg.show_status_bar ~= false
    local tb = menu.title_bar
    local tb_h = show_status_bar and tb and tb:getSize().h or 0
    local menu_h = menu.height or (menu.inner_dimen and menu.inner_dimen.h or menu.dimen.h)
    local body_h = menu_h - tb_h
    local navbar_h = tonumber(rawget(_G, "__ZEN_UI_NAVBAR_HEIGHT")) or 0
    local hard_body_h = Screen:getHeight() - tb_h - navbar_h
    if hard_body_h < 1 then hard_body_h = Screen:getHeight() - tb_h end
    if body_h < 1 then body_h = hard_body_h end
    if body_h > hard_body_h then body_h = hard_body_h end
    local body_w = menu.inner_dimen and menu.inner_dimen.w or Screen:getWidth()
    local side_pad = math.max(2, math.min(Screen:scaleBySize(8), math.floor(body_w * 0.025)))
    if side_pad * 2 >= body_w then
        side_pad = math.max(0, math.floor(body_w * 0.04))
    end
    local content_w = math.max(1, body_w - side_pad * 2)
    local right_pad = math.max(0, body_w - content_w - side_pad)
    local page_pad = 0
    local layout_h = math.max(1, body_h - page_pad * 2)
    local row_gap = 0
    local max_row_gap = 0
    if #rows > 1 then
        local base_gap = math.max(4, Screen:scaleBySize(8))
        local max_gaps_h = math.floor(layout_h * 0.08)
        row_gap = math.min(base_gap, math.floor(max_gaps_h / (#rows - 1)))
        max_row_gap = math.max(row_gap, Screen:scaleBySize(10))
    end
    local gaps_h = row_gap * math.max(0, #rows - 1)
    local rows_h_budget = layout_h - gaps_h
    if rows_h_budget < #rows then rows_h_budget = math.max(1, layout_h) end

    local row_heights = compute_row_heights(rows, rows_h_budget)
    local rows_h_used = 0
    for _i, row in ipairs(row_heights) do
        rows_h_used = rows_h_used + (row.h or 0)
    end
    local extra_spacing_h = rows_h_budget - rows_h_used
    if extra_spacing_h > 0 then
        local grown = grow_row_heights_by_priority(row_heights, extra_spacing_h)
        extra_spacing_h = extra_spacing_h - grown
    end
    if extra_spacing_h > 0 and #rows > 1 and row_gap < max_row_gap then
        local gap_room = max_row_gap - row_gap
        local add_each = math.floor(extra_spacing_h / (#rows - 1))
        if add_each > gap_room then add_each = gap_room end
        if add_each > 0 then
            row_gap = row_gap + add_each
            extra_spacing_h = extra_spacing_h - add_each * (#rows - 1)
        end
    end
    local extra_top_pad = 0
    if extra_spacing_h > 0 then extra_top_pad = math.floor(extra_spacing_h / 2) end

    local face_title = Font:getFace("smallinfofont", Screen:scaleBySize(24))
    local face_value = Font:getFace("smallinfofont", Screen:scaleBySize(20))
    local face_label = Font:getFace("smallinfofont", Screen:scaleBySize(16))
    local row_title_face = Font:getFace("smallinfofont", Screen:scaleBySize(13))
    local row_title_gap = Screen:scaleBySize(3)

    local FileManager = require("apps/filemanager/filemanager")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")

    local function open_book(path)
        if not path then return end
        local fm = FileManager.instance
        if filemanagerutil.openFile then
            filemanagerutil.openFile(fm, path)
        elseif fm and type(fm.openFile) == "function" then
            fm:openFile(path)
        end
    end

    local function show_book_context_menu(path, source)
        if type(path) ~= "string" or path == "" then return false end
        local fm = FileManager.instance
        local fc = fm and fm.file_chooser
        if not (fc and type(fc.showFileDialog) == "function") then return false end
        fc:showFileDialog({
            path = path,
            is_file = true,
            _zen_home_context = true,
            _zen_disable_select = true,
            _zen_is_history = source == "recently_read",
            _zen_after_status_change = function(changed_path)
                invalidate_home_book_cache(changed_path)
                M.rebuildActive()
            end,
        })
        return true
    end

    local function shift_strip(source_key, count, order_key, direction, component_id)
        if not (data_provider and type(data_provider.shiftStrip) == "function") then return false end
        return data_provider:shiftStrip(source_key, count, order_key, direction, component_id)
    end

    local top_tap_zone_h = math.max(1, math.floor(Screen:getHeight() * 0.05))
    local function open_top_menu(ges)
        if not (ges and ges.pos and ges.pos.y < top_tap_zone_h) then return false end
        local fm = FileManager.instance
        local fm_menu = fm and fm.menu
        if fm_menu and fm_menu.activation_menu ~= "swipe" then
            fm_menu:onShowMenu(fm_menu:_getTabIndexFromLocation(ges))
            return true
        end
        return false
    end

    local children = { align = "left" }
    local used_h = 0
    local top_pad = page_pad + extra_top_pad
    menu._zen_home_clock_refreshers = {}
    if top_pad > 0 then
        table.insert(children, VerticalSpan:new{ width = top_pad })
        used_h = used_h + top_pad
    end

    local function title_for_component(comp_id)
        return MODULE_TITLES[comp_id]
    end

    for i, comp in ipairs(rows) do
        local h = row_heights[i] and row_heights[i].h or 120
        local module_cfg = type(dcfg.modules) == "table" and dcfg.modules[comp.id] or nil
        local show_row_title = not (module_cfg and module_cfg.show_module_title == false)
        local row_title = title_for_component(comp.id) or comp.title or comp.label or ""
        local row_focus_base = i * 10
        local row_focus_actions = {}
        local title_h = 0
        local title_widget = nil
        if show_row_title and row_title ~= "" then
            title_widget = TextWidget:new{ text = row_title, face = row_title_face, bold = true }
            title_h = title_widget:getSize().h
        end
        local content_h = h
        local title_gap_h = title_h > 0 and row_title_gap or 0
        if title_widget then
            local reserved = title_h + title_gap_h
            if h > reserved + 20 then
                content_h = h - reserved
            else
                -- Hide row title when space is constrained, so widget content fits.
                title_widget = nil
                title_h = 0
                title_gap_h = 0
                content_h = h
            end
        end
        if content_h < 1 then content_h = 1 end
        local row_ctx = {
            width = content_w,
            height = content_h,
            menu = menu,
            config = dcfg,
            data = data_provider,
            openBook = open_book,
            showBookMenu = show_book_context_menu,
            shiftStrip = shift_strip,
            openTopMenu = open_top_menu,
            buildStatusRow = _zen_shared and _zen_shared.buildStatusRow,
            registerClockRefresh = function(refresh)
                if type(refresh) == "function" then
                    table.insert(menu._zen_home_clock_refreshers, refresh)
                end
            end,
            setWidgetActions = function(actions)
                row_focus_actions = type(actions) == "table" and actions or {}
            end,
            registerHomeFocusTarget = function(target, widget)
                if not target then return widget end
                target.row_order = tonumber(target.row_order) or row_focus_base + (tonumber(target.subrow) or 1)
                target.col = tonumber(target.col) or 1
                target.key = target.key or (comp.id .. ":" .. tostring(target.row_order) .. ":" .. tostring(target.col))
                return wrap_home_focus_target(menu, target, widget)
            end,
            face_title = face_title,
            face_value = face_value,
            face_label = face_label,
            component_id = comp.id,
            module_cfg = module_cfg,
            is_first_row = i == 1,
        }
        local ok_widget, widget = pcall(comp.build, row_ctx)
        if ok_widget and widget then
            local final_widget = widget
            if title_widget then
                final_widget = VerticalGroup:new{
                    align = "left",
                    LeftContainer:new{
                        dimen = Geom:new{ w = content_w, h = title_h },
                        title_widget,
                    },
                    VerticalSpan:new{ width = title_gap_h },
                    widget,
                }
            end
            final_widget = wrap_home_focus_target(menu, {
                key = "widget:" .. tostring(comp.id),
                row_order = row_focus_base,
                col = 0,
                width = content_w,
                height = h,
                activate = row_focus_actions.activate,
                context = row_focus_actions.context,
            }, final_widget)
            table.insert(children, FrameContainer:new{
                width = content_w,
                height = h,
                padding = 0,
                bordersize = 0,
                background = home_frame_bg(),
                final_widget,
            })
            used_h = used_h + h
        else
            logger.warn("zen-ui home: failed to build component:", comp.id, widget)
        end
        if row_gap > 0 and i < #rows then
            table.insert(children, VerticalSpan:new{ width = row_gap })
            used_h = used_h + row_gap
        end
    end

    if used_h < body_h then
        table.insert(children, VerticalSpan:new{ width = body_h - used_h })
    end

    sort_home_focus_targets(menu)
    local restore_i = find_home_focus_index(menu, prev_focus_key)
    if restore_i then
        set_home_focus(menu, restore_i)
    end

    return HorizontalGroup:new{
        HorizontalSpan:new{ width = side_pad },
        FrameContainer:new{
            width = content_w,
            height = body_h,
            padding = 0,
            bordersize = 0,
            background = home_frame_bg(),
            VerticalGroup:new(children),
        },
        HorizontalSpan:new{ width = right_pad },
    }
end

local function rows_have_clock_refreshers(rows, dcfg)
    local modules = type(dcfg) == "table" and type(dcfg.modules) == "table" and dcfg.modules or {}
    for _i, comp in ipairs(rows or {}) do
        if comp.id == "datetime" then
            return true
        end
        if comp.id == "featured_recent" or comp.id == "featured_custom" or comp.id == "featured_tbr" then
            local mcfg = modules[comp.id]
            if type(mcfg) == "table" and mcfg.show_status_bar == true then
                return true
            end
        end
    end
    return false
end

-- Stats (today/streak/week) and the daily quote both depend on the current
-- date and go stale after a wakeup that crossed midnight.
local function rows_have_date_dependent(rows)
    for _i, comp in ipairs(rows or {}) do
        if comp.id == "stats_triplet" or comp.id == "reading_goals"
                or comp.id == "quotes" then
            return true
        end
    end
    return false
end

function M.showHomeView(injectNavbar)
    local UIManager = require("ui/uimanager")

    refresh_shared_state()
    _home_inject_navbar = injectNavbar
    local last_read_file = rawget(_G, "__ZEN_UI_LAST_READ_FILE")
    if last_read_file then
        _G.__ZEN_UI_LAST_READ_FILE = nil
        invalidate_home_book_cache(last_read_file)
    end
    local cfg = load_zen_config()
    if type(cfg) ~= "table" then return end
    local dcfg = ensure_home_cfg()
    local show_status_bar = dcfg.show_status_bar ~= false

    local menu = StandalonePage.create_menu{
        name = "home",
        title = " ",
        no_title = not show_status_bar,
        block_filemanager_horizontal_swipe = true,
    }
    StandalonePage.prepare_shell(menu)

    local createStatusRow = _zen_shared and _zen_shared.createStatusRow
    local createStatusRowCustomBack = _zen_shared and _zen_shared.createStatusRowCustomBack
    local repaintTitleBar = _zen_shared and _zen_shared.repaintTitleBar
    if show_status_bar then
        StandalonePage.apply_status_row(menu, {
            createStatusRow = createStatusRow,
            createStatusRowCustomBack = createStatusRowCustomBack,
            repaintTitleBar = repaintTitleBar,
        })
    end
    menu._zen_home_show_status_bar = show_status_bar

    local rows = resolve_rows(dcfg)
    local data_provider = build_data_provider(cfg, dcfg)
    local has_clock_refreshers = rows_have_clock_refreshers(rows, dcfg)
    local has_date_dependent = rows_have_date_dependent(rows)
    menu._zen_home_has_clock_refreshers = has_clock_refreshers

    local function rebuild(refresh_stats)
        if data_provider then
            if type(data_provider.prepareStats) == "function" then
                data_provider:prepareStats(rows, refresh_stats == true)
            elseif refresh_stats and type(data_provider.refreshStats) == "function" then
                data_provider:refreshStats(rows)
            end
        end
        local content = build_home_content(menu, dcfg, rows, data_provider)
        StandalonePage.mount_body(menu, content)
        UIManager:setDirty(menu, "ui")
    end

    function menu:_zen_home_refresh_clock_widgets()
        if self._zen_home_closing then return end
        local refreshed = 0
        for _i, refresh in ipairs(self._zen_home_clock_refreshers or {}) do
            if type(refresh) == "function" then
                local ok, did_refresh = pcall(refresh)
                if ok and did_refresh then
                    refreshed = refreshed + 1
                elseif not ok then
                    logger.warn("zen-ui home: embedded clock refresh failed:", tostring(did_refresh))
                end
            end
        end
        if refreshed > 0 then
            UIManager:setDirty(self, "ui")
        end
    end

    local function refresh_home_clock_widgets_if_top()
        if menu._zen_home_closing or not rawequal(_home_menu, menu) then return end
        local stack = UIManager._window_stack
        local top = stack and stack[#stack]
        if not top or top.widget ~= menu then return end
        if menu._zen_home_refresh_clock_widgets then
            menu:_zen_home_refresh_clock_widgets()
        end
    end

    -- Date-dependent content (stats, daily quote) goes stale after a wakeup
    -- that crossed midnight. Force a stats re-query + rebuild when the home
    -- page is on top.
    local function refresh_home_date_dependent_if_top()
        if menu._zen_home_closing or not rawequal(_home_menu, menu) then return end
        local stack = UIManager._window_stack
        local top = stack and stack[#stack]
        if not top or top.widget ~= menu then return end
        rebuild(true)
    end

    if show_status_bar then
        local status_refresh = menu._zen_status_refresh
        menu._zen_status_refresh = function(self, ...)
            local target = type(self) == "table" and self or menu
            if status_refresh then
                status_refresh(target, ...)
            end
            if target and target._zen_home_refresh_clock_widgets then
                target:_zen_home_refresh_clock_widgets()
            end
        end
    else
        menu._zen_status_refresh = nil
    end
    if not show_status_bar and has_clock_refreshers then
        -- Featured embedded status bar drives its own minute heartbeat via this
        -- bind. Flag it so the FileManager dispatcher skips clock-tick refreshes
        -- (avoids a double refresh) while still serving event-driven refreshes
        -- like Wi-Fi toggle / TouchMenu close.
        menu._zen_status_clock_bound = true
        pcall(function()
            require("common/clock_timer").bind(menu, function(target)
                if target and target._zen_home_refresh_clock_widgets then
                    target:_zen_home_refresh_clock_widgets()
                end
            end)
        end)
    end

    local resume_refreshes_clock = not show_status_bar and has_clock_refreshers
    if resume_refreshes_clock or has_date_dependent then
        local orig_onResume = menu.onResume
        function menu:onResume(...)
            local result
            if orig_onResume then
                result = orig_onResume(self, ...)
            end
            if resume_refreshes_clock then
                UIManager:scheduleIn(0.5, refresh_home_clock_widgets_if_top)
                UIManager:scheduleIn(1.5, refresh_home_clock_widgets_if_top)
            end
            if has_date_dependent then
                UIManager:scheduleIn(0.5, refresh_home_date_dependent_if_top)
            end
            return result
        end
    end

    if not show_status_bar and has_clock_refreshers then
        -- Charging events arrive in pairs during USB negotiation (NotCharging ->
        -- Charging) within a few seconds. Debounce into one refresh 1.5 s after
        -- the last event so an embedded featured status bar shows the charging
        -- indicator without waiting for the next minute clock tick.
        local charging_refresh_timer = nil
        local function scheduleChargingRefresh()
            if charging_refresh_timer then
                UIManager:unschedule(charging_refresh_timer)
            end
            charging_refresh_timer = function()
                charging_refresh_timer = nil
                refresh_home_clock_widgets_if_top()
            end
            UIManager:scheduleIn(1.5, charging_refresh_timer)
        end

        local function hookCharging(event_name)
            local orig = menu[event_name]
            menu[event_name] = function(self, ...)
                local result
                if orig then result = orig(self, ...) end
                scheduleChargingRefresh()
                return result
            end
        end
        hookCharging("onCharging")
        hookCharging("onNotCharging")

        -- Wifi state changes: refresh so an embedded featured status bar updates
        -- its wifi indicator without waiting for the next minute clock tick.
        local function hookNetwork(event_name)
            local orig = menu[event_name]
            menu[event_name] = function(self, ...)
                local result
                if orig then result = orig(self, ...) end
                refresh_home_clock_widgets_if_top()
                return result
            end
        end
        hookNetwork("onNetworkConnected")
        hookNetwork("onNetworkDisconnected")

        local orig_onSuspend = menu.onSuspend
        function menu:onSuspend(...)
            if charging_refresh_timer then
                UIManager:unschedule(charging_refresh_timer)
                charging_refresh_timer = nil
            end
            if orig_onSuspend then return orig_onSuspend(self, ...) end
        end
    end

    function menu:_home_rebuild(refresh_stats, reload_config)
        if self._zen_home_closing then return end
        refresh_shared_state()
        if reload_config == true then
            local next_cfg = load_zen_config()
            if type(next_cfg) == "table" then
                cfg = next_cfg
                dcfg = ensure_home_cfg()
                data_provider = build_data_provider(cfg, dcfg)
            end
        end
        rows = resolve_rows(dcfg)
        has_clock_refreshers = rows_have_clock_refreshers(rows, dcfg)
        self._zen_home_has_clock_refreshers = has_clock_refreshers
        rebuild(refresh_stats == true)
    end

    menu.close_callback = function()
        if menu._zen_home_closing then return end
        menu._zen_home_closing = true
        if rawequal(_home_menu, menu) then
            _home_menu = nil
        end
        UIManager:close(menu)
    end

    local orig_onCloseWidget = menu.onCloseWidget
    function menu:onCloseWidget(...)
        self._zen_home_closing = true
        if rawequal(_home_menu, self) then
            _home_menu = nil
        end
        pcall(function()
            require("common/clock_timer").unbind(self)
        end)
        if self.item_group and type(self.item_group.free) == "function" then
            WidgetResources.free(self.item_group)
            while #self.item_group > 0 do table.remove(self.item_group) end
        end
        if orig_onCloseWidget then
            return orig_onCloseWidget(self, ...)
        end
    end

    _home_menu = menu

    if injectNavbar then
        injectNavbar(menu, "home")
    end
    install_home_key_handlers(menu)

    UIManager:show(menu)
    UIManager:nextTick(function()
        rebuild(true)
        if menu._zen_status_refresh then
            menu:_zen_status_refresh()
        end
    end)
end

function M.getActivePage()
    return _home_menu and (_home_menu.page or 1)
end

function M.invalidateBookCache(path)
    invalidate_home_book_cache(path)
end

function M.rebuildActive()
    if _home_menu and _home_menu._home_rebuild then
        local cfg = load_zen_config()
        local dcfg = type(cfg) == "table" and ensure_home_cfg() or nil
        local show_status_bar = not dcfg or dcfg.show_status_bar ~= false
        local has_clock_refreshers = false
        if dcfg then
            local active_rows = resolve_rows(dcfg)
            has_clock_refreshers = rows_have_clock_refreshers(active_rows, dcfg)
        end
        if _home_menu._zen_home_show_status_bar ~= show_status_bar
                or (not show_status_bar
                    and _home_menu._zen_home_has_clock_refreshers ~= has_clock_refreshers) then
            local UIManager = require("ui/uimanager")
            local old_menu = _home_menu
            _home_menu = nil
            old_menu._zen_home_closing = true
            UIManager:close(old_menu)
            M.showHomeView(_home_inject_navbar)
            return true
        end
        _home_menu:_home_rebuild(true, true)
        return true
    end
    return false
end

function M.refreshDateDependentActive()
    if not (M.isActiveOnTop() and _home_menu and _home_menu._home_rebuild) then
        return false
    end
    local cfg = load_zen_config()
    local dcfg = type(cfg) == "table" and ensure_home_cfg() or nil
    if not dcfg or not rows_have_date_dependent(resolve_rows(dcfg)) then
        return false
    end
    _home_menu:_home_rebuild(true)
    return true
end

function M.hasActive()
    return _home_menu ~= nil
end

function M.isActiveOnTop()
    if not _home_menu then return false end
    local UIManager = require("ui/uimanager")
    local stack = UIManager._window_stack
    local top = stack and stack[#stack]
    return top and top.widget == _home_menu
end

function M.closeAll()
    local menu = _home_menu
    if menu then
        local UIManager = require("ui/uimanager")
        _home_menu = nil
        if not menu._zen_home_closing then
            menu._zen_home_closing = true
            UIManager:close(menu)
        end
    end
end

Registry.setRefreshCallback(M.rebuildActive)

local function register_home_api(zen_plugin)
    if not zen_plugin or type(zen_plugin.config) ~= "table" then return end
    _zen_shared = SharedState.register(zen_plugin, { home = M })
    _zen_plugin = zen_plugin
end

SharedState.registerLoader("home", register_home_api)

return function()
    register_home_api(rawget(_G, "__ZEN_UI_PLUGIN"))
end

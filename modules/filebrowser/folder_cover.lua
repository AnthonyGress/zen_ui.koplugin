-- Shared folder/group cover provider for Zen's mosaic and list renderers.
local CoverUtils = require("common/cover_utils")
local CoverWidget = require("modules/filebrowser/patches/home/widgets/cover_common")
local lfs = require("libs/libkoreader-lfs")
local now = require("common/zen_logger").now

local M = {}
local Blitbuffer, Screen, Size
local DESCRIPTOR_CACHE_MAX = 32
local HISTORY_CACHE_TTL_S = 2
local DOC_EXTENSIONS = {
    azw = true, azw3 = true, cb7 = true, cbr = true, cbz = true, chm = true,
    djv = true, djvu = true, doc = true, docx = true, epub = true, epub3 = true,
    fb2 = true, fb3 = true, html = true, htm = true, kpub = true, md = true,
    mobi = true, odt = true, pdf = true, pdb = true, prc = true, rtf = true,
    txt = true, xhtml = true, zip = true,
}
local descriptor_cache = { values = {}, order = {} }
local history_cache
local count_entries

local METADATA_COLLATES = {
    authors = true,
    keywords = true,
    series = true,
    title = true,
    title_natural = true,
}
local NO_METADATA = "\u{FFFF}"

local function history_revision()
    local ok, ReadHistory = pcall(require, "readhistory")
    if not ok or type(ReadHistory) ~= "table" then return "none" end
    local first = type(ReadHistory.hist) == "table" and ReadHistory.hist[1]
    return table.concat({
        tostring(ReadHistory.last_read_time or 0),
        tostring(type(ReadHistory.hist) == "table" and #ReadHistory.hist or 0),
        tostring(first and first.file or ""),
        tostring(first and first.time or 0),
    }, "\30")
end

local function history_snapshot()
    local checked_at = now()
    local revision = history_revision()
    if history_cache and history_cache.revision == revision
            and checked_at - history_cache.loaded_at < HISTORY_CACHE_TTL_S then
        return history_cache.value, revision
    end
    local HistoryIndex = require("common/history_index")
    local paths = require("common/paths")
    local value = HistoryIndex.load(paths.normPath)
    revision = history_revision()
    history_cache = { value = value, revision = revision, loaded_at = checked_at }
    return value, revision
end

local function sort_policy(menu, path)
    local settings = rawget(_G, "G_reader_settings")
    local override_api = rawget(_G, "__ZEN_FOLDER_SORT")
    local override = override_api and type(override_api.get) == "function"
        and override_api.get(path) or nil
    local collate_id = type(override) == "table" and override.collate
        or (settings and type(settings.readSetting) == "function"
            and settings:readSetting("collate", "strcoll") or "strcoll")
    local reverse = type(override) == "table" and override.reverse == true
        or (not override and settings and type(settings.isTrue) == "function"
            and settings:isTrue("reverse_collate") or false)
    local collate = menu and menu.collates and menu.collates[collate_id]
    if not collate and menu and type(menu.getCollate) == "function" then
        local ok, fallback, fallback_id = pcall(menu.getCollate, menu)
        if ok then
            collate = fallback
            collate_id = fallback_id or collate_id
        end
    end
    return collate_id or "strcoll", reverse, collate
end

local function elapsed_ms(started_at)
    return (now() - started_at) * 1000
end

local function descriptor_key(menu, path)
    local settings = rawget(_G, "G_reader_settings")
    local collate, reverse = sort_policy(menu, path)
    local mixed = settings and type(settings.isTrue) == "function"
        and settings:isTrue("collate_mixed") or false
    local history_generation = collate == "access"
        and select(2, history_snapshot()) or ""
    return table.concat({
        tostring(path),
        tostring(lfs.attributes(path, "modification") or 0),
        tostring(collate), tostring(reverse), tostring(mixed),
        tostring(history_generation),
        tostring(menu and menu.show_hidden),
        tostring(menu and menu.show_filter and menu.show_filter.status),
    }, "\30")
end

local function sort_metadata(path)
    local ok, db_bookinfo = pcall(require, "common/db_bookinfo")
    if not ok or type(db_bookinfo.getLightMetadata) ~= "function" then return {} end
    local loaded, metadata = pcall(db_bookinfo.getLightMetadata, path)
    return loaded and type(metadata) == "table" and metadata or {}
end

local function fallback_doc_props(item)
    local title = item.text:gsub("%.[^%.]+$", "")
    return {
        display_title = title,
        title = title,
        authors = NO_METADATA,
        series = NO_METADATA,
        series_index = nil,
        keywords = NO_METADATA,
    }
end

local function prepare_candidate(menu, item, collate_id, collate, metadata, history,
        allow_expensive)
    if collate_id == "access" and history then
        local HistoryIndex = require("common/history_index")
        local paths = require("common/paths")
        local read_time = HistoryIndex.fileTime(history, item.path, paths.normPath)
        item.attr.access = read_time or item.attr.modification or item.attr.access or 0
    elseif METADATA_COLLATES[collate_id] then
        local paths = require("common/paths")
        local info = metadata[item.path] or metadata[paths.normPath(item.path)]
        if not info and allow_expensive and collate
                and type(collate.item_func) == "function" then
            return pcall(collate.item_func, item, menu and menu.ui)
        end
        info = info or {}
        local fallback = fallback_doc_props(item)
        item.doc_props = {
            display_title = info.title or fallback.display_title,
            title = info.title or fallback.title,
            authors = info.authors or fallback.authors,
            series = info.series or fallback.series,
            series_index = tonumber(info.series_index),
            keywords = info.keywords or fallback.keywords,
        }
        return info.title ~= nil or info.authors ~= nil or info.series ~= nil
            or info.keywords ~= nil
    elseif collate_id == "type" then
        item.suffix = item.text:match("%.([^%.]+)$") or ""
    elseif collate and type(collate.item_func) == "function" then
        if allow_expensive then
            return pcall(collate.item_func, item, menu and menu.ui)
        end
        item.opened = false
        item.percent_finished = 0
        item.sort_percent = -1
        item.rating = 0
        item.doc_props = fallback_doc_props(item)
        return false
    end
    return true
end

local function candidate_sort(menu, path)
    local collate_id, reverse, collate = sort_policy(menu, path)
    local sorting
    if collate and type(collate.init_sort_func) == "function" then
        local ok, result = pcall(collate.init_sort_func)
        if ok and type(result) == "function" then sorting = result end
    end
    if sorting and reverse then
        local unreversed = sorting
        sorting = function(a, b) return unreversed(b, a) end
    end
    local history = collate_id == "access" and history_snapshot() or nil
    local function less(a, b)
        if sorting then
            local ok_ab, before = pcall(sorting, a, b)
            local ok_ba, after = pcall(sorting, b, a)
            if ok_ab and ok_ba and before ~= after then return before end
        end
        local a_value = tostring(a.path or a.file or a.text or "")
        local b_value = tostring(b.path or b.file or b.text or "")
        local a_key = a_value:lower() .. "\30" .. a_value
        local b_key = b_value:lower() .. "\30" .. b_value
        return a_key < b_key
    end
    return collate_id, collate, history, less
end

local function retain_candidate(candidates, item, limit, less)
    local position = #candidates + 1
    for index = 1, #candidates do
        if less(item, candidates[index]) then
            position = index
            break
        end
    end
    if position <= limit then table.insert(candidates, position, item) end
    if #candidates > limit then table.remove(candidates) end
end

local function scan_descriptor(menu, path, max_covers, fallback_count, allow_expensive)
    local status_filter = menu and menu.show_filter and menu.show_filter.status
    local count_known = not status_filter and type(fallback_count) == "number"
    local count = count_known and fallback_count or 0
    local candidates = {}
    local target = count_known and math.min(max_covers, count) or max_covers
    if target == 0 then
        return { count = count, entries = candidates, exact = true }
    end
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then
        return { count = fallback_count or 0, entries = candidates, exact = true }
    end
    local show_hidden = menu and menu.show_hidden == true
    local collate_id, collate, history, less = candidate_sort(menu, path)
    local metadata
    local exact = true
    local needs_attributes = collate_id == "access" or collate_id == "date"
        or collate_id == "size"
    for name in iter, dir_obj do
        if name ~= "." and name ~= ".."
                and (show_hidden or name:sub(1, 1) ~= ".")
                and name:sub(1, 2) ~= "._" then
            local fullpath = path .. "/" .. name
            local lower_name = name:lower()
            local extension = lower_name:match("%.([^%.]+)$")
            if extension and DOC_EXTENSIONS[extension] then
                local attr = needs_attributes and lfs.attributes(fullpath)
                    or { mode = "file" }
                local visible = not needs_attributes
                    or (type(attr) == "table" and attr.mode == "file")
                if visible and menu and type(menu.show_file) == "function" then
                    local ok_show, shown = pcall(menu.show_file, menu, name, fullpath)
                    if ok_show and shown == false then visible = false end
                end
                if visible then
                    if not count_known then count = count + 1 end
                    if METADATA_COLLATES[collate_id] and metadata == nil then
                        metadata = sort_metadata(path)
                    end
                    local candidate = {
                        is_file = true,
                        file = fullpath,
                        path = fullpath,
                        text = name,
                        attr = attr,
                    }
                    if not prepare_candidate(menu, candidate, collate_id, collate,
                            metadata or {}, history, allow_expensive) then
                        exact = false
                    end
                    retain_candidate(candidates, candidate, target, less)
                end
            end
        end
    end
    return { count = count, entries = candidates, exact = exact }
end

local function mandatory_file_count(mandatory)
    if type(mandatory) == "number" then return mandatory end
    if type(mandatory) ~= "string" then return nil end
    return tonumber(mandatory:match("(%d+)%s*\xef\x80\x96"))
        or tonumber(mandatory:match("^%D*(%d+)%D*$"))
end

local function get_descriptor(menu, entry, max_covers, allow_expensive)
    local path = entry.path
    local key = descriptor_key(menu, path)
    local cached = descriptor_cache.values[path]
    if cached and cached.key == key and cached.max_covers >= max_covers
            and (not allow_expensive or cached.exact ~= false) then
        if #cached.entries > max_covers then
            local entries = {}
            for index = 1, max_covers do entries[index] = cached.entries[index] end
            return {
                key = cached.key,
                count = cached.count,
                entries = entries,
                exact = cached.exact,
                max_covers = max_covers,
            }, true, 0
        end
        return cached, true, 0
    end

    local started_at = now()
    local descriptor = scan_descriptor(
        menu, path, max_covers, mandatory_file_count(entry.mandatory or entry.count),
        allow_expensive)
    local enumeration_ms = elapsed_ms(started_at)
    descriptor.key = key
    descriptor.max_covers = max_covers
    if not descriptor_cache.values[path] then
        descriptor_cache.order[#descriptor_cache.order + 1] = path
    end
    descriptor_cache.values[path] = descriptor
    while #descriptor_cache.order > DESCRIPTOR_CACHE_MAX do
        descriptor_cache.values[table.remove(descriptor_cache.order, 1)] = nil
    end
    return descriptor, false, enumeration_ms
end

function M.isBook(entry)
    return type(entry) == "table" and (entry.is_file == true
        or type(entry.file) == "string"
        or (type(entry.attr) == "table" and entry.attr.mode == "file"))
end

local function is_directory(entry)
    return type(entry) == "table" and (entry.is_directory == true
        or entry.mode == "directory"
        or (type(entry.attr) == "table" and entry.attr.mode == "directory"))
end

function M.isSupported(entry, menu)
    if M.isBook(entry) then return true end
    if type(entry) ~= "table" then return false end
    if entry.is_go_up or entry.is_series_group or entry.series_items
            or entry._zen_files or entry._zen_empty_placeholder then
        return true
    end
    if menu and menu._zen_coll_list and entry.name then return true end
    return is_directory(entry) and menu
        and (menu.name == "filemanager" or menu._zen_renderer == true)
end

function M.title(entry, menu_text, menu)
    if menu and menu._zen_coll_list and entry and entry.name
            and type(menu._zen_get_collection_title) == "function" then
        local ok, collection_title = pcall(menu._zen_get_collection_title, entry.name)
        if ok and collection_title then menu_text = collection_title end
    end
    local title = menu_text or (entry and (entry.text or entry.name)) or ""
    title = tostring(title):gsub("/$", "")
    if title == "" and entry and entry.path then
        title = entry.path:gsub("/$", ""):match("([^/]+)$") or entry.path
    end
    return title
end

local function paths_to_entries(paths, limit)
    local entries = {}
    for _i, value in ipairs(paths or {}) do
        if limit and #entries >= limit then break end
        if type(value) == "table" then
            entries[#entries + 1] = value
        elseif type(value) == "string" and value ~= "" then
            entries[#entries + 1] = { is_file = true, path = value }
        end
    end
    return entries
end

local function first_entries(entries, limit)
    if not limit or #entries <= limit then return entries end
    local result = {}
    for index = 1, limit do result[index] = entries[index] end
    return result
end

function M.entries(menu, entry, load_members, limit)
    if type(entry) ~= "table" then return nil, false end
    if type(entry.series_items) == "table" then
        if load_members == false then return nil, false, #entry.series_items end
        return first_entries(entry.series_items, limit), false, #entry.series_items
    end
    if type(entry._zen_files) == "table" then
        if load_members == false then return nil, false, #entry._zen_files end
        return paths_to_entries(entry._zen_files, limit), false, #entry._zen_files
    end
    if menu and menu._zen_coll_list and entry.name
            and type(menu._zen_get_collection_files) == "function" then
        if load_members == false then return nil, false end
        local ok, files = pcall(menu._zen_get_collection_files, entry.name)
        return ok and paths_to_entries(files, limit) or {}, false,
            ok and type(files) == "table" and #files or 0
    end
    if entry.is_go_up or entry._zen_empty_placeholder then return {}, false end
    if is_directory(entry) then
        if load_members == false then return nil, true end
        local descriptor = scan_descriptor(menu, entry.path, limit or 4)
        return descriptor.entries, true, descriptor.count
    end
    return nil, false
end

function M.previewEntries(menu, entry, limit, options)
    if type(entry) ~= "table" then return {}, false, 0 end
    if type(limit) ~= "number" then
        limit = select(2, CoverUtils.getMode())
    end
    limit = math.max(0, limit)
    local is_virtual = type(entry.series_items) == "table"
        or type(entry._zen_files) == "table"
        or (menu and menu._zen_coll_list and entry.name
            and type(menu._zen_get_collection_files) == "function")
    if is_virtual then
        local entries, physical, count = M.entries(menu, entry, true, limit)
        return entries or {}, physical, count or 0, false, 0, true
    end
    if is_directory(entry) and entry.path then
        local descriptor, cache_hit, enumeration_ms = get_descriptor(
            menu, entry, limit, options and options.allow_expensive == true)
        return descriptor and descriptor.entries or {}, true,
            descriptor and descriptor.count or 0, cache_hit, enumeration_ms,
            not descriptor or descriptor.exact ~= false
    end
    local entries, physical, count = M.entries(menu, entry, true, limit)
    return entries or {}, physical, count or 0, false, 0, true
end

count_entries = function(entries, mandatory)
    if type(entries) == "table" then
        local count = 0
        for _i, entry in ipairs(entries) do
            if not entry.is_go_up then count = count + 1 end
        end
        return count
    end
    return mandatory_file_count(mandatory) or 0
end

local function append_covers(target, source, limit)
    for _i, cover in ipairs(source or {}) do
        if #target >= limit then break end
        target[#target + 1] = cover
    end
end

local function gallery_identity(menu, entry, title)
    if type(entry) ~= "table" then return nil end
    local virtual_kind = (entry.is_series_group or entry.series_items) and "series"
        or (entry._zen_files and "metadata")
        or (menu and menu._zen_coll_list and "collection")
    if entry.path and not virtual_kind then
        return table.concat({
            "folder", tostring(entry.path),
            tostring(lfs.attributes(entry.path, "modification") or 0),
        }, "\30")
    end
    return table.concat({
        virtual_kind or "group",
        tostring(entry.path or entry.name or entry.text or title or ""),
    }, "\30")
end

function M.build(menu, entry, menu_text, max_w, max_h, options)
    options = options or {}
    local title = M.title(entry, menu_text, menu)
    local mode, max_covers, need_copy = CoverUtils.getMode()
    local load_covers = options.load_covers ~= false and mode ~= "none"
    local perf = {
        descriptor_cache_hit = false,
        candidate_count = 0,
        enumeration_ms = 0,
        explicit_ms = 0,
        collect_ms = 0,
        draw_ms = 0,
        composite_cache_hit = false,
        composite_built = false,
    }
    local entries, physical
    local count
    local descriptor_exact = options.descriptor_exact ~= false
    if load_covers and options.entries ~= nil then
        entries = options.entries
        physical = options.physical
        count = options.count
        perf.descriptor_cache_hit = options.descriptor_cache_hit == true
        perf.enumeration_ms = tonumber(options.enumeration_ms) or 0
    elseif load_covers then
        local cache_hit, enumeration_ms, exact
        entries, physical, count, cache_hit, enumeration_ms, exact =
            M.previewEntries(menu, entry, max_covers, options)
        descriptor_exact = exact ~= false
        perf.descriptor_cache_hit = cache_hit
        perf.enumeration_ms = enumeration_ms
    else
        entries, physical, count = M.entries(menu, entry, load_covers, max_covers)
    end
    local count_hint = entry and (entry.mandatory or entry.count)
    if not load_covers and entry then
        if type(entry.series_items) == "table" then count_hint = #entry.series_items end
        if type(entry._zen_files) == "table" then count_hint = #entry._zen_files end
    end
    count = count or count_entries(entries, count_hint)
    perf.candidate_count = type(entries) == "table" and #entries or 0
    local portrait_w, portrait_h = CoverUtils.calcDims(max_w, max_h)
    local border = CoverUtils.BORDER_SIZE
    local uniform = options.uniform ~= false
    local covers = {}
    local needs_hydration = not descriptor_exact
    local gallery_cache_key
    local frame
    local cover_count = 0

    if load_covers and mode == "gallery"
            and not (entry and (entry.is_go_up or entry._zen_empty_placeholder)) then
        gallery_cache_key = CoverUtils.galleryCacheKey(
            gallery_identity(menu, entry, title), entries,
            portrait_w, portrait_h, uniform)
        if gallery_cache_key then
            local cache_started_at = now()
            frame = CoverUtils.getCachedGallery(
                gallery_cache_key, portrait_w, portrait_h, border)
            perf.draw_ms = perf.draw_ms + elapsed_ms(cache_started_at)
            if frame then
                perf.composite_cache_hit = true
                cover_count = math.max(1, math.min(max_covers, #entries))
            end
        end
    end

    if not frame and load_covers
            and not (entry and (entry.is_go_up or entry._zen_empty_placeholder)) then
        if physical and entry.path then
            local explicit_started_at = now()
            append_covers(covers, CoverUtils.loadExplicitCovers(entry.path, mode), max_covers)
            perf.explicit_ms = elapsed_ms(explicit_started_at)
        end
        if #covers < max_covers then
            local collect_started_at = now()
            local collected, pending = CoverUtils.collect(
                physical and entry.path or nil,
                physical and menu or nil,
                max_covers - #covers,
                need_copy,
                entries,
                options.cover_specs,
                #covers,
                options.cached_only == true
            )
            append_covers(covers, collected, max_covers)
            needs_hydration = needs_hydration or pending == true
            perf.collect_ms = elapsed_ms(collect_started_at)
        end
    end

    local draw_started_at = now()
    if not frame and mode == "gallery" and #covers > 0 then
        if not gallery_cache_key then
            gallery_cache_key = CoverUtils.galleryCacheKey(
                gallery_identity(menu, entry, title), entries,
                portrait_w, portrait_h, uniform)
        end
        local cache_key = not needs_hydration and gallery_cache_key or nil
        local cache_hit, composite_built
        frame, cache_hit, composite_built = CoverUtils.drawGallery(
            covers, portrait_w, portrait_h, border, nil, uniform, cache_key)
        perf.composite_cache_hit = cache_hit == true
        perf.composite_built = composite_built == true
        cover_count = #covers
    elseif mode == "stack" and #covers > 0 then
        local preview_w = not uniform and #covers == 1 and max_w or portrait_w
        local preview_h = not uniform and #covers == 1 and max_h or portrait_h
        frame = CoverUtils.drawStack(covers, preview_w, preview_h, border, nil, uniform)
        cover_count = #covers
    elseif #covers > 0 then
        local preview_w = uniform and portrait_w or max_w
        local preview_h = uniform and portrait_h or max_h
        frame = CoverUtils.drawSingle(covers[1], preview_w, preview_h, border, uniform)
        cover_count = #covers
    elseif not frame then
        frame = CoverUtils.drawNoImage(title, portrait_w, portrait_h, border)
    end
    perf.draw_ms = perf.draw_ms + elapsed_ms(draw_started_at)

    if options.decorate ~= false then CoverWidget.decorate_cover_frame(frame) end
    return {
        frame = frame,
        count = count,
        mode = mode,
        title = title,
        entries = entries,
        cover_count = cover_count,
        needs_hydration = needs_hydration,
        perf = perf,
    }
end

function M.isGalleryCached(menu, entry, menu_text, max_w, max_h, options)
    options = options or {}
    local mode, max_covers = CoverUtils.getMode()
    if mode ~= "gallery" then return false end
    local entries = options.entries
    if entries == nil then entries = M.previewEntries(menu, entry, max_covers) end
    if type(entries) ~= "table" or #entries == 0 then return false end
    local portrait_w, portrait_h = CoverUtils.calcDims(max_w, max_h)
    local cache_key = CoverUtils.galleryCacheKey(
        gallery_identity(menu, entry, M.title(entry, menu_text, menu)), entries,
        portrait_w, portrait_h, options.uniform ~= false)
    return type(CoverUtils.hasCachedGallery) == "function"
        and CoverUtils.hasCachedGallery(cache_key, portrait_w, portrait_h) == true
end

function M.warmGallery(menu, entry, menu_text, max_w, max_h, options)
    options = options or {}
    local mode, max_covers = CoverUtils.getMode()
    if mode ~= "gallery" then return false, false end
    local entries, physical, count, descriptor_cache_hit, enumeration_ms, descriptor_exact
    if options.entries ~= nil then
        entries = options.entries
        physical = options.physical
        count = options.count
        descriptor_cache_hit = options.descriptor_cache_hit
        enumeration_ms = options.enumeration_ms
        descriptor_exact = options.descriptor_exact
    else
        entries, physical, count, descriptor_cache_hit, enumeration_ms, descriptor_exact =
            M.previewEntries(menu, entry, max_covers, options)
    end
    local portrait_w, portrait_h = CoverUtils.calcDims(max_w, max_h)
    local cache_key = CoverUtils.galleryCacheKey(
        gallery_identity(menu, entry, M.title(entry, menu_text, menu)), entries,
        portrait_w, portrait_h, options.uniform ~= false)
    if type(CoverUtils.hasCachedGallery) == "function"
            and CoverUtils.hasCachedGallery(cache_key, portrait_w, portrait_h) then
        return false, true
    end
    local result = M.build(menu, entry, menu_text, max_w, max_h, {
        load_covers = true,
        cached_only = false,
        cover_specs = options.cover_specs,
        uniform = options.uniform,
        decorate = false,
        entries = entries,
        physical = physical,
        count = count,
        descriptor_cache_hit = descriptor_cache_hit,
        enumeration_ms = enumeration_ms,
        descriptor_exact = descriptor_exact,
    })
    local perf = result.perf or {}
    if result.frame and type(result.frame.free) == "function" then
        result.frame:free()
    end
    return perf.composite_built == true, perf.composite_cache_hit == true
end

function M.clear(path)
    if not path then
        descriptor_cache = { values = {}, order = {} }
        history_cache = nil
        return
    end
    descriptor_cache.values[path] = nil
    for index = #descriptor_cache.order, 1, -1 do
        if descriptor_cache.order[index] == path then
            table.remove(descriptor_cache.order, index)
            break
        end
    end
end

function M.paintSpines(bb, frame, item_x, item_y, options)
    local dimen = frame and frame.dimen
    if not (bb and dimen and dimen.x and dimen.y and dimen.w and dimen.h) then return end
    options = options or {}

    if not Screen then
        Blitbuffer = require("ffi/blitbuffer")
        Screen = require("device").screen
        Size = require("ui/size")
    end
    local thickness = math.max(1, Screen:scaleBySize(2.5))
    local margin = Size.line.medium
    local spine_gap = Screen:scaleBySize(9)
    local top_h = 2 * (thickness + margin)
    local orientation = options.orientation
    if not orientation then
        local top_gap = dimen.y - (item_y or 0)
        local left_gap = dimen.x - (item_x or 0)
        orientation = (top_gap >= top_h or left_gap < spine_gap) and "top" or "left"
    end

    local inset = options.rounded and Screen:scaleBySize(4) or 0
    local extent = options.line_extent
        or (orientation == "top" and dimen.w or dimen.h)
    local first_length = math.max(0, math.floor(extent * (0.97 ^ 2)) - 2 * inset)
    local second_length = math.max(0, math.floor(extent * 0.97) - 2 * inset)
    local color = Blitbuffer.COLOR_GRAY_4 or Blitbuffer.COLOR_BLACK

    local function paint_spine(x, y, width, height)
        if bb.paintRoundedRect then
            bb:paintRoundedRect(x, y, width, height, color,
                math.max(1, math.floor(math.min(width, height) / 2)))
        else
            bb:paintRect(x, y, width, height, color)
        end
    end

    if orientation == "top" then
        local lines_h = 2 * thickness + margin
        local first_y = dimen.y - top_h + math.floor((top_h - lines_h) / 2)
        if first_length > 0 then
            paint_spine(dimen.x + math.floor((dimen.w - first_length) / 2),
                first_y, first_length, thickness)
        end
        if second_length > 0 then
            paint_spine(dimen.x + math.floor((dimen.w - second_length) / 2),
                first_y + thickness + margin, second_length, thickness)
        end
    else
        local center_y = options.center_y or dimen.y + dimen.h / 2
        local first_x = dimen.x - spine_gap
        if first_length > 0 then
            paint_spine(first_x, math.floor(center_y - first_length / 2),
                thickness, first_length)
        end
        if second_length > 0 then
            paint_spine(first_x + thickness + margin,
                math.floor(center_y - second_length / 2),
                thickness, second_length)
        end
    end
    return orientation
end

return M

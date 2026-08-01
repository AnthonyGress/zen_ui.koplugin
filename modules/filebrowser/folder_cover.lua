-- Shared folder/group cover provider for Zen's mosaic and list renderers.
local CoverUtils = require("common/cover_utils")
local CoverWidget = require("modules/filebrowser/patches/home/widgets/cover_common")
local lfs = require("libs/libkoreader-lfs")
local now = require("common/zen_logger").now

local M = {}
local Blitbuffer, Screen, Size
local DESCRIPTOR_CACHE_MAX = 32
local DOC_EXTENSIONS = {
    azw = true, azw3 = true, cb7 = true, cbr = true, cbz = true, chm = true,
    djv = true, djvu = true, doc = true, docx = true, epub = true, epub3 = true,
    fb2 = true, fb3 = true, html = true, htm = true, kpub = true, md = true,
    mobi = true, odt = true, pdf = true, pdb = true, prc = true, rtf = true,
    txt = true, xhtml = true, zip = true,
}
local descriptor_cache = { values = {}, order = {} }
local count_entries

local function elapsed_ms(started_at)
    return (now() - started_at) * 1000
end

local function descriptor_key(menu, path)
    local settings = rawget(_G, "G_reader_settings")
    local collate = settings and type(settings.readSetting) == "function"
        and settings:readSetting("collate", "strcoll") or "strcoll"
    local reverse = settings and type(settings.isTrue) == "function"
        and settings:isTrue("reverse_collate") or false
    local mixed = settings and type(settings.isTrue) == "function"
        and settings:isTrue("collate_mixed") or false
    return table.concat({
        tostring(path),
        tostring(lfs.attributes(path, "modification") or 0),
        tostring(collate), tostring(reverse), tostring(mixed),
        tostring(menu and menu.show_hidden),
        tostring(menu and menu.show_filter and menu.show_filter.status),
    }, "\30")
end

local function scan_descriptor(menu, path, max_covers, fallback_count)
    local count_known = type(fallback_count) == "number"
    local count = count_known and fallback_count or 0
    local candidates = {}
    local target = count_known and math.min(max_covers, count) or max_covers
    if target == 0 then return { count = count, entries = candidates } end
    local ok, iter, dir_obj = pcall(lfs.dir, path)
    if not ok then
        return { count = fallback_count or 0, entries = candidates }
    end
    local show_hidden = menu and menu.show_hidden == true
    for name in iter, dir_obj do
        if name ~= "." and name ~= ".."
                and (show_hidden or name:sub(1, 1) ~= ".")
                and name:sub(1, 2) ~= "._" then
            local fullpath = path .. "/" .. name
            local lower_name = name:lower()
            local extension = lower_name:match("%.([^%.]+)$")
            if extension and DOC_EXTENSIONS[extension] then
                if not count_known then count = count + 1 end
                if #candidates < max_covers then
                    candidates[#candidates + 1] = {
                        is_file = true,
                        file = fullpath,
                        path = fullpath,
                        text = name,
                        attr = { mode = "file" },
                    }
                end
                if count_known and #candidates >= target then break end
            end
        end
    end
    return { count = count, entries = candidates }
end

local function mandatory_file_count(mandatory)
    if type(mandatory) == "number" then return mandatory end
    if type(mandatory) ~= "string" then return nil end
    return tonumber(mandatory:match("(%d+)%s*\xef\x80\x96"))
        or tonumber(mandatory:match("(%d+)"))
end

local function get_descriptor(menu, entry, max_covers)
    local path = entry.path
    local key = descriptor_key(menu, path)
    local cached = descriptor_cache.values[path]
    if cached and cached.key == key and cached.max_covers >= max_covers then
        if #cached.entries > max_covers then
            local entries = {}
            for index = 1, max_covers do entries[index] = cached.entries[index] end
            return {
                key = cached.key,
                count = cached.count,
                entries = entries,
                max_covers = max_covers,
            }, true, 0
        end
        return cached, true, 0
    end

    local started_at = now()
    local descriptor = scan_descriptor(
        menu, path, max_covers, mandatory_file_count(entry.mandatory or entry.count))
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

function M.previewEntries(menu, entry, limit)
    if type(entry) ~= "table" then return {}, false, 0 end
    if type(limit) ~= "number" then
        limit = select(2, CoverUtils.getMode())
    end
    limit = math.max(0, limit)
    if is_directory(entry) and entry.path then
        local descriptor, cache_hit, enumeration_ms = get_descriptor(menu, entry, limit)
        return descriptor and descriptor.entries or {}, true,
            descriptor and descriptor.count or 0, cache_hit, enumeration_ms
    end
    local entries, physical, count = M.entries(menu, entry, true, limit)
    return entries or {}, physical, count or 0, false, 0
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
    if entry.path then
        return table.concat({
            "folder", tostring(entry.path),
            tostring(lfs.attributes(entry.path, "modification") or 0),
        }, "\30")
    end
    local kind = entry.is_series_group and "series"
        or (entry._zen_files and "metadata")
        or (menu and menu._zen_coll_list and "collection")
        or "group"
    return table.concat({
        kind, tostring(entry.name or entry.text or title or ""),
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
    if load_covers and options.entries ~= nil then
        entries = options.entries
        physical = options.physical
        count = options.count
        perf.descriptor_cache_hit = options.descriptor_cache_hit == true
        perf.enumeration_ms = tonumber(options.enumeration_ms) or 0
    elseif load_covers then
        local cache_hit, enumeration_ms
        entries, physical, count, cache_hit, enumeration_ms =
            M.previewEntries(menu, entry, max_covers)
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
    local needs_hydration = false
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
            needs_hydration = pending == true
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

function M.warmGallery(menu, entry, menu_text, max_w, max_h, options)
    options = options or {}
    local mode, max_covers = CoverUtils.getMode()
    if mode ~= "gallery" then return false, false end
    local entries, physical, count, descriptor_cache_hit, enumeration_ms
    if options.entries ~= nil then
        entries = options.entries
        physical = options.physical
        count = options.count
        descriptor_cache_hit = options.descriptor_cache_hit
        enumeration_ms = options.enumeration_ms
    else
        entries, physical, count, descriptor_cache_hit, enumeration_ms =
            M.previewEntries(menu, entry, max_covers)
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

-- Shared folder/group cover provider for Zen's mosaic and list renderers.
local CoverUtils = require("common/cover_utils")
local CoverWidget = require("modules/filebrowser/patches/home/widgets/cover_common")

local M = {}

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
    return is_directory(entry) and menu and menu.name == "filemanager"
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

local function paths_to_entries(paths)
    local entries = {}
    for _i, value in ipairs(paths or {}) do
        if type(value) == "table" then
            entries[#entries + 1] = value
        elseif type(value) == "string" and value ~= "" then
            entries[#entries + 1] = { is_file = true, path = value }
        end
    end
    return entries
end

local function physical_entries(menu, path)
    if not (menu and type(menu.genItemTableFromPath) == "function" and path) then return nil end
    local previous = menu._zen_folder_cover_collect
    menu._zen_folder_cover_collect = true
    local ok, entries = pcall(menu.genItemTableFromPath, menu, path)
    menu._zen_folder_cover_collect = previous
    return ok and type(entries) == "table" and entries or nil
end

function M.entries(menu, entry, load_members)
    if type(entry) ~= "table" then return nil, false end
    if type(entry.series_items) == "table" then return entry.series_items, false end
    if type(entry._zen_files) == "table" then return paths_to_entries(entry._zen_files), false end
    if menu and menu._zen_coll_list and entry.name
            and type(menu._zen_get_collection_files) == "function" then
        if load_members == false then return nil, false end
        local ok, files = pcall(menu._zen_get_collection_files, entry.name)
        return ok and paths_to_entries(files) or {}, false
    end
    if entry.is_go_up or entry._zen_empty_placeholder then return {}, false end
    if is_directory(entry) then
        if load_members == false then return nil, true end
        return physical_entries(menu, entry.path), true
    end
    return nil, false
end

local function count_entries(entries, mandatory)
    if type(entries) == "table" then
        local count = 0
        for _i, entry in ipairs(entries) do
            if not entry.is_go_up then count = count + 1 end
        end
        return count
    end
    if type(mandatory) == "number" then return mandatory end
    return type(mandatory) == "string" and tonumber(mandatory:match("(%d+)")) or 0
end

local function append_covers(target, source, limit)
    for _i, cover in ipairs(source or {}) do
        if #target >= limit then break end
        target[#target + 1] = cover
    end
end

function M.build(menu, entry, menu_text, max_w, max_h, options)
    options = options or {}
    local title = M.title(entry, menu_text, menu)
    local mode, max_covers, need_copy = CoverUtils.getMode()
    local load_covers = options.load_covers ~= false and mode ~= "none"
    local entries, physical = M.entries(menu, entry, load_covers)
    local count = count_entries(entries, entry and entry.mandatory)
    local portrait_w, portrait_h = CoverUtils.calcDims(max_w, max_h)
    local border = CoverUtils.BORDER_SIZE
    local uniform = options.uniform ~= false
    local covers = {}

    if load_covers
            and not (entry and (entry.is_go_up or entry._zen_empty_placeholder)) then
        if physical and entry.path then
            append_covers(covers, CoverUtils.loadExplicitCovers(entry.path, mode), max_covers)
        end
        if #covers < max_covers then
            append_covers(covers, CoverUtils.collect(
                physical and entry.path or nil,
                physical and menu or nil,
                max_covers - #covers,
                need_copy,
                entries,
                options.cover_specs
            ), max_covers)
        end
    end

    local frame
    if mode == "gallery" and #covers > 0 then
        frame = CoverUtils.drawGallery(covers, portrait_w, portrait_h, border, nil, uniform)
    elseif mode == "stack" and #covers > 0 then
        frame = CoverUtils.drawStack(covers, portrait_w, portrait_h, border, nil, uniform)
    elseif #covers > 0 then
        frame = CoverUtils.drawSingle(covers[1], portrait_w, portrait_h, border, uniform)
    else
        frame = CoverUtils.drawNoImage(title, portrait_w, portrait_h, border)
    end

    CoverWidget.decorate_cover_frame(frame)
    return {
        frame = frame,
        count = count,
        mode = mode,
        title = title,
        entries = entries,
        cover_count = #covers,
    }
end

return M

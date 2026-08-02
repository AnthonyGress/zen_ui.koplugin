local builtin_components = {
    require("modules/filebrowser/patches/home/widgets/datetime"),
    require("modules/filebrowser/patches/home/widgets/featured_custom"),
    require("modules/filebrowser/patches/home/widgets/featured_tbr"),
    require("modules/filebrowser/patches/home/widgets/featured_recent"),
    require("modules/filebrowser/patches/home/widgets/stats_triplet"),
    require("modules/filebrowser/patches/home/widgets/reading_goals"),
    require("modules/filebrowser/patches/home/widgets/strip_custom"),
    require("modules/filebrowser/patches/home/widgets/strip_tbr"),
    require("modules/filebrowser/patches/home/widgets/strip_recent"),
    require("modules/filebrowser/patches/home/widgets/quotes"),
}

local builtin_by_id = {}
for _i, comp in ipairs(builtin_components) do
    builtin_by_id[comp.id] = comp
end

local external_by_id = {}
local refresh_callback = nil
local M = {}

function M.list()
    local components = {}
    for _i, comp in ipairs(builtin_components) do
        components[#components + 1] = comp
    end

    local external_ids = {}
    for id in pairs(external_by_id) do
        external_ids[#external_ids + 1] = id
    end
    table.sort(external_ids)
    for _i, id in ipairs(external_ids) do
        components[#components + 1] = external_by_id[id]
    end
    return components
end

function M.get(id)
    return builtin_by_id[id] or external_by_id[id]
end

function M.normalizeRows(rows, default_order, default_enabled)
    rows = type(rows) == "table" and rows or {}
    default_order = type(default_order) == "table" and default_order or {}
    default_enabled = type(default_enabled) == "table" and default_enabled or {}

    local order = {}
    local seen = {}
    for _i, id in ipairs(type(rows.order) == "table" and rows.order or {}) do
        if type(id) == "string" and id ~= "" and not seen[id] then
            order[#order + 1] = id
            seen[id] = true
        end
    end

    local enabled = {}
    local has_enabled = false
    for id, value in pairs(type(rows.enabled) == "table" and rows.enabled or {}) do
        if type(id) == "string" and id ~= "" then
            enabled[id] = value == true
            if value == true then has_enabled = true end
        end
    end
    if not has_enabled then
        for id, value in pairs(default_enabled) do
            enabled[id] = value == true
        end
    end
    local components = M.list()
    for _i, comp in ipairs(components) do
        if enabled[comp.id] == nil then enabled[comp.id] = false end
    end

    for _i, id in ipairs(default_order) do
        if type(id) == "string" and id ~= "" and not seen[id] then
            order[#order + 1] = id
            seen[id] = true
        end
    end
    for _i, comp in ipairs(components) do
        if not seen[comp.id] then
            order[#order + 1] = comp.id
            seen[comp.id] = true
        end
    end

    local dormant_ids = {}
    for id in pairs(enabled) do
        if not seen[id] then dormant_ids[#dormant_ids + 1] = id end
    end
    table.sort(dormant_ids)
    for _i, id in ipairs(dormant_ids) do
        order[#order + 1] = id
    end

    rows.order = order
    rows.enabled = enabled
    rows.max_rows = 5
    return rows
end

local function refresh()
    if refresh_callback then
        pcall(refresh_callback)
    end
end

-- build(ctx) receives width, height, is_first_row, and module_cfg.
function M.register(id, build, opts)
    if type(id) ~= "string" or id == "" or type(build) ~= "function"
            or builtin_by_id[id] then
        return false
    end
    opts = type(opts) == "table" and opts or {}
    external_by_id[id] = {
        id = id,
        label = type(opts.label) == "string" and opts.label or id,
        size = type(opts.size) == "table" and opts.size or nil,
        build = build,
    }
    refresh()
    return true
end

function M.unregister(id)
    if external_by_id[id] == nil then return end
    external_by_id[id] = nil
    refresh()
end

function M.setRefreshCallback(callback)
    refresh_callback = type(callback) == "function" and callback or nil
end

function M.install()
    rawset(_G, "__ZEN_UI_REGISTER_HOME_ITEM", M.register)
    rawset(_G, "__ZEN_UI_UNREGISTER_HOME_ITEM", M.unregister)
end

return M

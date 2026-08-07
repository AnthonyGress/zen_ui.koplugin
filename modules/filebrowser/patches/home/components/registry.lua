local builtin_components = {
    require("modules/filebrowser/patches/home/widgets/datetime"),
    require("modules/filebrowser/patches/home/widgets/featured_custom"),
    require("modules/filebrowser/patches/home/widgets/featured_tbr"),
    require("modules/filebrowser/patches/home/widgets/featured_recent"),
    require("modules/filebrowser/patches/home/widgets/stats_triplet"),
    require("modules/filebrowser/patches/home/widgets/reading_goals"),
    require("modules/filebrowser/patches/home/widgets/strip"),
    require("modules/filebrowser/patches/home/widgets/quotes"),
}

local builtin_by_id = {}
for _i, comp in ipairs(builtin_components) do
    builtin_by_id[comp.id] = comp
end

local external_by_id = {}
local refresh_callback = nil
local M = {}

M.CAPACITY_UNITS = 10

local SIZE_UNITS = {
    xs = 1,
    s = 2,
    m = 3,
    l = 4,
    xl = 10,
}

local LAYOUT_GROWTH = {
    datetime = { max = 3, priority = 2 },
    featured_custom = { max = 5, priority = 2 },
    featured_recent = { max = 5, priority = 2 },
    featured_tbr = { max = 5, priority = 2 },
    quotes = { max = 3, priority = 3 },
    reading_goals = { max = 2, priority = 4 },
    stats_triplet = { max = 1, priority = 4 },
    strip = { max = 3.5, priority = 1 },
}

local function clamp_units(value)
    local units = math.floor((tonumber(value) or 2) + 0.5)
    return math.max(1, math.min(M.CAPACITY_UNITS, units))
end

local function size_value(component)
    if type(component) == "table" and component.size ~= nil then
        return component.size
    end
    return component
end

function M.sizeClass(component)
    local size = size_value(component)
    if type(size) == "string" then
        local name = size:lower()
        if SIZE_UNITS[name] then return name end
    elseif type(size) == "table" then
        local name = type(size.class) == "string" and size.class:lower() or nil
        if name and SIZE_UNITS[name] then return name end
    end
    return nil
end

function M.baseSizeUnits(component)
    local size = size_value(component)
    local class = M.sizeClass(size)
    if class then return SIZE_UNITS[class] end
    if type(size) == "number" then return clamp_units(size) end
    if type(size) == "table" then
        if tonumber(size.units) then
            return math.max(1, math.min(M.CAPACITY_UNITS, tonumber(size.units)))
        end
        local pct = tonumber(size.preferred_pct)
        if pct then return clamp_units(pct * M.CAPACITY_UNITS) end
        if tonumber(size.preferred) then return clamp_units(size.preferred) end
    end
    return SIZE_UNITS.s
end

function M.sizeUnits(component, module_cfg)
    local units = M.baseSizeUnits(component)
    if type(module_cfg) == "table" and module_cfg.two_rows == true then
        units = math.min(6, units * 2)
    end
    return math.min(M.CAPACITY_UNITS, units)
end

function M.sizeLabel(component, module_cfg)
    local class = M.sizeClass(component)
    local label = class and class:upper() or tostring(M.baseSizeUnits(component))
    if M.sizeUnits(component, module_cfg) ~= M.baseSizeUnits(component) then
        label = label .. " × 2"
    end
    return label
end

function M.totalUnits(enabled, modules)
    local total = 0
    enabled = type(enabled) == "table" and enabled or {}
    modules = type(modules) == "table" and modules or {}
    for id, value in pairs(enabled) do
        local component = value == true and M.get(id) or nil
        if component then
            total = total + M.sizeUnits(component, modules[id])
        end
    end
    return total
end

function M.layoutUnits(components)
    components = components or {}
    local units = {}
    local total = 0
    local priorities = {}
    local seen_priorities = {}
    for i, component in ipairs(components) do
        local base = M.baseSizeUnits(component)
        units[i] = base
        total = total + base
        local growth = LAYOUT_GROWTH[component.id]
        if growth and not seen_priorities[growth.priority] then
            seen_priorities[growth.priority] = true
            priorities[#priorities + 1] = growth.priority
        end
    end
    table.sort(priorities)

    local remaining = math.max(0, M.CAPACITY_UNITS - total)
    for _i, priority in ipairs(priorities) do
        while remaining > 0 do
            local grew = false
            for i, component in ipairs(components) do
                local growth = LAYOUT_GROWTH[component.id]
                local max_units = growth
                    and math.max(growth.max, tonumber(component._home_units) or 0) or 0
                if growth and growth.priority == priority and units[i] < max_units then
                    local added = math.min(1, remaining, max_units - units[i])
                    units[i] = units[i] + added
                    remaining = remaining - added
                    grew = true
                    if remaining == 0 then break end
                end
            end
            if not grew then break end
        end
        if remaining == 0 then break end
    end
    return units
end

function M.gridHeights(unit_counts, body_h, gap)
    local heights = {}
    local capacity = M.CAPACITY_UNITS
    gap = math.max(0, math.floor(tonumber(gap) or 0))
    body_h = math.max(1, math.floor(tonumber(body_h) or 1))
    local pitch = (body_h + gap) / capacity
    local used_units = 0

    for _i, value in ipairs(unit_counts or {}) do
        if used_units >= capacity then break end
        local units = math.max(0, math.min(
            capacity - used_units,
            tonumber(value) or 1
        ))
        if units > 0 then
            local start_px = math.floor(used_units * pitch + 0.5)
            used_units = used_units + units
            local end_px = math.floor(used_units * pitch - gap + 0.5)
            heights[#heights + 1] = math.max(1, end_px - start_px)
        end
    end

    return heights
end

function M.equalSpacingShifts(items)
    local count = #(items or {})
    if count < 2 then return {} end

    local function shift_bounds(item)
        local first = item.min_shift or 0
        local second = item.max_shift or 0
        return math.min(first, second), math.max(first, second)
    end

    local base_gaps = {}
    local max_gap = 0
    for i = 1, count - 1 do
        local current = items[i]
        local following = items[i + 1]
        local gap = (following.row_y or 0) + (following.top or 0)
            - (current.row_y or 0) - (current.bottom or 0)
        base_gaps[i] = gap
        max_gap = math.max(max_gap, gap)
    end
    for _i, item in ipairs(items) do
        local min_shift, max_shift = shift_bounds(item)
        max_gap = max_gap
            + max_shift - min_shift
    end

    local best_shifts
    local best_cost
    for target_gap = 0, max_gap do
        local offsets = { 0 }
        local sum_offsets = 0
        for i = 1, count - 1 do
            offsets[i + 1] = offsets[i] + target_gap - base_gaps[i]
            sum_offsets = sum_offsets + offsets[i + 1]
        end

        local lower = -math.huge
        local upper = math.huge
        for i = 1, count do
            local min_shift, max_shift = shift_bounds(items[i])
            lower = math.max(lower, min_shift - offsets[i])
            upper = math.min(upper, max_shift - offsets[i])
        end
        if lower <= upper then
            local anchor = math.floor(-sum_offsets / count + 0.5)
            anchor = math.max(lower, math.min(upper, anchor))
            local shifts = {}
            local cost = 0
            for i = 1, count do
                shifts[i] = anchor + offsets[i]
                cost = cost + (items[i].shift_weight or 1) * shifts[i] * shifts[i]
            end
            if best_cost == nil or cost < best_cost then
                best_cost = cost
                best_shifts = shifts
            end
        end
    end
    if best_shifts then return best_shifts end

    local shifts = {}
    for i, item in ipairs(items) do
        local min_shift, max_shift = shift_bounds(item)
        shifts[i] = math.max(min_shift, math.min(max_shift, 0))
    end

    local function score()
        local gaps = {}
        local overlap = 0
        for i = 1, count - 1 do
            gaps[i] = base_gaps[i] + shifts[i + 1] - shifts[i]
            if gaps[i] < 0 then overlap = overlap + gaps[i] * gaps[i] end
        end
        local variance = 0
        for i = 1, #gaps do
            for j = i + 1, #gaps do
                local delta = gaps[i] - gaps[j]
                variance = variance + delta * delta
            end
        end
        local movement = 0
        for i, shift in ipairs(shifts) do
            movement = movement + (items[i].shift_weight or 1) * shift * shift
        end
        return overlap, variance, movement
    end

    local function improves(overlap, variance, movement, best_overlap, best_variance, best_movement)
        return overlap < best_overlap
            or overlap == best_overlap and variance < best_variance
            or overlap == best_overlap and variance == best_variance and movement < best_movement
    end

    for _pass = 1, 20 do
        local changed = false
        for i, item in ipairs(items) do
            local min_shift, max_shift = shift_bounds(item)
            min_shift = math.ceil(min_shift)
            max_shift = math.floor(max_shift)
            local original = shifts[i]
            local best = original
            local best_overlap, best_variance, best_movement = score()
            for candidate = min_shift, max_shift do
                shifts[i] = candidate
                local overlap, variance, movement = score()
                if improves(overlap, variance, movement,
                        best_overlap, best_variance, best_movement) then
                    best = candidate
                    best_overlap, best_variance, best_movement = overlap, variance, movement
                end
            end
            shifts[i] = best
            if best ~= original then changed = true end
        end
        if not changed then break end
    end
    return shifts
end

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
    rows.max_rows = nil
    rows.capacity_units = M.CAPACITY_UNITS
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
        size = (type(opts.size) == "table" or type(opts.size) == "string"
            or type(opts.size) == "number") and opts.size or nil,
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

local _ = require("gettext")
local Store = require("modules/menu/app_launcher/store")

local M = {}

local function valid_plugin(plugin)
    return type(plugin) == "table"
        and type(plugin.key) == "string"
        and type(plugin.method) == "string"
end

local function valid_koreader_menu(menu)
    return type(menu) == "table"
        and type(menu.id) == "string"
        and menu.id ~= ""
end

local function valid_entry(entry, allow_folder)
    if type(entry) ~= "table" or type(entry.id) ~= "string" then
        return false
    end
    if entry.type == "break" then
        return true
    end
    if type(entry.label) ~= "string" or entry.label == "" then
        return false
    end
    if entry.type == "action" then
        return type(entry.action) == "table"
    elseif entry.type == "plugin" then
        return valid_plugin(entry.plugin)
    elseif entry.type == "koreader_menu" then
        return valid_koreader_menu(entry.koreader_menu)
    elseif entry.type == "quick_setting" then
        return type(entry.quick_setting_id) == "string" and entry.quick_setting_id ~= ""
    elseif entry.type == "folder_shortcut" then
        return type(entry.folder) == "string" and entry.folder ~= ""
    elseif entry.type == "tag" then
        return type(entry.tag) == "string" and entry.tag ~= ""
    elseif allow_folder and entry.type == "folder" then
        return true
    end
    return false
end

local function sanitize_list(entries, allow_folder)
    local out = {}
    local changed = false
    if type(entries) ~= "table" then
        return out, true
    end
    for _i, entry in ipairs(entries) do
        if valid_entry(entry, allow_folder) then
            if entry.type == "folder" then
                local children, child_changed = sanitize_list(entry.children, false)
                local folder = entry
                if child_changed or type(entry.children) ~= "table" then
                    folder = {}
                    for key, value in pairs(entry) do
                        folder[key] = value
                    end
                    folder.children = children
                    changed = true
                end
                out[#out + 1] = folder
            else
                out[#out + 1] = entry
            end
        else
            changed = true
        end
    end
    return out, changed
end

local function zenpm_is_enabled()
    local ok_loader, PluginLoader = pcall(require, "pluginloader")
    if not ok_loader or type(PluginLoader) ~= "table"
            or type(PluginLoader.loadPlugins) ~= "function" then
        return false
    end
    local ok_plugins, plugins = pcall(PluginLoader.loadPlugins, PluginLoader)
    if not ok_plugins or type(plugins) ~= "table" then return false end
    for _i, plugin in ipairs(plugins) do
        if type(plugin) == "table" and plugin.name == "zenpm" then
            return true
        end
    end
    return false
end

local function has_zenpm_entry(entries)
    for _i, entry in ipairs(entries or {}) do
        if type(entry) == "table" then
            local plugin = entry.plugin
            if entry.type == "plugin" and type(plugin) == "table"
                    and plugin.key == "zenpm" then
                return true
            end
            if entry.type == "folder" and has_zenpm_entry(entry.children) then
                return true
            end
        end
    end
    return false
end

function M.ensure()
    local cfg = Store.load()
    local entries, changed = sanitize_list(cfg.entries, true)
    if changed then
        cfg.entries = entries
    elseif type(cfg.entries) ~= "table" then
        cfg.entries = {}
    end
    if changed then
        Store.save(cfg)
    end
    return cfg
end

function M.save(cfg)
    return Store.save(cfg)
end

function M.ensure_zenpm_launcher_entry()
    local cfg = M.ensure()
    if cfg.zenpm_launcher_added == true or not zenpm_is_enabled() then
        return false
    end
    if not has_zenpm_entry(cfg.entries) then
        cfg.entries[#cfg.entries + 1] = {
            id = M.next_id(cfg),
            type = "plugin",
            label = "ZenPM",
            icon = "zenpm",
            plugin = { key = "zenpm", method = "open" },
        }
    end
    cfg.zenpm_launcher_added = true
    Store.save(cfg)
    return true
end

-- Monotonic counter that only ever increments, so removing entries can never
-- cause a future id to collide with an existing one.
function M.next_id(cfg)
    cfg.next_id = (tonumber(cfg.next_id) or 0) + 1
    return "al_" .. cfg.next_id
end

function M.find_by_id(entries, id)
    for i, entry in ipairs(entries or {}) do
        if entry.id == id then
            return entries, i, entry, nil
        end
        if entry.type == "folder" then
            for j, child in ipairs(entry.children or {}) do
                if child.id == id then
                    return entry.children, j, child, entry
                end
            end
        end
    end
end

function M.move_by(entries, id, dir)
    local list, index = M.find_by_id(entries, id)
    if not list then return false end
    local target = index + dir
    if target < 1 or target > #list then return false end
    list[index], list[target] = list[target], list[index]
    return true
end

function M.remove_by_id(entries, id)
    local list, index = M.find_by_id(entries, id)
    if not list then return false end
    table.remove(list, index)
    return true
end

function M.move_to_folder(entries, id, folder_id)
    local entry = select(3, M.find_by_id(entries, id))
    local folder = select(3, M.find_by_id(entries, folder_id))
    if not entry or not folder or entry.type == "folder" or folder.type ~= "folder" then
        return false
    end
    M.remove_by_id(entries, id)
    folder.children = folder.children or {}
    folder.children[#folder.children + 1] = entry
    return true
end

function M.move_to_root(entries, id)
    local found = { M.find_by_id(entries, id) }
    local entry, parent = found[3], found[4]
    if not entry or not parent then return false end
    M.remove_by_id(entries, id)
    entries[#entries + 1] = entry
    return true
end

function M.display_label(entry)
    if not entry then return _("App") end
    if entry.type == "break" then return "\u{2014} " .. _("Row break") .. " \u{2014}" end
    return entry.label or _("App")
end

function M.enabled_entries(entries)
    local enabled = {}
    for _i, entry in ipairs(entries or {}) do
        if entry.enabled ~= false then
            enabled[#enabled + 1] = entry
        end
    end
    return enabled
end

return M

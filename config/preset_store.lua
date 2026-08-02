local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local lfs = require("libs/libkoreader-lfs")

local M = {}

local ROOT_DIR = DataStorage:getSettingsDir() .. "/Zen UI"
local VALID_KINDS = {
    home = true,
    stats = true,
    reader = true,
    screensaver = true,
}

local function ensure_dir(path)
    if lfs.attributes(path, "mode") == "directory" then return true end
    return lfs.mkdir(path) == true or lfs.attributes(path, "mode") == "directory"
end

local function ensure_root_dir()
    ensure_dir(ROOT_DIR)
    return ROOT_DIR
end

local function normalize_kind(kind)
    if VALID_KINDS[kind] then return kind end
end

local function kind_path(kind)
    kind = normalize_kind(kind)
    if not kind then return nil end
    return ensure_root_dir() .. "/" .. kind .. ".lua"
end

local function file_exists(path)
    return lfs.attributes(path, "mode") == "file"
end

local function empty_store()
    return {
        settings = {},
        presets = {},
        active_preset = nil,
        version = 1,
    }
end

local function normalize_store(data)
    if type(data) ~= "table" then data = {} end
    if type(data.settings) ~= "table" then data.settings = {} end
    if type(data.presets) ~= "table" then data.presets = {} end
    if type(data.active_preset) ~= "string" or data.active_preset == "" then
        data.active_preset = nil
    end
    if type(data.version) ~= "number" then data.version = 1 end
    return data
end

local function open_store(kind)
    local path = kind_path(kind)
    if not path then return nil end
    return LuaSettings:open(path)
end

function M.rootDir()
    return ensure_root_dir()
end

function M.kindPath(kind)
    return kind_path(kind)
end

function M.loadStore(kind)
    local settings = open_store(kind)
    if not settings then return empty_store() end
    return normalize_store(settings.data)
end

function M.saveStore(kind, data)
    local settings = open_store(kind)
    if not settings then return false end
    settings.data = normalize_store(data)
    settings:flush()
    return true
end

function M.getSettings(kind)
    return M.loadStore(kind).settings
end

function M.ensureStore(kind, initial_settings)
    local path = kind_path(kind)
    if not path then return false end

    local exists = file_exists(path)
    local settings = LuaSettings:open(path)
    local raw_store = settings.data
    local changed = not exists or type(raw_store) ~= "table"
        or type(raw_store.settings) ~= "table"
        or type(raw_store.presets) ~= "table"
        or type(raw_store.version) ~= "number"
    local store = normalize_store(raw_store)

    if not exists and type(initial_settings) == "table" then
        store.settings = initial_settings
    end
    if changed then
        settings.data = store
        settings:flush()
    end
    return changed
end

function M.migrateStores(initial_settings)
    local changed = false
    for _i, kind in ipairs({ "home", "stats", "reader", "screensaver" }) do
        local init = type(initial_settings) == "table" and initial_settings[kind] or nil
        if M.ensureStore(kind, init) then
            changed = true
        end
    end
    return changed
end

function M.saveSettings(kind, settings_data)
    local store = M.loadStore(kind)
    store.settings = type(settings_data) == "table" and settings_data or {}
    return M.saveStore(kind, store)
end

function M.getActivePreset(kind)
    return M.loadStore(kind).active_preset
end

function M.setActivePreset(kind, name)
    local store = M.loadStore(kind)
    store.active_preset = type(name) == "string" and name ~= "" and name or nil
    return M.saveStore(kind, store)
end

function M.list(kind)
    local store = M.loadStore(kind)
    local out = {}
    for name, preset in pairs(store.presets) do
        if type(preset) == "table" then
            if type(preset.name) ~= "string" or preset.name == "" then
                preset.name = tostring(name)
            end
            out[#out + 1] = preset
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    return out
end

function M.find(kind, name)
    if type(name) ~= "string" then return nil end
    local preset = M.loadStore(kind).presets[name]
    if type(preset) == "table" then
        if type(preset.name) ~= "string" or preset.name == "" then preset.name = name end
        return preset
    end
end

function M.save(kind, name, preset)
    if type(preset) ~= "table" then return false end
    name = tostring(name or ""):match("^%s*(.-)%s*$") or ""
    if name == "" then return false end

    local store = M.loadStore(kind)
    local copy = {}
    for key, value in pairs(preset) do
        if key ~= "_filename" then copy[key] = value end
    end
    copy.name = name
    store.presets[name] = copy
    return M.saveStore(kind, store)
end

function M.delete(kind, name)
    if type(name) ~= "string" then return false end
    local store = M.loadStore(kind)
    store.presets[name] = nil
    if store.active_preset == name then store.active_preset = nil end
    return M.saveStore(kind, store)
end

local function remove_tree(path)
    local mode = lfs.attributes(path, "mode")
    if mode == "file" then
        pcall(os.remove, path)
        return
    end
    if mode ~= "directory" then return end
    for entry in lfs.dir(path) do
        if entry ~= "." and entry ~= ".." then
            remove_tree(path .. "/" .. entry)
        end
    end
    pcall(lfs.rmdir, path)
end

function M.removeAll()
    remove_tree(ROOT_DIR)
end

return M

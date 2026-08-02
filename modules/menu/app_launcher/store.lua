local LuaSettings = require("luasettings")
local PresetStore = require("config/preset_store")

local M = {}

local _settings_file
local _current_config

local function default_config()
    return {
        entries = {},
        next_id = 0,
        show_labels = true,
        open_first = false,
        hide_reader_actions_in_library = false,
    }
end

local function settings_path()
    return PresetStore.rootDir() .. "/app_launcher.lua"
end

local function open_file()
    if not _settings_file then
        _settings_file = LuaSettings:open(settings_path())
    end
    return _settings_file
end

local function normalize(cfg)
    if type(cfg) ~= "table" then cfg = {} end
    if type(cfg.entries) ~= "table" then cfg.entries = {} end
    if type(cfg.next_id) ~= "number" then cfg.next_id = 0 end
    if type(cfg.show_labels) ~= "boolean" then cfg.show_labels = true end
    if type(cfg.open_first) ~= "boolean" then cfg.open_first = false end
    cfg.center_icons = nil
    if type(cfg.hide_reader_actions_in_library) ~= "boolean" then
        cfg.hide_reader_actions_in_library = false
    end
    return cfg
end

function M.path()
    return settings_path()
end

function M.load()
    if _current_config then return _current_config end
    local f = open_file()
    if type(f.data) == "table" and next(f.data) ~= nil then
        _current_config = normalize(f.data)
    else
        _current_config = default_config()
    end
    return _current_config
end

function M.save(cfg)
    cfg = normalize(cfg)
    local f = open_file()
    f.data = cfg
    f:flush()
    _current_config = cfg
    return cfg
end

return M

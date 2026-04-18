local defaults = require("config/defaults")
local utils = require("common/utils")

local KEY = "zen_ui_config"
local M = {}

local function merged_with_defaults(stored)
    local cfg = utils.deepcopy(defaults)
    if type(stored) == "table" then
        utils.deepmerge(stored, cfg)
        cfg = stored
    end
    utils.deepmerge(cfg, defaults)
    return cfg
end

local function normalize_renamed_keys(cfg)
    if type(cfg) ~= "table" then
        return cfg
    end

    cfg.features = cfg.features or {}

    if cfg.features.disable_top_menu_swipe_zones == nil
       and cfg.features.disable_top_menu_zones ~= nil then
        cfg.features.disable_top_menu_swipe_zones = cfg.features.disable_top_menu_zones
    end

    if cfg.features.browser_hide_up_folder == nil
       and cfg.features.browser_up_folder ~= nil then
        cfg.features.browser_hide_up_folder = cfg.features.browser_up_folder
    end

    if cfg.browser_hide_up_folder == nil and cfg.browser_up_folder ~= nil then
        cfg.browser_hide_up_folder = cfg.browser_up_folder
    end

    -- Always-on features: no user toggle in Zen settings.
    cfg.features.browser_folder_cover = true

    return cfg
end

function M.load()
    local stored = G_reader_settings:readSetting(KEY, {})
    local cfg = merged_with_defaults(stored)
    cfg = normalize_renamed_keys(cfg)
    return cfg
end

function M.save(config)
    G_reader_settings:saveSetting(KEY, config)
end

function M.key()
    return KEY
end

return M

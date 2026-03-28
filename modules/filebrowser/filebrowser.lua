local M = {}
local initialized = false

local FEATURES = {
    "navbar",
    "titlebar",
    "hide_pagination",
    "browser_folder_cover",
    "browser_hide_underline",
    "browser_hide_up_folder",
}

local PATCH_MODULES = {
    navbar = "modules/filebrowser/patches/navbar",
    titlebar = "modules/filebrowser/patches/titlebar",
    hide_pagination = "modules/filebrowser/patches/hide_pagination",
    browser_folder_cover = "modules/filebrowser/patches/browser_folder_cover",
    browser_hide_underline = "modules/filebrowser/patches/browser_hide_underline",
    browser_hide_up_folder = "modules/filebrowser/patches/browser_hide_up_folder",
}

local function is_feature_enabled(plugin, key)
    return plugin
        and type(plugin.config) == "table"
        and type(plugin.config.features) == "table"
        and plugin.config.features[key] == true
end

local function run_feature(logger, plugin, feature, fn)
    local prev_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    _G.__ZEN_UI_PLUGIN = plugin
    local ok, err = pcall(fn)
    _G.__ZEN_UI_PLUGIN = prev_plugin
    if not ok and logger then
        logger.warn("zen-ui: grouped filebrowser feature failed", feature, err)
    end
    return ok
end

local function load_patch(feature)
    local module_name = PATCH_MODULES[feature]
    if not module_name then
        return nil
    end

    local ok, patch_or_err = pcall(require, module_name)
    if not ok then
        return nil, patch_or_err
    end

    if type(patch_or_err) ~= "function" then
        return nil, "patch module did not return a function"
    end

    return patch_or_err
end

function M.init(logger, plugin)
    if initialized then
        return true
    end

    for _, feature in ipairs(FEATURES) do
        if is_feature_enabled(plugin, feature) then
            local fn, err = load_patch(feature)
            if fn then
                run_feature(logger, plugin, feature, fn)
            elseif logger then
                logger.warn("zen-ui: grouped filebrowser patch load failed", feature, err)
            end
        end
    end

    initialized = true
    return true
end

return M

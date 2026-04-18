local M = {}
local initialized = false

local FEATURES = {
    "quick_settings",
    "zen_mode",
}

local PATCH_MODULES = {
    quick_settings = "modules/menu/patches/quick_settings",
    zen_mode = "modules/menu/patches/zen_mode",
    disable_top_menu_swipe_zones = "modules/menu/patches/disable_top_menu_swipe_zones",
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
        logger.warn("zen-ui: grouped menu feature failed", feature, err)
    end
    return ok
end

local function load_patch(feature)
    local module_name = PATCH_MODULES[feature]
    if not module_name then
        return nil
    end
    local ok, patch_fn = pcall(require, module_name)
    if not ok or type(patch_fn) ~= "function" then
        return nil
    end
    return patch_fn
end

function M.init(logger, plugin)
    if initialized then
        return true
    end

    -- Ensure the runtime-patches registry exists.
    local runtime_patches = rawget(_G, "__ZEN_UI_RUNTIME_PATCHES")
    if type(runtime_patches) ~= "table" then
        runtime_patches = {}
        _G.__ZEN_UI_RUNTIME_PATCHES = runtime_patches
    end

    for _, feature in ipairs(FEATURES) do
        if is_feature_enabled(plugin, feature) then
            local fn = load_patch(feature)
            if fn then
                local ok = run_feature(logger, plugin, feature, fn)
                if ok then
                    runtime_patches[feature] = true
                end
            elseif logger then
                logger.warn("zen-ui: menu patch module missing", feature)
            end
        end
    end

    -- Always apply: disable swipe zones so quick settings tab is always shown first
    local swipe_fn = load_patch("disable_top_menu_swipe_zones")
    if swipe_fn then
        local ok = run_feature(logger, plugin, "disable_top_menu_swipe_zones", swipe_fn)
        if ok then
            runtime_patches["disable_top_menu_swipe_zones"] = true
        end
    end

    initialized = true
    return true
end

return M

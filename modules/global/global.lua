local M = {}
local initialized = false

local PATCH_MODULES = {
    night_mode_schedule    = "modules/global/patches/night_mode_schedule",
    warmth_schedule        = "modules/global/patches/warmth_schedule",
    brightness_schedule    = "modules/global/patches/brightness_schedule",
    disable_night_on_exit  = "modules/global/patches/disable_night_on_exit",
}

local function run_patch(logger, plugin, feature, fn)
    local prev_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    _G.__ZEN_UI_PLUGIN = plugin
    local ok, err = pcall(fn)
    _G.__ZEN_UI_PLUGIN = prev_plugin
    if not ok and logger then
        logger.warn("zen-ui: global patch failed", feature, err)
    end
    return ok
end

local function load_patch(feature)
    local module_name = PATCH_MODULES[feature]
    if not module_name then return nil end
    local ok, patch_fn = pcall(require, module_name)
    if not ok or type(patch_fn) ~= "function" then return nil end
    return patch_fn
end

function M.init(logger, plugin)
    if initialized then return true end

    -- Always apply: night-mode scheduler (self-disables when feature is off).
    local night_mode_schedule_fn = load_patch("night_mode_schedule")
    if night_mode_schedule_fn then
        run_patch(logger, plugin, "night_mode_schedule", night_mode_schedule_fn)
    end

    -- Always apply: warmth scheduler (no-ops on devices without natural light).
    local warmth_schedule_fn = load_patch("warmth_schedule")
    if warmth_schedule_fn then
        run_patch(logger, plugin, "warmth_schedule", warmth_schedule_fn)
    end

    -- Always apply: brightness scheduler.
    local brightness_schedule_fn = load_patch("brightness_schedule")
    if brightness_schedule_fn then
        run_patch(logger, plugin, "brightness_schedule", brightness_schedule_fn)
    end

    -- Always apply: disable night mode on Exit/Restart from any menu.
    local disable_night_on_exit_fn = load_patch("disable_night_on_exit")
    if disable_night_on_exit_fn then
        run_patch(logger, plugin, "disable_night_on_exit", disable_night_on_exit_fn)
    end

    initialized = true
    return true
end

return M

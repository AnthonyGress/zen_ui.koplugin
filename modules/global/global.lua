local M = {}
local initialized = false

local PATCH_MODULES = {
    night_mode_schedule    = "modules/global/patches/night_mode_schedule",
    warmth_schedule        = "modules/global/patches/warmth_schedule",
    brightness_schedule    = "modules/global/patches/brightness_schedule",
    disable_night_on_exit  = "modules/global/patches/disable_night_on_exit",
    menu_top_swipe         = "modules/global/patches/menu_top_swipe",
    opds                   = "modules/global/patches/opds",
    lockdown_mode          = "modules/global/patches/lockdown_mode",
    menu_font              = "modules/global/patches/menu_font",
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
    if not ok then return nil end
    -- Patch modules may return a plain function or a table with an `apply` key
    if type(patch_fn) == "table" and type(patch_fn.apply) == "function" then
        return patch_fn.apply
    end
    if type(patch_fn) == "function" then return patch_fn end
    return nil
end

function M.init(logger, plugin)
    if initialized then return true end

    local night_mode_schedule_fn = load_patch("night_mode_schedule")
    if night_mode_schedule_fn then
        run_patch(logger, plugin, "night_mode_schedule", night_mode_schedule_fn)
    end

    local warmth_schedule_fn = load_patch("warmth_schedule")
    if warmth_schedule_fn then
        run_patch(logger, plugin, "warmth_schedule", warmth_schedule_fn)
    end

    local brightness_schedule_fn = load_patch("brightness_schedule")
    if brightness_schedule_fn then
        run_patch(logger, plugin, "brightness_schedule", brightness_schedule_fn)
    end

    local disable_night_on_exit_fn = load_patch("disable_night_on_exit")
    if disable_night_on_exit_fn then
        run_patch(logger, plugin, "disable_night_on_exit", disable_night_on_exit_fn)
    end

    local menu_top_swipe_fn = load_patch("menu_top_swipe")
    if menu_top_swipe_fn then
        run_patch(logger, plugin, "menu_top_swipe", menu_top_swipe_fn)
    end

    local opds_fn = load_patch("opds")
    if opds_fn and plugin.config.features.zen_opds ~= false then
        run_patch(logger, plugin, "opds", opds_fn)
    end

    -- Lockdown mode runs last so it wraps any reader-layer patches (e.g. margin_hold_guard).
    local lockdown_mode_fn = load_patch("lockdown_mode")
    if lockdown_mode_fn then
        run_patch(logger, plugin, "lockdown_mode", lockdown_mode_fn)
    end

    local menu_font_fn = load_patch("menu_font")
    if menu_font_fn then
        run_patch(logger, plugin, "menu_font", menu_font_fn)
    end

    -- Hook Device._afterResume / _beforeSuspend directly so schedules always
    -- fire on power events regardless of widget-tree event dispatch.
    local Device = require("device")
    local SCHEDULE_STATES = {
        "__ZEN_UI_NIGHT_SCHEDULE",
        "__ZEN_UI_BRIGHTNESS_SCHEDULE",
        "__ZEN_UI_WARMTH_SCHEDULE",
    }

    if type(Device._afterResume) == "function" then
        local orig_afterResume = Device._afterResume
        Device._afterResume = function(self, ...)
            local result = orig_afterResume(self, ...)
            for _, name in ipairs(SCHEDULE_STATES) do
                local state = rawget(_G, name)
                if type(state) == "table" then
                    local fn = state.force_reschedule or state.reschedule
                    if type(fn) == "function" then pcall(fn) end
                end
            end
            return result
        end
    end

    if type(Device._beforeSuspend) == "function" then
        local orig_beforeSuspend = Device._beforeSuspend
        Device._beforeSuspend = function(self, ...)
            for _, name in ipairs(SCHEDULE_STATES) do
                local state = rawget(_G, name)
                if type(state) == "table" and type(state._on_suspend) == "function" then
                    pcall(state._on_suspend)
                end
            end
            return orig_beforeSuspend(self, ...)
        end
    end

    initialized = true
    return true
end

return M

-- incompatible_plugins_check.lua
-- Detects incompatible plugins via package.loaded (not file system checks).
-- Disables them synchronously before any Zen UI patches run, then prompts restart.
--
-- Each entry:
--   name     = key used in G_reader_settings "plugins_disabled"
--   sentinel = a module that only this plugin loads; used for detection
--
-- Note: ProjectTitle registers as name="coverbrowser" (see its _meta.lua),
-- so its plugins_disabled key is "coverbrowser", not "projecttitle".
-- The sentinel "ptutil" is unique to ProjectTitle and distinguishes it from
-- the stock CoverBrowser plugin.
local INCOMPATIBLE = {
    { name = "simpleui",     sentinel = "sui_core", label = "Simple UI"       },
    { name = "coverbrowser", sentinel = "ptutil",   label = "Project: Title" }, -- registers as coverbrowser
}

-- Returns the plugin directory for an already-loaded sentinel module
-- using debug info, with no file system access.
local function get_dir_from_loaded(sentinel)
    local mod = package.loaded[sentinel]
    if not mod then return nil end
    local src
    if type(mod) == "table" then
        for _, v in pairs(mod) do
            if type(v) == "function" then
                local info = debug.getinfo(v, "S")
                src = info and info.source
                break
            end
        end
    elseif type(mod) == "function" then
        local info = debug.getinfo(mod, "S")
        src = info and info.source
    end
    if src and src:sub(1, 1) == "@" then
        local dir = src:sub(2):match("^(.*)/[^/]+%.lua$")
        return dir and (dir .. "/")
    end
end

-- Returns true if any Zen UI schedule feature is enabled.
local function any_zen_schedule_enabled()
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    return features.brightness_schedule == true
        or features.warmth_schedule     == true
        or features.night_mode_schedule == true
end

local function apply_incompatible_plugins_check()
    if not G_reader_settings then return end

    local disabled_list = G_reader_settings:readSetting("plugins_disabled")
    if type(disabled_list) ~= "table" then disabled_list = {} end

    local needs_restart = false
    local disabled_labels = {}

    -- Disable incompatible plugins. Detection is purely via package.loaded:
    -- if the sentinel module is loaded, the plugin is active this session.
    for _, entry in ipairs(INCOMPATIBLE) do
        if package.loaded[entry.sentinel] and disabled_list[entry.name] == nil then
            local dir = get_dir_from_loaded(entry.sentinel)
            disabled_list[entry.name] = dir or entry.name
            disabled_labels[#disabled_labels + 1] = entry.label
            -- Track that we placed ProjectTitle under the "coverbrowser" key
            -- so the CoverBrowser re-enable logic below does not undo it.
            if entry.sentinel == "ptutil" then
                G_reader_settings:saveSetting("zen_ui_disabled_pt_as_cb", true)
            end
            needs_restart = true
        end
    end

    -- Disable autowarmth only when a Zen UI schedule is active (they conflict).
    if package.loaded["suntime"] and disabled_list["autowarmth"] == nil
            and any_zen_schedule_enabled() then
        local dir = get_dir_from_loaded("suntime")
        disabled_list["autowarmth"] = dir or "autowarmth"
        disabled_labels[#disabled_labels + 1] = "Auto warmth and night mode"
        needs_restart = true
    end

    -- Enable real CoverBrowser if it is installed but disabled.
    -- Skip if we know the "coverbrowser" slot holds ProjectTitle — re-enabling
    -- it would bring the incompatible plugin back.
    local pt_disabled_by_us = G_reader_settings:isTrue("zen_ui_disabled_pt_as_cb")
    local ok_cm = pcall(require, "covermenu")
    if not ok_cm and not pt_disabled_by_us and disabled_list["coverbrowser"] ~= nil then
        disabled_list["coverbrowser"] = nil
        needs_restart = true
    end
    -- Clear the PT flag once ProjectTitle is no longer blocking the slot
    -- (e.g. user uninstalled PT and the "coverbrowser" slot is free again).
    if pt_disabled_by_us and disabled_list["coverbrowser"] == nil then
        G_reader_settings:delSetting("zen_ui_disabled_pt_as_cb")
    end

    if not needs_restart then return end

    G_reader_settings:saveSetting("plugins_disabled", disabled_list)
    G_reader_settings:flush()

    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(0.5, function()
        local _ = require("gettext")
        local ConfirmBox = require("ui/widget/confirmbox")
        local Event = require("ui/event")
        local plugin_list = table.concat(disabled_labels, "\n")
        UIManager:show(ConfirmBox:new{
            text         = _("Incompatible plugins have been disabled:") .. "\n" .. plugin_list,
            dismissable  = false,
            no_ok_button = true,
            cancel_text  = _("Restart now"),
            cancel_callback = function()
                UIManager:broadcastEvent(Event:new("Restart"))
            end,
        })
    end)
end

return apply_incompatible_plugins_check

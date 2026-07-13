-- incompatible_plugins_check.lua
-- Detects incompatible plugins via package.loaded (not file system checks).
-- Two categories:
--   MANUAL_BLOCK  -- Zen UI cannot auto-fix these. User is informed and init is halted.
--   AUTO_DISABLE  -- Zen UI writes plugins_disabled and prompts restart.

-- Returns the plugin directory for an already-loaded sentinel module.
local function get_dir_from_loaded(sentinel)
    local mod = package.loaded[sentinel]
    if not mod then return nil end
    local src
    if type(mod) == "table" then
        for _k, v in pairs(mod) do
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

-- e.g. "/path/to/projecttitle.koplugin/" -> "projecttitle"
local function get_folder_key(dir)
    if not dir then return nil end
    return dir:match("([^/]+)%.koplugin/?$")
end

local function any_zen_schedule_enabled()
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    return features.brightness_schedule == true
        or features.warmth_schedule     == true
        or features.night_mode_schedule == true
end

-- Returns true if Project: Title is truly active (not just self-disabled).
-- PT always requires("ptutil") before its self-disable check, so ptutil is in
-- package.loaded even when PT has self-disabled. The real signal is whether
-- plugins_disabled["coverbrowser"] == true, which is PT's hard load precondition.
local function is_pt_active()
    if package.loaded["ptutil"] == nil then return false end
    local disabled_list = G_reader_settings and G_reader_settings:readSetting("plugins_disabled")
    return type(disabled_list) == "table" and disabled_list["coverbrowser"] == true
end

-- Plugins that Zen UI will auto-disable (writes plugins_disabled, requires restart).
local AUTO_DISABLE = {
    { sentinel = "sui_core", label = "Simple UI", fallback_key = "simpleui" },
}

local function apply_incompatible_plugins_check()
    local logger = require("common/zen_logger").new("incompatible_plugins_check")

    -- Manual-block check: inform user and halt init without touching anything.
    if is_pt_active() then
        logger.warn("Project: Title is active; initialization stopped")
        local UIManager = require("ui/uimanager")
        UIManager:scheduleIn(0.5, function()
            local _ = require("gettext")
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("Project: Title is not compatible with Zen UI.")
                    .. "\n\n" .. _("Please delete the Project: Title plugin from your plugins folder and restart KOReader."),
                show_icon = false,
            })
        end)
        return true
    end
    if not G_reader_settings then
        logger.warn("Unable to determine Project: Title status: G_reader_settings is nil")
        return false
    end

    if package.loaded["ptutil"] ~= nil then
        logger.info("Project: Title is loaded but inactive")
    else
        logger.info("Project: Title is not active")
    end

    local disabled_list = G_reader_settings:readSetting("plugins_disabled")
    if type(disabled_list) ~= "table" then disabled_list = {} end

    local needs_restart = false
    local disabled_labels = {}

    for _i, entry in ipairs(AUTO_DISABLE) do
        local sentinel_loaded = package.loaded[entry.sentinel] ~= nil
        if sentinel_loaded then
            local dir = get_dir_from_loaded(entry.sentinel)
            local folder_key = get_folder_key(dir) or entry.fallback_key
            local already_disabled = disabled_list[folder_key] ~= nil
            logger.info("Compatibility state", entry.label,
                "| loaded=true | folder_key=" .. tostring(folder_key),
                "| already_disabled=" .. tostring(already_disabled))
            if already_disabled then
                -- In disabled_list but still loaded: bad state, force restart.
                logger.warn(entry.label, "is disabled but still loaded; forcing restart")
                disabled_labels[#disabled_labels + 1] = entry.label
                needs_restart = true
            else
                logger.warn("Disabling", entry.label, "| key=" .. folder_key)
                disabled_list[folder_key] = true
                disabled_labels[#disabled_labels + 1] = entry.label
                needs_restart = true
            end
        end
    end

    -- Disable autowarmth when a Zen schedule is active (they conflict).
    if package.loaded["suntime"] ~= nil and disabled_list["autowarmth"] == nil
            and any_zen_schedule_enabled() then
        local dir = get_dir_from_loaded("suntime")
        local folder_key = get_folder_key(dir) or "autowarmth"
        logger.warn("Disabling autowarmth | key=" .. folder_key)
        disabled_list[folder_key] = true
        disabled_labels[#disabled_labels + 1] = "Auto warmth and night mode"
        needs_restart = true
    end

    if not needs_restart then return false end

    G_reader_settings:saveSetting("plugins_disabled", disabled_list)
    G_reader_settings:flush()

    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(0.5, function()
        local _ = require("gettext")
        local ConfirmBox = require("ui/widget/confirmbox")
        local Event = require("ui/event")
        UIManager:show(ConfirmBox:new{
            text         = _("Incompatible plugins have been disabled:") .. "\n" .. table.concat(disabled_labels, "\n"),
            dismissable  = false,
            no_ok_button = true,
            cancel_text  = _("Restart now"),
            cancel_callback = function()
                UIManager:broadcastEvent(Event:new("Restart"))
            end,
        })
    end)
    return true
end

return apply_incompatible_plugins_check

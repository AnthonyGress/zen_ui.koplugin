local _ = require("gettext")

local UIManager = require("ui/uimanager")
local ConfirmBox = require("ui/widget/confirmbox")
local Event = require("ui/event")

local M = {}

local PATCH_MODULES = {
    navbar = "modules/filebrowser/patches/navbar",
    quick_settings = "modules/menu/patches/quick_settings",
    disable_default_koreader_menu_sections = "modules/menu/patches/disable_default_koreader_menu_sections",
    titlebar = "modules/filebrowser/patches/titlebar",
    hide_pagination = "modules/filebrowser/patches/hide_pagination",
    disable_top_menu_swipe_zones = "modules/menu/patches/disable_top_menu_swipe_zones",
    browser_folder_cover = "modules/filebrowser/patches/browser_folder_cover",
    browser_hide_underline = "modules/filebrowser/patches/browser_hide_underline",
    browser_hide_up_folder = "modules/filebrowser/patches/browser_hide_up_folder",
    reader_header_clock = "modules/reader/patches/reader_header_clock",
}

local RESTART_REQUIRED = {
    browser_folder_cover = true,
    browser_hide_underline = true,
    disable_default_koreader_menu_sections = true,
}

local APPLY_MODE = {
    navbar = "filemanager_layout",
    quick_settings = "menu_refresh",
    disable_default_koreader_menu_sections = "menu_refresh",
    titlebar = "filemanager_reinit",
    hide_pagination = "filemanager_reinit",
    disable_top_menu_swipe_zones = "menu_refresh",
    browser_hide_up_folder = "filemanager_refresh",
    reader_header_clock = "reader_refresh",
}

local RUNTIME_PATCHES = rawget(_G, "__ZEN_UI_RUNTIME_PATCHES")
if type(RUNTIME_PATCHES) ~= "table" then
    RUNTIME_PATCHES = {}
    _G.__ZEN_UI_RUNTIME_PATCHES = RUNTIME_PATCHES
end

local function with_plugin(plugin, fn)
    local prev_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    _G.__ZEN_UI_PLUGIN = plugin
    local ok, err = pcall(fn)
    _G.__ZEN_UI_PLUGIN = prev_plugin
    return ok, err
end

local function ensure_patch_loaded(plugin, feature)
    if RUNTIME_PATCHES[feature] then
        return true
    end

    local module_name = PATCH_MODULES[feature]
    if not module_name then
        return true
    end

    local ok_require, patch_fn = pcall(require, module_name)
    if not ok_require or type(patch_fn) ~= "function" then
        return false
    end

    local ok_apply = with_plugin(plugin, patch_fn)
    if ok_apply then
        RUNTIME_PATCHES[feature] = true
    end

    return ok_apply
end

local function maybe_prompt_restart(feature_label)
    UIManager:show(ConfirmBox:new{
        text = _("This setting requires a KOReader restart to fully apply.") .. "\n\n"
            .. feature_label .. "\n\n"
            .. _("Restart now?"),
        ok_text = _("Restart now"),
        cancel_text = _("Later"),
        ok_callback = function()
            UIManager:broadcastEvent(Event:new("Restart"))
        end,
    })
end

local function apply_filemanager_layout()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FileManager and FileManager.instance
    if fm and fm.setupLayout then
        fm:setupLayout()
        UIManager:setDirty(fm, "ui")
    end
end

local function apply_filemanager_reinit()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FileManager and FileManager.instance
    if fm and fm.reinit then
        fm:reinit()
    end
end

local function apply_filemanager_refresh()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok and FileManager and FileManager.instance
    if fm and fm.file_chooser and fm.file_chooser.refreshPath then
        fm.file_chooser:refreshPath()
        UIManager:setDirty(fm, "ui")
    end
end

local function apply_menu_refresh()
    UIManager:setDirty("all", "ui")
end

local function apply_reader_refresh()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    local reader = ok and ReaderUI and ReaderUI.instance
    if reader then
        UIManager:setDirty(reader, "ui")
    end
end

-- Modes that reinitialise or re-layout the FileManager; must not run while the
-- menu is still open or they will reset the menu back to page 1.
local DISRUPTIVE_MODES = {
    filemanager_layout  = true,
    filemanager_reinit  = true,
    filemanager_refresh = true,
}

local deferred_applies    = {}
local deferred_poll_active = false

-- True when the FileManager's TouchMenu overlay is visible.
local function is_filemanager_menu_open()
    local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
    if not ok or not FileManager or not FileManager.instance then return false end
    local fm = FileManager.instance
    return fm.menu ~= nil and fm.menu.menu_container ~= nil
end

local function run_apply_mode_now(mode)
    if mode == "filemanager_layout" then
        apply_filemanager_layout()
    elseif mode == "filemanager_reinit" then
        apply_filemanager_reinit()
    elseif mode == "filemanager_refresh" then
        apply_filemanager_refresh()
    elseif mode == "menu_refresh" then
        apply_menu_refresh()
    elseif mode == "reader_refresh" then
        apply_reader_refresh()
    end
end

-- Called on a 0.25 s interval; applies pending disruptive changes once the
-- menu has been closed.
local function flush_deferred()
    deferred_poll_active = false
    if is_filemanager_menu_open() then
        deferred_poll_active = true
        UIManager:scheduleIn(0.25, flush_deferred)
        return
    end
    local pending = deferred_applies
    deferred_applies = {}
    for mode, _ in pairs(pending) do
        run_apply_mode_now(mode)
    end
end

local function run_apply_mode(mode)
    if DISRUPTIVE_MODES[mode] and is_filemanager_menu_open() then
        deferred_applies[mode] = true
        if not deferred_poll_active then
            deferred_poll_active = true
            UIManager:scheduleIn(0.25, flush_deferred)
        end
        return
    end
    run_apply_mode_now(mode)
end

function M.apply_feature_toggle(plugin, feature, enabled, feature_label)
    if RESTART_REQUIRED[feature] then
        maybe_prompt_restart(feature_label)
        return
    end

    if enabled and not ensure_patch_loaded(plugin, feature) then
        maybe_prompt_restart(feature_label)
        return
    end

    local mode = APPLY_MODE[feature]
    if mode then
        run_apply_mode(mode)
    end
end

return M

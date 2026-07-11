local _ = require("gettext")

local M = {}

local function save_config(plugin)
    if plugin and type(plugin.saveConfig) == "function" then
        plugin:saveConfig()
    end
end

local function get_reader()
    local ok, ReaderUI = pcall(require, "apps/reader/readerui")
    return ok and ReaderUI and ReaderUI.instance or nil
end

local function refresh_reader()
    local reader = get_reader()
    if reader then
        require("ui/uimanager"):setDirty(reader, "ui")
    end
end

local function open_navbar_tab(tab_id)
    local open = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_TAB")
    if type(open) ~= "function" then return false end
    return open(tab_id) ~= false
end

local group_view_show = {
    authors = "showAuthorsView",
    series = "showSeriesView",
    tags = "showTagsView",
}

local function tab_fallback(plugin, tab_id)
    local ok_shared, SharedState = pcall(require, "common/shared_state")
    if not ok_shared then return false end
    if tab_id == "home" then
        local home = SharedState.get(plugin, "home")
        if home and type(home.showHomeView) == "function" then
            home.showHomeView()
            return true
        end
        return false
    end
    local fn_name = group_view_show[tab_id]
    if not fn_name then return false end
    local gv = SharedState.get(plugin, "group_view")
    if not (gv and type(gv[fn_name]) == "function") then return false end
    gv[fn_name](nil)
    return true
end

local function show_tab_from_filemanager(plugin, tab_id)
    if tab_id == "home" then
        local ok_shared, SharedState = pcall(require, "common/shared_state")
        local home = ok_shared and SharedState.get(plugin, "home") or nil
        if home and type(home.isActiveOnTop) == "function" and home.isActiveOnTop() then
            return true
        end
    end
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok_fm and FileManager and FileManager.instance
    if fm then
        require("common/utils").closeWidgetsAbove(fm)
    end
    if open_navbar_tab(tab_id) then return true end
    return tab_fallback(plugin, tab_id)
end

local function show_zen_tab(plugin, tab_id, opts)
    opts = opts or {}
    if not opts.open_home then opts.target_tab = tab_id end
    local reader = get_reader()
    if reader and reader.document then
        return require("common/library_navigation").showFromReader(reader, plugin, opts)
    end
    return show_tab_from_filemanager(plugin, tab_id)
end

local function show_library_from_filemanager()
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok_fm and FileManager and FileManager.instance
    if fm then require("common/utils").closeWidgetsAbove(fm) end

    local open_default = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_DEFAULT_TAB")
    if type(open_default) == "function" then
        open_default()
        return true
    end

    local home_dir = require("common/paths").getHomeDir()
    if fm and fm.file_chooser and home_dir then
        fm.file_chooser.path_items[home_dir] = nil
        fm.file_chooser:changeToPath(home_dir)
        return true
    end
    return false
end

local function show_library(plugin)
    local reader = get_reader()
    if reader and reader.document then
        return require("common/library_navigation").showFromReader(reader, plugin)
    end
    return show_library_from_filemanager()
end

local function show_folder_from_filemanager(folder)
    if type(folder) ~= "string" or folder == "" then return false end
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(folder, "mode") ~= "directory" then
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text = _("Zen UI: folder not found: ") .. folder,
        })
        return false
    end
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    local fm = ok_fm and FileManager and FileManager.instance
    if not fm or not fm.file_chooser then return false end
    require("common/utils").closeWidgetsAbove(fm)
    fm.file_chooser:changeToPath(folder)
    return true
end

local function show_zen_folder(plugin, folder)
    if type(folder) ~= "string" or folder == "" then
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text = _("Zen UI: no folder set for this action."),
        })
        return false
    end
    local reader = get_reader()
    if reader and reader.document then
        return require("common/library_navigation").showFromReader(reader, plugin, { target_folder = folder })
    end
    return show_folder_from_filemanager(folder)
end

local function apply_top_status_bar(plugin, enabled)
    local apply = require("modules/settings/zen_settings_apply")
    apply.apply_feature_toggle(plugin, "reader_top_status_bar", enabled)
end

local function is_top_status_bar_enabled(plugin)
    local features = plugin and plugin.config and plugin.config.features
    return type(features) == "table" and features.reader_top_status_bar == true
end

local function set_top_status_bar(plugin, enabled)
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    if features.reader_top_status_bar == enabled then
        refresh_reader()
        return true
    end
    features.reader_top_status_bar = enabled
    save_config(plugin)
    apply_top_status_bar(plugin, enabled)
    return true
end

local function get_footer()
    local reader = get_reader()
    return reader and reader.view and reader.view.footer or nil
end

local function is_bottom_status_bar_visible()
    local footer = get_footer()
    return footer and footer.view and footer.view.footer_visible == true
end

local function fallback_footer_mode(footer)
    if not footer or type(footer.mode_list) ~= "table" then return 1 end
    return footer.mode_list.page_progress or 1
end

local function set_bottom_status_bar(plugin, enabled)
    local footer = get_footer()
    if not footer then return false end

    local plugin_config = plugin and plugin.config or nil
    local mode_list = footer.mode_list or {}
    local off_mode = mode_list.off or 0
    if enabled then
        local reader_footer = plugin_config and plugin_config.reader_footer
        local last_mode = reader_footer and reader_footer.last_status_bar_mode
        if type(last_mode) ~= "number" or last_mode == off_mode then
            last_mode = G_reader_settings:readSetting("reader_footer_mode")
        end
        if type(last_mode) ~= "number" or last_mode == off_mode then
            last_mode = fallback_footer_mode(footer)
        end
        footer:applyFooterMode(last_mode)
        G_reader_settings:saveSetting("reader_footer_mode", last_mode)
    else
        if plugin_config and type(plugin_config.reader_footer) ~= "table" then
            plugin_config.reader_footer = {}
        end
        if plugin_config and type(footer.mode) == "number" and footer.mode ~= off_mode then
            plugin_config.reader_footer.last_status_bar_mode = footer.mode
            save_config(plugin)
        end
        footer:applyFooterMode(off_mode)
        G_reader_settings:saveSetting("reader_footer_mode", off_mode)
    end

    footer:refreshFooter(true, true)
    if type(footer.rescheduleFooterAutoRefreshIfNeeded) == "function" then
        footer:rescheduleFooterAutoRefreshIfNeeded()
    end
    return true
end

-- Combines KOReader's built-in pull-then-push progress sync (previously the
-- "Sync" quick settings button) into a single bindable action.
local function sync_reading_progress()
    local NetworkMgr = require("ui/network/manager")
    local UIManager = require("ui/uimanager")
    local Event = require("ui/event")
    NetworkMgr:runWhenOnline(function()
        UIManager:broadcastEvent(Event:new("KOSyncPullProgress"))
        -- Push after a short delay to let the pull complete first.
        UIManager:scheduleIn(1, function()
            UIManager:broadcastEvent(Event:new("KOSyncPushProgress"))
        end)
    end)
    return true
end

local function show_zen_toc(plugin)
    local reader = get_reader()
    if not (reader and reader.document and reader.toc) then return false end
    if type(reader.toc.toc) ~= "table" or #reader.toc.toc == 0 then
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text = _("No table of contents available."),
        })
        return true
    end

    local ZenTocWidget = require("modules/reader/zen_toc_widget")
    ZenTocWidget.set_plugin(plugin)

    local focus_page = 1
    if type(reader.getCurrentPage) == "function" then
        local ok, page = pcall(reader.getCurrentPage, reader)
        if ok and type(page) == "number" then
            focus_page = page
        end
    end

    require("ui/uimanager"):show(ZenTocWidget:new{
        ui = reader,
        focus_page = focus_page,
        on_goto = function(page)
            if reader.link then
                reader.link:addCurrentLocationToStack()
            end
            reader:handleEvent(require("ui/event"):new("GotoPage", page))
        end,
    })
    return true
end

local _folder_picker_patched = false

-- Render a per-action folder picker for zen_ui_show_folder. The default Dispatcher
-- menu only builds fixed radio lists for category="string", so we wrap _addItem to
-- append a PathChooser-backed entry to the General section. The chosen path is stored
-- in location[settings].zen_ui_show_folder, i.e. per gesture/profile instance.
local function patch_folder_picker_menu(Dispatcher)
    if _folder_picker_patched then return end
    _folder_picker_patched = true
    local util = require("util")
    local UIManager = require("ui/uimanager")
    local ACTION = "zen_ui_show_folder"

    local orig_addItem = Dispatcher._addItem
    Dispatcher._addItem = function(self, caller, menu, location, settings, section)
        orig_addItem(self, caller, menu, location, settings, section)
        if section ~= "general" then return end

        local function stored_folder()
            return location[settings] ~= nil and location[settings][ACTION] or nil
        end

        table.insert(menu, {
            text_func = function()
                local folder = stored_folder()
                if type(folder) == "string" and folder ~= "" then
                    local name = select(2, util.splitFilePathName(folder))
                    return _("Zen UI - Open folder") .. ": " .. name
                end
                return _("Zen UI - Open folder")
            end,
            checked_func = function()
                return stored_folder() ~= nil
            end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local PathChooser = require("ui/widget/pathchooser")
                local folder = stored_folder()
                local start_path = (type(folder) == "string" and folder ~= "") and folder
                    or G_reader_settings:readSetting("lastdir") or "/"
                UIManager:show(PathChooser:new{
                    select_file = false,
                    show_files = false,
                    path = start_path,
                    onConfirm = function(dir_path)
                        if location[settings] == nil then location[settings] = {} end
                        location[settings][ACTION] = dir_path
                        Dispatcher._addToOrder(location, settings, ACTION)
                        caller.updated = true
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
            hold_callback = function(touchmenu_instance)
                if location[settings] ~= nil and location[settings][ACTION] ~= nil then
                    location[settings][ACTION] = nil
                    Dispatcher._removeFromOrder(location, settings, ACTION)
                    caller.updated = true
                    if touchmenu_instance then touchmenu_instance:updateItems() end
                end
            end,
        })
    end
end

function M.onDispatcherRegisterActions()
    local Dispatcher = require("dispatcher")
    Dispatcher:registerAction("zen_ui_toggle_zen_mode", {
        category = "none",
        event = "ToggleZenMode",
        title = _("Zen UI - Toggle Zen Mode"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_lockdown_mode", {
        category = "none",
        event = "ToggleLockdownMode",
        title = _("Zen UI - Toggle Lockdown Mode"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_incognito_mode", {
        category = "none",
        event = "ToggleIncognitoMode",
        title = _("Zen UI - Toggle Incognito Mode"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_reader_top_status_bar", {
        category = "none",
        event = "ToggleReaderTopStatusBar",
        title = _("Zen UI - Toggle top reader status bar"),
        reader = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_reader_bottom_status_bar", {
        category = "none",
        event = "ToggleReaderBottomStatusBar",
        title = _("Zen UI - Toggle bottom reader status bar"),
        reader = true,
    })
    Dispatcher:registerAction("zen_ui_toggle_reader_status_bars", {
        category = "none",
        event = "ToggleReaderStatusBars",
        title = _("Zen UI - Toggle reader status bars"),
        reader = true,
    })
    Dispatcher:registerAction("zen_ui_show_toc", {
        category = "none",
        event = "ShowZenUIToc",
        title = _("Zen UI - Table of contents"),
        reader = true,
    })
    Dispatcher:registerAction("zen_ui_show_home", {
        category = "none",
        event = "ShowZenUIHome",
        title = _("Zen UI - Home"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_show_library", {
        category = "none",
        event = "ShowZenUILibrary",
        title = _("Zen UI - Library"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_show_authors", {
        category = "none",
        event = "ShowZenUIAuthors",
        title = _("Zen UI - Authors"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_show_series", {
        category = "none",
        event = "ShowZenUISeries",
        title = _("Zen UI - Series"),
        general = true,
    })
    Dispatcher:registerAction("zen_ui_show_tags", {
        category = "none",
        event = "ShowZenUITags",
        title = _("Zen UI - Tags"),
        general = true,
    })
    -- Folder action stores its target path per-gesture (category="string" passes the
    -- stored value to the event). No section flag: the default menu loop skips it, so
    -- our _addItem patch renders a PathChooser in the General section instead of a fixed
    -- radio list. Per-gesture storage means each new action starts with no folder and
    -- users can bind several actions to different folders. Execution isn't gated on the
    -- section flag, so the action still fires in reader and file-browser contexts.
    Dispatcher:registerAction("zen_ui_show_folder", {
        category = "string",
        event = "ShowZenUIFolder",
        title = _("Zen UI - Open folder"),
        args = {},
        toggle = {},
        zen_folder_picker = true,
    })
    Dispatcher:registerAction("zen_ui_kosync_sync", {
        category = "none",
        event = "ZenUIKOSyncSync",
        title = _("Zen UI - Sync progress (pull + push)"),
        general = true,
    })
    patch_folder_picker_menu(Dispatcher)
end

function M.onToggleZenMode(plugin)
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    if features.lockdown_mode == true and features.zen_mode == true then
        return true
    end
    features.zen_mode = not features.zen_mode
    save_config(plugin)
    require("modules/settings/zen_settings_apply").prompt_restart()
    return true
end

function M.onToggleLockdownMode(plugin)
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    local enabling = not features.lockdown_mode
    features.lockdown_mode = enabling
    if enabling then features.zen_mode = true end
    local ok_lm, lockdown_mod = pcall(require, "modules/global/patches/lockdown_mode")
    if ok_lm and type(lockdown_mod) == "table" then
        lockdown_mod.apply_magnify_layout(plugin, enabling)
    end
    save_config(plugin)
    require("modules/settings/zen_settings_apply").prompt_restart()
    return true
end

function M.onToggleIncognitoMode(plugin)
    local features = plugin and plugin.config and plugin.config.features
    if type(features) ~= "table" then return false end
    local enabling = not features.incognito_mode
    features.incognito_mode = enabling
    save_config(plugin)
    require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
        text = enabling and _("Incognito mode enabled") or _("Incognito mode disabled"),
        timeout = 3,
    })
    return true
end

function M.onToggleReaderTopStatusBar(plugin)
    return set_top_status_bar(plugin, not is_top_status_bar_enabled(plugin))
end

M.isBottomStatusBarVisible = is_bottom_status_bar_visible
M.setBottomStatusBar = set_bottom_status_bar

function M.onToggleReaderBottomStatusBar(plugin)
    return set_bottom_status_bar(plugin, not is_bottom_status_bar_visible())
end

function M.onToggleReaderStatusBars(plugin)
    local enable = not (is_top_status_bar_enabled(plugin) or is_bottom_status_bar_visible())
    local top_ok = set_top_status_bar(plugin, enable)
    local bottom_ok = set_bottom_status_bar(plugin, enable)
    return top_ok or bottom_ok
end

function M.onShowZenUIHome(plugin)
    return show_zen_tab(plugin, "home", { open_home = true })
end

function M.onShowZenUILibrary(plugin)
    return show_library(plugin)
end

function M.onShowZenUIAuthors(plugin)
    return show_zen_tab(plugin, "authors")
end

function M.onShowZenUISeries(plugin)
    return show_zen_tab(plugin, "series")
end

function M.onShowZenUITags(plugin)
    return show_zen_tab(plugin, "tags")
end

function M.onShowZenUIFolder(plugin, folder)
    -- category="string": Dispatcher passes the per-action stored folder path as arg.
    return show_zen_folder(plugin, folder)
end

function M.onZenUIKOSyncSync()
    return sync_reading_progress()
end

function M.onShowZenUIToc(plugin)
    return show_zen_toc(plugin)
end

function M.install(target)
    target.onDispatcherRegisterActions = M.onDispatcherRegisterActions
    target.onToggleZenMode = M.onToggleZenMode
    target.onToggleLockdownMode = M.onToggleLockdownMode
    target.onToggleIncognitoMode = M.onToggleIncognitoMode
    target.onToggleReaderTopStatusBar = M.onToggleReaderTopStatusBar
    target.onToggleReaderBottomStatusBar = M.onToggleReaderBottomStatusBar
    target.onToggleReaderStatusBars = M.onToggleReaderStatusBars
    target.onShowZenUIHome = M.onShowZenUIHome
    target.onShowZenUILibrary = M.onShowZenUILibrary
    target.onShowZenUIAuthors = M.onShowZenUIAuthors
    target.onShowZenUISeries = M.onShowZenUISeries
    target.onShowZenUITags = M.onShowZenUITags
    target.onShowZenUIFolder = M.onShowZenUIFolder
    target.onZenUIKOSyncSync = M.onZenUIKOSyncSync
    target.onShowZenUIToc = M.onShowZenUIToc
end

return M

-- i18n must be installed before any other require() so every subsequent
-- require("gettext") in every sub-module receives the wrapped version.
local i18n = require("common/i18n")
i18n.install()

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

-- Early conflict detection: checked before any potentially interfering code
-- (font registration, icon injection) runs at module-load time.
-- ptutil is unique to ProjectTitle and is required at the top of its main.lua,
-- so it will be in package.loaded before our module-level code runs.
local _pt_active = package.loaded["ptutil"] ~= nil
if _pt_active then
    logger.warn("ZenUI [module-load]: ProjectTitle detected via package.loaded['ptutil'] — skipping font registration")
else
    logger.info("ZenUI [module-load]: package.loaded['ptutil'] is nil — no conflict at module-load time")
end

local ConfigManager = require("config/manager")
local registry = require("modules/registry")
local zen_settings = require("modules/settings/zen_settings")
local zen_updater   = require("modules/settings/zen_updater")
local paths         = require("common/paths")
local library_navigation = require("common/library_navigation")

-- Absolute path to this plugin's root directory (shared module resolves relative paths).
local _plugin_root = require("common/plugin_root")

-- Register all plugin icons into KOReader's icon cache (copies to user icons dir).
require("common/inject_icons")
if _plugin_root then
    local utils = require("common/utils")
    -- Override KOReader's default dialog icons with the Zen UI logo.
    local zen_icon = _plugin_root .. "/icons/zen_ui.svg"
    utils.overrideIcons({
        ["notice-info"]     = zen_icon,
        ["notice-question"] = zen_icon,
    })
    -- Register bundled SymbolsNerdFont as last-resort fallback for MDI glyphs.
    -- Skipped when ProjectTitle is active: crengine fails to register the font
    -- on some devices, which causes a width=0 crash in ProjectTitle's TextWidget.
    if not _pt_active then
        local ok_font, Font = pcall(require, "ui/font")
        local ok_fl, FontList = pcall(require, "fontlist")
        if ok_font and Font and Font.fallbacks and ok_fl and FontList then
            pcall(function()
                FontList:getFontList()
                if type(FontList.fontlist) == "table" then
                    table.insert(FontList.fontlist, _plugin_root .. "/fonts/SymbolsNerdFont-Regular.ttf")
                end
                table.insert(Font.fallbacks, "SymbolsNerdFont-Regular.ttf")
            end)
        end
    end
end

-- Holds the single plugin instance so the FileManagerMenu patch can reach it.
local _zen_plugin_ref = nil
-- Weak-keyed table of FileManagerMenu/ReaderMenu instances that have been patched,
-- so the on_update_found callback can rebuild their tab_item_table dynamically.
local _zen_menu_instances = setmetatable({}, { __mode = "k" })

local function refresh_home_date_dependent(plugin)
    local ok_shared, SharedState = pcall(require, "common/shared_state")
    local home = ok_shared and SharedState.get(plugin, "home") or nil
    if home and type(home.refreshDateDependentActive) == "function" then
        home.refreshDateDependentActive()
    end
end

local function build_update_changelog_scroll_text(items)
    if type(items) ~= "table" or #items == 0 then return nil end
    local lines = { _("What's New"), "" }
    for _i, item in ipairs(items) do
        if type(item) == "string" and item ~= "" then
            lines[#lines + 1] = "- " .. item
        end
    end
    if #lines == 2 then return nil end
    return table.concat(lines, "\n")
end

-- Defensive nil-action guard: prevent UIManager:scheduleIn/nextTick(nil) crashes.
-- Installed once per process; logs a traceback so the real culprit can be identified.
-- Catches bugs in Zen UI *and* in KOReader sync plugins (which share the same UIManager).
if not rawget(_G, "__zen_ui_uimgr_guard") then
    _G.__zen_ui_uimgr_guard = true
    local ok_um, UIManager = pcall(require, "ui/uimanager")
    if ok_um and UIManager then
        local _orig_scheduleIn = UIManager.scheduleIn
        UIManager.scheduleIn = function(self, seconds, action, ...)
            if action == nil then
                logger.warn("ZenUI guard: UIManager:scheduleIn(nil) suppressed\n" ..
                    (debug and debug.traceback and debug.traceback("", 2) or ""))
                return
            end
            return _orig_scheduleIn(self, seconds, action, ...)
        end
        local _orig_nextTick = UIManager.nextTick
        UIManager.nextTick = function(self, action, ...)
            if action == nil then
                logger.warn("ZenUI guard: UIManager:nextTick(nil) suppressed\n" ..
                    (debug and debug.traceback and debug.traceback("", 2) or ""))
                return
            end
            return _orig_nextTick(self, action, ...)
        end
    end
end

local ZenUI = WidgetContainer:extend{
    name = "zen_ui",
    is_doc_only = false,
}

require("common/dispatch_action").install(ZenUI)

function ZenUI:saveConfig()
    ConfigManager.save(self.config)
end

local function is_enabled(config, path)
    if not path then
        return true
    end
    local node = config
    for _i, key in ipairs(path) do
        node = node and node[key]
    end
    return node == true
end

function ZenUI:_initModules()
    for _i, def in ipairs(registry) do
        if is_enabled(self.config, def.setting) then
            local ok, module = pcall(require, def.file)
            if ok and module and module.init then
                local loaded_ok = module.init(logger, self)
                if not loaded_ok then
                    logger.warn("zen-ui: module failed to load", def.id)
                end
            else
                logger.warn("zen-ui: module require failed", def.id)
            end
        end
    end
end

function ZenUI:init()
    i18n.install()  -- reinstall after any context-switch uninstall (onCloseWidget removes it)
    self.config = ConfigManager.load()
    _G.__ZEN_UI_LIBRARY_FONT_CFG = self.config and self.config.library_font or nil
    _zen_plugin_ref = self
    self:onDispatcherRegisterActions()
    -- Initialize updater state; release metadata stays live-only.
    zen_updater.init_banner()

    -- Clamp persisted list items-per-page before any browser reads it,
    -- so covers stay legible regardless of where it was set (zen UI,
    -- KOReader's coverbrowser, or a legacy save).
    pcall(function() require("common/cover_utils").getFilesPerPage() end)

    -- Run incompatible-plugin detection before ANY module or patch loads.
    do
        local ok_compat, incompatible_check = pcall(require,
            "modules/filebrowser/patches/incompatible_plugins_check")
        if not ok_compat then
            logger.warn("ZenUI [init]: failed to load incompatible_plugins_check:", incompatible_check)
        elseif type(incompatible_check) == "function" and incompatible_check() then
            logger.warn("ZenUI [init]: conflict found — aborting init, restart pending")
            return
        end
    end

    -- First-run: backup user's original screensaver settings as a preset.
    if not self.config._meta.screensaver_backup_created then
        local PresetStore = require("config/preset_store")
        local backup = {
            name = "backup",
            screensaver_type = G_reader_settings:readSetting("screensaver_type"),
            screensaver_message = G_reader_settings:readSetting("screensaver_message"),
            screensaver_show_message = G_reader_settings:isTrue("screensaver_show_message"),
            screensaver_img_background = G_reader_settings:readSetting("screensaver_img_background"),
            screensaver_document_cover = G_reader_settings:readSetting("screensaver_document_cover"),
            screensaver_stretch_images = G_reader_settings:isTrue("screensaver_stretch_images"),
            screensaver_stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
        }
        PresetStore.save("screensaver", backup.name, backup)
        PresetStore.saveSettings("screensaver", backup)
        PresetStore.setActivePreset("screensaver", backup.name)
        self.config._meta.screensaver_backup_created = true
        self:saveConfig()
    end

    -- First-run: backup user's original footer settings as a preset.
    if not self.config._meta.footer_backup_created then
        local footer_settings = G_reader_settings:readSetting("footer")
        if footer_settings then
            local PresetStore = require("config/preset_store")
            local util = require("util")
            if type(self.config.reader_footer) ~= "table" then
                self.config.reader_footer = {}
            end
            local backup = {
                name = "Backup of Original",
                builtin = true,
                footer = util.tableDeepCopy(footer_settings),
                reader_footer_mode = G_reader_settings:readSetting("reader_footer_mode") or 1,
                reader_footer_custom_text = G_reader_settings:readSetting("reader_footer_custom_text") or "KOReader",
                reader_footer_custom_text_repetitions = G_reader_settings:readSetting("reader_footer_custom_text_repetitions") or 1,
            }
            PresetStore.save("reader", backup.name, backup)
            PresetStore.saveSettings("reader", backup)
            PresetStore.setActivePreset("reader", backup.name)
            self.config._meta.footer_backup_created = true
            self:saveConfig()
        end
    end

    -- First-run: color e-ink screens clip the footer bottom, so bump the
    -- container bottom margin from KOReader's default of 1 to 6.
    if not self.config._meta.footer_color_bottom_padding_applied then
        local Device = require("device")
        if Device:hasColorScreen() then
            local footer_settings = G_reader_settings:readSetting("footer")
            if type(footer_settings) == "table" then
                footer_settings.container_bottom_padding = 6
                G_reader_settings:saveSetting("footer", footer_settings)
            end
        end
        self.config._meta.footer_color_bottom_padding_applied = true
        self:saveConfig()
    end

    -- First-run: default to swipe-only menu activation (KOReader default is tap+swipe).
    if not self.config._meta.menu_activation_defaulted then
        G_reader_settings:saveSetting("activation_menu", "swipe")
        self.config._meta.menu_activation_defaulted = true
        self:saveConfig()
    end

    -- First-run: default sort to recently read, mix files and folders.
    -- Always override: KOReader ships "title" as its own default, so guarding
    -- on readSetting() would silently skip this on a fresh install.
    if not self.config._meta.sort_defaults_applied then
        G_reader_settings:saveSetting("collate", "access")
        G_reader_settings:saveSetting("collate_mixed", true)
        self.config._meta.sort_defaults_applied = true
        self:saveConfig()
    end

    -- First-run: defaults for folder covers (gallery, bottom name, transparent bg)
    -- are now in config/defaults.lua under browser_folder_cover; no explicit init needed.
    -- Guard flag kept so this block doesn't run on every startup for existing installs.
    if not self.config._meta.gallery_mode_defaulted then
        self.config._meta.gallery_mode_defaulted = true
        self:saveConfig()
    end

    -- First-run: default portrait list mode to 5 items per page.
    if not self.config._meta.files_per_page_defaulted then
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if ok_bim then
            BookInfoManager:saveSetting("files_per_page", 5)
            local ok_fc, FileChooser = pcall(require, "ui/widget/filechooser")
            if ok_fc then
                FileChooser.files_per_page = 5
            end
        end
        self.config._meta.files_per_page_defaulted = true
        self:saveConfig()
    end

    self:_initModules()

    -- -----------------------------------------------------------------------
    -- Quickstart / onboarding screen
    -- -----------------------------------------------------------------------
    do
        local function get_plugin_version()
            if _plugin_root then
                local ok, meta = pcall(dofile, _plugin_root .. "/_meta.lua")
                if ok and type(meta) == "table" and type(meta.version) == "string" then
                    return meta.version
                end
            end
            local ok, meta = pcall(require, "_meta")
            return (ok and type(meta) == "table" and type(meta.version) == "string")
                and meta.version or "0.0.0"
        end

        local current_ver = get_plugin_version()
        local shown_ver   = self.config._meta.quickstart_shown_for_version

        -- Normalize sentinel set by manager.lua for existing installs that
        -- predated the quickstart feature. Persisting current_ver prevents
        -- false-positive install and update screens on subsequent boots.
        if shown_ver == "pre-quickstart" then
            shown_ver = current_ver
            self.config._meta.quickstart_shown_for_version = current_ver
            self:saveConfig()
        end

        local updater_cfg = (type(self.config.updater) == "table") and self.config.updater or nil

        -- One-shot flag written by zen_updater before restart; takes priority
        -- over version comparison (handles pre-quickstart installs too).
        local just_updated_ver = updater_cfg and updater_cfg.just_updated_version or ""
        local from_updater = type(just_updated_ver) == "string" and just_updated_ver ~= ""
        if from_updater then
            self.config.updater.just_updated_version = ""
            self:saveConfig()
        end

        local pages_to_show
        local changelog_to_show
        local is_update = from_updater
            or (type(shown_ver) == "string" and shown_ver ~= current_ver)

        local update_channel = (type(self.config.updater) == "table"
            and self.config.updater.update_channel) or "stable"
        logger.info("ZenUI quickstart check: current_ver=", current_ver,
            "shown_ver=", tostring(shown_ver),
            "just_updated_ver=", tostring(just_updated_ver),
            "from_updater=", from_updater,
            "is_update=", is_update,
            "channel=", update_channel)
        if shown_ver == false then
            local ok_pages, pages_mod = pcall(require, "common/quickstart/quickstart_pages")
            if ok_pages then
                pages_to_show = pages_mod.build_install_pages({
                    plugin = self,
                    config = self.config,
                })
            end
        elseif is_update then
            local ok_pages, pages_mod = pcall(require, "common/quickstart/quickstart_pages")
            if ok_pages then
                -- Strip beta suffix (e.g. "1.0.4-beta2" -> "1.0.4") for changelog lookup.
                local stable_ver = current_ver:match("^([%d%.]+)")
                pages_to_show     = pages_mod.UPDATE_PAGES[current_ver]
                changelog_to_show = pages_mod.CHANGELOGS and (
                    pages_mod.CHANGELOGS[current_ver] or pages_mod.CHANGELOGS[stable_ver])
            end
        end

        if shown_ver == false and pages_to_show and #pages_to_show > 0 then
            -- Persist before showing so a force-quit doesn't replay the screen.
            self.config._meta.quickstart_shown_for_version = current_ver
            self:saveConfig()

            require("ui/uimanager"):scheduleIn(0.5, function()
                local ok_qs, QuickstartScreen = pcall(require, "common/quickstart/quickstart_screen")
                if not ok_qs then return end
                require("ui/uimanager"):show(QuickstartScreen:new{
                    pages    = pages_to_show,
                    on_close = function()
                        -- scheduleIn(0) lets UIManager finish the close-frame before
                        -- we force a full repaint and navbar reinject.
                        require("ui/uimanager"):scheduleIn(0, function()
                            if shown_ver == false then -- first install defaults
                                -- Disable CoverBrowser description hint (on by default).
                                local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
                                if ok_bim then
                                    pcall(BookInfoManager.saveSetting, BookInfoManager,
                                        "no_hint_description", true)
                                end
                                -- Disable auto-show bottom menu in reader.
                                G_reader_settings:makeFalse("show_bottom_menu")
                                -- Refresh file manager status bar with the chosen clock format.
                                local ok_fm2, FileManager2 = pcall(require, "apps/filemanager/filemanager")
                                local fm2 = ok_fm2 and FileManager2 and FileManager2.instance
                                if fm2 and type(fm2._updateStatusBar) == "function" then
                                    fm2:_updateStatusBar()
                                end
                            end
                            local reinject = _G.__ZEN_UI_REINJECT_FM_NAVBAR
                            if type(reinject) == "function" then
                                reinject()
                            else
                                -- fallback when navbar feature is disabled
                                local ok, FileManager = pcall(require, "apps/filemanager/filemanager")
                                local fm = ok and FileManager and FileManager.instance
                                if fm and type(fm.onHome) == "function" then fm:onHome() end
                            end
                            -- Navigate to new home_dir if it was set during quickstart
                            -- (reinject only repaints; it doesn't change the FM path).
                            local ok_fm3, FM3 = pcall(require, "apps/filemanager/filemanager")
                            local fm3 = ok_fm3 and FM3 and FM3.instance
                            if fm3 and fm3.file_chooser then
                                local new_home = paths.getHomeDir()
                                if new_home and new_home ~= "" and new_home ~= fm3.file_chooser.path then
                                    fm3.file_chooser:changeToPath(new_home)
                                end
                            end
                        end)
                    end,
                })
            end)
        elseif is_update then
            -- Post-update: always show the ZenScreen splash, then chain UPDATE_PAGES if present.
            self.config._meta.quickstart_shown_for_version = current_ver
            self:saveConfig()
            logger.info("ZenUI update splash: scheduling for version", current_ver, "pages_to_show=", pages_to_show and #pages_to_show or 0)
            require("ui/uimanager"):scheduleIn(0.5, function()
                logger.info("ZenUI update splash: timer fired, requiring zen_screen")
                local ok_zs, ZenScreen = pcall(require, "common/ui/zen_screen")
                if not ok_zs then
                    logger.warn("ZenUI update splash: failed to load zen_screen:", ZenScreen)
                    return
                end
                logger.info("ZenUI update splash: showing ZenScreen")
                local T = require("ffi/util").template
                require("ui/uimanager"):show(ZenScreen:new{
                    title       = _("Zen UI"),
                    title_icon  = true,
                    subtitle    = T(_("Updated to %1"), "v" .. current_ver),
                    changelog   = (type(changelog_to_show) == "table" and #changelog_to_show > 0)
                        and changelog_to_show or nil,
                    scroll_text = build_update_changelog_scroll_text(changelog_to_show),
                    on_close    = function()
                        logger.info("ZenUI update splash: closed, pages_to_show=", pages_to_show and #pages_to_show or 0)
                        if pages_to_show and #pages_to_show > 0 then
                            local ok_qs, QuickstartScreen = pcall(require, "common/quickstart/quickstart_screen")
                            if not ok_qs then
                                logger.warn("ZenUI update splash: failed to load quickstart_screen:", QuickstartScreen)
                                return
                            end
                            logger.info("ZenUI update splash: showing QuickstartScreen")
                            require("ui/uimanager"):show(QuickstartScreen:new{
                                pages = pages_to_show,
                            })
                        end
                    end,
                })
            end)
        end
    end

    -- Inject Zen UI and Library tabs around Quick Settings.
    -- Patches setUpdateItemTable once per class so it persists across menu rebuilds.
    local function find_quicksettings_pos(tab_table)
        for i, tab in ipairs(tab_table) do
            for _i, field in ipairs({ "id", "name", "icon" }) do
                local v = tab[field]
                if type(v) == "string" then
                    local norm = v:lower():gsub("[%s_%-]+", "")
                    if norm == "quicksettings" then
                        return i
                    end
                end
            end
        end
        return nil
    end

    local function take_quicksettings_tab(tab_table)
        local qs_pos = find_quicksettings_pos(tab_table)
        if not qs_pos then return nil, nil end
        return qs_pos, table.remove(tab_table, qs_pos)
    end

    local function take_tab_by_id(tab_table, id)
        for i, tab in ipairs(tab_table) do
            if tab.id == id then
                return i, table.remove(tab_table, i)
            end
        end
        return nil, nil
    end

    local function zen_panel_hidden()
        local _cfg = _zen_plugin_ref and _zen_plugin_ref.config
        local _lc = _cfg and _cfg.lockdown
        local _ft = _cfg and _cfg.features
        return type(_lc) == "table" and _lc.disable_settings_panel == true
            and type(_ft) == "table" and _ft.lockdown_mode == true
    end

    local function flip_lh_rh_icons()
        local _cfg = _zen_plugin_ref and _zen_plugin_ref.config
        local _qs = _cfg and _cfg.quick_settings
        if type(_qs) == "table" and _qs.flip_lh_rh_icon ~= nil then
            return _qs.flip_lh_rh_icon == true
        end
        local _menu = _cfg and _cfg.menu
        return type(_menu) == "table" and _menu.flip_lh_rh_icons == true
    end

    local function library_home_icon()
        local _cfg = _zen_plugin_ref and _zen_plugin_ref.config
        local _menu = _cfg and _cfg.menu
        local icon = type(_menu) == "table" and _menu.library_home_icon
        return (type(icon) == "string" and icon ~= "") and icon or "library"
    end

    local function app_launcher_enabled()
        local _cfg = _zen_plugin_ref and _zen_plugin_ref.config
        local _ft = _cfg and _cfg.features
        return type(_ft) == "table" and _ft.app_launcher == true
    end

    local function remove_zen_menu_tabs(m_self)
        for i = #m_self.tab_item_table, 1, -1 do
            local tab = m_self.tab_item_table[i]
            if tab == m_self._zen_tab_item or tab == m_self._zen_home_tab_item then
                table.remove(m_self.tab_item_table, i)
            end
        end
    end

    local function insert_zen_menu_tabs(m_self, panel_hidden)
        local qs_pos, qs_tab = take_quicksettings_tab(m_self.tab_item_table)
        local app_tab = select(2, take_tab_by_id(m_self.tab_item_table, "app_launcher"))
        if not app_launcher_enabled() then
            app_tab = nil
        end
        if qs_pos and not m_self._zen_qs_insert_pos then
            m_self._zen_qs_insert_pos = qs_pos
        end
        local insert_pos = m_self._zen_qs_insert_pos or qs_pos or 1
        insert_pos = math.min(insert_pos, #m_self.tab_item_table + 1)
        if flip_lh_rh_icons() then
            table.insert(m_self.tab_item_table, insert_pos, m_self._zen_home_tab_item)
            if not panel_hidden then
                table.insert(m_self.tab_item_table, insert_pos + 1, m_self._zen_tab_item)
            end
            if app_tab then
                table.insert(m_self.tab_item_table, app_tab)
            end
            if qs_tab then
                -- Last tab is pushed to far-right by TouchMenuBar's stretch spacer.
                table.insert(m_self.tab_item_table, qs_tab)
            end
        else
            if qs_tab then
                table.insert(m_self.tab_item_table, insert_pos, qs_tab)
            end
            local next_pos = qs_tab and (insert_pos + 1) or insert_pos
            if not panel_hidden then
                table.insert(m_self.tab_item_table, next_pos, m_self._zen_tab_item)
                next_pos = next_pos + 1
            end
            if app_tab then
                table.insert(m_self.tab_item_table, next_pos, app_tab)
            end
            -- Last tab is pushed to far-right by TouchMenuBar's stretch spacer.
            table.insert(m_self.tab_item_table, m_self._zen_home_tab_item)
        end
    end

    local function refresh_zen_menu_tabs(m_self)
        if type(m_self.tab_item_table) ~= "table" or not m_self._zen_home_tab_item then return end
        local panel_hidden = zen_panel_hidden()
        m_self._zen_home_tab_item.icon = library_home_icon()
        if not panel_hidden then
            if not m_self._zen_tab_item then
                m_self._zen_tab_item = zen_settings.build(_zen_plugin_ref).sub_item_table
                m_self._zen_tab_item.id = "zen_ui"
            end
            m_self._zen_tab_item.icon = zen_updater.has_update() and "zen_ui_update" or "zen_settings"
        end
        remove_zen_menu_tabs(m_self)
        insert_zen_menu_tabs(m_self, panel_hidden)
    end

    local function inject_zen_tab(menu_class)
        if not menu_class or menu_class.__zen_ui_tab_patched then return end
        menu_class.__zen_ui_tab_patched = true
        local orig_sut = menu_class.setUpdateItemTable
        menu_class.setUpdateItemTable = function(m_self)
            orig_sut(m_self)
            if type(m_self.tab_item_table) ~= "table" or not _zen_plugin_ref then return end
            -- Remove KOReader's default filebrowser tab; our library tab replaces it.
            for i = #m_self.tab_item_table, 1, -1 do
                if m_self.tab_item_table[i].id == "filemanager" then
                    table.remove(m_self.tab_item_table, i)
                    break
                end
            end
            _zen_menu_instances[m_self] = true
            local _panel_hidden = zen_panel_hidden()
            if not _panel_hidden then
                m_self._zen_tab_item = zen_settings.build(_zen_plugin_ref).sub_item_table
                m_self._zen_tab_item.id = "zen_ui"
            end
            local home_tab = { id = "zen_library_home", icon = library_home_icon(), remember = false }
            home_tab.callback = function()
                require("ui/uimanager"):scheduleIn(0, function()
                    local UIManager = require("ui/uimanager")
                    if m_self.menu_container then
                        UIManager:close(m_self.menu_container)
                        m_self.menu_container = nil
                    end
                    local ui = m_self.ui
                    if not ui then return end
                    if ui.document then
                        library_navigation.showFromReader(ui, _zen_plugin_ref)
                    else
                        local fm = require("apps/filemanager/filemanager").instance
                        if fm then require("common/utils").closeWidgetsAbove(fm) end
                        local open_default = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_DEFAULT_TAB")
                        if type(open_default) == "function" then
                            open_default()
                        else
                            local home_dir = require("common/paths").getHomeDir()
                            if fm and fm.file_chooser and home_dir then
                                fm.file_chooser.path_items[home_dir] = nil
                                fm.file_chooser:changeToPath(home_dir)
                            end
                        end
                    end
                end)
            end
            m_self._zen_home_tab_item = home_tab
            refresh_zen_menu_tabs(m_self)
        end
        -- Refresh the zen tab icon on every menu open so it reflects the
        -- current update state without needing a full tab_item_table rebuild.
        local orig_show = menu_class.onShowMenu
        if type(orig_show) == "function" then
            menu_class.onShowMenu = function(m_self, ...)
                refresh_zen_menu_tabs(m_self)
                return orig_show(m_self, ...)
            end
        end
    end

    local ok_fm, FileManagerMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if ok_fm then inject_zen_tab(FileManagerMenu) end

    local ok_rm, ReaderMenu = pcall(require, "apps/reader/modules/readermenu")
    if ok_rm then inject_zen_tab(ReaderMenu) end

    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end

    -- When the background check finds a new update, refresh the zen-tab icon
    -- on every known menu instance. We update the icon in place rather than
    -- forcing setUpdateItemTable to re-run, because KOReader's MenuSorter
    -- mutates self.menu_items during sorting (it nils out KOMenu:menu_buttons
    -- and every consumed leaf), so a second pass crashes in menusorter.lua at
    -- `ipairs(menu_table["KOMenu:menu_buttons"])`. The onShowMenu patch above
    -- also refreshes the icon, so this is just for the case where a menu
    -- instance already exists when the background check finishes.
    local update_icon = function()
        local icon = zen_updater.has_update() and "zen_ui_update" or "zen_settings"
        for m_instance in pairs(_zen_menu_instances) do
            if m_instance._zen_tab_item then
                m_instance._zen_tab_item.icon = icon
            end
        end
    end
    zen_updater._on_update_found = update_icon

    -- Trigger background update check on fresh startup too, not only on resume.
    zen_updater.schedule_wakeup_check()
end

-- addToMainMenu is a no-op; tab injection is done via the FileManagerMenu patch.
function ZenUI:addToMainMenu(menu_items) -- luacheck: ignore
end

-- On resume: schedule a background update check (if due + network up).
-- Also called from init() so a fresh KOReader start triggers the same check.
function ZenUI:onResume()
    zen_updater.schedule_wakeup_check()
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(0.5, function()
        refresh_home_date_dependent(self)
    end)
    UIManager:scheduleIn(1.5, function()
        refresh_home_date_dependent(self)
    end)
end

-- On suspend: cancel the pending timer so checks don't run while asleep.
function ZenUI:onSuspend()
    zen_updater.cancel_wakeup_check()
end

local function close_zen_standalone_views(shared)
    if type(shared) ~= "table" then return end
    for _i, key in ipairs({ "group_view", "home" }) do
        local view = shared[key]
        if view and type(view.closeAll) == "function" then
            local ok, err = pcall(view.closeAll)
            if not ok then
                logger.warn("zen-ui: failed to close standalone view", key, err)
            end
        end
    end
end

function ZenUI:onCloseWidget()
    close_zen_standalone_views(self._zen_shared)
    i18n.uninstall()
end

-- KOReader PluginLoader calls this only when the user explicitly chooses
-- the "delete plugin settings" action during disable/uninstall.
function ZenUI:deletePluginSettings()
    zen_updater.cancel_wakeup_check()
    zen_updater._on_update_found = nil

    -- Delete the dedicated settings folder.
    pcall(function()
        require("config/preset_store").removeAll()
    end)

    -- Also clean up any legacy G_reader_settings key left from before the
    -- file-based migration completed (e.g., plugin disabled mid-boot).
    local gs = rawget(_G, "G_reader_settings")
    if gs and type(gs.delSetting) == "function" then
        pcall(gs.delSetting, gs, ConfigManager.key())
        pcall(gs.delSetting, gs, "zen_ui_folder_sort")
        pcall(gs.delSetting, gs, "zen_ui_folder_display_mode")
        pcall(gs.flush, gs)
    end

    -- Remove userpatches installed alongside the plugin (e.g. the startup-alert
    -- suppressor seeded into koreader/patches/ at install time). Match any
    -- priority prefix so the patch is removed regardless of load order.
    pcall(function()
        local DataStorage = require("datastorage")
        local lfs = require("libs/libkoreader-lfs")
        local patches_dir = DataStorage:getPatchesDir()
        if lfs.attributes(patches_dir, "mode") ~= "directory" then return end
        for entry in lfs.dir(patches_dir) do
            if entry:match("^%d+%-zen.*%-suppress%-startup%-alerts%.lua$")
                or entry:match("^%d+%-zen[%-_]ui[%-_].*%.lua$") then
                local fullpath = patches_dir .. "/" .. entry
                if lfs.attributes(fullpath, "mode") == "file" then
                    os.remove(fullpath)
                    logger.info("ZenUI: removed userpatch", entry)
                end
            end
        end
    end)

    logger.info("ZenUI: deletePluginSettings completed")
    return true
end

return ZenUI

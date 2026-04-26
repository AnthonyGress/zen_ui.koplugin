-- i18n must be installed before any other require() so every subsequent
-- require("gettext") in every sub-module receives the wrapped version.
local i18n = require("common/i18n")
i18n.install()

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local ConfigManager = require("config/manager")
local registry = require("modules/registry")
local zen_settings = require("modules/settings/zen_settings")
local zen_updater   = require("modules/settings/zen_updater")

-- Absolute path to this plugin's root directory (used for custom icon paths).
local _plugin_root = (function()
    local src = debug.getinfo(1, "S").source or ""
    return (src:sub(1, 1) == "@") and src:sub(2):match("^(.*)/[^/]+$") or nil
end)()

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
    -- Append (not prepend) so KOReader's own icon fonts resolve first; our
    -- custom PUA codepoints are unique enough that they'll still reach this.
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

-- Holds the single plugin instance so the FileManagerMenu patch can reach it.
local _zen_plugin_ref = nil

local ZenUI = WidgetContainer:extend{
    name = "zen_ui",
    is_doc_only = false,
}

function ZenUI:saveConfig()
    ConfigManager.save(self.config)
end

local function is_enabled(config, path)
    if not path then
        return true
    end
    local node = config
    for _, key in ipairs(path) do
        node = node and node[key]
    end
    return node == true
end

function ZenUI:_initModules()
    for _, def in ipairs(registry) do
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
    self.config = ConfigManager.load()
    _zen_plugin_ref = self

    -- First-run: backup user's original screensaver settings as a preset.
    if not self.config._meta.screensaver_backup_created then
        if type(self.config.sleep_screen) ~= "table" then
            self.config.sleep_screen = { presets = {}, active_preset = nil }
        end
        if type(self.config.sleep_screen.presets) ~= "table" then
            self.config.sleep_screen.presets = {}
        end
        local backup = {
            name = "Backup of Original",
            screensaver_type = G_reader_settings:readSetting("screensaver_type"),
            screensaver_message = G_reader_settings:readSetting("screensaver_message"),
            screensaver_show_message = G_reader_settings:isTrue("screensaver_show_message"),
            screensaver_img_background = G_reader_settings:readSetting("screensaver_img_background"),
            screensaver_document_cover = G_reader_settings:readSetting("screensaver_document_cover"),
            screensaver_stretch_images = G_reader_settings:isTrue("screensaver_stretch_images"),
            screensaver_stretch_limit_percentage = G_reader_settings:readSetting("screensaver_stretch_limit_percentage"),
        }
        table.insert(self.config.sleep_screen.presets, 1, backup)
        self.config._meta.screensaver_backup_created = true
        self:saveConfig()
    end

    -- First-run: backup user's original footer settings as a preset.
    if not self.config._meta.footer_backup_created then
        local footer_settings = G_reader_settings:readSetting("footer")
        if footer_settings then
            local util = require("util")
            if type(self.config.reader_footer) ~= "table" then
                self.config.reader_footer = {}
            end
            self.config.reader_footer.backup_preset = {
                name = "Backup of Original",
                footer = util.tableDeepCopy(footer_settings),
                reader_footer_mode = G_reader_settings:readSetting("reader_footer_mode") or 1,
                reader_footer_custom_text = G_reader_settings:readSetting("reader_footer_custom_text") or "KOReader",
                reader_footer_custom_text_repetitions = G_reader_settings:readSetting("reader_footer_custom_text_repetitions") or 1,
            }
            self.config._meta.footer_backup_created = true
            self:saveConfig()
        end
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

    -- First-run: default gallery view ON, folder name bottom + transparent bg.
    if not self.config._meta.gallery_mode_defaulted then
        local ok_bim2, BookInfoManager2 = pcall(require, "bookinfomanager")
        if ok_bim2 then
            BookInfoManager2:saveSetting("folder_gallery_mode", true)
            -- Storing true makes BooleanSetting(default=true).get() return false = off.
            BookInfoManager2:saveSetting("folder_name_centered", true) -- bottom placement
            BookInfoManager2:saveSetting("folder_name_opaque", true)   -- transparent bg
        end
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

        -- One-shot flag written by zen_updater before restart; takes priority
        -- over version comparison (handles pre-quickstart installs too).
        local just_updated_ver = G_reader_settings:readSetting("zen_ui_just_updated")
        local from_updater = type(just_updated_ver) == "string" and just_updated_ver ~= ""
        if from_updater then
            G_reader_settings:delSetting("zen_ui_just_updated")
            pcall(G_reader_settings.flush, G_reader_settings)
        end

        local pages_to_show
        local is_update = from_updater
            or (type(shown_ver) == "string" and shown_ver ~= current_ver)

        logger.info("ZenUI quickstart check: current_ver=", current_ver,
            "shown_ver=", tostring(shown_ver),
            "just_updated_ver=", tostring(just_updated_ver),
            "from_updater=", from_updater,
            "is_update=", is_update)
        if shown_ver == false then
            local ok_pages, pages_mod = pcall(require, "common/quickstart_pages")
            if ok_pages then
                pages_to_show = pages_mod.build_install_pages({
                    plugin = self,
                    config = self.config,
                })
            end
        elseif is_update then
            local ok_pages, pages_mod = pcall(require, "common/quickstart_pages")
            if ok_pages then
                pages_to_show = pages_mod.UPDATE_PAGES[current_ver]
            end
        end

        if shown_ver == false and pages_to_show and #pages_to_show > 0 then
            -- Persist before showing so a force-quit doesn't replay the screen.
            self.config._meta.quickstart_shown_for_version = current_ver
            self:saveConfig()

            require("ui/uimanager"):scheduleIn(0.5, function()
                local ok_qs, QuickstartScreen = pcall(require, "common/quickstart_screen")
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
                                local new_home = G_reader_settings:readSetting("home_dir")
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
                local ok_zs, ZenScreen = pcall(require, "common/zen_screen")
                if not ok_zs then
                    logger.warn("ZenUI update splash: failed to load zen_screen:", ZenScreen)
                    return
                end
                logger.info("ZenUI update splash: showing ZenScreen")
                local T = require("ffi/util").template
                require("ui/uimanager"):show(ZenScreen:new{
                    title    = _("Zen UI"),
                    subtitle = T(_("Updated to %1"), "v" .. current_ver),
                    on_close = function()
                        logger.info("ZenUI update splash: closed, pages_to_show=", pages_to_show and #pages_to_show or 0)
                        if pages_to_show and #pages_to_show > 0 then
                            local ok_qs, QuickstartScreen = pcall(require, "common/quickstart_screen")
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

    -- Inject Zen UI tab after QuickSettings and a Home tab at the far right.
    -- Patches setUpdateItemTable once per class so it persists across menu rebuilds.
    local function find_quicksettings_pos(tab_table)
        for i, tab in ipairs(tab_table) do
            for _, field in ipairs({ "id", "name", "icon" }) do
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

    -- Last tab is pushed to far-right by TouchMenuBar's stretch spacer.
    local function inject_zen_tab(menu_class)
        if not menu_class or menu_class.__zen_ui_tab_patched then return end
        menu_class.__zen_ui_tab_patched = true
        local orig_sut = menu_class.setUpdateItemTable
        menu_class.setUpdateItemTable = function(m_self)
            orig_sut(m_self)
            if type(m_self.tab_item_table) ~= "table" or not _zen_plugin_ref then return end
            -- Insert Zen UI tab right after quicksettings.
            local zen_items = zen_settings.build(_zen_plugin_ref).sub_item_table
            -- Hide the zen tab if lockdown hides the settings panel.
            local _lc = _zen_plugin_ref.config and _zen_plugin_ref.config.lockdown
            local _ft = _zen_plugin_ref.config and _zen_plugin_ref.config.features
            local _panel_hidden = type(_lc) == "table" and _lc.disable_settings_panel == true
                and type(_ft) == "table" and _ft.lockdown_mode == true
            if not _panel_hidden then
                zen_items.icon = "zen_settings"
                local qs_pos = find_quicksettings_pos(m_self.tab_item_table)
                local insert_pos = qs_pos and (qs_pos + 1) or 1
                table.insert(m_self.tab_item_table, insert_pos, zen_items)
            end
            -- Append Home tab at the far right (stretched position).
            local home_tab = { icon = "library", remember = false }
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
                        local file = ui.document.file
                        ui:handleEvent(require("ui/event"):new("CloseConfigMenu"))
                        ui:onClose()
                        if type(ui.showFileManager) == "function" then
                            ui:showFileManager(file)
                        end
                    else
                        local fm = require("apps/filemanager/filemanager").instance
                        if fm then require("common/utils").closeWidgetsAbove(fm) end
                        if type(ui.onHome) == "function" then
                            ui:onHome()
                        end
                    end
                end)
            end
            table.insert(m_self.tab_item_table, home_tab)
        end
    end

    local ok_fm, FileManagerMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if ok_fm then inject_zen_tab(FileManagerMenu) end

    local ok_rm, ReaderMenu = pcall(require, "apps/reader/modules/readermenu")
    if ok_rm then inject_zen_tab(ReaderMenu) end

    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        self.ui.menu:registerToMainMenu(self)
    end
end

-- addToMainMenu is a no-op; tab injection is done via the FileManagerMenu patch.
function ZenUI:addToMainMenu(menu_items) -- luacheck: ignore
end

function ZenUI:onCloseWidget()
    i18n.uninstall()
end

return ZenUI

local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local ConfigManager = require("config/manager")
local registry = require("modules/registry")
local zen_settings = require("settings/zen_settings")

-- Holds the single plugin instance so the FileManagerMenu patch can reach it
-- without needing the __ZEN_UI_PLUGIN global (which is only set transiently).
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

    -- First-run: default portrait list mode to 5 items per page.
    -- We use a plugin-config flag so this fires exactly once (when the plugin is
    -- first installed), regardless of what BookInfoManager already has saved.
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

    -- Inject Zen UI as a dedicated second tab in both FileManager and Reader menus.
    -- We patch setUpdateItemTable once on each class so the tab appears regardless
    -- of how many times the menu is rebuilt.
    -- TouchMenu uses each tab entry directly as the item_table when the tab icon is
    -- tapped (switchMenuTab sets self.item_table = tab_item_table[n]), so the items
    -- must be the numerically-indexed array itself with icon set on the table.
    -- Find the index of the quicksettings tab so our Zen UI tab can be placed
    -- immediately after it (leftmost pairing) in both FileManager and Reader menus.
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

    -- KOReader's TouchMenuBar packs icons 1..N-1 left and pushes icon N to the
    -- far right via a stretch spacer.  We always append a home tab last so it
    -- occupies the far-right slot in both FileManager (QS, ZenUI, Home) and
    -- Reader (QS, ZenUI, [KO section], Home).
    local function inject_zen_tab(menu_class)
        if not menu_class or menu_class.__zen_ui_tab_patched then return end
        menu_class.__zen_ui_tab_patched = true
        local orig_sut = menu_class.setUpdateItemTable
        menu_class.setUpdateItemTable = function(m_self)
            orig_sut(m_self)
            if type(m_self.tab_item_table) ~= "table" or not _zen_plugin_ref then return end
            -- Insert Zen UI tab right after the quicksettings tab.
            local zen_items = zen_settings.build(_zen_plugin_ref).sub_item_table
            zen_items.icon = "appbar.settings"
            local qs_pos = find_quicksettings_pos(m_self.tab_item_table)
            local insert_pos = qs_pos and (qs_pos + 1) or 1
            table.insert(m_self.tab_item_table, insert_pos, zen_items)
            -- Append a Home tab at the far right (last = stretched position).
            -- Captures m_self so the callback can close the menu before navigating.
            local home_tab = { icon = "home", remember = false }
            home_tab.callback = function()
                require("ui/uimanager"):scheduleIn(0, function()
                    if m_self.menu_container then
                        require("ui/uimanager"):close(m_self.menu_container)
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
                    elseif type(ui.onHome) == "function" then
                        ui:onHome()
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

-- Tab injection is done directly via the FileManagerMenu patch above.
-- addToMainMenu is kept as a no-op so KOReader's plugin registry is
-- satisfied but we don't get a duplicate entry inside an existing tab.
function ZenUI:addToMainMenu(menu_items) -- luacheck: ignore
end

return ZenUI

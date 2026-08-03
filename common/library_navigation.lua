local paths = require("common/paths")

local M = {}

local function closeConfigMenuForTransition(ui)
    local was_tearing_down = ui.tearing_down
    ui.tearing_down = true
    local ok, err = pcall(
        ui.handleEvent, ui, require("ui/event"):new("CloseConfigMenu"))
    ui.tearing_down = was_tearing_down
    if not ok then error(err) end
end

local function closeReaderOverlays(ui)
    local was_tearing_down = ui.tearing_down
    ui.tearing_down = true
    local ok, err = pcall(
        require("common/utils").closeWidgetsAbove, ui.dialog or ui)
    ui.tearing_down = was_tearing_down
    if not ok then error(err) end
end

function M.restoreEnabled(plugin)
    local features = plugin and plugin.config and plugin.config.features
    return type(features) == "table" and features.restore_library_view == true
end

local function rakuyomiReturnToChapterListEnabled(plugin)
    local rakuyomi = plugin and plugin.config and plugin.config.rakuyomi
    if type(rakuyomi) ~= "table" then return true end
    if rakuyomi.return_to_chapter_list_on_exit ~= nil then
        return rakuyomi.return_to_chapter_list_on_exit ~= false
    end
    return true
end

function M.returnToRakuyomiReader(restore, plugin)
    if not rakuyomiReturnToChapterListEnabled(plugin) then
        return false
    end
    if not restore and not G_reader_settings:isTrue("allow_commaneer_filemanager") then
        return false
    end
    local ok, MangaReader = pcall(require, "MangaReader")
    if not ok or type(MangaReader) ~= "table"
            or MangaReader.is_showing ~= true
            or type(MangaReader.onReturn) ~= "function" then
        return false
    end
    MangaReader:onReturn()
    return true
end

function M.showFromReader(ui, plugin, opts)
    if not ui or not ui.document then return false end

    opts = type(opts) == "table" and opts or {}
    local file = ui.document.file
    local open_home = opts.open_home == true
    local target_tab = opts.target_tab
    local target_folder = opts.target_folder
    local return_to_default = not open_home and target_tab == nil and target_folder == nil
    local restore = M.restoreEnabled(plugin)
    local outside_home = file and not paths.isInHomeDir(file)
    _G.__ZEN_UI_LAST_READ_FILE = file

    closeConfigMenuForTransition(ui)
    closeReaderOverlays(ui)
    if M.returnToRakuyomiReader(restore, plugin) then
        return true
    end

    ui:onClose()
    if type(ui.showFileManager) == "function" then
        if open_home then
            _G.__ZEN_UI_OPEN_HOME_AFTER_FILEMANAGER = true
        elseif target_tab then
            _G.__ZEN_UI_OPEN_TARGET_TAB = target_tab
        elseif target_folder then
            _G.__ZEN_UI_OPEN_TARGET_FOLDER = target_folder
        elseif return_to_default and not outside_home then
            _G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB = true
        elseif not restore and not outside_home then
            _G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB = true
        elseif outside_home then
            _G.__ZEN_UI_KEEP_BOOK_LOCATION = true
        end
        ui:showFileManager(file)
    end
    return true
end

return M

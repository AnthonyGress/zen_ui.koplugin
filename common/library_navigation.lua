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
    local force_default = opts.force_default == true
    local target_tab = opts.target_tab
    local target_folder = opts.target_folder
    local target_tag = opts.target_tag
    local return_to_default = not open_home and target_tab == nil
        and target_folder == nil and target_tag == nil
    local restore = M.restoreEnabled(plugin)
    local outside_home = file and not paths.isInHomeDir(file)
    _G.__ZEN_UI_LAST_READ_FILE = file

    closeConfigMenuForTransition(ui)
    closeReaderOverlays(ui)
    if M.returnToRakuyomiReader(restore, plugin) then
        return true
    end

    local can_show_file_manager = type(ui.showFileManager) == "function"
    if can_show_file_manager then
        if open_home then
            _G.__ZEN_UI_OPEN_HOME_AFTER_FILEMANAGER = true
        elseif target_tab then
            _G.__ZEN_UI_OPEN_TARGET_TAB = target_tab
        elseif target_folder then
            _G.__ZEN_UI_OPEN_TARGET_FOLDER = target_folder
        elseif target_tag then
            _G.__ZEN_UI_OPEN_TARGET_TAG = target_tag
        elseif force_default or (return_to_default and not outside_home) then
            _G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB = true
        elseif not restore and not outside_home then
            _G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB = true
        elseif outside_home then
            _G.__ZEN_UI_KEEP_BOOK_LOCATION = true
        end
    end

    ui:onClose()
    if can_show_file_manager then
        ui:showFileManager(file)
        -- KOReader bypasses FileManager.showFiles when an instance survived teardown.
        if force_default and rawget(_G, "__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB") == true then
            local open_default = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_DEFAULT_TAB")
            if type(open_default) == "function" then
                _G.__ZEN_UI_FORCE_DEFAULT_LIBRARY_TAB = nil
                _G.__ZEN_UI_LIBRARY_STATE = nil
                open_default()
            end
        end
        if target_folder and rawget(_G, "__ZEN_UI_OPEN_TARGET_FOLDER") ~= nil then
            local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
            local fm = ok_fm and FileManager and FileManager.instance
            if fm and fm.file_chooser then
                _G.__ZEN_UI_OPEN_TARGET_FOLDER = nil
                local open_folder = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_FOLDER")
                if type(open_folder) == "function" then
                    open_folder(target_folder)
                else
                    fm.file_chooser:changeToPath(target_folder)
                end
            end
        end
        if target_tag and rawget(_G, "__ZEN_UI_OPEN_TARGET_TAG") ~= nil then
            local ok_shared, SharedState = pcall(require, "common/shared_state")
            local GroupView = ok_shared and SharedState.get(plugin, "group_view") or nil
            if GroupView and type(GroupView.showTagDetail) == "function" then
                _G.__ZEN_UI_OPEN_TARGET_TAG = nil
                GroupView.showTagDetail(target_tag)
            end
        end
    end
    return true
end

return M

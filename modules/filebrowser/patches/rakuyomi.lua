local M = {}

local FileManager
local Geom
local Screen
local UIManager
local logger
local _

local action_tabs_close_library = {
    continue = true,
    search = true,
    calibre_search = true,
    stats = true,
    exit = true,
}

local is_real_exit_target
local zen_plugin

local function get_zen_config()
    local plugin = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
    if plugin and type(plugin.config) == "table" then
        return plugin.config
    end

    local ok_cm, ConfigManager = pcall(require, "config/manager")
    if ok_cm and ConfigManager and type(ConfigManager.get) == "function" then
        return ConfigManager.get()
    end
end

local function is_library_view(widget)
    return widget and widget.name == "library_view"
end

local function is_chapter_listing(widget)
    return widget and widget.name == "chapter_listing"
end

local function close_top_chapter_listing()
    local stack = UIManager._window_stack
    local top = type(stack) == "table" and stack[#stack]
    local widget = top and top.widget
    if is_chapter_listing(widget) then
        UIManager:close(widget)
    end
end

local function return_to_chapter_list_on_exit_enabled()
    local config = get_zen_config()
    local rakuyomi = config and config.rakuyomi
    if type(rakuyomi) ~= "table" then return true end
    if rakuyomi.return_to_chapter_list_on_exit ~= nil then
        return rakuyomi.return_to_chapter_list_on_exit ~= false
    end
    if rakuyomi.return_to_chapter_list_on_reader_exit ~= nil then
        return rakuyomi.return_to_chapter_list_on_reader_exit ~= false
    end
    return true
end

local function reverse_page_scrolling_enabled()
    local config = get_zen_config()
    local rakuyomi = config and config.rakuyomi
    return type(rakuyomi) == "table" and rakuyomi.reverse_page_scrolling == true
end

local function save_reverse_page_scrolling_for_file(filepath, enabled)
    if type(filepath) ~= "string" or filepath == "" then
        return
    end
    if enabled == nil then enabled = reverse_page_scrolling_enabled() end
    local ok_ds, DocSettings = pcall(require, "docsettings")
    if not ok_ds or not DocSettings then
        return
    end
    local ok_doc, doc_settings = pcall(DocSettings.open, DocSettings, filepath)
    if not ok_doc or not doc_settings then
        return
    end
    doc_settings:saveSetting("inverse_reading_order", enabled == true)
    if type(doc_settings.flush) == "function" then
        pcall(doc_settings.flush, doc_settings)
    end
end

local function apply_reverse_page_scrolling_to_reader(ui, enabled, reason)
    local file = ui and ui.document and ui.document.file
    if not ui then
        return false
    end
    if not M.isChapterFile(file) then
        return false
    end

    enabled = enabled == true
    local view = ui.view
    if ui.doc_settings then
        ui.doc_settings:saveSetting("inverse_reading_order", enabled)
        if type(ui.doc_settings.flush) == "function" then
            pcall(ui.doc_settings.flush, ui.doc_settings)
        end
    else
        save_reverse_page_scrolling_for_file(file, enabled)
    end

    if view then
        local changed = view.inverse_reading_order ~= enabled
        view.inverse_reading_order = enabled
        if changed or ui._zen_rakuyomi_touch_zones_applied ~= enabled then
            if type(view.setupTouchZones) == "function" then
                view:setupTouchZones()
            end
            ui._zen_rakuyomi_touch_zones_applied = enabled
        end
    end
    return true
end

function M.isLibraryView(widget)
    return is_library_view(widget)
end

function M.isScrollBarMenu(widget)
    local name = widget and widget.name
    return name == "available_sources_listing"
        or name == "chapter_listing"
        or name == "installed_sources_listing"
        or name == "library_view"
        or name == "manga_search_results"
        or name == "notification_view"
end

function M.applyReversePageScrollingToCurrentReader(enabled)
    local ok_rui, ReaderUI = pcall(require, "apps/reader/readerui")
    local ui = ok_rui and ReaderUI and ReaderUI.instance
    return apply_reverse_page_scrolling_to_reader(ui, enabled, "settings_toggle")
end

function M.getStandaloneTabId(widget)
    if is_library_view(widget) then
        return "manga"
    end
end

function M.shouldCloseBeforeActionTab(widget, tab_id)
    return is_library_view(widget)
        and (action_tabs_close_library[tab_id] == true
            or type(tab_id) == "string" and tab_id:sub(1, 3) == "ct_")
end

local function normalize_path(path)
    if type(path) ~= "string" or path == "" then return nil end
    return path:gsub("^/sdcard/", "/storage/emulated/0/"):gsub("/+$", "")
end

local function path_is_inside(path, directory)
    path = normalize_path(path)
    directory = normalize_path(directory)
    return path and directory
        and (path == directory or path:sub(1, #directory + 1) == directory .. "/")
end

local function get_data_dir()
    local DataStorage = require("datastorage")
    return DataStorage:getFullDataDir() or DataStorage:getDataDir()
end

local function absolute_data_path(path)
    if type(path) ~= "string" or path == "" or path:sub(1, 1) == "/" then
        return path
    end
    path = path:gsub("^%./", "")
    return get_data_dir() .. "/" .. path
end

local storage_path_loaded = false
local storage_path_cache
local origin_metadata_cache = {}

local function get_storage_path()
    if storage_path_loaded then
        return storage_path_cache
    end
    storage_path_loaded = true
    local home = get_data_dir() .. "/rakuyomi"
    local storage = home .. "/downloads"
    local content = require("util").readFromFile(home .. "/settings.json", "rb")
    if content then
        local ok_json, rapidjson = pcall(require, "rapidjson")
        local ok_decode, settings = false, nil
        if ok_json then
            ok_decode, settings = pcall(rapidjson.decode, content)
        end
        if ok_decode and type(settings) == "table"
                and type(settings.storage_path) == "string"
                and settings.storage_path ~= "" then
            storage = absolute_data_path(settings.storage_path)
        end
    end
    storage_path_cache = normalize_path(storage)
    return storage_path_cache
end

local function read_zip_comment(path)
    local file = io.open(path, "rb")
    if not file then return nil end

    local size = file:seek("end")
    if not size or size <= 0 then
        file:close()
        return nil
    end

    local read_size = math.min(size, 65535 + 22)
    file:seek("set", size - read_size)
    local data = file:read(read_size)
    file:close()
    if not data then return nil end

    for pos = read_size - 21, 1, -1 do
        if data:sub(pos, pos + 3) == "PK\005\006" then
            local len_low = data:byte(pos + 20) or 0
            local len_high = data:byte(pos + 21) or 0
            local comment_len = len_low + len_high * 256
            if pos + 21 + comment_len == read_size and comment_len > 0 then
                return data:sub(pos + 22, pos + 21 + comment_len)
            end
        end
    end
end

local function has_origin_metadata(path)
    if origin_metadata_cache[path] ~= nil then
        return origin_metadata_cache[path]
    end

    local comment = read_zip_comment(path)
    local has_origin = type(comment) == "string"
        and comment:find('"chapter_id"', 1, true) ~= nil
        and comment:find('"manga_id"', 1, true) ~= nil
        and comment:find('"source_id"', 1, true) ~= nil
    origin_metadata_cache[path] = has_origin
    return has_origin
end

function M.isChapterFile(path)
    if type(path) ~= "string" then
        return false
    end

    local storage = get_storage_path()
    local in_storage = path_is_inside(path, storage) == true
    local has_origin = in_storage or has_origin_metadata(path)
    return has_origin
end

local function append_file_opener_candidate(candidates, label, object)
    if type(object) == "table" and type(object.openChapterListingFromFile) == "function" then
        candidates[#candidates + 1] = {
            label = label,
            object = object,
        }
    end
end

local function append_file_opener_candidates(candidates, label, object)
    append_file_opener_candidate(candidates, label .. " method", object)
end

function M.openLibraryView(options)
    local fm = FileManager and FileManager.instance
    local rakuyomi = fm and fm.rakuyomi
    if rakuyomi then
        options = options or { hideTopClose = true }
        rakuyomi:openLibraryView(options)
        if options.forceLibraryView == true then
            close_top_chapter_listing()
            UIManager:nextTick(close_top_chapter_listing)
        end
        return true
    end

    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{
        text = _("Rakuyomi plugin is not installed."),
    })
    return false
end

function M.openChapterListingFromFile(filepath, hide_top_close)
    if type(filepath) ~= "string" or filepath == "" then
        logger.warn("zen-ui rakuyomi-return: invalid chapter-list file")
        return false
    end

    local candidates = {}
    append_file_opener_candidates(candidates, "global RakuyomiShared", rawget(_G, "RakuyomiShared"))
    append_file_opener_candidates(candidates, "package.loaded RakuyomiShared", package.loaded.RakuyomiShared)

    local ok_shared, RakuyomiShared = pcall(require, "RakuyomiShared")
    if ok_shared then
        append_file_opener_candidates(candidates, "require RakuyomiShared", RakuyomiShared)
    end

    local fm = FileManager and FileManager.instance
    local rakuyomi = fm and fm.rakuyomi
    append_file_opener_candidates(candidates, "FileManager.rakuyomi", rakuyomi)
    append_file_opener_candidates(candidates, "FileManager.rakuyomi.shared", rakuyomi and rakuyomi.shared)
    append_file_opener_candidates(
        candidates,
        "FileManager.rakuyomi.RakuyomiShared",
        rakuyomi and rakuyomi.RakuyomiShared)

    for _i, candidate in ipairs(candidates) do
        local ok_open, opened = pcall(
            candidate.object.openChapterListingFromFile,
            candidate.object,
            filepath,
            hide_top_close)
        if ok_open and opened == true then
            return true
        elseif not ok_open then
            logger.warn(
                "zen-ui rakuyomi-return: openChapterListingFromFile failed:",
                candidate.label,
                tostring(opened))
        end
    end

    return false
end

function M.closeLibraryView(widget)
    if not (is_library_view(widget) and type(widget.onClose) == "function") then
        return false
    end
    if widget._zen_rakuyomi_onclose_running then
        return false
    end
    widget._zen_rakuyomi_onclose_running = true
    local ok, err = pcall(widget.onClose, widget)
    widget._zen_rakuyomi_onclose_running = nil
    if not ok then error(err) end
    return true
end

local function openTopMenuFromSwipe(ges)
    if not (ges and ges.direction == "south" and ges.pos
            and ges.pos.y < Screen:getHeight() * 0.05) then
        return false
    end
    local fm = FileManager.instance
    local fm_menu = fm and fm.menu
    if fm_menu and fm_menu.activation_menu ~= "tap" then
        local tab_index = fm_menu:_getTabIndexFromLocation(ges)
        fm_menu:onShowMenu(tab_index)
        return true
    end
    local ok_rui, RUI = pcall(require, "apps/reader/readerui")
    local reader_menu = ok_rui and RUI and RUI.instance and RUI.instance.menu
    if reader_menu and reader_menu.activation_menu ~= "tap" then
        local tab_index = reader_menu:_getTabIndexFromLocation(ges)
        reader_menu:onShowMenu(tab_index)
        return true
    end
    return false
end

function M.patchTopSwipe(widget)
    if not is_library_view(widget) or widget._zen_top_swipe_patched then return end
    widget._zen_top_swipe_patched = true
    local orig_onSwipe = widget.onSwipe
    widget.onSwipe = function(self, arg, ges)
        if openTopMenuFromSwipe(ges) then
            return true
        end
        if orig_onSwipe then return orig_onSwipe(self, arg, ges) end
        return false
    end
end

local function isTransientCover(widget, library_view)
    if not widget or widget == library_view then return true end
    if widget.show_parent == library_view then return true end
    local fm = FileManager.instance
    local fm_menu = fm and fm.menu
    if fm_menu and (widget == fm_menu or widget == fm_menu.menu_container) then
        return true
    end
    return widget.is_popout == true
end

local function closeCoveredLibraryView()
    local stack = UIManager._window_stack
    if type(stack) ~= "table" then return end
    local library_view, library_index
    for i = #stack, 1, -1 do
        local widget = stack[i] and stack[i].widget
        if is_library_view(widget) then
            library_view = widget
            library_index = i
            break
        end
    end
    if not library_view or library_index == #stack then return end
    local top_widget = stack[#stack] and stack[#stack].widget
    if isTransientCover(top_widget, library_view) then
        return
    end
    if type(is_real_exit_target) == "function" and is_real_exit_target(top_widget) then
        M.closeLibraryView(library_view)
    end
end

local function isTopWidget(widget)
    local stack = UIManager._window_stack
    return type(stack) == "table" and stack[#stack] and stack[#stack].widget == widget
end

local function scheduleStackCleanup()
    if UIManager._zen_rakuyomi_stack_cleanup_pending then return end
    UIManager._zen_rakuyomi_stack_cleanup_pending = true
    UIManager:nextTick(function()
        UIManager._zen_rakuyomi_stack_cleanup_pending = nil
        closeCoveredLibraryView()
    end)
end

function M.installCloseGuard(exit_target_predicate)
    if type(exit_target_predicate) == "function" then
        is_real_exit_target = exit_target_predicate
    end
    if UIManager._zen_rakuyomi_close_guard_patched then return end
    UIManager._zen_rakuyomi_close_guard_patched = true
    local orig_show = UIManager.show
    UIManager.show = function(self, ...)
        local result = orig_show(self, ...)
        scheduleStackCleanup()
        return result
    end
    local orig_close = UIManager.close
    UIManager.close = function(self, widget, ...)
        if is_library_view(widget)
                and not widget._zen_rakuyomi_onclose_running
                and type(widget.onClose) == "function" then
            if not isTopWidget(widget) then
                local result = orig_close(self, widget, ...)
                scheduleStackCleanup()
                return result
            end
            return M.closeLibraryView(widget)
        end
        local result = orig_close(self, widget, ...)
        scheduleStackCleanup()
        return result
    end
end

function M.onStandaloneNavbarInjected(widget, exit_target_predicate)
    if not is_library_view(widget) then return end
    M.patchTopSwipe(widget)
    M.installCloseGuard(exit_target_predicate)
end

-- Capture the Rakuyomi return target for *any* book open, not only the
-- Continue-tab resume. showReader is the single choke point every open flows
-- through, and it broadcasts "ShowingReader" before opening. Detect chapter
-- files here so file lists / history / etc. still restore to Rakuyomi.
function M.installShowReaderCapture()
    local ReaderUI = require("apps/reader/readerui")
    if ReaderUI._zen_rakuyomi_showReader_patched then
        return
    end
    ReaderUI._zen_rakuyomi_showReader_patched = true
    local orig_reader_showReader = ReaderUI.showReader
    function ReaderUI:showReader(file, ...)
        if type(file) == "string" then
            local is_chapter = M.isChapterFile(file) == true
            if is_chapter then
                save_reverse_page_scrolling_for_file(file)
            end
            local return_to_chapter_list = return_to_chapter_list_on_exit_enabled()
            if is_chapter then
                _G.__ZEN_UI_LIBRARY_SOURCE_TAB = "manga"
                _G.__ZEN_UI_FORCE_SOURCE_TAB_RESTORE = true
                _G.__ZEN_UI_RAKUYOMI_RETURN_FILE = return_to_chapter_list and file or nil
                if not return_to_chapter_list then
                    close_top_chapter_listing()
                end
            end
        end
        return orig_reader_showReader(self, file, ...)
    end

    local orig_onReaderReady = ReaderUI.onReaderReady
    function ReaderUI:onReaderReady(...)
        local result
        if orig_onReaderReady then
            result = orig_onReaderReady(self, ...)
        end
        apply_reverse_page_scrolling_to_reader(
            self,
            reverse_page_scrolling_enabled(),
            "onReaderReady")
        return result
    end

    local orig_saveSettings = ReaderUI.saveSettings
    function ReaderUI:saveSettings(...)
        apply_reverse_page_scrolling_to_reader(
            self,
            reverse_page_scrolling_enabled(),
            "saveSettings_before")
        return orig_saveSettings(self, ...)
    end

    local orig_onClose = ReaderUI.onClose
    function ReaderUI:onClose(...)
        local file = self.document and self.document.file
        apply_reverse_page_scrolling_to_reader(
            self,
            reverse_page_scrolling_enabled(),
            "onClose_before")
        if M.isChapterFile(file) and not return_to_chapter_list_on_exit_enabled()
                and type(UIManager.avoidFlashOnNextRepaint) == "function" then
            UIManager:avoidFlashOnNextRepaint()
        end
        return orig_onClose(self, ...)
    end

    if ReaderUI.instance then
        apply_reverse_page_scrolling_to_reader(
            ReaderUI.instance,
            reverse_page_scrolling_enabled(),
            "existing_instance")
    end
end

function M.refreshAfterResize(widget)
    if is_library_view(widget) and type(widget.updateItems) == "function"
            and widget.item_group and widget.content_group then
        widget:updateItems(widget.itemnumber)
        return true
    end
    return false
end

function M.configureScrollBarFooter(widget)
    if not M.isScrollBarMenu(widget) or not widget.page_return_arrow then
        return false
    end
    widget.onReturn = false
    widget.page_return_arrow:hide()
    widget.page_return_arrow.show = function() end
    widget.page_return_arrow.showHide = function() end
    widget.page_return_arrow.callback = nil
    widget.page_return_arrow.hold_callback = nil
    widget.page_return_arrow.dimen = Geom:new{ w = 0, h = 0 }
    widget.page_return_arrow.getSize = function()
        return widget.page_return_arrow.dimen
    end
    return true
end

local function apply_rakuyomi()
    if rawget(_G, "__ZEN_UI_RAKUYOMI") == M then
        return
    end

    FileManager = require("apps/filemanager/filemanager")
    Geom = require("ui/geometry")
    Screen = require("device").screen
    UIManager = require("ui/uimanager")
    logger = require("logger")
    _ = require("gettext")

    zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    _G.__ZEN_UI_RAKUYOMI = M
    M.installShowReaderCapture()
end

return apply_rakuyomi

-- This companion plugin is copied only into the isolated test runtime.
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local Event = require("ui/event")
local ffi = require("ffi")
local C = ffi.C
local rapidjson = require("rapidjson")
local UIManager = require("ui/uimanager")

local function find_settings_row_style(widget, seen)
    if type(widget) ~= "table" then return nil end
    seen = seen or {}
    if seen[widget] then return nil end
    seen[widget] = true
    if type(widget._zen_settings_style) == "table" then
        return widget._zen_settings_style
    end
    for _i, child in ipairs(widget) do
        local style = find_settings_row_style(child, seen)
        if style then return style end
    end
end

local function settings_row_standard()
    local IconItem = require("common/ui/icon_menu_item")
    return {
        row_height = IconItem.getSettingsRowHeight(),
        font_size = IconItem.getSettingsFontSize(),
        icon_width = IconItem.SETTINGS_ICON_WIDTH,
        toggle_width = IconItem.SETTINGS_TOGGLE_WIDTH,
        toggle_height = IconItem.SETTINGS_TOGGLE_HEIGHT,
        caret_size = IconItem.SETTINGS_CARET_SIZE,
    }
end

local function active_arrange_widget()
    for index = #UIManager._window_stack, 1, -1 do
        local window = UIManager._window_stack[index]
        local widget = window and window.widget
        local title_bar = widget and widget.title_bar
        if title_bar and title_bar._zen_settings_header then return widget end
    end
end

local function widget_height(widget)
    local size = widget and widget.getSize and widget:getSize()
    return size and size.h or 0
end

local function widget_y(widget)
    return widget and widget.dimen and widget.dimen.y or 0
end

local function filemanager_status_height()
    local FileManager = require("apps/filemanager/filemanager")
    local title_group = FileManager.instance and FileManager.instance.title_bar
        and FileManager.instance.title_bar.title_group
    return widget_height(title_group and title_group[2])
end

local function filemanager_status_y()
    local FileManager = require("apps/filemanager/filemanager")
    local title_group = FileManager.instance and FileManager.instance.title_bar
        and FileManager.instance.title_bar.title_group
    return widget_y(title_group and title_group[2])
end

local function focus_position(widget, target)
    if not (widget and target) then return nil end
    for row_i, row in ipairs(widget.layout or {}) do
        for column_i, control in ipairs(row) do
            if control == target then return column_i, row_i end
        end
    end
    return nil
end

local function is_focus_target(widget, target)
    return focus_position(widget, target) ~= nil
end

local function has_focus_feedback(control)
    if not (control and control.handleEvent) then return false end
    control:handleEvent(Event:new("Focus"))
    local focused = control.invert == true
        or control.image and control.image.invert == true
        or control.frame and control.frame.invert == true
    control:handleEvent(Event:new("Unfocus"))
    return focused
end

ffi.cdef[[
struct zen_test_sockaddr_un { unsigned short sun_family; char sun_path[108]; };
int socket(int domain, int type, int protocol);
int bind(int sockfd, const struct sockaddr *addr, unsigned int addrlen);
int listen(int sockfd, int backlog);
int accept(int sockfd, struct sockaddr *addr, unsigned int *addrlen);
int close(int fd);
long read(int fd, void *buf, unsigned long count);
long write(int fd, const void *buf, unsigned long count);
int unlink(const char *pathname);
int poll(struct pollfd *fds, unsigned long nfds, int timeout);
]]

local AF_UNIX = 1
local SOCK_STREAM = 1
local POLLIN = 1

local function widget_summary(widget, depth)
    if type(widget) ~= "table" or depth > 6 then return nil end
    local summary = { type = tostring(widget), children = {} }
    local size = widget.dimen
    if not size and type(widget.getSize) == "function" then
        local ok, value = pcall(widget.getSize, widget)
        if ok then size = value end
    end
    if type(size) == "table" then
        summary.x = size.x or 0
        summary.y = size.y or 0
        summary.width = size.w or size.width or 0
        summary.height = size.h or size.height or 0
    end
    if type(widget.text) == "string" then summary.text = widget.text end
    if type(widget.icon) == "string" then summary.icon = widget.icon end
    if type(widget.file) == "string" then summary.file = widget.file end
    for index, child in ipairs(widget) do
        if index > 64 then break end
        local described = widget_summary(child, depth + 1)
        if described then summary.children[#summary.children + 1] = described end
    end
    return summary
end

local function visible_ui()
    local windows = {}
    for index = #UIManager._window_stack, 1, -1 do
        local window = UIManager._window_stack[index]
        if window and window.widget then
            windows[#windows + 1] = widget_summary(window.widget, 0)
            if window.widget.covers_fullscreen then break end
        end
    end
    return { windows = windows }
end

local function collect_texts(widget, texts, seen, depth)
    if type(widget) ~= "table" or seen[widget] or depth > 64 then return end
    seen[widget] = true
    if type(widget.text) == "string" then texts[#texts + 1] = widget.text end
    local strip = widget._zen_strip_data
    if type(strip) == "table" then
        if type(strip.title) == "string" then texts[#texts + 1] = strip.title end
        if type(strip.authors) == "string" then texts[#texts + 1] = strip.authors end
    end
    for _i, child in ipairs(widget) do
        collect_texts(child, texts, seen, depth + 1)
    end
end

local count_image_widgets

local function collect_folder_widgets(widget, states, seen, depth)
    if type(widget) ~= "table" or seen[widget] or depth > 64 then return end
    seen[widget] = true
    local entry = widget.entry
    if type(entry) == "table" and not (entry.is_file or entry.file) and entry.path then
        states[#states + 1] = {
            path = entry.path,
            processed = widget._foldercover_processed == true,
            has_cover_frame = widget._cover_frame ~= nil,
        }
    end
    for _i, child in ipairs(widget) do
        collect_folder_widgets(child, states, seen, depth + 1)
    end
end

local function file_chooser_items()
    local FileManager = require("apps/filemanager/filemanager")
    local file_chooser = FileManager.instance and FileManager.instance.file_chooser
    if not file_chooser then return nil end

    local items = {}
    for _i, item in ipairs(file_chooser.item_table or {}) do
        local props = type(item.doc_props) == "table" and item.doc_props or {}
        items[#items + 1] = {
            text = item.text,
            path = item.path or item.file,
            is_file = item.is_file == true,
            is_directory = item.is_directory == true
                or item.mode == "directory"
                or type(item.attr) == "table" and item.attr.mode == "directory",
            mandatory = item.mandatory,
            dim = item.dim,
            title = props.title or props.display_title,
            authors = props.authors,
            series = props.series,
            pages = props.pages,
        }
    end
    local visible_texts = {}
    collect_texts(file_chooser.item_group or file_chooser, visible_texts, {}, 0)
    local folder_widgets = {}
    collect_folder_widgets(file_chooser.item_group or file_chooser, folder_widgets, {}, 0)
    local focused_item
    local focused_index = file_chooser.itemnumber or file_chooser.prev_itemnumber
    if focused_index and file_chooser.item_table then
        focused_item = file_chooser.item_table[focused_index]
    end
    local library_state = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
    return {
        path = file_chooser.path,
        display_mode_type = file_chooser.display_mode_type or file_chooser.display_mode,
        page = file_chooser.page,
        page_count = file_chooser.page_num,
        items_per_page = file_chooser.perpage,
        itemnumber = file_chooser.itemnumber,
        previous_itemnumber = file_chooser.prev_itemnumber,
        focused_path = focused_item and (focused_item.path or focused_item.file),
        active_tab_label = rawget(_G, "__ZEN_UI_ACTIVE_TAB_LABEL"),
        saved_tab = type(library_state) == "table" and library_state.tab or nil,
        image_widget_count = count_image_widgets
            and count_image_widgets(file_chooser.item_group or file_chooser, {}, 0) or 0,
        item_widget_count = type(file_chooser.item_group) == "table" and #file_chooser.item_group or 0,
        items = items,
        folder_widgets = folder_widgets,
        visible_texts = visible_texts,
    }
end

local function file_chooser_cover_state()
    local FileManager = require("apps/filemanager/filemanager")
    local chooser = FileManager.instance and FileManager.instance.file_chooser
    if not chooser then return nil end
    local BookInfoManager = require("bookinfomanager")
    local files = 0
    local fetched = 0
    for _i, item in ipairs(chooser.item_table or {}) do
        local path = item.path or item.file
        if path and (item.is_file or item.file) then
            files = files + 1
            local info = BookInfoManager:getBookInfo(path, false)
            if info and info.cover_fetched then fetched = fetched + 1 end
        end
    end
    return { files = files, fetched = fetched }
end

local function open_book(path)
    local FileManager = require("apps/filemanager/filemanager")
    local file_chooser = FileManager.instance and FileManager.instance.file_chooser
    if not file_chooser or type(file_chooser.onFileSelect) ~= "function" then
        return false, "file chooser unavailable"
    end
    local parent = path:match("^(.*)/[^/]+$")
    if parent and file_chooser.path ~= parent then
        file_chooser:changeToPath(parent)
    end
    local items = file_chooser.item_table or {}
    if parent and type(file_chooser.genItemTableFromPath) == "function" then
        items = file_chooser:genItemTableFromPath(parent)
    end
    for _i, item in ipairs(items) do
        if item.path == path and item.is_file == true then
            file_chooser:onFileSelect(item)
            return true
        end
    end
    local paths = {}
    for _i, item in ipairs(items) do
        if type(item.path) == "string" then paths[#paths + 1] = item.path end
    end
    return false, "book not found in file chooser: " .. table.concat(paths, ", ")
end

local function reader_state()
    local ReaderUI = require("apps/reader/readerui")
    local reader = ReaderUI.instance
    if not reader or not reader.document then return { open = false } end
    local page
    if type(reader.getCurrentPage) == "function" then
        local ok, value = pcall(reader.getCurrentPage, reader)
        if ok then page = value end
    end
    local visible_texts = {}
    collect_texts(reader, visible_texts, {}, 0)
    local library_state = rawget(_G, "__ZEN_UI_LIBRARY_STATE")
    return {
        open = true,
        file = reader.document.file,
        page = page,
        saved_tab = type(library_state) == "table" and library_state.tab or nil,
        saved_page = type(library_state) == "table" and library_state.page or nil,
        active_tab_label = rawget(_G, "__ZEN_UI_ACTIVE_TAB_LABEL"),
        visible_texts = visible_texts,
    }
end

local function find_upvalue(fn, wanted)
    if type(fn) ~= "function" then return nil end
    for index = 1, 128 do
        local name, value = debug.getupvalue(fn, index)
        if not name then return nil end
        if name == wanted then return value end
    end
end

count_image_widgets = function(widget, seen, depth)
    if type(widget) ~= "table" or seen[widget] or depth > 64 then return 0 end
    seen[widget] = true
    local kind = tostring(widget):lower()
    local count = (widget.image ~= nil or kind:find("imagewidget", 1, true)) and 1 or 0
    for _i, child in ipairs(widget) do
        count = count + count_image_widgets(child, seen, depth + 1)
    end
    return count
end

local function home_state()
    local apply_home = require("modules/filebrowser/patches/home_page")
    local register_home_api = find_upvalue(apply_home, "register_home_api")
    local Home = find_upvalue(register_home_api, "M")
    local menu = Home and find_upvalue(Home.hasActive, "_home_menu") or nil
    local visible_texts = {}
    if menu then collect_texts(menu, visible_texts, {}, 0) end
    local widget_ids = {}
    local book_paths = {}
    for _i, target in ipairs(menu and menu._zen_home_focus_targets or {}) do
        local key = type(target.key) == "string" and target.key or ""
        local widget_id = key:match("^widget:(.+)$")
        local book_path = key:match("^book:(.+)$")
        if widget_id then widget_ids[#widget_ids + 1] = widget_id end
        if book_path then book_paths[#book_paths + 1] = book_path end
    end
    return {
        active = Home and Home.hasActive() or false,
        on_top = Home and Home.isActiveOnTop() or false,
        page = Home and Home.getActivePage() or nil,
        active_tab_label = rawget(_G, "__ZEN_UI_ACTIVE_TAB_LABEL"),
        menu_name = menu and menu.name or nil,
        widget_ids = widget_ids,
        book_paths = book_paths,
        clock_refreshers = #(menu and menu._zen_home_clock_refreshers or {}),
        visible_texts = visible_texts,
        image_widget_count = menu and count_image_widgets(menu, {}, 0) or 0,
    }
end

local function navbar_state()
    local FileManager = require("apps/filemanager/filemanager")
    local chooser = FileManager.instance and FileManager.instance.file_chooser
    local stack = UIManager._window_stack
    local top = stack and stack[#stack]
    local widget = top and top.widget
    local visible_texts = {}
    if widget then collect_texts(widget, visible_texts, {}, 0) end
    return {
        active_tab_label = rawget(_G, "__ZEN_UI_ACTIVE_TAB_LABEL"),
        path = chooser and chooser.path or nil,
        display_mode_type = chooser and (chooser.display_mode_type or chooser.display_mode) or nil,
        top_name = widget and widget.name or nil,
        top_tab_id = widget and widget._zen_tab_id or nil,
        visible_texts = visible_texts,
    }
end

local function find_text_widget(widget, text, seen, depth)
    if type(widget) ~= "table" or seen[widget] or depth > 64 then return end
    seen[widget] = true
    if widget.text == text then return widget end
    for _i, child in ipairs(widget) do
        local found = find_text_widget(child, text, seen, depth + 1)
        if found then return found end
    end
end

local function tap_navbar_tab(label)
    local stack = UIManager._window_stack
    local top = stack and stack[#stack] and stack[#stack].widget
    if not top then return false, "top widget unavailable" end

    local navbar
    local function find_navbar(widget, seen, depth)
        if type(widget) ~= "table" or seen[widget] or depth > 64 then return end
        seen[widget] = true
        if type(widget.onTapNavBar) == "function"
                and find_text_widget(widget, label, {}, 0) then
            navbar = widget
            return
        end
        for _i, child in ipairs(widget) do
            find_navbar(child, seen, depth + 1)
            if navbar then return end
        end
    end
    find_navbar(top, {}, 0)
    if not navbar then return false, "navbar tab unavailable: " .. tostring(label) end

    local labels = {}
    collect_texts(navbar, labels, {}, 0)
    local label_index
    for i, value in ipairs(labels) do
        if value == label then
            label_index = i
            break
        end
    end
    local dimen = navbar.dimen
    if not label_index or not dimen or #labels == 0 then
        return false, "navbar label geometry unavailable"
    end
    local pos = {
        x = (dimen.x or 0)
            + math.floor((dimen.w or 1) * (label_index - 0.5) / #labels),
        y = (dimen.y or 0) + math.floor((dimen.h or 1) / 2),
        w = 0,
        h = 0,
    }
    return navbar:onTapNavBar(nil, { pos = pos }) == true
end

local function cover_cache_comparison()
    local FileManager = require("apps/filemanager/filemanager")
    local chooser = FileManager.instance and FileManager.instance.file_chooser
    if not chooser then
        return nil, "file chooser unavailable"
    end
    local cache = require("common/cover_decode_cache")
    local path
    for _i, item in ipairs(chooser.item_table or {}) do
        local candidate = item.path or item.file
        if candidate and cache:has(candidate) then
            path = candidate
            break
        end
    end
    if not path then return nil, "no visible cached cover" end
    local BookInfoManager = require("bookinfomanager")
    local now = require("common/zen_logger").now
    local function delta(after, before)
        local result = {}
        for key, value in pairs(after) do
            if type(value) == "number" then
                result[key] = value - (before[key] or 0)
            end
        end
        return result
    end

    cache:drop(path)
    local before_cold = cache:stats()
    local cold_started_at = now()
    local info = BookInfoManager:getBookInfo(path, true)
    local cold_elapsed_ms = (now() - cold_started_at) * 1000
    if info and info.cover_bb then info.cover_bb:free() end
    local after_cold = cache:stats()

    local warm_started_at = now()
    info = BookInfoManager:getBookInfo(path, true)
    local warm_elapsed_ms = (now() - warm_started_at) * 1000
    if info and info.cover_bb then info.cover_bb:free() end
    local after_warm = cache:stats()
    return {
        path = path,
        cold = {
            elapsed_ms = cold_elapsed_ms,
            delta = delta(after_cold, before_cold),
        },
        warm = {
            elapsed_ms = warm_elapsed_ms,
            delta = delta(after_warm, after_cold),
        },
        total = after_warm,
    }
end

local Driver = WidgetContainer:extend{}

function Driver:init()
    self.socket_path = os.getenv("ZEN_UI_TEST_SOCKET")
    self.testing = os.getenv("ZEN_UI_TESTING") == "1"
    if self.testing and self.socket_path and #self.socket_path < 108 then
        self:startServer()
    end
end

function Driver:startServer()
    pcall(C.unlink, self.socket_path)
    local fd = C.socket(AF_UNIX, SOCK_STREAM, 0)
    if fd < 0 then return end
    local address = ffi.new("struct zen_test_sockaddr_un")
    address.sun_family = AF_UNIX
    ffi.copy(address.sun_path, self.socket_path)
    if C.bind(fd, ffi.cast("struct sockaddr *", address), ffi.sizeof(address)) < 0
            or C.listen(fd, 4) < 0 then
        C.close(fd)
        return
    end
    self.server_fd = fd
    self:pollServer()
end

function Driver:reply(client, payload)
    local encoded = rapidjson.encode(payload) .. "\n"
    C.write(client, encoded, #encoded)
    C.close(client)
end

function Driver:handleCommand(command)
    local kind = command and command.type
    local params = command and command.params or {}
    if kind == "visible_ui" then return { ok = true, ui = visible_ui() } end
    if kind == "plugin_loaded" and type(params.name) == "string" then
        local PluginLoader = require("pluginloader")
        return { ok = true, loaded = PluginLoader:isPluginLoaded(params.name) }
    end
    if kind == "file_chooser_items" then
        local state = file_chooser_items()
        return state and { ok = true, file_chooser = state }
            or { ok = false, error = "file chooser unavailable" }
    end
    if kind == "file_chooser_cover_state" then
        local state = file_chooser_cover_state()
        return state and { ok = true, covers = state }
            or { ok = false, error = "file chooser unavailable" }
    end
    if kind == "open_book" and type(params.path) == "string" then
        local ok, err = open_book(params.path)
        return { ok = ok, error = err }
    end
    if kind == "reader_state" then
        return { ok = true, reader = reader_state() }
    end
    if kind == "page_browser_state" then
        local state = require("reader_tools").page_browser_state()
        return state and { ok = true, page_browser = state }
            or { ok = false, error = "page browser unavailable" }
    end
    if kind == "reader_overlay_state" then
        return { ok = true, overlays = require("reader_tools").overlay_state() }
    end
    if kind == "activate_reader_control" and type(params.name) == "string" then
        local activated, err = require("reader_tools").activate(params.name)
        return { ok = activated == true, activated = activated == true, error = err }
    end
    if kind == "home_state" then
        return { ok = true, home = home_state() }
    end
    if kind == "open_settings_page" then
        local FileManager = require("apps/filemanager/filemanager")
        local menu = FileManager.instance and FileManager.instance.menu
        if not menu then return { ok = false, error = "file manager menu unavailable" } end
        local item = menu._zen_tab_item
        if not item and type(menu.setUpdateItemTable) == "function" then
            menu:setUpdateItemTable()
            item = menu._zen_tab_item
        end
        if not (item and type(item.callback) == "function") then
            return { ok = false, error = "Zen settings tab unavailable" }
        end
        if not menu.menu_container and type(menu.onShowMenu) == "function" then
            menu:onShowMenu()
        end
        local touch_menu = menu.menu_container and menu.menu_container[1]
        local tab_index
        for i, tab in ipairs(menu.tab_item_table or {}) do
            if tab == item then
                tab_index = i
                break
            end
        end
        if touch_menu and tab_index and type(touch_menu.switchMenuTab) == "function" then
            touch_menu:switchMenuTab(tab_index)
        else
            item.callback()
        end
        return { ok = true }
    end
    if kind == "settings_page_state" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        if not page then return { ok = false, error = "settings page unavailable" } end
        local first_row = page.item_group and page.item_group[1]
        local focus_frame = first_row and first_row.item_frame
        local left_zone = page._zones and page._zones.zen_pn_left_tap
        local right_zone = page._zones and page._zones.zen_pn_right_tap
        local left_range = left_zone and left_zone.gs_range and left_zone.gs_range.range
        local right_range = right_zone and right_zone.gs_range and right_zone.gs_range.range
        local labels = {}
        local items = {}
        for _i, item in ipairs(page.item_table or {}) do
            local label = item._zen_display_text or item.text or ""
            local checked
            if type(item.checked_func) == "function" then
                local ok_checked, value = pcall(item.checked_func)
                if ok_checked then checked = value == true end
            end
            labels[#labels + 1] = label
            items[#items + 1] = {
                label = label,
                breadcrumb = item._zen_settings_breadcrumb,
                radio = item.radio == true,
                checked = checked,
            }
        end
        return {
            ok = true,
            settings = {
                title = page.title_bar and page.title_bar.title,
                back_visible = page.title_bar and page.title_bar.back_visible == true,
                status_visible = page.title_bar and page.title_bar.status_widget ~= nil,
                status_height = widget_height(page.title_bar and page.title_bar.status_widget),
                status_spacer_height = widget_height(page.title_bar and page.title_bar._vertical_group
                    and page.title_bar._vertical_group[3]),
                status_y = widget_y(page.title_bar and page.title_bar.status_widget),
                status_identity = tostring(page.title_bar and page.title_bar.status_widget),
                page = page.page,
                page_count = page.page_num,
                pager_x = left_range and left_range.x,
                pager_y = right_range and right_range.y,
                pager_width = left_range and right_range
                    and right_range.x + right_range.w - left_range.x,
                screen_width = page.width,
                title_font_size = page.title_bar and page.title_bar.title_widget
                    and page.title_bar.title_widget.face.orig_size or nil,
                title_bold = page.title_bar and page.title_bar.title_widget
                    and page.title_bar.title_widget.bold == true or false,
                search_active = page._search_active == true,
                has_search_input = page.title_bar and page.title_bar.search_input ~= nil,
                has_search_button = page.title_bar and page.title_bar.search_button ~= nil,
                has_more = page.title_bar and page.title_bar.more_button ~= nil,
                search_text = page.title_bar and page.title_bar.search_input
                    and page.title_bar.search_input:getText() or "",
                search_focused = page.title_bar and page.title_bar.search_input
                    and page.title_bar.search_input.focused == true or false,
                search_keyboard_visible = page.title_bar and page.title_bar.search_input
                    and page.title_bar.search_input:isKeyboardVisible() or false,
                search_text_inset = page.title_bar and page.title_bar.search_frame
                    and page.title_bar.search_frame.dimen
                    and page.title_bar.search_input.dimen
                    and page.title_bar.search_input.dimen.x
                        + page.title_bar.search_input.padding
                        - page.title_bar.search_frame.dimen.x or 0,
                search_radius = page.title_bar and page.title_bar.search_frame
                    and page.title_bar.search_frame.radius or 0,
                shortcuts_enabled = page.is_enable_shortcut == true
                    or page.key_events and page.key_events.SelectByShortCut ~= nil,
                row_focusable = focus_frame and focus_frame.focusable == true,
                row_focus_border_size = focus_frame and focus_frame.focus_border_size,
                row_focus_inner_border = focus_frame and focus_frame.focus_inner_border == true,
                row_focus_feedback = has_focus_feedback(focus_frame),
                row_style = find_settings_row_style(page.item_group),
                standard_style = settings_row_standard(),
                labels = labels,
                items = items,
            },
        }
    end
    if kind == "settings_page_footer_tap" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        if not page then return { ok = false, error = "settings page unavailable" } end
        local pager = require("common/ui/zen_pager")
        local Screen = require("device").screen
        local Geom = require("ui/geometry")
        local width = Screen:getWidth()
        local height = Screen:getHeight()
        local bar_width = math.floor(width * 0.92)
        local bar_x = math.floor((width - bar_width) / 2)
        local zone = params.zone or "right"
        local x = bar_x + math.floor(bar_width / 2)
        if zone == "left" then
            x = bar_x + math.floor(pager.CHEV_W / 2)
        elseif zone == "right" then
            x = bar_x + bar_width - math.floor(pager.CHEV_W / 2)
        end
        local footer_height = pager.getStyle() == "page_number"
            and pager.PN_FOOTER_H or pager.FOOTER_H
        local pager_zone = page._zones and page._zones["zen_pn_" .. zone .. "_tap"]
        local pager_range = pager_zone and pager_zone.gs_range and pager_zone.gs_range.range
        local gesture = {
            ges = "tap",
            pos = Geom:new{
                x = x,
                y = pager_range
                    and pager_range.y + math.floor(pager_range.h / 2)
                    or height - math.floor(footer_height / 2),
                w = 0,
                h = 0,
            },
        }
        local handled = page:handleEvent(Event:new("Gesture", gesture))
        return {
            ok = handled == true,
            page = page.page,
            page_count = page.page_num,
        }
    end
    if kind == "settings_page_titlebar_tap" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        local button = page and page.title_bar
            and page.title_bar[(params.button or "search") .. "_button"]
        if not (page and button and button.dimen) then
            return { ok = false, error = "settings titlebar button unavailable" }
        end
        local Geom = require("ui/geometry")
        local dimen = button.dimen
        local handled = page:handleEvent(Event:new("Gesture", {
            ges = "tap",
            pos = Geom:new{
                x = dimen.x + math.floor(dimen.w / 2),
                y = dimen.y + math.floor(dimen.h / 2),
                w = 0,
                h = 0,
            },
        }))
        return { ok = handled == true }
    end
    if kind == "settings_modal_enter_behavior" then
        if not rawget(_G, "__ZEN_UI_SETTINGS_PAGE") then
            return { ok = false, error = "settings page unavailable" }
        end
        local InputDialog = require("ui/widget/inputdialog")
        local submitted = false
        local dialog = InputDialog:new{
            title = "Keyboard test",
            buttons = {{
                {
                    text = "Set",
                    is_enter_default = true,
                    callback = function() submitted = true end,
                },
            }},
        }
        local input = dialog._input_widget
        local keyboard_closed = false
        local unfocused = false
        input.isKeyboardVisible = function() return true end
        input.onCloseKeyboard = function() keyboard_closed = true end
        input.unfocus = function() unfocused = true end
        local ok_enter, err = pcall(input.enter_callback)
        input:onCloseWidget()
        return {
            ok = ok_enter,
            error = ok_enter and nil or tostring(err),
            dismissed = keyboard_closed and unfocused,
            submitted = submitted,
        }
    end
    if kind == "settings_page_select" and type(params.label) == "string" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        if not page then return { ok = false, error = "settings page unavailable" } end
        for _i, item in ipairs(page.item_table or {}) do
            local label = item._zen_display_text or item.text or ""
            if label == params.label then
                local ok_select, err = pcall(page.onMenuSelect, page, item)
                return { ok = ok_select, error = ok_select and nil or tostring(err) }
            end
        end
        return { ok = false, error = "settings item unavailable" }
    end
    if kind == "settings_page_back" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        if not page then return { ok = false, error = "settings page unavailable" } end
        local ok_back, err = pcall(page.backToUpperMenu, page, true)
        return { ok = ok_back, error = ok_back and nil or tostring(err) }
    end
    if kind == "settings_page_search" and type(params.query) == "string" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        if not page then return { ok = false, error = "settings page unavailable" } end
        local ok_search, err = pcall(page._onSearchChanged, page, params.query)
        return { ok = ok_search, error = ok_search and nil or tostring(err) }
    end
    if kind == "settings_page_type_search" and type(params.text) == "string" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        local title_bar = page and page.title_bar
        local input = title_bar and title_bar.search_input
        if not input and title_bar and type(title_bar.openSearch) == "function" then
            title_bar:openSearch()
            input = title_bar.search_input
        end
        if not input then return { ok = false, error = "settings search unavailable" } end
        local ok_type, err = pcall(function()
            local dimen = title_bar.search_frame and title_bar.search_frame.dimen
            if title_bar.onTapSearch and dimen then
                title_bar:onTapSearch(nil, {
                    pos = {
                        x = dimen.x + math.floor(dimen.w / 2),
                        y = dimen.y + math.floor(dimen.h / 2),
                    },
                })
            else
                input:focus()
            end
            for character in params.text:gmatch(".") do
                UIManager:sendEvent(Event:new("TextInput", character))
            end
        end)
        return { ok = ok_type, error = ok_type and nil or tostring(err) }
    end
    if kind == "settings_page_submit_search" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        local input = page and page.title_bar and page.title_bar.search_input
        if not input then return { ok = false, error = "settings search unavailable" } end
        local ok_submit, err = pcall(input.onTextInput, input, "\n")
        return { ok = ok_submit, error = ok_submit and nil or tostring(err) }
    end
    if kind == "settings_page_non_touch_search" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        local title_bar = page and page.title_bar
        local search_button = title_bar and title_bar.search_button
        local button_x, button_y = focus_position(page, search_button)
        local initial_close_x, initial_close_y = focus_position(page, title_bar and title_bar.close_button)
        if not (title_bar and button_x and button_y and initial_close_x and initial_close_y) then
            return { ok = false, error = "settings search button unavailable" }
        end
        page.selected = { x = button_x, y = button_y }
        local search_button_focused = page.selected.x == button_x and page.selected.y == button_y
        page:onZenSettingsFocusRight()
        local close_focused_from_search = page.selected.x == initial_close_x
            and page.selected.y == initial_close_y
        page:onZenSettingsFocusLeft()
        local search_focused_from_close = page.selected.x == button_x and page.selected.y == button_y
        title_bar:openSearch()
        local input = title_bar.search_input
        local input_x, input_y = focus_position(page, input)
        local close_x, close_y = focus_position(page, title_bar.close_button)
        if not (input and input_x and input_y and close_x and close_y) then
            return { ok = false, error = "settings search input unavailable" }
        end
        local search_input_focused = input_x == page.selected.x and input_y == page.selected.y
        input.focused = true
        input.charpos = #(input.charlist or {}) + 1
        local exited = input:onKeyPress({ Right = true })
        local close_focused = page.selected.x == close_x and page.selected.y == close_y
        title_bar:setQuery("term")
        page:_onSearchChanged("term")
        title_bar.close_button.callback()
        local collapsed_search_x, collapsed_search_y = focus_position(page, title_bar.search_button)
        return {
            ok = true,
            search_button_focused = search_button_focused,
            close_focused_from_search = close_focused_from_search,
            search_focused_from_close = search_focused_from_close,
            search_input_focused = search_input_focused,
            exited = exited == true,
            close_focused = close_focused,
            search_input_focused_after_exit = input.focused == true,
            search_closed = title_bar.search_input == nil and title_bar.query == ""
                and page._search_active == false,
            search_button_focused_after_close = page.selected.x == collapsed_search_x
                and page.selected.y == collapsed_search_y,
        }
    end
    if kind == "arrange_page_state" then
        local widget = active_arrange_widget()
        local title_bar = widget and widget.title_bar
        if not (title_bar and title_bar._zen_settings_header) then
            return { ok = false, error = "arrange page unavailable" }
        end
        local labels = {}
        for _i, item in ipairs(widget.item_table or {}) do
            local label = item._zen_arrange_base_text or item.text or ""
            if type(item.text_func) == "function" then
                local ok_text, value = pcall(item.text_func)
                if ok_text and type(value) == "string" then label = value end
            end
            labels[#labels + 1] = label
        end
        local first_row = widget.main_content and widget.main_content[2]
        local focus_frame = first_row and first_row[1] and first_row[1][1]
        return {
            ok = true,
            arrange = {
                title = title_bar.title,
                back_visible = title_bar.back_button ~= nil,
                has_search = title_bar.search_input ~= nil,
                has_more = title_bar.more_button ~= nil,
                has_close = title_bar.close_button ~= nil,
                has_action = title_bar.action_button ~= nil,
                status_visible = title_bar.status_widget ~= nil,
                status_height = widget_height(title_bar.status_widget),
                status_y = widget_y(title_bar.status_widget),
                status_identity = tostring(title_bar.status_widget),
                filemanager_status_height = filemanager_status_height(),
                filemanager_status_y = filemanager_status_y(),
                page_count = widget.pages,
                pagination_visible = widget.page_info
                    and widget.page_info._zen_arrange_footer_visible == true,
                row_focusable = focus_frame and focus_frame.focusable == true,
                row_focus_border_size = focus_frame and focus_frame.focus_border_size,
                row_focus_inner_border = focus_frame and focus_frame.focus_inner_border == true,
                row_focus_feedback = has_focus_feedback(focus_frame),
                action_focusable = is_focus_target(widget, title_bar.action_button),
                close_focusable = is_focus_target(widget, title_bar.close_button),
                action_focus_feedback = has_focus_feedback(title_bar.action_button),
                close_focus_feedback = has_focus_feedback(title_bar.close_button),
                row_style = find_settings_row_style(widget.main_content),
                standard_style = settings_row_standard(),
                labels = labels,
            },
        }
    end
    if kind == "arrange_page_focus_header" then
        local widget = active_arrange_widget()
        local title_bar = widget and widget.title_bar
        local controls = title_bar and title_bar.generateHorizontalLayout
            and title_bar:generateHorizontalLayout()[1]
        local back_x, back_y = focus_position(widget, title_bar and title_bar.back_button)
        local action_x, action_y = focus_position(widget, title_bar and title_bar.action_button)
        local close_x, close_y = focus_position(widget, title_bar and title_bar.close_button)
        if not (back_x and action_x and close_x and controls) then
            return { ok = false, error = "arrange header controls unavailable" }
        end
        widget.selected = { x = back_x, y = back_y }
        widget:onZenArrangeOpenSubmenu()
        local action_focused = widget.selected.x == action_x and widget.selected.y == action_y
        widget:onZenArrangeOpenSubmenu()
        local close_focused = widget.selected.x == close_x and widget.selected.y == close_y
        title_bar.close_button:handleEvent(Event:new("Unfocus"))
        widget.selected = { x = 1, y = back_y + 1 }
        return { ok = true, action_focused = action_focused, close_focused = close_focused }
    end
    if kind == "arrange_page_top_tap" then
        local widget = active_arrange_widget()
        if not widget then return { ok = false, error = "arrange page unavailable" } end
        local Device = require("device")
        local Geom = require("ui/geometry")
        local FileManager = require("apps/filemanager/filemanager")
        local menu = FileManager.instance and FileManager.instance.menu
        local gesture = {
            ges = "tap",
            pos = Geom:new{
                x = math.floor(Device.screen:getWidth() * (tonumber(params.x_ratio) or 0.5)),
                y = math.floor(Device.screen:getHeight() * (tonumber(params.y_ratio) or 0.01)),
                w = 0,
                h = 0,
            },
        }
        local handled = widget:handleEvent(Event:new("Gesture", gesture))
        local current = active_arrange_widget()
        local menu_open = menu and menu.menu_container ~= nil
        if menu_open and params.close_menu == true
                and type(menu.onCloseFileManagerMenu) == "function" then
            menu:onCloseFileManagerMenu()
        end
        return {
            ok = handled == true,
            same_widget = current == widget,
            marked = current and current.marked,
            title = current and current.title_bar and current.title_bar.title,
            menu_open = menu_open,
        }
    end
    if kind == "arrange_page_action" then
        local widget = active_arrange_widget()
        local title_bar = widget and widget.title_bar
        local button = title_bar and title_bar.action_button
        if not (button and type(button.callback) == "function") then
            return { ok = false, error = "arrange action unavailable" }
        end
        button.callback()
        return { ok = true }
    end
    if kind == "arrange_page_search" and type(params.query) == "string" then
        local widget = active_arrange_widget()
        local title_bar = widget and widget.title_bar
        if not (title_bar and type(title_bar.search_callback) == "function") then
            return { ok = false, error = "arrange search unavailable" }
        end
        title_bar.search_callback(params.query)
        return { ok = true }
    end
    if kind == "close_arrange_page" then
        local widget = active_arrange_widget()
        if not widget then return { ok = false, error = "arrange page unavailable" } end
        if type(widget._zen_arrange_close_all) == "function" then
            widget:_zen_arrange_close_all()
        else
            UIManager:close(widget)
        end
        return { ok = true }
    end
    if kind == "refresh_clock" then
        require("common/clock_timer").refreshNow()
        return { ok = true }
    end
    if kind == "close_settings_page" then
        local page = rawget(_G, "__ZEN_UI_SETTINGS_PAGE")
        if not page then return { ok = false, error = "settings page unavailable" } end
        page:closeMenu()
        return { ok = true }
    end
    if kind == "open_widget_settings" and type(params.id) == "string" then
        local module_name = params.page == "stats"
            and "modules/settings/sections/stats_settings"
            or "modules/settings/sections/library_settings/home_settings"
        local ok_call, opened = pcall(function()
            local plugin = params.page == "stats" and nil
                or require("modules/filebrowser/patches/home_page")
            local register_home_api = type(plugin) == "function"
                and find_upvalue(plugin, "register_home_api") or nil
            return require(module_name).openWidgetSettings(
                params.id,
                register_home_api and find_upvalue(register_home_api, "_zen_plugin") or nil
            )
        end)
        return {
            ok = ok_call and opened == true,
            opened = ok_call and opened == true,
            error = ok_call and nil or tostring(opened),
        }
    end
    if kind == "navbar_state" then
        return { ok = true, navbar = navbar_state() }
    end
    if kind == "activate_navbar_tab" and type(params.id) == "string" then
        local allowed = {
            books = true, home = true, authors = true, series = true,
            tags = true, to_be_read = true,
        }
        local open_tab = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_TAB")
        if not allowed[params.id] then
            return { ok = false, error = "navbar tab is not allowed" }
        end
        if type(open_tab) ~= "function" then
            return { ok = false, error = "navbar callback unavailable" }
        end
        return { ok = open_tab(params.id) == true }
    end
    if kind == "tap_navbar_tab" and type(params.label) == "string" then
        local ok, err = tap_navbar_tab(params.label)
        return { ok = ok == true, error = err }
    end
    if kind == "race_home_to_books" then
        local open_tab = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_TAB")
        if type(open_tab) ~= "function" or open_tab("home") ~= true then
            return { ok = false, error = "Home tab unavailable" }
        end
        UIManager:scheduleIn(0.05, function() open_tab("books") end)
        return { ok = true }
    end
    if kind == "reader_menu_home" then
        local ReaderUI = require("apps/reader/readerui")
        local reader = ReaderUI.instance
        local menu = reader and reader.menu
        if not reader or not reader.document or not menu then
            return { ok = false, error = "reader unavailable" }
        end
        if type(menu.setUpdateItemTable) == "function" then
            menu:setUpdateItemTable()
        end
        local home_item = menu._zen_home_tab_item
        if not home_item or type(home_item.callback) ~= "function" then
            return { ok = false, error = "Zen library Home menu item unavailable" }
        end
        home_item.callback()
        return { ok = true }
    end
    if kind == "file_chooser_next_page" then
        local FileManager = require("apps/filemanager/filemanager")
        local chooser = FileManager.instance and FileManager.instance.file_chooser
        if not chooser or type(chooser.onNextPage) ~= "function" then
            return { ok = false, error = "file chooser unavailable" }
        end
        chooser:onNextPage()
        return { ok = true, page = chooser.page }
    end
    if kind == "cover_cache_stats" then
        return { ok = true, stats = require("common/cover_decode_cache"):stats() }
    end
    if kind == "cover_cache_comparison" then
        local result, err = cover_cache_comparison()
        return result and { ok = true, measurement = result }
            or { ok = false, error = err }
    end
    if kind == "checkpoint" then return { ok = true, name = params.name } end
    if kind == "screenshot" and type(params.output) == "string" then
        local ok, Device = pcall(require, "device")
        if ok and Device and Device.screen and Device.screen.shot then
            local saved = pcall(Device.screen.shot, Device.screen, params.output)
            return { ok = saved }
        end
        return { ok = false, error = "screen capture unavailable" }
    end
    return { ok = false, error = "unknown command" }
end

function Driver:pollServer()
    if not self.server_fd then return end
    local pollfd = ffi.new("struct pollfd")
    pollfd.fd = self.server_fd
    pollfd.events = POLLIN
    if C.poll(pollfd, 1, 0) > 0 then
        local client = C.accept(self.server_fd, nil, nil)
        if client >= 0 then
            local buffer = ffi.new("char[65536]")
            local count = C.read(client, buffer, 65535)
            if count > 0 then
                local ok, command = pcall(rapidjson.decode, ffi.string(buffer, count))
                self:reply(client, ok and self:handleCommand(command) or {
                    ok = false,
                    error = "invalid JSON",
                })
            else
                C.close(client)
            end
        end
    end
    UIManager:scheduleIn(0.1, function() self:pollServer() end)
end

function Driver:onClose()
    if self.server_fd then C.close(self.server_fd) end
    self.server_fd = nil
    if self.socket_path then pcall(C.unlink, self.socket_path) end
end

return Driver

-- This companion plugin is copied only into the isolated test runtime.
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffi = require("ffi")
local C = ffi.C
local rapidjson = require("rapidjson")
local UIManager = require("ui/uimanager")

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
        visible_texts = visible_texts,
    }
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

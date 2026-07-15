describe("file browser navbar navigation", function()
    local FileManager
    local shared
    local calls

    local function class(methods)
        methods = methods or {}
        methods.extend = methods.extend or function(self, child)
            child = child or {}
            child.extend = self.extend
            return setmetatable(child, { __index = self })
        end
        methods.new = methods.new or function(_, values)
            values = values or {}
            values.dimen = values.dimen or { w = values.width or 20, h = values.height or 20 }
            values.getSize = values.getSize or function(self) return self.dimen end
            values.free = values.free or function() end
            return values
        end
        return methods
    end

    before_each(function()
        calls = {}
        shared = {
            home = {
                showHomeView = function() calls[#calls + 1] = "home" end,
                closeAll = function() calls[#calls + 1] = "close_home" end,
            },
            group_view = {
                showAuthorsView = function() calls[#calls + 1] = "authors" end,
                showSeriesView = function() calls[#calls + 1] = "series" end,
                showTagsView = function() calls[#calls + 1] = "tags" end,
                showTBRView = function() calls[#calls + 1] = "to_be_read" end,
                closeAll = function() calls[#calls + 1] = "close_groups" end,
            },
        }
        FileManager = class({
            setupLayout = function() end,
            showFiles = function() end,
            onShowingReader = function() end,
        })
        FileManager.instance = nil
        ZenSpec.replace("apps/filemanager/filemanager", FileManager)
        ZenSpec.replace("ui/widget/filechooser", class({
            init = function() end,
            onPathChanged = function() end,
            onMenuSelect = function() end,
            onClose = function() end,
        }))
        ZenSpec.replace("apps/filemanager/filemanagerhistory", class({ onShowHist = function() end }))
        ZenSpec.replace("apps/filemanager/filemanagerfilesearcher", class({ onShowSearchResults = function() end }))
        ZenSpec.replace("apps/filemanager/filemanagercollection", class({
            onShowColl = function() end,
            onShowCollList = function() end,
        }))
        ZenSpec.replace("apps/filemanager/filemanagerutil", {})
        ZenSpec.replace("ui/widget/menu", class({ init = function() end, updateItems = function() end }))
        for _i, name in ipairs({
            "ui/widget/container/framecontainer", "ui/widget/container/inputcontainer",
            "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/iconwidget",
            "ui/widget/linewidget", "ui/widget/textwidget", "ui/widget/verticalgroup",
            "ui/widget/verticalspan", "ui/widget/widget", "ui/widget/infomessage",
            "ui/gesturerange",
        }) do
            ZenSpec.replace(name, class())
        end
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black", COLOR_DARK_GRAY = "dark", COLOR_WHITE = "white",
        })
        ZenSpec.replace("device", {
            screen = {
                scaleBySize = function(_, value) return value end,
                getWidth = function() return 800 end,
                getHeight = function() return 600 end,
                isColorScreen = function() return false end,
            },
            hasKeys = function() return false end,
        })
        ZenSpec.replace("ui/geometry", {
            new = function(_, values)
                function values:contains() return true end
                return values
            end,
        })
        ZenSpec.replace("ui/event", { new = function(_, name) return { name = name } end })
        ZenSpec.replace("ui/rendertext", { getGlyphByIndex = function() return nil end })
        ZenSpec.replace("dispatcher", {})
        ZenSpec.replace("ui/uimanager", {
            _window_stack = {},
            setDirty = function() end,
            forceRePaint = function() end,
            nextTick = function(_, callback) callback() end,
            scheduleIn = function() end,
            show = function() end,
            close = function() end,
            closeWidgetsAbove = function() end,
            broadcastEvent = function() end,
        })
        ZenSpec.replace("common/utils", {
            deepcopy = function(value)
                if type(value) ~= "table" then return value end
                local result = {}
                for key, child in pairs(value) do result[key] = child end
                return result
            end,
            resolveLocalIcon = function(_, icon) return icon end,
            closeWidgetsAbove = function() end,
        })
        ZenSpec.replace("common/paths", { getHomeDir = function() return "/library" end })
        ZenSpec.replace("common/plugin_root", "/plugin")
        ZenSpec.replace("common/shared_state", {
            get = function(_, key) return shared[key] end,
        })
        ZenSpec.replace("common/ui/background", {
            library_active = function() return false end,
        })
        ZenSpec.replace("modules/menu/app_launcher/plugin_scan", {})
        ZenSpec.replace("modules/filebrowser/patches/library_font", {
            getFace = function(size) return { size = size } end,
            scaleValue = function(value) return value end,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, field)
                if field == "mode" and path == "/library" then return "directory" end
            end,
            dir = function() return function() end end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("common/zen_logger", {
            new = function() return { dbg = function() end, perf = function() end, warn = function() end } end,
        })
        _G.G_reader_settings = ZenSpec.memorySettings()
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { navbar = true, restore_library_view = false },
                navbar = {
                    show_tabs = {
                        books = true, home = true, authors = true, series = true,
                        tags = true, to_be_read = true, history = true,
                        favorites = true, collections = true, search = true,
                        page_left = true, page_right = true, menu = true,
                    },
                    tab_order = {
                        "home", "books", "authors", "series", "tags", "to_be_read",
                        "history", "favorites", "collections", "search",
                        "page_left", "page_right", "menu",
                    },
                    default_tab = "home",
                    show_icons = false,
                    show_labels = true,
                },
            },
        }
        ZenSpec.unload("modules/filebrowser/patches/navbar")
        require("modules/filebrowser/patches/navbar")()
    end)

    after_each(function()
        for _i, name in ipairs({
            "__ZEN_UI_PLUGIN", "__ZEN_UI_NAVBAR_OPEN_DEFAULT_TAB", "__ZEN_UI_NAVBAR_OPEN_TAB",
            "__ZEN_UI_NAVBAR_RESOLVE_DEFAULT_TAB", "__ZEN_UI_ACTIVE_TAB_LABEL",
            "__ZEN_UI_REINJECT_FM_NAVBAR", "__ZEN_UI_REINJECT_NAVBARS",
        }) do
            _G[name] = nil
        end
    end)

    local function make_instance()
        local instance = {
            file_chooser = {
                path = "/library/subfolder",
                path_items = {},
                item_table = {},
                changeToPath = function(_, path) calls[#calls + 1] = "books:" .. path end,
                onPrevPage = function() calls[#calls + 1] = "previous" end,
                onNextPage = function() calls[#calls + 1] = "next" end,
                showFileDialog = function() calls[#calls + 1] = "menu" end,
            },
            history = { onShowHist = function() calls[#calls + 1] = "history" end },
            collections = {
                onShowColl = function() calls[#calls + 1] = "favorites" end,
                onShowCollList = function() calls[#calls + 1] = "collections" end,
            },
            filesearcher = { onShowFileSearch = function() calls[#calls + 1] = "search" end },
        }
        FileManager.instance = instance
        return instance
    end

    it("keeps configured tab order and resolves the first enabled default", function()
        assert.are.equal("home", _G.__ZEN_UI_NAVBAR_RESOLVE_DEFAULT_TAB())
        assert.are.same({
            "home", "books", "authors", "series", "tags", "to_be_read",
            "history", "favorites", "collections", "search",
            "page_left", "page_right", "menu",
        }, { unpack(_G.__ZEN_UI_PLUGIN.config.navbar.tab_order, 1, 13) })
        assert.are.equal("Home", _G.__ZEN_UI_ACTIVE_TAB_LABEL)
    end)

    it("dispatches persistent tabs to their intended library views and tracks active state", function()
        make_instance()
        for _i, id in ipairs({ "home", "authors", "series", "tags", "to_be_read" }) do
            assert.is_true(_G.__ZEN_UI_NAVBAR_OPEN_TAB(id))
            assert.are.equal(id == "to_be_read" and "To Be Read" or id:gsub("^%l", string.upper),
                _G.__ZEN_UI_ACTIVE_TAB_LABEL)
        end
        assert.are.same({ "home", "authors", "series", "tags", "to_be_read" }, calls)
    end)

    it("dispatches books and stock file-browser tabs to their intended actions", function()
        make_instance()
        for _i, id in ipairs({
            "books", "history", "favorites", "collections", "search",
            "page_left", "page_right", "menu",
        }) do
            assert.is_true(_G.__ZEN_UI_NAVBAR_OPEN_TAB(id))
        end
        assert.are.same({
            "books:/library", "history", "favorites", "collections", "search",
            "previous", "next", "menu",
        }, calls)
        assert.are.equal("Collections", _G.__ZEN_UI_ACTIVE_TAB_LABEL)
    end)

    it("rejects unknown tab ids without changing the active tab", function()
        make_instance()
        assert.is_true(_G.__ZEN_UI_NAVBAR_OPEN_TAB("authors"))
        assert.is_false(_G.__ZEN_UI_NAVBAR_OPEN_TAB("not-a-tab"))
        assert.are.equal("Authors", _G.__ZEN_UI_ACTIVE_TAB_LABEL)
    end)
end)

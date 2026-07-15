describe("file browser guard patches", function()
    local original_plugin

    local function apply_patch(name)
        ZenSpec.unload(name)
        require(name)()
    end

    before_each(function()
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        _G.G_reader_settings = ZenSpec.memorySettings()
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = original_plugin
    end)

    it("shows hidden and unsupported files only outside the library home", function()
        local observed = {}
        local FileChooser
        FileChooser = {
            show_hidden = true,
            show_unsupported = true,
            getList = function(self, path, collate)
                observed[#observed + 1] = {
                    path = path,
                    collate = collate,
                    hidden = FileChooser.show_hidden,
                    unsupported = FileChooser.show_unsupported,
                }
                return "stock"
            end,
        }
        ZenSpec.replace("ui/widget/filechooser", FileChooser)
        ZenSpec.replace("common/paths", {
            getHomeDir = function() return "/library" end,
            normPath = function(path) return path end,
        })
        _G.__ZEN_UI_PLUGIN = {
            config = { developer = { show_hidden_outside_home = true } },
        }

        apply_patch("modules/filebrowser/patches/browser_show_hidden")
        local chooser = { name = "filemanager", path = "/library" }
        assert.are.equal("stock", FileChooser.getList(chooser, "/library/series/", "natural"))
        assert.is_false(observed[1].hidden)
        assert.is_false(observed[1].unsupported)
        assert.is_false(G_reader_settings:readSetting("show_hidden"))

        assert.are.equal("stock", FileChooser.getList(chooser, "/mnt/usb", "date"))
        assert.is_true(observed[2].hidden)
        assert.is_true(observed[2].unsupported)
        assert.is_true(G_reader_settings:readSetting("show_unsupported"))
    end)

    it("does not change hidden-file policy for non-file-manager choosers", function()
        local FileChooser = {
            show_hidden = false,
            show_unsupported = false,
            getList = function() return {} end,
        }
        ZenSpec.replace("ui/widget/filechooser", FileChooser)
        ZenSpec.replace("common/paths", {
            getHomeDir = function() return "/library" end,
            normPath = function(path) return path end,
        })
        _G.__ZEN_UI_PLUGIN = {
            config = { developer = { show_hidden_outside_home = true } },
        }

        apply_patch("modules/filebrowser/patches/browser_show_hidden")
        FileChooser.getList({ name = "move_chooser" }, "/mnt/usb")
        assert.is_false(FileChooser.show_hidden)
        assert.is_false(FileChooser.show_unsupported)
    end)

    it("hides the up-folder row and turns the title action into folder-up", function()
        local home_locked = false
        local FileChooser = {
            genItemTable = function(self) return self.stock_items end,
        }
        ZenSpec.replace("ui/widget/filechooser", FileChooser)
        ZenSpec.replace("ui/bidi", { mirroredUILayout = function() return false end })
        ZenSpec.replace("common/paths", {
            isHomeRoot = function(path) return path == "/library" end,
            isHomeLocked = function() return home_locked end,
        })
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { browser_hide_up_folder = true },
                browser_hide_up_folder = { hide_up_folder = true },
            },
        }

        apply_patch("modules/filebrowser/patches/browser_hide_up_folder")
        local folder_up_calls = 0
        local button = { setIcon = function(self, icon) self.icon = icon end }
        local chooser = {
            name = "filemanager",
            stock_items = {
                { path = "/library/series/..", text = "\u{2B06} ..", is_go_up = true },
                { path = "/library/series/book.epub", text = "Book" },
            },
            title_bar = {
                left_button = button,
                left_icon_tap_callback = function() return "home" end,
            },
            onFolderUp = function() folder_up_calls = folder_up_calls + 1 end,
        }
        setmetatable(chooser, { __index = FileChooser })

        local items = FileChooser.genItemTable(chooser, {}, {}, "/library/series")
        assert.are.equal(1, #items)
        assert.are.equal("Book", items[1].text)
        assert.are.equal("back.top", button.icon)
        button.callback()
        assert.are.equal(1, folder_up_calls)
    end)

    it("force-hides up-folder at a locked home even when the feature is disabled", function()
        local FileChooser = {
            genItemTable = function(self) return self.stock_items end,
        }
        ZenSpec.replace("ui/widget/filechooser", FileChooser)
        ZenSpec.replace("ui/bidi", { mirroredUILayout = function() return false end })
        ZenSpec.replace("common/paths", {
            isHomeRoot = function() return true end,
            isHomeLocked = function() return true end,
        })
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { browser_hide_up_folder = false },
                browser_hide_up_folder = { hide_up_folder = false },
            },
        }

        apply_patch("modules/filebrowser/patches/browser_hide_up_folder")
        local button = { setIcon = function(self, icon) self.icon = icon end }
        local chooser = {
            name = "filemanager",
            stock_items = {
                { path = "/library/..", text = "\u{2B06} ..", is_go_up = true },
                { path = "/library/book.epub", text = "Book" },
            },
            title_bar = {
                left_button = button,
                left_icon_tap_callback = function() return "home" end,
            },
        }
        setmetatable(chooser, { __index = FileChooser })
        local items = FileChooser.genItemTable(chooser, {}, {}, "/library")
        assert.are.equal(1, #items)
        assert.are.equal("home", button.icon)
    end)

    it("makes every movable container unmovable and consumes drag callbacks", function()
        local init_calls = 0
        local MovableContainer = {
            init = function(self, marker)
                init_calls = init_calls + 1
                return self.unmovable and marker
            end,
            onMovableTouch = function() return "touch" end,
            onMovableSwipe = function() return "swipe" end,
        }
        ZenSpec.replace("ui/widget/container/movablecontainer", MovableContainer)

        apply_patch("modules/filebrowser/patches/disable_modal_drag")
        local instance = {}
        assert.are.equal("initialized", MovableContainer.init(instance, "initialized"))
        assert.is_true(instance.unmovable)
        assert.are.equal(1, init_calls)
        assert.is_nil(MovableContainer.onMovableTouch(instance))
        assert.is_nil(MovableContainer.onMovableSwipe(instance))
        assert.is_nil(MovableContainer.onMovablePanRelease(instance))
    end)

    it("hides separators in non-classic menus and CoverBrowser layouts", function()
        local registered, shared
        local menu_updates, cover_updates = 0, 0
        local Menu = {
            updateItems = function() menu_updates = menu_updates + 1 end,
        }
        local CoverMenu = {
            updateItems = function() cover_updates = cover_updates + 1 end,
        }
        ZenSpec.replace("ffi/blitbuffer", { COLOR_WHITE = "white" })
        ZenSpec.replace("ui/widget/menu", Menu)
        ZenSpec.replace("covermenu", CoverMenu)
        ZenSpec.replace("mosaicmenu", { _updateItemsBuildUI = function() end })
        ZenSpec.replace("listmenu", { _updateItemsBuildUI = function() end })
        ZenSpec.replace("common/shared_state", {
            register = function(_, values) shared = values end,
        })
        ZenSpec.replace("userpatch", {
            registerPatchPluginFunc = function(name, callback)
                assert.are.equal("coverbrowser", name)
                registered = callback
            end,
        })
        _G.__ZEN_UI_PLUGIN = { config = {} }

        apply_patch("modules/filebrowser/patches/browser_hide_underline")
        assert.is_true(shared.hide_underline_active)
        assert.is_function(registered)
        registered({})

        local hidden = { _underline_container = { color = "black" } }
        Menu.updateItems({ name = "history", layout = { { hidden } } })
        assert.are.equal("white", hidden._underline_container.color)

        local classic = { _underline_container = { color = "black" } }
        Menu.updateItems({ name = "filemanager", layout = { { classic } } })
        assert.are.equal("black", classic._underline_container.color)

        local cover = { _underline_container = { color = "black" } }
        CoverMenu.updateItems({ layout = { { cover } } })
        assert.are.equal("white", cover._underline_container.color)
        assert.are.same({ 2, 1 }, { menu_updates, cover_updates })
    end)

    it("avoids repainting one-page menus but delegates multi-page navigation", function()
        local next_calls, previous_calls = 0, 0
        local Menu = {
            onNextPage = function() next_calls = next_calls + 1; return "next" end,
            onPrevPage = function() previous_calls = previous_calls + 1; return "previous" end,
        }
        local FileChooser = { onMenuSelect = function() return "selected" end }
        ZenSpec.replace("ui/widget/menu", Menu)
        ZenSpec.replace("ui/widget/filechooser", FileChooser)

        apply_patch("modules/filebrowser/patches/menu_single_page_scroll_guard")
        assert.is_true(Menu.onNextPage({ page_num = 1 }))
        assert.is_true(Menu.onPrevPage({}))
        assert.are.equal("next", Menu.onNextPage({ page_num = 2 }))
        assert.are.equal("previous", Menu.onPrevPage({ page_num = 3 }))
        assert.are.same({ 1, 1 }, { next_calls, previous_calls })

        _G.__ZEN_QUICKSTART_JUST_CLOSED = true
        assert.is_true(FileChooser.onMenuSelect({}, {}))
        _G.__ZEN_QUICKSTART_JUST_CLOSED = nil
        assert.are.equal("selected", FileChooser.onMenuSelect({}, {}))
    end)

    it("marks new and abandoned books as reading before opening", function()
        local statuses = { new = "new", abandoned = "abandoned", complete = "complete" }
        local saved, cached, opened = {}, {}, {}
        local filemanagerutil = {
            openFile = function(_, file)
                opened[#opened + 1] = file
                return "opened"
            end,
            saveSummary = function(_, summary)
                saved[#saved + 1] = summary.status
            end,
        }
        ZenSpec.replace("apps/filemanager/filemanagerutil", filemanagerutil)
        ZenSpec.replace("docsettings", {
            open = function(_, file)
                return {
                    readSetting = function() return { status = statuses[file] } end,
                }
            end,
        })
        ZenSpec.replace("ui/widget/booklist", {
            setBookInfoCacheProperty = function(file, key, value)
                cached[#cached + 1] = { file, key, value }
            end,
        })
        ZenSpec.replace("common/book_status", { acknowledgeNewVersion = function() return false end })

        apply_patch("modules/filebrowser/patches/status_on_open")
        assert.are.equal("opened", filemanagerutil.openFile({}, "new"))
        assert.are.equal("opened", filemanagerutil.openFile({}, "abandoned"))
        assert.are.equal("opened", filemanagerutil.openFile({}, "complete"))
        assert.same({ "reading", "reading" }, saved)
        assert.same({
            { "new", "status", "reading" },
            { "abandoned", "status", "reading" },
        }, cached)
        assert.same({ "new", "abandoned", "complete" }, opened)
    end)
end)

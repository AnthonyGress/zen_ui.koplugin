describe("background provider paint routing", function()
    local original_plugin
    local original_broadcast_guard
    local original_open_tab
    local original_modules

    local module_names = {
        "apps/filemanager/filemanager",
        "common/clock_timer",
        "common/ui/background",
        "common/widget_resources",
        "device",
        "modules/filebrowser/patches/library_background",
        "modules/filebrowser/patches/standalone_page",
        "ui/geometry",
        "ui/uimanager",
        "ui/widget/container/underlinecontainer",
        "ui/widget/container/widgetcontainer",
        "ui/widget/iconwidget",
        "ui/widget/menu",
        "ui/widget/textboxwidget",
        "ui/widget/titlebar",
    }

    before_each(function()
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        original_broadcast_guard = rawget(_G, "__ZEN_UI_BROADCAST_GUARD_PATCHED")
        original_open_tab = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_TAB")
        original_modules = {}
        for _i, name in ipairs(module_names) do
            original_modules[name] = package.loaded[name]
        end
        _G.__ZEN_UI_PLUGIN = { config = {} }
        _G.__ZEN_UI_BROADCAST_GUARD_PATCHED = nil
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = original_plugin
        _G.__ZEN_UI_BROADCAST_GUARD_PATCHED = original_broadcast_guard
        _G.__ZEN_UI_NAVBAR_OPEN_TAB = original_open_tab
        for _i, name in ipairs(module_names) do
            package.loaded[name] = original_modules[name]
        end
    end)

    it("rebuilds only Zen library surfaces after a missing background", function()
        local recovery_handler
        local closed = {}
        local reopen_calls = 0
        local cleanup_calls = 0
        local page_updates = 0
        local reinitializations = 0
        local dirty = {}
        local fm = {
            reinit = function() reinitializations = reinitializations + 1 end,
        }
        local reopened_home = {
            _zen_navbar_tab_id = "home",
            updateItems = function() page_updates = page_updates + 1 end,
        }
        local home = {
            _zen_bg_applied = true,
            _zen_navbar_tab_id = "home",
            page = 3,
        }
        local lock_modal = { modal = true }
        local UIManager = {
            _window_stack = {
                { widget = fm },
                { widget = home },
                { widget = lock_modal },
            },
            close = function(self, widget)
                closed[#closed + 1] = widget
                for index = #self._window_stack, 1, -1 do
                    if self._window_stack[index].widget == widget then
                        table.remove(self._window_stack, index)
                        break
                    end
                end
            end,
            setDirty = function(_self, widget, mode)
                dirty[#dirty + 1] = { widget, mode }
            end,
        }
        home.close_callback = function()
            cleanup_calls = cleanup_calls + 1
            UIManager:close(home)
        end
        home._zen_library_bg_reopen = function()
            reopen_calls = reopen_calls + 1
            table.insert(UIManager._window_stack, 2, { widget = reopened_home })
            return true
        end
        local FileManager = {
            instance = fm,
            setupLayout = function() end,
            paintTo = function() end,
        }
        ZenSpec.replace("apps/filemanager/filemanager", FileManager)
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 800 end,
                getHeight = function() return 600 end,
            },
        })
        ZenSpec.replace("ui/uimanager", UIManager)
        ZenSpec.replace("common/ui/background", {
            library_path = function() return "" end,
            clearWhiteBackgrounds = function() end,
            isWhite = function() return false end,
            paintScreenRegion = function() end,
            setMissingLibraryBackgroundHandler = function(handler)
                recovery_handler = handler
            end,
        })
        ZenSpec.replace("ui/widget/container/widgetcontainer", {
            paintTo = function() end,
        })
        ZenSpec.replace("ui/widget/textboxwidget", { _zen_bg_patched = true })
        ZenSpec.replace("ui/widget/iconwidget", { _zen_bg_patched = true })
        ZenSpec.replace("ui/widget/container/underlinecontainer", {
            _zen_bg_patched = true,
        })
        _G.__ZEN_UI_NAVBAR_OPEN_TAB = function()
            error("surface-owned recovery callback was bypassed")
        end

        require("modules/filebrowser/patches/library_background")()

        assert.is_function(recovery_handler)
        assert.is_true(recovery_handler())
        assert.are.same({ home }, closed)
        assert.are.equal(1, cleanup_calls)
        assert.are.equal(1, reinitializations)
        assert.are.equal(1, reopen_calls)
        assert.are.equal(3, reopened_home.page)
        assert.are.equal(1, page_updates)
        assert.are.same({}, dirty)
        assert.are.same({ fm, reopened_home, lock_modal }, {
            UIManager._window_stack[1].widget,
            UIManager._window_stack[2].widget,
            UIManager._window_stack[3].widget,
        })

        local foreign_surface = {}
        local blocked_home = {
            _zen_navbar_tab_id = "home",
            _zen_library_bg_reopen = function()
                error("blocked surface was reopened")
            end,
        }
        UIManager._window_stack = {
            { widget = fm },
            { widget = blocked_home },
            { widget = foreign_surface },
        }
        assert.is_false(recovery_handler())
        assert.are.same({ home }, closed)
        assert.are.equal(1, reinitializations)
        assert.are.equal(1, reopen_calls)
    end)

    it("lets a sentinel provider paint the full FileManager surface", function()
        local paint_args
        local base_paints = 0
        local FileManager = {
            setupLayout = function() end,
            paintTo = function()
                base_paints = base_paints + 1
                return "stock"
            end,
        }
        ZenSpec.replace("apps/filemanager/filemanager", FileManager)
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 800 end,
                getHeight = function() return 600 end,
            },
        })
        ZenSpec.replace("ui/uimanager", {
            _window_stack = {},
            close = function() end,
            setDirty = function() end,
        })
        ZenSpec.replace("common/ui/background", {
            library_path = function() return "__thematic__" end,
            clearWhiteBackgrounds = function() end,
            isWhite = function() return false end,
            paint = function() error("full-page paint bypassed the provider seam") end,
            paintScreenRegion = function(...)
                paint_args = { ... }
                return true
            end,
            setMissingLibraryBackgroundHandler = function() end,
        })
        ZenSpec.replace("ui/widget/container/widgetcontainer", {
            paintTo = function() return "container" end,
        })
        ZenSpec.replace("ui/widget/textboxwidget", { _zen_bg_patched = true })
        ZenSpec.replace("ui/widget/iconwidget", { _zen_bg_patched = true })
        ZenSpec.replace("ui/widget/container/underlinecontainer", {
            _zen_bg_patched = true,
        })

        require("modules/filebrowser/patches/library_background")()
        local bb = {}
        local result = FileManager.paintTo({ {}, file_chooser = {} }, bb, 9, 11)

        assert.are.equal("stock", result)
        assert.are.equal(1, base_paints)
        assert.are.same({
            bb, 0, 0, 0, 0, 800, 600, "__thematic__",
        }, paint_args)
    end)

    it("lets a sentinel provider paint a full standalone page", function()
        local paint_args
        local base_paints = 0
        ZenSpec.replace("ui/widget/menu", {})
        ZenSpec.replace("ui/widget/titlebar", {})
        ZenSpec.replace("ui/geometry", {})
        ZenSpec.replace("common/clock_timer", {})
        ZenSpec.replace("common/widget_resources", {})
        ZenSpec.replace("ui/uimanager", {
            broadcastEvent = function() end,
        })
        ZenSpec.replace("common/ui/background", {
            library_path = function() return "__thematic__" end,
            clearWhiteBackgrounds = function() end,
            paint = function() error("full-page paint bypassed the provider seam") end,
            paintScreenRegion = function(...)
                paint_args = { ... }
                return true
            end,
        })

        local StandalonePage = require("modules/filebrowser/patches/standalone_page")
        local menu = {
            dimen = { w = 720, h = 540 },
            {},
            paintTo = function()
                base_paints = base_paints + 1
                return "stock"
            end,
        }
        StandalonePage.apply_background(menu)
        local bb = {}
        local result = menu:paintTo(bb, 3, 5)

        assert.are.equal("stock", result)
        assert.are.equal(1, base_paints)
        assert.are.same({
            bb, 0, 0, 0, 0, 720, 540, "__thematic__",
        }, paint_args)
    end)
end)

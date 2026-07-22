describe("page browser entry", function()
    local shown, events, zones

    local function expect(condition, message)
        if not condition then error(message or "expectation failed", 2) end
    end

    local function logger_stub()
        return { dbg = function() end, warn = function() end, err = function() end }
    end

    local function install_widget_dependencies(PageBrowserWidget)
        local empty_modules = {
            "ui/font", "ui/geometry", "ui/widget/iconbutton", "ui/widget/iconwidget",
            "ui/widget/horizontalgroup", "ui/widget/verticalgroup", "ui/widget/verticalspan",
            "ui/widget/textwidget", "ui/widget/container/framecontainer",
            "ui/widget/container/centercontainer", "ui/widget/overlapgroup", "ffi/blitbuffer",
            "ui/size", "ui/gesturerange", "common/ui/zen_slider", "common/ui/zen_icon_button",
        }
        for _i, name in ipairs(empty_modules) do ZenSpec.replace(name, {}) end
        ZenSpec.replace("ui/widget/pagebrowserwidget", PageBrowserWidget)
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_, value) return value end,
            },
        })
    end

    before_each(function()
        shown, events, zones = nil, {}, nil
        _G.__ZEN_UI_PLUGIN = nil
        G_reader_settings = ZenSpec.memorySettings()
        ZenSpec.replace("common/plugin_root", "/tmp/zen-ui")
        ZenSpec.replace("common/utils", { resolveIcon = function() return nil end })
        ZenSpec.replace("common/zen_logger", { new = logger_stub })
        ZenSpec.replace("config/manager", { load = function() return {} end, save = function() end })
        ZenSpec.replace("modules/reader/zen_toc_widget", { set_plugin = function() end })
        ZenSpec.replace("ui/event", {
            new = function(_, name, ...)
                return { name = name, args = { ... } }
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            show = function(_, widget) shown = widget end,
            scheduleIn = function() end,
            setDirty = function() end,
            unschedule = function() end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("apps/reader/modules/readersearch", {})
        ZenSpec.replace("ui/widget/inputdialog", { onTap = function() end })
        ZenSpec.replace("apps/reader/readerui", {})
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
        package.loaded["db"] = nil
        ZenSpec.unload("modules/reader/patches/page_browser")
    end)

    it("registers the bottom gesture and opens the patched browser only when enabled", function()
        local stock_listener_calls = 0
        local ReaderMenu = {
            initGesListener = function() stock_listener_calls = stock_listener_calls + 1 end,
        }
        local stock_swipes = 0
        local ReaderConfig = {
            onSwipeShowConfigMenu = function()
                stock_swipes = stock_swipes + 1
                return "stock"
            end,
        }
        local PageBrowserWidget = {
            new = function(_, spec) return { ui = spec.ui, zen_page_browser = true } end,
        }
        install_widget_dependencies(PageBrowserWidget)
        ZenSpec.replace("apps/reader/modules/readermenu", ReaderMenu)
        ZenSpec.replace("apps/reader/modules/readerconfig", ReaderConfig)
        local plugin = {
            config = { features = { page_browser = false } },
        }
        _G.__ZEN_UI_PLUGIN = plugin
        require("modules/reader/patches/page_browser")()

        local ui = {
            registerTouchZones = function(_, registered) zones = registered end,
            handleEvent = function(_, event) events[#events + 1] = event end,
        }
        ReaderMenu.initGesListener({ ui = ui })
        expect(stock_listener_calls == 1)
        expect(zones[1].id == "zen_page_browser_reader")
        local disabled_result = zones[1].handler({ direction = "north" })
        expect(disabled_result == nil)
        expect(shown == nil)
        expect(ReaderConfig.onSwipeShowConfigMenu({ ui = ui }, { direction = "north" }) == nil)
        expect(stock_swipes == 0)

        plugin.config.features.page_browser = true
        expect(ReaderConfig.onSwipeShowConfigMenu({ ui = ui }, { direction = "south" }) == "stock")
        expect(stock_swipes == 1)
        expect(zones[1].handler({ direction = "north" }) == true)
        expect(shown.zen_page_browser == true)
        expect(shown.ui == ui)
        expect(events[1].name == "HandledAsSwipe")
        expect(ReaderConfig.onSwipeShowConfigMenu({ ui = ui }, { direction = "north" }) == true)
        expect(events[2].name == "HandledAsSwipe")

        local activated = {}
        local function zone(name)
            return { contains = function() activated[#activated + 1] = name; return true end }
        end
        local browser = {
            _zen_slider = {
                handleTap = function() return false end,
                handleSwipe = function() return false end,
            },
            _zen_btn_skip_left_zone = zone("skip-left-zone"),
            _zen_skip_prev = function() activated[#activated + 1] = "skip-left" end,
            _zen_switch_single = function() activated[#activated + 1] = "single" end,
            dimen = { x = 0, y = 0, h = 800 },
        }
        expect(PageBrowserWidget.onTap(browser, nil, { pos = { x = 10, y = 10 } }) == true)
        expect(activated[1] == "skip-left-zone")
        expect(activated[2] == "skip-left")

        activated = {}
        browser._zen_btn_skip_left_zone = nil
        browser._zen_btn_view_zone = zone("single-zone")
        expect(PageBrowserWidget.onTap(browser, nil, { pos = { x = 20, y = 20 } }) == true)
        expect(activated[1] == "single-zone")
        expect(activated[2] == "single")

        local page_down, page_up = 0, 0
        browser.onScrollPageDown = function() page_down = page_down + 1 end
        browser.onScrollPageUp = function() page_up = page_up + 1 end
        expect(PageBrowserWidget.onSwipe(browser, nil, { direction = "west" }) == true)
        expect(PageBrowserWidget.onSwipe(browser, nil, { direction = "east" }) == true)
        expect(page_down == 1 and page_up == 1)
    end)

    it("honors lockdown by suppressing page-browser and native config gestures", function()
        local stock_calls = 0
        local ReaderMenu = { initGesListener = function() end }
        local ReaderConfig = {
            onSwipeShowConfigMenu = function()
                stock_calls = stock_calls + 1
                return "stock"
            end,
        }
        install_widget_dependencies({ new = function(_, spec) return spec end })
        ZenSpec.replace("apps/reader/modules/readermenu", ReaderMenu)
        ZenSpec.replace("apps/reader/modules/readerconfig", ReaderConfig)
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { page_browser = true, lockdown_mode = true },
                lockdown = { disable_bottom_menu_swipe = true },
            },
        }
        require("modules/reader/patches/page_browser")()
        local ui = { handleEvent = function() end }
        local lockdown_result = ReaderConfig.onSwipeShowConfigMenu(
            { ui = ui }, { direction = "north" }
        )
        expect(lockdown_result == nil)
        expect(ReaderConfig.onSwipeShowConfigMenu({ ui = ui }, { direction = "south" }) == nil)
        expect(stock_calls == 0)
        expect(shown == nil)
    end)

    it("routes every title-bar action after closing the page browser", function()
        local ReaderMenu = { initGesListener = function() end }
        local ReaderConfig = { onSwipeShowConfigMenu = function() end }
        local PageBrowserWidget = {
            init = function(self)
                local left = { callback = function() end, hold_callback = function() end }
                local right = { callback = function() end, hold_callback = function() end }
                self.ges_events = {}
                self.nb_cols, self.nb_rows = 3, 2
                self.title_bar = {
                    left,
                    right,
                    left_button = left,
                    right_button = right,
                    button_padding = 11,
                    setTitle = function(bar, title) bar.title = title end,
                }
            end,
            new = function(_, spec) return { ui = spec.ui } end,
        }
        install_widget_dependencies(PageBrowserWidget)
        ZenSpec.replace("apps/reader/modules/readermenu", ReaderMenu)
        ZenSpec.replace("apps/reader/modules/readerconfig", ReaderConfig)

        local function button_class()
            return { new = function(_, spec) return spec end }
        end
        ZenSpec.replace("ui/widget/iconbutton", button_class())
        ZenSpec.replace("common/ui/zen_icon_button", button_class())
        ZenSpec.replace("ui/gesturerange", button_class())
        ZenSpec.replace("ui/geometry", button_class())
        local toc_spec
        ZenSpec.replace("modules/reader/zen_toc_widget", {
            set_plugin = function() end,
            new = function(_, spec)
                toc_spec = spec
                return spec
            end,
        })
        ZenSpec.replace("common/utils", {
            resolveIcon = function(_, name) return "/icons/" .. name .. ".svg" end,
        })
        local shown_widgets = {}
        ZenSpec.replace("ui/uimanager", {
            show = function(_, widget) shown_widgets[#shown_widgets + 1] = widget end,
            scheduleIn = function() end,
            setDirty = function() end,
            unschedule = function() end,
            nextTick = function(_, callback) callback() end,
        })
        local config_dialog
        ZenSpec.replace("ui/widget/configdialog", {
            new = function(_, spec)
                spec.onShowConfigPanel = function(self, index) self.shown_panel = index end
                config_dialog = spec
                return spec
            end,
        })
        _G.__ZEN_UI_PLUGIN = {
            config = { features = { page_browser = true } },
            saveConfig = function() end,
        }
        package.loaded["db"] = {}
        require("modules/reader/patches/page_browser")()

        local bootstrap_ui = { handleEvent = function() end }
        ReaderConfig.onSwipeShowConfigMenu({ ui = bootstrap_ui }, { direction = "north" })

        local action_events, closes, bookmarks, stack_adds, stopped = {}, 0, 0, 0, 0
        local ui = {
            link = { addCurrentLocationToStack = function() stack_adds = stack_adds + 1 end },
            bookmark = { onShowBookmark = function() bookmarks = bookmarks + 1 end },
            keyselection = {
                onStopHighlightIndicator = function(_, immediate)
                    if immediate then stopped = stopped + 1 end
                end,
            },
            config = {
                document = {}, ui = {}, configurable = {}, options = {}, last_panel_index = 4,
            },
            handleEvent = function(_, event) action_events[#action_events + 1] = event end,
        }
        local browser = {
            ui = ui,
            focus_page = 12,
            dimen = { x = 0, y = 0, w = 600, h = 800 },
            onClose = function() closes = closes + 1 end,
            updateLayout = function() error("layout stop") end,
        }
        local initialized, init_err = pcall(PageBrowserWidget.init, browser)
        expect(initialized == false, "test seam should stop before layout")
        expect(tostring(init_err):find("layout stop", 1, true) ~= nil, tostring(init_err))

        local by_icon, by_file = {}, {}
        for _i, button in ipairs(browser.title_bar) do
            if button.icon then by_icon[button.icon] = button.callback end
            if button.file then by_file[button.file] = button.callback end
        end
        expect(type(by_icon["appbar.search"]) == "function")
        expect(type(by_icon["appbar.textsize"]) == "function")
        expect(type(by_icon.bookmark) == "function")
        expect(type(by_file["/icons/toc.svg"]) == "function")
        expect(type(by_file["/icons/tab_vocab.svg"]) == "function")

        by_icon["appbar.search"]()
        expect(closes == 1 and action_events[#action_events].name == "ShowFulltextSearchInput")
        by_icon.bookmark()
        expect(closes == 2 and bookmarks == 1)
        by_file["/icons/tab_vocab.svg"]()
        expect(closes == 3 and action_events[#action_events].name == "ShowVocabBuilder")

        by_file["/icons/toc.svg"]()
        expect(closes == 4 and toc_spec.focus_page == 12)
        toc_spec.on_goto(27)
        expect(stack_adds == 1)
        expect(action_events[#action_events].name == "GotoPage"
            and action_events[#action_events].args[1] == 27)

        by_icon["appbar.textsize"]()
        expect(closes == 5)
        expect(config_dialog ~= nil and ui.config.config_dialog == config_dialog)
        expect(config_dialog.shown_panel == 4 and stopped == 1)
        expect(action_events[#action_events].name == "DisableHinting")
        config_dialog.panel_index = 2
        config_dialog.close_callback()
        expect(ui.config.config_dialog == nil and ui.config.last_panel_index == 2)
        expect(action_events[#action_events].name == "RestoreHinting")
    end)
end)

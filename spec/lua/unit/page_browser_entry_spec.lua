describe("page browser entry", function()
    local shown, events, zones, reader_store

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
        reader_store = { settings = {}, presets = {} }
        _G.__ZEN_UI_PLUGIN = nil
        G_reader_settings = ZenSpec.memorySettings()
        ZenSpec.replace("common/plugin_root", "/tmp/zen-ui")
        ZenSpec.replace("common/utils", { resolveLocalIcon = function() return nil end })
        ZenSpec.replace("common/zen_logger", { new = logger_stub })
        ZenSpec.replace("config/preset_store", {
            getSettings = function() return reader_store.settings end,
            loadStore = function() return reader_store end,
            saveStore = function(_, store)
                reader_store = store
                return true
            end,
        })
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
        ZenSpec.unload("common/cover_utils")
        ZenSpec.unload("ui/widget/booklist")
        ZenSpec.unload("modules/reader/book_info_widget")
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
        local page_down, page_up = 0, 0
        local browser = {
            _zen_slider = {
                handleTap = function() return false end,
                handleSwipe = function() return false end,
            },
            _zen_btn_skip_left_zone = zone("skip-left-zone"),
            _zen_skip_prev = function() activated[#activated + 1] = "skip-left" end,
            _zen_skip_next = function() activated[#activated + 1] = "skip-right" end,
            _zen_switch_single = function() activated[#activated + 1] = "single" end,
            onScrollPageDown = function() page_down = page_down + 1 end,
            onScrollPageUp = function() page_up = page_up + 1 end,
            dimen = { x = 0, y = 0, h = 800 },
        }
        expect(PageBrowserWidget.onTap(browser, nil, { pos = { x = 10, y = 10 } }) == true)
        expect(activated[1] == "skip-left-zone")
        expect(page_up == 1)

        activated = {}
        expect(PageBrowserWidget.onHold(browser, nil, { pos = { x = 10, y = 10 } }) == true)
        expect(activated[1] == "skip-left-zone")
        expect(activated[2] == "skip-left")

        activated = {}
        browser._zen_btn_skip_left_zone = nil
        browser._zen_btn_skip_right_zone = zone("skip-right-zone")
        expect(PageBrowserWidget.onTap(browser, nil, { pos = { x = 30, y = 10 } }) == true)
        expect(activated[1] == "skip-right-zone")
        expect(page_down == 1)

        activated = {}
        expect(PageBrowserWidget.onHold(browser, nil, { pos = { x = 30, y = 10 } }) == true)
        expect(activated[1] == "skip-right-zone")
        expect(activated[2] == "skip-right")

        activated = {}
        browser._zen_btn_skip_right_zone = nil
        browser._zen_btn_view_zone = zone("single-zone")
        expect(PageBrowserWidget.onTap(browser, nil, { pos = { x = 20, y = 20 } }) == true)
        expect(activated[1] == "single-zone")
        expect(activated[2] == "single")

        expect(PageBrowserWidget.onSwipe(browser, nil, { direction = "west" }) == true)
        expect(PageBrowserWidget.onSwipe(browser, nil, { direction = "east" }) == true)
        expect(page_down == 2 and page_up == 2)
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

    it("hides non-linear fragments from page-browser navigation", function()
        local ReaderMenu = { initGesListener = function() end }
        local ReaderConfig = { onSwipeShowConfigMenu = function() end }
        local PageBrowserWidget = {
            init = function(self)
                local left = { callback = function() end }
                local right = { callback = function() end }
                self.ges_events = {}
                self.nb_cols, self.nb_rows = 3, 2
                self.nb_pages, self.cur_page, self.focus_page = 5, 3, 3
                self.title_bar = {
                    left,
                    right,
                    left_button = left,
                    right_button = right,
                    setTitle = function() end,
                }
            end,
            new = function(_, spec) return spec end,
            onTap = function() error("mapped thumbnail tap was not handled") end,
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
        ZenSpec.replace("common/utils", {
            resolveLocalIcon = function(_, name) return "/icons/" .. name .. ".svg" end,
        })
        _G.__ZEN_UI_PLUGIN = { config = { features = { page_browser = true } } }
        require("modules/reader/patches/page_browser")()

        ReaderConfig.onSwipeShowConfigMenu({ ui = { handleEvent = function() end } }, { direction = "north" })
        local goto_page, closes, locations = nil, 0, 0
        local browser = {
            dimen = { x = 0, y = 0, w = 600, h = 800 },
            ui = {
                document = {
                    getPageCount = function() return 5 end,
                    hasHiddenFlows = function() return true end,
                    getPageFlow = function(_, page) return (page == 2 or page == 4) and 1 or 0 end,
                },
                link = { addCurrentLocationToStack = function() locations = locations + 1 end },
                handleEvent = function(_, event) goto_page = event.args[1] end,
            },
            onClose = function(_, all) if all then closes = closes + 1 end end,
            updateLayout = function() error("layout stop") end,
        }
        local initialized, init_err = pcall(PageBrowserWidget.init, browser)
        expect(initialized == false and tostring(init_err):find("layout stop", 1, true) ~= nil)
        expect(browser.nb_pages == 3)
        expect(browser.focus_page == 2 and browser.cur_page == 2)
        expect(browser._zen_visible_pages[1] == 1
            and browser._zen_visible_pages[2] == 3
            and browser._zen_visible_pages[3] == 5)

        browser.nb_grid_items = 1
        browser.grid = {{
            page_idx = 2,
            dimen = { x = 0, y = 0, w = 100, h = 100 },
        }}
        PageBrowserWidget.onTap(browser, nil, {
            pos = { intersectWith = function() return true end, x = 10, y = 10 },
        })
        expect(goto_page == 3 and closes == 1 and locations == 1)
    end)

    it("preserves KOReader search-type tables for whole-word searches", function()
        local search_call = {}
        local find_all_call = {}
        local default_search_type = { flags = 0x00FF, regex = false, text = "default" }
        local original_search = function(_, pattern, origin, search_type, case_insensitive)
            search_call = {
                pattern = pattern,
                origin = origin,
                search_type = search_type,
                case_insensitive = case_insensitive,
            }
        end
        local ReaderSearch = {
            default_search_type = default_search_type,
            search = original_search,
            findAllText = function(self, pattern)
                find_all_call = {
                    pattern = pattern,
                    search_type = self.current_search_type,
                }
            end,
        }
        ZenSpec.replace("apps/reader/modules/readersearch", ReaderSearch)
        ZenSpec.replace("apps/reader/modules/readermenu", { initGesListener = function() end })
        ZenSpec.replace("apps/reader/modules/readerconfig", { onSwipeShowConfigMenu = function() end })
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { page_browser = false },
                search = { substring = false },
            },
        }
        require("modules/reader/patches/page_browser")()

        expect(ReaderSearch.search ~= original_search)
        ReaderSearch:search("red", 0, default_search_type, true)
        expect(search_call.pattern == "\\b" .. "red" .. "\\b")
        expect(search_call.origin == 0 and search_call.case_insensitive == true)
        expect(search_call.search_type ~= default_search_type)
        expect(search_call.search_type.flags == default_search_type.flags)
        expect(search_call.search_type.text == default_search_type.text)
        expect(search_call.search_type.regex == true and default_search_type.regex == false)

        ReaderSearch:search("red", 0, nil, true)
        expect(type(search_call.search_type) == "table")
        expect(search_call.search_type.regex == true)

        ReaderSearch.current_search_type = default_search_type
        ReaderSearch:findAllText("red")
        expect(find_all_call.pattern == "\\b" .. "red" .. "\\b")
        expect(find_all_call.search_type ~= default_search_type)
        expect(find_all_call.search_type.regex == true)
        expect(ReaderSearch.current_search_type == default_search_type)
    end)

    it("routes page-browser title-bar actions and keeps TOC returnable", function()
        local ReaderMenu = { initGesListener = function() end }
        local ReaderConfig = { onSwipeShowConfigMenu = function() end }
        local close_button_taps = 0
        local PageBrowserWidget = {
            init = function(self)
                local left = { callback = function() end, hold_callback = function() end }
                local right = {
                    callback = function() close_button_taps = close_button_taps + 1 end,
                    hold_callback = function() end,
                }
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
            resolveLocalIcon = function(_, name) return "/icons/" .. name .. ".svg" end,
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
        local info_spec
        local cover_options
        ZenSpec.replace("ui/font", {
            sizemap = { cfont = 16 },
            getFace = function(_, name, size, index)
                if name == "ReaderFont.ttf" then return nil end
                return { name = name, size = size, index = index }
            end,
        })
        ZenSpec.replace("document/credocument", {
            engineInit = function()
                return {
                    getFontFaceFilenameAndFaceIndex = function(_, _, italic)
                        if italic then return "ReaderFont.ttf", 0 end
                    end,
                }
            end,
        })
        ZenSpec.replace("ui/language", {
            getLanguageName = function(_, code)
                return code == "en" and "English" or code
            end,
        })
        ZenSpec.replace("common/cover_utils", {
            getRatio = function() return 2 / 3 end,
            makeCover = function(_, _, options)
                cover_options = options
                return { copy = function(self) return self end }, 120, 180, "single", "real_cover"
            end,
        })
        ZenSpec.replace("ui/widget/booklist", {
            getBookRatingString = function(rating) return "rating " .. rating end,
        })
        ZenSpec.replace("modules/reader/book_info_widget", {
            new = function(_, spec)
                info_spec = spec
                return spec
            end,
        })
        _G.__ZEN_UI_PLUGIN = {
            config = { features = { page_browser = true, browser_cover_rounded_corners = true } },
            saveConfig = function() end,
        }
        require("modules/reader/patches/page_browser")()

        local bootstrap_ui = { handleEvent = function() end }
        ReaderConfig.onSwipeShowConfigMenu({ ui = bootstrap_ui }, { direction = "north" })

        local action_events, closes, bookmarks, stack_adds, stopped = {}, 0, 0, 0, 0
        local ui = {
            link = { addCurrentLocationToStack = function() stack_adds = stack_adds + 1 end },
            bookmark = { onShowBookmark = function() bookmarks = bookmarks + 1 end },
            document = { file = "/books/test.epub" },
            doc_props = {
                title = "Test title",
                authors = "Test author",
                series = "Test series",
                series_index = 2,
                keywords = "First tag; Second tag",
                language = "en",
                description = "Test description",
            },
            doc_settings = {
                readSetting = function(_, key)
                    if key == "summary" then return { rating = 4, note = "" } end
                    if key == "annotations" then return { {}, {} } end
                    if key == "doc_pages" then return 240 end
                    if key == "font_face" then return "ReaderFont" end
                end,
            },
            annotation = { annotations = { {}, {} } },
            font = { font_face = "ReaderFont" },
            configurable = { font_size = 21 },
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

        local by_file, positions = {}, {}
        for _i, button in ipairs(browser.title_bar) do
            if button.file then
                by_file[button.file] = button.callback
                positions[button.file] = button.overlap_offset and button.overlap_offset[1]
            end
        end
        expect(type(by_file["/icons/appbar.search.svg"]) == "function")
        expect(type(by_file["/icons/appbar.textsize.svg"]) == "function")
        expect(type(by_file["/icons/bookmark.svg"]) == "function")
        expect(type(by_file["/icons/toc.svg"]) == "function")
        expect(type(by_file["/icons/info.svg"]) == "function")
        expect(positions["/icons/appbar.search.svg"] == 0)
        expect(positions["/icons/info.svg"] == 54)
        expect(positions["/icons/appbar.textsize.svg"] == 108)
        expect(positions["/icons/bookmark.svg"] == 162)
        expect(positions["/icons/toc.svg"] == 216)
        expect(browser._zen_orig_nb_cols == 3 and browser._zen_orig_nb_rows == 2)
        local close_button = browser.title_bar.right_button
        expect(close_button.file == "/icons/close.svg")
        expect(close_button.width == 32 and close_button.height == 32)
        expect(close_button.padding == 11 and close_button.padding_bottom == 32)
        expect(close_button.overlap_align == "right")
        close_button.callback()
        expect(close_button_taps == 1)

        by_file["/icons/appbar.search.svg"]()
        expect(closes == 1 and action_events[#action_events].name == "ShowFulltextSearchInput")
        by_file["/icons/bookmark.svg"]()
        expect(closes == 2 and bookmarks == 1)

        by_file["/icons/toc.svg"]()
        expect(closes == 2 and toc_spec.focus_page == 12)
        toc_spec.on_goto(27)
        expect(closes == 3 and stack_adds == 1)
        expect(action_events[#action_events].name == "GotoPage"
            and action_events[#action_events].args[1] == 27)

        by_file["/icons/info.svg"]()
        expect(closes == 3 and info_spec ~= nil and info_spec.title == "Book details")
        expect(info_spec.cover ~= nil and info_spec.cover_width == 120 and info_spec.cover_height == 180)
        expect(#info_spec.details == 8)
        expect(info_spec.details[1].text == "Test title" and info_spec.details[1].bold == true
            and info_spec.details[1].style == "title")
        expect(info_spec.details[2].text == "Test author" and info_spec.details[2].style == "author")
        expect(info_spec.details[3].text == "Test series #2" and info_spec.details[3].style == "secondary")
        expect(info_spec.details[4].text == "First tag, Second tag" and info_spec.details[4].style == "secondary")
        expect(info_spec.details[5].text == "240 pages" and info_spec.details[5].style == "secondary")
        expect(info_spec.details[6].text == "English" and info_spec.details[6].style == "secondary")
        expect(info_spec.details[7].text == "rating 4" and info_spec.details[7].style == "secondary")
        expect(info_spec.details[8].text == "2 Annotations" and info_spec.details[8].style == "secondary")
        expect(info_spec.rounded_cover == true and type(info_spec.cover_tap_callback) == "function")
        expect(info_spec.text_face.name == "ReaderFont" and info_spec.text_face.size == 21)
        expect(info_spec.text_faces.author.name == "ReaderFont" and info_spec.text_faces.author.size == 18)
        expect(info_spec.text_faces.secondary.name == "ReaderFont" and info_spec.text_faces.secondary.size == 15)
        expect(cover_options.height == 240)
        expect(info_spec.description == "Test description")

        by_file["/icons/appbar.textsize.svg"]()
        expect(closes == 4)
        expect(config_dialog ~= nil and ui.config.config_dialog == config_dialog)
        expect(config_dialog.shown_panel == 4 and stopped == 1)
        expect(action_events[#action_events].name == "DisableHinting")
        config_dialog.panel_index = 2
        config_dialog.close_callback()
        expect(ui.config.config_dialog == nil and ui.config.last_panel_index == 2)
        expect(action_events[#action_events].name == "RestoreHinting")
    end)
end)

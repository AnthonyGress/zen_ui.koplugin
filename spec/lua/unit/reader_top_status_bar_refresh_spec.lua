describe("reader top status bar refresh", function()
    local ReaderUI
    local ReaderView
    local UIManager
    local saved_modules
    local saved_plugin
    local saved_settings
    local scheduled
    local paint_rects
    local dirty_calls
    local paint_order

    local dependencies = {
        "apps/reader/modules/readerview",
        "apps/reader/readerui",
        "common/inline_icon_map",
        "common/reader_themes",
        "common/utils",
        "common/zen_logger",
        "datetime",
        "device",
        "ffi/blitbuffer",
        "gettext",
        "ui/bidi",
        "ui/font",
        "ui/geometry",
        "ui/size",
        "ui/uimanager",
        "ui/widget/container/centercontainer",
        "ui/widget/container/leftcontainer",
        "ui/widget/container/rightcontainer",
        "ui/widget/horizontalgroup",
        "ui/widget/horizontalspan",
        "ui/widget/linewidget",
        "ui/widget/textwidget",
        "ui/widget/verticalgroup",
        "ui/widget/verticalspan",
        "modules/reader/patches/reader_top_status_bar",
    }

    local function geometry_class()
        return {
            new = function(_self, values) return values end,
        }
    end

    local function replace(name, module)
        ZenSpec.replace(name, module)
    end

    local function replace_upvalue(fn, target, replacement)
        for index = 1, 40 do
            local name = debug.getupvalue(fn, index)
            if not name then break end
            if name == target then
                debug.setupvalue(fn, index, replacement)
                return true
            end
        end
        return false
    end

    local function reset_paint_log()
        paint_rects = {}
        dirty_calls = {}
        paint_order = {}
    end

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(dependencies) do
            saved_modules[name] = package.loaded[name] or false
        end
        saved_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        saved_settings = G_reader_settings
        scheduled = {}
        reset_paint_log()

        local screen_bb = {
            paintRect = function(_self, x, y, w, h, color)
                paint_rects[#paint_rects + 1] = { x = x, y = y, w = w, h = h, color = color }
                paint_order[#paint_order + 1] = "clear"
            end,
        }
        local screen = {
            bb = screen_bb,
            getWidth = function() return 600 end,
            scaleBySize = function(_self, value) return value end,
        }

        UIManager = {
            _window_stack = {},
            scheduleIn = function(_self, delay, callback)
                scheduled[#scheduled + 1] = { delay = delay, callback = callback }
            end,
            unschedule = function() end,
            widgetRepaint = function()
                paint_order[#paint_order + 1] = "header"
            end,
            setDirty = function(_self, widget, mode, region, dither)
                dirty_calls[#dirty_calls + 1] = {
                    widget = widget, mode = mode, region = region, dither = dither,
                }
                paint_order[#paint_order + 1] = "dirty"
            end,
        }
        ReaderUI = {
            onSuspend = function() end,
            onResume = function() end,
            onCharging = function() end,
            onNotCharging = function() end,
            onNetworkConnected = function() end,
            onNetworkDisconnected = function() end,
        }
        ReaderView = { paintTo = function() end }

        replace("apps/reader/modules/readerview", ReaderView)
        replace("apps/reader/readerui", ReaderUI)
        replace("common/inline_icon_map", {})
        replace("common/reader_themes", {
            getBackgroundColor = function() end,
            getTextColor = function() end,
        })
        replace("common/utils", {})
        replace("common/zen_logger", {
            new = function() return { dbg = function() end } end,
        })
        replace("datetime", {})
        replace("device", { screen = screen })
        replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_DARK_GRAY = "dark_gray",
            COLOR_LIGHT_GRAY = "light_gray",
            COLOR_WHITE = "white",
        })
        replace("gettext", function(text) return text end)
        replace("ui/bidi", {})
        replace("ui/font", {})
        replace("ui/geometry", geometry_class())
        replace("ui/size", { line = { medium = 1 }, padding = { small = 2 } })
        replace("ui/uimanager", UIManager)
        for _i, name in ipairs({
            "ui/widget/container/centercontainer",
            "ui/widget/container/leftcontainer",
            "ui/widget/container/rightcontainer",
            "ui/widget/horizontalgroup",
            "ui/widget/horizontalspan",
            "ui/widget/linewidget",
            "ui/widget/textwidget",
            "ui/widget/verticalgroup",
            "ui/widget/verticalspan",
        }) do
            replace(name, {})
        end

        G_reader_settings = ZenSpec.memorySettings({ footer = {} })
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { reader_top_status_bar = true },
                reader_top_status_bar = {
                    left_order = { "wifi" },
                    center_order = { "time" },
                    right_order = { "battery" },
                },
            },
        }

        ZenSpec.unload("modules/reader/patches/reader_top_status_bar")
        require("modules/reader/patches/reader_top_status_bar")()

        local header = { paintTo = function() end }
        local slot_regions = {
            left = { x = 0, y = 0, w = 100, h = 20 },
            center = { x = 250, y = 0, w = 100, h = 20 },
            right = { x = 500, y = 0, w = 100, h = 20 },
        }
        assert.is_true(replace_upvalue(ReaderView.paintTo, "buildHeader", function()
            return header, {}, 20, 600, slot_regions
        end))
    end)

    after_each(function()
        for _i, name in ipairs(dependencies) do
            package.loaded[name] = saved_modules[name] or nil
        end
        _G.__ZEN_UI_PLUGIN = saved_plugin
        G_reader_settings = saved_settings
    end)

    local function make_view()
        local ui = { document = {}, dithered = true }
        local view = {
            ui = ui,
            document = {},
            dogear_visible = true,
            dogear = {
                paintTo = function()
                    paint_order[#paint_order + 1] = "dogear"
                end,
            },
        }
        UIManager._window_stack = { { widget = ui } }
        ReaderView.paintTo(view, require("device").screen.bb, 0, 0)
        reset_paint_log()
        return view
    end

    local function assert_single_slot(expected_x)
        assert.are.equal(1, #paint_rects)
        assert.same({ x = expected_x, y = 0, w = 100, h = 20, color = "white" }, paint_rects[1])
        assert.are.equal(1, #dirty_calls)
        assert.is_nil(dirty_calls[1].widget)
        assert.are.equal("ui", dirty_calls[1].mode)
        assert.are.equal(expected_x, dirty_calls[1].region.x)
        assert.are.equal(100, dirty_calls[1].region.w)
        assert.is_true(dirty_calls[1].dither)
        assert.same({ "clear", "header", "dogear", "dirty" }, paint_order)
    end

    it("refreshes only the dynamic item's slot and restores the dogear", function()
        make_view()

        scheduled[1].callback()
        assert_single_slot(250)

        reset_paint_log()
        ReaderUI.onNetworkConnected({})
        assert_single_slot(0)

        reset_paint_log()
        ReaderUI.onCharging({})
        assert.are.equal(0, #paint_rects)
        scheduled[#scheduled].callback()
        assert_single_slot(500)
    end)

    it("refreshes only configured dynamic slots on resume", function()
        _G.__ZEN_UI_PLUGIN.config.reader_top_status_bar.left_order = { "book_title" }
        _G.__ZEN_UI_PLUGIN.config.reader_top_status_bar.right_order = { "wifi", "battery" }
        make_view()

        ReaderUI.onResume({})

        assert.are.equal(2, #paint_rects)
        assert.same({ 250, 500 }, { paint_rects[1].x, paint_rects[2].x })
        assert.are.equal(2, #dirty_calls)
        for _i, call in ipairs(dirty_calls) do
            assert.is_nil(call.widget)
            assert.is_true(call.dither)
            assert.is_true(call.region.w < 600)
        end
        local dogear_paints = 0
        for _i, step in ipairs(paint_order) do
            if step == "dogear" then dogear_paints = dogear_paints + 1 end
        end
        assert.are.equal(1, dogear_paints)
    end)

    it("uses the active reader theme background for a direct slot refresh", function()
        package.loaded["common/reader_themes"].getBackgroundColor = function() return "sepia" end
        make_view()

        scheduled[1].callback()

        assert.are.equal("sepia", paint_rects[1].color)
        assert.is_nil(dirty_calls[1].widget)
        assert.is_true(dirty_calls[1].dither)
        assert.same({ "clear", "header", "dogear", "dirty" }, paint_order)
    end)
end)

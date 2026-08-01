describe("opening banner", function()
    local function apply_patch()
        ZenSpec.unload("modules/reader/patches/opening_banner")
        require("modules/reader/patches/opening_banner")()
    end

    local function install_stubs()
        local next_tick
        local shown, closed = {}, {}
        local ReaderUI = {
            showReaderCoroutine = function() end,
        }
        local ReaderHighlight = {
            onTap = function()
                return "stock"
            end,
        }
        local ListMenuItem = {
            onTapSelect = function()
                return "selected"
            end,
        }
        local MosaicMenuItem = {
            onTapSelect = function()
                return "mosaic selected"
            end,
        }
        local function build_list_items()
            return ListMenuItem
        end
        local function build_mosaic_items()
            return MosaicMenuItem
        end
        local Widget = {}
        function Widget:extend(proto)
            return setmetatable(proto, { __index = self })
        end
        function Widget:new(props)
            return setmetatable(props, { __index = self })
        end

        ZenSpec.replace("apps/reader/readerui", ReaderUI)
        ZenSpec.replace("apps/reader/modules/readerhighlight", ReaderHighlight)
        ZenSpec.replace("ui/uimanager", {
            show = function(_, widget)
                shown[#shown + 1] = widget
            end,
            close = function(_, widget)
                closed[#closed + 1] = widget
            end,
            nextTick = function(_, callback)
                next_tick = callback
            end,
            forceRePaint = function() end,
        })
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_, value) return value end,
            },
            setIgnoreInput = function() end,
        })
        ZenSpec.replace("ffi/blitbuffer", {})
        ZenSpec.replace("ui/font", {})
        ZenSpec.replace("ui/geometry", { new = function(_, value) return value end })
        ZenSpec.replace("ui/widget/textwidget", {})
        ZenSpec.replace("ui/widget/widget", Widget)
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return { info = function() end, warn = function() end, err = function() end, perf = function() end }
            end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("listmenu", { _updateItemsBuildUI = build_list_items })
        ZenSpec.replace("mosaicmenu", { _updateItemsBuildUI = build_mosaic_items })
        ZenSpec.replace("common/cover_utils", { BORDER_SIZE = 1 })
        ZenSpec.replace("apps/filemanager/filemanager", { instance = {} })

        return ReaderUI, ReaderHighlight, shown, closed, function()
            assert.is_function(next_tick)
            next_tick()
        end, ListMenuItem, MosaicMenuItem
    end

    it("defers no-banner opens while retaining a silent UI window", function()
        local ReaderUI, _, shown, closed, run_next_tick = install_stubs()
        local opens = 0
        local reader = {
            doShowReader = function()
                opens = opens + 1
            end,
        }
        apply_patch()

        ReaderUI.showReaderCoroutine(reader, "book.epub", {}, true)
        assert.are.equal(0, opens)
        assert.are.equal(1, #shown)
        assert.is_true(shown[1].invisible)

        run_next_tick()
        assert.same({ shown[1] }, closed)
        assert.are.equal(1, opens)
    end)

    it("uses a home-widget cover supplied by the opening-banner handoff", function()
        local ReaderUI, _, shown, _, run_next_tick = install_stubs()
        local opens = 0
        local reader = {
            doShowReader = function()
                opens = opens + 1
            end,
        }
        apply_patch()

        local set_cover = rawget(_G, "__ZEN_UI_SET_OPENING_BANNER_COVER")
        assert.is_function(set_cover)
        assert.is_true(set_cover({ dimen = { x = 31, y = 47, w = 220, h = 330 } }))
        assert.are.same({ x = 31, y = 349, w = 220, h = 28 }, shown[1].dimen)

        ReaderUI.showReaderCoroutine(reader, "book.epub", {})
        assert.are.equal(1, #shown)

        run_next_tick()
        assert.is_true(set_cover({ dimen = { x = 52, y = 80, w = 180, h = 270 } }))
        assert.are.same({ x = 52, y = 322, w = 180, h = 28 }, shown[2].dimen)
        ReaderUI.showReaderCoroutine(reader, "book.epub", {})
        assert.are.equal(2, #shown)

        run_next_tick()
        assert.are.equal(2, opens)
    end)

    it("prepares list banners only for actual books", function()
        local _, _, shown, _, _, ListMenuItem, MosaicMenuItem = install_stubs()
        apply_patch()

        local dimen = { x = 10, y = 20, w = 300, h = 60 }
        assert.are.equal("mosaic selected", MosaicMenuItem.onTapSelect({
            entry = { path = "/book.epub", is_file = true },
            filepath = "/book.epub",
            dimen = dimen,
            menu = { ui = { selected_files = {} } },
        }))
        assert.are.equal("selected", ListMenuItem.onTapSelect({
            entry = { path = "/book.epub", is_file = true },
            filepath = "/book.epub",
            dimen = dimen,
            menu = { ui = { selected_files = {} } },
        }))
        assert.are.equal(0, #shown)

        package.loaded["apps/filemanager/filemanager"].instance.selected_files = {}
        assert.are.equal("selected", ListMenuItem.onTapSelect({
            entry = { path = "/book.epub", is_file = true },
            filepath = "/book.epub",
            dimen = dimen,
            menu = {},
        }))
        assert.are.equal(0, #shown)
        package.loaded["apps/filemanager/filemanager"].instance.selected_files = nil

        assert.are.equal("selected", ListMenuItem.onTapSelect({
            entry = { text = "Author", _zen_files = { "/book.epub" } },
            dimen = dimen,
        }))
        assert.are.equal("selected", ListMenuItem.onTapSelect({
            entry = { path = "/books", attr = { mode = "directory" } },
            filepath = "/books",
            is_directory = true,
            dimen = dimen,
        }))
        assert.are.equal(0, #shown)

        assert.are.equal("selected", ListMenuItem.onTapSelect({
            entry = { path = "/book.epub", is_file = true },
            filepath = "/book.epub",
            dimen = dimen,
        }))
        assert.are.equal(1, #shown)
    end)

    it("ignores an early tap before visible highlight boxes exist", function()
        local _, ReaderHighlight = install_stubs()
        local stock_calls = 0
        ReaderHighlight.onTap = function()
            stock_calls = stock_calls + 1
            return "stock"
        end
        apply_patch()

        local highlight = {
            view = { highlight = { visible_boxes = nil } },
        }
        assert.is_nil(ReaderHighlight.onTap(highlight, nil, { pos = {} }))
        assert.are.equal(0, stock_calls)

        highlight.view.highlight.visible_boxes = {}
        assert.are.equal("stock", ReaderHighlight.onTap(highlight, nil, { pos = {} }))
        assert.are.equal(1, stock_calls)

        highlight.hold_pos = {}
        highlight.view.highlight.visible_boxes = nil
        assert.are.equal("stock", ReaderHighlight.onTap(highlight, nil, { pos = {} }))
        assert.are.equal(2, stock_calls)
    end)
end)

describe("reader interaction patches", function()
    local function apply_patch(name)
        ZenSpec.unload(name)
        require(name)()
    end

    before_each(function()
        _G.__ZEN_UI_PLUGIN = nil
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
    end)

    it("swallows holds in page margins and delegates content holds", function()
        local delegated = 0
        local ReaderHighlight = {
            onHold = function()
                delegated = delegated + 1
                return "stock"
            end,
        }
        ZenSpec.replace("apps/reader/modules/readerhighlight", ReaderHighlight)
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
            },
        })
        apply_patch("modules/reader/patches/margin_hold_guard")

        local highlight = {
            ui = {
                document = { getPageMargins = function()
                    return { left = 30, right = 40, top = 50, bottom = 60 }
                end },
            },
            view = { view_mode = "page" },
        }
        assert.is_false(ReaderHighlight.onHold(highlight, nil, { pos = { x = 10, y = 400 } }))
        assert.is_false(ReaderHighlight.onHold(highlight, nil, { pos = { x = 300, y = 20 } }))
        assert.are.equal("stock",
            ReaderHighlight.onHold(highlight, nil, { pos = { x = 300, y = 400 } }))
        assert.are.equal(1, delegated)
    end)

    it("does not guard vertical margins in scroll mode or any margins for paging docs", function()
        local delegated = 0
        local ReaderHighlight = {
            onHold = function()
                delegated = delegated + 1
                return "stock"
            end,
        }
        ZenSpec.replace("apps/reader/modules/readerhighlight", ReaderHighlight)
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
            },
        })
        apply_patch("modules/reader/patches/margin_hold_guard")

        local highlight = {
            ui = {
                document = { getPageMargins = function()
                    return { left = 30, right = 40, top = 50, bottom = 60 }
                end },
            },
            view = { view_mode = "scroll" },
        }
        assert.are.equal("stock",
            ReaderHighlight.onHold(highlight, nil, { pos = { x = 300, y = 10 } }))
        highlight.ui.paging = {}
        assert.are.equal("stock",
            ReaderHighlight.onHold(highlight, nil, { pos = { x = 10, y = 10 } }))
        assert.are.equal(2, delegated)
    end)

    it("acknowledges a new book version after stock reader setup and flushes changes", function()
        local order = {}
        local ReaderUI = {
            onReaderReady = function() order[#order + 1] = "stock" end,
        }
        ZenSpec.replace("apps/reader/readerui", ReaderUI)
        ZenSpec.replace("common/book_status", {
            acknowledgeNewVersion = function(settings)
                order[#order + 1] = "acknowledge"
                return settings.changed
            end,
        })
        apply_patch("modules/reader/patches/status_on_open")

        local ui = {
            doc_settings = {
                changed = true,
                flush = function() order[#order + 1] = "flush" end,
            },
        }
        ReaderUI.onReaderReady(ui)
        assert.same({ "stock", "acknowledge", "flush" }, order)
    end)

    it("does not flush status when acknowledgement makes no change", function()
        local flushes = 0
        local ReaderUI = { onReaderReady = function() end }
        ZenSpec.replace("apps/reader/readerui", ReaderUI)
        ZenSpec.replace("common/book_status", {
            acknowledgeNewVersion = function() return false end,
        })
        apply_patch("modules/reader/patches/status_on_open")

        ReaderUI.onReaderReady({ doc_settings = { flush = function() flushes = flushes + 1 end } })
        assert.are.equal(0, flushes)
    end)

    it("routes Home through library navigation only while a document is open", function()
        local stock_calls, routed = 0, 0
        local ReaderUI = {
            onHome = function(_, value)
                stock_calls = stock_calls + 1
                return value
            end,
        }
        local plugin = { marker = "plugin" }
        _G.__ZEN_UI_PLUGIN = plugin
        ZenSpec.replace("apps/reader/readerui", ReaderUI)
        ZenSpec.replace("common/library_navigation", {
            showFromReader = function(ui, received_plugin)
                routed = routed + 1
                assert.are.equal(plugin, received_plugin)
                assert.is_truthy(ui.document)
                return "library"
            end,
        })
        apply_patch("modules/reader/patches/library_navigation")

        assert.are.equal("library", ReaderUI.onHome({ document = {} }))
        assert.are.equal("stock", ReaderUI.onHome({}, "stock"))
        assert.are.equal(1, routed)
        assert.are.equal(1, stock_calls)
    end)

    it("updates bookmark page styling and swaps title-bar actions", function()
        local stock_calls, update_calls = 0, 0
        local ReaderBookmark = {
            onShowBookmark = function() stock_calls = stock_calls + 1 end,
        }
        ZenSpec.replace("apps/reader/modules/readerbookmark", ReaderBookmark)
        apply_patch("modules/reader/patches/bookmarks")

        local left_tap = function() return "left" end
        local left_hold = function() return "hold" end
        local right_tap = function() return "right" end
        local left, right = {
            callback = left_tap,
            hold_callback = left_hold,
            setIcon = function(self, icon) self.icon = icon end,
        }, {
            callback = right_tap,
            setIcon = function(self, icon) self.icon = icon end,
        }
        local menu = {
            font_size = 20,
            item_table = { { mandatory_dim = true }, { mandatory_dim = true } },
            updateItems = function() update_calls = update_calls + 1 end,
            title_bar = { left_button = left, right_button = right },
        }
        local bookmark = { bookmark_menu = { menu } }
        ReaderBookmark.onShowBookmark(bookmark)

        assert.are.equal(1, stock_calls)
        assert.are.equal(18, menu.items_mandatory_font_size)
        assert.is_nil(menu.item_table[1].mandatory_dim)
        assert.is_nil(menu.item_table[2].mandatory_dim)
        assert.are.equal(1, update_calls)
        assert.are.equal("chevron.left", left.icon)
        assert.are.equal(right_tap, left.callback)
        assert.is_nil(left.hold_callback)
        assert.are.equal("appbar.menu", right.icon)
        assert.are.equal(left_tap, right.callback)
        assert.are.equal(left_hold, right.hold_callback)

        menu.item_table[1].mandatory_dim = true
        menu:updateItems()
        assert.is_nil(menu.item_table[1].mandatory_dim)
        assert.are.equal(2, update_calls)
    end)
end)

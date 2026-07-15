describe("reader lookup menus", function()
    local shown

    local function logger_stub()
        return { dbg = function() end, warn = function() end, err = function() end }
    end

    before_each(function()
        shown = nil
        _G.__ZEN_UI_PLUGIN = nil
        ZenSpec.replace("common/zen_logger", { new = logger_stub })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/event", {
            new = function(_, name, ...)
                return { handler = "on" .. name, args = { ... }, name = name }
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            show = function(_, widget) shown = widget end,
            scheduleIn = function(_, _, callback) callback() end,
            setDirty = function() end,
            nextTick = function(_, callback) callback() end,
        })
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
        ZenSpec.unload("modules/reader/patches/highlight_menu")
        ZenSpec.unload("modules/reader/patches/dict_quick_lookup")
    end)

    it("renders the enabled highlight actions and dispatches their callbacks", function()
        local dialog_spec
        ZenSpec.replace("ui/widget/buttondialog", {
            new = function(_, spec)
                dialog_spec = spec
                return spec
            end,
        })
        local ReaderHighlight = { onShowHighlightMenu = function() return "stock" end }
        ZenSpec.replace("apps/reader/modules/readerhighlight", ReaderHighlight)
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { highlight_lookup = true },
                highlight_lookup = { show_wikipedia = true },
            },
        }
        require("modules/reader/patches/highlight_menu")()

        local calls, events = {}, {}
        local highlight = {
            selected_text = { text = "deterministic" },
            hold_pos = { x = 10, y = 20 },
            ui = { handleEvent = function(_, event) events[#events + 1] = event end },
            saveHighlight = function(_, close) calls.saved = close end,
            onClose = function() calls.closed = (calls.closed or 0) + 1 end,
            lookupWikipedia = function() calls.wikipedia = true end,
            translate = function(_, index) calls.translated = index end,
            onHighlightSearch = function() calls.searched = true end,
            _getDialogAnchor = function() return { x = 1, y = 2 } end,
        }
        ReaderHighlight.onShowHighlightMenu(highlight, 7)

        assert.are.equal(dialog_spec, shown)
        assert.same({
            "lookup.highlight", "lookup.wikipedia", "lookup.dictionary",
            "lookup.translate", "lookup.search",
        }, (function()
            local icons = {}
            for _i, button in ipairs(dialog_spec.buttons[1]) do
                icons[#icons + 1] = button.icon
            end
            return icons
        end)())
        dialog_spec.buttons[1][1].callback()
        dialog_spec.buttons[1][2].callback()
        dialog_spec.buttons[1][3].callback()
        dialog_spec.buttons[1][4].callback()
        dialog_spec.buttons[1][5].callback()
        assert.is_true(calls.saved)
        assert.is_true(calls.wikipedia)
        assert.are.equal(7, calls.translated)
        assert.is_true(calls.searched)
        assert.are.equal(2, calls.closed)
        assert.are.equal("LookupWord", events[1].name)
        assert.same({ "deterministic", true }, events[1].args)
    end)

    it("delegates the highlight menu when disabled and ignores empty selections", function()
        local stock_calls = 0
        local ReaderHighlight = {
            onShowHighlightMenu = function()
                stock_calls = stock_calls + 1
                return "stock"
            end,
        }
        ZenSpec.replace("apps/reader/modules/readerhighlight", ReaderHighlight)
        ZenSpec.replace("ui/widget/buttondialog", { new = function(_, spec) return spec end })
        _G.__ZEN_UI_PLUGIN = { config = { features = { highlight_lookup = false } } }
        require("modules/reader/patches/highlight_menu")()
        assert.are.equal("stock", ReaderHighlight.onShowHighlightMenu({}))
        assert.are.equal(1, stock_calls)

        _G.__ZEN_UI_PLUGIN.config.features.highlight_lookup = true
        assert.is_nil(ReaderHighlight.onShowHighlightMenu({}))
        assert.is_nil(shown)
    end)

    it("turns dictionary buttons into the configured icon row", function()
        local original = {
            { { id = "highlight", callback = function() end }, { id = "wikipedia" } },
            { { id = "translate" }, { id = "search" }, { id = "third_party", text = "Extra" } },
        }
        local DictQuickLookup = {
            buildButtonLayout = function() return original end,
        }
        ZenSpec.replace("ui/widget/dictquicklookup", DictQuickLookup)
        ZenSpec.replace("apps/reader/modules/readerhighlight", {})
        ZenSpec.replace("ui/translator", {})
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { dict_quick_lookup = true },
                highlight_lookup = { show_wikipedia = true, allow_unknown_items = true },
            },
        }
        require("modules/reader/patches/dict_quick_lookup")()

        local result = DictQuickLookup.buildButtonLayout({ highlight = {} })
        assert.same({
            "lookup.highlight", "lookup.wikipedia", "lookup.translate", "lookup.search",
        }, (function()
            local icons = {}
            for _i, button in ipairs(result[1]) do icons[#icons + 1] = button.icon end
            return icons
        end)())
        assert.are.equal("third_party", result[2][1].id)
        assert.are.equal("Extra", result[2][1].text)
    end)

    it("toggles an existing dictionary highlight off and closes the lookup", function()
        local original_adds, deleted, closes = 0, nil, 0
        local DictQuickLookup = {
            buildButtonLayout = function()
                return { { { id = "highlight", callback = function() original_adds = original_adds + 1 end } } }
            end,
        }
        ZenSpec.replace("ui/widget/dictquicklookup", DictQuickLookup)
        ZenSpec.replace("apps/reader/modules/readerhighlight", {})
        ZenSpec.replace("ui/translator", {})
        _G.__ZEN_UI_PLUGIN = {
            config = { features = { dict_quick_lookup = true }, highlight_lookup = {} },
        }
        require("modules/reader/patches/dict_quick_lookup")()

        local lookup = {
            highlight = {
                selected_text = { pos0 = "a", pos1 = "b" },
                ui = { rolling = {}, annotation = { annotations = {
                    { drawer = "lighten", pos0 = "a", pos1 = "b" },
                } } },
                deleteHighlight = function(_, index) deleted = index end,
            },
            onClose = function() closes = closes + 1 end,
        }
        local result = DictQuickLookup.buildButtonLayout(lookup)
        result[1][1].callback()
        assert.are.equal(1, deleted)
        assert.are.equal(0, original_adds)
        assert.are.equal(1, closes)
    end)
end)

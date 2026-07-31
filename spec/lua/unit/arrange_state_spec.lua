local ArrangeState = require("common/arrange_state")

describe("arrange state", function()
    it("detects reorder, additions, and removals by stable item identity", function()
        local original = {
            { orig_item = { id = "books" } },
            { orig_item = { id = "home" } },
        }

        assert.is_false(ArrangeState.hasRearrangedItems(original, {
            { orig_item = { id = "books" } },
            { orig_item = { id = "home" } },
        }))
        assert.is_true(ArrangeState.hasRearrangedItems(original, {
            { orig_item = { id = "home" } },
            { orig_item = { id = "books" } },
        }))
        assert.is_true(ArrangeState.hasRearrangedItems(original, {
            { orig_item = { id = "books" } },
        }))
    end)

    it("preserves labels while removing submenu and value decorations", function()
        assert.are.equal("Tabs", ArrangeState.stripSubmenuCaret("Tabs \u{25B8}"))
        assert.are.equal("Tabs", ArrangeState.stripSubmenuCaret("Tabs >"))
        assert.are.equal("Clock", ArrangeState.stripValueSuffix("Clock: 24-hour"))
        assert.are.equal("Title", ArrangeState.stripValueSuffix("Title"))
    end)

    it("uses entry keys and display text when an item has no explicit id", function()
        assert.are.equal("quick", ArrangeState.itemOrderKey({ orig_entry = { key = "quick" } }))
        assert.are.equal("Display", ArrangeState.itemOrderKey({ text = "Display" }))
        assert.is_true(ArrangeState.hasRearrangedItems(
            { { text = "One" } },
            { { text = "Two" } }
        ))
    end)

    it("routes root taps to controls instead of arrange selection", function()
        local configurable = {
            checked_func = function() return true end,
            callback = function() end,
            sub_item_table_func = function() return {} end,
        }
        local toggle_only = {
            checked_func = function() return true end,
            callback = function() end,
        }

        assert.are.equal("toggle", ArrangeState.rootTapAction(configurable, true))
        assert.are.equal("submenu", ArrangeState.rootTapAction(configurable, false))
        assert.are.equal("callback", ArrangeState.rootTapAction(toggle_only, false))
        assert.are.equal("consume", ArrangeState.rootTapAction({}, false))
    end)

    it("uses Right as hold-to-arrange only on non-touch few-key devices", function()
        assert.is_true(ArrangeState.rightKeyEntersArrange(false, true))
        assert.is_false(ArrangeState.rightKeyEntersArrange(true, true))
        assert.is_false(ArrangeState.rightKeyEntersArrange(false, false))
    end)

    it("recognizes unmodified Enter keys for delayed hold handling", function()
        local press = {
            match = function(_self, sequence) return sequence[1] == "Press" end,
        }
        local shifted_press = {
            match = function() return false end,
        }

        assert.are.equal("Press", ArrangeState.confirmKeyName("Press"))
        assert.are.equal("Return", ArrangeState.confirmKeyName("Return"))
        assert.are.equal("Press", ArrangeState.confirmKeyName(press))
        assert.is_nil(ArrangeState.confirmKeyName(shifted_press))
        assert.is_nil(ArrangeState.confirmKeyName("Down"))
    end)
end)

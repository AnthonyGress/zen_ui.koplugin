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
end)

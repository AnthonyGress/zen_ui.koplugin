describe("Markdown text formatting", function()
    local MarkdownText = require("common/ui/markdown_text")
    local header = "\u{FFF1}"
    local bold_start = "\u{FFF2}"
    local bold_end = "\u{FFF3}"

    it("formats headings, bullets, emphasis, links, and quotes", function()
        local rendered = MarkdownText.render(table.concat({
            "# What's New",
            "",
            "- Added **formatted bullets**",
            "  * Nested `item`",
            "1) First step",
            "> Read [the notes](https://example.com/notes)",
        }, "\n"))

        assert.are.equal(table.concat({
            header .. bold_start .. "What's New" .. bold_end,
            "",
            "\u{2022} Added " .. bold_start .. "formatted bullets" .. bold_end,
            "  \u{2022} Nested item",
            "1. First step",
            "\u{2502} Read the notes (https://example.com/notes)",
        }, "\n"), rendered)
    end)

    it("keeps identifier underscores while formatting emphasis", function()
        assert.are.equal(
            header .. "zen_ui and " .. bold_start .. "important" .. bold_end,
            MarkdownText.render("zen_ui and _important_")
        )
    end)

    it("builds the same formatted list used by update screens", function()
        assert.are.equal(table.concat({
            header .. bold_start .. "What's New" .. bold_end,
            "",
            "\u{2022} One",
            "\u{2022} " .. bold_start .. "Two" .. bold_end,
        }, "\n"), MarkdownText.format_list("What's New", { "One", "**Two**" }))
        assert.is_nil(MarkdownText.format_list("What's New", {}))
    end)
end)

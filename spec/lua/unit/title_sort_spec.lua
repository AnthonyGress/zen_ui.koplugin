local TitleSort = require("common/title_sort")

describe("title sort", function()
    local original_language

    before_each(function()
        original_language = G_reader_settings:readSetting("language")
    end)

    after_each(function()
        G_reader_settings:saveSetting("language", original_language)
    end)

    it("moves supported leading articles without changing other titles", function()
        assert.are.equal("Left Hand of Darkness", TitleSort.key("The Left Hand of Darkness"))
        assert.are.equal("Archive", TitleSort.key("An Archive"))
        assert.are.equal("A-Frame", TitleSort.key("A-Frame"))
        assert.are.equal("123", TitleSort.key("  123"))
    end)

    it("moves Spanish titles under the word after their article", function()
        G_reader_settings:saveSetting("language", "es_ES")

        assert.are.equal("blues de Beale Street", TitleSort.key("El blues de Beale Street"))
        assert.are.equal("castillo", TitleSort.key("El castillo"))
    end)
end)

describe("language names", function()
    local saved_language
    local saved_iso_language

    before_each(function()
        saved_language = package.loaded["ui/language"]
        saved_iso_language = package.loaded["ui/data/isolanguage"]
        ZenSpec.replace("ui/language", {
            getLanguageName = function(_, code)
                return code == "en" and "English" or code
            end,
        })
        ZenSpec.replace("ui/data/isolanguage", {
            getLocalizedLanguage = function(_, code)
                return code == "fra" and "French" or code
            end,
        })
        ZenSpec.unload("common/language_name")
    end)

    after_each(function()
        ZenSpec.unload("common/language_name")
        package.loaded["ui/language"] = saved_language
        package.loaded["ui/data/isolanguage"] = saved_iso_language
    end)

    it("writes out two- and three-letter language codes", function()
        local LanguageName = require("common/language_name")

        assert.are.equal("English", LanguageName.get("en"))
        assert.are.equal("English", LanguageName.get("en-US"))
        assert.are.equal("French", LanguageName.get("fra"))
        assert.are.equal("Unknown", LanguageName.get("Unknown"))
    end)
end)

describe("home quotes", function()
    local dofile_stub
    local HomeQuotes
    local state

    before_each(function()
        state = ZenSpec.memorySettings()
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, field)
                if path:match("quotes%.lua$") and field == "mode" then return "file" end
                return "directory"
            end,
            mkdir = function() return true end,
        })
        ZenSpec.replace("config/preset_store", {
            rootDir = function() return "/tmp/zen-ui-spec" end,
        })
        ZenSpec.replace("luasettings", {
            open = function() return state end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/quote_list", {
            { text = "Default quote", author = "Default author" },
        })
        dofile_stub = stub(_G, "dofile")
        ZenSpec.unload("modules/filebrowser/patches/home/home_quotes")
        HomeQuotes = require("modules/filebrowser/patches/home/home_quotes")
    end)

    after_each(function()
        dofile_stub:revert()
    end)

    it("uses only the default list when no sources are configured", function()
        assert.are.same({
            { text = "Default quote", author = "Default author" },
        }, HomeQuotes.getQuotes())
        assert.stub(dofile_stub).was_not_called()
    end)

    it("supports plain, legacy, and title-bearing custom quotes", function()
        dofile_stub.returns({
            "Plain quote",
            { text = "Legacy quote", author = "Legacy author" },
            {
                text = "Enhanced quote",
                author = "Enhanced author",
                title = "Enhanced title",
            },
        })

        assert.are.same({
            {
                text = "Plain quote",
                author = "",
                title = "",
                attribution = "",
            },
            {
                text = "Legacy quote",
                author = "Legacy author",
                title = "",
                attribution = "Legacy author",
            },
            {
                text = "Enhanced quote",
                author = "Enhanced author",
                title = "Enhanced title",
                attribution = "Enhanced author,  Enhanced title",
            },
        }, HomeQuotes.getQuotes({ sources = { custom = true } }))
    end)

    it("combines selected sources", function()
        dofile_stub.returns({ { text = "Custom quote", author = "Custom author" } })

        local quotes = HomeQuotes.getQuotes({
            sources = { default = true, custom = true },
        })
        assert.are.equal("Default quote", quotes[1].text)
        assert.are.equal("Custom quote", quotes[2].text)
    end)

    it("keeps a daily quote stable and advances a shuffled deck on refresh", function()
        dofile_stub.returns({
            "First",
            "Second",
            "Third",
        })
        local config = { sources = { custom = true } }

        local daily = HomeQuotes.selectQuote(config, "daily")
        assert.are.equal(daily.text, HomeQuotes.selectQuote(config, "daily").text)

        local refresh_two = HomeQuotes.selectQuote(config, "refresh")
        local refresh_three = HomeQuotes.selectQuote(config, "refresh")
        assert.are_not.equal(daily.text, refresh_two.text)
        assert.are_not.equal(daily.text, refresh_three.text)
        assert.are_not.equal(refresh_two.text, refresh_three.text)
    end)

    it("does not skip again after a manual swipe rebuild", function()
        dofile_stub.returns({
            "First",
            "Second",
            "Third",
        })
        local config = { sources = { custom = true } }
        HomeQuotes.selectQuote(config, "refresh")
        local stepped = HomeQuotes.stepQuote(config, 1)

        assert.are.equal(stepped.text, HomeQuotes.selectQuote(config, "refresh").text)
    end)
end)

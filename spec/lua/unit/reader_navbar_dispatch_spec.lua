describe("reader navbar dispatch", function()
    local Dispatch
    local reader
    local calls

    before_each(function()
        calls = {}
        reader = { document = { file = "/library/Book.epub" } }
        ZenSpec.replace("apps/reader/readerui", { instance = reader })
        ZenSpec.replace("common/library_navigation", {
            showFromReader = function(received_reader, plugin, opts)
                calls[#calls + 1] = {
                    reader = received_reader,
                    plugin = plugin,
                    opts = opts,
                }
                return true
            end,
        })
        ZenSpec.unload("common/dispatch_action")
        Dispatch = require("common/dispatch_action")
    end)

    it("returns from the reader to the requested navbar group tab", function()
        local plugin = { marker = "zen" }

        assert.is_true(Dispatch.onShowZenUIAuthors(plugin))
        assert.are.equal(reader, calls[1].reader)
        assert.are.equal(plugin, calls[1].plugin)
        assert.are.equal("authors", calls[1].opts.target_tab)
        assert.is_nil(calls[1].opts.open_home)

        assert.is_true(Dispatch.onShowZenUISeries(plugin))
        assert.are.equal("series", calls[2].opts.target_tab)

        assert.is_true(Dispatch.onShowZenUITags(plugin))
        assert.are.equal("tags", calls[3].opts.target_tab)

        assert.is_true(Dispatch.onShowZenUIStats(plugin))
        assert.are.equal("stats", calls[4].opts.target_tab)
    end)

    it("routes the reader Home action without replacing it with a tab target", function()
        local plugin = { marker = "zen" }

        assert.is_true(Dispatch.onShowZenUIHome(plugin))
        assert.are.equal(reader, calls[1].reader)
        assert.are.equal(plugin, calls[1].plugin)
        assert.is_true(calls[1].opts.open_home)
        assert.is_nil(calls[1].opts.target_tab)
    end)

    it("registers Stats as a general dispatcher action", function()
        local actions = {}
        ZenSpec.replace("dispatcher", {
            registerAction = function(_self, name, spec) actions[name] = spec end,
            _addItem = function() end,
        })
        ZenSpec.replace("util", {})
        ZenSpec.replace("ui/uimanager", {})

        Dispatch.onDispatcherRegisterActions()

        local action = actions.zen_ui_show_stats
        assert.are.equal("ShowZenUIStats", action.event)
        assert.are.equal("ZenOS: Stats", action.title)
        assert.is_true(action.general)
    end)
end)

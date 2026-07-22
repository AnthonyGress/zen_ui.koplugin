describe("incognito mode guards", function()
    local original_plugin

    before_each(function()
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        ZenSpec.unload("modules/global/patches/incognito_mode")
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = original_plugin
    end)

    it("suppresses history and sidecar writes only while enabled", function()
        local history_calls = 0
        local flush_calls = 0
        local ReadHistory = { addItem = function() history_calls = history_calls + 1; return "history" end }
        local DocSettings = { flush = function() flush_calls = flush_calls + 1; return "flush" end }
        ZenSpec.replace("readhistory", ReadHistory)
        ZenSpec.replace("docsettings", DocSettings)
        local plugin = { config = { features = { incognito_mode = false } } }
        _G.__ZEN_UI_PLUGIN = plugin

        require("modules/global/patches/incognito_mode").apply()
        assert.are.equal("history", ReadHistory:addItem("book"))
        assert.are.equal("flush", DocSettings:flush())

        plugin.config.features.incognito_mode = true
        assert.is_nil(ReadHistory:addItem("book"))
        assert.is_nil(DocSettings:flush())
        assert.are.equal(1, history_calls)
        assert.are.equal(1, flush_calls)
    end)
end)

describe("lockdown mode guards", function()
    local original_plugin

    before_each(function()
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        ZenSpec.unload("modules/global/patches/lockdown_mode")
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = original_plugin
    end)

    it("blocks configured hold gestures only while lockdown is active", function()
        local hold_calls = 0
        local pan_calls = 0
        local ReaderHighlight = {
            onHold = function() hold_calls = hold_calls + 1; return "hold" end,
            onHoldPan = function() pan_calls = pan_calls + 1; return "pan" end,
        }
        ZenSpec.replace("apps/reader/modules/readerhighlight", ReaderHighlight)
        local plugin = {
            config = {
                features = { lockdown_mode = false },
                lockdown = { disable_hold_search = true, disable_word_selection = true },
            },
        }
        _G.__ZEN_UI_PLUGIN = plugin

        require("modules/global/patches/lockdown_mode").apply()
        assert.are.equal("hold", ReaderHighlight:onHold({}, {}))
        assert.are.equal("pan", ReaderHighlight:onHoldPan({}, {}))

        plugin.config.features.lockdown_mode = true
        assert.is_false(ReaderHighlight:onHold({}, {}))
        assert.is_false(ReaderHighlight:onHoldPan({}, {}))
        assert.are.equal(1, hold_calls)
        assert.are.equal(1, pan_calls)
    end)

    it("saves and restores the pre-magnification browser layout", function()
        local values = {
            nb_cols_portrait = 4,
            nb_rows_portrait = 5,
            files_per_page = 12,
        }
        local BookInfoManager = {
            getSetting = function(_self, key) return values[key] end,
            saveSetting = function(_self, key, value) values[key] = value end,
        }
        ZenSpec.replace("bookinfomanager", BookInfoManager)
        local lockdown = { magnify_ui = true }
        local plugin = { config = { lockdown = lockdown } }
        local Lockdown = require("modules/global/patches/lockdown_mode")

        Lockdown.apply_magnify_layout(plugin, true)
        assert.are.same({ 2, 2, 3 }, {
            values.nb_cols_portrait, values.nb_rows_portrait, values.files_per_page,
        })

        Lockdown.apply_magnify_layout(plugin, false)
        assert.are.same({ 4, 5, 12 }, {
            values.nb_cols_portrait, values.nb_rows_portrait, values.files_per_page,
        })
        assert.is_nil(lockdown._pre_nb_cols_portrait)
        assert.is_nil(lockdown._pre_nb_rows_portrait)
        assert.is_nil(lockdown._pre_files_per_page)
    end)
end)

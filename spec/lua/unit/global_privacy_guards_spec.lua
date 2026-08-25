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
        local stats_calls = {
            annotations = 0,
            init = 0,
            insert = 0,
            metadata = 0,
            page = 0,
        }
        local ReadHistory = { addItem = function() history_calls = history_calls + 1; return "history" end }
        local DocSettings = { flush = function() flush_calls = flush_calls + 1; return "flush" end }
        local Statistics = {
            name = "statistics",
            initData = function() stats_calls.init = stats_calls.init + 1; return "init" end,
            getIdBookDB = function() return 42 end,
            onPageUpdate = function() stats_calls.page = stats_calls.page + 1; return "page" end,
            insertDB = function() stats_calls.insert = stats_calls.insert + 1; return "insert" end,
            onAnnotationsModified = function() stats_calls.annotations = stats_calls.annotations + 1 end,
            onBookMetadataChanged = function() stats_calls.metadata = stats_calls.metadata + 1 end,
            resetVolatileStats = function(self, now_ts)
                self.page_stat = now_ts and { [self.curr_page] = { { now_ts, 0 } } } or {}
            end,
        }
        local stats_instance = setmetatable({
            curr_page = 1,
            isEnabledAndNotFrozen = function() return true end,
            ui = { getCurrentPage = function() return 9 end },
        }, { __index = Statistics })
        ZenSpec.replace("readhistory", ReadHistory)
        ZenSpec.replace("docsettings", DocSettings)
        ZenSpec.replace("pluginloader", {
            loadPlugins = function() return { Statistics } end,
            getPluginInstance = function() return stats_instance end,
        })
        local plugin = { config = { features = { incognito_mode = false } } }
        _G.__ZEN_UI_PLUGIN = plugin

        local Incognito = require("modules/global/patches/incognito_mode")
        Incognito.apply()
        assert.are.equal("history", ReadHistory:addItem("book"))
        assert.are.equal("flush", DocSettings:flush())
        assert.are.equal("init", stats_instance:initData())
        assert.are.equal(42, stats_instance:getIdBookDB())
        assert.are.equal("page", stats_instance:onPageUpdate(2))
        assert.are.equal("insert", stats_instance:insertDB())
        stats_instance:onAnnotationsModified({})
        stats_instance:onBookMetadataChanged({})

        Incognito.beforeEnable()
        plugin.config.features.incognito_mode = true
        assert.is_nil(ReadHistory:addItem("book"))
        assert.is_nil(DocSettings:flush())
        assert.is_nil(stats_instance:initData())
        assert.is_nil(stats_instance:getIdBookDB())
        assert.is_nil(stats_instance:onPageUpdate(3))
        assert.is_nil(stats_instance:insertDB())
        stats_instance:onAnnotationsModified({})
        stats_instance:onBookMetadataChanged({})
        assert.are.equal(1, history_calls)
        assert.are.equal(1, flush_calls)
        assert.are.same({
            annotations = 1,
            init = 1,
            insert = 2,
            metadata = 1,
            page = 2,
        }, stats_calls)
        assert.are.same({}, stats_instance.page_stat)

        plugin.config.features.incognito_mode = false
        Incognito.afterDisable()
        assert.are.equal(2, stats_calls.init)
        assert.is_nil(stats_instance._zen_incognito_needs_init)
        assert.are.equal(9, stats_instance.curr_page)
        assert.is_not_nil(stats_instance.page_stat[9])
    end)

    it("persists and resumes the configured timeout", function()
        local scheduled_callback
        local scheduled_delay
        local unscheduled = 0
        local expired
        local saves = 0
        ZenSpec.replace("readhistory", { addItem = function() end })
        ZenSpec.replace("docsettings", { flush = function() end })
        ZenSpec.replace("pluginloader", {
            loadPlugins = function() return {} end,
            getPluginInstance = function() return nil end,
        })
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function(_, delay, callback)
                scheduled_delay = delay
                scheduled_callback = callback
            end,
            unschedule = function() unscheduled = unscheduled + 1 end,
        })
        ZenSpec.replace("common/dispatch_action", {
            setIncognitoMode = function(_plugin, enabled, opts)
                expired = { enabled = enabled, timed_out = opts and opts.timed_out }
            end,
        })
        local plugin = {
            config = {
                features = { incognito_mode = false },
                incognito = { timeout_minutes = 5 },
            },
            saveConfig = function() saves = saves + 1 end,
        }
        _G.__ZEN_UI_PLUGIN = plugin

        local Incognito = require("modules/global/patches/incognito_mode")
        Incognito.apply()
        plugin.config.features.incognito_mode = true
        Incognito.afterEnable(plugin)
        assert.are.equal(300, scheduled_delay)
        assert.is_not_nil(plugin.config.incognito.timeout_at)

        Incognito.onSuspend()
        assert.are.equal(1, unscheduled)
        Incognito.onResume(plugin)
        assert.is_true(scheduled_delay > 0 and scheduled_delay <= 300)

        assert.is_true(Incognito.setTimeoutMinutes(plugin, 15))
        assert.are.equal(15, plugin.config.incognito.timeout_minutes)
        assert.are.equal(900, scheduled_delay)
        assert.are.equal(1, saves)

        plugin.config.incognito.timeout_at = os.time() - 1
        scheduled_callback()
        assert.are.same({ enabled = false, timed_out = true }, expired)
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

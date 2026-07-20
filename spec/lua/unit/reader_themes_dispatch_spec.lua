describe("reader themes dispatcher action", function()
    local Dispatch
    local applied

    before_each(function()
        applied = {}
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("modules/settings/zen_settings_apply", {
            apply_feature_toggle = function(plugin, feature, enabled)
                applied[#applied + 1] = { plugin = plugin, feature = feature, enabled = enabled }
            end,
        })
        ZenSpec.unload("common/dispatch_action")
        Dispatch = require("common/dispatch_action")
    end)

    it("registers a reader-only toggle with active state", function()
        local actions = {}
        ZenSpec.replace("dispatcher", {
            registerAction = function(_, name, spec) actions[name] = spec end,
            _addItem = function() end,
        })
        ZenSpec.replace("util", {})
        ZenSpec.replace("ui/uimanager", {})

        Dispatch.onDispatcherRegisterActions()
        local action = actions.zen_ui_toggle_reader_themes
        assert.are.equal("ToggleReaderThemes", action.event)
        assert.is_true(action.reader)
        assert.is_true(action.active_func({ config = { features = { reader_themes = true } } }))
    end)

    it("persists and applies the same feature toggle", function()
        local saves = 0
        local plugin = {
            config = { features = { reader_themes = false } },
            saveConfig = function() saves = saves + 1 end,
        }

        assert.is_true(Dispatch.onToggleReaderThemes(plugin))
        assert.is_true(plugin.config.features.reader_themes)
        assert.are.equal(1, saves)
        assert.are.equal("reader_themes", applied[1].feature)
        assert.is_true(applied[1].enabled)
    end)
end)

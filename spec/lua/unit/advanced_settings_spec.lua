describe("Advanced settings", function()
    before_each(function()
        _G.G_reader_settings = ZenSpec.memorySettings()
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {
            show = function() end,
        })
        ZenSpec.replace("modules/settings/zen_settings_utils", {})
        ZenSpec.replace("common/paths", {})
        ZenSpec.unload("modules/settings/sections/advanced_settings")
    end)

    it("does not expose the old Reader margins action", function()
        local items = require("modules/settings/sections/advanced_settings").build({
            config = { features = {}, developer = {} },
            plugin = { saveConfig = function() end },
            settings_apply = { prompt_restart = function() end },
        })
        for _i, item in ipairs(items) do
            assert.are_not.equal("Enable Zen UI Reader margins", item.text)
        end
    end)

    it("keeps settings open when clearing gestures", function()
        local items = require("modules/settings/sections/advanced_settings").build({
            config = { features = {}, developer = {} },
            plugin = { saveConfig = function() end },
            settings_apply = { prompt_restart = function() end },
        })
        local clear_gestures
        for _i, item in ipairs(items) do
            if item.text == "Clear all gestures" then
                clear_gestures = item
                break
            end
        end

        assert.is_true(clear_gestures.keep_menu_open)
    end)

    it("toggles double-tap book opening", function()
        local saved = 0
        local config = { features = {}, developer = {} }
        local items = require("modules/settings/sections/advanced_settings").build({
            config = config,
            plugin = { saveConfig = function() saved = saved + 1 end },
            settings_apply = { prompt_restart = function() end },
        })
        local double_tap_item
        for _i, item in ipairs(items) do
            if item.text == "Require double tap to open books" then
                double_tap_item = item
                break
            end
        end

        assert.is_table(double_tap_item)
        assert.is_false(double_tap_item.checked_func())
        double_tap_item.callback()
        assert.is_true(double_tap_item.checked_func())
        assert.are.equal(1, saved)
    end)
end)

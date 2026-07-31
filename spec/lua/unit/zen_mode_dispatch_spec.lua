describe("Zen mode dispatcher action", function()
    local saved_modules

    local dependencies = {
        "gettext",
        "ui/uimanager",
        "ui/widget/infomessage",
        "modules/settings/zen_settings_apply",
        "common/dispatch_action",
    }

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(dependencies) do saved_modules[name] = package.loaded[name] end
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {
            show = function(_self, message) _G.__ZEN_UI_TEST_MESSAGE = message end,
        })
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_self, options) return options end,
        })
        _G.__ZEN_UI_TEST_MESSAGE = nil
        ZenSpec.unload("common/dispatch_action")
    end)

    after_each(function()
        for _i, name in ipairs(dependencies) do package.loaded[name] = saved_modules[name] end
        _G.__ZEN_UI_TEST_MESSAGE = nil
    end)

    it("persists, applies, and reports Zen mode changes live", function()
        local applied = {}
        local restart_prompts = 0
        ZenSpec.replace("modules/settings/zen_settings_apply", {
            apply_feature_toggle = function(plugin, feature, enabled)
                applied[#applied + 1] = { plugin = plugin, feature = feature, enabled = enabled }
            end,
            prompt_restart = function() restart_prompts = restart_prompts + 1 end,
        })
        local saves = 0
        local plugin = {
            config = { features = { zen_mode = false } },
            saveConfig = function() saves = saves + 1 end,
        }

        assert.is_true(require("common/dispatch_action").onToggleZenMode(plugin))
        assert.is_true(plugin.config.features.zen_mode)
        assert.are.equal(1, saves)
        assert.are.same({ plugin = plugin, feature = "zen_mode", enabled = true }, applied[1])
        assert.are.same({ text = "Zen Mode: Enabled", timeout = 2 }, _G.__ZEN_UI_TEST_MESSAGE)
        assert.is_true(require("common/dispatch_action").onToggleZenMode(plugin))
        assert.is_false(plugin.config.features.zen_mode)
        assert.are.equal(2, saves)
        assert.are.same({ plugin = plugin, feature = "zen_mode", enabled = false }, applied[2])
        assert.are.same({ text = "Zen Mode: Disabled", timeout = 2 }, _G.__ZEN_UI_TEST_MESSAGE)
        assert.are.equal(0, restart_prompts)
    end)
end)

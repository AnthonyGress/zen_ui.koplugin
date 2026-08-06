describe("Advanced settings", function()
    local shown_message

    before_each(function()
        shown_message = nil
        _G.G_reader_settings = ZenSpec.memorySettings()
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {
            show = function(_self, widget) shown_message = widget end,
        })
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_self, spec) return spec end,
        })
        ZenSpec.replace("modules/settings/zen_settings_utils", {})
        ZenSpec.replace("common/paths", {})
        ZenSpec.unload("modules/settings/sections/advanced_settings")
    end)

    it("offers the Quickstart Reader margin defaults", function()
        local items = require("modules/settings/sections/advanced_settings").build({
            config = { features = {}, developer = {} },
            plugin = { saveConfig = function() end },
            settings_apply = { prompt_restart = function() end },
        })
        local margin_item
        for _i, item in ipairs(items) do
            if item.text == "Enable Zen UI Reader margins" then
                margin_item = item
                break
            end
        end

        assert.is_table(margin_item)
        margin_item.callback()

        assert.are.same({30, 30}, G_reader_settings:readSetting("copt_h_page_margins"))
        assert.are.equal(1, G_reader_settings:readSetting("copt_sync_t_b_page_margins"))
        assert.are.equal(30, G_reader_settings:readSetting("copt_t_page_margin"))
        assert.are.equal(30, G_reader_settings:readSetting("copt_b_page_margin"))
        assert.are.equal("Zen UI Reader margins enabled", shown_message.text)
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

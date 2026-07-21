describe("reader themes settings", function()
    local ReaderSettings
    local shown_dialog
    local dialog_input
    local reader_settings

    before_each(function()
        shown_dialog = nil
        dialog_input = nil
        reader_settings = {}
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {
            show = function(_, dialog) shown_dialog = dialog end,
            close = function() end,
        })
        ZenSpec.replace("ui/event", {})
        ZenSpec.replace("common/dispatch_action", {})
        ZenSpec.replace("modules/settings/zen_settings_utils", {
            make_enable_feature_item = function(feature, text, config, save_and_apply)
                return {
                    text = text,
                    checked_func = function() return config.features[feature] == true end,
                    callback = function()
                        config.features[feature] = config.features[feature] ~= true
                        save_and_apply(feature)
                    end,
                }
            end,
        })
        ZenSpec.replace("common/constants", { SEPARATOR_PRESETS = {} })
        ZenSpec.replace("config/preset_store", {
            getSettings = function() return reader_settings end,
            saveSettings = function(_, settings)
                reader_settings = settings
                return true
            end,
        })
        ZenSpec.replace("common/inline_icon_map", {
            settings_status = "status",
            settings_background = "background",
            title = "title",
            search = "search",
        })
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item) return item end,
        })
        ZenSpec.replace("ui/widget/inputdialog", {
            new = function(_, spec)
                spec.getInputText = function() return dialog_input end
                spec.onShowKeyboard = function() end
                return spec
            end,
        })
        ZenSpec.unload("modules/settings/sections/reader_settings")
        ReaderSettings = require("modules/settings/sections/reader_settings")
    end)

    it("creates a named custom copy only after a built-in theme changes", function()
        local saved, applied = 0, 0
        local config = {
            features = {
                reader_themes = true,
                reader_top_status_bar = false,
                dict_quick_lookup = false,
                highlight_lookup = false,
                reader_bottom_menu = false,
                page_browser = false,
                restore_library_view = false,
            },
            reader_themes = { dark_mode = "dark_warm_gray", light_mode = "default" },
        }
        local items = ReaderSettings.build({
            config = config,
            plugin = { saveConfig = function() saved = saved + 1 end },
            save_and_apply = function() end,
            apply_feature = function() applied = applied + 1 end,
        })
        local themes
        for _i, item in ipairs(items) do
            if item.text == "Reader themes" then themes = item end
        end
        local custom_items = themes.sub_item_table[4].sub_item_table_func()
        local dark_warm_gray = custom_items[2]

        dialog_input = "#1f1f1f"
        dark_warm_gray.sub_item_table[1].callback()
        shown_dialog.buttons[1][2].callback()
        assert.is_nil(config.reader_themes.custom.custom_1)

        dialog_input = "#101010"
        dark_warm_gray.sub_item_table[1].callback()
        shown_dialog.buttons[1][2].callback()
        local custom = config.reader_themes.custom.custom_1
        assert.are.equal("Custom Dark warm gray", custom.name)
        assert.are.equal("#101010", custom.background)
        assert.are.equal("#dcdccc", custom.text)
        assert.are.equal("dark_warm_gray", config.reader_themes.dark_mode)
        assert.are.equal(custom, reader_settings.reader_themes.custom.custom_1)
        assert.are.equal(1, saved)
        assert.are.equal(1, applied)
    end)

    it("creates a custom theme without using a built-in theme as its base", function()
        local saved, applied = 0, 0
        local config = {
            features = {
                reader_themes = true,
                reader_top_status_bar = false,
                dict_quick_lookup = false,
                highlight_lookup = false,
                reader_bottom_menu = false,
                page_browser = false,
                restore_library_view = false,
            },
            reader_themes = { dark_mode = "dark_warm_gray", light_mode = "default" },
        }
        local items = ReaderSettings.build({
            config = config,
            plugin = { saveConfig = function() saved = saved + 1 end },
            save_and_apply = function() end,
            apply_feature = function() applied = applied + 1 end,
        })
        local themes
        for _i, item in ipairs(items) do
            if item.text == "Reader themes" then themes = item end
        end
        local custom_items = themes.sub_item_table[4].sub_item_table_func()
        local new_theme = custom_items[1]

        assert.are.equal("New custom theme", new_theme.text_func())
        dialog_input = "#f0f0f0"
        new_theme.sub_item_table[2].callback()
        shown_dialog.buttons[1][2].callback()

        local custom = config.reader_themes.custom.custom_1
        assert.are.equal("Custom theme", custom.name)
        assert.are.equal("#f0f0f0", custom.background)
        assert.are.equal("#000000", custom.text)
        assert.are.equal("default", custom.font_face)
        assert.are.equal("dark_warm_gray", config.reader_themes.dark_mode)
        assert.are.equal("default", config.reader_themes.light_mode)
        assert.are.equal(custom, reader_settings.reader_themes.custom.custom_1)
        assert.are.equal(1, saved)
        assert.are.equal(1, applied)
    end)

    it("persists separate light and dark themes and immediately applies enabled themes", function()
        local saved, applied = 0, {}
        local config = {
            features = {
                reader_themes = false,
                reader_top_status_bar = false,
                dict_quick_lookup = false,
                highlight_lookup = false,
                reader_bottom_menu = false,
                page_browser = false,
                restore_library_view = false,
            },
            reader_themes = { dark_mode = "dark_warm_gray", light_mode = "default" },
        }
        local items = ReaderSettings.build({
            config = config,
            plugin = { saveConfig = function() saved = saved + 1 end },
            save_and_apply = function(feature) applied[#applied + 1] = feature end,
            apply_feature = function(feature) applied[#applied + 1] = feature end,
        })
        local themes
        for _i, item in ipairs(items) do
            if item.text == "Reader themes" then themes = item end
        end

        assert.is_table(themes)
        local enable = themes.sub_item_table[1]
        enable.callback()
        assert.is_true(config.features.reader_themes)
        assert.are.equal("reader_themes", applied[1])

        local dark_themes = themes.sub_item_table[2].sub_item_table_func()
        dark_themes[4].callback()
        assert.are.equal("light_sepia", config.reader_themes.dark_mode)
        local light_themes = themes.sub_item_table[3].sub_item_table_func()
        light_themes[1].callback()
        assert.are.equal("default", config.reader_themes.light_mode)

        config.reader_themes.custom = {
            custom_1 = {
                name = "Paper",
                text = "#30251b",
                background = "#f5e7ce",
                font_face = "default",
            },
        }
        dark_themes = themes.sub_item_table[2].sub_item_table_func()
        dark_themes[#dark_themes].callback()
        assert.are.equal("custom_1", config.reader_themes.dark_mode)
        assert.are.equal(3, saved)
        assert.are.equal("reader_themes", applied[4])
    end)
end)

describe("reader themes settings", function()
    local ReaderSettings
    local shown_dialog
    local dialog_input
    local reader_store

    before_each(function()
        shown_dialog = nil
        dialog_input = nil
        reader_store = { settings = { footer = { existing = true } } }
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
            loadStore = function() return reader_store end,
            saveStore = function(_, store)
                reader_store = store
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
        ZenSpec.replace("ui/widget/confirmbox", {
            new = function(_, spec) return spec end,
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
        assert.are.equal(custom, reader_store.reader_themes.custom.custom_1)
        assert.is_nil(reader_store.settings.reader_themes)
        assert.is_true(reader_store.settings.footer.existing)
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

        assert.are.equal("New custom theme", new_theme.text)
        local opened_item, updates = nil, 0
        local touchmenu = {
            item_table_stack = {},
            updateItems = function() updates = updates + 1 end,
            onMenuSelect = function(self, item)
                opened_item = item
                table.insert(self.item_table_stack, self.item_table)
                self.item_table = item.sub_item_table
            end,
            backToUpperMenu = function(self)
                self.item_table = table.remove(self.item_table_stack)
                self:updateItems()
            end,
        }
        new_theme.callback(touchmenu)

        local custom = config.reader_themes.custom.custom_1
        assert.are.equal("Custom theme", custom.name)
        assert.are.equal("#ffffff", custom.background)
        assert.are.equal("#000000", custom.text)
        assert.are.equal("default", custom.font_face)
        assert.are.equal("dark_warm_gray", config.reader_themes.dark_mode)
        assert.are.equal("default", config.reader_themes.light_mode)
        assert.are.equal(custom, reader_store.reader_themes.custom.custom_1)
        assert.are.equal("Custom theme", opened_item.text_func())
        assert.are.equal("Theme name: Custom theme", touchmenu.item_table[1].text_func())
        assert.are.equal("Background color: #ffffff", touchmenu.item_table[2].text_func())
        assert.are.equal("Text color: #000000", touchmenu.item_table[3].text_func())
        assert.are.equal("New custom theme", touchmenu.item_table_stack[1][1].text)
        assert.are.equal(1, saved)
        assert.are.equal(1, applied)

        touchmenu.item_table[5].callback(touchmenu)
        shown_dialog.ok_callback()

        assert.is_nil(config.reader_themes.custom.custom_1)
        assert.are.equal(0, #touchmenu.item_table_stack)
        assert.are.equal(5, #touchmenu.item_table)
        assert.are.equal("New custom theme", touchmenu.item_table[1].text)
        assert.are.equal(1, updates)
        assert.are.equal(2, saved)
        assert.are.equal(2, applied)
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

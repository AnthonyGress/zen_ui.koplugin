describe("app launcher settings", function()
    local entry
    local launcher_cfg
    local saves
    local shown_options

    before_each(function()
        entry = {
            id = "al_1",
            type = "plugin",
            label = "Legacy",
            icon = "zen_ui",
            plugin = { key = "legacy", method = "open" },
        }
        shown_options = nil
        saves = 0
        launcher_cfg = { entries = { entry } }

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ffi/util", {
            template = function(text, value)
                return text:gsub("%%1", tostring(value))
            end,
        })
        ZenSpec.replace("ui/uimanager", {})
        ZenSpec.replace("common/inline_icon_map", setmetatable({}, {
            __index = function(_self, key) return key end,
        }))
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item) return item end,
        })
        ZenSpec.replace("common/utils", {
            getIconDisplayName = function(name)
                return name == "zen_ui" and "ZenOS" or name
            end,
            getIconPickerList = function() return {} end,
            suggestIcon = function() return "lightning" end,
        })
        ZenSpec.replace("modules/menu/app_launcher/model", {
            ensure = function()
                return launcher_cfg
            end,
            display_label = function(item) return item.label end,
            save = function() saves = saves + 1 end,
        })
        ZenSpec.replace("modules/menu/app_launcher/native_menu", {
            scan = function() return {} end,
        })
        ZenSpec.replace("modules/menu/app_launcher/plugin_scan", {
            scan = function() return {} end,
        })
        ZenSpec.replace("common/dispatcher_menu", { wrap = function() end })
        ZenSpec.replace("dispatcher", {})
        ZenSpec.replace("common/plugin_root", "/plugin")
        ZenSpec.replace("common/ui/zen_arrange_list", {
            show = function(options) shown_options = options end,
        })
        ZenSpec.unload("modules/settings/sections/app_launcher_settings")
    end)

    it("displays ZenOS without rewriting the persisted legacy icon ID", function()
        local section = require(
            "modules/settings/sections/app_launcher_settings").build({
                config = { features = { app_launcher = true } },
                save_and_apply = function() end,
        })

        local search_items = section._zen_search_items_func()
        assert.is_true(search_items[1]._zen_search_open())
        local icon_label
        for _i, item in ipairs(shown_options.item_table) do
            if item.text_func and item.text_func():sub(1, 6) == "Icon: " then
                icon_label = item.text_func()
                break
            end
        end

        assert.are.equal("Icon: ZenOS", icon_label)
        assert.are.equal("zen_ui", entry.icon)
    end)

    it("offers reader-only Book details without a redundant visibility setting", function()
        local section = require(
            "modules/settings/sections/app_launcher_settings").build({
                config = { features = { app_launcher = true } },
                save_and_apply = function() end,
        })
        local details
        for _i, item in ipairs(section.sub_item_table) do
            if item.text == "Book details" then details = item end
        end

        assert.is_table(details)
        assert.are.equal(2, #details.sub_item_table)
        assert.are.equal("Enable", details.sub_item_table[1].text)
        assert.are.equal("Show as first page", details.sub_item_table[2].text)
        details.sub_item_table[1].callback()
        assert.is_true(launcher_cfg.show_book_details)
        assert.is_true(details.sub_item_table[2].enabled_func())
        launcher_cfg.book_switcher_first = true
        details.sub_item_table[2].callback()
        assert.is_true(launcher_cfg.book_details_first)
        assert.is_false(launcher_cfg.book_switcher_first)

        local switcher
        for _i, item in ipairs(section.sub_item_table) do
            if item.text == "Book switcher" then switcher = item end
        end
        switcher.sub_item_table[2].callback()
        assert.is_true(launcher_cfg.book_switcher_first)
        assert.is_false(launcher_cfg.book_details_first)
        assert.are.equal(3, saves)
    end)
end)

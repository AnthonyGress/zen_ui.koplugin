describe("app launcher settings", function()
    local entry
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
                return { entries = { entry } }
            end,
            display_label = function(item) return item.label end,
            save = function() end,
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
end)

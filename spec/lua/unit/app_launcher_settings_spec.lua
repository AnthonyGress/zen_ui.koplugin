describe("app launcher settings", function()
    local entry
    local launcher_cfg
    local original_quick_settings
    local picker_options
    local saves
    local shown_options
    local suggested_preferred

    before_each(function()
        original_quick_settings = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")
        entry = {
            id = "al_1",
            type = "plugin",
            label = "Legacy",
            icon = "zen_ui",
            plugin = { key = "legacy", method = "open" },
        }
        shown_options = nil
        picker_options = nil
        suggested_preferred = nil
        saves = 0
        launcher_cfg = {
            entries = { entry },
            page_order = { "book_details", "book_switcher", "buttons" },
        }

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ffi/util", {
            template = function(text, value)
                return text:gsub("%%1", tostring(value))
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, callback) callback() end,
        })
        ZenSpec.replace("common/inline_icon_map", setmetatable({}, {
            __index = function(_self, key) return key end,
        }))
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item, icon)
                item.test_icon = icon
                return item
            end,
        })
        ZenSpec.replace("common/utils", {
            getIconDisplayName = function(name)
                return name == "zen_ui" and "ZenOS" or name
            end,
            getIconPickerList = function() return {} end,
            suggestIcon = function(_root, _label, _fallback, _strip_zen_prefix, preferred)
                suggested_preferred = preferred
                return preferred and "approved_zenfm" or "lightning"
            end,
        })
        ZenSpec.replace("modules/menu/app_launcher/model", {
            ensure = function()
                return launcher_cfg
            end,
            display_label = function(item) return item.label end,
            next_id = function() return "al_2" end,
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
        ZenSpec.replace("common/ui/zen_menu_picker", function(options)
            picker_options = options
        end)
        ZenSpec.unload("modules/settings/sections/app_launcher_settings")
    end)

    after_each(function()
        _G.__ZEN_UI_QUICK_SETTINGS = original_quick_settings
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

    it("offers page visibility options and arranges their launcher order", function()
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
        assert.are.equal(1, #details.sub_item_table)
        assert.are.equal("Enable", details.sub_item_table[1].text)
        details.sub_item_table[1].callback()
        assert.is_true(launcher_cfg.show_book_details)

        local switcher
        local order_item
        local order_index
        local open_menu_index
        for _i, item in ipairs(section.sub_item_table) do
            if item.text == "Book switcher" then switcher = item end
            if item.text:match("^Order") then
                order_item = item
                order_index = _i
            end
            if item.text == "Open menu to Launcher" then open_menu_index = _i end
        end
        assert.are.equal(2, #switcher.sub_item_table)
        assert.are.equal("Only show while reading", switcher.sub_item_table[2].text)
        assert.are.equal(order_index + 1, open_menu_index)
        assert.are.equal("sort", order_item.test_icon)

        order_item.callback()
        assert.are.equal("Order", shown_options.title)
        assert.are.same({ "Book information", "Book switcher", "Buttons" }, {
            shown_options.item_table[1].text,
            shown_options.item_table[2].text,
            shown_options.item_table[3].text,
        })
        shown_options.item_table[1], shown_options.item_table[3]
            = shown_options.item_table[3], shown_options.item_table[1]
        shown_options.callback()
        assert.are.same({ "buttons", "book_switcher", "book_details" },
            launcher_cfg.page_order)
        assert.are.equal(2, saves)
    end)

    it("stores an approved icon name instead of a control's plugin path", function()
        _G.__ZEN_UI_QUICK_SETTINGS = {
            getItems = function()
                return {{
                    id = "zenfm",
                    label = "ZenFM",
                    icon = "/plugins/zenfm.koplugin/icons/zenfm.svg",
                }}
            end,
        }
        local section = require(
            "modules/settings/sections/app_launcher_settings").build({
                config = { features = { app_launcher = true } },
                save_and_apply = function() end,
        })

        section.sub_item_table[2].callback()
        local add_control
        for _i, item in ipairs(shown_options.add_item_table) do
            if item.text == "Control" then add_control = item end
        end
        add_control.callback()
        picker_options.on_select(picker_options.items[1])

        local added = launcher_cfg.entries[2]
        assert.are.equal("/plugins/zenfm.koplugin/icons/zenfm.svg", suggested_preferred)
        assert.are.equal("approved_zenfm", added.icon)
    end)
end)

describe("Controls destination settings", function()
    local arrange_options
    local choose_folder
    local choose_tag
    local config
    local dispatcher_action
    local dispatcher_text
    local dispatcher_update
    local suggested_label

    before_each(function()
        arrange_options = nil
        choose_folder = nil
        choose_tag = nil
        dispatcher_action = nil
        dispatcher_text = "Nothing"
        dispatcher_update = nil
        suggested_label = nil
        config = {
            quick_settings = {
                button_order = {},
                show_buttons = {},
                custom_buttons = {},
                next_custom_id = 0,
            },
        }
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ffi/util", {
            template = function(text, value) return text:gsub("%%1", tostring(value)) end,
        })
        ZenSpec.replace("device", {
            hasFrontlight = function() return false end,
            hasGSensor = function() return false end,
        })
        ZenSpec.replace("ui/uimanager", { show = function() end })
        ZenSpec.replace("config/defaults", { quick_settings = {
            button_order = {}, show_buttons = {},
        } })
        ZenSpec.replace("common/inline_icon_map", setmetatable({}, {
            __index = function(_self, key) return key end,
        }))
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item) return item end,
        })
        ZenSpec.replace("modules/menu/app_launcher/native_menu", { scan = function() return {} end })
        ZenSpec.replace("modules/menu/app_launcher/plugin_scan", { scan = function() return {} end })
        ZenSpec.replace("common/dispatcher_menu", {
            wrap = function(_items, _caller, on_update)
                dispatcher_update = on_update
            end,
        })
        ZenSpec.replace("common/utils", {
            deepcopy = function(value) return value end,
            stripZenPrefix = function(text)
                return text:gsub("^ZenOS%s*[:%-]%s*", "")
            end,
            suggestIcon = function(_root, label, _fallback, _strip, preferred)
                suggested_label = label
                return preferred or "lightning"
            end,
            getIconPickerList = function() return {} end,
            getIconDisplayName = function(name) return name end,
        })
        ZenSpec.replace("common/bluetooth", { isAvailable = function() return false end })
        ZenSpec.replace("common/library_destination", {
            folderLabel = function(path) return path:match("([^/]+)$") or path end,
            chooseFolder = function(callback) choose_folder = callback end,
            chooseTag = function(callback) choose_tag = callback end,
        })
        ZenSpec.replace("common/ui/zen_arrange_list", {
            show = function(opts) arrange_options = opts end,
        })
        ZenSpec.replace("common/ui/zen_icon_picker", function() end)
        ZenSpec.replace("dispatcher", {
            addSubMenu = function(_self, _caller, _items, location, settings)
                if dispatcher_action then location[settings] = dispatcher_action end
            end,
            menuTextFunc = function() return dispatcher_text end,
        })
        ZenSpec.replace("apps/filemanager/filemanager", {})
        ZenSpec.replace("apps/reader/readerui", {})
        ZenSpec.unload("modules/settings/sections/menu_settings")
    end)

    it("adds multiple folders and one-tag destination buttons", function()
        local section = require("modules/settings/sections/menu_settings").build({
            config = config,
            plugin = {},
            save_and_apply = function() end,
        })
        section.sub_item_table[1].callback()
        local add_folder
        local add_tag
        for _i, item in ipairs(arrange_options.add_item_table) do
            if item.text == "Folder" then add_folder = item end
            if item.text == "Specific tag" then add_tag = item end
        end

        add_folder.callback()
        choose_folder("/library/Fiction")
        add_folder.callback()
        choose_folder("/library/Nonfiction")
        add_tag.callback()
        choose_tag("Science")

        assert.are.same({
            { id = "cb_1", type = "folder", folder = "/library/Fiction",
                label = "Fiction", label_auto = true, icon = "folder" },
            { id = "cb_2", type = "folder", folder = "/library/Nonfiction",
                label = "Nonfiction", label_auto = true, icon = "folder" },
            { id = "cb_3", type = "tag", tag = "Science",
                label = "Science", label_auto = true, icon = "tab_tags" },
        }, config.quick_settings.custom_buttons)
    end)

    it("strips the ZenOS prefix from a new action label and icon suggestion", function()
        dispatcher_action = { zen_ui_home = true }
        dispatcher_text = "ZenOS: Home"
        local section = require("modules/settings/sections/menu_settings").build({
            config = config,
            plugin = {},
            save_and_apply = function() end,
        })
        section.sub_item_table[1].callback()
        local add_action
        for _i, item in ipairs(arrange_options.add_item_table) do
            if item.text == "Action" then add_action = item; break end
        end
        local touch_menu = {
            item_table = {},
            item_table_stack = {},
            updateItems = function() end,
        }

        add_action.callback(touch_menu)
        dispatcher_update(touch_menu)

        assert.are.equal("Home", config.quick_settings.custom_buttons[1].label)
        assert.are.equal("Home", suggested_label)
    end)
end)

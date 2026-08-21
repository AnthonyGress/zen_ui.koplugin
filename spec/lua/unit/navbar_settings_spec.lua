describe("navbar settings", function()
    local arrange_options
    local config
    local original_quick_settings
    local saved
    local shown
    local suggested_label
    local suggested_preferred
    local touch_menu
    local picker_options
    local dispatcher_update
    local dispatcher_action
    local dispatcher_text
    local choose_folder
    local choose_tag

    local function find_arrange_item(id)
        for _i, item in ipairs(arrange_options.item_table) do
            if item.orig_item == id then return item end
        end
    end

    before_each(function()
        original_quick_settings = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")
        arrange_options = nil
        saved = 0
        shown = {}
        suggested_label = nil
        suggested_preferred = nil
        picker_options = nil
        dispatcher_update = nil
        dispatcher_action = nil
        dispatcher_text = "Nothing"
        choose_folder = nil
        choose_tag = nil
        touch_menu = {
            item_table = {},
            item_table_stack = {},
            backToSettingsRoot = function() end,
            backToUpperMenu = function(self)
                self.back_count = (self.back_count or 0) + 1
            end,
            updateItems = function(self)
                self.update_count = (self.update_count or 0) + 1
            end,
        }
        config = {
            navbar = {
                default_tab = "home",
                show_tabs = { books = true, home = true },
                tab_order = { "books", "home" },
                custom_tabs = {},
            },
        }

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ffi/util", {
            template = function(text, value)
                return text:gsub("%%1", tostring(value))
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function(_self, _delay, callback) callback() end,
            show = function(_self, widget) shown[#shown + 1] = widget end,
        })
        ZenSpec.replace("ui/widget/confirmbox", {
            new = function(_self, opts) return opts end,
        })
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_self, opts) return opts end,
        })
        ZenSpec.replace("ui/widget/pathchooser", {
            new = function(_self, opts) return opts end,
        })
        ZenSpec.replace("modules/settings/zen_settings_utils", {
            buildColorSubMenu = function(opts) return opts end,
            get_current_dir = function() return "/current" end,
            get_last_dir = function() return "/last" end,
        })
        ZenSpec.replace("common/utils", {
            copyDefaultCustomTabIcon = function() end,
            getIconPickerList = function() return {} end,
            getIconDisplayName = function(name)
                return name == "zen_ui" and "ZenOS" or name
            end,
            stripZenPrefix = function(text)
                return text:gsub("^ZenOS%s*[:%-]%s*", "")
            end,
            suggestIcon = function(_root, label, _fallback, _strip_zen_prefix, preferred)
                suggested_label = label
                suggested_preferred = preferred
                if preferred == "tab_folder" then return "tab_folder" end
                return preferred and "approved_zenfm" or "lightning"
            end,
        })
        ZenSpec.replace("common/paths", {
            getHomeDir = function() return "/home" end,
        })
        ZenSpec.replace("common/inline_icon_map", setmetatable({}, {
            __index = function(_self, key) return key end,
        }))
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item) return item end,
        })
        ZenSpec.replace("modules/menu/app_launcher/plugin_scan", {
            scan = function() return {} end,
        })
        ZenSpec.replace("modules/menu/app_launcher/native_menu", {
            scan = function(scope)
                assert.are.equal("filemanager", scope)
                return {
                    { id = "network", title = "Network", text = "Settings › Network" },
                }
            end,
        })
        ZenSpec.replace("common/dispatcher_menu", {
            wrap = function(_items, _caller, on_update)
                dispatcher_update = on_update
            end,
        })
        ZenSpec.replace("common/library_destination", {
            folderLabel = function(path) return path:match("([^/]+)$") or path end,
            chooseFolder = function(callback) choose_folder = callback end,
            chooseTag = function(callback) choose_tag = callback end,
        })
        ZenSpec.replace("dispatcher", {
            addSubMenu = function(_self, _caller, _items, location, settings)
                if dispatcher_action then location[settings] = dispatcher_action end
            end,
            menuTextFunc = function() return dispatcher_text end,
        })
        ZenSpec.replace("common/ui/zen_icon_picker", function() end)
        ZenSpec.replace("common/ui/zen_arrange_list", {
            show = function(opts) arrange_options = opts end,
        })
        ZenSpec.replace("common/ui/zen_menu_picker", function(opts)
            picker_options = opts
        end)
        ZenSpec.replace("common/plugin_root", "/plugin")
        ZenSpec.unload("modules/settings/sections/library_settings/navbar_settings")
    end)

    after_each(function()
        _G.__ZEN_UI_QUICK_SETTINGS = original_quick_settings
    end)

    local function build_navbar()
        return require("modules/settings/sections/library_settings/navbar_settings").build({
            config = config,
            plugin = { saveConfig = function() saved = saved + 1 end },
            save_and_apply = function() end,
            settings_apply = { refresh_navbar_on_menu_close = function() end },
        })
    end

    it("keeps the default when its tab is hidden", function()
        local navbar = build_navbar()
        navbar.sub_item_table[1].callback()

        find_arrange_item("home").callback(touch_menu)

        assert.is_false(config.navbar.show_tabs.home)
        assert.are.equal("home", config.navbar.default_tab)
        assert.are.equal(1, saved)
        assert.are.equal(0, #shown)
    end)

    it("keeps the default when its built-in tab is deleted from the navbar", function()
        local navbar = build_navbar()
        navbar.sub_item_table[1].callback()
        local home_item = find_arrange_item("home")
        local home_settings = home_item.sub_item_table_func()

        home_settings[#home_settings].callback(touch_menu)
        shown[1].ok_callback()

        assert.is_false(config.navbar.show_tabs.home)
        assert.are.same({ "books" }, config.navbar.tab_order)
        assert.are.equal("home", config.navbar.default_tab)
        assert.are.equal(1, touch_menu.back_count)
        assert.are.equal(1, saved)
    end)

    it("creates a library-scoped KOReader menu tab", function()
        local navbar = build_navbar()
        navbar.sub_item_table[1].callback()
        local add_item
        for _i, item in ipairs(arrange_options.add_item_table) do
            if item.text == "KOReader menu" then add_item = item end
        end

        add_item.callback(touch_menu)
        assert.are.equal("Choose KOReader menu", picker_options.title)
        picker_options.on_select(picker_options.items[1])

        local custom = config.navbar.custom_tabs[1]
        assert.are.equal("koreader_menu", custom.type)
        assert.are.same({ id = "network", title = "Network" }, custom.koreader_menu)
        assert.are.equal("Network", custom.label)
        assert.are.equal("lightning", custom.icon)
        assert.is_true(config.navbar.show_tabs[custom.id])
        assert.are.equal(custom.id, config.navbar.tab_order[#config.navbar.tab_order])
        assert.are.equal(1, saved)
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
        local navbar = build_navbar()
        navbar.sub_item_table[1].callback()
        local add_control
        for _i, item in ipairs(arrange_options.add_item_table) do
            if item.text == "Control" then add_control = item end
        end

        add_control.callback(touch_menu)
        picker_options.on_select(picker_options.items[1])

        local added = config.navbar.custom_tabs[1]
        assert.are.equal("/plugins/zenfm.koplugin/icons/zenfm.svg", suggested_preferred)
        assert.are.equal("approved_zenfm", added.icon)
    end)

    it("offers a built-in Folder tab with a configurable path", function()
        local navbar = build_navbar()
        navbar.sub_item_table[1].callback()
        arrange_options.add_item_table[1].callback(touch_menu)

        local folder_picker_item
        for _i, item in ipairs(picker_options.items) do
            if item.id == "folder" then folder_picker_item = item; break end
        end
        assert.is_table(folder_picker_item)
        picker_options.on_select(folder_picker_item)

        navbar = build_navbar()
        navbar.sub_item_table[1].callback()

        local folder_settings = find_arrange_item("folder").sub_item_table_func()
        folder_settings[1].callback(touch_menu)
        shown[1].onConfirm("/home/Fiction")

        assert.are.equal("/home/Fiction", config.navbar.folder_path)
        assert.are.equal(1, touch_menu.update_count)
        assert.are.equal(2, saved)
    end)

    it("suggests tab_folder for an Open folder action tab", function()
        dispatcher_action = { zen_ui_show_folder = "/home/Fiction" }
        dispatcher_text = "ZenOS: Open folder"
        local navbar = build_navbar()
        navbar.sub_item_table[1].callback()
        local add_action
        for _i, item in ipairs(arrange_options.add_item_table) do
            if item.text == "Action" then add_action = item end
        end

        add_action.callback(touch_menu)
        dispatcher_update(touch_menu)

        local added = config.navbar.custom_tabs[1]
        assert.are.equal("Open folder", added.label)
        assert.are.equal("Open folder", suggested_label)
        assert.are.equal("tab_folder", suggested_preferred)
        assert.are.equal("tab_folder", added.icon)
        assert.are.same(dispatcher_action, added.action)
    end)

    it("adds multiple folder tabs and a specific-tag tab", function()
        local navbar = build_navbar()
        navbar.sub_item_table[1].callback()
        local add_folder
        local add_tag
        for _i, item in ipairs(arrange_options.add_item_table) do
            if item.text == "Folder" then add_folder = item end
            if item.text == "Specific tag" then add_tag = item end
        end

        add_folder.callback(touch_menu)
        choose_folder("/home/Fiction")
        add_folder.callback(touch_menu)
        choose_folder("/home/Nonfiction")
        add_tag.callback(touch_menu)
        choose_tag("Science")

        assert.are.same({
            {
                id = "ct_1", type = "folder", folder = "/home/Fiction",
                label = "Fiction", label_auto = true, icon = "tab_folder",
            },
            {
                id = "ct_2", type = "folder", folder = "/home/Nonfiction",
                label = "Nonfiction", label_auto = true, icon = "tab_folder",
            },
            {
                id = "ct_3", type = "tag", tag = "Science",
                label = "Science", label_auto = true, icon = "tab_tags",
            },
        }, config.navbar.custom_tabs)
        assert.is_true(config.navbar.show_tabs.ct_1)
        assert.is_true(config.navbar.show_tabs.ct_2)
        assert.is_true(config.navbar.show_tabs.ct_3)
    end)

    it("shows the ZenOS icon label without rewriting a legacy custom-tab ID", function()
        config.navbar.custom_tabs = {
            { id = "ct_1", type = "action", label = "Legacy", icon = "zen_ui", action = {} },
        }
        config.navbar.show_tabs.ct_1 = true
        config.navbar.tab_order = { "books", "home", "ct_1" }

        local navbar = build_navbar()
        navbar.sub_item_table[1].callback()
        local sub_items = find_arrange_item("ct_1").sub_item_table_func()
        local icon_label
        for _i, item in ipairs(sub_items) do
            if item.text_func and item.text_func():sub(1, 6) == "Icon: " then
                icon_label = item.text_func()
                break
            end
        end

        assert.are.equal("Icon: ZenOS", icon_label)
        assert.are.equal("zen_ui", config.navbar.custom_tabs[1].icon)
    end)
end)

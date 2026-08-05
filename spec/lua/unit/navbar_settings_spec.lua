describe("navbar settings", function()
    local arrange_options
    local config
    local saved
    local shown
    local touch_menu

    local function find_arrange_item(id)
        for _i, item in ipairs(arrange_options.item_table) do
            if item.orig_item == id then return item end
        end
    end

    before_each(function()
        arrange_options = nil
        saved = 0
        shown = {}
        touch_menu = {
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
        ZenSpec.replace("modules/settings/zen_settings_utils", {
            buildColorSubMenu = function(opts) return opts end,
            get_current_dir = function() return "/current" end,
            get_last_dir = function() return "/last" end,
        })
        ZenSpec.replace("common/utils", {
            copyDefaultCustomTabIcon = function() end,
            getIconPickerList = function() return {} end,
            suggestIcon = function() return "lightning" end,
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
        ZenSpec.replace("common/dispatcher_menu", { wrap = function() end })
        ZenSpec.replace("dispatcher", {
            addSubMenu = function() end,
            menuTextFunc = function() return "Nothing" end,
        })
        ZenSpec.replace("common/ui/zen_icon_picker", function() end)
        ZenSpec.replace("common/ui/zen_arrange_list", {
            show = function(opts) arrange_options = opts end,
        })
        ZenSpec.replace("common/plugin_root", "/plugin")
        ZenSpec.unload("modules/settings/sections/library_settings/navbar_settings")
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
end)

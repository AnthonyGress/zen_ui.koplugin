describe("TouchMenu footer", function()
    local original_defaults
    local original_modules
    local original_plugin
    local plugin
    local settings_plugin
    local TouchMenu

    local module_names = {
        "common/inline_icon_map",
        "common/plugin_root",
        "device",
        "modules/menu/patches/touch_menu_footer",
        "modules/settings/zen_settings_page",
        "ui/geometry",
        "ui/gesturerange",
        "ui/uimanager",
        "ui/widget/button",
        "ui/widget/container/inputcontainer",
        "ui/widget/horizontalgroup",
        "ui/widget/horizontalspan",
        "ui/widget/iconwidget",
        "ui/widget/touchmenu",
    }

    local function widget_class()
        local class = {}
        function class:extend(child)
            child = child or {}
            return setmetatable(child, { __index = self })
        end
        function class:new(values)
            values = setmetatable(values or {}, { __index = self })
            values.ges_events = values.ges_events or {}
            if values.init then values:init() end
            return values
        end
        return class
    end

    local function new_menu()
        return setmetatable({
            cur_tab = 1,
            tab_item_table = {
                { id = "quicksettings" },
                { id = "history" },
            },
        }, { __index = TouchMenu })
    end

    before_each(function()
        original_defaults = rawget(_G, "G_defaults")
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        original_modules = {}
        for _i, name in ipairs(module_names) do
            original_modules[name] = package.loaded[name] or false
        end

        settings_plugin = nil
        plugin = {
            config = {
                features = { quick_settings = true, lockdown_mode = false },
                lockdown = { disable_settings_panel = false },
                quick_settings = { settings_button_in_footer = true },
            },
        }
        _G.__ZEN_UI_PLUGIN = plugin
        _G.G_defaults = { readSetting = function() return 40 end }

        local Widget = widget_class()
        TouchMenu = {
            init = function(self)
                self.page_info = { id = "pager" }
                self.footer = { {}, {}, {} }
            end,
            switchMenuTab = function(self, index) self.cur_tab = index end,
        }
        ZenSpec.replace("common/inline_icon_map", { settings = "gear" })
        ZenSpec.replace("common/plugin_root", "/plugin")
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_self, size) return size end },
        })
        ZenSpec.replace("modules/settings/zen_settings_page", {
            show = function(value) settings_plugin = value end,
        })
        ZenSpec.replace("ui/geometry", Widget)
        ZenSpec.replace("ui/gesturerange", Widget)
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, callback) callback() end,
        })
        ZenSpec.replace("ui/widget/button", Widget)
        ZenSpec.replace("ui/widget/container/inputcontainer", Widget)
        ZenSpec.replace("ui/widget/horizontalgroup", Widget)
        ZenSpec.replace("ui/widget/horizontalspan", Widget)
        ZenSpec.replace("ui/widget/iconwidget", Widget)
        ZenSpec.replace("ui/widget/touchmenu", TouchMenu)
        ZenSpec.unload("modules/menu/patches/touch_menu_footer")
        require("modules/menu/patches/touch_menu_footer")()
    end)

    after_each(function()
        _G.G_defaults = original_defaults
        _G.__ZEN_UI_PLUGIN = original_plugin
        for _i, name in ipairs(module_names) do
            package.loaded[name] = original_modules[name] or nil
        end
    end)

    it("uses the Controls pager slot only while the setting is enabled", function()
        local menu = new_menu()
        menu.closed = false
        menu.closeMenu = function(self) self.closed = true end
        menu.backToUpperMenu = function() end
        menu:init()

        local gear = menu._zen_settings_footer_button
        assert.are.equal("gear", gear.text)
        assert.are.equal(16, gear.text_font_size)
        assert.are.equal(56, gear.width)
        assert.are.equal(7, menu._zen_settings_footer_widget[1].width)
        assert.is_true(menu.footer[1][1] == menu._zen_settings_footer_widget)
        assert.is_true(menu.footer[3][1] == menu.page_info)

        menu:switchMenuTab(2)
        assert.is_true(menu.footer[1][1] == menu._zen_empty_footer_widget)
        menu:switchMenuTab(1)
        assert.is_true(menu.footer[1][1] == menu._zen_settings_footer_widget)

        gear.callback()
        assert.is_true(menu.closed)
        assert.is_true(settings_plugin == plugin)

        plugin.config.quick_settings.settings_button_in_footer = false
        local disabled_menu = new_menu()
        disabled_menu:init()
        assert.is_true(disabled_menu.footer[1][1] == disabled_menu._zen_empty_footer_widget)

        plugin.config.quick_settings.settings_button_in_footer = true
        plugin.config.features.lockdown_mode = true
        plugin.config.lockdown.disable_settings_panel = true
        local locked_menu = new_menu()
        locked_menu:init()
        assert.is_true(locked_menu.footer[1][1] == locked_menu._zen_empty_footer_widget)
    end)
end)

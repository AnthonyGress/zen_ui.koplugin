describe("quick settings Tailscale", function()
    local original_modules
    local original_plugin
    local original_quick_settings
    local tailscale

    local module_names = {
        "ffi/blitbuffer",
        "ffi/util",
        "ui/widget/container/centercontainer",
        "device",
        "ui/event",
        "ui/font",
        "common/ui/zen_solid_circle",
        "ui/geometry",
        "ui/widget/horizontalgroup",
        "ui/widget/horizontalspan",
        "ui/widget/iconwidget",
        "ui/network/manager",
        "ui/widget/confirmbox",
        "ui/widget/textwidget",
        "ui/uimanager",
        "modules/filebrowser/patches/library_font",
        "ui/widget/verticalgroup",
        "ui/widget/verticalspan",
        "common/utils",
        "common/shutdown",
        "common/restart",
        "common/shared_state",
        "common/bluetooth",
        "modules/menu/patches/brightness_slider",
        "modules/menu/patches/warmth_slider",
        "gettext",
        "dispatcher",
        "common/dispatch_action",
        "modules/menu/app_launcher/plugin_scan",
        "common/plugin_root",
        "modules/menu/patches/touch_menu_panel",
        "ui/widget/touchmenu",
        "apps/filemanager/filemanagermenu",
        "apps/reader/modules/readermenu",
        "apps/filemanager/filemanager",
        "apps/reader/readerui",
        "pluginloader",
    }

    before_each(function()
        original_modules = {}
        for _i, name in ipairs(module_names) do
            original_modules[name] = package.loaded[name]
        end
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        original_quick_settings = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")

        local no_op = {}
        ZenSpec.replace("ffi/blitbuffer", no_op)
        ZenSpec.replace("ffi/util", { template = function(text) return text end, strcoll = function(a, b) return a < b end })
        ZenSpec.replace("ui/widget/container/centercontainer", no_op)
        ZenSpec.replace("device", { screen = {} })
        ZenSpec.replace("ui/event", { new = function(_self, name) return { name = name } end })
        ZenSpec.replace("ui/font", no_op)
        ZenSpec.replace("common/ui/zen_solid_circle", no_op)
        ZenSpec.replace("ui/geometry", no_op)
        ZenSpec.replace("ui/widget/horizontalgroup", no_op)
        ZenSpec.replace("ui/widget/horizontalspan", no_op)
        ZenSpec.replace("ui/widget/iconwidget", no_op)
        ZenSpec.replace("ui/network/manager", no_op)
        ZenSpec.replace("ui/widget/confirmbox", no_op)
        ZenSpec.replace("ui/widget/textwidget", no_op)
        ZenSpec.replace("ui/uimanager", no_op)
        ZenSpec.replace("modules/filebrowser/patches/library_font", no_op)
        ZenSpec.replace("ui/widget/verticalgroup", no_op)
        ZenSpec.replace("ui/widget/verticalspan", no_op)
        ZenSpec.replace("common/utils", {
            deepcopy = function(value)
                if type(value) ~= "table" then return value end
                local copy = {}
                for key, item in pairs(value) do copy[key] = item end
                return copy
            end,
            resolveLocalIcon = function(icons_dir, name)
                return icons_dir .. name .. ".svg"
            end,
        })
        ZenSpec.replace("common/shutdown", no_op)
        ZenSpec.replace("common/restart", no_op)
        ZenSpec.replace("common/shared_state", { get = function() end })
        ZenSpec.replace("common/bluetooth", no_op)
        ZenSpec.replace("modules/menu/patches/brightness_slider", function() end)
        ZenSpec.replace("modules/menu/patches/warmth_slider", function() end)
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("dispatcher", no_op)
        ZenSpec.replace("common/dispatch_action", no_op)
        ZenSpec.replace("modules/menu/app_launcher/plugin_scan", no_op)
        ZenSpec.replace("common/plugin_root", "/tmp/zen-ui")
        ZenSpec.replace("modules/menu/patches/touch_menu_panel", { install = function() end })
        ZenSpec.replace("ui/widget/touchmenu", {
            init = function() end,
            switchMenuTab = function() end,
        })
        ZenSpec.replace("apps/filemanager/filemanagermenu", { setUpdateItemTable = function() end })
        ZenSpec.replace("apps/reader/modules/readermenu", { setUpdateItemTable = function() end })
        ZenSpec.replace("apps/filemanager/filemanager", {})
        ZenSpec.replace("apps/reader/readerui", {})

        tailscale = {
            running = false,
            toggle_calls = 0,
            isRunning = function(self) return self.running end,
            onToggleTailscale = function(self, callback)
                self.toggle_calls = self.toggle_calls + 1
                self.running = not self.running
                callback()
            end,
        }
        ZenSpec.replace("pluginloader", { loaded_plugins = { tailscale = tailscale } })

        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { quick_settings = true },
                quick_settings = {
                    layout_version = 2,
                    button_order = { "tailscale" },
                    show_buttons = { tailscale = true },
                    custom_buttons = {},
                    next_custom_id = 0,
                },
            },
        }
        ZenSpec.unload("modules/menu/patches/quick_settings")
        require("modules/menu/patches/quick_settings")()
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do
            package.loaded[name] = original_modules[name]
        end
        ZenSpec.unload("modules/menu/patches/quick_settings")
        _G.__ZEN_UI_PLUGIN = original_plugin
        _G.__ZEN_UI_QUICK_SETTINGS = original_quick_settings
    end)

    it("uses the plugin's toggle and running state", function()
        local updates = 0
        local touch_menu = {
            item_table = { panel = true },
            updateItems = function() updates = updates + 1 end,
        }

        assert.is_true(_G.__ZEN_UI_QUICK_SETTINGS.has("tailscale"))
        assert.is_false(_G.__ZEN_UI_QUICK_SETTINGS.isActive("tailscale"))
        assert.is_true(_G.__ZEN_UI_QUICK_SETTINGS.activate("tailscale", touch_menu))
        assert.is_equal(1, tailscale.toggle_calls)
        assert.is_true(_G.__ZEN_UI_QUICK_SETTINGS.isActive("tailscale"))
        assert.is_equal(1, updates)
    end)
end)

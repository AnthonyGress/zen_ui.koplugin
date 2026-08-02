describe("quick settings Wi-Fi", function()
    local original_modules
    local original_plugin
    local original_quick_settings
    local NetworkMgr
    local Device
    local UIManager

    local module_names = {
        "ffi/blitbuffer",
        "ffi/util",
        "ui/widget/container/centercontainer",
        "device",
        "ui/event",
        "ui/font",
        "ui/widget/container/framecontainer",
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
    }

    local function deepcopy(value)
        if type(value) ~= "table" then return value end
        local copy = {}
        for key, item in pairs(value) do
            copy[key] = deepcopy(item)
        end
        return copy
    end

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
        ZenSpec.replace("ui/font", no_op)
        ZenSpec.replace("ui/widget/container/framecontainer", no_op)
        ZenSpec.replace("ui/geometry", no_op)
        ZenSpec.replace("ui/widget/horizontalgroup", no_op)
        ZenSpec.replace("ui/widget/horizontalspan", no_op)
        ZenSpec.replace("ui/widget/iconwidget", no_op)
        ZenSpec.replace("ui/widget/confirmbox", no_op)
        ZenSpec.replace("ui/widget/textwidget", no_op)
        ZenSpec.replace("modules/filebrowser/patches/library_font", no_op)
        ZenSpec.replace("ui/widget/verticalgroup", no_op)
        ZenSpec.replace("ui/widget/verticalspan", no_op)
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
        ZenSpec.replace("common/utils", {
            deepcopy = deepcopy,
            resolveLocalIcon = function() end,
        })
        ZenSpec.replace("ui/event", { new = function(_, name) return { name = name } end })
        ZenSpec.replace("modules/menu/patches/touch_menu_panel", { install = function() end })
        ZenSpec.replace("ui/widget/touchmenu", {
            init = function() end,
            switchMenuTab = function() end,
            updateItems = function() end,
            onTapCloseAllMenus = function() end,
            onHoldCloseAllMenus = function() end,
            onSetRotationMode = function() end,
        })
        ZenSpec.replace("apps/filemanager/filemanagermenu", { setUpdateItemTable = function() end })
        ZenSpec.replace("apps/reader/modules/readermenu", { setUpdateItemTable = function() end })
        ZenSpec.replace("apps/filemanager/filemanager", {})
        ZenSpec.replace("apps/reader/readerui", {})

        Device = {
            hasWifiRestore = function() return true end,
            screen = {},
        }
        ZenSpec.replace("device", Device)

        UIManager = {
            events = {},
            scheduled = {},
            broadcastEvent = function(self, event) self.events[#self.events + 1] = event end,
            scheduleIn = function(self, delay, callback)
                self.scheduled[#self.scheduled + 1] = { delay = delay, callback = callback }
            end,
        }
        ZenSpec.replace("ui/uimanager", UIManager)

        NetworkMgr = {
            wifi_on = false,
            restore_calls = 0,
            connectivity_calls = 0,
            stock_calls = 0,
            isWifiOn = function(self) return self.wifi_on end,
            restoreWifiAsync = function(self) self.restore_calls = self.restore_calls + 1 end,
            scheduleConnectivityCheck = function(self, callback)
                self.connectivity_calls = self.connectivity_calls + 1
                self.connectivity_callback = callback
            end,
            getWifiMenuTable = function(self)
                return {
                    callback = function(touch_menu)
                        self.stock_calls = self.stock_calls + 1
                        self.stock_touch_menu = touch_menu
                    end,
                }
            end,
        }
        ZenSpec.replace("ui/network/manager", NetworkMgr)

        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { quick_settings = true },
                quick_settings = {
                    layout_version = 2,
                    button_order = { "wifi" },
                    show_buttons = { wifi = true },
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

    it("starts supported Wi-Fi restores in the background", function()
        local updates = 0
        local touch_menu = {
            item_table = { panel = true },
            updateItems = function() updates = updates + 1 end,
        }

        assert.is_true(_G.__ZEN_UI_QUICK_SETTINGS.activate("wifi", touch_menu))

        assert.are.equal(1, NetworkMgr.restore_calls)
        assert.are.equal(1, NetworkMgr.connectivity_calls)
        assert.are.equal(0, NetworkMgr.stock_calls)
        assert.is_true(NetworkMgr.pending_connection)
        assert.are.equal("NetworkConnecting", UIManager.events[1].name)
        assert.are.equal(1, #UIManager.scheduled)

        NetworkMgr.connectivity_callback()
        assert.are.equal(1, updates)
    end)

    it("keeps KOReader's normal Wi-Fi action as the fallback", function()
        Device.hasWifiRestore = function() return false end
        local touch_menu = { item_table = { panel = true }, updateItems = function() end }

        assert.is_true(_G.__ZEN_UI_QUICK_SETTINGS.activate("wifi", touch_menu))

        assert.are.equal(0, NetworkMgr.restore_calls)
        assert.are.equal(1, NetworkMgr.stock_calls)
        assert.are.equal(touch_menu, NetworkMgr.stock_touch_menu)
    end)

    it("does not restart an active Wi-Fi connection attempt", function()
        NetworkMgr.pending_connection = true

        assert.is_true(_G.__ZEN_UI_QUICK_SETTINGS.activate("wifi", {}))

        assert.are.equal(0, NetworkMgr.restore_calls)
        assert.are.equal(0, NetworkMgr.stock_calls)
    end)
end)

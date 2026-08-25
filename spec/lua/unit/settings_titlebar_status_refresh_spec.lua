describe("settings title bar status refresh", function()
    local SettingsTitleBar
    local saved_modules
    local scheduled
    local unscheduled

    local dependency_names = {
        "ffi/blitbuffer",
        "ui/widget/button",
        "ui/widget/container/centercontainer",
        "device",
        "ui/widget/container/framecontainer",
        "ui/geometry",
        "ui/gesturerange",
        "ui/widget/horizontalgroup",
        "ui/widget/horizontalspan",
        "ui/widget/iconbutton",
        "ui/widget/container/inputcontainer",
        "ui/widget/inputtext",
        "ui/widget/container/leftcontainer",
        "ui/widget/linewidget",
        "ui/widget/overlapgroup",
        "ui/size",
        "ui/widget/textwidget",
        "ui/uimanager",
        "ui/widget/verticalgroup",
        "ui/widget/verticalspan",
        "common/clock_timer",
        "common/shared_state",
        "common/ui/icon_menu_item",
        "common/ui/zen_icon_button",
        "common/ui/zen_solid_circle",
        "common/ui/zen_settings_titlebar",
        "common/ui/zen_title_style",
        "common/widget_resources",
        "common/utils",
        "gettext",
        "apps/filemanager/filemanager",
    }

    before_each(function()
        saved_modules = {}
        scheduled = {}
        unscheduled = {}
        for _i, name in ipairs(dependency_names) do
            saved_modules[name] = package.loaded[name] or false
        end

        for _i, name in ipairs(dependency_names) do
            ZenSpec.replace(name, {})
        end
        ZenSpec.replace("ui/widget/container/inputcontainer", {
            extend = function(_self, prototype)
                prototype.__index = prototype
                return prototype
            end,
        })
        ZenSpec.replace("device", { screen = {} })
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function(_self, delay, callback)
                scheduled[#scheduled + 1] = { delay = delay, callback = callback }
            end,
            unschedule = function(_self, callback)
                unscheduled[#unscheduled + 1] = callback
            end,
        })
        ZenSpec.replace("common/clock_timer", { unbind = function() end })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.unload("apps/filemanager/filemanager")
        ZenSpec.unload("common/ui/zen_settings_titlebar")
        SettingsTitleBar = require("common/ui/zen_settings_titlebar")
    end)

    after_each(function()
        for _i, name in ipairs(dependency_names) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    local function make_title_bar()
        local refreshes = 0
        local owner = {}
        local title_bar = { show_parent = owner }
        owner._zen_status_title_bar = title_bar
        owner._zen_status_refresh = function()
            refreshes = refreshes + 1
        end
        package.loaded["ui/uimanager"]._window_stack = { { widget = owner } }
        return title_bar, function() return refreshes end, owner
    end

    it("refreshes immediately when the network connects or disconnects", function()
        local title_bar, refreshes = make_title_bar()

        SettingsTitleBar.onNetworkConnected(title_bar)
        SettingsTitleBar.onNetworkDisconnected(title_bar)

        assert.are.equal(2, refreshes())
    end)

    it("debounces charging changes and cancels the timer when cleared", function()
        local title_bar, refreshes, owner = make_title_bar()

        SettingsTitleBar.onCharging(title_bar)
        local first_callback = scheduled[1].callback
        SettingsTitleBar.onNotCharging(title_bar)

        assert.are.equal(2, #scheduled)
        assert.are.equal(1.5, scheduled[2].delay)
        assert.are.equal(first_callback, unscheduled[1])

        scheduled[2].callback()
        assert.are.equal(1, refreshes())

        SettingsTitleBar.onCharging(title_bar)
        local pending_callback = scheduled[3].callback
        SettingsTitleBar.clearStatusRefresh(title_bar)

        assert.are.equal(pending_callback, unscheduled[2])
        assert.is_nil(title_bar._zen_status_charging_refresh_timer)
        assert.is_nil(owner._zen_status_refresh)
    end)

    it("leaves device events to the active file manager dispatcher", function()
        local title_bar, refreshes = make_title_bar()
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = { _updateStatusBar = function() end },
        })

        SettingsTitleBar.onNetworkConnected(title_bar)
        SettingsTitleBar.onCharging(title_bar)

        assert.are.equal(0, refreshes())
        assert.are.equal(0, #scheduled)
    end)
end)

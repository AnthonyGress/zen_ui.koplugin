describe("Zen arrange list settings resume", function()
    local ArrangeList
    local shown_widgets
    local saved_modules
    local ui_manager

    local dependency_names = {
        "ffi/blitbuffer",
        "ui/bidi",
        "device",
        "ui/event",
        "ui/widget/container/bottomcontainer",
        "ui/widget/container/centercontainer",
        "ui/widget/checkmark",
        "ui/widget/container/framecontainer",
        "ui/geometry",
        "ui/gesturerange",
        "ui/widget/horizontalgroup",
        "ui/widget/horizontalspan",
        "ui/widget/iconwidget",
        "ui/widget/container/inputcontainer",
        "ui/widget/container/leftcontainer",
        "ui/widget/linewidget",
        "ui/widget/container/overlapgroup",
        "ui/widget/radiomark",
        "ui/widget/container/rightcontainer",
        "ui/size",
        "ui/widget/sortwidget",
        "ui/widget/textwidget",
        "ui/uimanager",
        "ui/widget/verticalgroup",
        "gettext",
        "common/ui/icon_menu_item",
        "common/ui/zen_settings_titlebar",
        "modules/global/patches/menu_top_swipe",
        "common/ui/zen_toggle",
        "common/ui/zen_pager",
        "common/utils",
        "common/arrange_state",
        "common/dispatcher_menu",
        "modules/settings/zen_settings_page",
    }

    local function class()
        local result = {}
        function result:extend(prototype)
            prototype = prototype or {}
            setmetatable(prototype, { __index = self })
            prototype.__index = prototype
            return prototype
        end
        return result
    end

    before_each(function()
        saved_modules = {}
        shown_widgets = {}
        for _i, name in ipairs(dependency_names) do
            saved_modules[name] = package.loaded[name] or false
        end

        local UIManager = {
            _refresh_func_stack = {},
            close = function(_self, widget)
                widget.closed = true
            end,
            nextTick = function(_self, callback)
                _self.next_tick_count = (_self.next_tick_count or 0) + 1
                callback()
            end,
            scheduleIn = function() end,
            setDirty = function() end,
            show = function(_self, widget)
                shown_widgets[#shown_widgets + 1] = widget
            end,
            unschedule = function() end,
        }
        ui_manager = UIManager
        local SortWidget = {}
        function SortWidget:new(instance)
            instance = instance or {}
            instance.ges_events = {}
            instance.key_events = {}
            instance.dimen = { x = 0, y = 0, w = 100, h = 100 }
            instance.pages = 1
            instance.selected = { x = 1, y = 1 }
            instance.show_page = 1
            instance._populateItems = function() end
            instance.onClose = function(widget)
                UIManager:close(widget)
                return true
            end
            return instance
        end

        ZenSpec.replace("ffi/blitbuffer", {})
        ZenSpec.replace("ui/bidi", {})
        ZenSpec.replace("device", {
            hasDPad = function() return false end,
            isTouchDevice = function() return false end,
        })
        ZenSpec.replace("ui/event", { new = function(_self, event) return event end })
        ZenSpec.replace("ui/widget/container/bottomcontainer", {})
        ZenSpec.replace("ui/widget/container/centercontainer", {})
        ZenSpec.replace("ui/widget/checkmark", {})
        ZenSpec.replace("ui/widget/container/framecontainer", {})
        ZenSpec.replace("ui/geometry", { new = function(_self, dimen) return dimen end })
        ZenSpec.replace("ui/gesturerange", { new = function(_self, opts) return opts end })
        ZenSpec.replace("ui/widget/horizontalgroup", {})
        ZenSpec.replace("ui/widget/horizontalspan", {})
        ZenSpec.replace("ui/widget/iconwidget", {})
        ZenSpec.replace("ui/widget/container/inputcontainer", class())
        ZenSpec.replace("ui/widget/container/leftcontainer", {})
        ZenSpec.replace("ui/widget/linewidget", {})
        ZenSpec.replace("ui/widget/container/overlapgroup", {})
        ZenSpec.replace("ui/widget/radiomark", {})
        ZenSpec.replace("ui/widget/container/rightcontainer", {})
        ZenSpec.replace("ui/size", { padding = { large = 1 } })
        ZenSpec.replace("ui/widget/sortwidget", SortWidget)
        ZenSpec.replace("ui/widget/textwidget", {})
        ZenSpec.replace("ui/uimanager", UIManager)
        ZenSpec.replace("ui/widget/verticalgroup", {})
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("common/ui/icon_menu_item", {})
        ZenSpec.replace("common/ui/zen_settings_titlebar", {})
        ZenSpec.replace("modules/global/patches/menu_top_swipe", {
            getTapHeight = function() return 0 end,
        })
        ZenSpec.replace("common/ui/zen_toggle", {})
        ZenSpec.replace("common/ui/zen_pager", {})
        ZenSpec.replace("common/utils", {})
        ZenSpec.replace("common/arrange_state", {
            SUBMENU_CARET = " >",
            stripSubmenuCaret = function(text) return text end,
            stripValueSuffix = function(text) return text end,
        })
        ZenSpec.replace("common/dispatcher_menu", { flush = function() end })
        ZenSpec.replace("modules/settings/zen_settings_page", {
            claimArrangeRoute = function()
                return {
                    opener = { text = "Arrange" },
                    path = { "First", "Second" },
                }
            end,
        })
        _G.__ZEN_UI_SETTINGS_PAGE = {}
        ZenSpec.unload("common/ui/zen_arrange_list")
        ArrangeList = require("common/ui/zen_arrange_list")
    end)

    after_each(function()
        _G.__ZEN_UI_SETTINGS_PAGE = nil
        ZenSpec.unload("common/ui/zen_arrange_list")
        for _i, name in ipairs(dependency_names) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("renders only the resumed leaf and reveals parent menus on Back", function()
        ArrangeList.show{
            allow_arrange = false,
            item_table = {
                {
                    text = "First",
                    sub_item_table = {
                        {
                            text = "Second",
                            sub_item_table = {{ text = "Destination" }},
                        },
                    },
                },
            },
        }

        assert.are.equal(3, #shown_widgets)
        assert.is_true(shown_widgets[1].invisible)
        assert.is_true(shown_widgets[2].invisible)
        assert.are.equal("Second", shown_widgets[3].title)
        assert.is_false(shown_widgets[3].invisible)
        assert.is_nil(ui_manager.next_tick_count)
        assert.are.same({ "First", "Second" }, shown_widgets[3]._zen_settings_resume.path)

        shown_widgets[3]:onClose()
        assert.are.equal("First", shown_widgets[2].title)
        assert.is_false(shown_widgets[2].invisible)
        assert.is_true(shown_widgets[1].invisible)

        shown_widgets[2]:onClose()
        assert.are.equal(3, #shown_widgets)
        assert.is_false(shown_widgets[1].invisible)
    end)

    it("inherits an explicit settings route for a nested arrange page", function()
        local inherited = {
            opener = { text = "Widgets", occurrence = 1 },
            path = { "strip", "Controls" },
        }

        ArrangeList.show{
            settings_resume = inherited,
            item_table = {{ text = "Recent" }},
        }

        assert.are.equal(inherited, shown_widgets[1]._zen_settings_resume)
        assert.are.equal(inherited,
            shown_widgets[1]._zen_menu_proxy._zen_settings_resume)
    end)

    it("restores a callback-backed settings leaf", function()
        local callback_parent
        require("modules/settings/zen_settings_page").claimArrangeRoute = function()
            return {
                opener = { text = "Arrange" },
                path = { "First", "Tabs" },
            }
        end

        ArrangeList.show{
            allow_arrange = false,
            item_table = {
                {
                    text = "First",
                    sub_item_table = {
                        {
                            text = "Tabs",
                            _zen_settings_submenu = true,
                            keep_menu_open = true,
                            callback = function(parent)
                                callback_parent = parent
                                ui_manager:show({ title = "Tabs" })
                            end,
                        },
                    },
                },
            },
        }

        assert.are.equal(3, #shown_widgets)
        assert.are.equal("Tabs", shown_widgets[3].title)
        assert.is_false(shown_widgets[2].invisible)
        assert.are.same({ "First" }, callback_parent._zen_settings_resume.path)
    end)

    it("does not reveal deferred parents while closing the whole arrange stack", function()
        local settings_parent = { _deferred_arrange_parent = true }
        require("modules/settings/zen_settings_page").claimArrangeRoute = function()
            return {
                opener = { text = "Arrange" },
                path = { "First", "Second" },
                deferred_parent = settings_parent,
            }
        end
        ArrangeList.show{
            allow_arrange = false,
            item_table = {
                {
                    text = "First",
                    sub_item_table = {
                        {
                            text = "Second",
                            sub_item_table = {{ text = "Destination" }},
                        },
                    },
                },
            },
        }

        shown_widgets[3]:_zen_arrange_close_all()

        assert.are.equal(3, #shown_widgets)
        assert.is_true(shown_widgets[1].invisible)
        assert.is_true(shown_widgets[2].invisible)
        assert.is_true(settings_parent._deferred_arrange_parent)
    end)

    it("reveals a deferred settings page after backing out of the arrange root", function()
        local settings_parent = { title = "Controls", _deferred_arrange_parent = true }
        settings_parent.invisible = true
        ui_manager:show(settings_parent)
        require("modules/settings/zen_settings_page").claimArrangeRoute = function()
            return {
                opener = { text = "Arrange" },
                path = { "First" },
                deferred_parent = settings_parent,
            }
        end
        ArrangeList.show{
            allow_arrange = false,
            item_table = {
                {
                    text = "First",
                    sub_item_table = {{ text = "Destination" }},
                },
            },
        }

        shown_widgets[3]:onClose()
        shown_widgets[2]:onClose()

        assert.are.equal(3, #shown_widgets)
        assert.are.equal(settings_parent, shown_widgets[1])
        assert.is_false(settings_parent.invisible)
    end)
end)

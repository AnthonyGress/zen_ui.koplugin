describe("app launcher plugin menu host", function()
    local shown_menu

    before_each(function()
        ZenSpec.unload("modules/menu/app_launcher/menu_host")
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("common/ui/zen_toggle", {
            new = function(_self, opts)
                return opts
            end,
        })
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 800 end,
                getHeight = function() return 600 end,
                scaleBySize = function(_self, value) return value end,
            },
        })
        ZenSpec.replace("ui/widget/menu", {
            new = function(_self, opts)
                shown_menu = {
                    paths = {},
                    item_table = opts.item_table,
                    state_w = opts.state_w,
                    switch_count = 0,
                    switchItemTable = function(self, title, items)
                        self.last_title = title
                        self.last_items = items
                        self.switch_count = self.switch_count + 1
                    end,
                }
                return shown_menu
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            show = function() end,
            close = function() end,
        })
    end)

    it("uses a Zen toggle for checkbox items and refreshes their live state", function()
        local enabled = false
        local MenuHost = require("modules/menu/app_launcher/menu_host")
        local host = MenuHost.show{
            title = "Wallabag",
            item_table = {
                {
                    text = "Send review as tags",
                    checked_func = function() return enabled end,
                    callback = function() enabled = not enabled end,
                },
            },
        }

        local row = shown_menu.item_table[1]
        assert.is_equal(56, shown_menu.state_w)
        assert.is_false(row.state.value_func())

        row.callback()

        assert.is_true(enabled)
        assert.is_nil(host._closed)
        assert.is_equal(1, shown_menu.switch_count)
        assert.is_true(shown_menu.last_items[1].state.value_func())
    end)

    it("does not turn radio options into toggles", function()
        local MenuHost = require("modules/menu/app_launcher/menu_host")
        MenuHost.show{
            title = "Choices",
            item_table = {
                {
                    text = "Choice A",
                    radio = true,
                    checked_func = function() return true end,
                    callback = function() end,
                },
            },
        }

        assert.is_nil(shown_menu.state_w)
        assert.is_nil(shown_menu.item_table[1].state)
    end)
end)

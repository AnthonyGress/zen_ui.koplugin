describe("top menu tap handling", function()
    local Device
    local FileManager
    local Menu
    local TopMenu

    local function point(x, y)
        return {
            x = x,
            y = y,
            intersectWith = function(self, dimen)
                return self.x >= dimen.x and self.x < dimen.x + dimen.w
                    and self.y >= dimen.y and self.y < dimen.y + dimen.h
            end,
        }
    end

    before_each(function()
        Device = {
            screen = {
                getHeight = function() return 1000 end,
                getWidth = function() return 1000 end,
                scaleBySize = function(_self, value) return value end,
            },
        }
        FileManager = {
            instance = {
                menu = {
                    activation_menu = "tap",
                    _getTabIndexFromLocation = function() return 1 end,
                    onShowMenu = function(self)
                        self.shown = (self.shown or 0) + 1
                    end,
                },
            },
        }
        Menu = {
            init = function() end,
            onSwipe = function() end,
        }
        ZenSpec.replace("device", Device)
        ZenSpec.replace("ui/widget/menu", Menu)
        ZenSpec.replace("apps/filemanager/filemanager", FileManager)
        ZenSpec.replace("apps/reader/readerui", {})
        ZenSpec.replace("ui/gesturerange", { new = function(_self, opts) return opts end })
        ZenSpec.unload("modules/global/patches/menu_top_swipe")
        TopMenu = require("modules/global/patches/menu_top_swipe")
        TopMenu.apply()
    end)

    after_each(function()
        ZenSpec.unload("modules/global/patches/menu_top_swipe")
        ZenSpec.unload("device")
        ZenSpec.unload("ui/widget/menu")
        ZenSpec.unload("apps/filemanager/filemanager")
        ZenSpec.unload("apps/reader/readerui")
        ZenSpec.unload("ui/gesturerange")
    end)

    it("still opens the KOReader menu from the unoccupied top area", function()
        local settings = {
            name = "zen_settings",
            title_bar = {
                close_button = { dimen = { x = 0, y = 0, w = 50, h = 50 } },
            },
        }

        assert.is_true(Menu.onTap(settings, nil, { pos = point(100, 10) }))
        assert.are.equal(1, FileManager.instance.menu.shown)
    end)

    it("eats taps above and between right-side header controls", function()
        local title_bar = {
            action_button = {
                dimen = { x = 800, y = 50, w = 40, h = 40 },
                image = { dimen = { x = 808, y = 58, w = 24, h = 24 } },
            },
            close_button = {
                dimen = { x = 900, y = 50, w = 40, h = 40 },
                image = { dimen = { x = 908, y = 58, w = 24, h = 24 } },
            },
        }

        assert.is_false(TopMenu.isInsideHeaderControl(title_bar, point(820, 10)))
        assert.is_true(TopMenu.handleTap(title_bar, { pos = point(820, 10) }))
        assert.is_true(TopMenu.handleTap(title_bar, { pos = point(860, 10) }))
        assert.is_nil(FileManager.instance.menu.shown)
        assert.is_true(TopMenu.isInsideHeaderControl(title_bar, point(820, 70)))
    end)

    it("opens the KOReader menu from an unoccupied top-center tap", function()
        local title_bar = {
            action_button = { dimen = { x = 800, y = 50, w = 40, h = 40 } },
            close_button = { dimen = { x = 900, y = 50, w = 40, h = 40 } },
        }

        assert.is_true(TopMenu.handleTap(title_bar, { pos = point(500, 10) }))
        assert.are.equal(1, FileManager.instance.menu.shown)
    end)
end)

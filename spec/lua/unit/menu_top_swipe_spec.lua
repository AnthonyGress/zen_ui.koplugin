describe("top menu tap handling", function()
    local Device
    local FileManager
    local Menu

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
            screen = { getHeight = function() return 1000 end },
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
        ZenSpec.replace("ui/gesturerange", { new = function(_self, opts) return opts end })
        ZenSpec.unload("modules/global/patches/menu_top_swipe")
        require("modules/global/patches/menu_top_swipe")()
    end)

    after_each(function()
        ZenSpec.unload("modules/global/patches/menu_top_swipe")
        ZenSpec.unload("device")
        ZenSpec.unload("ui/widget/menu")
        ZenSpec.unload("apps/filemanager/filemanager")
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
end)

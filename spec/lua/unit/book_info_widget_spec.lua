describe("book details", function()
    local BookInfoWidget
    local image_specs
    local top_taps
    local top_swipes
    local description_swipes
    local saved_modules

    local dependency_names = {
        "gettext",
        "device",
        "datastorage",
        "ffi/blitbuffer",
        "ui/font",
        "ui/geometry",
        "ui/uimanager",
        "ui/widget/container/inputcontainer",
        "ui/widget/iconwidget",
        "ui/widget/imagewidget",
        "ui/widget/scrolltextwidget",
        "ui/widget/textboxwidget",
        "ui/widget/textwidget",
        "common/cover_utils",
        "common/utils",
        "modules/global/patches/menu_top_swipe",
    }

    local function input_container()
        local InputContainer = {}

        function InputContainer:extend(prototype)
            prototype = prototype or {}
            prototype.__index = prototype
            return setmetatable(prototype, { __index = self })
        end

        function InputContainer:new(values)
            values = values or {}
            setmetatable(values, { __index = self })
            values:init()
            return values
        end

        function InputContainer:registerTouchZones(zones)
            self.touch_zones = zones
        end

        return InputContainer
    end

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(dependency_names) do
            saved_modules[name] = package.loaded[name] or false
        end
        image_specs = {}
        top_taps = 0
        top_swipes = 0
        description_swipes = 0

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_self, value) return value end,
            },
            hasKeys = function() return false end,
        })
        ZenSpec.replace("datastorage", { getDataDir = function() return "/koreader" end })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_LIGHT_GRAY = "light_gray",
            COLOR_WHITE = "white",
        })
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("ui/geometry", { new = function(_self, values) return values end })
        ZenSpec.replace("ui/uimanager", { close = function() end, setDirty = function() end })
        ZenSpec.replace("ui/widget/container/inputcontainer", input_container())
        ZenSpec.replace("ui/widget/iconwidget", {
            new = function(_self, values)
                values.getSize = function() return { w = 26, h = 26 } end
                values.paintTo = function() end
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/imagewidget", {
            new = function(_self, values)
                image_specs[#image_specs + 1] = values
                values.paintTo = function() end
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/scrolltextwidget", {
            new = function(_self, values)
                values.paintTo = function() end
                values.free = function() end
                values.onTapScrollText = function() end
                values.onScrollText = function()
                    description_swipes = description_swipes + 1
                end
                values.onPanText = function() end
                values.onPanReleaseText = function() end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/textboxwidget", {
            new = function(_self, values)
                values.getSize = function() return { w = 100, h = 20 } end
                values.paintTo = function() end
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/textwidget", {
            new = function(_self, values)
                values.getSize = function() return { w = 100, h = 20 } end
                values.paintTo = function() end
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("common/cover_utils", { BORDER_SIZE = 1 })
        ZenSpec.replace("common/utils", { resolveLocalIcon = function() return nil end })
        ZenSpec.replace("modules/global/patches/menu_top_swipe", {
            handleTap = function()
                top_taps = top_taps + 1
                return true
            end,
            handleSwipe = function()
                top_swipes = top_swipes + 1
                return true
            end,
        })
        ZenSpec.unload("modules/reader/book_info_widget")
        BookInfoWidget = require("modules/reader/book_info_widget")
    end)

    after_each(function()
        ZenSpec.unload("modules/reader/book_info_widget")
        for _i, name in ipairs(dependency_names) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    local function new_widget()
        return BookInfoWidget:new{
            cover = {},
            cover_width = 120,
            cover_height = 180,
            description = "Description",
        }
    end

    it("keeps the cover colors correct in night mode", function()
        new_widget()

        assert.are.equal(true, image_specs[1].original_in_nightmode)
    end)

    it("opens the KOReader menu from an unoccupied top tap", function()
        local widget = new_widget()

        assert.is_true(widget:_onTap({ pos = { x = 300, y = 10 } }))
        assert.are.equal(1, top_taps)
    end)

    it("opens the KOReader menu from a top south swipe without blocking description scrolling", function()
        local widget = new_widget()

        assert.is_true(widget:_onSwipe({ direction = "south", pos = { x = 300, y = 10 } }))
        assert.are.equal(1, top_swipes)
        assert.are.equal(0, description_swipes)

        assert.is_true(widget:_onSwipe({ direction = "south", pos = { x = 300, y = 400 } }))
        assert.are.equal(1, top_swipes)
        assert.are.equal(1, description_swipes)
    end)
end)

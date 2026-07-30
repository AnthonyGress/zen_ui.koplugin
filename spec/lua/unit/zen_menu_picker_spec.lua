describe("Zen menu picker", function()
    local saved_modules
    local shown
    local selected
    local device_has_dpad
    local device_has_keyboard
    local device_is_touch
    local back_inverted
    local closed
    local pager_x
    local pager_y
    local pager_w

    local module_names = {
        "gettext",
        "device",
        "ui/geometry",
        "ffi/blitbuffer",
        "ui/font",
        "ui/size",
        "ui/uimanager",
        "ui/widget/focusmanager",
        "ui/widget/iconwidget",
        "ui/widget/textwidget",
        "common/ui/zen_pager",
        "common/ui/zen_menu_picker",
    }

    local function focus_manager()
        local FocusManager = {}

        function FocusManager:extend(definition)
            definition = definition or {}
            setmetatable(definition, { __index = self })
            return definition
        end

        function FocusManager:new(values)
            values = values or {}
            setmetatable(values, { __index = self })
            values:init()
            return values
        end

        function FocusManager:_init()
            self.key_events = {
                FocusDown = { { "Down" }, event = "FocusMove", args = { 0, 1 } },
                Press = { { "Press" }, event = "Press" },
            }
        end

        function FocusManager:registerTouchZones() end

        return FocusManager
    end

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(module_names) do
            saved_modules[name] = package.loaded[name] or false
        end
        shown = nil
        selected = nil
        device_has_dpad = true
        device_has_keyboard = false
        device_is_touch = false
        back_inverted = nil
        closed = 0
        pager_x = nil
        pager_y = nil
        pager_w = nil

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_, value) return value end,
            },
            input = { group = { Back = { "Back" }, PgBack = { "PgBack" }, PgFwd = { "PgFwd" } } },
            hasKeys = function() return true end,
            hasDPad = function() return device_has_dpad end,
            hasKeyboard = function() return device_has_keyboard end,
            isTouchDevice = function() return device_is_touch end,
        })
        ZenSpec.replace("ui/geometry", { new = function(_, values) return values end })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_DARK_GRAY = "dark_gray",
            COLOR_LIGHT_GRAY = "light_gray",
            COLOR_WHITE = "white",
        })
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("ui/size", {
            line = { thick = 1 },
            padding = { default = 10, large = 20 },
            span = { vertical_default = 4 },
        })
        ZenSpec.replace("ui/uimanager", {
            show = function(_, widget) shown = widget end,
            close = function() closed = closed + 1 end,
            forceRePaint = function() end,
            nextTick = function(_, callback) callback() end,
            setDirty = function() end,
        })
        ZenSpec.replace("ui/widget/focusmanager", focus_manager())
        ZenSpec.replace("ui/widget/iconwidget", {
            new = function(_, values)
                values.paintTo = function(self) back_inverted = self.invert end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/textwidget", {
            new = function(_, values)
                values.getSize = function() return { w = 100, h = 20 } end
                values.paintTo = function() end
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("common/ui/zen_pager", {
            CHEV_W = 20,
            PN_FOOTER_H = 30,
            getHoldSkip = function() return "ends" end,
            getCenteredFooterY = function(content_bottom, footer_y, footer_h)
                local gap_h = footer_y + footer_h - content_bottom
                return content_bottom + math.floor((gap_h - footer_h) / 2)
            end,
            paint = function(_bb, x, y, w)
                pager_x = x
                pager_y = y
                pager_w = w
            end,
        })
        ZenSpec.unload("common/ui/zen_menu_picker")
    end)

    after_each(function()
        for _i, name in ipairs(module_names) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("uses D-pad focus movement to select an item", function()
        require("common/ui/zen_menu_picker"){
            title = "Choose plugin menu",
            items = {
                { text = "First" },
                { text = "Second" },
            },
            on_select = function(item) selected = item.text end,
        }

        assert.is_not_nil(shown.key_events.FocusDown)
        assert.is_nil(shown.key_events.MenuPickerDown)
        assert.is_true(shown:onFocusMove({ 0, 1 }))
        assert.is_true(shown:onPress())
        assert.are.equal("Second", selected)
    end)

    it("shows focus when a touchscreen device has a keyboard", function()
        device_has_dpad = false
        device_has_keyboard = true
        device_is_touch = true
        require("common/ui/zen_menu_picker"){
            items = { { text = "Plugin" } },
        }

        local painted = {}
        shown:paintTo({
            paintRect = function(_, _x, _y, _w, _h, color)
                painted[#painted + 1] = color
            end,
        }, 0, 0)

        assert.is_true(table.concat(painted, ","):find("black", 1, true) ~= nil)
    end)

    it("focuses and activates the back chevron from the first item", function()
        require("common/ui/zen_menu_picker"){
            items = { { text = "Plugin" } },
        }

        assert.is_true(shown:onFocusMove({ 0, -1 }))
        local painted = {}
        shown:paintTo({
            paintRect = function(_, _x, _y, _w, _h, color)
                painted[#painted + 1] = color
            end,
        }, 0, 0)
        assert.is_true(back_inverted)
        assert.is_nil(table.concat(painted, ","):find("black", 1, true))
        assert.is_true(shown:onFocusMove({ 0, 1 }))
        painted = {}
        shown:paintTo({
            paintRect = function(_, _x, _y, _w, _h, color)
                painted[#painted + 1] = color
            end,
        }, 0, 0)
        assert.is_false(back_inverted)
        assert.is_true(table.concat(painted, ","):find("black", 1, true) ~= nil)
        assert.is_true(shown:onFocusMove({ 0, -1 }))
        assert.is_true(shown:onPress())
        assert.are.equal(1, closed)
    end)

    it("keeps a centered pager at the same height on every page", function()
        local items = {}
        for item_index = 1, 15 do
            items[item_index] = { text = "Item " .. tostring(item_index) }
        end
        require("common/ui/zen_menu_picker"){ items = items }

        shown:paintTo({ paintRect = function() end }, 0, 0)
        local first_page_y = pager_y
        shown:onMenuPickerPage(1)
        shown:paintTo({ paintRect = function() end }, 0, 0)

        assert.are.equal(10, pager_x)
        assert.are.equal(743, first_page_y)
        assert.are.equal(580, pager_w)
        assert.are.equal(first_page_y, pager_y)
    end)
end)

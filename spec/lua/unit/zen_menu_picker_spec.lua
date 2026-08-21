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
    local pager_page
    local row_font_size
    local text_widgets
    local back_icon
    local back_paint_x
    local truncated_text

    local module_names = {
        "gettext",
        "device",
        "ui/geometry",
        "ffi/blitbuffer",
        "ui/font",
        "ui/size",
        "ui/uimanager",
        "ui/widget/infomessage",
        "ui/widget/focusmanager",
        "ui/widget/iconwidget",
        "ui/widget/textwidget",
        "common/ui/zen_pager",
        "common/ui/zen_title_style",
        "common/ui/truncated_text_message",
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

        function FocusManager:registerTouchZones(zones) self.touch_zones = zones end

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
        pager_page = nil
        row_font_size = nil
        text_widgets = {}
        back_icon = nil
        back_paint_x = nil
        truncated_text = nil

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
        ZenSpec.replace("ui/font", {
            getFace = function(_self, _name, size)
                if size then row_font_size = size end
                return {}
            end,
        })
        ZenSpec.replace("ui/size", {
            line = { thick = 1 },
            padding = { default = 10, large = 20, small = 4 },
            span = { vertical_default = 4 },
        })
        ZenSpec.replace("ui/uimanager", {
            show = function(_, widget) shown = widget end,
            close = function() closed = closed + 1 end,
            forceRePaint = function() end,
            nextTick = function(_, callback) callback() end,
            setDirty = function() end,
        })
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_self, options)
                options.movable = {}
                return options
            end,
        })
        ZenSpec.replace("ui/widget/focusmanager", focus_manager())
        ZenSpec.replace("ui/widget/iconwidget", {
            new = function(_, values)
                back_icon = values
                values.paintTo = function(self, _bb, x)
                    back_inverted = self.invert
                    back_paint_x = x
                end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/textwidget", {
            new = function(_, values)
                values.getSize = function() return { w = 100, h = 20 } end
                values.isTruncated = function(self) return self.text == truncated_text end
                values.paintTo = function(self, _bb, x) self.paint_x = x end
                values.free = function() end
                text_widgets[#text_widgets + 1] = values
                return values
            end,
        })
        ZenSpec.replace("common/ui/zen_pager", {
            CHEV_W = 20,
            CHEV_HIT_W = 40,
            PN_FOOTER_H = 30,
            getHoldSkip = function() return "ends" end,
            getCenteredFooterY = function(content_bottom, footer_y, footer_h)
                local gap_h = footer_y + footer_h - content_bottom
                return content_bottom + math.floor((gap_h - footer_h) / 2)
            end,
            getPageNumberZone = function(x, y, footer_x, footer_y, footer_w, footer_h, available_bottom)
                local hit_bottom = math.min(footer_y + footer_h + 24, available_bottom)
                if x < footer_x or x >= footer_x + footer_w
                        or y < footer_y or y >= hit_bottom then
                    return nil
                end
                if x < footer_x + 40 then return "left" end
                if x >= footer_x + footer_w - 40 then return "right" end
                if y < footer_y + footer_h then return "center" end
            end,
            paint = function(_bb, x, y, w, _h, cur_page)
                pager_x = x
                pager_y = y
                pager_w = w
                pager_page = cur_page
            end,
        })
        ZenSpec.replace("common/ui/zen_title_style", {
            ICON_SIZE = 28,
            BUTTON_SIZE = 44,
            LEFT_PADDING = 4,
            RIGHT_PADDING = 20,
            ROW_HEIGHT = 44,
            VERTICAL_PADDING = 6,
            DIVIDER_HEIGHT = 2,
            DIVIDER_COLOR = "light_gray",
            HEADER_CONTENT_HEIGHT = 56,
            HEADER_HEIGHT = 58,
            getTitleFace = function() return { name = "settings_title" } end,
            getLeadingIconX = function(origin) return (origin or 0) + 12 end,
            getTitleX = function(origin) return (origin or 0) + 54 end,
        })
        ZenSpec.unload("common/ui/truncated_text_message")
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

    it("uses larger text for picker rows", function()
        require("common/ui/zen_menu_picker"){
            items = { { text = "Plugin" } },
        }

        assert.are.equal(24, row_font_size)
    end)

    it("matches the arrange-list header divider", function()
        require("common/ui/zen_menu_picker"){
            items = { { text = "Plugin" } },
        }
        local dividers = {}
        shown:paintTo({
            paintRect = function(_bb, _x, _y, _w, h, color)
                if h == 2 then dividers[#dividers + 1] = color end
            end,
        }, 0, 0)

        assert.are.same({ "light_gray" }, dividers)
    end)

    it("aligns its title and back icon with the arrange-list header", function()
        require("common/ui/zen_menu_picker"){
            title = "Choose plugin menu",
            items = { { text = "Plugin" } },
        }
        shown:paintTo({ paintRect = function() end }, 0, 0)

        assert.are.equal(28, back_icon.width)
        assert.are.equal(12, back_paint_x)
        assert.are.equal("settings_title", text_widgets[1].face.name)
        assert.are.equal(54, text_widgets[1].paint_x)
    end)

    it("bolds root rows and indents nested rows", function()
        require("common/ui/zen_menu_picker"){
            items = {
                { text = "Settings", bold = true, indent_level = 0 },
                { text = "Network", indent_level = 1 },
            },
        }

        shown:paintTo({ paintRect = function() end }, 0, 0)
        local root_row = text_widgets[2]
        local nested_row = text_widgets[3]
        assert.is_true(root_row.bold)
        assert.is_false(nested_row.bold)
        assert.are.equal(16, nested_row.paint_x - root_row.paint_x)
    end)

    it("shows full truncated row text on hold", function()
        local full_text = "A plugin menu label too long for its row"
        truncated_text = full_text
        require("common/ui/zen_menu_picker"){
            items = { { text = full_text } },
        }
        local picker = shown
        picker:paintTo({ paintRect = function() end }, 0, 0)

        assert.is_true(picker.touch_zones[2].handler({ pos = { x = 100, y = 70 } }))
        assert.are.equal(full_text, shown.text)
        assert.is_false(shown.show_icon)
        assert.are.same({ y = 54, h = 56 }, shown.movable.anchor)
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

    it("uses its supplied root callback when its header is held", function()
        local root_returns = 0
        local fallback_returns = 0
        _G.__ZEN_UI_SETTINGS_PAGE = {
            backToRootMenu = function() fallback_returns = fallback_returns + 1 end,
        }
        require("ui/uimanager").close = function()
            closed = closed + 1
            _G.__ZEN_UI_SETTINGS_PAGE = nil
        end
        require("common/ui/zen_menu_picker"){
            items = { { text = "Plugin" } },
            back_hold_callback = function() root_returns = root_returns + 1 end,
        }

        assert.is_true(shown.touch_zones[2].handler({ pos = { x = 30, y = 20 } }))
        assert.are.equal(1, closed)
        assert.are.equal(1, root_returns)
        assert.are.equal(0, fallback_returns)
        _G.__ZEN_UI_SETTINGS_PAGE = nil
    end)

    it("captures the settings page before closing the picker", function()
        local root_returns = 0
        _G.__ZEN_UI_SETTINGS_PAGE = {
            backToRootMenu = function() root_returns = root_returns + 1 end,
        }
        require("ui/uimanager").close = function()
            closed = closed + 1
            _G.__ZEN_UI_SETTINGS_PAGE = nil
        end
        require("common/ui/zen_menu_picker"){
            items = { { text = "Plugin" } },
        }

        assert.is_true(shown.touch_zones[2].handler({ pos = { x = 30, y = 20 } }))
        assert.are.equal(1, closed)
        assert.are.equal(1, root_returns)
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
        assert.are.equal(745, first_page_y)
        assert.are.equal(580, pager_w)
        assert.are.equal(first_page_y, pager_y)
    end)

    it("accepts wider chevron taps briefly below the painted footer", function()
        local items = {}
        for item_index = 1, 15 do
            items[item_index] = { text = "Item " .. tostring(item_index) }
        end
        require("common/ui/zen_menu_picker"){ items = items }
        local tap = shown.touch_zones[1].handler

        assert.is_true(tap({ pos = { x = 40, y = 790 } }))
        shown:paintTo({ paintRect = function() end }, 0, 0)
        assert.are.equal(2, pager_page)
        assert.is_true(tap({ pos = { x = 300, y = 790 } }))
        assert.is_true(tap({ pos = { x = 40, y = 799 } }))
        shown:paintTo({ paintRect = function() end }, 0, 0)
        assert.are.equal(2, pager_page)
    end)
end)

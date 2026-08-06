describe("Zen TOC hardware focus", function()
    local ZenTocWidget
    local close_calls
    local dirty_calls

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
        close_calls = 0
        dirty_calls = 0
        ZenSpec.replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 260 end,
                scaleBySize = function(_self, value) return value end,
            },
            hasKeys = function() return true end,
            hasDPad = function() return true end,
            hasKeyboard = function() return false end,
            input = {
                group = { Back = "Back", PgBack = "PgBack", PgFwd = "PgFwd" },
            },
        })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_DARK_GRAY = "dark_gray",
            COLOR_LIGHT_GRAY = "light_gray",
            COLOR_WHITE = "white",
            gray = function(value) return value end,
        })
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("ui/geometry", { new = function(_self, values) return values end })
        ZenSpec.replace("ui/widget/container/inputcontainer", input_container())
        ZenSpec.replace("ui/widget/iconwidget", {
            new = function(_self, values)
                values.paintTo = function() end
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/textwidget", {
            new = function(_self, values)
                values.getSize = function() return { w = 80, h = 20 } end
                values.paintTo = function() end
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            close = function() close_calls = close_calls + 1 end,
            setDirty = function() dirty_calls = dirty_calls + 1 end,
        })
        ZenSpec.replace("common/ui/zen_pager", {
            PN_FOOTER_H = 40,
            FOOTER_H = 20,
            CHEV_W = 50,
            CHEV_HIT_W = 80,
            getStyle = function() return "page_number" end,
            getCenteredFooterY = function(_list_bottom, footer_top) return footer_top end,
            getHoldSkip = function() return 10 end,
            getPageNumberZone = function(x, y, footer_x, footer_y, footer_w, footer_h, available_bottom)
                local hit_bottom = math.min(footer_y + footer_h + 24, available_bottom)
                if x < footer_x or x >= footer_x + footer_w
                        or y < footer_y or y >= hit_bottom then
                    return nil
                end
                if x < footer_x + 80 then return "left" end
                if x >= footer_x + footer_w - 80 then return "right" end
                if y < footer_y + footer_h then return "center" end
            end,
            paint = function() end,
            setPlugin = function() end,
        })
        ZenSpec.unload("modules/reader/zen_toc_widget")
        ZenTocWidget = require("modules/reader/zen_toc_widget")
    end)

    after_each(function()
        ZenSpec.unload("modules/reader/zen_toc_widget")
    end)

    local function new_widget(on_goto)
        local toc = {}
        for i = 1, 8 do
            toc[i] = { title = "Section " .. i, page = i * 10, depth = 1 }
        end
        return ZenTocWidget:new{
            ui = { toc = { toc = toc } },
            focus_page = 1,
            on_goto = on_goto,
        }
    end

    local function key(name)
        return {
            match = function(_self, sequence) return sequence[1] == name end,
        }
    end

    it("moves from Back through every visible section and footer button", function()
        local widget = new_widget()
        assert.are.equal("back", widget._zen_focus_area)
        assert.are.equal("Back", widget.key_events.Close[1][1])
        assert.are.equal("PgFwd", widget.key_events.TocPageDown[1][1])

        assert.is_true(widget:onKeyPress(key("Down")))
        assert.are.equal("entry", widget._zen_focus_area)
        local first = widget._zen_focus_entry_idx
        assert.is_true(widget:onKeyPress(key("Down")))
        assert.are.equal(first + 1, widget._zen_focus_entry_idx)
        assert.is_true(widget:onKeyPress(key("Down")))
        assert.are.equal(first + 2, widget._zen_focus_entry_idx)
        assert.is_true(widget:onKeyPress(key("Down")))
        assert.are.equal("footer", widget._zen_focus_area)
        assert.are.equal("left", widget._zen_footer_side)

        assert.is_true(widget:onKeyPress(key("Right")))
        assert.are.equal("right", widget._zen_footer_side)
        assert.is_true(widget:onKeyPress(key("Press")))
        assert.are.equal(2, widget._toc_page)
        assert.is_true(widget:onKeyPress(key("Up")))
        assert.are.equal("entry", widget._zen_focus_area)
    end)

    it("opens a focused section and pages with hardware page-turn events", function()
        local selected_page
        local widget = new_widget(function(page) selected_page = page end)

        assert.is_true(widget:onTocPage(1))
        assert.are.equal(2, widget._toc_page)
        assert.is_true(widget:onKeyPress(key("Down")))
        assert.are.equal("entry", widget._zen_focus_area)
        local entry = widget._entries[widget._zen_focus_entry_idx]
        assert.is_true(widget:onKeyPress(key("Return")))
        assert.are.equal(entry.page, selected_page)
        assert.are.equal(1, close_calls)
        assert.is_true(dirty_calls > 0)
    end)
end)

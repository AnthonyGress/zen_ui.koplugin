describe("home basic widgets", function()
    local created
    local date_stub

    local function geom_new(_, values)
        values = values or {}
        function values:contains(pos)
            return pos.x >= (self.x or 0) and pos.x < (self.x or 0) + (self.w or 0)
                and pos.y >= (self.y or 0) and pos.y < (self.y or 0) + (self.h or 0)
        end
        return values
    end

    local function widget_class(kind)
        return {
            new = function(_, values)
                values = values or {}
                values.kind = kind
                values.dimen = values.dimen or {
                    x = 0,
                    y = 0,
                    w = values.width or (type(values.text) == "string" and #values.text * 6 or 20),
                    h = values.height or 12,
                }
                values.getSize = values.getSize or function(self) return self.dimen end
                values.paintTo = values.paintTo or function(self)
                    self.painted = (self.painted or 0) + 1
                end
                values.free = values.free or function(self) self.freed = true end
                created[#created + 1] = values
                return values
            end,
        }
    end

    local function setup_widget_dependencies()
        created = {}
        ZenSpec.replace("common/ui/background", { tile_bg = function(color) return color end })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_GRAY_3 = "gray",
            COLOR_WHITE = "white",
        })
        ZenSpec.replace("device", {
            screen = {
                scaleBySize = function(_, value) return value end,
                getWidth = function() return 800 end,
                getHeight = function() return 600 end,
            },
        })
        ZenSpec.replace("ui/font", {
            getFace = function(_, name, size) return { name = name, size = size } end,
        })
        ZenSpec.replace("ui/geometry", { new = geom_new })
        for _i, name in ipairs({
            "ui/widget/container/framecontainer",
            "ui/widget/container/inputcontainer",
            "ui/widget/textboxwidget",
            "ui/widget/textwidget",
        }) do
            ZenSpec.replace(name, widget_class(name))
        end
        ZenSpec.replace("ui/gesturerange", widget_class("gesture"))
        ZenSpec.unload("common/widget_resources")
    end

    local function texts()
        local result = {}
        for _i, widget in ipairs(created) do
            if type(widget.text) == "string" then result[#result + 1] = widget.text end
        end
        return result
    end

    local function has_text(expected)
        for _i, value in ipairs(texts()) do
            if value == expected then return true end
        end
        return false
    end

    before_each(function()
        setup_widget_dependencies()
        _G.G_reader_settings = ZenSpec.memorySettings()
    end)

    after_each(function()
        if date_stub then date_stub:revert() end
        date_stub = nil
    end)

    it("renders a 24-hour clock and localized date and registers refresh", function()
        date_stub = stub(os, "date")
        date_stub.on_call_with("%H:%M").returns("21:07")
        date_stub.on_call_with("*t").returns({ wday = 2, day = 8 })
        date_stub.on_call_with("%B").returns("January")
        date_stub.on_call_with("%A").returns("Monday")
        ZenSpec.replace("datetime", {
            weekDays = { [2] = "Mon" },
            shortDayOfWeekToLongTranslation = { Mon = "Monday" },
            longMonthTranslation = { January = "January" },
        })
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/datetime")
        local refresh
        local component = require("modules/filebrowser/patches/home/widgets/datetime")
        local widget = component.build({
            width = 500,
            height = 120,
            is_first_row = true,
            registerClockRefresh = function(callback) refresh = callback end,
        })

        assert.are.equal("datetime", component.id)
        assert.are.same({ preferred_pct = 0.15, min_pct = 0.10, max_pct = 0.26, grow_priority = 2 }, component.size)
        assert.is_table(widget)
        assert.is_function(refresh)
        assert.is_true(refresh())
        assert.is_true(has_text("21:07"))
        assert.is_true(has_text("Monday, January 8"))
        local clock_size, date_size
        for _i, child in ipairs(created) do
            if child.text == "21:07" then
                clock_size = child.face.size
            elseif child.text == "Monday, January 8" then
                date_size = child.face.size
            end
        end
        assert.are.equal(240, clock_size)
        assert.are.equal(86, date_size)
    end)

    it("honors the twelve-hour clock setting and removes its leading zero", function()
        _G.G_reader_settings = ZenSpec.memorySettings({ twelve_hour_clock = true })
        date_stub = stub(os, "date")
        date_stub.on_call_with("%I:%M").returns("09:05")
        date_stub.on_call_with("*t").returns({ wday = 2, day = 8 })
        date_stub.on_call_with("%B").returns("January")
        date_stub.on_call_with("%A").returns("Monday")
        ZenSpec.replace("datetime", {
            weekDays = { [2] = "Mon" },
            shortDayOfWeekToLongTranslation = { Mon = "Monday" },
            longMonthTranslation = { January = "January" },
        })
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/datetime")
        require("modules/filebrowser/patches/home/widgets/datetime").build({
            width = 300, height = 60, is_first_row = false,
        })

        assert.is_true(has_text("9:05"))
        local clock_size
        for _i, child in ipairs(created) do
            if child.text == "9:05" then
                clock_size = child.face.size
            end
        end
        assert.are.equal(120, clock_size)
    end)

    it("renders quote text and author and navigates in both tap zones", function()
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/quotes")
        local previous, next_quote = 0, 0
        local component = require("modules/filebrowser/patches/home/widgets/quotes")
        local widget = component.build({
            width = 400,
            height = 120,
            config = { quotes = { show_author = true } },
            data = {
                getCurrentQuote = function() return { text = "Read deeply.", author = "Zen Tester" } end,
                prevQuote = function() previous = previous + 1 end,
                nextQuote = function() next_quote = next_quote + 1 end,
            },
        })
        widget.dimen.x, widget.dimen.y = 10, 20

        assert.are.equal("quotes", component.id)
        assert.is_true(widget:onTapQuote(nil, { pos = { x = 40, y = 40 } }))
        assert.is_true(widget:onTapQuote(nil, { pos = { x = 300, y = 40 } }))
        assert.are.same({ 1, 1 }, { previous, next_quote })
        assert.is_false(widget:onTapQuote(nil, { pos = { x = 700, y = 40 } }))
        assert.is_true(has_text('"Read deeply."'))
        assert.is_true(has_text("\226\128\148 Zen Tester"))
    end)

    it("renders the empty-history quote fallback without an author", function()
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/quotes")
        local component = require("modules/filebrowser/patches/home/widgets/quotes")
        component.build({
            width = 400,
            height = 100,
            config = { quotes = { show_author = true } },
            data = { getCurrentQuote = function() return nil end },
        })

        assert.is_true(has_text('"No quote available."'))
        assert.is_false(has_text("\226\128\148 "))
    end)
end)

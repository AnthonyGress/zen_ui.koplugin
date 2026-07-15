describe("reading goals settings", function()
    before_each(function()
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", { show = function() end })
        ZenSpec.unload("common/reading_goals")
    end)

    it("migrates a legacy goal and keeps every selected period", function()
        local Goals = require("common/reading_goals")
        local goals = Goals.normalize({
            metric = "time",
            period = "weekly",
            periods = { "daily", "monthly", "yearly", "monthly", "invalid" },
        })

        assert.are.same({ "daily", "monthly", "yearly" }, goals.periods)
        assert.are.equal("time", goals.metric)
        assert.are.equal(900, goals.monthly_pages_target)
        assert.are.equal(1000, goals.yearly_time_target_min)
        assert.are.equal("time", goals.metrics.monthly)

        local legacy = Goals.normalize({ period = "weekly" })
        assert.are.same({ "weekly" }, legacy.periods)
    end)

    it("offers each goal period as a submenu with its own metric and targets", function()
        local Goals = require("common/reading_goals")
        local items = Goals.settingsItems({ periods = { "daily" } }, function() end)

        assert.are.equal("Daily", items[1].text)
        assert.are.equal("Weekly", items[2].text)
        assert.are.equal("Monthly", items[3].text)
        assert.are.equal("Yearly", items[4].text)
        local daily = items[1].sub_item_table_func()
        assert.are.equal("Show goal", daily[1].text)
        assert.are.equal("Pages", daily[2].text)
        assert.are.equal("Time", daily[3].text)
        assert.are.equal("Daily pages goal: 30", daily[4].text_func())
        assert.are.equal("Daily time goal (min): 30", daily[5].text_func())
    end)
end)

describe("reading goals widget", function()
    local created
    local shown

    local function widget_class(kind)
        return {
            new = function(_, values)
                values = values or {}
                values.kind = kind
                values.dimen = values.dimen or {
                    w = values.width or (type(values.text) == "string" and #values.text * 6 or 20),
                    h = values.height or 10,
                }
                values.getSize = values.getSize or function(self) return self.dimen end
                created[#created + 1] = values
                return values
            end,
        }
    end

    before_each(function()
        created = {}
        shown = nil
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("common/ui/background", { tile_bg = function(color) return color end })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_GRAY_3 = "gray3", COLOR_GRAY_5 = "gray5",
            COLOR_LIGHT_GRAY = "lightgray", COLOR_WHITE = "white",
        })
        ZenSpec.replace("ui/geometry", {
            new = function(_, values)
                function values:contains(pos)
                    return pos.x >= (self.x or 0) and pos.x < (self.x or 0) + (self.w or 0)
                        and pos.y >= (self.y or 0) and pos.y < (self.y or 0) + (self.h or 0)
                end
                return values
            end,
        })
        ZenSpec.replace("ui/font", { getFace = function(_, name, size) return { name = name, size = size } end })
        ZenSpec.replace("device", { screen = {
            scaleBySize = function(_, value) return value end,
            getWidth = function() return 800 end,
            getHeight = function() return 600 end,
        } })
        ZenSpec.replace("common/widget_resources", { free = function() end })
        ZenSpec.replace("ui/uimanager", { show = function(_self, widget) shown = widget end })
        for _i, name in ipairs({
            "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/textwidget",
            "ui/widget/container/framecontainer", "ui/widget/container/centercontainer",
            "ui/widget/container/leftcontainer", "ui/widget/container/rightcontainer",
            "ui/widget/verticalgroup", "ui/widget/verticalspan",
            "ui/widget/container/inputcontainer",
            "ui/widget/container/scrollablecontainer", "ui/widget/titlebar",
        }) do
            ZenSpec.replace(name, widget_class(name))
        end
        ZenSpec.replace("ui/gesturerange", widget_class("ui/gesturerange"))
        ZenSpec.replace("ui/widget/container/scrollablecontainer", {
            getScrollbarWidth = function() return 0 end,
            new = function(_, values)
                values.getSize = values.getSize or function() return values.dimen end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/buttondialog", {
            new = function(_, values)
                values.widgets = {}
                values.ges_events = {}
                function values:addWidget(widget) self.widgets[#self.widgets + 1] = widget end
                return values
            end,
        })
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/reading_goals")
    end)

    it("stacks every selected goal period", function()
        local widget = require("modules/filebrowser/patches/home/widgets/reading_goals")
        local goal_widget = widget.build({
            width = 600,
            height = 160,
            config = {
                goals = {
                    periods = { "daily", "weekly", "monthly", "yearly" },
                    metrics = { daily = "pages", weekly = "time", monthly = "pages", yearly = "time" },
                },
            },
            data = { stats = {
                today_pages = 1, week_pages = 2, month_pages = 3, year_pages = 4,
                year_duration = 240,
            } },
        })

        local found = {}
        for _i, item in ipairs(created) do
            if item.text then found[item.text] = true end
        end
        assert.is_true(found["Daily"])
        assert.is_true(found["Weekly"])
        assert.is_true(found["Monthly"])
        assert.is_true(found["Yearly"])
        assert.is_true(found["1 / 30 pages (3%)"])
        assert.is_true(found["4 / 1000 min (0%)"])

        goal_widget.dimen.x, goal_widget.dimen.y = 0, 0
        assert.is_true(goal_widget:onTapReadingGoals(nil, { pos = { x = 20, y = 20 } }))
        assert.are.equal("Reading goals", shown.widgets[1].title)
        local popup_texts = {}
        for _i, item in ipairs(created) do
            if item.text then popup_texts[item.text] = true end
        end
        assert.is_true(popup_texts[string.format("Daily goal (%s)", os.date("%B %d"))])
        assert.is_true(popup_texts[string.format("Monthly goal (%s)", os.date("%B"))])
        assert.is_true(popup_texts[string.format("Yearly goal (%s)", os.date("%Y"))])
    end)
end)

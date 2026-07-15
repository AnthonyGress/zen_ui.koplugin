local UIManager = require("ui/uimanager")
local _ = require("gettext")

local M = {}

local PERIODS = {
    {
        id = "daily", text = _("Daily"),
        pages = { key = "daily_pages_target", default = 30, max = 5000 },
        time = { key = "daily_time_target_min", default = 30, max = 1440 },
    },
    {
        id = "weekly", text = _("Weekly"),
        pages = { key = "weekly_pages_target", default = 210, max = 20000 },
        time = { key = "weekly_time_target_min", default = 210, max = 10080 },
    },
    {
        id = "monthly", text = _("Monthly"),
        pages = { key = "monthly_pages_target", default = 900, max = 100000 },
        time = { key = "monthly_time_target_min", default = 900, max = 44640 },
    },
    {
        id = "yearly", text = _("Yearly"),
        pages = { key = "yearly_pages_target", default = 1000, max = 1000000 },
        time = { key = "yearly_time_target_min", default = 1000, max = 525600 },
    },
}

local function has_period(goals, wanted)
    for _i, period in ipairs(goals.periods) do
        if period == wanted then return true end
    end
    return false
end

function M.normalize(goals)
    if type(goals) ~= "table" then goals = {} end
    local legacy_metric = goals.metric == "time" and "time" or "pages"
    local valid, periods, seen = {}, {}, {}
    for _i, item in ipairs(PERIODS) do valid[item.id] = true end
    for _i, period in ipairs(type(goals.periods) == "table" and goals.periods or {}) do
        if valid[period] and not seen[period] then
            periods[#periods + 1] = period
            seen[period] = true
        end
    end
    if #periods == 0 then periods[1] = goals.period == "weekly" and "weekly" or "daily" end
    goals.periods = periods
    if type(goals.metrics) ~= "table" then goals.metrics = {} end
    for _i, period in ipairs(PERIODS) do
        if goals.metrics[period.id] ~= "time" and goals.metrics[period.id] ~= "pages" then
            goals.metrics[period.id] = legacy_metric
        end
        for _j, target in ipairs({ period.pages, period.time }) do
            if type(goals[target.key]) ~= "number" then goals[target.key] = target.default end
        end
    end
    return goals
end

function M.settingsItems(goals, save)
    goals = M.normalize(goals)
    local items = {}
    for _i, item in ipairs(PERIODS) do
        local period = item
        items[#items + 1] = {
            text = period.text,
            sub_item_table_func = function()
                local function set_metric(metric)
                    goals.metrics[period.id] = metric
                    save()
                end
                local function target_item(target)
                    local is_time = target == period.time
                    local title = is_time
                        and string.format(_("%s time goal (min)"), period.text)
                        or string.format(_("%s pages goal"), period.text)
                    local label = title .. ": "
                    return {
                        text_func = function()
                            return label .. tostring(goals[target.key] or target.default)
                        end,
                        keep_menu_open = true,
                        callback = function()
                            local SpinWidget = require("ui/widget/spinwidget")
                            UIManager:show(SpinWidget:new{
                                title_text = title,
                                value = goals[target.key] or target.default,
                                value_min = 1,
                                value_max = target.max,
                                callback = function(spin)
                                    goals[target.key] = spin.value
                                    save()
                                end,
                            })
                        end,
                    }
                end
                return {
                    {
                        text = _("Show goal"),
                        checked_func = function() return has_period(goals, period.id) end,
                        callback = function()
                            for i, selected in ipairs(goals.periods) do
                                if selected == period.id then
                                    if #goals.periods > 1 then
                                        table.remove(goals.periods, i)
                                        save()
                                    end
                                    return
                                end
                            end
                            goals.periods[#goals.periods + 1] = period.id
                            save()
                        end,
                    },
                    {
                        text = _("Pages"),
                        radio = true,
                        checked_func = function() return goals.metrics[period.id] == "pages" end,
                        callback = function() set_metric("pages") end,
                    },
                    {
                        text = _("Time"),
                        radio = true,
                        checked_func = function() return goals.metrics[period.id] == "time" end,
                        callback = function() set_metric("time") end,
                    },
                    target_item(period.pages),
                    target_item(period.time),
                }
            end,
        }
    end
    return items
end

function M.metricFor(goals, period)
    goals = M.normalize(goals)
    return goals.metrics[period] == "time" and "time" or "pages"
end

return M

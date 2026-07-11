local _ = require("gettext")
local StatsSettings = require("modules/filebrowser/patches/stats_settings")

local M = {}

local function label_for(id)
    local labels = {
        today = _("Today"),
        this_week = _("This Week"),
        this_month = _("This Month"),
        this_year = _("This Year"),
        all_time = _("All Time"),
        personal_records = _("Personal Records"),
        library = _("Library"),
        current_book = _("Current Book"),
        trend_graph = _("Reading Trend"),
        goal_progress = _("Goal Progress"),
        calendar = _("Reading Calendar"),
    }
    return labels[id] or tostring(id)
end

local function refresh_active_page()
    local StatsPage = require("modules/filebrowser/patches/stats_page")
    if StatsPage.rebuildActive then StatsPage.rebuildActive() end
end

function M.build(_ctx)
    local function save(settings)
        StatsSettings.save(settings)
        refresh_active_page()
    end

    local function graph_items(settings)
        local graph = settings.widgets.options.trend_graph
        return {
            {
                text = _("Metric"),
                sub_item_table = {
                    {
                        text = _("Pages"),
                        radio = true,
                        checked_func = function() return graph.metric ~= "time" end,
                        callback = function() graph.metric = "pages"; save(settings) end,
                    },
                    {
                        text = _("Time"),
                        radio = true,
                        checked_func = function() return graph.metric == "time" end,
                        callback = function() graph.metric = "time"; save(settings) end,
                    },
                },
            },
            {
                text = _("Range"),
                sub_item_table_func = function()
                    local items = {}
                    for _i, range in ipairs({ 7, 14, 30, 90 }) do
                        local item_range = range
                        items[#items + 1] = {
                            text = tostring(item_range) .. _(" days"),
                            radio = true,
                            checked_func = function() return graph.range_days == item_range end,
                            callback = function() graph.range_days = item_range; save(settings) end,
                        }
                    end
                    return items
                end,
            },
        }
    end

    local function arrange_widgets()
        local settings = StatsSettings.load()
        local widgets = settings.widgets
        local sort_items = {}
        local function used_slots(except_id)
            local slots = 0
            for _i, id in ipairs(widgets.order) do
                if id ~= except_id and widgets.enabled[id] then
                    slots = slots + StatsSettings.widgetSlots(id)
                end
            end
            return slots
        end
        local function should_dim(id)
            return not widgets.enabled[id]
                and used_slots(id) + StatsSettings.widgetSlots(id) > StatsSettings.MAX_WIDGET_SLOTS
        end
        local function update_dims()
            for _i, item in ipairs(sort_items) do item.dim = should_dim(item.orig_item) end
        end
        for _i, id in ipairs(widgets.order) do
            local item_id = id
            local item = {
                text = label_for(item_id),
                orig_item = item_id,
                dim = should_dim(item_id),
                checked_func = function() return widgets.enabled[item_id] == true end,
                callback = function()
                    if widgets.enabled[item_id] then
                        if used_slots(item_id) <= 0 then return end
                        widgets.enabled[item_id] = false
                    elseif used_slots(item_id) + StatsSettings.widgetSlots(item_id) <= StatsSettings.MAX_WIDGET_SLOTS then
                        widgets.enabled[item_id] = true
                    else
                        return
                    end
                    save(settings)
                    update_dims()
                end,
            }
            if item_id == "trend_graph" then
                item.sub_title = label_for(item_id)
                item.sub_item_table_func = function() return graph_items(settings) end
            end
            sort_items[#sort_items + 1] = item
        end
        require("common/ui/zen_arrange_list").show{
            title = _("Widgets"),
            item_table = sort_items,
            callback = function()
                local order = {}
                for _i, item in ipairs(sort_items) do order[#order + 1] = item.orig_item end
                widgets.order = order
                save(settings)
            end,
        }
    end

    local function style_items()
        local settings = StatsSettings.load()
        local items = {}
        for _i, item in ipairs({
            { id = "divider", text = _("Divider") },
            { id = "outline", text = _("Outline") },
            { id = "none", text = _("None") },
        }) do
            local style = item.id
            items[#items + 1] = {
                text = item.text,
                radio = true,
                checked_func = function() return settings.stat_style == style end,
                callback = function() settings.stat_style = style; save(settings) end,
            }
        end
        return items
    end

    return {
        text = _("Stats"),
        sub_item_table = {
            {
                text = _("Widgets") .. " \u{25B8}",
                keep_menu_open = true,
                callback = arrange_widgets,
            },
            {
                text = _("Stat separators"),
                sub_item_table_func = style_items,
            },
        },
    }
end

return M

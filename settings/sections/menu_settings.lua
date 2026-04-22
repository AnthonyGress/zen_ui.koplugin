-- settings/sections/menu.lua
-- Touch menu settings items for Zen UI (Quick Settings panel).
-- Receives ctx: { plugin, config, save_and_apply }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local utils = require("settings/zen_settings_utils")

local M = {}

function M.build(ctx)
    local config = ctx.config
    local save_and_apply = ctx.save_and_apply

    local function save_and_apply_quick_settings() save_and_apply("quick_settings") end

    local function make_enable_feature_item(feature, text)
        return utils.make_enable_feature_item(feature, text, config, save_and_apply)
    end

    local quick_button_items = {
        { key = "wifi",        text = _("Wi-Fi")          },
        { key = "night",       text = _("Night mode")     },
        { key = "zen",         text = _("Zen mode")       },
        { key = "lockdown",    text = _("Lockdown")        },
        { key = "rotate",      text = _("Rotate")         },
        { key = "usb",         text = _("USB")            },
        { key = "search",      text = _("File search")    },
        { key = "quickrss",    text = _("QuickRSS")       },
        { key = "cloud",       text = _("Cloud storage")  },
        { key = "zlibrary",    text = _("Z-Library")      },
        { key = "calibre",     text = _("Calibre")        },
        { key = "notion",      text = _("Notion")         },
        { key = "streak",      text = _("Streak")         },
        { key = "opds",        text = _("OPDS")           },
        { key = "filebrowser", text = _("Filebrowser")    },
        { key = "restart",     text = _("Restart")        },
        { key = "exit",        text = _("Exit")           },
        { key = "sleep",       text = _("Sleep")          },
    }

    local quick_button_label_by_id = {}
    for _, quick_item in ipairs(quick_button_items) do
        quick_button_label_by_id[quick_item.key] = quick_item.text
    end

    local quick_buttons_max = 9

    -- only count buttons that are actually toggleable in the UI
    local quick_button_key_set = {}
    for _, item in ipairs(quick_button_items) do
        quick_button_key_set[item.key] = true
    end

    local function countEnabledButtons()
        local count = 0
        for key, v in pairs(config.quick_settings.show_buttons) do
            if v == true and quick_button_key_set[key] then count = count + 1 end
        end
        return count
    end

    local quick_button_sub_items = {}

    table.insert(quick_button_sub_items, {
        text = _("Arrange buttons"),
        keep_menu_open = true,
        separator = true,
        callback = function()
            local SortWidget = require("ui/widget/sortwidget")
            local sort_items = {}
            for _, id in ipairs(config.quick_settings.button_order) do
                local label = quick_button_label_by_id[id]
                if label then
                    table.insert(sort_items, {
                        text = label,
                        orig_item = id,
                        dim = not (config.quick_settings.show_buttons[id] == true),
                    })
                end
            end
            UIManager:show(SortWidget:new{
                title = _("Arrange quick settings buttons"),
                item_table = sort_items,
                callback = function()
                    for i, item in ipairs(sort_items) do
                        config.quick_settings.button_order[i] = item.orig_item
                    end
                    save_and_apply_quick_settings()
                end,
            })
        end,
    })

    for _, quick_item in ipairs(quick_button_items) do
        local key = quick_item.key
        table.insert(quick_button_sub_items, {
            text = quick_item.text,
            checked_func = function()
                return config.quick_settings.show_buttons[key] == true
            end,
            enabled_func = function()
                return config.quick_settings.show_buttons[key] == true
                    or countEnabledButtons() < quick_buttons_max
            end,
            callback = function()
                config.quick_settings.show_buttons[key] = not (config.quick_settings.show_buttons[key] == true)
                save_and_apply_quick_settings()
            end,
        })
    end

    return {
        text = _("Quick Settings"),
        sub_item_table = {
            {
                text = _("Buttons"),
                sub_item_table = quick_button_sub_items,
            },
            {
                text = _("Show brightness slider"),
                checked_func = function() return config.quick_settings.show_frontlight == true end,
                callback = function()
                    config.quick_settings.show_frontlight = not (config.quick_settings.show_frontlight == true)
                    save_and_apply_quick_settings()
                end,
            },
            {
                text = _("Show warmth slider"),
                checked_func = function() return config.quick_settings.show_warmth == true end,
                callback = function()
                    config.quick_settings.show_warmth = not (config.quick_settings.show_warmth == true)
                    save_and_apply_quick_settings()
                end,
            },
        },
    }
end

return M

-- settings/sections/library/status_bar.lua
-- Status bar settings item for Zen UI.
-- Returns a single menu-item table: { text = _("Status bar"), sub_item_table = {...} }
-- Receives ctx: { config, save_and_apply }

local _ = require("gettext")
local UIManager = require("ui/uimanager")
local utils = require("settings/zen_settings_utils")

local M = {}

function M.build(ctx)
    local config        = ctx.config
    local save_and_apply = ctx.save_and_apply

    local function save_and_apply_status_bar() save_and_apply("status_bar") end

    local function make_enable_feature_item(feature, text)
        return utils.make_enable_feature_item(feature, text, config, save_and_apply)
    end

    -- -------------------------------------------------------------------------
    -- Slot items (deduplicates left / center / right)
    -- -------------------------------------------------------------------------

    local status_bar_all_items = {
        { key = "wifi",        text = _("Wi-Fi")       },
        { key = "disk",        text = _("Disk space")  },
        { key = "ram",         text = _("RAM usage")   },
        { key = "frontlight",  text = _("Brightness")  },
        { key = "battery",     text = _("Battery")     },
        { key = "time",        text = _("Time")        },
        { key = "custom_text", text = _("Custom text") },
    }

    local function make_status_bar_slot_items(slot_name, arrange_title)
        local order_key = slot_name .. "_order"
        local other_keys = {}
        for _, s in ipairs({ "left", "center", "right" }) do
            if s ~= slot_name then
                table.insert(other_keys, s .. "_order")
            end
        end

        local t = {
            {
                text = _("Arrange"),
                keep_menu_open = true,
                separator = true,
                callback = function()
                    local SortWidget = require("ui/widget/sortwidget")
                    local lbl = {}
                    for _, d in ipairs(status_bar_all_items) do lbl[d.key] = d.text end
                    local sort_items = {}
                    for _, key in ipairs(config.status_bar[order_key] or {}) do
                        if lbl[key] then
                            table.insert(sort_items, { text = lbl[key], orig_item = key })
                        end
                    end
                    UIManager:show(SortWidget:new{
                        title = arrange_title,
                        item_table = sort_items,
                        callback = function()
                            local new_order = {}
                            for _, item in ipairs(sort_items) do
                                table.insert(new_order, item.orig_item)
                            end
                            config.status_bar[order_key] = new_order
                            save_and_apply_status_bar()
                        end,
                    })
                end,
            },
        }

        for _, def in ipairs(status_bar_all_items) do
            local key = def.key
            table.insert(t, {
                text = def.text,
                checked_func = function()
                    for _, k in ipairs(config.status_bar[order_key] or {}) do
                        if k == key then return true end
                    end
                    return false
                end,
                callback = function()
                    local this_order = config.status_bar[order_key] or {}
                    local found = false
                    local new_this = {}
                    for _, k in ipairs(this_order) do
                        if k == key then found = true else table.insert(new_this, k) end
                    end
                    if found then
                        config.status_bar[order_key] = new_this
                    else
                        for _, other_key in ipairs(other_keys) do
                            local new_other = {}
                            for _, k in ipairs(config.status_bar[other_key] or {}) do
                                if k ~= key then table.insert(new_other, k) end
                            end
                            config.status_bar[other_key] = new_other
                        end
                        table.insert(this_order, key)
                        config.status_bar[order_key] = this_order
                    end
                    save_and_apply_status_bar()
                end,
            })
        end
        return t
    end

    -- -------------------------------------------------------------------------
    -- Status bar item
    -- -------------------------------------------------------------------------

    return {
        text = _("Status bar"),
        sub_item_table = {
            make_enable_feature_item("status_bar", _("Enable custom status bar")),
            {
                text_func = function()
                    local name = config.status_bar.custom_text
                    if name == nil or name == "" then
                        name = require("device").model or ""
                    end
                    return _("Custom text: ") .. name
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local InputDialog = require("ui/widget/inputdialog")
                    local Device = require("device")
                    local dlg
                    dlg = InputDialog:new{
                        title = _("Custom text"),
                        input = config.status_bar.custom_text or "",
                        hint = Device.model or "",
                        buttons = {{
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function() UIManager:close(dlg) end,
                            },
                            {
                                text = _("Set"),
                                is_enter_default = true,
                                callback = function()
                                    config.status_bar.custom_text = dlg:getInputText()
                                    UIManager:close(dlg)
                                    save_and_apply_status_bar()
                                    if touchmenu_instance then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            },
                        }},
                    }
                    UIManager:show(dlg)
                    dlg:onShowKeyboard()
                end,
            },
            {
                text = _("Show bottom border"),
                checked_func = function() return config.status_bar.show_bottom_border == true end,
                callback = function()
                    config.status_bar.show_bottom_border = not (config.status_bar.show_bottom_border == true)
                    save_and_apply_status_bar()
                end,
            },
            {
                text = _("Bold text"),
                checked_func = function() return config.status_bar.bold_text == true end,
                callback = function()
                    config.status_bar.bold_text = not (config.status_bar.bold_text == true)
                    save_and_apply_status_bar()
                end,
            },
            {
                text = _("Colored status icons"),
                checked_func = function() return config.status_bar.colored == true end,
                callback = function()
                    config.status_bar.colored = not (config.status_bar.colored == true)
                    save_and_apply_status_bar()
                end,
            },
            {
                text = _("Left items"),
                sub_item_table = make_status_bar_slot_items("left", _("Arrange left items")),
            },
            {
                text = _("Center items"),
                sub_item_table = make_status_bar_slot_items("center", _("Arrange center items")),
            },
            {
                text = _("Right items"),
                sub_item_table = make_status_bar_slot_items("right", _("Arrange right items")),
            },
            {
                text_func = function()
                    local separator_label = {
                        dot             = _("Middle dot"),
                        bar             = _("Vertical bar"),
                        dash            = _("Dash"),
                        bullet          = _("Bullet"),
                        space           = _("Space only"),
                        ["small-space"] = _("Space only (small)"),
                        none            = _("No separator"),
                        custom          = _("Custom"),
                    }
                    local key = config.status_bar.separator_key or "dot"
                    return _("Separator: ") .. (separator_label[key] or key)
                end,
                sub_item_table = {
                    {
                        text = _("Middle dot") .. "  '  ·  '",
                        checked_func = function() return config.status_bar.separator_key == "dot" end,
                        callback = function()
                            config.status_bar.separator_key = "dot"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Vertical bar") .. "  '  |  '",
                        checked_func = function() return config.status_bar.separator_key == "bar" end,
                        callback = function()
                            config.status_bar.separator_key = "bar"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Dash") .. "  '  -  '",
                        checked_func = function() return config.status_bar.separator_key == "dash" end,
                        callback = function()
                            config.status_bar.separator_key = "dash"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Bullet") .. "  '  •  '",
                        checked_func = function() return config.status_bar.separator_key == "bullet" end,
                        callback = function()
                            config.status_bar.separator_key = "bullet"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Space only") .. "  '   '",
                        checked_func = function() return config.status_bar.separator_key == "space" end,
                        callback = function()
                            config.status_bar.separator_key = "space"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("Space only (small)") .. "  ' '",
                        checked_func = function() return config.status_bar.separator_key == "small-space" end,
                        callback = function()
                            config.status_bar.separator_key = "small-space"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text = _("No separator"),
                        checked_func = function() return config.status_bar.separator_key == "none" end,
                        callback = function()
                            config.status_bar.separator_key = "none"
                            save_and_apply_status_bar()
                        end,
                    },
                    {
                        text_func = function()
                            return _("Custom") .. "  '" .. (config.status_bar.custom_separator or "") .. "'"
                        end,
                        checked_func = function() return config.status_bar.separator_key == "custom" end,
                        callback = function(touchmenu_instance)
                            local InputDialog = require("ui/widget/inputdialog")
                            local dlg
                            dlg = InputDialog:new{
                                title = _("Custom separator"),
                                input = config.status_bar.custom_separator or "",
                                buttons = {{
                                    {
                                        text = _("Cancel"),
                                        id = "close",
                                        callback = function() UIManager:close(dlg) end,
                                    },
                                    {
                                        text = _("Set"),
                                        is_enter_default = true,
                                        callback = function()
                                            config.status_bar.custom_separator = dlg:getInputText()
                                            config.status_bar.separator_key = "custom"
                                            UIManager:close(dlg)
                                            save_and_apply_status_bar()
                                            if touchmenu_instance then
                                                touchmenu_instance:updateItems()
                                            end
                                        end,
                                    },
                                }},
                            }
                            UIManager:show(dlg)
                            dlg:onShowKeyboard()
                        end,
                    },
                },
            },
        },
    }
end

return M

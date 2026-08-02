local _ = require("gettext")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local icons = require("common/inline_icon_map")
local IconItem = require("common/ui/icon_menu_item")
local icon_utils = require("common/utils")

local Model = require("modules/menu/app_launcher/model")
local PluginScan = require("modules/menu/app_launcher/plugin_scan")

local M = {}
local DEFAULT_ENTRY_ICON = "lightning"
local DEFAULT_FOLDER_ICON = "folder_open"

local function suggest_icon(label, strip_zen_prefix)
    local ok_root, root = pcall(require, "common/plugin_root")
    return icon_utils.suggestIcon(ok_root and root or nil, label, DEFAULT_ENTRY_ICON, strip_zen_prefix)
end

local function trim(text)
    return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.build(ctx)
    local config = ctx.config
    local save_and_apply = ctx.save_and_apply
    local cfg = Model.ensure(config)
    local build_entry_items
    local show_entries_arrange
    local sync_action_label

    local function save_app_launcher()
        Model.save(cfg)
        if ctx.apply_feature then
            ctx.apply_feature("app_launcher")
        else
            save_and_apply("app_launcher")
        end
    end

    local function is_draft_entry(entry)
        return type(entry) == "table" and type(entry._zen_draft_commit) == "function"
    end

    local function open_entry_settings(touch_menu, entry, parent)
        if not (touch_menu and type(touch_menu.updateItems) == "function" and entry) then
            return
        end
        table.insert(touch_menu.item_table_stack, touch_menu.item_table)
        touch_menu.parent_id = nil
        touch_menu.item_table = build_entry_items(entry, parent)
        touch_menu:updateItems(1)
    end

    local ok_disp, Dispatcher = pcall(require, "dispatcher")

    local function wrap_dispatch_callbacks(items, caller, on_update)
        if type(items) ~= "table" then return end
        for _i, item in ipairs(items) do
            if type(item.callback) == "function" and not item._zen_launcher_dispatch_wrapped then
                local orig_callback = item.callback
                item.callback = function(touch_menu, ...)
                    caller.updated = false
                    local result = orig_callback(touch_menu, ...)
                    if caller.updated then
                        caller.updated = false
                        on_update(touch_menu)
                    end
                    return result
                end
                item._zen_launcher_dispatch_wrapped = true
            end
            if type(item.hold_callback) == "function" and not item._zen_launcher_dispatch_hold_wrapped then
                local orig_hold_callback = item.hold_callback
                item.hold_callback = function(touch_menu, ...)
                    caller.updated = false
                    local result = orig_hold_callback(touch_menu, ...)
                    if caller.updated then
                        caller.updated = false
                        on_update(touch_menu)
                    end
                    return result
                end
                item._zen_launcher_dispatch_hold_wrapped = true
            end
            if type(item.sub_item_table_func) == "function" and not item._zen_launcher_dispatch_func_wrapped then
                local orig_sub_item_table_func = item.sub_item_table_func
                item.sub_item_table_func = function(...)
                    local sub_items = orig_sub_item_table_func(...)
                    wrap_dispatch_callbacks(sub_items, caller, on_update)
                    return sub_items
                end
                item._zen_launcher_dispatch_func_wrapped = true
            end
            wrap_dispatch_callbacks(item.sub_item_table, caller, on_update)
        end
    end

    local ICONS
    local function get_icons()
        if ICONS then return ICONS end
        local ok_root, root = pcall(require, "common/plugin_root")
        ICONS = icon_utils.getIconPickerList(ok_root and root or nil, {
            zen_ui_light = true,
            zen_ui_update = true,
        })
        return ICONS
    end

    local function show_icon_picker(entry, touch_menu)
        require("common/ui/zen_icon_picker")(get_icons(), entry.icon, function(name)
            entry.icon = name
            if not is_draft_entry(entry) then
                save_app_launcher()
            end
            if touch_menu and touch_menu.updateItems then
                touch_menu:updateItems(1)
            end
        end)
    end

    local function action_label(entry)
        if ok_disp and entry.action and next(entry.action) then
            local text = Dispatcher:menuTextFunc(entry.action)
            if text and text ~= "" and text ~= _("Nothing") then
                return text
            end
        end
        return nil
    end

    local function has_valid_target(entry)
        if entry.type == "action" then
            return type(entry.action) == "table" and next(entry.action) ~= nil
        end
        if entry.type == "quick_setting" then
            return type(entry.quick_setting_id) == "string" and entry.quick_setting_id ~= ""
        end
        return entry.type == "plugin"
            and type(entry.plugin) == "table"
            and entry.plugin.key ~= nil
            and entry.plugin.method ~= nil
    end

    local function add_done_metadata(items, entry)
        items._zen_arrange_done_func = function()
            if entry.type == "action" then
                sync_action_label(entry)
            end
            if is_draft_entry(entry) then
                entry._zen_draft_commit()
            elseif has_valid_target(entry) then
                save_app_launcher()
            end
        end
        items._zen_arrange_done_enabled_func = function()
            return has_valid_target(entry)
        end
    end

    sync_action_label = function(entry)
        if entry.type ~= "action" then return end
        local current = entry.label or ""
        if entry.label_auto == true or current == "" or current == _("Action") then
            entry.label = action_label(entry) or _("Action")
            entry.label_auto = true
        end
        if entry.icon == DEFAULT_ENTRY_ICON then
            entry.icon = suggest_icon(entry.label, true)
        end
    end

    local function prompt_label(entry, title, touch_menu)
        local InputDialog = require("ui/widget/inputdialog")
        local dialog
        dialog = InputDialog:new{
            title = title,
            input = entry.label or "",
            input_hint = entry.type == "action" and _("Leave empty to use action title") or nil,
            buttons = {{
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Set"),
                    is_enter_default = true,
                    callback = function()
                        local label = trim(dialog:getInputText())
                        if label ~= "" then
                            entry.label = label
                            entry.label_auto = false
                            if not is_draft_entry(entry) then
                                save_app_launcher()
                            end
                        elseif entry.type == "action" then
                            entry.label_auto = true
                            sync_action_label(entry)
                            if not is_draft_entry(entry) then
                                save_app_launcher()
                            end
                        end
                        UIManager:close(dialog)
                        if touch_menu and touch_menu.updateItems then
                            touch_menu:updateItems(1)
                        end
                    end,
                },
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    local function insert_entry(entry, folder)
        if folder then
            folder.children = folder.children or {}
            folder.children[#folder.children + 1] = entry
        else
            cfg.entries[#cfg.entries + 1] = entry
        end
        save_app_launcher()
    end

    local function current_list(parent)
        if parent then
            if type(parent.children) ~= "table" then
                parent.children = {}
            end
            return parent.children
        end
        if type(cfg.entries) ~= "table" then
            cfg.entries = {}
        end
        return cfg.entries
    end

    local function entry_exists_in_list(list, entry)
        if not (list and entry and entry.id) then return false end
        for _i, candidate in ipairs(list) do
            if candidate.id == entry.id then
                return true
            end
        end
        return false
    end

    local function new_action_entry(label, draft)
        return {
            id = draft and nil or Model.next_id(cfg),
            type = "action",
            label = label or _("Action"),
            label_auto = true,
            icon = DEFAULT_ENTRY_ICON,
            action = {},
        }
    end

    local function add_folder(touch_menu)
        local InputDialog = require("ui/widget/inputdialog")
        local dialog
        dialog = InputDialog:new{
            title = _("New folder"),
            input = "",
            buttons = {{
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Add"),
                    is_enter_default = true,
                    callback = function()
                        local label = trim(dialog:getInputText())
                        UIManager:close(dialog)
                        if label == "" then return end
                        local entry = {
                            id = Model.next_id(cfg),
                            type = "folder",
                            label = label,
                            icon = DEFAULT_FOLDER_ICON,
                            children = {},
                        }
                        insert_entry(entry)
                        UIManager:nextTick(function()
                            open_entry_settings(touch_menu, entry, nil)
                        end)
                    end,
                },
            }},
        }
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    local function add_plugin(folder, touch_menu)
        local found = PluginScan.scan()
        if #found == 0 then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("No launchable plugin menus found") })
            return
        end
        local picker_items = {}
        for _i, plugin in ipairs(found) do
            picker_items[#picker_items + 1] = {
                text = plugin.title,
                plugin = plugin,
            }
        end
        local show_menu_picker = require("common/ui/zen_menu_picker")
        show_menu_picker{
            title = _("Choose plugin menu"),
            items = picker_items,
            on_select = function(item)
                local plugin = item.plugin
                local entry = {
                    id = Model.next_id(cfg),
                    type = "plugin",
                    label = plugin.title,
                    icon = suggest_icon(plugin.title),
                    plugin = { key = plugin.key, method = plugin.method },
                }
                insert_entry(entry, folder)
                UIManager:nextTick(function()
                    open_entry_settings(touch_menu, entry, folder)
                end)
            end,
        }
    end

    local function choose_plugin_entry(entry, touch_menu)
        local found = PluginScan.scan()
        if #found == 0 then
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{ text = _("No launchable plugin menus found") })
            return
        end
        local picker_items = {}
        for _i, plugin in ipairs(found) do
            picker_items[#picker_items + 1] = {
                text = plugin.title,
                plugin = plugin,
            }
        end
        local show_menu_picker = require("common/ui/zen_menu_picker")
        show_menu_picker{
            title = _("Choose plugin menu"),
            items = picker_items,
            on_select = function(item)
                local plugin = item.plugin
                entry.type = "plugin"
                entry.plugin = { key = plugin.key, method = plugin.method }
                entry.label = plugin.title
                save_app_launcher()
                if touch_menu and touch_menu.updateItems then
                    touch_menu:updateItems(1)
                end
            end,
        }
    end

    local function open_new_action_picker(folder, touch_menu)
        if not ok_disp then return end
        local entry = new_action_entry(nil, true)
        local committed = false
        local function commit()
            if committed or not (entry.action and next(entry.action)) then return end
            sync_action_label(entry)
            entry.id = Model.next_id(cfg)
            entry._zen_draft_commit = nil
            insert_entry(entry, folder)
            committed = true
        end
        entry._zen_draft_commit = commit
        open_entry_settings(touch_menu, entry, folder)
    end

    local function show_quick_setting_picker(on_select)
        local controls = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")
        if not controls or type(controls.getItems) ~= "function" then return end
        local picker_items = controls.getItems()
        if #picker_items == 0 then return end
        require("common/ui/zen_menu_picker"){
            title = _("Choose control"),
            items = picker_items,
            on_select = on_select,
        }
    end

    local function choose_quick_setting_entry(entry, touch_menu)
        show_quick_setting_picker(function(item)
            entry.quick_setting_id = item.id
            entry.label = item.label
            entry.icon = item.icon or suggest_icon(item.label)
            save_app_launcher()
            if touch_menu and touch_menu.updateItems then
                touch_menu:updateItems(1)
            end
        end)
    end

    local function add_quick_setting(folder, touch_menu)
        show_quick_setting_picker(function(item)
                local entry = {
                    id = Model.next_id(cfg),
                    type = "quick_setting",
                    label = item.label,
                    icon = item.icon or suggest_icon(item.label),
                    quick_setting_id = item.id,
                }
                insert_entry(entry, folder)
                UIManager:nextTick(function()
                    open_entry_settings(touch_menu, entry, folder)
                end)
        end)
    end

    local function add_items(folder)
        return {
            IconItem.decorate({
                text = _("Add action"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    open_new_action_picker(folder, touch_menu)
                end,
            }, icons.action),
            IconItem.decorate({
                text = _("Add control"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    add_quick_setting(folder, touch_menu)
                end,
            }, icons.settings_quick),
            IconItem.decorate({
                text = _("Add plugin"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    add_plugin(folder, touch_menu)
                end,
            }, icons.plugin),
        }
    end

    local function arrange_add_items(folder)
        local items = {
            IconItem.decorate({
                text = _("Action"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    open_new_action_picker(folder, touch_menu)
                end,
            }, icons.action),
            IconItem.decorate({
                text = _("Control"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    add_quick_setting(folder, touch_menu)
                end,
            }, icons.settings_quick),
            IconItem.decorate({
                text = _("Plugin"),
                keep_menu_open = true,
                callback = function(touch_menu)
                    add_plugin(folder, touch_menu)
                end,
            }, icons.plugin),
        }
        if not folder then
            items[#items + 1] = IconItem.decorate({
                text = _("Folder"),
                keep_menu_open = true,
                callback = add_folder,
            }, icons.new_folder)
        end
        items[#items + 1] = IconItem.decorate({
            text = _("Row break"),
            keep_menu_open = true,
            callback = function(touch_menu)
                local entry = {
                    id = Model.next_id(cfg),
                    type = "break",
                }
                insert_entry(entry, folder)
                if touch_menu then touch_menu:backToUpperMenu() end
            end,
        }, icons.move)
        return items
    end

    local function build_action_picker(entry)
        if not ok_disp then return nil end
        local dispatch_items = {}
        local caller = {}
        Dispatcher:addSubMenu(caller, dispatch_items, entry, "action")
        wrap_dispatch_callbacks(dispatch_items, caller, function(touch_menu)
            sync_action_label(entry)
            if is_draft_entry(entry) then
                entry._zen_draft_commit()
            else
                save_app_launcher()
            end
            if touch_menu and touch_menu.updateItems then
                touch_menu:updateItems(1)
            end
        end)
        return IconItem.decorate({
            text_func = function()
                if entry.action and next(entry.action) then
                    return T(_("Action: %1"), Dispatcher:menuTextFunc(entry.action))
                end
                return _("Action: (none)")
            end,
            keep_menu_open = true,
            sub_item_table = dispatch_items,
        }, icons.action)
    end

    local function build_move_items(entry, parent)
        local items = {}
        if entry.type ~= "folder" then
            local folder_choices = {}
            for _i, candidate in ipairs(cfg.entries) do
                if candidate.type == "folder" and not (parent and candidate.id == parent.id) then
                    folder_choices[#folder_choices + 1] = candidate
                end
            end
            if parent then
                items[#items + 1] = IconItem.decorate({
                    text = _("Move out of folder"),
                    callback = function(touch_menu)
                        if Model.move_to_root(cfg.entries, entry.id) then
                            save_app_launcher()
                            if touch_menu then touch_menu:backToUpperMenu() end
                        end
                    end,
                }, icons.move)
            end
            if #folder_choices > 0 then
                items[#items + 1] = IconItem.decorate({
                    text = _("Move to folder"),
                    keep_menu_open = true,
                    callback = function(touch_menu)
                        local ButtonDialog = require("ui/widget/buttondialog")
                        local dialog
                        local buttons = {}
                        for _i, folder in ipairs(folder_choices) do
                            local folder_id = folder.id
                            buttons[#buttons + 1] = {{
                                text = folder.label,
                                callback = function()
                                    UIManager:close(dialog)
                                    if Model.move_to_folder(cfg.entries, entry.id, folder_id) then
                                        save_app_launcher()
                                        if touch_menu then touch_menu:backToUpperMenu() end
                                    end
                                end,
                            }}
                        end
                        dialog = ButtonDialog:new{
                            title = _("Move to folder"),
                            title_align = "center",
                            width_factor = 0.85,
                            buttons = buttons,
                        }
                        UIManager:show(dialog)
                    end,
                }, icons.move)
            end
        end
        return items
    end

    build_entry_items = function(entry, parent)
        local items = {}
        local function add_icon_item()
            items[#items + 1] = IconItem.decorate({
                text_func = function()
                    return T(_("Icon: %1"), entry.icon or DEFAULT_ENTRY_ICON)
                end,
                keep_menu_open = true,
                callback = function(touch_menu)
                    show_icon_picker(entry, touch_menu)
                end,
            }, icons.icon)
        end
        local function add_label_item()
            items[#items + 1] = IconItem.decorate({
                text_func = function()
                    return T(_("Label: %1"), entry.label)
                end,
                keep_menu_open = true,
                callback = function(touch_menu)
                    prompt_label(entry, _("Launcher label"), touch_menu)
                end,
            }, icons.label)
        end
        if entry.type == "action" then
            local picker = build_action_picker(entry)
            if picker then items[#items + 1] = picker end
            add_icon_item()
            add_label_item()
        elseif entry.type == "folder" then
            add_label_item()
            add_icon_item()
            items[#items + 1] = IconItem.decorate({
                text = _("Folder buttons"),
                keep_menu_open = true,
                callback = function()
                    show_entries_arrange(entry)
                end,
            }, icons.folder_open)
            local add_sub = add_items(entry)
            for _i, item in ipairs(add_sub) do
                items[#items + 1] = item
            end
        elseif entry.type == "quick_setting" then
            items[#items + 1] = IconItem.decorate({
                text_func = function()
                    return T(_("Control: %1"), entry.label or _("(none)"))
                end,
                keep_menu_open = true,
                callback = function(touch_menu)
                    choose_quick_setting_entry(entry, touch_menu)
                end,
            }, icons.settings_quick)
            local controls = rawget(_G, "__ZEN_UI_QUICK_SETTINGS")
            local settings_items = controls and controls.getSettingsItems
                and controls.getSettingsItems(entry.quick_setting_id)
            if settings_items and #settings_items > 0 then
                items[#items + 1] = IconItem.decorate({
                    text = _("Control settings"),
                    keep_menu_open = true,
                    sub_item_table = settings_items,
                }, icons.settings_quick)
            end
            add_label_item()
            add_icon_item()
        elseif entry.type ~= "break" then
            items[#items + 1] = IconItem.decorate({
                text_func = function()
                    return T(_("Plugin: %1"), entry.label or _("(none)"))
                end,
                keep_menu_open = true,
                callback = function(touch_menu)
                    choose_plugin_entry(entry, touch_menu)
                end,
            }, icons.plugin)
            add_label_item()
            add_icon_item()
        end
        if not is_draft_entry(entry) then
            local move_items = build_move_items(entry, parent)
            for _i, item in ipairs(move_items) do
                items[#items + 1] = item
            end
        end
        items[#items + 1] = IconItem.decorate({
            text = _("Delete"),
            separator = true,
            callback = function(touch_menu)
                if is_draft_entry(entry) then
                    if touch_menu then touch_menu:backToUpperMenu() end
                    return
                end
                local ConfirmBox = require("ui/widget/confirmbox")
                local function remove()
                    Model.remove_by_id(cfg.entries, entry.id)
                    save_app_launcher()
                    if touch_menu then touch_menu:backToUpperMenu() end
                end
                UIManager:show(ConfirmBox:new{
                    text = entry.type == "folder" and entry.children and #entry.children > 0
                            and _("Delete this folder and its buttons?")
                        or entry.type == "break" and _("Delete this row break?")
                        or _("Delete this button?"),
                    ok_text = _("Delete"),
                    ok_callback = remove,
                })
            end,
        }, icons.delete)
        if entry.type == "action" or entry.type == "plugin" or entry.type == "quick_setting" then
            add_done_metadata(items, entry)
        end
        return items
    end

    show_entries_arrange = function(parent)
        local list = current_list(parent)
        local ZenArrangeList = require("common/ui/zen_arrange_list")
        local sort_items
        local function build_sort_items()
            local items = {}
            list = current_list(parent)
            for _i, entry in ipairs(list) do
                items[#items + 1] = {
                    text_func = function()
                        return Model.display_label(entry)
                    end,
                    orig_entry = entry,
                    sub_title = Model.display_label(entry),
                    sub_item_table_func = function()
                        return build_entry_items(entry, parent)
                    end,
                    dim = entry.enabled == false,
                    checked_func = function()
                        return entry.enabled ~= false
                    end,
                    callback = function()
                        entry.enabled = entry.enabled == false and true or false
                        save_app_launcher()
                    end,
                }
            end
            sort_items = items
            return items
        end
        sort_items = build_sort_items()
        ZenArrangeList.show{
            title = (parent and parent.label or _("Buttons")) .. " (" .. _("Hold to arrange") .. ")",
            item_table = sort_items,
            add_title = _("Add"),
            add_item_table = arrange_add_items(parent),
            open_add_on_show = #sort_items == 0,
            callback = function()
                list = current_list(parent)
                local reordered = {}
                local reordered_ids = {}
                for _i, item in ipairs(sort_items) do
                    if entry_exists_in_list(list, item.orig_entry) then
                        reordered[#reordered + 1] = item.orig_entry
                        reordered_ids[item.orig_entry.id] = true
                    end
                end
                for _i, entry in ipairs(list) do
                    if entry.id and not reordered_ids[entry.id] then
                        reordered[#reordered + 1] = entry
                    end
                end
                if parent then
                    parent.children = reordered
                else
                    cfg.entries = reordered
                end
                save_app_launcher()
            end,
            refresh_func = build_sort_items,
        }
    end

    local root_items = {
        {
            text = _("Enable"),
            checked_func = function()
                return config.features.app_launcher == true
            end,
            callback = function(touch_menu)
                config.features.app_launcher = config.features.app_launcher ~= true
                save_and_apply("app_launcher")
                if touch_menu and touch_menu.closeMenu then
                    touch_menu:closeMenu()
                end
            end,
        },
        {
            text = _("Buttons") .. " \u{25B8}",
            separator = true,
            keep_menu_open = true,
            _zen_launcher_buttons = true,
            callback = function()
                show_entries_arrange(nil)
            end,
        },
        {
            text = _("Show labels"),
            checked_func = function()
                return cfg.show_labels ~= false
            end,
            callback = function(touch_menu)
                cfg.show_labels = cfg.show_labels == false
                save_app_launcher()
                if touch_menu and touch_menu.updateItems then
                    touch_menu:updateItems(1)
                end
            end,
        },
        {
            text = _("Open menu to Launcher"),
            checked_func = function()
                return cfg.open_first == true
            end,
            callback = function(touch_menu)
                cfg.open_first = cfg.open_first ~= true
                save_app_launcher()
                if touch_menu and touch_menu.updateItems then
                    touch_menu:updateItems(1)
                end
            end,
        },
        {
            text = _("Hide reader actions in library"),
            checked_func = function()
                return cfg.hide_reader_actions_in_library == true
            end,
            callback = function(touch_menu)
                cfg.hide_reader_actions_in_library = cfg.hide_reader_actions_in_library ~= true
                save_app_launcher()
                if touch_menu and touch_menu.updateItems then
                    touch_menu:updateItems(1)
                end
            end,
        },
    }
    IconItem.decorate(root_items[2], icons.action)

    return {
        text = _("Launcher"),
        sub_item_table = root_items,
    }
end

return M

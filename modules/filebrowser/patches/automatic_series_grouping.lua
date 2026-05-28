--[[
    automatic_series_grouping.lua
    Groups books in the file browser into virtual folders by metadata series name.
    Virtual folder covers are rendered by browser_folder_cover.lua (is_series_group).
]]

local function apply_automatic_series_grouping()
    local BD = require("ui/bidi")
    local FileChooser = require("ui/widget/filechooser")
    local TitleBar = require("ui/widget/titlebar")
    local logger = require("logger")
    local _ = require("gettext")

    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim or not BookInfoManager then
        logger.warn("zen-ui automatic_series_grouping: BookInfoManager not available")
        return
    end

    if FileChooser._zen_automatic_series_patched then
        return
    end
    FileChooser._zen_automatic_series_patched = true

    local Icon = {
        up = BD.mirroredUILayout() and "back.top.rtl" or "back.top",
    }

    local current_series_group = nil
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function get_plugin()
        -- __ZEN_UI_PLUGIN is only guaranteed during apply-time, so keep
        -- a stable reference for runtime checks after init.
        return zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
    end

    local function is_enabled()
        local plugin = get_plugin()
        local features = plugin and plugin.config and plugin.config.features
        if type(features) ~= "table" then
            return true
        end
        if features.automatic_series_grouping == nil then
            return true
        end
        return features.automatic_series_grouping == true
    end

    local function isDirectory(item)
        return item.is_directory
            or (item.attr and item.attr.mode == "directory")
            or item.mode == "directory"
    end

    local function is_hide_up_folder_enabled(file_chooser)
        if file_chooser._changeLeftIcon == nil then
            return false
        end
        local plugin = get_plugin()
        if plugin
            and type(plugin.config) == "table"
            and type(plugin.config.features) == "table"
            and plugin.config.features.browser_hide_up_folder == true
        then
            local cfg = plugin.config.browser_hide_up_folder
            return type(cfg) == "table" and cfg.hide_up_folder == true
        end
        local g_settings = rawget(_G, "G_reader_settings")
        return g_settings and g_settings:readSetting("filemanager_hide_up_folder", false)
    end

    local AutomaticSeries = {}

    local function clone_item_table(item_table)
        local copy = {}
        for i, v in ipairs(item_table) do
            copy[i] = v
        end
        for k, v in pairs(item_table) do
            if type(k) ~= "number" then
                copy[k] = v
            end
        end
        return copy
    end

    local function clear_item_table_cache(file_chooser)
        if file_chooser and file_chooser._zen_clear_item_table_cache then
            file_chooser:_zen_clear_item_table_cache()
        end
    end

    function AutomaticSeries:processItemTable(item_table, file_chooser)
        if not file_chooser or not item_table then return end
        if file_chooser.show_current_dir_for_hold then return end

        local collate, collate_id = file_chooser:getCollate()
        local reverse = G_reader_settings:isTrue("reverse_collate")
        local sort_func = file_chooser:getSortingFunction(collate, reverse)
        local mixed = G_reader_settings:isTrue("collate_mixed") and collate.can_collate_mixed
        local is_name_sort = (collate_id == "strcoll" or collate_id == "natural" or collate_id == "title")

        local series_map = {}
        local processed_list = {}
        local book_count = 0
        local non_series_book_count = 0

        for _, item in ipairs(item_table) do
            if item.is_go_up then
                table.insert(processed_list, item)
            else
                if not item.sort_percent then item.sort_percent = 0 end
                if not item.percent_finished then item.percent_finished = 0 end
                if not item.opened then item.opened = false end

                local series_handled = false

                if item.is_file and item.path then
                    book_count = book_count + 1
                    local doc_props = item.doc_props or BookInfoManager:getDocProps(item.path)
                    if doc_props and doc_props.series and doc_props.series ~= "\u{FFFF}" then
                        local series_name = doc_props.series
                        item._series_index = doc_props.series_index or 0

                        if not series_map[series_name] then
                            local group_attr = {}
                            if item.attr then
                                for k, v in pairs(item.attr) do group_attr[k] = v end
                            end
                            group_attr.mode = "directory"

                            local group_item = {
                                text = series_name,
                                is_file = false,
                                is_directory = true,
                                path = (item.path:match("(.*/)") or item.path) .. series_name,
                                is_series_group = true,
                                series_items = { item },
                                attr = group_attr,
                                mode = "directory",
                                sort_percent = item.sort_percent,
                                percent_finished = item.percent_finished,
                                opened = item.opened,
                                doc_props = item.doc_props or {
                                    series = series_name,
                                    series_index = 0,
                                    display_title = series_name,
                                },
                                suffix = item.suffix,
                            }
                            series_map[series_name] = group_item
                            table.insert(processed_list, group_item)
                            group_item._list_index = #processed_list
                        else
                            table.insert(series_map[series_name].series_items, item)
                        end
                        series_handled = true
                    else
                        non_series_book_count = non_series_book_count + 1
                    end
                end

                if not series_handled then
                    table.insert(processed_list, item)
                end
            end
        end

        local series_count = 0
        for _ in pairs(series_map) do
            series_count = series_count + 1
            if series_count > 1 then break end
        end

        if series_count == 1 and non_series_book_count == 0 and book_count > 0 then
            return
        end

        for _, group in pairs(series_map) do
            if #group.series_items == 1 then
                if group._list_index and processed_list[group._list_index] == group then
                    processed_list[group._list_index] = group.series_items[1]
                end
            else
                group.mandatory = tostring(#group.series_items) .. " \u{F016}"
                table.sort(group.series_items, function(a, b)
                    return (a._series_index or 0) < (b._series_index or 0)
                end)
            end
        end

        local final_table = {}

        if mixed then
            if is_name_sort then
                local up_item
                local to_sort = {}
                for _, item in ipairs(processed_list) do
                    if item.is_go_up then
                        up_item = item
                    else
                        table.insert(to_sort, item)
                    end
                end
                local ok, err = pcall(table.sort, to_sort, sort_func)
                if not ok then
                    logger.warn("zen-ui automatic_series_grouping: sort failed:", err)
                end
                if up_item then table.insert(final_table, up_item) end
                for _, item in ipairs(to_sort) do table.insert(final_table, item) end
            else
                final_table = processed_list
            end
        else
            local dirs = {}
            local files = {}
            local up_item

            for _, item in ipairs(processed_list) do
                if item.is_go_up then
                    up_item = item
                elseif isDirectory(item) then
                    table.insert(dirs, item)
                else
                    table.insert(files, item)
                end
            end

            local ok, err = pcall(table.sort, dirs, sort_func)
            if not ok then
                logger.warn("zen-ui automatic_series_grouping: sort failed:", err)
            end

            if up_item then table.insert(final_table, up_item) end
            for _, d in ipairs(dirs) do table.insert(final_table, d) end
            for _, f in ipairs(files) do table.insert(final_table, f) end
        end

        for k in pairs(item_table) do item_table[k] = nil end
        for i, v in ipairs(final_table) do item_table[i] = v end
    end

    function AutomaticSeries:openSeriesGroup(file_chooser, group_item)
        if not file_chooser then return end

        local items = group_item.series_items
        local parent_path = file_chooser.path

        current_series_group = {
            series_name = group_item.text,
            parent_path = parent_path,
        }

        local up_item_already_present = items[1] and items[1].is_go_up
        local hide_up_folder = is_hide_up_folder_enabled(file_chooser)

        if not up_item_already_present then
            local up_item = {
                text = BD.mirroredUILayout() and BD.ltr("../ \u{2B06}") or "\u{2B06} ../",
                is_directory = true,
                path = parent_path,
                is_go_up = true,
            }
            if not hide_up_folder then
                table.insert(items, 1, up_item)
            end
        end

        items.is_in_series_view = true
        items.parent_path = parent_path

        file_chooser:switchItemTable(nil, items, nil, nil, group_item.text)

        if hide_up_folder then
            file_chooser:_changeLeftIcon(Icon.up, function() file_chooser:onFolderUp() end)
        end
    end

    local function exitVirtualFolderIfNeeded(file_chooser)
        if file_chooser and file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            local parent_path = file_chooser.item_table.parent_path
            if parent_path then
                if current_series_group then
                    current_series_group.should_restore_focus = true
                end
                file_chooser:changeToPath(parent_path)
                return true
            end
        end
        return false
    end

    local old_setSubTitle = TitleBar.setSubTitle
    TitleBar.setSubTitle = function(self, subtitle, no_refresh)
        if current_series_group then
            return old_setSubTitle(self, current_series_group.series_name, no_refresh)
        end
        return old_setSubTitle(self, subtitle, no_refresh)
    end

    local old_updateItems = FileChooser.updateItems
    local old_onMenuSelect = FileChooser.onMenuSelect
    local old_onFolderUp = FileChooser.onFolderUp
    local old_changeToPath = FileChooser.changeToPath
    local old_refreshPath = FileChooser.refreshPath
    local old_goHome = FileChooser.goHome
    local old_switchItemTable = FileChooser.switchItemTable

    FileChooser.switchItemTable = function(file_chooser, new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
        if is_enabled() and new_item_table and not new_item_table.is_in_series_view then
            -- Never mutate genItemTableFromPath cache tables in place.
            new_item_table = clone_item_table(new_item_table)
            AutomaticSeries:processItemTable(new_item_table, file_chooser)
        end
        return old_switchItemTable(file_chooser, new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
    end

    FileChooser.goHome = function(file_chooser)
        if file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            if current_series_group then
                current_series_group.should_restore_focus = true
            end
            local parent_path = file_chooser.item_table.parent_path
            local home_dir = G_reader_settings:readSetting("home_dir") or require("device").home_dir
            if parent_path and home_dir and parent_path == home_dir then
                file_chooser:changeToPath(parent_path)
                return true
            end
        end
        return old_goHome(file_chooser)
    end

    FileChooser.refreshPath = function(file_chooser)
        if not is_enabled() then
            current_series_group = nil
            clear_item_table_cache(file_chooser)
            old_refreshPath(file_chooser)
            return
        end
        old_refreshPath(file_chooser)
        if current_series_group then
            local series_name = current_series_group.series_name
            for _, item in ipairs(file_chooser.item_table) do
                if item.is_series_group and item.text == series_name then
                    AutomaticSeries:openSeriesGroup(file_chooser, item)
                    break
                end
            end
        end
    end

    FileChooser.onFolderUp = function(file_chooser)
        if exitVirtualFolderIfNeeded(file_chooser) then
            return true
        end
        return old_onFolderUp(file_chooser)
    end

    FileChooser.onMenuSelect = function(file_chooser, item)
        if is_enabled() and item.is_series_group then
            AutomaticSeries:openSeriesGroup(file_chooser, item)
            return true
        end
        return old_onMenuSelect(file_chooser, item)
    end

    FileChooser.changeToPath = function(file_chooser, path, ...)
        if file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            local parent_path = file_chooser.item_table.parent_path
            if parent_path and path and (path:match("/%.%.") or path:match("^%.%.")) then
                path = parent_path
            end
            if current_series_group then
                current_series_group.should_restore_focus = true
            end
        else
            current_series_group = nil
        end
        return old_changeToPath(file_chooser, path, ...)
    end

    FileChooser.updateItems = function(file_chooser, ...)
        if not is_enabled() then
            current_series_group = nil
            return old_updateItems(file_chooser, ...)
        end

        if not file_chooser.item_table or #file_chooser.item_table == 0 then
            return old_updateItems(file_chooser, ...)
        end

        if file_chooser.item_table.is_in_series_view then
            return old_updateItems(file_chooser, ...)
        end

        if current_series_group and current_series_group.should_restore_focus
            and file_chooser.item_table and #file_chooser.item_table > 0 then
            for index, item in ipairs(file_chooser.item_table) do
                if item.is_series_group and item.text == current_series_group.series_name then
                    local page = math.ceil(index / file_chooser.perpage)
                    local select_number = ((index - 1) % file_chooser.perpage) + 1
                    file_chooser.page = page
                    file_chooser.path_items[file_chooser.path] = index
                    current_series_group = nil
                    return old_updateItems(file_chooser, select_number)
                end
            end
            current_series_group = nil
        end

        return old_updateItems(file_chooser, ...)
    end
end

return apply_automatic_series_grouping

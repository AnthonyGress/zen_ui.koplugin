-- Groups books in the file browser into virtual folders by metadata series name.
local function apply_automatic_series_grouping()
    local BD = require("ui/bidi")
    local Device = require("device")
    local FileChooser = require("ui/widget/filechooser")
    local TitleBar = require("ui/widget/titlebar")
    local logger = require("common/zen_logger").new("automatic_series_grouping")
    local util = require("util")

    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim or not BookInfoManager then
        logger.warn("BookInfoManager not available")
        return
    end

    if FileChooser._zen_automatic_series_patched then
        return
    end
    FileChooser._zen_automatic_series_patched = true

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local current_series_group
    local NO_SERIES = "\239\191\191"

    local function log_navigation(event, file_chooser, detail)
        local item_table = file_chooser and file_chooser.item_table
        local path = file_chooser and file_chooser.path
        local path_item = file_chooser and file_chooser.path_items
            and path and file_chooser.path_items[path]
        logger.info(
            "Navigation:", event,
            detail or "",
            "page=", tostring(file_chooser and file_chooser.page),
            "page_num=", tostring(file_chooser and file_chooser.page_num),
            "perpage=", tostring(file_chooser and file_chooser.perpage),
            "itemnumber=", tostring(file_chooser and file_chooser.itemnumber),
            "path_item=", tostring(path_item),
            "items=", tostring(item_table and #item_table),
            "series_view=", tostring(item_table and item_table.is_in_series_view),
            "display=", tostring(file_chooser
                and (file_chooser.display_mode_type or file_chooser.display_mode))
        )
    end

    local Icon = {
        up = BD.mirroredUILayout() and "back.top.rtl" or "back.top",
    }

    local function get_plugin()
        return zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
    end

    local function is_enabled()
        local plugin = get_plugin()
        local features = plugin and plugin.config and plugin.config.features
        if type(features) ~= "table" then
            return true
        end
        return features.automatic_series_grouping ~= false
    end

    local function is_dim_finished_enabled()
        local plugin = get_plugin()
        local cfg = plugin and plugin.config and plugin.config.browser_cover_badges
        return type(cfg) == "table" and cfg.dim_finished_books == true
    end

    local function is_directory(item)
        return item.is_directory
            or (item.attr and item.attr.mode == "directory")
            or item.mode == "directory"
    end

    local function ensure_sort_doc_props(item)
        if type(item) ~= "table" then return end
        local props = type(item.doc_props) == "table" and item.doc_props or {}
        local title = props.display_title or props.title or item.text or item.path or item.file or ""
        props.display_title = tostring(title)
        props.title = props.title or props.display_title
        props.authors = props.authors or NO_SERIES
        props.series = props.series or NO_SERIES
        props.series_index = props.series_index or 0
        props.keywords = props.keywords or NO_SERIES
        item.doc_props = props
    end

    local function prefetch_directory_metadata(dir_path)
        BookInfoManager:openDbConnection()

        if not BookInfoManager._zen_dir_stmt then
            -- Shin chilling BOOKINFO_DB_VERSION >= 20201210
            local cols = {
                "directory", "filename", "filesize", "filemtime", "in_progress",
                "unsupported", "cover_fetched", "has_meta", "has_cover",
                "cover_sizetag", "ignore_meta", "ignore_cover", "pages",
                "title", "authors", "series", "series_index", "language",
                "keywords", "description"
            }
            local sql = "SELECT " .. table.concat(cols, ",") .. " FROM bookinfo WHERE directory=? AND in_progress=0;"
            BookInfoManager._zen_dir_stmt = BookInfoManager.db_conn:prepare(sql)
        end

        local stmt = BookInfoManager._zen_dir_stmt
        stmt:bind(dir_path)

        local metadata_map = {}
        while true do
            local row = stmt:step()
            if not row then break end

            local filename = row[2]
            if filename then
                -- 13 -> 20
                metadata_map[filename] = {
                    pages = tonumber(row[13]),
                    title = row[14],
                    authors = row[15],
                    series = row[16],
                    series_index = row[17],
                    language = row[18],
                    keywords = row[19],
                    description = row[20],
                }
            end
        end
        stmt:clearbind():reset()
        return metadata_map
    end

    local function get_doc_props(item, cache)
        if type(item.doc_props) == "table" then
            return item.doc_props
        end
        local path = item.path or item.file
        if not path then return nil end

        local _, filename = util.splitFilePathName(path)

        if cache and cache[filename] then
            item.doc_props = cache[filename]
            return cache[filename]
        end

        local bookinfo
        if type(BookInfoManager.getDocProps) == "function" then
            bookinfo = BookInfoManager:getDocProps(path)
        else
            bookinfo = BookInfoManager:getBookInfo(path)
        end
        if type(bookinfo) == "table" then
            item.doc_props = bookinfo
            return bookinfo
        end
        return nil
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
        return false
    end

    local function clone_item_table(item_table)
        local copy = {}
        for _i, item in ipairs(item_table) do
            copy[_i] = item
        end
        for key, value in pairs(item_table) do
            if type(key) ~= "number" then
                copy[key] = value
            end
        end
        return copy
    end

    local function clone_series_items(series_items)
        local copy = {}
        for _i, item in ipairs(series_items or {}) do
            if item and not item.is_go_up then
                table.insert(copy, item)
            end
        end
        return copy
    end

    local function clear_item_table_cache(file_chooser)
        if file_chooser and file_chooser._zen_clear_item_table_cache then
            file_chooser:_zen_clear_item_table_cache()
        end
    end

    local book_status
    local function get_book_status()
        if not book_status then
            book_status = require("common/book_status")
        end
        return book_status
    end

    local function get_item_status(item)
        local status_api = get_book_status()
        if type(item) ~= "table" then return "new" end
        if item._zen_effective_status then return item._zen_effective_status end
        if item.status then
            return status_api.getEffectiveStatus(item.status, item.percent_finished)
        end

        local path = item.path or item.file
        if path then
            local ok, status = pcall(status_api.getEffectiveStatusFromFile, path)
            if ok and status then return status end
        end
        return status_api.getEffectiveStatus(item.status, item.percent_finished)
    end

    local function set_series_status(group)
        if not is_dim_finished_enabled() then return end
        if type(group) ~= "table" or type(group.series_items) ~= "table"
                or #group.series_items == 0 then
            return
        end
        for _i, item in ipairs(group.series_items) do
            if get_item_status(item) ~= "complete" then
                return
            end
        end
        group.status = "complete"
        group.percent_finished = 1
        group.sort_percent = 1
        group._zen_effective_status = "complete"
    end

    local AutomaticSeries = {}

    function AutomaticSeries:sortSeriesItems(items, group_item, file_chooser)
        local sort_key = group_item and (group_item._zen_sort_key or group_item.path)
        local fsd_api = rawget(_G, "__ZEN_FOLDER_SORT")
        local override = fsd_api and fsd_api.get and fsd_api.get(sort_key)

        if not override then
            table.sort(items, function(a, b)
                return (a._series_index or 0) < (b._series_index or 0)
            end)
            return
        end

        local saved_override = file_chooser._zen_sort_override
        file_chooser._zen_sort_override = override
        local ok_collate, collate = pcall(function() return file_chooser:getCollate() end)
        if ok_collate and collate then
            if type(collate.item_func) == "function" then
                for _i, item in ipairs(items) do
                    if item and item.path then
                        pcall(collate.item_func, item, file_chooser.ui)
                    end
                end
            end
            for _i, item in ipairs(items) do
                ensure_sort_doc_props(item)
            end

            local ok_sort_func, sort_func = pcall(
                file_chooser.getSortingFunction, file_chooser, collate, override.reverse == true)
            if ok_sort_func and sort_func then
                local ok_sort, err = pcall(table.sort, items, sort_func)
                if not ok_sort then
                    logger.warn("series sort failed:", err)
                end
            end
        end
        file_chooser._zen_sort_override = saved_override
    end

    function AutomaticSeries:processItemTable(item_table, file_chooser)
        if not file_chooser or not item_table then return end
        if file_chooser.show_current_dir_for_hold then return end

        local current_dir_cache = {}
        local first_file_path
        for _i, item in ipairs(item_table) do
            if item.is_file and item.path then
                first_file_path = item.path
                break
            end
        end

        if first_file_path then
            local directory, _ = util.splitFilePathName(first_file_path)
            local ok, cached_map = pcall(prefetch_directory_metadata, directory)
            if ok and cached_map then
                current_dir_cache = cached_map
            end
        end

        local collate, collate_id = file_chooser:getCollate()
        local reverse = G_reader_settings:isTrue("reverse_collate")
        local sort_func = file_chooser:getSortingFunction(collate, reverse)
        local mixed = G_reader_settings:isTrue("collate_mixed")
            and collate and collate.can_collate_mixed
        local is_name_sort = collate_id == "strcoll"
            or collate_id == "natural"
            or collate_id == "title"
            or collate_id == "title_natural"
        local needs_doc_props_sort = collate_id == "title"
            or collate_id == "title_natural"
            or collate_id == "authors"
            or collate_id == "series"
            or collate_id == "keywords"

        local series_map = {}
        local processed_list = {}
        local book_count = 0
        local non_series_book_count = 0

        for _i, item in ipairs(item_table) do
            if item.is_go_up then
                table.insert(processed_list, item)
            else
                if not item.sort_percent then item.sort_percent = 0 end
                if not item.percent_finished then item.percent_finished = 0 end
                if not item.opened then item.opened = false end

                local series_handled = false
                if item.is_file and item.path then
                    book_count = book_count + 1
                    local doc_props = get_doc_props(item, current_dir_cache)
                    local series_name = doc_props and doc_props.series
                    if type(series_name) == "string" and series_name ~= "" and series_name ~= NO_SERIES then
                        ---@diagnostic disable-next-line: need-check-nil
                        item._series_index = tonumber(doc_props.series_index) or 0

                        if not series_map[series_name] then
                            local group_attr = {}
                            if item.attr then
                                for key, value in pairs(item.attr) do
                                    group_attr[key] = value
                                end
                            end
                            group_attr.mode = "directory"

                            local group_item = {
                                text = series_name,
                                is_file = false,
                                is_directory = true,
                                path = (item.path:match("(.*/)") or item.path) .. series_name,
                                _zen_sort_key = (item.path:match("(.*/)") or item.path) .. series_name,
                                is_series_group = true,
                                series_items = { item },
                                attr = group_attr,
                                mode = "directory",
                                sort_percent = item.sort_percent,
                                percent_finished = item.percent_finished,
                                opened = item.opened,
                                doc_props = {
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
        for _series_name in pairs(series_map) do
            series_count = series_count + 1
            if series_count > 1 then break end
        end

        if series_count == 1 and non_series_book_count == 0 and book_count > 0 then
            return
        end

        for _series_name, group in pairs(series_map) do
            if #group.series_items == 1 then
                if group._list_index and processed_list[group._list_index] == group then
                    processed_list[group._list_index] = group.series_items[1]
                end
            else
                group.mandatory = tostring(#group.series_items) .. " \u{F016}"
                set_series_status(group)
                self:sortSeriesItems(group.series_items, group, file_chooser)
            end
        end

        local final_table = {}
        if mixed then
            if is_name_sort and sort_func then
                local up_item
                local to_sort = {}
                for _i, item in ipairs(processed_list) do
                    if item.is_go_up then
                        up_item = item
                    else
                        if needs_doc_props_sort then ensure_sort_doc_props(item) end
                        table.insert(to_sort, item)
                    end
                end
                local ok_sort, err = pcall(table.sort, to_sort, sort_func)
                if not ok_sort then
                    logger.warn("sort failed:", err)
                end
                if up_item then table.insert(final_table, up_item) end
                for _i, item in ipairs(to_sort) do
                    table.insert(final_table, item)
                end
            else
                final_table = processed_list
            end
        else
            local dirs = {}
            local files = {}
            local up_item

            for _i, item in ipairs(processed_list) do
                if item.is_go_up then
                    up_item = item
                elseif is_directory(item) then
                    if needs_doc_props_sort then ensure_sort_doc_props(item) end
                    table.insert(dirs, item)
                else
                    if needs_doc_props_sort then ensure_sort_doc_props(item) end
                    table.insert(files, item)
                end
            end

            if sort_func then
                local ok_sort, err = pcall(table.sort, dirs, sort_func)
                if not ok_sort then
                    logger.warn("sort failed:", err)
                end
            end

            if up_item then table.insert(final_table, up_item) end
            for _i, item in ipairs(dirs) do table.insert(final_table, item) end
            for _i, item in ipairs(files) do table.insert(final_table, item) end
        end

        for key in pairs(item_table) do item_table[key] = nil end
        for _i, item in ipairs(final_table) do item_table[_i] = item end
    end

    function AutomaticSeries:openSeriesGroup(file_chooser, group_item)
        if not file_chooser then return end

        local items = clone_series_items(group_item.series_items)
        local parent_path = file_chooser.path
        local parent_page = file_chooser.page
        local parent_item_index
        for index, item in ipairs(file_chooser.item_table or {}) do
            if item == group_item then
                parent_item_index = index
                break
            end
        end
        if not parent_item_index and file_chooser.path_items then
            parent_item_index = file_chooser.path_items[parent_path]
        end
        self:sortSeriesItems(items, group_item, file_chooser)
        local display_api = rawget(_G, "__ZEN_FOLDER_DISPLAY_MODE")
        local display_key = group_item._zen_sort_key or group_item.path
        local display_override = display_api and type(display_api.get) == "function"
            and display_api.get(display_key)
        log_navigation("open:before-display", file_chooser,
            "series=" .. tostring(group_item.text)
                .. " index=" .. tostring(parent_item_index)
                .. " captured_page=" .. tostring(parent_page)
                .. " override=" .. tostring(display_override))
        if display_override
                and type(display_api.apply) == "function" then
            local applied = display_api.apply(display_key)
            log_navigation("open:after-display", file_chooser,
                "series=" .. tostring(group_item.text)
                    .. " applied=" .. tostring(applied))
        end

        current_series_group = {
            series_name = group_item.text,
            parent_path = parent_path,
            group_item = group_item,
            sort_key = group_item._zen_sort_key or group_item.path,
            parent_item_index = parent_item_index,
            parent_page = parent_page,
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
        items._zen_series_group_item = group_item
        items._zen_series_sort_key = group_item._zen_sort_key or group_item.path
        file_chooser:switchItemTable(nil, items, nil, nil, group_item.text)
        log_navigation("open:after-switch", file_chooser,
            "series=" .. tostring(group_item.text))

        if hide_up_folder then
            file_chooser:_changeLeftIcon(Icon.up, function() file_chooser:onFolderUp() end)
        end

        -- Entering a series view does not change file_chooser.path, so the zen
        -- status bar's onPathChanged hook never fires. Refresh it directly so the
        -- back chevron appears for the virtual folder.
        local FileManager = require("apps/filemanager/filemanager")
        local fm = FileManager.instance
        if fm and fm._updateStatusBar then
            fm:_updateStatusBar()
        end
    end

    local function exit_virtual_folder_if_needed(file_chooser)
        if file_chooser and file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            local parent_path = file_chooser.item_table.parent_path
            if parent_path then
                log_navigation("back:requested", file_chooser,
                    "parent=" .. tostring(parent_path)
                        .. " tracked=" .. tostring(current_series_group ~= nil))
                if current_series_group then
                    current_series_group.should_restore_focus = true
                end
                file_chooser:changeToPath(parent_path)
                return true
            end
        end
        return false
    end

    -- Exposed so the navbar Library tab can leave a virtual series folder cleanly.
    -- Clears current_series_group so a following changeToPath/refreshPath won't
    -- re-open the group. Does NOT navigate; the caller decides the destination.
    -- Returns the parent path, or nil when not in a series view.
    rawset(_G, "__ZEN_SERIES_EXIT", function(file_chooser)
        if file_chooser and file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            current_series_group = nil
            file_chooser.item_table.is_in_series_view = false
            return file_chooser.item_table.parent_path
        end
        return nil
    end)

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
        local restore_state = current_series_group
        if not (restore_state and restore_state.should_restore_focus
                and new_item_table and not new_item_table.is_in_series_view) then
            restore_state = nil
        end
        local trace_navigation = current_series_group ~= nil
            or (new_item_table and new_item_table.is_in_series_view)
        local restore_index
        if is_enabled() and new_item_table and not new_item_table.is_in_series_view then
            new_item_table = clone_item_table(new_item_table)
            AutomaticSeries:processItemTable(new_item_table, file_chooser)
        end
        if restore_state then
            restore_index = restore_state.parent_item_index
            for index, item in ipairs(new_item_table) do
                if item.is_series_group and item.text == restore_state.series_name then
                    restore_index = index
                    break
                end
            end
            file_chooser.page = restore_state.parent_page or 1
            file_chooser.itemnumber = nil
            -- A negative itemnumber tells Menu:switchItemTable to preserve page.
            -- This avoids calculating it with the virtual view's stale perpage.
            itemnumber = -1
            itemmatch = nil
            log_navigation("switch:restore-captured-page", file_chooser,
                "series=" .. tostring(restore_state.series_name)
                    .. " captured_page=" .. tostring(restore_state.parent_page)
                    .. " restore_index=" .. tostring(restore_index))
            current_series_group = nil
        end
        if trace_navigation then
            log_navigation("switch:before", file_chooser,
                "incoming_itemnumber=" .. tostring(itemnumber)
                    .. " incoming_items=" .. tostring(new_item_table and #new_item_table)
                    .. " incoming_series_view="
                    .. tostring(new_item_table and new_item_table.is_in_series_view))
        end
        local ret = old_switchItemTable(
            file_chooser, new_title, new_item_table, itemnumber, itemmatch, new_subtitle)
        if restore_state and file_chooser.path_items and restore_state.parent_path
                and restore_index then
            file_chooser.path_items[restore_state.parent_path] = restore_index
        end
        if trace_navigation then
            log_navigation("switch:after", file_chooser)
        end
        return ret
    end

    FileChooser.goHome = function(file_chooser)
        if file_chooser.item_table and file_chooser.item_table.is_in_series_view then
            if current_series_group then
                current_series_group.should_restore_focus = true
            end
            local parent_path = file_chooser.item_table.parent_path
            local home_dir = G_reader_settings:readSetting("home_dir") or Device.home_dir
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
        -- Only re-open the series view for an in-place refresh (e.g. returning
        -- from the reader). When should_restore_focus is set we are exiting the
        -- virtual folder, so re-opening would trap the user inside it.
        if current_series_group and not current_series_group.should_restore_focus then
            local series_name = current_series_group.series_name
            for _i, item in ipairs(file_chooser.item_table) do
                if item.is_series_group and item.text == series_name then
                    AutomaticSeries:openSeriesGroup(file_chooser, item)
                    break
                end
            end
        end
    end

    FileChooser.onFolderUp = function(file_chooser)
        if exit_virtual_folder_if_needed(file_chooser) then
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
            log_navigation("change-path:before", file_chooser,
                "requested=" .. tostring(path)
                    .. " parent=" .. tostring(parent_path)
                    .. " captured_page="
                    .. tostring(current_series_group and current_series_group.parent_page)
                    .. " captured_index="
                    .. tostring(current_series_group and current_series_group.parent_item_index))
            if parent_path and path and (path:match("/%.%.") or path:match("^%.%.")) then
                path = parent_path
            end
            if current_series_group then
                current_series_group.should_restore_focus = true
                if parent_path and current_series_group.parent_item_index
                        and file_chooser.path_items then
                    file_chooser.path_items[parent_path] = current_series_group.parent_item_index
                end
            end
            local ret = old_changeToPath(file_chooser, path, ...)
            log_navigation("change-path:after", file_chooser,
                "resolved=" .. tostring(path))
            return ret
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
            -- The virtual folder keeps file_chooser.path at the parent dir, so the
            -- base updateItems would overwrite path_items[parent] with the virtual
            -- folder's page index. Snapshot and restore it so exiting the group
            -- returns the parent listing to its original page/focus.
            local pi = file_chooser.path_items
            local saved = pi and pi[file_chooser.path]
            log_navigation("update:virtual-before", file_chooser,
                "saved_path_item=" .. tostring(saved))
            local ret = old_updateItems(file_chooser, ...)
            if pi then pi[file_chooser.path] = saved end
            log_navigation("update:virtual-after", file_chooser,
                "restored_path_item=" .. tostring(saved))
            return ret
        end

        return old_updateItems(file_chooser, ...)
    end
end

return apply_automatic_series_grouping

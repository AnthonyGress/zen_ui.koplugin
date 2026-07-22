describe("file browser group views", function()
    local api
    local config
    local menus
    local shown
    local closed
    local dialogs
    local metadata
    local statuses
    local saved
    local opened
    local file_dialog_args
    local sort_dialog_args
    local saved_modules
    local replaced_modules = {
        "gettext",
        "config/manager",
        "common/book_status",
        "common/shared_state",
        "modules/filebrowser/patches/standalone_page",
        "common/db_bookinfo",
        "bookinfomanager",
        "covermenu",
        "listmenu",
        "common/cover_utils",
        "ui/widget/menu",
        "ui/uimanager",
        "ui/widget/buttondialog",
        "device",
        "ui/gesturerange",
        "ui/geometry",
        "libs/libkoreader-lfs",
        "util",
        "apps/filemanager/filemanagerutil",
        "apps/filemanager/filemanager",
        "ui/widget/filechooser",
    }

    local function find_menu(name)
        for _i, menu in ipairs(menus) do
            if menu.name == name then return menu end
        end
    end

    local function install_group_view(groups)
        config = {
            features = { browser_hide_up_folder = true },
            browser_hide_up_folder = { hide_up_folder = true },
            group_view = { display_mode = {} },
        }
        menus, shown, closed, dialogs = {}, {}, {}, {}
        metadata, statuses, opened = {}, {}, {}
        saved, file_dialog_args, sort_dialog_args = 0, nil, nil

        local plugin = {
            config = config,
            saveConfig = function()
                saved = saved + 1
            end,
        }

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("config/manager", {
            load = function() return config end,
            save = function(cfg) config = cfg end,
        })
        ZenSpec.replace("common/book_status", {
            getEffectiveStatusFromFile = function(path) return statuses[path] end,
        })
        ZenSpec.replace("common/shared_state", {
            registerLoader = function() end,
            register = function(_, exports)
                api = exports.group_view
                return {}
            end,
            restore = function() return {} end,
        })
        ZenSpec.replace("modules/filebrowser/patches/standalone_page", {
            create_menu = function(spec)
                spec.page = spec.page or 1
                spec.update_count = 0
                spec.updateItems = function(self)
                    self.update_count = self.update_count + 1
                end
                table.insert(menus, spec)
                return spec
            end,
            prepare_shell = function() end,
            hide_page_arrow = function() end,
            suppress_page_info_tap = function() end,
            apply_status_row = function() end,
        })
        ZenSpec.replace("common/db_bookinfo", {
            getGroupedByAuthor = function() return groups.authors or {} end,
            getGroupedBySeries = function() return groups.series or {} end,
            getGroupedByTags = function() return groups.tags or {} end,
            getTBRBooks = function() return groups.tbr or {} end,
        })
        ZenSpec.replace("bookinfomanager", {
            getSetting = function() return nil end,
            getBookInfo = function(_, path) return metadata[path] end,
        })
        ZenSpec.replace("covermenu", {
            updateItems = function(self)
                self.update_count = self.update_count + 1
            end,
            onCloseWidget = function() end,
        })
        ZenSpec.replace("listmenu", {
            _recalculateDimen = function() end,
            _updateItemsBuildUI = function() end,
        })
        ZenSpec.replace("common/cover_utils", {
            getFilesPerPage = function() return 10 end,
        })
        ZenSpec.replace("ui/widget/menu", {
            updateItems = function(self)
                self.update_count = self.update_count + 1
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            show = function(_, widget) table.insert(shown, widget) end,
            close = function(_, widget) table.insert(closed, widget) end,
            nextTick = function(_, callback) callback() end,
            isShown = function() return true end,
        })
        ZenSpec.replace("ui/widget/buttondialog", {
            new = function(_, spec)
                table.insert(dialogs, spec)
                return spec
            end,
        })
        ZenSpec.replace("device", {
            isTouchDevice = function() return false end,
            screen = { getWidth = function() return 600 end, getHeight = function() return 800 end },
        })
        ZenSpec.replace("ui/gesturerange", {
            new = function(_, spec) return spec end,
        })
        ZenSpec.replace("ui/geometry", {
            new = function(_, spec) return spec end,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, field)
                if field == "access" then return metadata[path] and metadata[path].access or 0 end
                return { size = metadata[path] and metadata[path].size or 0 }
            end,
        })
        ZenSpec.replace("util", {
            getFriendlySize = function(size) return tostring(size) .. " B" end,
        })
        ZenSpec.replace("apps/filemanager/filemanagerutil", {
            openFile = function(_, path) table.insert(opened, path) end,
        })
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = {
                file_chooser = {
                    showFileDialog = function(_, args) file_dialog_args = args end,
                    showSortOrderDialog = function(_, args) sort_dialog_args = args end,
                    refreshPath = function() end,
                },
            },
        })
        ZenSpec.replace("ui/widget/filechooser", { show_filter = {} })

        _G.__ZEN_UI_PLUGIN = plugin
        _G.__ZEN_UI_LIBRARY_STATE = nil
        ZenSpec.unload("modules/filebrowser/patches/group_view")
        require("modules/filebrowser/patches/group_view")()
        _G.__ZEN_UI_PLUGIN = nil
    end

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(replaced_modules) do
            saved_modules[name] = package.loaded[name] or false
        end
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
        _G.__ZEN_UI_LIBRARY_STATE = nil
        ZenSpec.unload("modules/filebrowser/patches/group_view")
        for _i, name in ipairs(replaced_modules) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("builds author, series, and tag pages from database groups", function()
        install_group_view({
            authors = {
                { author = "Ada\nLovelace", files = { "/a.epub", "/b.epub" } },
            },
            series = {
                { series = "Earthsea", items = { { file = "/e1.epub" }, { file = "/e2.epub" } } },
            },
            tags = {
                { tag = "Science", files = { "/s.epub" } },
            },
        })

        api.showAuthorsView()
        api.showSeriesView()
        api.showTagsView()

        local authors = assert(find_menu("authors"))
        local series = assert(find_menu("series"))
        local tags = assert(find_menu("tags"))
        assert.are.equal("Ada, Lovelace", authors.item_table[1].text)
        assert.are.equal("2 \u{F016}", authors.item_table[1].mandatory)
        assert.are.same({ "/e1.epub", "/e2.epub" }, series.item_table[1]._zen_files)
        assert.are.equal("Science", tags.item_table[1].text)
        assert.are.equal(1, authors.update_count)
        assert.are.equal(1, series.update_count)
        assert.are.equal(1, tags.update_count)
    end)

    it("names the missing metadata in an empty group page", function()
        install_group_view({})

        api.showAuthorsView()
        api.showSeriesView()
        api.showTagsView()

        local empty_messages = {
            authors = "No books with author metadata found",
            series = "No books with series metadata found",
            tags = "No books with tags metadata found",
        }
        for tab_id, message in pairs(empty_messages) do
            local item = assert(find_menu(tab_id)).item_table[1]
            assert.are.equal(message, item.text)
            assert.is_true(item.dim)
            assert.is_function(item.callback)
        end
    end)

    it("names the group metadata when a detail page has no books", function()
        install_group_view({
            authors = { { author = "Ada", files = {} } },
            series = { { series = "Earthsea", items = {} } },
            tags = { { tag = "Science", files = {} } },
        })

        api.showAuthorsView()
        api.showSeriesView()
        api.showTagsView()

        local empty_messages = {
            authors = "No books with author metadata found",
            series = "No books with series metadata found",
            tags = "No books with tags metadata found",
        }
        for tab_id, message in pairs(empty_messages) do
            local root = assert(find_menu(tab_id))
            root.onMenuSelect(root, root.item_table[1])
            local item = assert(find_menu(tab_id .. "_detail")).item_table[1]
            assert.are.equal(message, item.text)
            assert.is_true(item.dim)
        end
    end)

    it("persists reverse group sorting and rebuilds the open page", function()
        install_group_view({
            authors = {
                { author = "Alpha", files = { "/a.epub" } },
                { author = "Zulu", files = { "/z.epub" } },
            },
        })
        package.loaded.device.isTouchDevice = function() return true end
        api.showAuthorsView()
        local menu = assert(find_menu("authors"))
        menu:onZenGroupBlankHold()
        assert.is_function(file_dialog_args._zen_sort_cb)
        file_dialog_args._zen_sort_cb()
        sort_dialog_args.on_select(true)

        assert.is_true(config.group_view.group_reverse.authors)
        assert.are.equal(1, saved)
        assert.are.same({ "Zulu", "Alpha" }, {
            menu.item_table[1].text,
            menu.item_table[2].text,
        })
        assert.are.equal(2, menu.update_count)
    end)

    it("opens series detail pages sorted by numeric series index", function()
        install_group_view({
            series = {
                { series = "Saga", items = {
                    { file = "/third.epub" }, { file = "/first.epub" }, { file = "/second.epub" },
                } },
            },
        })
        metadata["/first.epub"] = { series_index = "1", size = 10 }
        metadata["/second.epub"] = { series_index = 2, size = 20 }
        metadata["/third.epub"] = { series_index = 3, size = 30 }

        api.showSeriesView()
        local root = assert(find_menu("series"))
        root.onMenuSelect(root, root.item_table[1])

        local detail = assert(find_menu("series_detail"))
        assert.are.same({ "first", "second", "third" }, {
            detail.item_table[1].text,
            detail.item_table[2].text,
            detail.item_table[3].text,
        })
        assert.are.equal("20 B", detail.item_table[2].mandatory)
        assert.are.same({ group_name = "Saga", tab_id = "series", page = 1 }, api.getActiveDetail())
    end)

    it("applies saved title sort, reverse state, and status filtering to author details", function()
        install_group_view({
            authors = {
                { author = "Writer", files = { "/the-zebra.epub", "/apple.epub", "/beta.epub" } },
            },
        })
        config.group_view.detail_collate = { authors = { Writer = "title" } }
        config.group_view.detail_reverse = { authors = { Writer = true } }
        metadata["/the-zebra.epub"] = { title = "The Zebra" }
        metadata["/apple.epub"] = { title = "Apple" }
        metadata["/beta.epub"] = { title = "Beta" }
        statuses["/the-zebra.epub"] = "complete"
        statuses["/apple.epub"] = "reading"
        statuses["/beta.epub"] = "complete"
        package.loaded["ui/widget/filechooser"].show_filter.status = { complete = true }

        api.showAuthorsView()
        local root = assert(find_menu("authors"))
        root.onMenuSelect(root, root.item_table[1])

        local detail = assert(find_menu("authors_detail"))
        assert.are.same({ "the-zebra", "beta" }, {
            detail.item_table[1].text,
            detail.item_table[2].text,
        })
    end)

    it("saves per-series detail sorting and rebuilds the visible book page", function()
        install_group_view({
            series = {
                { series = "Saga", items = { { file = "/z.epub" }, { file = "/a.epub" } } },
            },
        })
        metadata["/z.epub"] = { title = "Zulu", series_index = 1 }
        metadata["/a.epub"] = { title = "Alpha", series_index = 2 }
        package.loaded.device.isTouchDevice = function() return true end

        api.showSeriesView()
        local root = assert(find_menu("series"))
        root.onMenuSelect(root, root.item_table[1])
        local detail = assert(find_menu("series_detail"))
        assert.are.same({ "z", "a" }, { detail.item_table[1].text, detail.item_table[2].text })

        detail:onZenDetailBlankHold()
        file_dialog_args._zen_sort_cb()
        local sort_dialog = dialogs[#dialogs]
        sort_dialog.buttons[2][1].callback()

        assert.are.equal("title", config.group_view.detail_collate.series.Saga)
        assert.are.same({ "a", "z" }, { detail.item_table[1].text, detail.item_table[2].text })
        assert.are.equal(1, saved)
    end)

    it("persists tag-global collation and descending order from the page menu", function()
        install_group_view({
            tags = { { tag = "Classics", files = { "/book.epub" } } },
        })
        package.loaded.device.isTouchDevice = function() return true end
        api.showTagsView()
        local menu = assert(find_menu("tags"))

        menu:onZenGroupBlankHold()
        file_dialog_args._zen_sort_cb()
        local sort_dialog = dialogs[#dialogs]
        sort_dialog.buttons[4][1].callback()
        assert.are.equal("access", config.group_view.tags_global.collate)

        menu:onZenGroupBlankHold()
        file_dialog_args._zen_sort_cb()
        sort_dialog = dialogs[#dialogs]
        sort_dialog.buttons[5][1].callback()
        local order_dialog = dialogs[#dialogs]
        order_dialog.buttons[2][1].callback()

        assert.is_true(config.group_view.tags_global.reverse)
        assert.are.equal(2, saved)
    end)

    it("restores root and detail pages after returning from the reader", function()
        install_group_view({
            tags = {
                { tag = "Later", files = { "/later.epub" } },
                { tag = "Focus", files = { "/focus.epub" } },
            },
        })
        metadata["/focus.epub"] = { title = "Focus" }
        _G.__ZEN_UI_LIBRARY_STATE = {
            tab = "tags",
            page = 4,
            detail_group = "Focus",
            detail_page = 3,
        }

        api.showTagsView()

        local root = assert(find_menu("tags"))
        local detail = assert(find_menu("tags_detail"))
        assert.are.equal(4, root.page)
        assert.are.equal("Focus", detail._zen_group_name)
        assert.are.equal(3, detail.page)
        assert.is_nil(_G.__ZEN_UI_LIBRARY_STATE)
        assert.are.equal(4, api.getActivePage("tags"))
    end)

    it("opens books, navigates up, and closes every group-view layer", function()
        install_group_view({
            authors = { { author = "Writer", files = { "/book.epub" } } },
        })
        metadata["/book.epub"] = { title = "Book" }

        api.showAuthorsView()
        local root = assert(find_menu("authors"))
        root.onMenuSelect(root, root.item_table[1])
        local detail = assert(find_menu("authors_detail"))
        detail.onMenuSelect(detail, detail.item_table[1])
        assert.are.same({ "/book.epub" }, opened)

        detail.close_callback()
        assert.are.equal(detail, closed[#closed])
        assert.is_nil(api.getActiveDetail())

        root.onMenuSelect(root, { is_go_up = true })
        assert.are.equal(root, closed[#closed])
        assert.is_nil(api.getActivePage("authors"))

        api.showAuthorsView()
        local second_root = assert(menus[#menus])
        second_root.onMenuSelect(second_root, second_root.item_table[1])
        local second_detail = assert(menus[#menus])
        api.closeAll()
        assert.are.equal(second_root, closed[#closed])
        assert.is_nil(api.getActiveDetail())
        assert.is_nil(api.getActivePage("authors"))
        assert.is_true(#closed >= 4)
        assert.are.equal("authors_detail", second_detail.name)
    end)
end)

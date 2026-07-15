describe("automatic series grouping patch", function()
    local FileChooser
    local TitleBar
    local metadata
    local original_select_calls
    local cached_rows
    local doc_props_lookups

    local function item(path, title)
        return {
            text = title,
            path = path,
            is_file = true,
            attr = { mode = "file" },
        }
    end

    local function chooser()
        return setmetatable({
            path = "/library",
            page = 2,
            perpage = 10,
            path_items = { ["/library"] = 3 },
            getCollate = function() return { can_collate_mixed = false }, "natural" end,
            getSortingFunction = function()
                return function(a, b) return (a.text or "") < (b.text or "") end
            end,
            switchItemTable = FileChooser.switchItemTable,
        }, { __index = FileChooser })
    end

    before_each(function()
        metadata = {}
        original_select_calls = 0
        cached_rows = {}
        doc_props_lookups = 0
        G_reader_settings = ZenSpec.memorySettings({
            reverse_collate = false,
            collate_mixed = false,
            home_dir = "/library",
        })
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { automatic_series_grouping = true },
                browser_cover_badges = { dim_finished_books = false },
            },
        }
        _G.__ZEN_FOLDER_SORT = nil
        _G.__ZEN_FOLDER_DISPLAY_MODE = nil

        FileChooser = {
            updateItems = function() return "updated" end,
            onMenuSelect = function()
                original_select_calls = original_select_calls + 1
                return "selected"
            end,
            onFolderUp = function() return "folder-up" end,
            changeToPath = function(self, path)
                self.changed_to = path
                return "changed"
            end,
            refreshPath = function() end,
            goHome = function() return "home" end,
            switchItemTable = function(self, _title, new_items, itemnumber, itemmatch, subtitle)
                self.item_table = new_items
                self.switched_itemnumber = itemnumber
                self.switched_itemmatch = itemmatch
                self.subtitle = subtitle
                return "switched"
            end,
        }
        TitleBar = { setSubTitle = function(self, subtitle) self.subtitle = subtitle end }

        ZenSpec.replace("ui/widget/filechooser", FileChooser)
        ZenSpec.replace("ui/widget/titlebar", TitleBar)
        ZenSpec.replace("ui/bidi", {
            mirroredUILayout = function() return false end,
            ltr = function(value) return value end,
        })
        ZenSpec.replace("device", { home_dir = "/library" })
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return { info = function() end, warn = function() end }
            end,
        })
        ZenSpec.replace("util", {
            splitFilePathName = function(path)
                return assert(path:match("^(.*)/([^/]+)$"))
            end,
        })
        ZenSpec.replace("bookinfomanager", {
            openDbConnection = function(self)
                self.db_conn = {
                    prepare = function()
                        local position = 0
                        return {
                            bind = function(stmt, directory)
                                stmt.directory = directory
                                position = 0
                            end,
                            step = function()
                                position = position + 1
                                return cached_rows[position]
                            end,
                            clearbind = function(stmt) return stmt end,
                            reset = function(stmt) return stmt end,
                        }
                    end,
                }
            end,
            getDocProps = function(_, path)
                doc_props_lookups = doc_props_lookups + 1
                return metadata[path]
            end,
        })
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = { _updateStatusBar = function(self) self.updated = true end },
        })

        ZenSpec.unload("modules/filebrowser/patches/automatic_series_grouping")
        require("modules/filebrowser/patches/automatic_series_grouping")()
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
        _G.__ZEN_FOLDER_SORT = nil
        _G.__ZEN_FOLDER_DISPLAY_MODE = nil
        _G.__ZEN_SERIES_EXIT = nil
    end)

    it("groups repeated metadata series and orders books by series index", function()
        local first = item("/library/B.epub", "B")
        local second = item("/library/A.epub", "A")
        local loose = item("/library/Loose.epub", "Loose")
        metadata[first.path] = { series = "Saga", series_index = 2 }
        metadata[second.path] = { series = "Saga", series_index = 1 }
        metadata[loose.path] = { title = "Loose" }
        local fc = chooser()

        FileChooser.switchItemTable(fc, nil, { first, second, loose })

        assert.are.equal(2, #fc.item_table)
        local group = fc.item_table[1]
        assert.is_true(group.is_series_group)
        assert.are.equal("Saga", group.text)
        assert.are.equal("2 \u{F016}", group.mandatory)
        assert.are.same({ second, first }, group.series_items)
        assert.are.equal(loose, fc.item_table[2])
    end)

    it("groups Series-A from the CoverBrowser directory metadata cache", function()
        local alpha = item("/library/Series-A/01 - Alpha.epub", "01 - Alpha")
        local no_cover = item("/library/Series-A/02 - No Cover.epub", "02 - No Cover")
        local finale = item("/library/Series-A/03 - Finale.epub", "03 - Finale")
        local loose = item("/library/Series-A/Loose.epub", "Loose")
        cached_rows = {
            { "/library/Series-A/", "01 - Alpha.epub", nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, 101, "Alpha", "Zen Author", "Series A", 1, "en", "" },
            { "/library/Series-A/", "02 - No Cover.epub", nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, 102, "No Cover", "Zen Author", "Series A", 2, "en", "" },
            { "/library/Series-A/", "03 - Finale.epub", nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, 103, "Finale", "Zen Author", "Series A", 3, "en", "" },
            { "/library/Series-A/", "Loose.epub", nil, nil, nil, nil, nil, nil,
                nil, nil, nil, nil, 104, "Loose", "Zen Author", nil, nil, "en", "" },
        }
        local fc = chooser()

        FileChooser.switchItemTable(fc, nil, { finale, loose, alpha, no_cover })

        assert.are.equal(2, #fc.item_table)
        local group = fc.item_table[1]
        assert.are.equal("Series A", group.text)
        assert.are.same({ alpha, no_cover, finale }, group.series_items)
        assert.are.equal("Alpha", alpha.doc_props.title)
        assert.are.equal("Zen Author", finale.doc_props.authors)
        assert.are.equal(0, doc_props_lookups)
    end)

    it("does not create a redundant group when every book belongs to one series", function()
        local first = item("/library/One.epub", "One")
        local second = item("/library/Two.epub", "Two")
        metadata[first.path] = { series = "Only", series_index = 1 }
        metadata[second.path] = { series = "Only", series_index = 2 }
        local fc = chooser()

        FileChooser.switchItemTable(fc, nil, { first, second })

        assert.are.same({ first, second }, fc.item_table)
    end)

    it("opens a virtual series folder and returns to its parent", function()
        local first = item("/library/One.epub", "One")
        local second = item("/library/Two.epub", "Two")
        local loose = item("/library/Loose.epub", "Loose")
        metadata[first.path] = { series = "Saga", series_index = 1 }
        metadata[second.path] = { series = "Saga", series_index = 2 }
        local fc = chooser()
        FileChooser.switchItemTable(fc, nil, { first, second, loose })
        local group = fc.item_table[1]

        assert.is_true(FileChooser.onMenuSelect(fc, group))
        assert.is_true(fc.item_table.is_in_series_view)
        assert.are.equal("/library", fc.item_table.parent_path)
        assert.is_true(fc.item_table[1].is_go_up)
        assert.are.same({ first, second }, { fc.item_table[2], fc.item_table[3] })
        assert.are.equal("Saga", fc.subtitle)
        assert.are.equal(0, original_select_calls)

        assert.is_true(FileChooser.onFolderUp(fc))
        assert.are.equal("/library", fc.changed_to)
    end)

    it("leaves ordinary selection and disabled grouping to KOReader", function()
        local fc = chooser()
        local ordinary = item("/library/Plain.epub", "Plain")
        assert.are.equal("selected", FileChooser.onMenuSelect(fc, ordinary))
        assert.are.equal(1, original_select_calls)

        _G.__ZEN_UI_PLUGIN.config.features.automatic_series_grouping = false
        metadata[ordinary.path] = { series = "Saga", series_index = 1 }
        FileChooser.switchItemTable(fc, nil, { ordinary })
        assert.are.same({ ordinary }, fc.item_table)
    end)
end)

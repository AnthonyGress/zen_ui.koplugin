describe("file browser item-table cache", function()
    local FileChooser
    local generated
    local saved_modules
    local saved_settings
    local saved_plugin
    local collate_mode
    local mixed
    local history_times
    local descendant_times
    local source_items

    local module_names = {
        "common/cover_utils",
        "ui/widget/container/alphacontainer", "ui/bidi", "ffi/blitbuffer",
        "ui/widget/container/bottomcontainer", "ui/widget/container/centercontainer",
        "device", "ui/widget/filechooser", "ui/widget/container/framecontainer",
        "ui/widget/horizontalgroup", "ui/widget/horizontalspan", "ui/widget/imagewidget",
        "ui/widget/container/leftcontainer", "ui/widget/linewidget",
        "ui/widget/overlapgroup", "ui/widget/container/rightcontainer", "ui/size",
        "ui/widget/textboxwidget", "ui/widget/textwidget", "ui/widget/container/topcontainer",
        "ui/widget/verticalgroup", "ui/widget/verticalspan", "ffi/util",
        "libs/libkoreader-lfs", "common/history_index", "common/zen_logger",
        "common/paths", "modules/filebrowser/patches/library_font", "common/utils",
        "gettext", "apps/filemanager/filemanager",
    }

    before_each(function()
        generated = {}
        collate_mode = "title"
        mixed = false
        history_times = {}
        descendant_times = {}
        source_items = {}
        saved_modules = {}
        for _i, name in ipairs(module_names) do
            saved_modules[name] = package.loaded[name]
        end
        saved_settings = _G.G_reader_settings
        saved_plugin = _G.__ZEN_UI_PLUGIN

        FileChooser = {
            collates = {
                title = { id = "title" },
                access = {
                    id = "access",
                    can_collate_mixed = true,
                    mandatory_func = function() return "2026-08-01 12:00" end,
                },
            },
            getCollate = function(self)
                return self.collates[collate_mode], collate_mode
            end,
            getMenuItemMandatory = function(_, item, collate)
                return collate.mandatory_func(item)
            end,
            getListItem = function() end,
            genItemTableFromPath = function(_, path)
                generated[path] = (generated[path] or 0) + 1
                return source_items[path] or { { path = path } }
            end,
        }
        ZenSpec.replace("common/cover_utils", { BORDER_SIZE = 2 })
        for _i, name in ipairs({
            "ui/widget/container/alphacontainer", "ui/bidi", "ffi/blitbuffer",
            "ui/widget/container/bottomcontainer", "ui/widget/container/centercontainer",
            "ui/widget/container/framecontainer", "ui/widget/horizontalgroup",
            "ui/widget/horizontalspan", "ui/widget/imagewidget", "ui/widget/container/leftcontainer",
            "ui/widget/linewidget", "ui/widget/overlapgroup", "ui/widget/container/rightcontainer",
            "ui/widget/textboxwidget", "ui/widget/textwidget", "ui/widget/container/topcontainer",
            "ui/widget/verticalgroup", "ui/widget/verticalspan", "common/utils",
        }) do
            ZenSpec.replace(name, {})
        end
        ZenSpec.replace("device", { screen = { scaleBySize = function(_, value) return value end } })
        ZenSpec.replace("ui/widget/filechooser", FileChooser)
        ZenSpec.replace("ui/size", { line = { medium = 1 } })
        ZenSpec.replace("ffi/util", { realpath = function(path) return path end })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(_, field)
                if field == "modification" then return 1 end
            end,
        })
        ZenSpec.replace("common/history_index", {
            load = function() return history_times end,
            fileTime = function(index, path) return index[path] end,
            maxDescendantTimes = function() return descendant_times end,
        })
        ZenSpec.replace("common/zen_logger", {
            now = function() return 0 end,
            new = function()
                return { measure = function() end, dbg = function() end, warn = function() end }
            end,
        })
        ZenSpec.replace("common/paths", {
            getHomeDir = function() return "/library" end,
            normPath = function(path) return path end,
        })
        ZenSpec.replace("modules/filebrowser/patches/library_font", {})
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("apps/filemanager/filemanager", { setupLayout = function() end })
        _G.G_reader_settings = {
            readSetting = function(_, key, default)
                if key == "collate" then return collate_mode end
                return default
            end,
            isTrue = function(_, key)
                return key == "collate_mixed" and mixed
            end,
        }
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { browser_hide_up_folder = true, zen_mode = true },
                browser_hide_up_folder = { hide_up_folder = true, lock_home_folder = "zen" },
            },
        }
        ZenSpec.unload("modules/filebrowser/patches/browser_item_table_cache")
        require("modules/filebrowser/patches/browser_item_table_cache")()
    end)

    after_each(function()
        ZenSpec.unload("modules/filebrowser/patches/browser_item_table_cache")
        _G.__ZEN_UI_DEFER_FILEMANAGER_LISTING = nil
        _G.__ZEN_UI_LAST_READ_FILE = nil
        for _i, name in ipairs(module_names) do
            package.loaded[name] = saved_modules[name]
        end
        _G.G_reader_settings = saved_settings
        _G.__ZEN_UI_PLUGIN = saved_plugin
    end)

    it("keeps the library root cached while a child folder is open", function()
        local chooser = setmetatable({ name = "filemanager" }, { __index = FileChooser })

        chooser:genItemTableFromPath("/library")
        chooser:genItemTableFromPath("/library/series")
        chooser:genItemTableFromPath("/library")

        assert.are.equal(1, generated["/library"])
        assert.are.equal(1, generated["/library/series"])
    end)

    it("returns a synthetic empty list only during hidden Home bootstrap", function()
        local chooser = setmetatable({ name = "filemanager" }, { __index = FileChooser })
        _G.__ZEN_UI_DEFER_FILEMANAGER_LISTING = { path = "/library" }

        local deferred = chooser:genItemTableFromPath("/library")
        assert.are.same({}, deferred)
        assert.is_nil(generated["/library"])

        _G.__ZEN_UI_DEFER_FILEMANAGER_LISTING = nil
        local materialized = chooser:genItemTableFromPath("/library")
        assert.are.equal(1, #materialized)
        assert.are.equal(1, generated["/library"])
    end)

    it("refreshes cached folders when up-folder visibility changes", function()
        local chooser = setmetatable({ name = "filemanager" }, { __index = FileChooser })

        chooser:genItemTableFromPath("/library/series")
        _G.__ZEN_UI_PLUGIN.config.browser_hide_up_folder.hide_up_folder = false
        chooser:genItemTableFromPath("/library/series")

        assert.are.equal(2, generated["/library/series"])
    end)

    it("promotes a folder when one of its descendant books is read", function()
        collate_mode = "access"
        mixed = true
        source_items["/library"] = {
            {
                text = "Earlier/", path = "/library/Earlier",
                mandatory = "1 \xef\x80\x96", attr = { mode = "directory", modification = 1 },
            },
            {
                text = "Later/", path = "/library/Later",
                mandatory = "2 \xef\x80\x96", attr = { mode = "directory", modification = 1 },
            },
        }
        descendant_times = {
            ["/library/Earlier"] = 20,
            ["/library/Later"] = 10,
        }
        local chooser = setmetatable({ name = "filemanager" }, { __index = FileChooser })

        local before = chooser:genItemTableFromPath("/library")
        assert.are.equal("Earlier/", before[1].text)
        assert.are.equal("1 \xef\x80\x96", before[1].mandatory)

        descendant_times["/library/Later"] = 30
        _G.__ZEN_UI_LAST_READ_FILE = "/library/Later/book.epub"
        local after = chooser:genItemTableFromPath("/library")

        assert.are.equal("Later/", after[1].text)
        assert.are.equal("2 \xef\x80\x96", after[1].mandatory)
        assert.are.equal(1, generated["/library"])
    end)
end)

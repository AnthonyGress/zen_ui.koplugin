describe("file browser item-table cache", function()
    local FileChooser
    local generated
    local saved_modules
    local saved_settings
    local saved_plugin

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
        saved_modules = {}
        for _i, name in ipairs(module_names) do
            saved_modules[name] = package.loaded[name]
        end
        saved_settings = _G.G_reader_settings
        saved_plugin = _G.__ZEN_UI_PLUGIN

        FileChooser = {
            collates = { title = { id = "title" } },
            getCollate = function(self) return self.collates.title, "title" end,
            getListItem = function() end,
            genItemTableFromPath = function(_, path)
                generated[path] = (generated[path] or 0) + 1
                return { { path = path } }
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
        ZenSpec.replace("common/history_index", {})
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
                if key == "collate" then return "title" end
                return default
            end,
            isTrue = function() return false end,
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

    it("refreshes cached folders when up-folder visibility changes", function()
        local chooser = setmetatable({ name = "filemanager" }, { __index = FileChooser })

        chooser:genItemTableFromPath("/library/series")
        _G.__ZEN_UI_PLUGIN.config.browser_hide_up_folder.hide_up_folder = false
        chooser:genItemTableFromPath("/library/series")

        assert.are.equal(2, generated["/library/series"])
    end)
end)

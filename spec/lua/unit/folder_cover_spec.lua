describe("shared folder cover provider", function()
    local calls
    local cover_mode

    before_each(function()
        calls = { collect = {}, decorate = 0 }
        cover_mode = "gallery"
        ZenSpec.replace("common/cover_utils", {
            BORDER_SIZE = 2,
            getMode = function()
                if cover_mode == "none" then return "none", 0, false end
                return cover_mode, 4, true
            end,
            calcDims = function(width, height) return width, height end,
            loadExplicitCovers = function(path)
                calls.explicit = path
                return {}
            end,
            collect = function(path, chooser, limit, need_copy, entries, specs)
                calls.collect[#calls.collect + 1] = {
                    path = path, chooser = chooser, limit = limit,
                    need_copy = need_copy, entries = entries, specs = specs,
                }
                return entries and #entries > 0 and { { data = "cover" } } or {}
            end,
            drawGallery = function(covers, _width, _height, _border, _bg, uniform)
                calls.uniform = uniform
                return { kind = "gallery", covers = covers, bordersize = 2 }
            end,
            drawStack = function() return { kind = "stack", bordersize = 2 } end,
            drawSingle = function() return { kind = "single", bordersize = 2 } end,
            drawNoImage = function(title)
                return { kind = "placeholder", title = title, bordersize = 2 }
            end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/widgets/cover_common", {
            decorate_cover_frame = function(frame)
                calls.decorate = calls.decorate + 1
                frame.decorated = true
            end,
        })
        ZenSpec.unload("modules/filebrowser/folder_cover")
    end)

    after_each(function()
        ZenSpec.unload("modules/filebrowser/folder_cover")
    end)

    it("classifies every Zen library entry while leaving unknown menus alone", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local filemanager = { name = "filemanager" }

        assert.is_true(FolderCover.isSupported({ is_file = true }, filemanager))
        assert.is_true(FolderCover.isSupported({ attr = { mode = "directory" } }, filemanager))
        assert.is_true(FolderCover.isSupported({ series_items = {} }, {}))
        assert.is_true(FolderCover.isSupported({ _zen_files = {} }, {}))
        assert.is_true(FolderCover.isSupported({ is_go_up = true }, {}))
        assert.is_true(FolderCover.isSupported({ name = "Favorites" }, { _zen_coll_list = true }))
        assert.is_false(FolderCover.isSupported({ text = "Unrelated" }, {}))
    end)

    it("does not enumerate a physical folder when covers are suppressed", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local enumerations = 0
        local menu = {
            name = "filemanager",
            genItemTableFromPath = function()
                enumerations = enumerations + 1
                return { { is_file = true, path = "/library/a.epub" } }
            end,
        }
        local result = FolderCover.build(menu, {
            path = "/library/folder", attr = { mode = "directory" },
            mandatory = "7 books",
        }, "Folder/", 80, 120, { load_covers = false })

        assert.are.equal(0, enumerations)
        assert.are.equal(0, #calls.collect)
        assert.are.equal(7, result.count)
        assert.are.equal("Folder", result.title)
        assert.are.equal("placeholder", result.frame.kind)
        assert.is_true(result.frame.decorated)
    end)

    it("does not enumerate a physical folder in folder-name-only mode", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        cover_mode = "none"
        local enumerations = 0
        local result = FolderCover.build({
            name = "filemanager",
            genItemTableFromPath = function()
                enumerations = enumerations + 1
                return {}
            end,
        }, {
            path = "/library/folder", attr = { mode = "directory" },
            mandatory = "4 books",
        }, "Folder/", 80, 120)

        assert.are.equal(0, enumerations)
        assert.are.equal(4, result.count)
        assert.are.equal("none", result.mode)
    end)

    it("enumerates a physical folder once and passes the ordered entries through", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local enumerations = 0
        local entries = {
            { is_file = true, path = "/library/folder/a.epub" },
            { is_file = true, path = "/library/folder/b.epub" },
        }
        local menu = {
            name = "filemanager",
            genItemTableFromPath = function(self)
                enumerations = enumerations + 1
                assert.is_true(self._zen_folder_cover_collect)
                return entries
            end,
        }
        local specs = { max_cover_w = 80, max_cover_h = 120 }
        local result = FolderCover.build(menu, {
            path = "/library/folder", attr = { mode = "directory" },
        }, "Folder/", 80, 120, { cover_specs = specs })

        assert.are.equal(1, enumerations)
        assert.are.equal("/library/folder", calls.explicit)
        assert.are.equal(1, #calls.collect)
        assert.are.equal(entries, calls.collect[1].entries)
        assert.are.equal(specs, calls.collect[1].specs)
        assert.are.equal(2, result.count)
        assert.are.equal("gallery", result.frame.kind)
        assert.is_true(calls.uniform)
    end)

    it("passes non-uniform sizing through to group previews", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        FolderCover.build({}, {
            _zen_files = { "/library/landscape.epub" },
        }, "Author", 80, 120, { uniform = false })

        assert.is_false(calls.uniform)
    end)

    it("uses synthetic group and collection members without scanning paths", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local menu = {
            _zen_coll_list = true,
            _zen_get_collection_files = function()
                return { "/library/b.epub", "/library/a.epub" }
            end,
            _zen_get_collection_title = function() return "Favorites" end,
            genItemTableFromPath = function() error("synthetic group scanned a path") end,
        }
        local result = FolderCover.build(menu, { name = "favorites" }, nil, 80, 120)

        assert.are.equal("Favorites", result.title)
        assert.are.equal(2, result.count)
        assert.is_nil(calls.collect[1].path)
        assert.are.equal("/library/b.epub", calls.collect[1].entries[1].path)
        assert.are.equal("/library/a.epub", calls.collect[1].entries[2].path)
    end)

    it("does not sort collection members when cover loading is suppressed", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local provider_calls = 0
        local menu = {
            _zen_coll_list = true,
            _zen_get_collection_files = function()
                provider_calls = provider_calls + 1
                return { "/library/a.epub" }
            end,
        }
        local result = FolderCover.build(menu, {
            name = "favorites", mandatory = "3 books",
        }, "Favorites", 80, 120, { load_covers = false })

        assert.are.equal(0, provider_calls)
        assert.are.equal(3, result.count)
    end)

    it("preserves numeric collection counts when cover loading is suppressed", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local result = FolderCover.build({ _zen_coll_list = true }, {
            name = "favorites", mandatory = 3,
        }, "Favorites", 80, 120, { load_covers = false })

        assert.are.equal(3, result.count)
    end)
end)

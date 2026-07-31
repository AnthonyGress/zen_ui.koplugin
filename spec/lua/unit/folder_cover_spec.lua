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
            drawSingle = function(_cover, width, height, _border, uniform)
                calls.single = { width = width, height = height, uniform = uniform }
                return { kind = "single", bordersize = 2 }
            end,
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
        assert.is_true(FolderCover.isSupported({ is_directory = true }, { _zen_renderer = true }))
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

    it("gives a natural single preview the same full bounds as its child", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        cover_mode = "normal"
        FolderCover.build({}, {
            _zen_files = { "/library/tall.epub" },
        }, "Author", 80, 122, { uniform = false })

        assert.are.same({ width = 80, height = 122, uniform = false }, calls.single)
    end)

    it("keeps mosaic spine lines short and separated from the cover", function()
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_self, value) return math.floor(value + 0.5) end },
        })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_GRAY_4 = 4, COLOR_BLACK = 0 })
        ZenSpec.replace("ui/size", { line = { medium = 2 } })
        ZenSpec.unload("modules/filebrowser/folder_cover")
        local FolderCover = require("modules/filebrowser/folder_cover")
        local rects = {}
        local bb = {
            paintRect = function(_self, x, y, width, height)
                rects[#rects + 1] = { x = x, y = y, width = width, height = height }
            end,
        }

        local orientation = FolderCover.paintSpines(bb, {
            dimen = { x = 30, y = 20, w = 100, h = 150 },
        }, 0, 0, { rounded = true })

        assert.are.equal("top", orientation)
        assert.are.same({
            { x = 37, y = 11, width = 86, height = 3 },
            { x = 35, y = 16, width = 89, height = 3 },
        }, rects)
        assert.are.equal(1, 20 - (rects[2].y + rects[2].height))
    end)

    it("moves spines left when the mosaic has no room above", function()
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_self, value) return math.floor(value + 0.5) end },
        })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_GRAY_4 = 4, COLOR_BLACK = 0 })
        ZenSpec.replace("ui/size", { line = { medium = 2 } })
        ZenSpec.unload("modules/filebrowser/folder_cover")
        local FolderCover = require("modules/filebrowser/folder_cover")
        local rects = {}
        local bb = {
            paintRect = function(_self, x, y, width, height)
                rects[#rects + 1] = { x = x, y = y, width = width, height = height }
            end,
        }

        local orientation = FolderCover.paintSpines(bb, {
            dimen = { x = 30, y = 2, w = 100, h = 150 },
        }, 0, 0, { rounded = true })

        assert.are.equal("left", orientation)
        assert.are.same({
            { x = 21, y = 10, width = 3, height = 133 },
            { x = 26, y = 8, width = 3, height = 137 },
        }, rects)
        assert.are.equal(1, 30 - (rects[2].x + rects[2].width))
    end)

    it("uses the full list row height for left spine lengths", function()
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_self, value) return math.floor(value + 0.5) end },
        })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_GRAY_4 = 4, COLOR_BLACK = 0 })
        ZenSpec.replace("ui/size", { line = { medium = 2 } })
        ZenSpec.unload("modules/filebrowser/folder_cover")
        local FolderCover = require("modules/filebrowser/folder_cover")
        local rects = {}
        local bb = {
            paintRect = function(_self, x, y, width, height)
                rects[#rects + 1] = { x = x, y = y, width = width, height = height }
            end,
        }

        FolderCover.paintSpines(bb, {
            dimen = { x = 30, y = 6, w = 60, h = 90 },
        }, 0, 0, {
            orientation = "left", line_extent = 100, center_y = 51, rounded = true,
        })

        assert.are.same({
            { x = 21, y = 8, width = 3, height = 86 },
            { x = 26, y = 6, width = 3, height = 89 },
        }, rects)
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

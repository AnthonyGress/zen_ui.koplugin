describe("shared folder cover provider", function()
    local calls
    local cover_mode

    local function install_lfs(entries_for_path, on_scan, on_yield)
        ZenSpec.replace("libs/libkoreader-lfs", {
            dir = function(path)
                if on_scan then on_scan(path) end
                local entries = entries_for_path(path)
                local names = { ".", ".." }
                for _i, entry in ipairs(entries) do names[#names + 1] = entry.name end
                local index = 0
                return function()
                    index = index + 1
                    local name = names[index]
                    if on_yield and name ~= "." and name ~= ".." then on_yield(name) end
                    return name
                end
            end,
            attributes = function(path, field)
                if field == "modification" then return 1 end
                local dir, name = path:match("^(.*)/([^/]+)$")
                for _i, entry in ipairs(entries_for_path(dir)) do
                    if entry.name == name then
                        local attr = {
                            mode = entry.mode or "file",
                            access = entry.access or 0,
                            modification = entry.modification or 0,
                            size = entry.size or 0,
                        }
                        return field and attr[field] or attr
                    end
                end
            end,
        })
        ZenSpec.unload("modules/filebrowser/folder_cover")
    end

    before_each(function()
        calls = { collect = {}, decorate = 0 }
        cover_mode = "gallery"
        ZenSpec.replace("common/cover_utils", {
            BORDER_SIZE = 2,
            getMode = function()
                if cover_mode == "none" then return "none", 0, false end
                if cover_mode == "normal" then return "normal", 1, false end
                return cover_mode, 4, true
            end,
            calcDims = function(width, height) return width, height end,
            galleryCacheKey = function(...)
                calls.gallery_key_args = { ... }
                return calls.gallery_cache_key
            end,
            getCachedGallery = function(key)
                calls.gallery_cache_lookups = (calls.gallery_cache_lookups or 0) + 1
                calls.gallery_lookup_key = key
                return calls.cached_gallery
            end,
            loadExplicitCovers = function(path)
                calls.explicit = path
                return {}
            end,
            collect = function(path, chooser, limit, need_copy, entries, specs,
                    cover_offset, cached_only)
                calls.collect[#calls.collect + 1] = {
                    path = path, chooser = chooser, limit = limit,
                    need_copy = need_copy, entries = entries, specs = specs,
                    cover_offset = cover_offset, cached_only = cached_only,
                }
                return entries and #entries > 0 and { { data = "cover" } } or {},
                    calls.collect_pending == true
            end,
            drawGallery = function(covers, _width, _height, _border, _bg, uniform, cache_key)
                calls.uniform = uniform
                calls.draw_gallery_cache_key = cache_key
                return {
                    kind = "gallery",
                    covers = covers,
                    bordersize = 2,
                    free = function() calls.gallery_freed = true end,
                },
                    false, cache_key ~= nil
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
            mandatory = "2 \xef\x84\x94 7 \xef\x80\x96",
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

    it("scans a folder without constructing child FileChooser items", function()
        local scans = 0
        install_lfs(function()
            return {
                { name = "b.epub" },
                { name = "a.epub" },
                { name = "notes.bin" },
                { name = "nested", mode = "directory" },
            }
        end, function() scans = scans + 1 end)
        local FolderCover = require("modules/filebrowser/folder_cover")
        local menu = {
            name = "filemanager",
            genItemTableFromPath = function() error("child item table was constructed") end,
        }
        local specs = { max_cover_w = 80, max_cover_h = 120 }
        local result = FolderCover.build(menu, {
            path = "/library/folder", attr = { mode = "directory" },
        }, "Folder/", 80, 120, { cover_specs = specs })

        assert.are.equal(1, scans)
        assert.are.equal("/library/folder", calls.explicit)
        assert.are.equal(1, #calls.collect)
        assert.are.equal(2, #calls.collect[1].entries)
        assert.are.equal("/library/folder/b.epub", calls.collect[1].entries[1].path)
        assert.are.equal("/library/folder/a.epub", calls.collect[1].entries[2].path)
        assert.are.equal(specs, calls.collect[1].specs)
        assert.are.equal(2, result.count)
        assert.are.equal("gallery", result.frame.kind)
        assert.is_true(calls.uniform)
    end)

    it("retains only the configured number of book candidates", function()
        local yielded = 0
        install_lfs(function()
            return {
                { name = "f.epub" }, { name = "e.epub" }, { name = "d.epub" },
                { name = "c.epub" }, { name = "b.epub" }, { name = "a.epub" },
            }
        end, nil, function() yielded = yielded + 1 end)
        local FolderCover = require("modules/filebrowser/folder_cover")
        local menu = {
            name = "filemanager",
            genItemTableFromPath = function() error("child item table was constructed") end,
        }
        local entry = {
            path = "/library/folder",
            attr = { mode = "directory" },
            mandatory = "6 \xef\x80\x96",
        }

        local gallery = FolderCover.build(menu, entry, "Folder", 80, 120)
        assert.are.equal(6, gallery.count)
        assert.are.equal(4, #gallery.entries)
        assert.are.equal("/library/folder/f.epub", gallery.entries[1].path)
        assert.are.equal(4, yielded)

        cover_mode = "normal"
        local single = FolderCover.build(menu, entry, "Folder", 80, 120)
        assert.are.equal(6, single.count)
        assert.are.equal(1, #single.entries)
        assert.are.equal(1, calls.collect[#calls.collect].limit)
    end)

    it("stops after one candidate in single mode when the parent supplied the count", function()
        local yielded = 0
        cover_mode = "normal"
        install_lfs(function()
            return {
                { name = "first.epub" }, { name = "second.epub" },
                { name = "third.epub" }, { name = "fourth.epub" },
            }
        end, nil, function() yielded = yielded + 1 end)
        local FolderCover = require("modules/filebrowser/folder_cover")
        local result = FolderCover.build({ name = "filemanager" }, {
            path = "/library/folder",
            attr = { mode = "directory" },
            mandatory = "4 \xef\x80\x96",
        }, "Folder", 80, 120)

        assert.are.equal(1, yielded)
        assert.are.equal(4, result.count)
        assert.are.equal(1, #result.entries)
        assert.are.equal(1, calls.collect[1].limit)
    end)

    it("shares candidate one across modes and adds only three gallery candidates", function()
        install_lfs(function()
            return {
                { name = "first.epub" }, { name = "second.epub" },
                { name = "third.epub" }, { name = "fourth.epub" },
            }
        end)
        local FolderCover = require("modules/filebrowser/folder_cover")
        local entry = {
            path = "/library/folder",
            attr = { mode = "directory" },
            mandatory = "4 books",
        }

        local single = FolderCover.previewEntries({}, entry, 1)
        local gallery = FolderCover.previewEntries({}, entry, 4)

        assert.are.equal("/library/folder/first.epub", single[1].path)
        assert.are.equal(single[1].path, gallery[1].path)
        assert.are.equal(4, #gallery)
    end)

    it("reuses bounded physical-folder descriptors until invalidated", function()
        local enumerations = 0
        install_lfs(function(path)
            return { { name = path:match("([^/]+)$") .. ".epub" } }
        end, function() enumerations = enumerations + 1 end)
        local FolderCover = require("modules/filebrowser/folder_cover")
        local menu = {
            name = "filemanager",
            genItemTableFromPath = function() error("child item table was constructed") end,
        }
        local entry = { path = "/library/folder", attr = { mode = "directory" } }

        FolderCover.build(menu, entry, "Folder/", 80, 120)
        local cached = FolderCover.build(menu, entry, "Folder/", 80, 120)

        assert.are.equal(1, enumerations)
        assert.is_true(cached.perf.descriptor_cache_hit)

        FolderCover.clear(entry.path)
        local rebuilt = FolderCover.build(menu, entry, "Folder/", 80, 120)
        assert.are.equal(2, enumerations)
        assert.is_false(rebuilt.perf.descriptor_cache_hit)
    end)

    it("evicts the oldest folder descriptor after 32 folders", function()
        local enumerations = 0
        install_lfs(function()
            return { { name = "book.epub" } }
        end, function() enumerations = enumerations + 1 end)
        local FolderCover = require("modules/filebrowser/folder_cover")
        local menu = {
            name = "filemanager",
            genItemTableFromPath = function() error("child item table was constructed") end,
        }
        for index = 1, 33 do
            FolderCover.build(menu, {
                path = "/library/folder-" .. index,
                attr = { mode = "directory" },
            }, "Folder", 80, 120)
        end

        local rebuilt = FolderCover.build(menu, {
            path = "/library/folder-1",
            attr = { mode = "directory" },
        }, "Folder", 80, 120)

        assert.are.equal(34, enumerations)
        assert.is_false(rebuilt.perf.descriptor_cache_hit)
    end)

    it("passes non-uniform sizing through to group previews", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        FolderCover.build({}, {
            _zen_files = { "/library/landscape.epub" },
        }, "Author", 80, 120, { uniform = false })

        assert.is_false(calls.uniform)
    end)

    it("reports cached-only folder previews that still need hydration", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        calls.collect_pending = true

        local result = FolderCover.build({}, {
            _zen_files = { "/library/cold.epub" },
        }, "Author", 80, 120, { cached_only = true })

        assert.is_true(calls.collect[1].cached_only)
        assert.is_true(result.needs_hydration)
        assert.are.equal(1, result.cover_count)
    end)

    it("reuses a complete gallery bitmap without loading its child covers", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        calls.gallery_cache_key = "gallery:key"
        calls.cached_gallery = { kind = "gallery", bordersize = 2 }

        local result = FolderCover.build({}, {
            _zen_files = { "/library/a.epub", "/library/b.epub" },
        }, "Author", 80, 120)

        assert.are.equal(0, #calls.collect)
        assert.are.equal("gallery:key", calls.gallery_lookup_key)
        assert.is_true(result.perf.composite_cache_hit)
        assert.are.equal(2, result.cover_count)
    end)

    it("warms and releases one complete gallery bitmap", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        calls.gallery_cache_key = "gallery:key"
        calls.cached_gallery = nil

        local warmed, cached = FolderCover.warmGallery({}, {
            _zen_files = { "/library/a.epub" },
        }, "Author", 80, 120)

        assert.is_true(warmed)
        assert.is_false(cached)
        assert.is_true(calls.gallery_freed)
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

    it("matches mosaic spine proportions in list view", function()
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
            orientation = "left", rounded = true,
        })

        assert.are.same({
            { x = 21, y = 13, width = 3, height = 76 },
            { x = 26, y = 11, width = 3, height = 79 },
        }, rects)
    end)

    it("rounds spine line ends when supported by the blitbuffer", function()
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_self, value) return math.floor(value + 0.5) end },
        })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_GRAY_4 = 4, COLOR_BLACK = 0 })
        ZenSpec.replace("ui/size", { line = { medium = 2 } })
        ZenSpec.unload("modules/filebrowser/folder_cover")
        local FolderCover = require("modules/filebrowser/folder_cover")
        local rounded = {}
        local bb = {
            paintRoundedRect = function(_self, x, y, width, height, _color, radius)
                rounded[#rounded + 1] = {
                    x = x, y = y, width = width, height = height, radius = radius,
                }
            end,
        }

        FolderCover.paintSpines(bb, {
            dimen = { x = 30, y = 6, w = 60, h = 90 },
        }, 0, 0, { orientation = "left", rounded = true })

        assert.are.same({
            { x = 21, y = 13, width = 3, height = 76, radius = 1 },
            { x = 26, y = 11, width = 3, height = 79, radius = 1 },
        }, rounded)
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

    it("counts all virtual members while retaining only preview candidates", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local files = {}
        for index = 1, 6 do files[index] = "/library/book-" .. index .. ".epub" end

        local gallery = FolderCover.build({}, { _zen_files = files }, "Author", 80, 120)
        assert.are.equal(6, gallery.count)
        assert.are.equal(4, #gallery.entries)

        cover_mode = "normal"
        local single = FolderCover.build({}, { _zen_files = files }, "Author", 80, 120)
        assert.are.equal(6, single.count)
        assert.are.equal(1, #single.entries)
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

    it("uses virtual-group size without building member descriptors when suppressed", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local result = FolderCover.build({}, {
            _zen_files = { "/library/a.epub", "/library/b.epub" },
        }, "Author", 80, 120, { load_covers = false })

        assert.are.equal(2, result.count)
        assert.is_nil(result.entries)
        assert.are.equal(0, #calls.collect)
    end)

    it("preserves numeric collection counts when cover loading is suppressed", function()
        local FolderCover = require("modules/filebrowser/folder_cover")
        local result = FolderCover.build({ _zen_coll_list = true }, {
            name = "favorites", mandatory = 3,
        }, "Favorites", 80, 120, { load_covers = false })

        assert.are.equal(3, result.count)
    end)
end)

describe("cover utility policy", function()
    local CoverUtils

    before_each(function()
        _G.G_reader_settings = ZenSpec.memorySettings({ uniform_cover_ratio = "2:3" })
        ZenSpec.replace("ffi/blitbuffer", {})
        ZenSpec.replace("modules/filebrowser/patches/library_font", {})
        ZenSpec.replace("ui/widget/textboxwidget", {})
        ZenSpec.replace("ui/rendertext", {})
        ZenSpec.replace("ui/bidi", { directory = function(text) return text end })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")
    end)

    it("calculates portrait cover dimensions from the configured ratio", function()
        assert.are.same({ 200, 300 }, { CoverUtils.calcDims(300, 300) })
        _G.G_reader_settings:saveSetting("uniform_cover_ratio", "3:4")
        assert.are.same({ 225, 300 }, { CoverUtils.calcDims(300, 300) })
        assert.are.same({ 300, 400 }, { CoverUtils.calcDims(300, 500) })
    end)

    it("describes each empty home-book source", function()
        assert.are.equal("No recently read books found", CoverUtils.getEmptyPlaceholderText("recently_read"))
        assert.are.equal("No TBR books found", CoverUtils.getEmptyPlaceholderText("to_be_read"))
        assert.are.equal(
            "No books found in the selected folder",
            CoverUtils.getEmptyPlaceholderText("custom_strip")
        )
    end)

    it("enforces and persists the readable files-per-page cap", function()
        local saved
        ZenSpec.replace("bookinfomanager", {
            getSetting = function() return 20 end,
            saveSetting = function(_, _, value) saved = value end,
        })
        ZenSpec.replace("ui/widget/filechooser", { files_per_page = 20 })
        ZenSpec.replace("apps/filemanager/filemanager", { instance = nil })
        assert.are.equal(12, CoverUtils.getFilesPerPage())
        assert.are.equal(12, saved)
    end)

    it("maps configured folder cover modes to cover counts and gallery behavior", function()
        _G.__ZEN_UI_PLUGIN = { config = { browser_folder_cover = { cover_mode = "gallery" } } }
        assert.are.same({ "gallery", 4, true }, { CoverUtils.getMode() })
        _G.__ZEN_UI_PLUGIN.config.browser_folder_cover.cover_mode = "none"
        assert.are.same({ "none", 0, false }, { CoverUtils.getMode() })
    end)

    it("keeps tiny synthetic covers to one bulk fill", function()
        local paints = {}
        local pixels = 0
        local requested_cover
        ZenSpec.replace("ffi/blitbuffer", {
            TYPE_BBRGB32 = 4,
            ColorRGB32 = function(...) return { ... } end,
            new = function()
                return {
                    paintRect = function(_self, ...)
                        paints[#paints + 1] = { ... }
                    end,
                    setPixel = function() pixels = pixels + 1 end,
                }
            end,
        })
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function(_self, _path, get_cover)
                requested_cover = get_cover
                return nil
            end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")

        CoverUtils.genCover("/book.epub", 3, 3)

        assert.are.equal(1, #paints)
        assert.are.equal(0, pixels)
        assert.is_false(requested_cover)
    end)

    it("uses supplied metadata without another BookInfo lookup", function()
        local lookups = 0
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function()
                lookups = lookups + 1
                return nil
            end,
        })
        ZenSpec.replace("ffi/blitbuffer", {
            TYPE_BBRGB32 = 4,
            ColorRGB32 = function(...) return { ... } end,
            new = function()
                return {
                    paintRect = function() end,
                    setPixel = function() end,
                }
            end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")

        CoverUtils.genCover("/book.epub", 3, 3, nil, false)

        assert.are.equal(0, lookups)
    end)

    it("keeps every grouped-book slot when a cached cover is stale or missing", function()
        local real_frees = 0
        local stale_frees = 0
        local generated = {}
        local real_bb = {
            copy = function() return "real-copy" end,
            free = function() real_frees = real_frees + 1 end,
        }
        local stale_bb = {
            free = function() stale_frees = stale_frees + 1 end,
        }
        local info = {
            ["/real.epub"] = {
                cover_bb = real_bb,
                cover_w = 100,
                cover_h = 150,
                cover_fetched = true,
                has_cover = true,
            },
            ["/stale.epub"] = {
                cover_bb = stale_bb,
                cover_w = 50,
                cover_h = 75,
                cover_fetched = true,
                has_cover = true,
                stale = true,
            },
            ["/missing.epub"] = {
                cover_fetched = true,
                has_cover = false,
                title = "Missing",
            },
        }
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function(_self, path) return info[path] end,
            isCachedCoverInvalid = function(bookinfo) return bookinfo.stale == true end,
        })
        local stale_metadata = { title = "Stale", authors = "Author" }
        CoverUtils.genCover = function(path, _width, _height, _no_fallback, metadata)
            generated[#generated + 1] = { path = path, metadata = metadata }
            return "placeholder:" .. path, 100, 150
        end

        local covers = CoverUtils.collect(nil, nil, 4, true, {
            { path = "/real.epub", is_file = true },
            { path = "/stale.epub", is_file = true, doc_props = stale_metadata },
            { path = "/missing.epub", is_file = true },
        }, { max_cover_w = 100, max_cover_h = 150 })

        assert.are.equal(3, #covers)
        assert.are.same({ "real-copy", "placeholder:/stale.epub", "placeholder:/missing.epub" }, {
            covers[1].data,
            covers[2].data,
            covers[3].data,
        })
        assert.are.equal(stale_metadata, generated[1].metadata)
        assert.are.equal(info["/missing.epub"], generated[2].metadata)
        assert.are.equal(1, real_frees)
        assert.are.equal(1, stale_frees)
    end)

    it("uses the book placeholder renderer for title-only folder covers", function()
        local request
        local function container()
            return { new = function(_self, values) return values end }
        end
        ZenSpec.replace("ui/widget/container/centercontainer", container())
        ZenSpec.replace("ui/widget/container/framecontainer", container())
        ZenSpec.replace("ui/widget/imagewidget", container())
        CoverUtils.genCover = function(path, width, height, no_fallback, metadata)
            request = {
                path = path,
                width = width,
                height = height,
                no_fallback = no_fallback,
                metadata = metadata,
            }
            return "folder-placeholder"
        end

        CoverUtils.drawNoImage("Empty Shelf", 100, 150, 2)

        assert.are.equal("zen-folder-placeholder:Empty Shelf", request.path)
        assert.are.same({ title = "Empty Shelf", authors = "", title_only = true }, request.metadata)
        assert.is_true(request.no_fallback)
    end)

    it("draws and caches the ornate placeholder cover", function()
        local paint_calls = 0
        local svg_renders = 0
        local ornament_frees = 0
        local rendered_path
        local cached = {}
        local mask_blits = 0
        local opaque_text_paints = 0
        local background_colors = {}
        local text_configs = {}
        local function cache_key(key, width, height)
            return table.concat({ key, width, height }, "\31")
        end
        ZenSpec.replace("ffi/blitbuffer", {
            TYPE_BBRGB32 = 4,
            COLOR_BLACK = "black",
            COLOR_WHITE = "white",
            ColorRGB32 = function(...) return { ... } end,
            new = function()
                return {
                    paintRect = function(_self, _x, _y, _width, _height, color)
                        paint_calls = paint_calls + 1
                        background_colors[#background_colors + 1] = color
                    end,
                    alphablitFrom = function() paint_calls = paint_calls + 1 end,
                    pmulalphablitFrom = function() paint_calls = paint_calls + 1 end,
                    colorblitFrom = function()
                        paint_calls = paint_calls + 1
                        mask_blits = mask_blits + 1
                    end,
                }
            end,
        })
        ZenSpec.replace("modules/filebrowser/patches/library_font", {
            getFontName = function() return "cfont" end,
            getBaseSize = function() return 18 end,
            scaleValue = function(value) return value end,
            getFace = function() return {} end,
        })
        ZenSpec.replace("ui/widget/textboxwidget", {
            new = function(_self, values)
                text_configs[#text_configs + 1] = values
                values.getSize = function() return { w = 40, h = 12 } end
                values.paintTo = function()
                    paint_calls = paint_calls + 1
                    opaque_text_paints = opaque_text_paints + 1
                end
                values.free = function() end
                values._bb = { invert = function() end }
                return values
            end,
        })
        ZenSpec.replace("ui/rendertext", { getEllipsisWidth = function() return 0 end })
        ZenSpec.replace("ui/renderimage", {
            renderSVGImageFile = function(_self, path)
                svg_renders = svg_renders + 1
                rendered_path = path
                return {
                    free = function() ornament_frees = ornament_frees + 1 end,
                }, true
            end,
        })
        ZenSpec.replace("common/cover_render_cache", {
            get = function(_self, key, width, height)
                return cached[cache_key(key, width, height)]
            end,
            put = function(_self, key, width, height, bb)
                cached[cache_key(key, width, height)] = bb
            end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")

        CoverUtils.genCover("/book.epub", 120, 180, nil, {
            title = "A Classic Title",
            authors = "An Author",
        })
        local first_paint_count = paint_calls
        CoverUtils.genCover("/book.epub", 120, 180, nil, {
            title = "A Classic Title",
            authors = "An Author",
        })

        assert.is_true(first_paint_count >= 4)
        assert.are.equal(first_paint_count, paint_calls)
        assert.are.equal(1, svg_renders)
        assert.are.equal(1, ornament_frees)
        assert.are.equal(2, mask_blits)
        assert.are.equal(0, opaque_text_paints)
        assert.are.equal("white", background_colors[1])
        assert.are.equal("black", text_configs[1].fgcolor)
        assert.are.equal("white", text_configs[1].bgcolor)
        assert.matches("images/ornate%-cover%-frame%.svg$", rendered_path)

        CoverUtils.genCover("/another-book.epub", 120, 180, nil, {
            title = "Another Classic",
            authors = "Another Author",
        })
        assert.are.equal(1, svg_renders)
        assert.are.equal(4, mask_blits)

        CoverUtils.genCover("zen-empty-placeholder", 120, 180, true, {
            title = "No books found",
            authors = "",
            title_only = true,
        })
        assert.are.equal(5, mask_blits)
        assert.are.equal("No books found", text_configs[5].text)
    end)

    it("does not pre-scale folder covers before the selected renderer", function()
        _G.__ZEN_UI_PLUGIN = { config = { browser_folder_cover = { cover_mode = "stack" } } }
        local source = {}
        local received
        local scale_calls = 0
        CoverUtils.scaleCover = function()
            scale_calls = scale_calls + 1
            return {}
        end
        CoverUtils.drawStack = function(covers)
            received = covers
            return "stack-widget"
        end

        local widget = CoverUtils.makeCover("/folder", nil, {
            is_folder = true,
            max_w = 200,
            max_h = 300,
            covers_data = { { data = source, w = 100, h = 150 } },
        })

        assert.are.equal("stack-widget", widget)
        assert.are.equal(source, received[1].data)
        assert.are.equal(0, scale_calls)
    end)
end)

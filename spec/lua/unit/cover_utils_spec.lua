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
        ZenSpec.replace("common/cover_decode_cache", {
            getFreshMetadata = function() end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")
    end)

    it("calculates portrait cover dimensions from the configured ratio", function()
        assert.are.same({ 200, 300 }, { CoverUtils.calcDims(300, 300) })
        _G.G_reader_settings:saveSetting("uniform_cover_ratio", "3:4")
        assert.are.same({ 225, 300 }, { CoverUtils.calcDims(300, 300) })
        assert.are.same({ 300, 400 }, { CoverUtils.calcDims(300, 500) })
    end)

    it("fits real covers without changing their aspect ratio", function()
        assert.are.same({ 100, 67 }, { CoverUtils.fitDims(100, 150, 120, 80) })
        assert.are.same({ 60, 150 }, { CoverUtils.fitDims(100, 150, 80, 200) })
    end)

    it("uses the shared crop renderer for real single-book covers", function()
        local source = {}
        local render_request
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function()
                return {
                    cover_bb = source,
                    cover_w = 120,
                    cover_h = 80,
                    has_cover = true,
                    cover_fetched = true,
                }
            end,
        })
        ZenSpec.replace("common/cover_render_cache", {
            get = function() end,
            put = function() end,
            render = function(_self, cache_key, cover_bb, width, height)
                render_request = {
                    cache_key = cache_key,
                    cover_bb = cover_bb,
                    width = width,
                    height = height,
                }
                return "cropped-cover"
            end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")

        local cover_bb, width, height, mode, kind = CoverUtils.makeCover(
            "/landscape.epub", nil, { is_folder = false, width = 100, height = 150 })

        assert.are.equal("cropped-cover", cover_bb)
        assert.are.same({
            cache_key = "/landscape.epub",
            cover_bb = source,
            width = 100,
            height = 150,
        }, render_request)
        assert.are.same({ 100, 150, "single", "real_cover" }, { width, height, mode, kind })
    end)

    it("describes each empty home-book source", function()
        assert.are.equal("Start reading a book to fill this space.",
            CoverUtils.getEmptyPlaceholderText("recently_read"))
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
        _G.__ZEN_UI_PLUGIN.config.browser_folder_cover.cover_mode = "stack"
        assert.are.same({ "stack", 4, true }, { CoverUtils.getMode() })
        _G.__ZEN_UI_PLUGIN.config.browser_folder_cover.cover_mode = "normal"
        assert.are.same({ "normal", 1, false }, { CoverUtils.getMode() })
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

    it("reuses preloaded no-cover metadata for folder candidates", function()
        local metadata = {
            cover_fetched = "Y",
            has_cover = false,
            title = "Generated",
        }
        _G.__ZEN_UI_PLUGIN = {
            config = { browser_folder_cover = { cover_mode = "gallery" } },
        }
        ZenSpec.replace("common/cover_decode_cache", {
            getFreshMetadata = function(_self, path)
                return path == "/generated.epub" and metadata or nil
            end,
        })
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function() error("unexpected BookInfo lookup") end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")
        local generated_request
        CoverUtils.genCover = function(_path, width, height, _no_fallback, bookinfo)
            generated_request = { width = width, height = height, metadata = bookinfo }
            return "generated-cover", 100, 150
        end

        local covers = CoverUtils.collect(nil, nil, 1, false, {
            { path = "/generated.epub", is_file = true },
        }, { max_cover_w = 100, max_cover_h = 150, uniform = true })

        assert.are.equal(1, #covers)
        assert.are.equal("generated-cover", covers[1].data)
        assert.are.same({ width = 49, height = 74, metadata = metadata }, generated_request)
    end)

    it("uses a final-render hit before loading a decoded folder cover", function()
        local metadata = {
            cover_fetched = "Y",
            has_cover = "Y",
            cover_w = 120,
            cover_h = 180,
        }
        local cache_request
        _G.__ZEN_UI_PLUGIN = {
            config = { browser_folder_cover = { cover_mode = "gallery" } },
        }
        ZenSpec.replace("common/cover_decode_cache", {
            getFreshMetadata = function() return metadata end,
        })
        ZenSpec.replace("common/cover_render_cache", {
            get = function(_self, path, width, height)
                cache_request = { path = path, width = width, height = height }
                return "cached-preview"
            end,
        })
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function() error("unexpected decoded-cover lookup") end,
            isCachedCoverInvalid = function() return false end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")

        local covers = CoverUtils.collect(nil, nil, 4, true, {
            { path = "/cached.epub", is_file = true },
        }, { max_cover_w = 100, max_cover_h = 150, uniform = true })

        assert.are.same({ path = "/cached.epub", width = 49, height = 73 }, cache_request)
        assert.are.equal("cached-preview", covers[1].data)
        assert.is_nil(covers[1].cache_key)
    end)

    it("keeps cached folder previews and defers cold cover reads", function()
        local metadata = {
            ["/cached.epub"] = {
                cover_fetched = "Y", has_cover = "Y", cover_w = 120, cover_h = 180,
            },
            ["/cold.epub"] = {
                cover_fetched = "Y", has_cover = "Y", cover_w = 120, cover_h = 180,
            },
            ["/generated.epub"] = {
                cover_fetched = "Y", has_cover = false, title = "Generated",
            },
        }
        local lookups = 0
        local render_requests = {}
        _G.__ZEN_UI_PLUGIN = {
            config = { browser_folder_cover = { cover_mode = "gallery" } },
        }
        ZenSpec.replace("common/cover_decode_cache", {
            getFreshMetadata = function(_self, path) return metadata[path] end,
        })
        ZenSpec.replace("common/cover_render_cache", {
            get = function(_self, path)
                render_requests[#render_requests + 1] = path
                if path == "/cached.epub" then return "cached-preview" end
            end,
        })
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function()
                lookups = lookups + 1
                return nil
            end,
            isCachedCoverInvalid = function() return false end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")
        CoverUtils.genCover = function() error("foreground placeholder was generated") end

        local covers, needs_hydration = CoverUtils.collect(nil, nil, 4, true, {
            { path = "/cached.epub", is_file = true },
            { path = "/cold.epub", is_file = true },
            { path = "/generated.epub", is_file = true },
        }, { max_cover_w = 100, max_cover_h = 150, uniform = true }, 0, true)

        assert.are.equal(0, lookups)
        assert.is_true(needs_hydration)
        assert.are.equal(1, #covers)
        assert.are.equal("cached-preview", covers[1].data)
        assert.are.same({ "/cached.epub", "/cold.epub" }, render_requests)
    end)

    it("reuses a cached generated preview without creating one in the initial pass", function()
        local metadata = { cover_fetched = "Y", has_cover = false, title = "Generated" }
        _G.__ZEN_UI_PLUGIN = {
            config = { browser_folder_cover = { cover_mode = "gallery" } },
        }
        ZenSpec.replace("common/cover_decode_cache", {
            getFreshMetadata = function() return metadata end,
        })
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function() error("unexpected BookInfo lookup") end,
            isCachedCoverInvalid = function() return false end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")
        CoverUtils.getCachedGeneratedCover = function(path, width, height, _no_fallback, info)
            assert.are.equal("/generated.epub", path)
            assert.are.same(metadata, info)
            return "cached-generated", width, height
        end

        local covers, needs_hydration = CoverUtils.collect(nil, nil, 1, false, {
            { path = "/generated.epub", is_file = true },
        }, { max_cover_w = 100, max_cover_h = 150, uniform = true }, 0, true)

        assert.is_false(needs_hydration)
        assert.are.equal("cached-generated", covers[1].data)
    end)

    it("loads a stale real folder cover during hydration using preview-sized validation", function()
        local metadata = {
            cover_fetched = "Y", has_cover = "Y", cover_w = 30, cover_h = 45,
        }
        local real_cover = { free = function() end }
        local requested_cover
        local validated_specs
        _G.__ZEN_UI_PLUGIN = {
            config = { browser_folder_cover = { cover_mode = "gallery" } },
        }
        ZenSpec.replace("common/cover_decode_cache", {
            getFreshMetadata = function() return metadata end,
        })
        ZenSpec.replace("common/cover_render_cache", { get = function() end })
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function(_self, _path, get_cover)
                requested_cover = get_cover
                return {
                    cover_fetched = "Y", has_cover = "Y",
                    cover_w = 30, cover_h = 45, cover_bb = real_cover,
                }
            end,
            isCachedCoverInvalid = function(_info, specs)
                validated_specs = specs
                return true
            end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")

        local covers = CoverUtils.collect(nil, nil, 1, false, {
            { path = "/stale.epub", is_file = true },
        }, { max_cover_w = 100, max_cover_h = 150, uniform = true })

        assert.is_true(requested_cover)
        assert.are.same({ max_cover_w = 49, max_cover_h = 74 }, validated_specs)
        assert.are.equal(real_cover, covers[1].data)
        assert.are.equal("/stale.epub", covers[1].cache_key)
    end)

    it("keeps every grouped-book slot when a cached cover is stale or missing", function()
        local real_frees = 0
        local real_copies = 0
        local stale_frees = 0
        local generated = {}
        local real_bb = {
            copy = function()
                real_copies = real_copies + 1
                return "real-copy"
            end,
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
        _G.__ZEN_UI_PLUGIN = {
            config = { browser_folder_cover = { cover_mode = "gallery" } },
        }
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
        assert.are.same({ real_bb, stale_bb, "placeholder:/missing.epub" }, {
            covers[1].data,
            covers[2].data,
            covers[3].data,
        })
        assert.are.equal("/real.epub", covers[1].cache_key)
        assert.are.equal("/stale.epub", covers[2].cache_key)
        assert.are.equal(info["/missing.epub"], generated[1].metadata)
        assert.are.equal(0, real_copies)
        assert.are.equal(0, real_frees)
        assert.are.equal(0, stale_frees)
        covers[2].data:free()
        assert.are.equal(1, stale_frees)
        covers[1].data:free()
        assert.are.equal(1, real_frees)
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

        local frame = CoverUtils.drawNoImage("Empty Shelf", 100, 150, 2)

        assert.are.equal("zen-folder-placeholder:Empty Shelf", request.path)
        assert.are.same({ title = "Empty Shelf", authors = "", title_only = true }, request.metadata)
        assert.is_true(request.no_fallback)
        assert.is_true(frame[1][1].original_in_nightmode)
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
        local color_mask_blits = 0
        local color_mask_colors = {}
        local ornament_inverts = 0
        local rgb_background_paints = 0
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
                    paintRectRGB32 = function(_self, _x, _y, _width, _height, color)
                        paint_calls = paint_calls + 1
                        rgb_background_paints = rgb_background_paints + 1
                        background_colors[#background_colors + 1] = color
                    end,
                    alphablitFrom = function() paint_calls = paint_calls + 1 end,
                    pmulalphablitFrom = function() paint_calls = paint_calls + 1 end,
                    colorblitFrom = function()
                        paint_calls = paint_calls + 1
                        mask_blits = mask_blits + 1
                    end,
                    colorblitFromRGB32 = function(_self, _mask, _x, _y, _sx, _sy, _width, _height, color)
                        paint_calls = paint_calls + 1
                        color_mask_blits = color_mask_blits + 1
                        color_mask_colors[#color_mask_colors + 1] = color
                    end,
                }
            end,
        })
        ZenSpec.replace("device", { screen = {
            isColorScreen = function() return true end,
            isColorEnabled = function() return false end,
        } })
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
                    getWidth = function() return 120 end,
                    getHeight = function() return 180 end,
                    invertRect = function() ornament_inverts = ornament_inverts + 1 end,
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

        ZenSpec.replace("device", { screen = {
            isColorScreen = function() return true end,
            isColorEnabled = function() return true end,
        } })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")
        CoverUtils.genCover("/color-book.epub", 120, 180, nil, {
            title = "A Color Title",
            authors = "An Author",
        })
        assert.are.equal("white", background_colors[1])
        assert.are.equal(0, rgb_background_paints)
        assert.are.equal(7, mask_blits)
        assert.are.equal(0, color_mask_blits)
        assert.are.equal(0, ornament_inverts)
        assert.are.equal(1, svg_renders)
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

    it("sizes one-book stack previews with the uniform-cover policy", function()
        local function container()
            return { new = function(_self, values) return values end }
        end
        ZenSpec.replace("ui/widget/container/centercontainer", container())
        ZenSpec.replace("ui/widget/container/framecontainer", container())
        ZenSpec.replace("ui/widget/imagewidget", container())
        ZenSpec.replace("ui/widget/overlapgroup", container())
        ZenSpec.replace("ui/widget/verticalspan", container())

        local natural = CoverUtils.drawStack({ {
            data = {}, w = 120, h = 80,
        } }, 100, 150, 2, nil, false)
        local natural_image = natural[1][1]
        assert.are.equal(104, natural.width)
        assert.are.equal(71, natural.height)
        assert.are.equal(100, natural_image.width)
        assert.are.equal(67, natural_image.height)
        assert.are.equal(0, natural_image.scale_factor)

        local uniform = CoverUtils.drawStack({ {
            data = {}, w = 120, h = 80,
        } }, 100, 150, 2, nil, true)
        local uniform_image = uniform[1][1]
        assert.are.equal(104, uniform.width)
        assert.are.equal(154, uniform.height)
        assert.are.equal(100, uniform_image.width)
        assert.are.equal(150, uniform_image.height)
        assert.are.equal(1.875, uniform_image.scale_factor)
    end)

    it("does not rescale an exact cached gallery preview", function()
        local images = {}
        local function container()
            return { new = function(_self, values) return values end }
        end
        ZenSpec.replace("ui/widget/container/centercontainer", container())
        ZenSpec.replace("ui/widget/container/framecontainer", container())
        ZenSpec.replace("ui/widget/horizontalgroup", container())
        ZenSpec.replace("ui/widget/linewidget", container())
        ZenSpec.replace("ui/widget/verticalgroup", container())
        ZenSpec.replace("ui/widget/verticalspan", container())
        ZenSpec.replace("ui/widget/imagewidget", {
            new = function(_self, values)
                images[#images + 1] = values
                return values
            end,
        })

        CoverUtils.drawGallery({ {
            data = "cached-preview", w = 49, h = 74,
        } }, 100, 150, 2, function() return "background" end, false)

        assert.are.equal(1, images[1].scale_factor)
        assert.are.equal(49, images[1].width)
        assert.are.equal(74, images[1].height)
    end)

    it("uses the shared final-render path for real group previews", function()
        local request
        local function container()
            return { new = function(_self, values) return values end }
        end
        ZenSpec.replace("ui/widget/container/centercontainer", container())
        ZenSpec.replace("ui/widget/container/framecontainer", container())
        ZenSpec.replace("ui/widget/imagewidget", container())
        ZenSpec.replace("common/cover_render_cache", {
            render = function(_self, key, _source, width, height)
                request = { key = key, width = width, height = height }
                return "final-cover"
            end,
        })
        ZenSpec.unload("common/cover_utils")
        CoverUtils = require("common/cover_utils")

        local frame = CoverUtils.drawSingle({
            data = "decoded-cover",
            w = 120,
            h = 180,
            cache_key = "/book.epub",
        }, 100, 150, 2, true)

        assert.are.same({ key = "/book.epub", width = 100, height = 150 }, request)
        assert.are.equal("final-cover", frame[1][1].image)
        assert.are.equal(1, frame[1][1].scale_factor)
    end)
end)

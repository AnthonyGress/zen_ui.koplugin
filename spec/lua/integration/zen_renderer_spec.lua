describe("Zen renderer", function()
    local MosaicMenu
    local stock_created
    local cover_requests
    local folder_requests
    local painted_text
    local native_progress_paints
    local native_progress
    local banner_labels
    local banner_sizes
    local background_menus
    local calc_dimensions
    local folder_name_labels

    local function class(base)
        local out = {}
        out.__index = out
        setmetatable(out, { __index = base })
        function out:extend(values)
            local child = class(self)
            for key, value in pairs(values or {}) do child[key] = value end
            return child
        end
        function out:new(values)
            values = values or {}
            setmetatable(values, self)
            if values.init then values:init() end
            return values
        end
        function out:paintTo() end
        function out:free() end
        return out
    end

    before_each(function()
        stock_created = 0
        cover_requests = {}
        folder_requests = {}
        painted_text = {}
        native_progress_paints = 0
        native_progress = nil
        banner_labels = {}
        banner_sizes = {}
        background_menus = {}
        folder_name_labels = {}
        calc_dimensions = function(width, height) return width, height end
        local MosaicMenuItem = class()
        function MosaicMenuItem:new(values)
            stock_created = stock_created + 1
            values.bookinfo_found = true
            values.is_directory = true
            return values
        end
        local function stock_builder()
            return MosaicMenuItem
        end
        MosaicMenu = { _updateItemsBuildUI = stock_builder }
        ZenSpec.replace("mosaicmenu", MosaicMenu)
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function() return nil end,
            isCachedCoverInvalid = function() return false end,
        })
        ZenSpec.replace("device", {
            screen = {
                scaleBySize = function(_self, value) return value end,
            },
        })
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("ui/bidi", {
            mirroredUILayout = function() return false end,
            directory = function(text) return text end,
        })
        ZenSpec.replace("ui/geometry", { new = function(_self, values) return values end })
        ZenSpec.replace("ui/gesturerange", { new = function(_self, values) return values end })
        ZenSpec.replace("ui/widget/imagewidget", class())
        ZenSpec.replace("ui/widget/container/inputcontainer", class())
        local function widget_class()
            local Widget = class()
            function Widget:new(values) return values end
            return Widget
        end
        ZenSpec.replace("ui/widget/container/centercontainer", widget_class())
        ZenSpec.replace("ui/widget/container/alphacontainer", widget_class())
        ZenSpec.replace("ui/widget/container/bottomcontainer", widget_class())
        ZenSpec.replace("ui/widget/container/framecontainer", widget_class())
        ZenSpec.replace("ui/widget/horizontalgroup", widget_class())
        ZenSpec.replace("ui/widget/horizontalspan", widget_class())
        ZenSpec.replace("ui/widget/container/leftcontainer", widget_class())
        ZenSpec.replace("ui/widget/overlapgroup", widget_class())
        ZenSpec.replace("ui/widget/textwidget", {
            new = function(_self, values)
                values.getSize = function(self)
                    return { w = #tostring(self.text or "") * 5, h = 8 }
                end
                values.paintTo = function(self)
                    painted_text[#painted_text + 1] = self.text
                end
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/textboxwidget", {
            new = function(_self, values)
                folder_name_labels[#folder_name_labels + 1] = values
                values.free = function() end
                return values
            end,
        })
        ZenSpec.replace("ui/widget/container/underlinecontainer", widget_class())
        ZenSpec.replace("ui/widget/verticalgroup", widget_class())
        ZenSpec.replace("ui/widget/verticalspan", widget_class())
        ZenSpec.replace("ui/size", { border = { thin = 1, default = 1 }, padding = { tiny = 1 }, line = { focus_indicator = 1 } })
        ZenSpec.replace("ui/widget/menu", { getMenuText = function(entry) return entry.title end })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_BLACK = 0, COLOR_WHITE = 1 })
        ZenSpec.replace("common/cover_render_cache", { render = function() return nil end })
        ZenSpec.replace("ui/widget/progresswidget", {
            new = function(_self, values)
                native_progress = values
                values.setPercentage = function(self, percentage) self.percentage = percentage end
                values.paintTo = function() native_progress_paints = native_progress_paints + 1 end
                return values
            end,
        })
        ZenSpec.replace("common/ui/corner_banner", {
            paint = function(_bb, _left, _right, _top, _height, span, thick, label)
                banner_labels[#banner_labels + 1] = label
                banner_sizes[#banner_sizes + 1] = { span = span, thick = thick }
            end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("common/book_status", {
            getFileStatusData = function()
                return { effective_status = "new", sidecar_checked = true }
            end,
            getEffectiveStatus = function(status) return status end,
        })
        ZenSpec.replace("common/cover_utils", {
            BORDER_SIZE = 2,
            calcDims = function(width, height) return calc_dimensions(width, height) end,
        })
        ZenSpec.replace("modules/filebrowser/folder_cover", {
            isBook = function(entry)
                return entry.is_file == true or type(entry.file) == "string"
                    or (entry.attr and entry.attr.mode == "file")
            end,
            isSupported = function(entry, menu)
                return entry.is_file == true or type(entry.file) == "string"
                    or (entry.attr and entry.attr.mode == "file")
                    or entry.is_go_up or entry.is_series_group or entry.series_items
                    or entry._zen_files or entry._zen_empty_placeholder
                    or (menu._zen_coll_list and entry.name)
                    or ((menu.name == "filemanager" or menu._zen_renderer)
                        and (entry.is_directory or (entry.attr and entry.attr.mode == "directory")))
            end,
            build = function(menu, entry, text, width, height, options)
                folder_requests[#folder_requests + 1] = {
                    menu = menu, entry = entry, text = text, options = options,
                }
                return {
                    frame = {
                        dimen = { w = width, h = height },
                        getSize = function()
                            return { w = width - 20, h = height - 20 }
                        end,
                    },
                    count = entry.count or 2,
                    title = text,
                    cover_count = options.load_covers and 1 or 0,
                    mode = "gallery",
                }
            end,
        })
        ZenSpec.replace("common/ui/background", {
            library_path = function() return "" end,
            paintScreenRegion = function() return false end,
            applyToMenu = function(menu)
                background_menus[#background_menus + 1] = menu
            end,
        })
        ZenSpec.replace("common/utils", {
            formatPageCount = function(pages) return pages .. " p." end,
            getStablePageCount = function(_path, pages) return pages end,
            getBadgeColor = function() return 2 end,
            getBadgeInset = function(radius) return math.floor(radius * 0.4) end,
            getBadgeScale = function(config)
                return config.browser_cover_badges.badge_size == "extra_large" and 1.5 or 1
            end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/widgets/cover_common", {
            BORDER_SIZE = 2,
            make_cover_widget = function(_book, width, height, options)
                cover_requests[#cover_requests + 1] = {
                    width = width,
                    height = height,
                    options = options,
                }
                return { dimen = { w = 66, h = 99 } }
            end,
        })
        ZenSpec.replace("modules/filebrowser/patches/library_font", {
            getFontName = function() return "cfont" end,
            getBaseSize = function() return 18 end,
            getFace = function() return {} end,
            scaleValue = function(value) return value end,
        })
        ZenSpec.replace("ui/widget/filechooser", { _updateItemsBuildUI = stock_builder })
        _G.G_reader_settings = {
            readSetting = function() return "2:3" end,
        }
        _G.__ZEN_UI_PLUGIN = {
            config = { features = { browser_cover_mosaic_uniform = true } },
        }
        ZenSpec.unload("modules/filebrowser/patches/zen_renderer")
    end)

    it("uses Zen tiles for books, folders, and virtual groups", function()
        require("modules/filebrowser/patches/zen_renderer")()
        local menu = {
            name = "filemanager",
            _zen_coll_list = true,
            item_table = {
                { title = "Book", is_file = true, path = "/book.epub" },
                { title = "Folder/", path = "/folder", attr = { mode = "directory" } },
                { title = "Series", is_series_group = true, series_items = {} },
                { title = "Author", _zen_files = { "/book.epub" } },
                { title = "Favorites", name = "favorites" },
                { title = "Unknown" },
            },
            item_group = {}, layout = {}, items_to_update = {}, page = 1,
            perpage = 6, nb_cols = 6, item_margin = 1, item_width = 100,
            item_height = 150, item_dimen = { copy = function() return {} end },
            inner_dimen = { w = 620 }, _do_cover_images = true,
        }

        MosaicMenu._updateItemsBuildUI(menu)

        assert.is_not_nil(MosaicMenu._zen_mosaic_item_class)
        assert.are.equal(1, stock_created)
        assert.are.equal(1, #menu.items_to_update)
        assert.are.equal(4, #folder_requests)
        assert.is_true(folder_requests[1].options.uniform)
        assert.is_true(folder_requests[1].options.cover_specs.uniform)
        assert.are.same({ width = 96, height = 144, options = {
            border = 2, uniform = true,
        } }, cover_requests[1])
        local found_stock_item = false
        for index = 1, 128 do
            local name = debug.getupvalue(MosaicMenu._updateItemsBuildUI, index)
            if name == "MosaicMenuItem" then
                found_stock_item = true
                break
            end
        end
        assert.is_true(found_stock_item)
    end)

    it("uses non-uniform sizing for group previews when configured", function()
        _G.__ZEN_UI_PLUGIN.config.features.browser_cover_mosaic_uniform = false
        calc_dimensions = function() return 64, 96 end
        require("modules/filebrowser/patches/zen_renderer")()
        local menu = {
            name = "authors",
            item_table = { { title = "Author", _zen_files = { "/book.epub" } } },
            item_group = {}, layout = {}, items_to_update = {}, page = 1,
            perpage = 1, nb_cols = 2, item_margin = 1, item_width = 100,
            item_height = 150, item_dimen = { copy = function() return {} end },
            inner_dimen = { w = 110 }, _do_cover_images = true,
        }

        MosaicMenu._updateItemsBuildUI(menu)

        assert.is_false(folder_requests[1].options.uniform)
        assert.is_false(folder_requests[1].options.cover_specs.uniform)
        assert.are.equal(96, folder_requests[1].options.cover_specs.max_cover_w)
        assert.are.equal(146, folder_requests[1].options.cover_specs.max_cover_h)
    end)

    it("uses Zen folder tiles and the library background for opted-in choosers", function()
        require("modules/filebrowser/patches/zen_renderer")()
        local menu = {
            _zen_renderer = true,
            item_table = {
                { title = "Destination", path = "/destination", is_directory = true },
            },
            item_group = {}, layout = {}, items_to_update = {}, page = 1,
            perpage = 1, nb_cols = 2, item_margin = 1, item_width = 100,
            item_height = 150, item_dimen = { copy = function() return {} end },
            inner_dimen = { w = 110 }, _do_cover_images = false,
        }

        MosaicMenu._updateItemsBuildUI(menu)

        assert.are.equal(0, stock_created)
        assert.are.equal(1, #folder_requests)
        assert.is_false(folder_requests[1].options.load_covers)
        assert.are.same({ menu }, background_menus)
    end)

    it("bounds two-line folder name labels to their cover when title strips are off", function()
        _G.__ZEN_UI_PLUGIN.config.browser_folder_cover = { name_opaque = true }
        _G.__ZEN_UI_PLUGIN.config.features.browser_cover_rounded_corners = true
        require("modules/filebrowser/patches/zen_renderer")()
        local function folder_menu(title)
            return {
                name = "filemanager",
                item_table = {
                    {
                        title = title or string.rep("Long folder name ", 12),
                        path = "/folder",
                        attr = { mode = "directory" },
                    },
                },
                item_group = {}, layout = {}, items_to_update = {}, page = 1,
                perpage = 1, nb_cols = 2, item_margin = 1, item_width = 100,
                item_height = 150, item_dimen = { copy = function() return {} end },
                inner_dimen = { w = 110 }, _do_cover_images = true,
            }
        end
        local menu = folder_menu()

        MosaicMenu._updateItemsBuildUI(menu)

        assert.are.equal(1, #folder_name_labels)
        local item = menu.layout[1][1]
        local overlay = item._underline_container[1][1]
        local label_container = overlay[2][1]
        local label_frame = label_container[1]
        local cover_size = item._zen_cover_frame:getSize()
        assert.are.equal(cover_size.w - 14, folder_name_labels[1].width)
        assert.are.equal(cover_size.w, label_container.dimen.w)
        assert.are.equal(cover_size.h, label_container.dimen.h)
        assert.are.equal(16, label_frame[1].dimen.h)
        assert.is_true(label_frame._zen_keep_background)
        assert.are.equal(8, label_frame.radius)
        assert.are.equal(8, label_frame._zen_bottom_corner_radius)
        assert.are.equal("center", folder_name_labels[1].alignment)
        assert.is_true(folder_name_labels[1].height_adjust)
        assert.is_true(folder_name_labels[1].height_overflow_show_ellipsis)
        assert.are.equal(16, folder_name_labels[1].height)

        _G.__ZEN_UI_PLUGIN.config.browser_folder_cover.name_opaque = false
        local translucent_menu = folder_menu()
        MosaicMenu._updateItemsBuildUI(translucent_menu)
        local translucent_overlay = translucent_menu.layout[1][1]._underline_container[1][1]
        local alpha_label = translucent_overlay[2][1][1]

        assert.are.equal(0.75, alpha_label.alpha)
        assert.is_true(alpha_label[1]._zen_keep_background)

        local short_menu = folder_menu("Short")
        MosaicMenu._updateItemsBuildUI(short_menu)
        local short_overlay = short_menu.layout[1][1]._underline_container[1][1]
        local short_frame = short_overlay[2][1][1][1]
        assert.are.equal(label_frame[1].dimen.h, short_frame[1].dimen.h)
    end)

    it("supplies the rendered book cover before opening a Zen mosaic tile", function()
        require("modules/filebrowser/patches/zen_renderer")()
        local captured_cover
        local selected_entry
        rawset(_G, "__ZEN_UI_SET_OPENING_BANNER_COVER", function(cover)
            captured_cover = cover
        end)
        local cover = { dimen = { x = 20, y = 30, w = 80, h = 120 } }
        local entry = { path = "/book.epub" }
        local item = setmetatable({
            _zen_cover_frame = cover,
            _zen_is_book = true,
            entry = entry,
            menu = { onMenuSelect = function(_, selected) selected_entry = selected end },
        }, { __index = MosaicMenu._zen_mosaic_item_class })

        assert.is_true(item:onTapSelect())
        assert.are.equal(cover, captured_cover)
        assert.are.equal(entry, selected_entry)

        captured_cover = nil
        item._zen_is_book = false
        assert.is_true(item:onTapSelect())
        assert.is_nil(captured_cover)
    end)

    it("queues cover extraction for metadata-only and undersized cached covers", function()
        local mode = "metadata_only"
        local freed = 0
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function()
                if mode == "metadata_only" then
                    return { pages = 120, cover_fetched = false, has_cover = false }
                end
                return {
                    pages = 120,
                    cover_fetched = true,
                    has_cover = true,
                    cover_bb = { free = function() freed = freed + 1 end },
                }
            end,
            isCachedCoverInvalid = function() return mode == "undersized" end,
        })
        _G.__ZEN_UI_PLUGIN.config.browser_page_count = { show_page_count = true }
        ZenSpec.unload("modules/filebrowser/patches/zen_renderer")
        require("modules/filebrowser/patches/zen_renderer")()

        local function build()
            local menu = {
                item_table = { { title = "Book", is_file = true, path = "/book.epub" } },
                item_group = {}, layout = {}, items_to_update = {}, page = 1,
                perpage = 1, nb_cols = 2, item_margin = 1, item_width = 100,
                item_height = 150, item_dimen = { copy = function() return {} end },
                inner_dimen = { w = 110 }, _do_cover_images = true,
            }
            MosaicMenu._updateItemsBuildUI(menu)
            return menu
        end

        local metadata_menu = build()
        assert.are.equal(1, #metadata_menu.items_to_update)
        assert.is_false(metadata_menu.layout[1][1].bookinfo_found)
        assert.are.equal("120 p.", metadata_menu.layout[1][1]._zen_page_label)

        mode = "undersized"
        local undersized_menu = build()
        assert.are.equal(1, #undersized_menu.items_to_update)
        assert.is_false(undersized_menu.layout[1][1].bookinfo_found)
        assert.are.equal("120 p.", undersized_menu.layout[1][1]._zen_page_label)
        assert.are.equal(1, freed)
    end)

    it("dims selected mosaic book covers", function()
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function()
                return { cover_fetched = true, has_cover = false }
            end,
            isCachedCoverInvalid = function() return false end,
        })
        ZenSpec.unload("modules/filebrowser/patches/zen_renderer")
        require("modules/filebrowser/patches/zen_renderer")()
        local menu = {
            item_table = { { title = "Book", is_file = true, path = "/book.epub", dim = true } },
            item_group = {}, layout = {}, items_to_update = {}, page = 1,
            perpage = 1, nb_cols = 2, item_margin = 1, item_width = 100,
            item_height = 150, item_dimen = { copy = function() return {} end },
            inner_dimen = { w = 110 }, _do_cover_images = true,
        }

        MosaicMenu._updateItemsBuildUI(menu)

        assert.is_true(menu.layout[1][1]._zen_cover_frame.dim)
    end)

    it("paints status, page, and series badges at the configured scale", function()
        require("modules/filebrowser/patches/zen_renderer")()
        _G.__ZEN_UI_PLUGIN.config.browser_cover_badges = {
            show_mosaic_progress = true,
            show_native_progress_bar = true,
            show_favorite_badge = true,
            badge_size = "compact",
        }
        _G.__ZEN_UI_PLUGIN.config.browser_page_count = { show_page_count = true }
        _G.__ZEN_UI_PLUGIN.config.browser_series_badge = { show_series_badge = true }
        local item_class = MosaicMenu._zen_mosaic_item_class
        local item = setmetatable({
            _zen_cover_frame = { dimen = { x = 0, y = 0, w = 100, h = 150 }, bordersize = 1 },
            _zen_effective_status = "reading",
            percent_finished = 0.5,
            _zen_is_fav = true,
            _zen_page_label = "120 p.",
            _zen_series_label = "#2",
            _zen_is_book = true,
            filepath = "/book.epub",
        }, { __index = item_class })
        local compact = {}
        local rounded_progress
        local bb = {
            paintRectRGB32 = function(_self, x, y, width, height)
                compact[#compact + 1] = { x = x, y = y, width = width, height = height }
            end,
            paintRect = function() end,
            paintRoundedRect = function(_self, _x, _y, width, height, _color, radius)
                rounded_progress = { width = width, height = height, radius = radius }
            end,
        }

        item:paintTo(bb, 0, 0)

        assert.is_true(#compact > 0)
        assert.is_true(table.concat(painted_text, " "):find("50%%") ~= nil)
        assert.is_true(table.concat(painted_text, " "):find("120 p%.") ~= nil)
        assert.is_true(table.concat(painted_text, " "):find("#2") ~= nil)
        assert.is_true(table.concat(painted_text, " "):find("☆") ~= nil)
        assert.are.equal(1, native_progress_paints)
        assert.are.equal(4, native_progress.radius)
        assert.are.same({ width = 42, height = 4, radius = 2 }, rounded_progress)

        _G.__ZEN_UI_PLUGIN.config.browser_cover_badges.show_native_progress_bar = false
        item:paintTo(bb, 0, 0)
        assert.are.equal(1, native_progress_paints)

        _G.__ZEN_UI_PLUGIN.config.browser_cover_badges.show_native_progress_bar = true
        _G.__ZEN_UI_PLUGIN.config.browser_cover_badges.badge_size = "extra_large"
        local large = {}
        bb.paintRectRGB32 = function(_self, x, y, width, height)
            large[#large + 1] = { x = x, y = y, width = width, height = height }
        end
        item:paintTo(bb, 0, 0)

        local function widest(calls)
            local width = 0
            for _i, call in ipairs(calls) do width = math.max(width, call.width) end
            return width
        end
        assert.is_true(widest(large) > widest(compact))
    end)

    it("resolves metadata during update and performs no metadata reads during paint", function()
        local metadata_allowed = true
        local calls = {
            bookinfo = 0, sidecar_check = 0, sidecar_open = 0,
            sidecar_read = 0, booklist = 0, favorite = 0, stat = 0,
        }
        local function metadata_call(key)
            assert.is_true(metadata_allowed, key .. " metadata read during paint")
            calls[key] = calls[key] + 1
        end
        ZenSpec.replace("bookinfomanager", {
            getBookInfo = function()
                metadata_call("bookinfo")
                return { series_index = 4, cover_fetched = true, has_cover = false }
            end,
            isCachedCoverInvalid = function() return false end,
        })
        local doc_values = {
            summary = { status = "reading" },
            percent_finished = 0.25,
            zen_new_mtime = 200,
            pagemap_use_page_labels = false,
        }
        local doc = {
            readSetting = function(_self, key)
                metadata_call("sidecar_read")
                return doc_values[key]
            end,
        }
        ZenSpec.replace("docsettings", {
            hasSidecarFile = function()
                metadata_call("sidecar_check")
                return true
            end,
            open = function()
                metadata_call("sidecar_open")
                return doc
            end,
            findSidecarFile = function() return "/book.sdr/metadata.lua" end,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, attribute)
                metadata_call("stat")
                local values = path == "/book.epub"
                    and { mode = "file", modification = 200 }
                    or { mode = "file", modification = 150 }
                return attribute and values[attribute] or values
            end,
        })
        ZenSpec.replace("ui/widget/booklist", {
            getBookInfo = function()
                metadata_call("booklist")
                return { pages = 999 }
            end,
        })
        ZenSpec.replace("gettext", setmetatable({
            pgettext = function(_context, text) return text end,
        }, {
            __call = function(_self, text) return text end,
        }))
        ZenSpec.replace("readcollection", {
            isFileInCollections = function()
                metadata_call("favorite")
                return true
            end,
        })
        _G.__ZEN_UI_PLUGIN.config.browser_cover_badges = {
            show_mosaic_progress = true,
            show_favorite_badge = true,
        }
        _G.__ZEN_UI_PLUGIN.config.browser_page_count = { show_page_count = true }
        _G.__ZEN_UI_PLUGIN.config.browser_series_badge = { show_series_badge = true }
        ZenSpec.unload("common/book_status")
        ZenSpec.unload("common/utils")
        ZenSpec.unload("modules/filebrowser/patches/zen_renderer")
        require("modules/filebrowser/patches/zen_renderer")()
        local menu = {
            item_table = { { title = "Book", is_file = true, path = "/book.epub" } },
            item_group = {}, layout = {}, items_to_update = {}, page = 1,
            perpage = 1, nb_cols = 2, item_margin = 1, item_width = 100,
            item_height = 150, item_dimen = { copy = function() return {} end },
            inner_dimen = { w = 110 }, _do_cover_images = true,
        }
        MosaicMenu._updateItemsBuildUI(menu)
        local item = menu.layout[1][1]
        local before_paint = {}
        for key, value in pairs(calls) do before_paint[key] = value end
        metadata_allowed = false
        item._zen_cover_frame.dimen.x = 0
        item._zen_cover_frame.dimen.y = 0
        item:paintTo({
            paintRectRGB32 = function() end,
            paintRect = function() end,
        }, 0, 0)

        assert.are.same(before_paint, calls)
        assert.matches("999", item._zen_page_label)
        assert.are.equal("#4", item._zen_series_label)
        assert.are.equal(1, calls.sidecar_open)
        assert.are.equal(1, calls.booklist)
    end)

    it("honors finished dimming and the new-banner setting", function()
        require("modules/filebrowser/patches/zen_renderer")()
        _G.__ZEN_UI_PLUGIN.config.browser_cover_badges = { dim_finished_books = true }
        local item_class = MosaicMenu._zen_mosaic_item_class
        local item = setmetatable({
            _zen_cover_frame = { dimen = { x = 0, y = 0, w = 100, h = 150 }, bordersize = 1 },
            _zen_effective_status = "complete",
            _zen_is_book = true,
            width = 320,
            height = 400,
        }, { __index = item_class })
        local dimmed = 0
        local bb = {
            paintRectRGB32 = function() end,
            paintRect = function() end,
            lightenRect = function() dimmed = dimmed + 1 end,
        }

        item:paintTo(bb, 0, 0)
        assert.are.equal(1, dimmed)

        _G.__ZEN_UI_PLUGIN.config.browser_cover_badges = { show_new_banner = true }
        item._zen_effective_status = "new"
        item:paintTo(bb, 0, 0)
        assert.are.same({ "New" }, banner_labels)
        assert.are.same({ { span = 100, thick = 35 } }, banner_sizes)
    end)

    it("respects the hide-underline feature when focus returns", function()
        require("modules/filebrowser/patches/zen_renderer")()
        local item = setmetatable({ _underline_container = {} }, {
            __index = MosaicMenu._zen_mosaic_item_class,
        })

        item:onFocus()
        assert.are.equal(0, item._underline_container.color)

        _G.__ZEN_UI_PLUGIN.config.features.browser_hide_underline = true
        item:onFocus()
        assert.are.equal(1, item._underline_container.color)
    end)
end)

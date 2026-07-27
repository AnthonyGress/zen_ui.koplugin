describe("Zen mosaic renderer", function()
    local MosaicMenu
    local stock_created
    local cover_requests
    local painted_text
    local native_progress_paints
    local banner_labels
    local banner_sizes

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
        painted_text = {}
        native_progress_paints = 0
        banner_labels = {}
        banner_sizes = {}
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
        })
        ZenSpec.replace("device", {
            screen = {
                scaleBySize = function(_self, value) return value end,
            },
        })
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("ui/bidi", { mirroredUILayout = function() return false end })
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
        ZenSpec.replace("ui/widget/container/framecontainer", widget_class())
        ZenSpec.replace("ui/widget/horizontalgroup", widget_class())
        ZenSpec.replace("ui/widget/horizontalspan", widget_class())
        ZenSpec.replace("ui/widget/container/leftcontainer", widget_class())
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
        ZenSpec.replace("ui/widget/container/underlinecontainer", widget_class())
        ZenSpec.replace("ui/widget/verticalgroup", widget_class())
        ZenSpec.replace("ui/widget/verticalspan", widget_class())
        ZenSpec.replace("ui/size", { border = { thin = 1, default = 1 }, padding = { tiny = 1 }, line = { focus_indicator = 1 } })
        ZenSpec.replace("ui/widget/menu", { getMenuText = function(entry) return entry.title end })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_BLACK = 0, COLOR_WHITE = 1 })
        ZenSpec.replace("common/cover_render_cache", { render = function() return nil end })
        ZenSpec.replace("ui/widget/progresswidget", {
            new = function(_self, values)
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
            make_cover_widget = function(_book, width, height, options)
                cover_requests[#cover_requests + 1] = {
                    width = width,
                    height = height,
                    options = options,
                }
                return { dimen = { w = 66, h = 99 } }
            end,
        })
        ZenSpec.replace("ui/widget/filechooser", { _updateItemsBuildUI = stock_builder })
        _G.G_reader_settings = {
            readSetting = function() return "2:3" end,
        }
        _G.__ZEN_UI_PLUGIN = {
            config = { features = { browser_cover_mosaic_uniform = true } },
        }
        ZenSpec.unload("modules/filebrowser/patches/zen_mosaic_renderer")
    end)

    it("uses Zen tiles for books and retains stock tiles for folders", function()
        require("modules/filebrowser/patches/zen_mosaic_renderer")()
        local menu = {
            item_table = {
                { title = "Book", is_file = true, path = "/book.epub" },
                { title = "Folder/", path = "/folder" },
            },
            item_group = {}, layout = {}, items_to_update = {}, page = 1,
            perpage = 2, nb_cols = 2, item_margin = 1, item_width = 100,
            item_height = 150, item_dimen = { copy = function() return {} end },
            inner_dimen = { w = 220 }, _do_cover_images = true,
        }

        MosaicMenu._updateItemsBuildUI(menu)

        assert.is_not_nil(MosaicMenu._zen_mosaic_item_class)
        assert.are.equal(1, stock_created)
        assert.are.equal(1, #menu.items_to_update)
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

    it("paints status, page, and series badges at the configured scale", function()
        require("modules/filebrowser/patches/zen_mosaic_renderer")()
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
            filepath = "/book.epub",
        }, { __index = item_class })
        local compact = {}
        local bb = {
            paintRectRGB32 = function(_self, x, y, width, height)
                compact[#compact + 1] = { x = x, y = y, width = width, height = height }
            end,
            paintRect = function() end,
        }

        item:paintTo(bb, 0, 0)

        assert.is_true(#compact > 0)
        assert.is_true(table.concat(painted_text, " "):find("50%%") ~= nil)
        assert.is_true(table.concat(painted_text, " "):find("120 p%.") ~= nil)
        assert.is_true(table.concat(painted_text, " "):find("#2") ~= nil)
        assert.is_true(table.concat(painted_text, " "):find("☆") ~= nil)
        assert.are.equal(1, native_progress_paints)

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
                return { pages = 321, series_index = 4, has_cover = false }
            end,
        })
        local doc_values = {
            summary = { status = "reading" },
            percent_finished = 0.25,
            zen_new_mtime = 200,
            pagemap_use_page_labels = true,
            pagemap_doc_pages = 321,
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
        ZenSpec.unload("modules/filebrowser/patches/zen_mosaic_renderer")
        require("modules/filebrowser/patches/zen_mosaic_renderer")()
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
        assert.matches("321", item._zen_page_label)
        assert.are.equal("#4", item._zen_series_label)
        assert.are.equal(1, calls.sidecar_open)
        assert.are.equal(0, calls.booklist)
    end)

    it("honors finished dimming and the new-banner setting", function()
        require("modules/filebrowser/patches/zen_mosaic_renderer")()
        _G.__ZEN_UI_PLUGIN.config.browser_cover_badges = { dim_finished_books = true }
        local item_class = MosaicMenu._zen_mosaic_item_class
        local item = setmetatable({
            _zen_cover_frame = { dimen = { x = 0, y = 0, w = 100, h = 150 }, bordersize = 1 },
            _zen_effective_status = "complete",
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
        require("modules/filebrowser/patches/zen_mosaic_renderer")()
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

describe("app launcher book details page", function()
    local originals

    local function replace(name, module)
        if originals[name] == nil then
            originals[name] = package.loaded[name] == nil and false or package.loaded[name]
        end
        package.loaded[name] = module
    end

    local function widget_class(kind, created)
        local class = {}
        class.__index = class

        function class:extend(values)
            values = values or {}
            values.__index = values
            return setmetatable(values, { __index = self })
        end

        function class:new(values)
            values = values or {}
            values.kind = kind
            values.getSize = values.getSize or function(widget)
                if widget.width or widget.height then
                    return { w = widget.width or 1, h = widget.height or 1 }
                end
                if widget.text then return { w = #widget.text * 6, h = 20 } end
                local width, height = 0, 0
                for _i, child in ipairs(widget) do
                    local size = child:getSize()
                    if kind == "ui/widget/verticalgroup" then
                        width = math.max(width, size.w)
                        height = height + size.h
                    else
                        width = width + size.w
                        height = math.max(height, size.h)
                    end
                end
                return { w = width, h = height }
            end
            values.paintTo = values.paintTo or function() end
            values.free = values.free or function() end
            values.dimen = values.dimen or {
                x = 0, y = 0,
                w = values.width or values:getSize().w,
                h = values.height or values:getSize().h,
            }
            setmetatable(values, { __index = self })
            if created then created[#created + 1] = values end
            if values.init then values:init() end
            return values
        end

        return class
    end

    before_each(function()
        originals = {}
        ZenSpec.unload("modules/menu/app_launcher/book_details_page")
        ZenSpec.unload("modules/menu/app_launcher/page_plan")
    end)

    after_each(function()
        ZenSpec.unload("modules/menu/app_launcher/book_details_page")
        ZenSpec.unload("modules/menu/app_launcher/page_plan")
        for name, original in pairs(originals) do
            package.loaded[name] = original == false and nil or original
        end
    end)

    it("is reader-only without exposing a reader-only option", function()
        local Page = require("modules/menu/app_launcher/book_details_page")
        local cfg = { show_book_details = true }
        assert.is_true(Page.isEnabled(cfg, false))
        assert.is_false(Page.isEnabled(cfg, true))
        assert.is_false(Page.isEnabled({}, false))
        assert.are.same({ uniform = true }, Page.rendererOptions({
            features = { browser_cover_mosaic_uniform = true },
        }))
    end)

    it("orders both optional launcher pages deterministically", function()
        local Plan = require("modules/menu/app_launcher/page_plan")
        local cfg = {
            show_book_switcher = true,
            show_book_details = true,
            book_switcher_first = true,
            book_details_first = true,
        }
        local plan = Plan.build(2, cfg, false)
        assert.are.same({ "book_details", "buttons", "buttons", "book_switcher" }, {
            plan[1].kind, plan[2].kind, plan[3].kind, plan[4].kind,
        })
        assert.are.equal(1, plan[2].index)
        assert.are.equal(2, plan[3].index)

        cfg.show_book_details = false
        plan = Plan.build(2, cfg, false)
        assert.are.same({ "book_switcher", "buttons", "buttons" }, {
            plan[1].kind, plan[2].kind, plan[3].kind,
        })
        cfg.show_book_details = true

        local library_plan = Plan.build(2, cfg, true)
        assert.are.same({ "book_switcher", "buttons", "buttons" }, {
            library_plan[1].kind, library_plan[2].kind, library_plan[3].kind,
        })
    end)

    it("shows cover, metadata, current page, and progress as one tappable card", function()
        local created = {}
        local progress_spec
        local cover_options
        local cover_width
        local cover_height
        local opened = 0
        local InputContainer = widget_class("input", created)
        for _i, name in ipairs({
            "ui/widget/container/centercontainer",
            "ui/widget/horizontalgroup",
            "ui/widget/horizontalspan",
            "ui/widget/textboxwidget",
            "ui/widget/textwidget",
            "ui/widget/verticalgroup",
            "ui/widget/verticalspan",
        }) do
            replace(name, widget_class(name, created))
        end
        replace("ui/widget/container/inputcontainer", InputContainer)
        replace("ui/geometry", { new = function(_, values) return values end })
        replace("ui/gesturerange", widget_class("gesture"))
        replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_LIGHT_GRAY = "lightgray",
        })
        replace("device", {
            screen = {
                getWidth = function() return 600 end,
                getHeight = function() return 800 end,
                scaleBySize = function(_, value) return value end,
            },
        })
        replace("ui/font", { getFace = function() return {} end })
        replace("ui/uimanager", { setDirty = function() end })
        replace("gettext", function(text) return text end)
        replace("common/ui/book_progress", {
            build = function(spec)
                progress_spec = spec
                return widget_class("progress", created):new{ width = spec.width, height = 20 }
            end,
        })
        replace("modules/reader/book_details", { getSummary = function() end })
        replace("modules/filebrowser/patches/library_font", {
            getFace = function(size) return { size = size } end,
            scaleValue = function(size) return size end,
        })
        replace("modules/filebrowser/patches/home/widgets/cover_common", {
            BORDER_SIZE = 2,
            make_cover_widget = function(_book, width, height, options)
                cover_options = options
                cover_width = width
                cover_height = height
                return widget_class("cover", created):new{
                    width = width, height = height,
                }, width, height
            end,
        })

        local config = {
            features = { browser_cover_mosaic_uniform = false },
            mosaic_title_strip = { show_title = true, show_author = true },
        }
        local Page = require("modules/menu/app_launcher/book_details_page")
        local panel, refs = Page.build{
            width = 600,
            height = 500,
            config = config,
            book = {
                path = "/books/current.epub",
                title = "Current title",
                authors = "Current author",
                series = "Current series #2",
                genres = "Fantasy, Adventure",
                progress = 0.425,
                pages = 300,
                page_text = "Page 128 of 300",
                cover_bb = {},
            },
            open_details = function() opened = opened + 1 end,
        }

        assert.is_table(panel)
        assert.are.equal(1, #refs.buttons)
        assert.are.equal(1, #refs.layout_rows)
        assert.is_false(cover_options.uniform)
        local switcher_layout = require(
            "modules/menu/app_launcher/book_switcher_page").layout{
                width = 600, height = 500, config = config,
            }
        assert.are.equal(switcher_layout.cover_max_w, cover_width)
        assert.are.equal(switcher_layout.cover_max_h, cover_height)
        assert.are.equal(switcher_layout.cell_h, refs.buttons[1].widget.height)
        assert.are.equal(0.425, progress_spec.ratio)
        assert.are.equal(300, progress_spec.pages)
        assert.are.equal("", progress_spec.right_text)
        local texts = {}
        local text_sizes = {}
        for _i, widget in ipairs(created) do
            if widget.text then
                texts[widget.text] = true
                text_sizes[widget.text] = widget.face and widget.face.size
            end
        end
        assert.is_true(texts["Current title"])
        assert.is_true(texts["Current author"])
        assert.is_true(texts["Current series #2"])
        assert.is_true(texts["Fantasy, Adventure"])
        assert.is_true(texts["Page 128 of 300"])
        assert.are.equal(22, text_sizes["Current title"])
        assert.are.equal(19, text_sizes["Current author"])
        assert.are.equal(19, text_sizes["Current series #2"])
        assert.are.equal(19, text_sizes["Fantasy, Adventure"])
        assert.are.equal(19, text_sizes["Page 128 of 300"])
        assert.are.equal(19, progress_spec.face.size)
        refs.buttons[1].callback()
        assert.are.equal(1, opened)
    end)
end)

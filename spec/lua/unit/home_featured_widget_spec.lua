describe("home featured widget", function()
    local created
    local cover_calls

    local function widget_class(kind)
        return {
            new = function(_, values)
                values = values or {}
                values.kind = kind
                local width = values.width
                local height = values.height
                if not width or not height then
                    local child_w, child_h = 0, 0
                    for _i, child in ipairs(values) do
                        local size = child.getSize and child:getSize() or child.dimen or {}
                        child_w = child_w + (size.w or 0)
                        child_h = math.max(child_h, size.h or 0)
                    end
                    width = width or (values.text and #values.text * 6) or child_w
                    height = height or child_h
                end
                values.dimen = values.dimen or { x = 0, y = 0, w = width or 1, h = height or 12 }
                values.getSize = values.getSize or function(self) return self.dimen end
                values.free = values.free or function(self) self.freed = true end
                created[#created + 1] = values
                return values
            end,
        }
    end

    before_each(function()
        created = {}
        cover_calls = {}
        ZenSpec.replace("common/ui/background", { tile_bg = function(color) return color end })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black", COLOR_GRAY_5 = "gray5",
            COLOR_LIGHT_GRAY = "lightgray", COLOR_WHITE = "white",
        })
        ZenSpec.replace("ui/geometry", {
            new = function(_, values)
                function values:contains(pos)
                    return pos.x >= (self.x or 0) and pos.x < (self.x or 0) + self.w
                        and pos.y >= (self.y or 0) and pos.y < (self.y or 0) + self.h
                end
                return values
            end,
        })
        for _i, name in ipairs({
            "ui/widget/horizontalgroup", "ui/widget/horizontalspan",
            "ui/widget/textboxwidget", "ui/widget/textwidget",
            "ui/widget/verticalgroup", "ui/widget/verticalspan",
            "ui/widget/container/centercontainer", "ui/widget/container/framecontainer",
            "ui/widget/container/inputcontainer", "ui/widget/container/topcontainer",
        }) do
            ZenSpec.replace(name, widget_class(name))
        end
        ZenSpec.replace("ui/gesturerange", widget_class("gesture"))
        ZenSpec.replace("device", {
            screen = {
                scaleBySize = function(_, value) return value end,
                getWidth = function() return 800 end,
                getHeight = function() return 600 end,
            },
            isTouchDevice = function() return false end,
        })
        ZenSpec.replace("ui/font", {
            getFace = function(_, name, size) return { name = name, size = size or 12 } end,
        })
        ZenSpec.replace("util", { htmlToPlainTextIfHtml = function(text) return text:gsub("<.->", "") end })
        ZenSpec.replace("common/utils", { formatPageCount = function(pages) return pages .. " pages" end })
        ZenSpec.replace("modules/filebrowser/patches/library_font", {
            getFontName = function() return "default" end,
            getScale = function() return 1 end,
            scaleValue = function(value) return value end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/widgets/cover_common", {
            make_cover_widget = function(book, max_w, max_h, opts)
                cover_calls[#cover_calls + 1] = { book = book, max_w = max_w, max_h = max_h, opts = opts }
                local cover = widget_class("cover"):new{ width = 90, height = 135 }
                return cover, 90, 135
            end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.unload("common/widget_resources")
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/featured_common")
    end)

    local function has_text(expected)
        for _i, widget in ipairs(created) do
            if widget.text == expected then return true end
        end
        return false
    end

    it("renders the recent book cover, title, author, and description", function()
        local opened
        local actions
        local book = {
            path = "/library/alpha.epub",
            title = "Alpha",
            authors = "Zen Author",
            description = "<p>A deterministic description.</p>",
            status = "reading",
            percent = 0.25,
            pages = 120,
        }
        local Featured = require("modules/filebrowser/patches/home/widgets/featured_common")
        local widget = Featured.build({
            width = 600,
            height = 220,
            face_label = { size = 12 },
            module_cfg = { show_description = true, progress_meta = { left = "percent", right = "total_pages" } },
            data = { getFeaturedBook = function(_, source) assert.are.equal("recently_read", source); return book end },
            setWidgetActions = function(value) actions = value end,
            openBook = function(path) opened = path end,
        }, "recently_read")

        assert.is_table(widget)
        assert.are.equal(1, #cover_calls)
        assert.are.equal(book, cover_calls[1].book)
        assert.is_true(has_text("Alpha"))
        assert.is_true(has_text("Zen Author"))
        assert.is_true(has_text("A deterministic description."))
        assert.is_true(has_text("25%"))
        assert.is_true(has_text("120 pages"))
        assert.is_true(actions.activate())
        assert.are.equal(book.path, opened)
    end)

    it("renders an explicit empty-history state without constructing a cover", function()
        local Featured = require("modules/filebrowser/patches/home/widgets/featured_common")
        local widget = Featured.build({
            width = 500,
            height = 180,
            face_label = { size = 12 },
            module_cfg = {},
            data = { getFeaturedBook = function() return nil end },
        }, "recently_read")

        assert.is_table(widget)
        assert.are.equal(0, #cover_calls)
        assert.is_true(has_text("No books found"))
    end)
end)

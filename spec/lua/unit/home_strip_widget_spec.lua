describe("home recent strip widget", function()
    local created
    local cover_books
    local empty_sources
    local library_font_sizes
    local touch_device
    local scheduled

    local function widget_class(kind)
        return {
            new = function(_, values)
                values = values or {}
                values.kind = kind
                local width = values.width
                local height = values.height
                if not width or not height then
                    local total_w, max_h = 0, 0
                    for _i, child in ipairs(values) do
                        local size = child.getSize and child:getSize() or child.dimen or {}
                        total_w = total_w + (size.w or 0)
                        max_h = math.max(max_h, size.h or 0)
                    end
                    width = width or (values.text and #values.text * 6) or total_w
                    height = height or max_h
                end
                values.dimen = values.dimen or { x = 0, y = 0, w = width or 1, h = height or 12 }
                values.getSize = values.getSize or function(self) return self.dimen end
                values.paintTo = values.paintTo or function() end
                values.free = values.free or function(self)
                    self.free_calls = (self.free_calls or 0) + 1
                end
                created[#created + 1] = values
                return values
            end,
        }
    end

    before_each(function()
        created, cover_books, empty_sources, library_font_sizes, scheduled = {}, {}, {}, {}, {}
        touch_device = false
        rawset(_G, "__ZEN_UI_SET_OPENING_BANNER_COVER", nil)
        ZenSpec.replace("common/ui/background", { tile_bg = function(color) return color end })
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black", COLOR_WHITE = "white", COLOR_LIGHT_GRAY = "lightgray",
        })
        ZenSpec.replace("common/ui/corner_banner", { paint = function() end })
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
            "ui/widget/container/framecontainer", "ui/widget/container/centercontainer",
            "ui/widget/container/leftcontainer", "ui/widget/container/topcontainer",
            "ui/widget/textwidget", "ui/widget/textboxwidget",
            "ui/widget/container/inputcontainer", "ui/widget/verticalgroup",
            "ui/widget/verticalspan",
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
            isTouchDevice = function() return touch_device end,
        })
        ZenSpec.replace("ui/font", { getFace = function(_, name, size) return { name = name, size = size } end })
        ZenSpec.replace("common/utils", {
            getBadgeColor = function() return "badge" end,
            getBadgeTextColor = function() return "text" end,
            isBadgeDark = function() return false end,
            getBadgeScale = function() return 1 end,
            getBadgeInset = function() return 1 end,
            formatPageCount = function(pages) return tostring(pages) end,
        })
        ZenSpec.replace("modules/filebrowser/patches/library_font", {
            getFace = function(size)
                library_font_sizes[#library_font_sizes + 1] = size
                return { name = "LibraryFont", size = size }
            end,
            scaleValue = function() error("home strip used library font size") end,
        })
        ZenSpec.replace("modules/filebrowser/patches/home/widgets/cover_common", {
            make_cover_widget = function(book, _max_w, max_h)
                cover_books[#cover_books + 1] = book
                local cover = widget_class("cover"):new{ width = 80, height = max_h }
                return cover, 80, max_h
            end,
            make_empty_placeholder_cover = function(_max_w, max_h)
                empty_sources[#empty_sources + 1] = true
                local cover = widget_class("cover"):new{ width = 80, height = max_h }
                return cover, 80, max_h
            end,
            get_empty_message = function(source)
                if source == "recently_read" then return "No recently read books found" end
                return "No books found"
            end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function(_, _delay, callback)
                scheduled[#scheduled + 1] = callback
            end,
            unschedule = function(_, callback)
                for i = #scheduled, 1, -1 do
                    if scheduled[i] == callback then table.remove(scheduled, i) end
                end
            end,
            setDirty = function() end,
        })
        ZenSpec.unload("common/widget_resources")
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/strip_common")
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/strip_recent")
    end)

    local function has_text(expected)
        for _i, widget in ipairs(created) do
            if widget.text == expected then return true end
        end
        return false
    end

    local function run_scheduled()
        local callback = table.remove(scheduled, 1)
        if callback then callback() end
    end

    it("loads recent books, renders strip titles, and exposes open actions", function()
        local book = { path = "/library/alpha.epub", title = "Alpha", authors = "Zen Author" }
        local requested
        local focus_target
        local opened
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            face_label = { size = 12 },
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true, show_strip_titles = true },
            data = {
                getBooksForStrip = function(_, source, count, order, component_id)
                    requested = { source, count, order, component_id }
                    return { book }
                end,
            },
            registerHomeFocusTarget = function(target, child)
                focus_target = target
                return child
            end,
            openBook = function(path) opened = path end,
        })

        assert.is_table(widget)
        assert.are.same({ "recently_read", 4, "default", "strip_recent" }, requested)
        assert.are.same({ book }, cover_books)
        assert.is_true(has_text("Alpha"))
        assert.are.same({ 16 }, library_font_sizes)
        assert.are.equal("book:/library/alpha.epub", focus_target.key)
        assert.is_true(focus_target.activate())
        assert.are.equal(book.path, opened)
    end)

    it("renders an empty recent-history state", function()
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 500,
            height = 140,
            face_label = { size = 12 },
            component_id = "strip_recent",
            module_cfg = {},
            data = { getBooksForStrip = function() return {} end },
        })

        assert.is_table(widget)
        assert.are.equal(0, #cover_books)
        assert.are.same({ true }, empty_sources)
        assert.is_true(has_text("No recently read books found"))
    end)

    it("supplies the selected strip cover before opening its book", function()
        local captured_cover
        rawset(_G, "__ZEN_UI_SET_OPENING_BANNER_COVER", function(cover)
            captured_cover = cover
        end)
        local book = { path = "/library/alpha.epub", title = "Alpha" }
        local focus_target
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        Strip.build({
            width = 600,
            height = 160,
            face_label = { size = 12 },
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true },
            data = { getBooksForStrip = function() return { book } end },
            registerHomeFocusTarget = function(target, child)
                focus_target = target
                return child
            end,
            openBook = function() end,
        })

        assert.is_true(focus_target.activate())
        assert.is_not_nil(captured_cover)
    end)

    it("replaces only the swiped strip with its next books", function()
        touch_device = true
        local first = { path = "/library/first.epub", title = "First" }
        local second = { path = "/library/second.epub", title = "Second" }
        local show_second = false
        local shifted = {}
        local refreshed = 0
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true },
            data = {
                getBooksForStrip = function()
                    return { show_second and second or first }
                end,
            },
            shiftStrip = function(source, count, order, direction, component_id, two_rows, refresh)
                shifted = { source, count, order, direction, component_id, two_rows }
                show_second = true
                refresh()
                return true
            end,
            refreshStrip = function() refreshed = refreshed + 1 end,
        })

        assert.is_true(widget:onSwipeStrip(nil, { pos = { x = 10, y = 10 }, direction = "west" }))
        assert.are.same({ "recently_read", 4, "default", "next", "strip_recent", false }, shifted)
        assert.are.same({ first, second }, cover_books)
        assert.are.equal(1, refreshed)
    end)

    it("uses the idle-built adjacent frame without synchronous book or cover work", function()
        touch_device = true
        local pages = {
            [-1] = { { path = "/library/previous.epub", title = "Previous" } },
            [0] = { { path = "/library/current.epub", title = "Current" } },
            [1] = { { path = "/library/next.epub", title = "Next" } },
        }
        local current_page = 0
        local page_requests = 0
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true },
            data = {
                getBooksForStripPage = function(_, _source, _count, _order, _component_id, delta)
                    page_requests = page_requests + 1
                    return pages[current_page + delta], true
                end,
            },
            shiftStrip = function(_source, _count, _order, direction, _component_id, _two_rows, refresh)
                current_page = current_page + (direction == "next" and 1 or -1)
                refresh()
                return true
            end,
            refreshStrip = function() end,
        })

        widget:paintTo({}, 0, 0)
        run_scheduled()
        run_scheduled()
        assert.are.equal(3, page_requests)
        assert.are.equal(3, #cover_books)

        assert.is_true(widget:onSwipeStrip(nil, {
            pos = { x = 10, y = 10 }, direction = "west",
        }))
        assert.are.equal(3, page_requests)
        assert.are.equal(3, #cover_books)

        widget:free()
        while #scheduled > 0 do run_scheduled() end
        assert.are.equal(3, page_requests)
        assert.are.equal(3, #cover_books)
    end)
end)

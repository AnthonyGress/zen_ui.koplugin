describe("home recent strip widget", function()
    local created
    local cover_books
    local empty_sources
    local library_font_sizes
    local touch_device
    local scheduled
    local scheduled_delays

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
        scheduled_delays = {}
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
                return cover, 80, max_h, book.is_cover_pending == true
            end,
            make_empty_placeholder_cover = function(_max_w, max_h)
                empty_sources[#empty_sources + 1] = true
                local cover = widget_class("cover"):new{ width = 80, height = max_h }
                return cover, 80, max_h
            end,
            get_empty_message = function(source)
                if source == "recently_read" then return "Start reading a book to fill this space." end
                return "No books found"
            end,
        })
        ZenSpec.replace("common/memory_policy", {
            getProfile = function() return { pressure = "normal" } end,
            canPreload = function() return true end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function(_, delay, callback)
                scheduled[#scheduled + 1] = callback
                scheduled_delays[#scheduled_delays + 1] = delay
            end,
            unschedule = function(_, callback)
                for i = #scheduled, 1, -1 do
                    if scheduled[i] == callback then
                        table.remove(scheduled, i)
                        table.remove(scheduled_delays, i)
                    end
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
        table.remove(scheduled_delays, 1)
        if callback then callback() end
    end

    it("loads recent books, renders strip titles, and exposes open actions", function()
        local book = { path = "/library/alpha.epub", title = "Alpha", authors = "Zen Author" }
        local requested
        local focus_target
        local opened
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        assert.are.same({ units = 3.5 }, Strip.size)
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
        assert.are.equal("ui/widget/container/centercontainer", widget[1][1].kind)
        assert.are.equal("ui/widget/container/centercontainer", widget[1][1][1].kind)
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
        assert.is_true(has_text("Start reading a book to fill this space."))
    end)

    it("exposes vertical slack for Home gap balancing", function()
        local books = {
            { path = "/library/a.epub" },
            { path = "/library/b.epub" },
            { path = "/library/c.epub" },
            { path = "/library/d.epub" },
        }
        local content_bounds
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        Strip.build({
            width = 600,
            height = 400,
            component_id = "strip_recent",
            module_cfg = { count = 4 },
            data = { getBooksForStrip = function() return books end },
            setContentBounds = function(bounds) content_bounds = bounds end,
        })

        assert.is_true(content_bounds.min_shift < 0)
        assert.is_true(content_bounds.max_shift > content_bounds.min_shift)
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

    it("hydrates cold visible covers after paint with a strip-only refresh", function()
        local book = {
            path = "/library/cold.epub",
            title = "Cold",
            is_cover_pending = true,
        }
        local warmed
        local refreshed = 0
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true },
            data = {
                getBooksForStripPage = function()
                    return { book }, false
                end,
                warmStripCover = function(_self, requested, width, height)
                    warmed = { book = requested, width = width, height = height }
                    requested.is_cover_pending = false
                    return "warmed"
                end,
            },
            refreshStrip = function() refreshed = refreshed + 1 end,
        })

        assert.are.equal(1, #cover_books)
        widget:paintTo({}, 0, 0)
        assert.are.same({ 0.05 }, scheduled_delays)
        run_scheduled()

        assert.are.same({ book = book, width = 80, height = 136 }, warmed)
        assert.are.equal(2, #cover_books)
        assert.are.equal(1, refreshed)
        assert.are.equal(0, #scheduled)
    end)

    it("prewarms only the next-direction frame without swipe-time work", function()
        touch_device = true
        local pages = {
            [-1] = { { path = "/library/previous.epub", title = "Previous" } },
            [0] = { { path = "/library/current.epub", title = "Current" } },
            [1] = { { path = "/library/next.epub", title = "Next" } },
        }
        local current_page = 0
        local page_requests = 0
        local requested_deltas = {}
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true },
            data = {
                getBooksForStripPage = function(_, _source, _count, _order, _component_id, delta)
                    page_requests = page_requests + 1
                    requested_deltas[#requested_deltas + 1] = delta
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
        assert.are.same({ 0.35 }, scheduled_delays)
        run_scheduled()
        assert.are.equal(2, page_requests)
        assert.are.equal(2, #cover_books)

        assert.is_true(widget:onSwipeStrip(nil, {
            pos = { x = 10, y = 10 }, direction = "west",
        }))
        assert.are.equal(2, page_requests)
        assert.are.equal(2, #cover_books)

        assert.is_true(widget:onSwipeStrip(nil, {
            pos = { x = 10, y = 10 }, direction = "east",
        }))
        assert.are.equal(2, page_requests)
        assert.are.equal(2, #cover_books)

        run_scheduled()
        assert.are.same({ 0, 1, -1 }, requested_deltas)

        widget:free()
        while #scheduled > 0 do run_scheduled() end
        assert.are.equal(3, page_requests)
        assert.are.equal(3, #cover_books)
    end)

    it("bounds directional cover prewarming to four jobs per callback", function()
        touch_device = true
        local current = { { path = "/library/current.epub", title = "Current" } }
        local next_page = {}
        for i = 1, 5 do
            next_page[i] = {
                path = "/library/next-" .. i .. ".epub",
                title = "Next " .. i,
                is_cover_pending = true,
            }
        end
        local warmed = 0
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip_recent",
            module_cfg = { count = 5, interactive = true },
            data = {
                getBooksForStripPage = function(_, _source, _count, _order, _component, delta)
                    return delta == 0 and current or next_page, true
                end,
                warmStripCover = function(_self, book)
                    warmed = warmed + 1
                    book.is_cover_pending = false
                    return "warmed"
                end,
                isStripCoverWorkBusy = function() return false end,
            },
        })

        widget:paintTo({}, 0, 0)
        run_scheduled()
        assert.are.equal(4, warmed)
        assert.are.same({ 0.05 }, scheduled_delays)

        run_scheduled()
        assert.are.equal(5, warmed)
        assert.are.equal(0, #scheduled)
    end)

    it("skips directional prewarming while cover extraction is active", function()
        touch_device = true
        local page_requests = 0
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true },
            data = {
                getBooksForStripPage = function()
                    page_requests = page_requests + 1
                    return { { path = "/library/current.epub", title = "Current" } }, true
                end,
                isStripCoverWorkBusy = function() return true end,
            },
        })

        widget:paintTo({}, 0, 0)
        run_scheduled()
        assert.are.equal(1, page_requests)
        assert.are.equal(0, #scheduled)
    end)

    it("skips directional prewarming under memory pressure", function()
        touch_device = true
        local page_requests = 0
        require("common/memory_policy").canPreload = function() return false end
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true },
            data = {
                getBooksForStripPage = function()
                    page_requests = page_requests + 1
                    return { { path = "/library/current.epub", title = "Current" } }, true
                end,
            },
        })

        widget:paintTo({}, 0, 0)
        run_scheduled()
        assert.are.equal(1, page_requests)
        assert.are.equal(0, #scheduled)
    end)

    it("does not poll prewarming while visible extraction is pending", function()
        touch_device = true
        local warm_requests = 0
        local book = {
            path = "/library/pending.epub",
            title = "Pending",
            is_cover_pending = true,
        }
        local Strip = require("modules/filebrowser/patches/home/widgets/strip_recent")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip_recent",
            module_cfg = { count = 4, interactive = true },
            data = {
                getBooksForStripPage = function()
                    return { book }, true
                end,
                warmStripCover = function()
                    warm_requests = warm_requests + 1
                    return "pending"
                end,
                isStripCoverWorkBusy = function() return true end,
            },
        })

        widget:paintTo({}, 0, 0)
        run_scheduled()
        assert.are.equal(1, warm_requests)
        assert.are.same({ 0.35, 0.4 }, scheduled_delays)

        run_scheduled()
        assert.are.same({ 0.4 }, scheduled_delays)
        widget:free()
        assert.are.equal(0, #scheduled)
    end)
end)

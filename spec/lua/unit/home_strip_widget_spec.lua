describe("home strip widget", function()
    local created
    local cover_books
    local empty_sources
    local folder_calls
    local folder_needs_hydration
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
        created, cover_books, empty_sources, folder_calls = {}, {}, {}, {}
        folder_calls.builds = {}
        folder_needs_hydration = false
        library_font_sizes, scheduled = {}, {}
        scheduled_delays = {}
        touch_device = false
        rawset(_G, "__ZEN_UI_NAVBAR_OPEN_TAB", nil)
        rawset(_G, "__ZEN_UI_PLUGIN", nil)
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
            "ui/widget/overlapgroup",
            "ui/widget/textwidget", "ui/widget/textboxwidget",
            "ui/widget/linewidget",
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
            deepcopy = function(value)
                if type(value) ~= "table" then return value end
                local out = {}
                for key, item in pairs(value) do out[key] = item end
                return out
            end,
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
            BORDER_SIZE = 2,
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
        ZenSpec.replace("common/cover_utils", {
            getFolderPreviewBounds = function(_mode, width, height)
                return width, height
            end,
        })
        ZenSpec.replace("modules/filebrowser/folder_cover", {
            build = function(menu, entry, title, width, height, options)
                local build = {
                    menu = menu,
                    entry = entry,
                    title = title,
                    width = width,
                    height = height,
                    options = options,
                }
                folder_calls.build = build
                folder_calls.builds[#folder_calls.builds + 1] = build
                local pending = folder_needs_hydration and options.cached_only == true
                if options.cached_only == false then folder_needs_hydration = false end
                local entries = {}
                for _i, path in ipairs(entry._zen_files or {}) do
                    entries[#entries + 1] = { is_file = true, path = path }
                end
                return {
                    frame = widget_class("folder-cover"):new{
                        width = width,
                        height = height,
                    },
                    title = title,
                    count = #entry._zen_files,
                    cover_count = pending and 0 or 1,
                    entries = entries,
                    mode = "normal",
                    needs_hydration = pending,
                }
            end,
            overlayName = function(cover, options)
                folder_calls.overlay = { cover = cover, options = options }
                return widget_class("folder-overlay"):new{
                    width = options.width,
                    height = options.height,
                    cover,
                }
            end,
            decorateWidget = function(widget, frame, count, config)
                folder_calls.decorate = {
                    widget = widget,
                    frame = frame,
                    count = count,
                    config = config,
                }
                return widget
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
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/strip_controls")
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/strip_common")
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/strip")
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
        local context_args
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        assert.are.same({ units = 2.5 }, Strip.size)
        local widget = Strip.build({
            width = 600,
            height = 160,
            face_label = { size = 12 },
            component_id = "strip",
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
            showBookMenu = function(path, source)
                context_args = { path, source }
                return true
            end,
        })

        assert.is_table(widget)
        assert.are.equal("ui/widget/container/centercontainer", widget[1][1].kind)
        assert.are.equal("ui/widget/container/centercontainer", widget[1][1][1].kind)
        assert.are.same({ "recently_read", 4, "default", "strip" }, requested)
        assert.are.same({ book }, cover_books)
        assert.is_true(has_text("Alpha"))
        assert.are.same({ 16 }, library_font_sizes)
        assert.are.equal("book:/library/alpha.epub", focus_target.key)
        assert.is_true(focus_target.activate())
        assert.are.equal(book.path, opened)
        assert.is_true(focus_target.context())
        assert.are.same({ book.path, "recently_read" }, context_args)
    end)

    it("adds a small vertical gap between two book rows", function()
        local books = {}
        for i = 1, 8 do
            books[i] = { path = "/library/" .. tostring(i) .. ".epub" }
        end
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 600,
            component_id = "strip",
            module_cfg = {
                count = 8,
                interactive = false,
                show_strip_titles = false,
                two_rows = true,
            },
            data = { getBooksForStrip = function() return books end },
        })

        local row_gaps = 0
        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/verticalspan" and widget.width == 7 then
                row_gaps = row_gaps + 1
            end
        end
        assert.are.equal(1, row_gaps)
    end)

    it("keeps books slightly closer together horizontally", function()
        local books = {}
        for i = 1, 4 do
            books[i] = { path = "/library/" .. tostring(i) .. ".epub" }
        end
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            component_id = "strip",
            module_cfg = { count = 4, interactive = false },
            data = { getBooksForStrip = function() return books end },
        })

        local book_gaps = {}
        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/horizontalspan" then
                book_gaps[#book_gaps + 1] = widget.width
            end
        end
        assert.are.same({ 82, 82, 82 }, book_gaps)
    end)

    it("renders an empty recent-history state", function()
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 500,
            height = 140,
            face_label = { size = 12 },
            component_id = "strip",
            module_cfg = {},
            data = { getBooksForStrip = function() return {} end },
        })

        assert.is_table(widget)
        assert.are.equal(0, #cover_books)
        assert.are.same({ true }, empty_sources)
        assert.is_true(has_text("Start reading a book to fill this space."))
    end)

    it("builds compact segmented tabs inside the strip width", function()
        rawset(_G, "__ZEN_UI_PLUGIN", {
            config = { features = { browser_cover_rounded_corners = true } },
        })
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            component_id = "strip",
            module_cfg = {
                count = 4,
                controls = {
                    enabled = true,
                    order = { "recent", "to_be_read", "tags", "search" },
                    show_buttons = {
                        recent = true, to_be_read = true, tags = true, search = true,
                    },
                    labels = { tags = "Tags" },
                    custom_buttons = {},
                },
            },
            data = { getStripItemsForPage = function() return {} end },
        })

        local outer_frames = {}
        local tab_frames = {}
        local dividers = {}
        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/container/framecontainer"
                    and widget.height == 30 and widget.bordersize == 2 then
                outer_frames[#outer_frames + 1] = widget
            elseif widget.kind == "ui/widget/container/framecontainer"
                    and widget.height == 26 then
                tab_frames[#tab_frames + 1] = widget
            elseif widget.kind == "ui/widget/linewidget"
                    and widget.dimen.h == 26 then
                dividers[#dividers + 1] = widget
            end
        end
        assert.are.equal(1, #outer_frames)
        assert.are.equal(584, outer_frames[1].width)
        assert.are.equal(8, outer_frames[1].radius)
        assert.are.equal(3, #tab_frames)
        assert.are.same({ 176, 176, 175 }, {
            tab_frames[1].width,
            tab_frames[2].width,
            tab_frames[3].width,
        })
        assert.are.same({ 0, 0, 0 }, {
            tab_frames[1].bordersize,
            tab_frames[2].bordersize,
            tab_frames[3].bordersize,
        })
        assert.are.equal(3, #dividers)
        for _i, divider in ipairs(dividers) do
            assert.are.equal(1, divider.dimen.w)
            assert.are.equal("black", divider.background)
        end
        assert.is_true(has_text("Recent"))
        assert.is_true(has_text("Tags"))
        assert.is_true(has_text(require("common/inline_icon_map").search))
    end)

    it("squares strip controls when rounded library covers are disabled", function()
        rawset(_G, "__ZEN_UI_PLUGIN", {
            config = { features = { browser_cover_rounded_corners = false } },
        })
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            component_id = "strip",
            module_cfg = {
                count = 4,
                controls = {
                    enabled = true,
                    order = { "recent" },
                    show_buttons = { recent = true },
                    labels = {},
                    custom_buttons = {},
                },
            },
            data = { getStripItemsForPage = function() return {} end },
        })

        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/container/framecontainer"
                    and widget.height == 30 and widget.bordersize == 2 then
                assert.are.equal(0, widget.radius)
                return
            end
        end
        error("strip controls frame not found")
    end)

    it("keeps normal tab text stable while fitting a long active group label", function()
        local StripControls = require(
            "modules/filebrowser/patches/home/widgets/strip_controls")
        StripControls.build({
            width = 600,
            height = 20,
            active_id = "tags",
            active_group = "A very long tag name that needs truncation",
            controls = {
                order = { "recent", "to_be_read", "tags", "search" },
                show_buttons = {
                    recent = true, to_be_read = true, tags = true, search = true,
                },
                labels = { tags = "Tags" },
                custom_buttons = {},
            },
            on_source = function() return true end,
            on_action = function() return true end,
        })

        local text_widgets = {}
        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/textwidget" and widget.text then
                text_widgets[widget.text] = widget
            end
        end
        assert.are.equal(10, text_widgets.Recent.face.size)
        assert.are.equal(10, text_widgets["To Be Read"].face.size)
        assert.are.equal(9,
            text_widgets["A very long tag name that needs truncation"].face.size)
        assert.is_true(
            text_widgets["A very long tag name that needs truncation"].truncate_with_ellipsis)
        assert.are.equal(14,
            text_widgets[require("common/inline_icon_map").search].face.size)
    end)

    it("applies the configured control font style", function()
        local StripControls = require(
            "modules/filebrowser/patches/home/widgets/strip_controls")
        StripControls.build({
            width = 600,
            height = 30,
            controls = {
                order = { "recent", "search" },
                show_buttons = { recent = true, search = true },
                labels = {},
                custom_buttons = {},
                text_style = {
                    font_face = "ControlFont",
                    font_size = 13,
                    bold = true,
                },
            },
            on_source = function() return true end,
            on_action = function() return true end,
        })

        local recent
        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/textwidget" and widget.text == "Recent" then
                recent = widget
                break
            end
        end
        assert.are.equal("ControlFont", recent.face.name)
        assert.are.equal(13, recent.face.size)
        assert.is_true(recent.bold)
    end)

    it("prepares every visible control for non-touch focus and activation", function()
        local prepared = {}
        local activated = {}
        local StripControls = require(
            "modules/filebrowser/patches/home/widgets/strip_controls")
        local targets = select(2, StripControls.build({
            width = 600,
            height = 20,
            active_id = "recent",
            controls = {
                order = { "recent", "to_be_read", "books", "search" },
                show_buttons = {
                    recent = true, to_be_read = true, books = true, search = true,
                },
                labels = {}, custom_buttons = {},
            },
            prepare_focus = function(target, widget)
                prepared[#prepared + 1] = target
                return widget
            end,
            on_source = function(entry)
                activated[#activated + 1] = entry.id
                return true
            end,
            on_action = function(entry)
                activated[#activated + 1] = entry.id
                return true
            end,
        }))

        assert.are.equal(4, #prepared)
        assert.are.same({
            "strip-control:recent",
            "strip-control:to_be_read",
            "strip-control:books",
            "strip-control:search",
        }, {
            targets[1].key, targets[2].key, targets[3].key, targets[4].key,
        })
        assert.are.equal("white", targets[1].focus_color)
        assert.are.equal("black", targets[2].focus_color)
        for _i, target in ipairs(targets) do
            assert.is_true(target.activate())
        end
        assert.are.same({ "recent", "to_be_read", "books", "search" }, activated)
    end)

    it("renders a restored group as the active strip tab", function()
        local requested_source
        local menu = {
            _zen_home_strip_runtime = {
                active_id = "tags",
                source = {
                    kind = "tags",
                    drill = {
                        label = "Adventure",
                    },
                },
            },
        }
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            menu = menu,
            component_id = "strip",
            module_cfg = {
                controls = {
                    enabled = true,
                    order = { "recent", "tags" },
                    show_buttons = { recent = true, tags = true },
                    labels = { tags = "Tags" }, custom_buttons = {},
                },
            },
            data = {
                getStripItemsForPage = function(_self, source)
                    requested_source = source
                    return {}
                end,
            },
        })

        local active_frames = 0
        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/container/framecontainer"
                    and widget.height == 26 and widget.background == "black" then
                active_frames = active_frames + 1
            end
        end
        assert.are.equal("Adventure", requested_source.drill.label)
        assert.is_true(has_text("Adventure"))
        assert.are.equal(1, active_frames)
    end)

    it("maps a restored tag source to the active Tags tab", function()
        local menu = {
            _zen_home_strip_runtime = {
                source = { kind = "tag", value = "Adventure" },
            },
        }
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            menu = menu,
            component_id = "strip",
            module_cfg = {
                controls = {
                    enabled = true,
                    order = { "recent", "tags" },
                    show_buttons = { recent = true, tags = true },
                    labels = { tags = "Tags" }, custom_buttons = {},
                },
            },
            data = { getStripItemsForPage = function() return {} end },
        })

        local active_frames = 0
        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/container/framecontainer"
                    and widget.height == 26 and widget.background == "black" then
                active_frames = active_frames + 1
            end
        end
        assert.are.equal("tags", menu._zen_home_strip_runtime.active_id)
        assert.is_true(has_text("Adventure"))
        assert.are.equal(1, active_frames)
    end)

    it("repairs a restored source whose control was removed", function()
        local remembered
        local menu = {
            _zen_home_strip_runtime = {
                source = { kind = "authors" },
                active_id = "authors",
            },
        }
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            menu = menu,
            component_id = "strip",
            module_cfg = {
                default_source = { kind = "recent" },
                controls = {
                    enabled = true,
                    order = { "recent", "favorites" },
                    show_buttons = { recent = true, favorites = true },
                    labels = {}, custom_buttons = {},
                },
            },
            data = { getStripItemsForPage = function() return {} end },
            rememberStripState = function(runtime)
                remembered = {
                    source = runtime.source.kind,
                    active_id = runtime.active_id,
                }
            end,
        })

        assert.are.same({ kind = "recent" }, menu._zen_home_strip_runtime.source)
        assert.are.equal("recent", menu._zen_home_strip_runtime.active_id)
        assert.are.same({ source = "recent", active_id = "recent" }, remembered)
    end)

    it("switches source tabs in place and delegates normal actions and Search", function()
        local menu = {}
        local rebuilt = 0
        local resets = 0
        local opened = {}
        local remembered = {}
        local targets
        menu._home_rebuild = function() rebuilt = rebuilt + 1; return true end
        rawset(_G, "__ZEN_UI_NAVBAR_OPEN_TAB", function(id)
            opened[#opened + 1] = id
            return true
        end)
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            menu = menu,
            component_id = "strip",
            module_cfg = {
                count = 4,
                default_source = { kind = "recent" },
                controls = {
                    enabled = true,
                    order = { "recent", "to_be_read", "tags", "books", "search" },
                    show_buttons = {
                        recent = true, to_be_read = true, tags = true,
                        books = true, search = true,
                    },
                    labels = {}, custom_buttons = {},
                },
            },
            data = {
                getStripItemsForPage = function() return {} end,
                resetStripPages = function() resets = resets + 1 end,
            },
            registerHomeFocusTarget = function(_target, widget) return widget end,
            prepareHomeFocusTarget = function(_target, widget) return widget end,
            activateStripFocusTargets = function(value) targets = value end,
            rememberStripState = function(runtime)
                remembered[#remembered + 1] = {
                    active_id = runtime.active_id,
                    kind = runtime.source.kind,
                }
            end,
        })

        local by_key = {}
        for _i, target in ipairs(targets) do by_key[target.key] = target end
        assert.are.same({ kind = "recent" }, menu._zen_home_strip_runtime.source)
        assert.is_true(by_key["strip-control:to_be_read"].activate())
        assert.are.same({ kind = "to_be_read" }, menu._zen_home_strip_runtime.source)
        assert.are.equal("to_be_read", menu._zen_home_strip_runtime.active_id)
        assert.are.equal(1, rebuilt)
        assert.are.equal(1, resets)

        assert.is_true(by_key["strip-control:books"].activate())
        assert.is_true(by_key["strip-control:tags"].activate())
        assert.are.same({ kind = "tags" }, menu._zen_home_strip_runtime.source)
        assert.are.equal("tags", menu._zen_home_strip_runtime.active_id)
        assert.is_true(by_key["strip-control:search"].activate())
        assert.are.same({ "books", "search" }, opened)
        assert.are.equal(2, rebuilt)
        assert.are.equal(2, resets)
        assert.are.same({
            { active_id = "recent", kind = "recent" },
            { active_id = "to_be_read", kind = "to_be_read" },
            { active_id = "tags", kind = "tags" },
        }, remembered)
    end)

    it("does nothing on control hold outside edit mode", function()
        touch_device = true
        local targets
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            component_id = "strip",
            module_cfg = {
                default_source = { kind = "recent" },
                controls = {
                    enabled = true,
                    order = { "recent", "to_be_read", "books" },
                    show_buttons = { recent = true, to_be_read = true, books = true },
                    labels = {}, custom_buttons = {},
                },
            },
            data = { getStripItemsForPage = function() return {} end },
            prepareHomeFocusTarget = function(_target, widget) return widget end,
            activateStripFocusTargets = function(value) targets = value end,
        })

        for _i, widget in ipairs(created) do
            assert.is_nil(widget.onHoldStripControl)
        end

        local by_key = {}
        for _i, target in ipairs(targets) do by_key[target.key] = target end
        assert.is_nil(by_key["strip-control:recent"].context)
        assert.is_nil(by_key["strip-control:to_be_read"].context)
        assert.is_nil(by_key["strip-control:books"].context)
    end)

    it("opens Strip settings from every control hold in edit mode", function()
        touch_device = true
        local settings_opened = 0
        local targets
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            component_id = "strip",
            editMode = true,
            module_cfg = {
                default_source = { kind = "recent" },
                controls = {
                    enabled = true,
                    order = { "recent", "search" },
                    show_buttons = { recent = true, search = true },
                    labels = {}, custom_buttons = {},
                },
            },
            data = { getStripItemsForPage = function() return {} end },
            prepareHomeFocusTarget = function(_target, widget) return widget end,
            activateStripFocusTargets = function(value) targets = value end,
            openWidgetSettings = function()
                settings_opened = settings_opened + 1
                return true
            end,
        })

        local control_inputs = {}
        for _i, widget in ipairs(created) do
            if type(widget.onHoldStripControl) == "function" then
                control_inputs[#control_inputs + 1] = widget
            end
        end
        assert.are.equal(2, #control_inputs)
        assert.is_true(control_inputs[1]:onHoldStripControl(
            nil, { pos = { x = 1, y = 1 } }))

        local by_key = {}
        for _i, target in ipairs(targets) do by_key[target.key] = target end
        assert.is_true(by_key["strip-control:recent"].context())
        assert.is_true(by_key["strip-control:search"].context())
        assert.are.equal(3, settings_opened)
    end)

    it("drills into a stack and resets it from the active tab", function()
        rawset(_G, "__ZEN_UI_PLUGIN", {
            config = {
                browser_folder_cover = {
                    name_centered = true,
                    name_opaque = true,
                    show_folder_name = true,
                    show_item_count = true,
                    show_spine_lines = true,
                },
                features = {
                    browser_cover_mosaic_uniform = true,
                    browser_cover_rounded_corners = true,
                },
            },
        })
        local menu = {}
        local rebuilt = 0
        local resets = 0
        local targets
        local held_group
        local remembered = {}
        menu._home_rebuild = function() rebuilt = rebuilt + 1; return true end
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 300,
            menu = menu,
            component_id = "strip",
            module_cfg = {
                count = 4,
                show_strip_titles = false,
                default_source = { kind = "tags" },
                controls = {
                    enabled = true,
                    order = { "tags" },
                    show_buttons = { tags = true },
                    labels = { tags = "Tags" }, custom_buttons = {},
                },
            },
            data = {
                getStripItemsForPage = function()
                    return {{
                        is_group = true,
                        group_label = "Fantasy",
                        group_count = 2,
                        group_files = { "/books/a.epub", "/books/b.epub" },
                    }}
                end,
                resetStripPages = function() resets = resets + 1 end,
            },
            registerHomeFocusTarget = function(_target, widget) return widget end,
            prepareHomeFocusTarget = function(_target, widget) return widget end,
            activateStripFocusTargets = function(value) targets = value end,
            showStripGroupMenu = function(book)
                held_group = book
                return true
            end,
            rememberStripState = function(runtime)
                remembered[#remembered + 1] = {
                    active_id = runtime.active_id,
                    label = runtime.source.drill and runtime.source.drill.label,
                }
            end,
        })

        local group_stack_found = false
        for _i, widget in ipairs(created) do
            if widget.kind == "ui/widget/overlapgroup" then
                group_stack_found = true
                break
            end
        end
        assert.is_false(group_stack_found)
        assert.is_false(has_text("Fantasy (2)"))
        assert.are.equal(0, #cover_books)
        assert.are.same({ "/books/a.epub", "/books/b.epub" },
            folder_calls.build.entry._zen_files)
        assert.are.equal("Fantasy", folder_calls.build.title)
        assert.is_true(folder_calls.build.options.uniform)
        assert.are.equal(0, folder_calls.overlay.options.strip_height)
        assert.is_true(folder_calls.overlay.options.config.browser_folder_cover.name_centered)
        assert.is_true(folder_calls.overlay.options.config.browser_folder_cover.name_opaque)
        assert.is_true(folder_calls.overlay.options.config.features.browser_cover_rounded_corners)
        assert.are.equal(2, folder_calls.decorate.count)
        assert.are.equal(folder_calls.overlay.options.config, folder_calls.decorate.config)

        local by_key = {}
        for _i, target in ipairs(targets) do by_key[target.key] = target end
        assert.is_true(by_key["group:Fantasy"].context())
        assert.are.equal("Fantasy", held_group.group_label)
        assert.is_true(by_key["group:Fantasy"].activate())
        assert.are.equal("Fantasy", menu._zen_home_strip_runtime.source.drill.label)
        assert.are.same({ "/books/a.epub", "/books/b.epub" },
            menu._zen_home_strip_runtime.source.drill.files)
        assert.is_true(by_key["strip-control:tags"].activate())
        assert.is_nil(menu._zen_home_strip_runtime.source.drill)
        assert.are.same({
            { active_id = "tags" },
            { active_id = "tags", label = "Fantasy" },
            { active_id = "tags" },
        }, remembered)
        assert.are.equal(2, rebuilt)
        assert.are.equal(2, resets)
    end)

    it("exposes vertical slack for Home gap balancing", function()
        local books = {
            { path = "/library/a.epub" },
            { path = "/library/b.epub" },
            { path = "/library/c.epub" },
            { path = "/library/d.epub" },
        }
        local content_bounds
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 400,
            component_id = "strip",
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
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        Strip.build({
            width = 600,
            height = 160,
            face_label = { size = 12 },
            component_id = "strip",
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
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip",
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
        assert.are.same({ { kind = "recent" }, 4, "default", "next", "strip", false }, shifted)
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
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip",
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

    it("hydrates grouped folder previews after the first paint", function()
        folder_needs_hydration = true
        local refreshed = 0
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 240,
            component_id = "strip",
            module_cfg = { count = 4, show_strip_titles = false },
            data = {
                getStripItemsForPage = function()
                    return {{
                        is_group = true,
                        group_kind = "tags",
                        group_label = "Fantasy",
                        group_count = 2,
                        group_files = { "/books/a.epub", "/books/b.epub" },
                    }}
                end,
            },
            refreshStrip = function() refreshed = refreshed + 1 end,
        })

        assert.is_true(folder_calls.builds[1].options.cached_only)
        widget:paintTo({}, 0, 0)
        assert.are.same({ 0.05 }, scheduled_delays)
        run_scheduled()

        assert.is_false(folder_calls.builds[2].options.cached_only)
        assert.is_false(folder_calls.builds[2].options.decorate)
        assert.is_true(folder_calls.builds[3].options.cached_only)
        assert.are.equal(1, refreshed)
        assert.are.equal(0, #scheduled)
    end)

    it("refreshes a grouped preview when one of its pending covers is ready", function()
        folder_needs_hydration = true
        local member_covers_pending = true
        local cover_listener
        local refreshed = 0
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 240,
            component_id = "strip",
            module_cfg = { count = 4, show_strip_titles = false },
            data = {
                getStripItemsForPage = function()
                    return {{
                        is_group = true,
                        group_kind = "tags",
                        group_label = "Fantasy",
                        group_count = 2,
                        group_files = { "/books/a.epub", "/books/b.epub" },
                    }}
                end,
                warmStripCover = function()
                    return member_covers_pending and "pending" or "warmed"
                end,
            },
            registerStripCoverListener = function(listener)
                cover_listener = listener
                return function() end
            end,
            refreshStrip = function() refreshed = refreshed + 1 end,
        })

        widget:paintTo({}, 0, 0)
        run_scheduled()
        assert.are.equal(1, #folder_calls.builds)
        assert.are.same({ 0.4 }, scheduled_delays)
        assert.are.equal(0, refreshed)

        member_covers_pending = false
        cover_listener("/books/a.epub")
        assert.are.same({ 0 }, scheduled_delays)
        run_scheduled()

        assert.is_false(folder_calls.builds[2].options.cached_only)
        assert.is_true(folder_calls.builds[3].options.cached_only)
        assert.are.equal(1, refreshed)
        assert.are.equal(0, #scheduled)
    end)

    it("prewarms next-direction covers without building its frame", function()
        touch_device = true
        local pages = {
            [-1] = { { path = "/library/previous.epub", title = "Previous" } },
            [0] = { { path = "/library/current.epub", title = "Current" } },
            [1] = { { path = "/library/next.epub", title = "Next" } },
        }
        local current_page = 0
        local page_requests = 0
        local requested_deltas = {}
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip",
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
        assert.are.equal(1, #cover_books)

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
        assert.are.equal(2, #cover_books)
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
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip",
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
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip",
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
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip",
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
        local Strip = require("modules/filebrowser/patches/home/widgets/strip")
        local widget = Strip.build({
            width = 600,
            height = 160,
            component_id = "strip",
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

describe("home cover rendering", function()
    local allocations
    local old_plugin
    local render_request

    local function widget_class()
        return {
            new = function(_, values)
                values = values or {}
                values.dimen = values.dimen or {
                    x = 0, y = 0, w = values.width or 1, h = values.height or 1,
                }
                values.getSize = values.getSize or function(self) return self.dimen end
                values.paintTo = values.paintTo or function(self, _bb, x, y)
                    self.dimen.x, self.dimen.y = x, y
                end
                values.free = values.free or function() end
                return values
            end,
        }
    end

    before_each(function()
        allocations = {}
        render_request = nil
        old_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        _G.__ZEN_UI_PLUGIN = {
            config = { features = { browser_cover_rounded_corners = true } },
        }
        ZenSpec.replace("ffi/blitbuffer", {
            COLOR_BLACK = "black",
            COLOR_LIGHT_GRAY = "lightgray",
            new = function(width, height)
                allocations[#allocations + 1] = { width, height }
                return { blitFrom = function() end, free = function() end }
            end,
        })
        ZenSpec.replace("device", {
            screen = { scaleBySize = function(_, value) return value end },
        })
        ZenSpec.replace("ui/geometry", { new = function(_, values) return values end })
        for _i, name in ipairs({
            "ui/widget/container/centercontainer", "ui/widget/container/framecontainer",
            "ui/widget/imagewidget", "ui/widget/textboxwidget", "ui/widget/verticalgroup",
            "ui/widget/verticalspan", "ui/widget/widget",
        }) do
            ZenSpec.replace(name, widget_class())
        end
        ZenSpec.replace("ui/font", { getFace = function() return {} end })
        ZenSpec.replace("common/cover_utils", {
            BORDER_SIZE = 1,
            fitDims = function(max_w, max_h, source_w, source_h)
                local scale = math.min(max_w / source_w, max_h / source_h)
                return math.floor(source_w * scale + 0.5),
                    math.floor(source_h * scale + 0.5)
            end,
            genCover = function()
                return { free = function() end }
            end,
            getEmptyPlaceholderText = function() return "Empty" end,
        })
        ZenSpec.replace("common/cover_render_cache", {
            get = function() end,
            render = function(_, path, source, width, height)
                render_request = { path = path, width = width, height = height }
                return source
            end,
        })
        ZenSpec.unload("modules/filebrowser/patches/home/widgets/cover_common")
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = old_plugin
    end)

    it("snapshots only four packed corner squares", function()
        local Cover = require("modules/filebrowser/patches/home/widgets/cover_common")
        local frame = Cover.make_cover_widget(
            { path = "/library/alpha.epub" }, 100, 150, { uniform = false })
        local target = {
            getType = function() return "bb8" end,
            blitFrom = function() end,
            paintRect = function() end,
        }

        frame:paintTo(target, 10, 20)

        assert.are.same({ { 32, 8 } }, allocations)
    end)

    it("keeps the corner radius fixed for smaller list covers", function()
        local Cover = require("modules/filebrowser/patches/home/widgets/cover_common")
        local target = {
            getType = function() return "bb8" end,
            blitFrom = function() end,
            paintRect = function() end,
        }
        local large = Cover.make_cover_widget(
            { path = "/library/large.epub" }, 100, 150)
        local small = Cover.make_cover_widget(
            { path = "/library/small.epub" }, 18, 28)

        large:paintTo(target, 10, 20)
        small:paintTo(target, 10, 20)

        assert.are.same({ { 32, 8 }, { 32, 8 } }, allocations)
    end)

    it("fits a non-uniform frame to the real cover aspect ratio", function()
        local Cover = require("modules/filebrowser/patches/home/widgets/cover_common")
        local frame, width, height = Cover.make_cover_widget({
            path = "/library/landscape.epub",
            cover_bb = {
                getWidth = function() return 120 end,
                getHeight = function() return 80 end,
            },
        }, 100, 150, { uniform = false })

        assert.are.equal(100, width)
        assert.are.equal(67, height)
        assert.are.equal(100, frame:getSize().w)
        assert.are.equal(67, frame:getSize().h)
        assert.are.same({
            path = "/library/landscape.epub", width = 100, height = 67,
        }, render_request)
    end)
end)

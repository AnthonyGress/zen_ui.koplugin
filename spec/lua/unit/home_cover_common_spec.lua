describe("home cover rendering", function()
    local allocations
    local old_plugin

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
            genCover = function()
                return { free = function() end }
            end,
            getEmptyPlaceholderText = function() return "Empty" end,
        })
        ZenSpec.replace("common/cover_render_cache", {
            get = function() end,
            render = function(_, _path, source) return source end,
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
end)

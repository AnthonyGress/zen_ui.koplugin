describe("library background cleanup", function()
    before_each(function()
        ZenSpec.replace("device", { screen = {} })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_WHITE = "white" })
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return { warn = function() end }
            end,
        })
        ZenSpec.replace("ui/widget/imagewidget", {})
        ZenSpec.replace("libs/libkoreader-lfs", {})
        ZenSpec.unload("common/ui/background")
    end)

    after_each(function()
        ZenSpec.unload("common/ui/background")
    end)

    it("keeps explicitly opaque widget backgrounds", function()
        local Background = require("common/ui/background")
        local protected = { background = "white", _zen_keep_background = true }
        local ordinary = { background = "white" }

        Background.clearWhiteBackgrounds({ protected, ordinary })

        assert.are.equal("white", protected.background)
        assert.is_nil(ordinary.background)
    end)
end)

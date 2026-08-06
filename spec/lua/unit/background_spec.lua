describe("library background cleanup", function()
    local original_plugin

    before_each(function()
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        ZenSpec.replace("device", { screen = {} })
        ZenSpec.replace("ffi/blitbuffer", { COLOR_WHITE = "white" })
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return { warn = function() end }
            end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/widget/imagewidget", {})
        ZenSpec.replace("libs/libkoreader-lfs", {})
        ZenSpec.unload("common/ui/background")
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = original_plugin
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

    it("coalesces missing-image recovery without restoring the live widget tree", function()
        local exists = true
        local saved = 0
        local recoveries = 0
        local scheduled = {}
        local path = "/library/background.jpg"
        local config = {
            library_background = { enabled = true, path = path },
        }
        local plugin = {
            config = config,
            saveConfig = function() saved = saved + 1 end,
        }
        _G.__ZEN_UI_PLUGIN = plugin
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function() return exists and "file" or nil end,
        })
        ZenSpec.replace("ui/widget/notification", {
            new = function(_self, opts) return opts end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, callback) scheduled[#scheduled + 1] = callback end,
            show = function() end,
        })
        ZenSpec.unload("common/ui/background")

        local Background = require("common/ui/background")
        Background.paintScreenRegion = function() return true end
        local tile = { background = nil }
        local root = { background = "white", tile }
        local menu = {
            dimen = { w = 100, h = 100 },
            root,
        }
        Background.applyToMenu(menu)

        menu:paintTo({}, 0, 0)
        assert.is_nil(root.background)
        assert.is_nil(tile.background)

        Background.setMissingLibraryBackgroundHandler(function()
            recoveries = recoveries + 1
            assert.is_nil(root.background)
            assert.is_nil(tile.background)
            return true
        end)
        exists = false
        menu:paintTo({}, 0, 0)
        assert.are.equal("", Background.library_path(plugin))

        assert.is_false(config.library_background.enabled)
        assert.are.equal(1, saved)
        assert.are.equal(1, #scheduled)
        assert.are.equal(0, recoveries)
        assert.is_nil(root.background)
        assert.is_nil(tile.background)

        scheduled[1]()

        assert.are.equal(1, recoveries)
        assert.is_nil(root.background)
        assert.is_nil(tile.background)
        assert.are.equal("", Background.library_path(plugin))
        assert.are.equal(1, saved)
        assert.are.equal(1, #scheduled)
    end)

    it("retries a deferred recovery after a temporary blocker and then stops", function()
        local recoveries = 0
        local saved = 0
        local notices = 0
        local scheduled = {}
        local path = "/library/background.jpg"
        local config = {
            library_background = { enabled = true, path = path },
        }
        local plugin = {
            config = config,
            saveConfig = function() saved = saved + 1 end,
        }
        _G.__ZEN_UI_PLUGIN = plugin
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function() return nil end,
        })
        ZenSpec.replace("ui/widget/notification", {
            new = function(_self, opts) return opts end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, callback) scheduled[#scheduled + 1] = callback end,
            show = function() notices = notices + 1 end,
        })
        ZenSpec.unload("common/ui/background")

        local Background = require("common/ui/background")
        Background.setMissingLibraryBackgroundHandler(function()
            recoveries = recoveries + 1
            return recoveries > 1
        end)

        assert.are.equal("", Background.library_path(plugin))
        assert.are.equal("", Background.library_path(plugin))
        assert.are.equal(1, #scheduled)
        scheduled[1]()

        assert.are.equal(1, recoveries)
        assert.are.equal(1, notices)
        assert.are.equal(1, saved)

        assert.are.equal("", Background.library_path(plugin))
        assert.are.equal("", Background.library_path(plugin))
        assert.are.equal(2, #scheduled)
        scheduled[2]()

        assert.are.equal(2, recoveries)
        assert.are.equal(1, notices)
        assert.are.equal(1, saved)
        assert.are.equal("", Background.library_path(plugin))
        assert.are.equal(2, #scheduled)
    end)

    it("disables a configured background and notifies when its image is missing", function()
        local saved = 0
        local shown
        local notice_closes = 0
        local dirty
        local scheduled = {}
        local path = "/library/removed.jpg"
        local config = {
            library_background = { enabled = true, path = path },
        }
        local plugin = {
            config = config,
            saveConfig = function() saved = saved + 1 end,
        }
        _G.__ZEN_UI_PLUGIN = plugin
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(checked_path, attribute)
                assert.are.equal(path, checked_path)
                assert.are.equal("mode", attribute)
                return nil
            end,
        })
        ZenSpec.replace("ui/widget/notification", {
            new = function(_self, opts)
                opts.onCloseWidget = function()
                    notice_closes = notice_closes + 1
                    return "closed"
                end
                return opts
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            nextTick = function(_self, callback) scheduled[#scheduled + 1] = callback end,
            show = function(_self, widget) shown = widget end,
            setDirty = function(_self, widget, refresh)
                dirty = { widget, refresh }
            end,
        })
        ZenSpec.unload("common/ui/background")

        local Background = require("common/ui/background")
        assert.are.equal("", Background.library_path(plugin))

        assert.is_false(config.library_background.enabled)
        assert.are.equal(path, config.library_background.path)
        assert.are.equal(1, saved)
        assert.are.equal(1, #scheduled)
        assert.is_nil(shown)

        scheduled[1]()
        assert.are.equal(
            "Library background was disabled because the image file was not found.",
            shown.text
        )
        assert.are.equal("closed", shown:onCloseWidget())
        assert.are.equal(1, notice_closes)
        assert.are.equal(2, #scheduled)
        assert.is_nil(dirty)

        scheduled[2]()
        assert.are.same({ "all", "full" }, dirty)
        assert.are.equal("", Background.library_path(plugin))
        assert.are.equal(1, saved)
    end)
end)

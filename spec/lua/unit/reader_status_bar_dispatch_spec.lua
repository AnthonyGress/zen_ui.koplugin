describe("reader status bar dispatcher actions", function()
    local Dispatch
    local footer
    local plugin

    before_each(function()
        _G.G_reader_settings = ZenSpec.memorySettings({ reader_footer_mode = 3 })
        footer = {
            mode = 3,
            mode_list = { off = 0, page_progress = 1 },
            view = { footer_visible = true },
            applyFooterMode = function(self, mode)
                self.mode = mode
                self.view.footer_visible = mode ~= self.mode_list.off
            end,
            refreshFooter = function() end,
            rescheduleFooterAutoRefreshIfNeeded = function() end,
        }
        ZenSpec.replace("apps/reader/readerui", {
            instance = { view = { footer = footer } },
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.unload("common/dispatch_action")
        Dispatch = require("common/dispatch_action")
        plugin = {
            config = { features = {}, reader_footer = {} },
            saves = 0,
            saveConfig = function(self) self.saves = self.saves + 1 end,
        }
    end)

    it("persists the disabled bottom bar and its previous mode", function()
        assert.is_true(Dispatch.setBottomStatusBar(plugin, false))

        assert.is_false(plugin.config.reader_footer.status_bar_enabled)
        assert.are.equal(3, plugin.config.reader_footer.last_status_bar_mode)
        assert.are.equal(0, G_reader_settings:readSetting("reader_footer_mode"))
        assert.is_false(footer.view.footer_visible)
        assert.are.equal(1, plugin.saves)
    end)

    it("persists re-enabling and restores the previous mode", function()
        plugin.config.reader_footer = {
            status_bar_enabled = false,
            last_status_bar_mode = 3,
        }
        footer.mode = 0
        footer.view.footer_visible = false
        G_reader_settings:saveSetting("reader_footer_mode", 0)

        assert.is_true(Dispatch.setBottomStatusBar(plugin, true))

        assert.is_true(plugin.config.reader_footer.status_bar_enabled)
        assert.are.equal(3, G_reader_settings:readSetting("reader_footer_mode"))
        assert.is_true(footer.view.footer_visible)
        assert.are.equal(1, plugin.saves)
    end)

    it("falls back to persisted state outside the reader", function()
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI.instance = nil
        plugin.config.reader_footer.status_bar_enabled = true

        assert.is_true(Dispatch.isBottomStatusBarVisible(plugin))
        plugin.config.reader_footer.status_bar_enabled = false
        assert.is_false(Dispatch.isBottomStatusBarVisible(plugin))
        plugin.config.reader_footer = nil
        assert.is_true(Dispatch.isBottomStatusBarVisible(plugin))

        plugin.config.reader_footer = { status_bar_enabled = false }
        ReaderUI.instance = { view = { footer = footer } }
        footer.view.footer_visible = true
        assert.is_true(Dispatch.isBottomStatusBarVisible(plugin))
        plugin.config.reader_footer.status_bar_enabled = true
        footer.view.footer_visible = false
        assert.is_false(Dispatch.isBottomStatusBarVisible(plugin))
        footer.view.footer_visible = nil
        assert.is_true(Dispatch.isBottomStatusBarVisible(plugin))
    end)
end)

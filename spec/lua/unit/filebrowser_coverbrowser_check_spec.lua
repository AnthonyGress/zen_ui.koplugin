describe("filebrowser CoverBrowser availability check", function()
    local UIManager
    local scheduled
    local shown
    local closed
    local restart_prompts

    before_each(function()
        scheduled = nil
        shown = nil
        closed = nil
        restart_prompts = 0
        UIManager = {
            scheduleIn = function(_, delay, callback)
                scheduled = { delay = delay, callback = callback }
            end,
            show = function(_, dialog) shown = dialog end,
            close = function(_, dialog) closed = dialog end,
        }
        ZenSpec.replace("ui/uimanager", UIManager)
        ZenSpec.replace("ui/widget/buttondialog", {
            new = function(_, options) return options end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("modules/settings/zen_settings_apply", {
            prompt_restart = function() restart_prompts = restart_prompts + 1 end,
        })
        package.loaded.covermenu = nil
        package.preload.covermenu = nil
        ZenSpec.unload("modules/filebrowser/patches/coverbrowser_check")
    end)

    after_each(function()
        package.loaded.covermenu = nil
        package.preload.covermenu = nil
    end)

    it("defers the check and stays silent when CoverBrowser is loaded", function()
        package.loaded.covermenu = {}
        require("modules/filebrowser/patches/coverbrowser_check")()

        assert.are.equal(1, scheduled.delay)
        scheduled.callback()
        assert.is_nil(shown)
    end)

    it("shows a dismissible warning when CoverBrowser is unavailable", function()
        package.preload.covermenu = function() error("disabled") end
        _G.G_reader_settings = ZenSpec.memorySettings()
        require("modules/filebrowser/patches/coverbrowser_check")()
        scheduled.callback()

        assert.is_truthy(shown.title:find("not enabled", 1, true))
        assert.are.equal("OK", shown.buttons[1][1].text)
        shown.buttons[1][1].callback()
        assert.is_true(rawequal(shown, closed))
    end)

    it("enables a disabled CoverBrowser plugin and requests restart", function()
        package.preload.covermenu = function() error("disabled") end
        local disabled = { coverbrowser = true, statistics = true }
        local flushed = 0
        _G.G_reader_settings = ZenSpec.memorySettings({ plugins_disabled = disabled })
        _G.G_reader_settings.flush = function() flushed = flushed + 1 end
        require("modules/filebrowser/patches/coverbrowser_check")()
        scheduled.callback()

        assert.are.equal("Enable", shown.buttons[1][1].text)
        assert.are.equal("OK", shown.buttons[2][1].text)
        shown.buttons[1][1].callback()

        assert.is_nil(disabled.coverbrowser)
        assert.is_true(disabled.statistics)
        assert.are.equal(1, flushed)
        assert.are.equal(1, restart_prompts)
        assert.is_true(rawequal(shown, closed))
    end)
end)

describe("Zen mode settings apply", function()
    local saved_runtime_patches
    local saved_modules

    local dependencies = {
        "gettext",
        "ui/uimanager",
        "ui/widget/confirmbox",
        "common/restart",
        "common/shared_state",
        "ui/widget/touchmenu",
        "modules/menu/patches/zen_mode",
        "modules/settings/zen_settings_apply",
    }

    before_each(function()
        saved_runtime_patches = rawget(_G, "__ZEN_UI_RUNTIME_PATCHES")
        saved_modules = {}
        for _i, name in ipairs(dependencies) do saved_modules[name] = package.loaded[name] end
        _G.__ZEN_UI_RUNTIME_PATCHES = nil
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {
            setDirty = function() end,
            nextTick = function(_self, callback) callback() end,
        })
        ZenSpec.replace("ui/widget/confirmbox", {
            new = function(_self, values) return values end,
        })
        ZenSpec.replace("common/restart", {})
        ZenSpec.replace("ui/widget/touchmenu", {})
        ZenSpec.unload("modules/settings/zen_settings_apply")
    end)

    after_each(function()
        _G.__ZEN_UI_RUNTIME_PATCHES = saved_runtime_patches
        for _i, name in ipairs(dependencies) do package.loaded[name] = saved_modules[name] end
    end)

    it("loads and refreshes Zen mode without prompting for restart", function()
        local applies = 0
        local refreshes = 0
        local restart_prompts = 0
        local plugin = { config = { features = { zen_mode = true } } }
        ZenSpec.replace("common/shared_state", {
            register = function() end,
            get = function(_plugin, key)
                if key == "refreshZenModeMenus" then
                    return function() refreshes = refreshes + 1 end
                end
            end,
        })
        ZenSpec.replace("modules/menu/patches/zen_mode", function()
            applies = applies + 1
        end)
        package.loaded["ui/uimanager"].show = function()
            restart_prompts = restart_prompts + 1
        end

        require("modules/settings/zen_settings_apply").apply_feature_toggle(plugin, "zen_mode", true)

        assert.are.equal(1, applies)
        assert.are.equal(1, refreshes)
        assert.are.equal(0, restart_prompts)
    end)

    it("defers navbar reinjection until the Zen settings page closes", function()
        local reinjections = 0
        local queued = {}
        local UIManager = require("ui/uimanager")
        UIManager.nextTick = function(_self, callback)
            queued[#queued + 1] = callback
        end
        _G.__ZEN_UI_SETTINGS_PAGE = {}
        _G.__ZEN_UI_REINJECT_NAVBARS = function()
            reinjections = reinjections + 1
        end

        local settings_apply = require("modules/settings/zen_settings_apply")
        settings_apply.refresh_navbar_on_menu_close()

        assert.are.equal(0, reinjections)
        _G.__ZEN_UI_SETTINGS_PAGE = nil
        settings_apply.flush_deferred_on_settings_close()
        assert.are.equal(1, #queued)

        queued[1]()
        assert.are.equal(1, reinjections)
        _G.__ZEN_UI_REINJECT_NAVBARS = nil
    end)
end)

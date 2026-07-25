describe("global schedule resume hook", function()
    local global
    local ui_manager
    local patched_modules = {
        "modules/global/patches/night_mode_schedule",
        "modules/global/patches/warmth_schedule",
        "modules/global/patches/brightness_schedule",
        "modules/global/patches/menu_top_swipe",
        "modules/global/patches/opds",
        "modules/global/patches/kindle_network_profile_guard",
        "modules/global/patches/lockdown_mode",
        "modules/global/patches/incognito_mode",
        "modules/global/patches/menu_font",
    }

    before_each(function()
        _G.__ZEN_UI_NIGHT_SCHEDULE = { force_reschedule = function()
            _G.night_reschedules = (_G.night_reschedules or 0) + 1
        end }
        _G.__ZEN_UI_BRIGHTNESS_SCHEDULE = { force_reschedule = function()
            _G.brightness_reschedules = (_G.brightness_reschedules or 0) + 1
        end }
        _G.__ZEN_UI_WARMTH_SCHEDULE = { force_reschedule = function()
            _G.warmth_reschedules = (_G.warmth_reschedules or 0) + 1
        end }
        _G.night_reschedules = nil
        _G.brightness_reschedules = nil
        _G.warmth_reschedules = nil

        ui_manager = {
            broadcastEvent = function(_, event)
                return event.handler == "onResume"
            end,
            setDirty = function() end,
        }
        ZenSpec.replace("ui/uimanager", ui_manager)
        ZenSpec.replace("device", {
            canHWInvert = function() return false end,
        })
        for _i, name in ipairs(patched_modules) do
            ZenSpec.replace(name, function() end)
        end
        ZenSpec.unload("modules/global/global")
        global = require("modules/global/global")
    end)

    after_each(function()
        for _i, name in ipairs(patched_modules) do
            ZenSpec.unload(name)
        end
        ZenSpec.unload("modules/global/global")
        ZenSpec.unload("ui/uimanager")
        ZenSpec.unload("device")
        _G.__ZEN_UI_NIGHT_SCHEDULE = nil
        _G.__ZEN_UI_BRIGHTNESS_SCHEDULE = nil
        _G.__ZEN_UI_WARMTH_SCHEDULE = nil
        _G.night_reschedules = nil
        _G.brightness_reschedules = nil
        _G.warmth_reschedules = nil
    end)

    it("reapplies schedules after Resume even when another widget handled it", function()
        assert.is_true(global.init(nil, { config = { features = {} } }))

        assert.is_true(ui_manager:broadcastEvent({ handler = "onResume" }))
        assert.are.equal(1, _G.night_reschedules)
        assert.are.equal(1, _G.brightness_reschedules)
        assert.are.equal(1, _G.warmth_reschedules)
    end)

    it("does not reapply schedules for unrelated broadcasts", function()
        assert.is_true(global.init(nil, { config = { features = {} } }))

        ui_manager:broadcastEvent({ handler = "onCharging" })
        assert.is_nil(_G.night_reschedules)
        assert.is_nil(_G.brightness_reschedules)
        assert.is_nil(_G.warmth_reschedules)
    end)
end)

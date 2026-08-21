describe("global frontlight settings", function()
    local module_names = {
        "gettext",
        "ui/uimanager",
        "device",
        "ui/widget/confirmbox",
        "common/restart",
        "config/preset_store",
        "modules/settings/zen_settings_utils",
        "common/inline_icon_map",
        "common/ui/icon_menu_item",
        "common/plugin_root",
        "libs/libkoreader-lfs",
    }
    local originals
    local original_suntime
    local original_brightness_state
    local original_warmth_state

    before_each(function()
        originals = {}
        for _i, name in ipairs(module_names) do originals[name] = package.loaded[name] end
        original_suntime = package.loaded["suntime"]
        package.loaded["suntime"] = nil
        original_brightness_state = rawget(_G, "__ZEN_UI_BRIGHTNESS_SCHEDULE")
        original_warmth_state = rawget(_G, "__ZEN_UI_WARMTH_SCHEDULE")

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ui/uimanager", {})
        ZenSpec.replace("device", {
            powerd = {
                fl_max = 100,
                fl_warmth_min = 0,
                fl_warmth_max = 24,
            },
            hasNaturalLight = function() return true end,
        })
        ZenSpec.replace("ui/widget/confirmbox", {})
        ZenSpec.replace("common/restart", {})
        ZenSpec.replace("config/preset_store", {})
        ZenSpec.replace("modules/settings/zen_settings_utils", {
            fmt_time = function(h, m) return h .. ":" .. m end,
        })
        ZenSpec.replace("common/inline_icon_map", {})
        ZenSpec.replace("common/ui/icon_menu_item", {})
        ZenSpec.replace("common/plugin_root", "/missing")
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function() return nil end,
        })
        ZenSpec.unload("modules/settings/sections/global_settings")
    end)

    after_each(function()
        ZenSpec.unload("modules/settings/sections/global_settings")
        for _i, name in ipairs(module_names) do package.loaded[name] = originals[name] end
        package.loaded["suntime"] = original_suntime
        _G.__ZEN_UI_BRIGHTNESS_SCHEDULE = original_brightness_state
        _G.__ZEN_UI_WARMTH_SCHEDULE = original_warmth_state
    end)

    local function build_items()
        local config = {
            search = {},
            features = {
                night_mode_schedule = false,
                brightness_schedule = false,
                warmth_schedule = false,
            },
            night_mode_schedule = {},
            brightness_schedule = {
                day_value = 20,
                night_value = 5,
                use_mode_values = true,
            },
            warmth_schedule = {
                day_value = 3,
                night_value = 8,
                use_mode_values = true,
            },
            lockdown = {},
        }
        local plugin = {
            saveConfig = function(self)
                self.save_calls = (self.save_calls or 0) + 1
            end,
        }
        local items = require("modules/settings/sections/global_settings").build({
            config = config,
            plugin = plugin,
        })
        return items, config, plugin
    end

    it("uses the day/night wording pattern for light/dark values", function()
        local items = build_items()
        local brightness = items[3].sub_item_table
        local warmth = items[4].sub_item_table

        assert.are.equal("Light mode / Dark mode brightness", brightness[2].text)
        assert.are.equal("Light mode brightness: 20", brightness[4].text_func())
        assert.are.equal("Dark mode brightness: 5", brightness[6].text_func())
        assert.are.equal("Light mode / Dark mode warmth", warmth[2].text)
        assert.are.equal("Light mode warmth: 3", warmth[4].text_func())
        assert.are.equal("Dark mode warmth: 8", warmth[6].text_func())
    end)

    it("turns mode brightness off whenever its schedule is toggled", function()
        local items, config, plugin = build_items()
        local schedule_toggle = items[3].sub_item_table[1]
        local reschedules = 0
        _G.__ZEN_UI_BRIGHTNESS_SCHEDULE = {
            reschedule = function() reschedules = reschedules + 1 end,
        }

        schedule_toggle.callback()
        assert.is_true(config.features.brightness_schedule)
        assert.is_false(config.brightness_schedule.use_mode_values)

        config.brightness_schedule.use_mode_values = true
        schedule_toggle.callback()
        assert.is_false(config.features.brightness_schedule)
        assert.is_false(config.brightness_schedule.use_mode_values)
        assert.are.equal(2, plugin.save_calls)
        assert.are.equal(2, reschedules)
    end)

    it("turns the brightness schedule off when mode brightness is enabled", function()
        local items, config, plugin = build_items()
        local mode_toggle = items[3].sub_item_table[2]
        local reschedules = 0
        config.features.brightness_schedule = true
        config.brightness_schedule.use_mode_values = false
        _G.__ZEN_UI_BRIGHTNESS_SCHEDULE = {
            reschedule = function() reschedules = reschedules + 1 end,
        }

        mode_toggle.callback()

        assert.is_true(config.brightness_schedule.use_mode_values)
        assert.is_false(config.features.brightness_schedule)
        assert.are.equal(1, plugin.save_calls)
        assert.are.equal(1, reschedules)
    end)

    it("turns mode warmth off whenever its schedule is toggled", function()
        local items, config, plugin = build_items()
        local schedule_toggle = items[4].sub_item_table[1]
        local reschedules = 0
        _G.__ZEN_UI_WARMTH_SCHEDULE = {
            reschedule = function() reschedules = reschedules + 1 end,
        }

        schedule_toggle.callback()
        assert.is_true(config.features.warmth_schedule)
        assert.is_false(config.warmth_schedule.use_mode_values)

        config.warmth_schedule.use_mode_values = true
        schedule_toggle.callback()
        assert.is_false(config.features.warmth_schedule)
        assert.is_false(config.warmth_schedule.use_mode_values)
        assert.are.equal(2, plugin.save_calls)
        assert.are.equal(2, reschedules)
    end)

    it("turns the warmth schedule off when mode warmth is enabled", function()
        local items, config, plugin = build_items()
        local mode_toggle = items[4].sub_item_table[2]
        local reschedules = 0
        config.features.warmth_schedule = true
        config.warmth_schedule.use_mode_values = false
        _G.__ZEN_UI_WARMTH_SCHEDULE = {
            reschedule = function() reschedules = reschedules + 1 end,
        }

        mode_toggle.callback()

        assert.is_true(config.warmth_schedule.use_mode_values)
        assert.is_false(config.features.warmth_schedule)
        assert.are.equal(1, plugin.save_calls)
        assert.are.equal(1, reschedules)
    end)
end)

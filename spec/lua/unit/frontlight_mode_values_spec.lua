describe("frontlight light/dark mode values", function()
    local original_plugin

    before_each(function()
        original_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
        _G.__ZEN_UI_BRIGHTNESS_SCHEDULE = nil
        _G.__ZEN_UI_WARMTH_SCHEDULE = nil
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = original_plugin
        _G.__ZEN_UI_BRIGHTNESS_SCHEDULE = nil
        _G.__ZEN_UI_WARMTH_SCHEDULE = nil
        ZenSpec.unload("modules/global/patches/brightness_schedule")
        ZenSpec.unload("modules/global/patches/warmth_schedule")
        ZenSpec.unload("ui/uimanager")
        ZenSpec.unload("device")
    end)

    local function make_screen()
        return {
            night_mode = false,
            toggleNightMode = function(self)
                self.night_mode = not self.night_mode
            end,
        }
    end

    local function make_ui_manager()
        return {
            setDirty = function() end,
            scheduleIn = function() end,
            unschedule = function() end,
            nextTick = function(_, callback) callback() end,
        }
    end

    it("applies brightness on mode changes while the time schedule is off", function()
        local screen = make_screen()
        local powerd = {
            fl_min = 0,
            fl_max = 100,
            is_on = true,
            values = {},
            setIntensity = function(self, value)
                self.values[#self.values + 1] = value
            end,
            isFrontlightOff = function(self) return not self.is_on end,
            turnOnFrontlight = function(self) self.is_on = true end,
            updateResumeFrontlightState = function() end,
        }
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { brightness_schedule = false },
                brightness_schedule = {
                    use_mode_values = true,
                    day_value = 42,
                    night_value = 7,
                },
            },
        }
        ZenSpec.replace("device", { screen = screen, powerd = powerd })
        ZenSpec.replace("ui/uimanager", make_ui_manager())

        require("modules/global/patches/brightness_schedule")()
        assert.are.same({ 42 }, powerd.values)

        screen:toggleNightMode()
        assert.are.same({ 42, 7 }, powerd.values)
    end)

    it("lets a mode brightness of zero turn the frontlight off", function()
        local screen = make_screen()
        local powerd = {
            fl_min = 0,
            fl_max = 100,
            is_on = true,
            turnOffFrontlight = function(self)
                self.is_on = false
                self.off_calls = (self.off_calls or 0) + 1
            end,
            setIntensity = function(self, value) self.value = value end,
            isFrontlightOff = function(self) return not self.is_on end,
            turnOnFrontlight = function(self) self.is_on = true end,
            updateResumeFrontlightState = function() end,
        }
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { brightness_schedule = false },
                brightness_schedule = {
                    use_mode_values = true,
                    day_value = 0,
                    night_value = 5,
                },
            },
        }
        ZenSpec.replace("device", { screen = screen, powerd = powerd })
        ZenSpec.replace("ui/uimanager", make_ui_manager())

        require("modules/global/patches/brightness_schedule")()
        assert.are.equal(1, powerd.off_calls)
        assert.is_false(powerd.is_on)

        screen:toggleNightMode()
        assert.are.equal(5, powerd.value)
        assert.is_true(powerd.is_on)
    end)

    it("keeps time-based brightness authoritative when its schedule is on", function()
        local screen = make_screen()
        local now = os.date("*t")
        local night = (now.hour * 60 + now.min + 1) % 1440
        local powerd = {
            fl_min = 0,
            fl_max = 100,
            is_on = true,
            values = {},
            setIntensity = function(self, value)
                self.values[#self.values + 1] = value
            end,
            isFrontlightOff = function(self) return not self.is_on end,
            updateResumeFrontlightState = function() end,
        }
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { brightness_schedule = true },
                brightness_schedule = {
                    day_h = now.hour,
                    day_m = now.min,
                    day_value = 31,
                    night_h = math.floor(night / 60),
                    night_m = night % 60,
                    night_value = 9,
                    use_mode_values = true,
                },
            },
        }
        ZenSpec.replace("device", { screen = screen, powerd = powerd })
        ZenSpec.replace("ui/uimanager", make_ui_manager())

        require("modules/global/patches/brightness_schedule")()
        assert.are.same({ 31 }, powerd.values)

        screen:toggleNightMode()
        assert.are.same({ 31 }, powerd.values)
    end)

    it("applies warmth on mode changes while the time schedule is off", function()
        local screen = make_screen()
        local powerd = {
            fl_warmth_min = 0,
            fl_warmth_max = 24,
            values = {},
            fromNativeWarmth = function(_, value) return value * 10 end,
            setWarmth = function(self, value)
                self.values[#self.values + 1] = value
            end,
        }
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { warmth_schedule = false },
                warmth_schedule = {
                    use_mode_values = true,
                    day_value = 3,
                    night_value = 8,
                },
            },
        }
        ZenSpec.replace("device", { screen = screen, powerd = powerd })
        ZenSpec.replace("ui/uimanager", make_ui_manager())

        require("modules/global/patches/warmth_schedule")()
        assert.are.same({ 30 }, powerd.values)

        screen:toggleNightMode()
        assert.are.same({ 30, 80 }, powerd.values)
    end)

    it("does nothing when both automatic brightness modes are disabled", function()
        local screen = make_screen()
        local powerd = {
            fl_min = 0,
            fl_max = 100,
            setIntensity = function(self)
                self.calls = (self.calls or 0) + 1
            end,
        }
        _G.__ZEN_UI_PLUGIN = {
            config = {
                features = { brightness_schedule = false },
                brightness_schedule = { use_mode_values = false },
            },
        }
        ZenSpec.replace("device", { screen = screen, powerd = powerd })
        ZenSpec.replace("ui/uimanager", make_ui_manager())

        require("modules/global/patches/brightness_schedule")()
        screen:toggleNightMode()
        assert.is_nil(powerd.calls)
    end)
end)

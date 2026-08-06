describe("Double-tap book opening", function()
    local now
    local config
    local saved_modules

    before_each(function()
        saved_modules = {
            time = package.loaded["ui/time"],
            gesture_detector = package.loaded["device/gesturedetector"],
            config_manager = package.loaded["config/manager"],
        }
        now = 0
        config = { developer = { double_tap_to_open_books = true } }
        ZenSpec.replace("ui/time", {
            now = function() return now end,
            ms = function(value) return value / 1000 end,
        })
        ZenSpec.replace("device/gesturedetector", {
            ges_double_tap_interval = 0.3,
        })
        ZenSpec.replace("config/manager", {
            get = function() return config end,
        })
        ZenSpec.unload("common/book_open_tap")
    end)

    after_each(function()
        ZenSpec.unload("common/book_open_tap")
        package.loaded["ui/time"] = saved_modules.time
        package.loaded["device/gesturedetector"] = saved_modules.gesture_detector
        package.loaded["config/manager"] = saved_modules.config_manager
    end)

    it("opens only after two rapid taps on the same book", function()
        local BookOpenTap = require("common/book_open_tap")

        assert.is_false(BookOpenTap.willOpen("/books/one.epub", 0))
        assert.is_false(BookOpenTap.shouldOpen("/books/one.epub"))
        assert.is_true(BookOpenTap.willOpen("/books/one.epub", 0.2))
        now = 0.2
        assert.is_true(BookOpenTap.shouldOpen("/books/one.epub"))
        assert.is_false(BookOpenTap.willOpen("/books/one.epub", 0.25))
        now = 0.25
        assert.is_false(BookOpenTap.shouldOpen("/books/one.epub"))
    end)

    it("rejects late and mismatched second taps", function()
        local BookOpenTap = require("common/book_open_tap")

        assert.is_false(BookOpenTap.shouldOpen("/books/one.epub"))
        now = 0.3
        assert.is_false(BookOpenTap.shouldOpen("/books/one.epub"))
        now = 0.4
        assert.is_false(BookOpenTap.shouldOpen("/books/two.epub"))
        now = 0.5
        assert.is_true(BookOpenTap.shouldOpen("/books/two.epub"))
    end)

    it("keeps single-tap opening when disabled", function()
        local BookOpenTap = require("common/book_open_tap")
        config.developer.double_tap_to_open_books = false

        assert.is_true(BookOpenTap.willOpen("/books/one.epub"))
        assert.is_true(BookOpenTap.shouldOpen("/books/one.epub"))
    end)
end)

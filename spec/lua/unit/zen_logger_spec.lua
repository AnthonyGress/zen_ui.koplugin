describe("Zen logger branding", function()
    local original_backend
    local captured

    before_each(function()
        package.loaded["common/zen_logger"] = nil
        original_backend = package.loaded.logger
        local backend = {}
        for _i, level in ipairs({ "dbg", "info", "warn", "err" }) do
            backend[level] = function(...)
                captured = { ... }
            end
        end
        package.loaded.logger = backend
    end)

    after_each(function()
        package.loaded["common/zen_logger"] = nil
        package.loaded.logger = original_backend
    end)

    it("uses ZenOS and strips current and legacy product prefixes", function()
        local logger = require("common/zen_logger").new("test")

        logger.info("Zen UI: legacy message")
        assert.are.equal("ZenOS: [zen_logger_spec] legacy message", captured[1])

        logger.info("ZenOS: current message")
        assert.are.equal("ZenOS: [zen_logger_spec] current message", captured[1])
    end)
end)

describe("Rakuyomi availability", function()
    local original_filemanager

    before_each(function()
        original_filemanager = package.loaded["apps/filemanager/filemanager"]
        ZenSpec.unload("common/rakuyomi")
    end)

    after_each(function()
        package.loaded["apps/filemanager/filemanager"] = original_filemanager
        ZenSpec.unload("common/rakuyomi")
    end)

    it("exports the availability API used by Zen UI initialization", function()
        package.loaded["apps/filemanager/filemanager"] = {
            instance = { rakuyomi = {} },
        }

        local Rakuyomi = require("common/rakuyomi")

        assert.is_table(Rakuyomi)
        assert.is_function(Rakuyomi.is_available)
        assert.is_true(Rakuyomi.is_available())
    end)
end)

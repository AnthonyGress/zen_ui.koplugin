describe("modal border", function()
    local ModalBorder
    local original_settings

    before_each(function()
        original_settings = G_reader_settings
        _G.G_reader_settings = {
            nilOrTrue = function() return true end,
        }
        ZenSpec.unload("common/ui/modal_border")
        ModalBorder = require("common/ui/modal_border")
    end)

    after_each(function()
        _G.G_reader_settings = original_settings
    end)

    it("disables UI antialiasing only while painting a modal", function()
        local inner_anti_alias
        local frame = {
            paintTo = function()
                inner_anti_alias = G_reader_settings:nilOrTrue("anti_alias_ui")
            end,
        }

        ModalBorder.apply(frame)
        frame:paintTo()

        assert.is_false(inner_anti_alias)
        assert.is_true(G_reader_settings:nilOrTrue("anti_alias_ui"))
    end)

    it("restores the normal setting when modal painting fails", function()
        local frame = {
            paintTo = function()
                assert.is_false(G_reader_settings:nilOrTrue("anti_alias_ui"))
                error("paint failure")
            end,
        }

        ModalBorder.apply(frame)

        assert.has_error(function() frame:paintTo() end, "paint failure")
        assert.is_true(G_reader_settings:nilOrTrue("anti_alias_ui"))
    end)
end)

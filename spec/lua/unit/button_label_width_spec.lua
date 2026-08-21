describe("button label width", function()
    local ButtonLabelWidth

    before_each(function()
        ZenSpec.unload("common/ui/button_label_width")
        ButtonLabelWidth = require("common/ui/button_label_width")
    end)

    it("uses equal cells for a row while preserving all available label width", function()
        local cell_width = ButtonLabelWidth.equalCellWidth(775, 6)

        assert.are.equal(129, cell_width)
        assert.are.equal(121, ButtonLabelWidth.maxWidth(cell_width, 4))
    end)

    it("keeps a usable label width when the available space is too small", function()
        assert.are.equal(1, ButtonLabelWidth.equalCellWidth(0, 0))
        assert.are.equal(1, ButtonLabelWidth.maxWidth(0, 4))
    end)

end)

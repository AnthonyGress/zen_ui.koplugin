describe("Reader margins", function()
    it("applies the same Reader defaults used by Quickstart", function()
        local settings = ZenSpec.memorySettings()

        require("common/reader_margins").applyZenDefaults(settings)

        assert.are.same({30, 30}, settings:readSetting("copt_h_page_margins"))
        assert.are.equal(1, settings:readSetting("copt_sync_t_b_page_margins"))
        assert.are.equal(30, settings:readSetting("copt_t_page_margin"))
        assert.are.equal(30, settings:readSetting("copt_b_page_margin"))
    end)
end)

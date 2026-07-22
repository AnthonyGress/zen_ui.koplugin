describe("top menu swipe suppression", function()
    local ReaderMenu
    local FileManagerMenu

    before_each(function()
        ReaderMenu = {
            _getTabIndexFromLocation = function() return "reader-original" end,
        }
        FileManagerMenu = {
            _getTabIndexFromLocation = function() return "filemanager-original" end,
        }
        ZenSpec.replace("apps/reader/modules/readermenu", ReaderMenu)
        ZenSpec.replace("apps/filemanager/filemanagermenu", FileManagerMenu)
        ZenSpec.unload("modules/menu/patches/disable_top_menu_swipe_zones")
    end)

    it("keeps both menus on their current tab regardless of gesture", function()
        require("modules/menu/patches/disable_top_menu_swipe_zones")()

        assert.are.equal(3, ReaderMenu._getTabIndexFromLocation({ last_tab_index = 3 }, {}))
        assert.are.equal(5, FileManagerMenu._getTabIndexFromLocation({ last_tab_index = 5 }, {}))
    end)
end)

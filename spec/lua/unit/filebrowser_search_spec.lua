describe("file browser search", function()
    local dialog

    before_each(function()
        dialog = nil
        _G.__ZEN_UI_PLUGIN = { config = { features = { search = true } } }

        local FileManagerFileSearcher = {
            onShowFileSearch = function() end,
            isFileMatch = function() end,
            updateItemTable = function() end,
            onMenuHold = function() end,
            onShowSearchResults = function() end,
        }
        ZenSpec.replace("apps/filemanager/filemanagerfilesearcher", FileManagerFileSearcher)
        ZenSpec.replace("ui/widget/inputdialog", {
            onTap = function() end,
            new = function(_, spec)
                dialog = spec
                dialog.onShowKeyboard = function() end
                return dialog
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            close = function() end,
            show = function() end,
        })
        ZenSpec.replace("common/paths", { getHomeDir = function() return "/library" end })
        ZenSpec.replace("common/utils", {
            resolveLocalIcon = function(dir, name) return dir .. name .. ".svg" end,
        })
        ZenSpec.replace("common/plugin_root", "/zen-ui")
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("util", { stringLower = string.lower })
        ZenSpec.replace("document/documentregistry", { hasProvider = function() return false end })

        ZenSpec.unload("modules/filebrowser/patches/search")
        require("modules/filebrowser/patches/search")()
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
        ZenSpec.unload("modules/filebrowser/patches/search")
    end)

    it("resolves the modal close icon to the bundled SVG", function()
        local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
        FileManagerFileSearcher:onShowFileSearch()

        assert.are.equal("/zen-ui/icons/close.svg", dialog.title_bar_left_icon)
    end)
end)

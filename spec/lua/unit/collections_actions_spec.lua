describe("ZenOS collection actions", function()
    local FileManagerCollection
    local collection_manager
    local file_dialog_args
    local renamed
    local removed
    local saved_modules
    local replaced_modules = {
        "gettext",
        "common/zen_logger",
        "common/inline_icon_map",
        "common/cover_utils",
        "modules/filebrowser/patches/library_font",
        "common/ui/background",
        "common/shared_state",
        "common/tbr_index",
        "readcollection",
        "apps/filemanager/filemanagercollection",
        "apps/filemanager/filemanager",
        "ui/widget/menu",
        "ui/widget/buttondialog",
        "ui/uimanager",
        "device",
    }

    local function install_collections_patch()
        file_dialog_args = nil
        renamed = {}
        removed = {}

        FileManagerCollection = {
            onShowColl = function() end,
            onShowCollList = function(self)
                self.coll_list = {}
            end,
            updateCollListItemTable = function() end,
            renameCollection = function(_self, item)
                renamed[#renamed + 1] = item.name
            end,
            removeCollection = function(_self, item)
                removed[#removed + 1] = item.name
            end,
        }
        collection_manager = setmetatable({}, { __index = FileManagerCollection })

        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("common/zen_logger", {
            new = function()
                return { dbg = function() end }
            end,
        })
        ZenSpec.replace("common/inline_icon_map", {
            rename = "rename",
            delete = "delete",
        })
        ZenSpec.replace("common/cover_utils", {})
        ZenSpec.replace("modules/filebrowser/patches/library_font", {
            scaleValue = function(value) return value end,
            getFontName = function() return "sans" end,
        })
        ZenSpec.replace("common/ui/background", { applyToMenu = function() end })
        ZenSpec.replace("common/shared_state", {
            get = function() end,
            register = function() end,
        })
        ZenSpec.replace("common/tbr_index", {
            collectionName = function() return "To Be Read" end,
        })
        ZenSpec.replace("readcollection", {
            default_collection_name = "favorites",
            coll = {
                favorites = {},
                ["To Be Read"] = {},
                Reading = {},
            },
            coll_settings = {
                favorites = {},
                ["To Be Read"] = {},
                Reading = {},
            },
        })
        ZenSpec.replace("apps/filemanager/filemanagercollection", FileManagerCollection)
        ZenSpec.replace("apps/filemanager/filemanager", {
            instance = {
                collections = collection_manager,
                file_chooser = {
                    showFileDialog = function(_self, args)
                        file_dialog_args = args
                    end,
                },
            },
        })
        ZenSpec.replace("ui/widget/menu", { init = function() end })
        ZenSpec.replace("ui/widget/buttondialog", {
            new = function(_self, spec) return spec end,
        })
        ZenSpec.replace("ui/uimanager", {
            close = function() end,
            setDirty = function() end,
        })
        ZenSpec.replace("device", { isTouchDevice = function() return false end })

        _G.__ZEN_UI_PLUGIN = { config = { features = { collections = true } } }
        ZenSpec.unload("modules/filebrowser/patches/collections")
        require("modules/filebrowser/patches/collections")()
        collection_manager:onShowCollList()
    end

    before_each(function()
        saved_modules = {}
        for _i, name in ipairs(replaced_modules) do
            saved_modules[name] = package.loaded[name] or false
        end
        install_collections_patch()
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
        ZenSpec.unload("modules/filebrowser/patches/collections")
        for _i, name in ipairs(replaced_modules) do
            package.loaded[name] = saved_modules[name] or nil
        end
    end)

    it("omits rename and delete actions for To Be Read", function()
        assert.is_true(collection_manager.coll_list:onMenuHold({ name = "To Be Read" }))
        assert.are.same({}, file_dialog_args._zen_prepend_buttons)
        assert.are.equal(1, #file_dialog_args._zen_extra_buttons)
        assert.is_truthy(file_dialog_args._zen_extra_buttons[1][1].text:find(
            "Connect folders", 1, true))
    end)

    it("retains rename and delete actions for ordinary collections", function()
        assert.is_true(collection_manager.coll_list:onMenuHold({ name = "Reading" }))
        assert.are.equal(1, #file_dialog_args._zen_prepend_buttons)
        assert.are.equal(2, #file_dialog_args._zen_extra_buttons)
        assert.is_truthy(file_dialog_args._zen_prepend_buttons[1][1].text:find(
            "Rename", 1, true))
        assert.is_truthy(file_dialog_args._zen_extra_buttons[2][1].text:find(
            "Delete collection", 1, true))
    end)

    it("rejects direct rename and delete calls for To Be Read", function()
        collection_manager:renameCollection({ name = "To Be Read" })
        collection_manager:removeCollection({ name = "To Be Read" })
        collection_manager:renameCollection({ name = "Reading" })
        collection_manager:removeCollection({ name = "Reading" })

        assert.are.same({ "Reading" }, renamed)
        assert.are.same({ "Reading" }, removed)
    end)
end)

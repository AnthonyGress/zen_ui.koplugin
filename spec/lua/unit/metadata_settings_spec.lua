describe("metadata settings", function()
    local Settings
    local saved = {}
    local ui_manager
    local token
    local token_error

    before_each(function()
        for _i, name in ipairs({
            "device", "ui/uimanager", "common/inline_icon_map",
            "common/ui/icon_menu_item", "config/hardcover_token", "gettext",
            "ui/widget/confirmbox", "ui/widget/infomessage", "ui/widget/inputdialog",
            "modules/settings/sections/library_settings/metadata_settings",
        }) do
            saved[name] = package.loaded[name] or false
        end
        ZenSpec.replace("device", {
            screen = { getWidth = function() return 600 end, getHeight = function() return 800 end },
            openLink = function() end,
        })
        ui_manager = {}
        token = ""
        token_error = nil
        ZenSpec.replace("ui/uimanager", ui_manager)
        ZenSpec.replace("common/inline_icon_map", { edit = "edit" })
        ZenSpec.replace("common/ui/icon_menu_item", {
            decorate = function(item) return item end,
        })
        ZenSpec.replace("config/hardcover_token", {
            clean = function(value)
                value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
                if value == "" or value:find("%s") then return nil end
                return value
            end,
            get = function() return token end,
            save = function(value)
                if token_error then return nil, token_error end
                token = value
                return true
            end,
            clear = function()
                if token_error then return nil, token_error end
                token = ""
                return true
            end,
        })
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.unload("modules/settings/sections/library_settings/metadata_settings")
        Settings = require("modules/settings/sections/library_settings/metadata_settings")
    end)

    after_each(function()
        for name, module in pairs(saved) do package.loaded[name] = module or nil end
        saved = {}
    end)

    it("validates and masks Hardcover tokens", function()
        assert.same("hc_pat_token", Settings.cleanToken("  hc_pat_token  "))
        assert.is_nil(Settings.cleanToken("bad token"))
        assert.is_nil(Settings.cleanToken(""))
        assert.same("••••oken", Settings.maskedToken("hc_pat_token"))
        assert.same("••••", Settings.maskedToken("abc"))
    end)

    it("clears the dedicated token file", function()
        local confirm
        token = "secret"
        ZenSpec.replace("ui/widget/confirmbox", {
            new = function(_self, options) return options end,
        })
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_self, options) return options end,
        })
        ui_manager.show = function(_self, widget) confirm = widget end
        local menu = Settings.build{}

        menu.sub_item_table[4].callback()
        confirm.ok_callback()

        assert.are.equal("", token)
        assert.is_false(menu.sub_item_table[4].enabled_func())
    end)

    it("keeps the token dialog open when verified persistence fails", function()
        local shown = {}
        local closed = 0
        token = "original"
        token_error = "disk full"
        ZenSpec.replace("ui/widget/inputdialog", {
            new = function(_self, options)
                options.getInputText = function() return "replacement" end
                options.onShowKeyboard = function() end
                return options
            end,
        })
        ZenSpec.replace("ui/widget/infomessage", {
            new = function(_self, options) return options end,
        })
        ui_manager.show = function(_self, widget) shown[#shown + 1] = widget end
        ui_manager.close = function() closed = closed + 1 end
        local menu = Settings.build{}

        menu.sub_item_table[3].callback()
        shown[1].buttons[1][2].callback()

        assert.are.equal("original", token)
        assert.are.equal(0, closed)
        assert.are.equal("Metadata could not be saved.", shown[2].text)
    end)

    it("saves match-selection and backup preferences", function()
        local config = { metadata = {} }
        local save_count = 0
        local menu = Settings.build{
            config = config,
            plugin = { saveConfig = function() save_count = save_count + 1 end },
        }

        assert.is_true(menu.sub_item_table[1].sub_item_table[1].checked_func())
        assert.is_false(menu.sub_item_table[2].checked_func())
        menu.sub_item_table[1].sub_item_table[2].callback()
        menu.sub_item_table[2].callback()

        assert.is_false(config.metadata.hardcover_auto_match)
        assert.is_true(config.metadata.epub_backup)
        assert.are.equal(2, save_count)
    end)
end)

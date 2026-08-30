local UIManager = require("ui/uimanager")
local icons = require("common/inline_icon_map")
local IconItem = require("common/ui/icon_menu_item")
local TokenStore = require("config/hardcover_token")
local _ = require("gettext")

local M = {}
local TOKEN_URL = "https://hardcover.app/account/api"

local function masked_token(token)
    if token == "" then return _("Not set") end
    if #token <= 4 then return "••••" end
    return "••••" .. token:sub(-4)
end

function M.build(ctx)
    local config = ctx.config or {}
    local plugin = ctx.plugin
    if type(config.metadata) ~= "table" then config.metadata = {} end
    local metadata = config.metadata

    local function save(touchmenu_instance)
        if plugin then plugin:saveConfig() end
        if touchmenu_instance then touchmenu_instance:updateItems() end
    end

    local function edit_token(touchmenu_instance)
        local InputDialog = require("ui/widget/inputdialog")
        local dlg
        dlg = InputDialog:new{
            title = _("Hardcover API token"),
            description = _("Use a token limited to read:catalog. It is stored locally as plain text and is never logged."),
            input = TokenStore.get(),
            text_type = "password",
            buttons = {{
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dlg) end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local token = TokenStore.clean(dlg:getInputText())
                        if not token then
                            UIManager:show(require("ui/widget/infomessage"):new{
                                text = _("Enter a valid Hardcover token without spaces."),
                            })
                            return
                        end
                        if not TokenStore.save(token) then
                            UIManager:show(require("ui/widget/infomessage"):new{
                                text = _("Metadata could not be saved."),
                            })
                            return
                        end
                        UIManager:close(dlg)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                },
            }},
        }
        UIManager:show(dlg)
        dlg:onShowKeyboard()
    end

    local item = {
        text = _("Metadata"),
        _zen_metadata_settings = true,
        sub_item_table = {
            {
                text = _("Hardcover match selection"),
                sub_item_table = {
                    {
                        text = _("Auto-pick best match"),
                        radio = true,
                        checked_func = function()
                            return metadata.hardcover_auto_match ~= false
                        end,
                        callback = function(touchmenu_instance)
                            metadata.hardcover_auto_match = true
                            save(touchmenu_instance)
                        end,
                    },
                    {
                        text = _("Choose match manually"),
                        radio = true,
                        checked_func = function()
                            return metadata.hardcover_auto_match == false
                        end,
                        callback = function(touchmenu_instance)
                            metadata.hardcover_auto_match = false
                            save(touchmenu_instance)
                        end,
                    },
                },
            },
            {
                text = _("Keep an EPUB metadata backup"),
                checked_func = function() return metadata.epub_backup == true end,
                callback = function(touchmenu_instance)
                    metadata.epub_backup = metadata.epub_backup ~= true
                    save(touchmenu_instance)
                end,
            },
            {
                text_func = function()
                    return _("Hardcover API token:") .. " "
                        .. masked_token(TokenStore.get())
                end,
                keep_menu_open = true,
                callback = edit_token,
            },
            {
                text = _("Clear Hardcover token"),
                enabled_func = function()
                    return TokenStore.get() ~= ""
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    local ConfirmBox = require("ui/widget/confirmbox")
                    UIManager:show(ConfirmBox:new{
                        text = _("Clear the saved Hardcover API token?"),
                        ok_text = _("Clear"),
                        ok_callback = function()
                            local saved = TokenStore.clear()
                            if not saved then
                                UIManager:show(require("ui/widget/infomessage"):new{
                                    text = _("The Hardcover token could not be cleared."),
                                })
                            end
                            if touchmenu_instance then touchmenu_instance:updateItems() end
                        end,
                    })
                end,
            },
            {
                text = _("Show Hardcover token-page QR code"),
                callback = function()
                    local Device = require("device")
                    local QRMessage = require("ui/widget/qrmessage")
                    UIManager:show(QRMessage:new{
                        text = TOKEN_URL,
                        width = Device.screen:getWidth(),
                        height = Device.screen:getHeight(),
                    })
                end,
            },
            {
                text = _("Open Hardcover token page"),
                callback = function() require("device"):openLink(TOKEN_URL) end,
            },
        },
    }
    return IconItem.decorate(item, icons.edit)
end

M.cleanToken = TokenStore.clean
M.maskedToken = masked_token

return M

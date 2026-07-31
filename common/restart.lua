local _ = require("gettext")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")

local M = {}

function M.request()
    UIManager:show(InfoMessage:new{
        text = _("Restarting") .. "...",
    })
    UIManager:tickAfterNext(function()
        UIManager:broadcastEvent(Event:new("Restart"))
    end)
end

return M

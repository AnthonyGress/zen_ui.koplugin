local _ = require("gettext")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local InfoMessage = require("ui/widget/infomessage")

local M = {}

function M.request(opts)
    opts = opts or {}
    if opts.show_notice ~= false then
        UIManager:show(InfoMessage:new{
            text = _("Restarting") .. "...",
        })
    end
    UIManager:tickAfterNext(function()
        UIManager:broadcastEvent(Event:new("Restart"))
    end)
end

return M

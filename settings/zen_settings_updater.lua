local _ = require("gettext")

local M = {}

function M.run_update(plugin)
    local UIManager = require("ui/uimanager")
    local ConfirmBox = require("ui/widget/confirmbox")
    local InfoMessage = require("ui/widget/infomessage")
    local Event = require("ui/event")
    local lfs = require("libs/libkoreader-lfs")

    UIManager:show(ConfirmBox:new{
        text = _("Run Zen UI update now?\n\nIf this plugin is a git checkout, Zen UI will run a fast-forward pull and then ask for restart."),
        ok_text = _("Update"),
        ok_callback = function()
            local plugin_path = plugin.path or ""
            local git_dir = plugin_path ~= "" and (plugin_path .. "/.git") or nil
            if not git_dir or lfs.attributes(git_dir, "mode") ~= "directory" then
                UIManager:show(InfoMessage:new{
                    text = _("No git checkout detected for Zen UI. Use your normal plugin installation/update workflow."),
                })
                return
            end

            local command = string.format("git -C %q pull --ff-only", plugin_path)
            local ok = os.execute(command)
            if ok == true or ok == 0 then
                UIManager:show(ConfirmBox:new{
                    text = _("Zen UI update completed. Restart KOReader now?"),
                    ok_text = _("Restart"),
                    ok_callback = function()
                        UIManager:broadcastEvent(Event:new("Restart"))
                    end,
                })
            else
                UIManager:show(InfoMessage:new{
                    text = _("Zen UI update failed. Check logs and retry."),
                })
            end
        end,
    })
end

function M.build_update_now_item(plugin)
    return {
        text = _("Update Zen UI"),
        callback = function()
            M.run_update(plugin)
        end,
    }
end

return M

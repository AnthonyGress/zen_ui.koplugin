local _ = require("gettext")

local M = {}

function M.folderLabel(path)
    if type(path) ~= "string" or path == "" then return _("Folder") end
    if path == "/" then return path end
    return path:match("([^/]+)/?$") or path
end

function M.chooseFolder(on_select, opts)
    if type(on_select) ~= "function" then return false end
    opts = type(opts) == "table" and opts or {}
    local paths = require("common/paths")
    local start_path = type(opts.path) == "string" and opts.path ~= "" and opts.path
        or paths.getHomeDir() or G_reader_settings:readSetting("lastdir") or "/"
    require("ui/uimanager"):show(require("ui/widget/pathchooser"):new{
        select_directory = true,
        select_file = false,
        show_files = false,
        path = start_path,
        onConfirm = function(path)
            local lfs = require("libs/libkoreader-lfs")
            if type(path) == "string" and lfs.attributes(path, "mode") == "directory" then
                on_select(path)
            end
        end,
    })
    return true
end

function M.chooseTag(on_select, opts)
    if type(on_select) ~= "function" then return false end
    opts = type(opts) == "table" and opts or {}
    local ok_db, db = pcall(require, "common/db_bookinfo")
    local groups = ok_db and db and type(db.getGroupedByTags) == "function"
        and db.getGroupedByTags() or {}
    if #groups == 0 then
        require("ui/uimanager"):show(require("ui/widget/infomessage"):new{
            text = _("No tags found"),
        })
        return false
    end
    local items = {}
    for _i, group in ipairs(groups) do
        if type(group.tag) == "string" and group.tag ~= "" then
            items[#items + 1] = { text = group.tag, tag = group.tag }
        end
    end
    require("common/ui/zen_menu_picker"){
        title = _("Choose tag"),
        items = items,
        back_hold_callback = opts.back_hold_callback,
        on_select = function(item)
            if item and item.tag then on_select(item.tag) end
        end,
    }
    return true
end

return M

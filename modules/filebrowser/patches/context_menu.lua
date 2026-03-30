local function apply_context_menu()
    --[[
        Replaces the long-hold file/folder context menu in the file browser with
        a clean, minimal layout:

            New folder
            Move          (opens PathChooser to pick destination, then moves immediately)
            Add/Remove from favorites
            Book status ▶ (files only: Reading · On hold · Finished · Unread)
            Edit ▶        (anchored submenu at right edge: Select · Rename · Delete · Cut · Copy · Paste)

        Everything else (book info, collections, open with, reset, status rows,
        scripts, converter, shortcuts, etc.) is intentionally hidden.
        No feature toggle – always active.
    ]]

    local BD           = require("ui/bidi")
    local ButtonDialog = require("ui/widget/buttondialog")
    local Device       = require("device")
    local FileChooser  = require("ui/widget/filechooser")
    local FileManager  = require("apps/filemanager/filemanager")
    local PathChooser  = require("ui/widget/pathchooser")
    local UIManager    = require("ui/uimanager")
    local _            = require("gettext")
    local C_           = _.pgettext

    -- ── MoveChooser ──────────────────────────────────────────────────────────
    -- PathChooser subclass for picking a move destination.
    --   • Cover-browser rendering applies automatically when the coverbrowser
    --     plugin is active (it hooks MosaicMenuItem.update on FileChooser items).
    --   • genItemTable strips hidden folders (.sdr, .thumbnails, etc.) and the
    --     go-up row — the list is intentionally flat.
    --   • onMenuSelect fires immediately on single tap (no navigate-into behaviour).
    local _orig_fc_genItemTable = FileChooser.genItemTable
    local MoveChooser = PathChooser:extend{}

    function MoveChooser:genItemTable(dirs, files, path)
        local ffiUtil3 = require("ffi/util")
        local items = _orig_fc_genItemTable(self, dirs, files, path)
        local filtered = {}
        for _, item in ipairs(items) do
            -- drop the ".." go-up row
            if item.is_go_up then goto continue end
            -- drop PathChooser's "Long-press to choose current folder" hint row
            -- (its path ends in "/." regardless of translated text)
            if item.path and item.path:sub(-2) == "/." then goto continue end
            -- drop hidden entries (.sdr, .thumbnails, etc.)
            local fname = item.text or ""
            if fname:sub(1, 1) == "." then goto continue end
            table.insert(filtered, item)
            ::continue::
        end
        -- Prepend a Home item so the user can move directly into home_dir.
        -- Skip it when the item being moved is already a direct child of home_dir
        -- (moving it there would be a no-op).
        local real_path = ffiUtil3.realpath(path)
        if not self.src_dir or self.src_dir ~= real_path then
            table.insert(filtered, 1, {
                text           = ffiUtil3.basename(path),
                path           = path,
                is_file        = false,
                bidi_wrap_func = BD.directory,
                mandatory      = self:getMenuItemMandatory({ path = path }),
            })
        end
        return filtered
    end

    function MoveChooser:onMenuSelect(item)
        local path = item and item.path
        if not path then return true end
        local ffiUtil2 = require("ffi/util")
        local real = ffiUtil2.realpath(path)
        if not real then return true end
        local lfs2 = require("libs/libkoreader-lfs")
        if lfs2.attributes(real, "mode") == "directory" then
            if self.onConfirm then self.onConfirm(real) end
            UIManager:close(self)
        end
        return true
    end

    function MoveChooser:onMenuHold() return true end
    -- ─────────────────────────────────────────────────────────────────────────

    local orig_setupLayout = FileManager.setupLayout

    FileManager.setupLayout = function(self)
        orig_setupLayout(self)

        local file_chooser = self.file_chooser
        local file_manager = self

        -- Replace the instance-level showFileDialog defined by setupLayout
        file_chooser.showFileDialog = function(self_fc, item)
            local file               = item.path
            local is_file            = item.is_file
            local is_not_parent_folder = not item.is_go_up

            local function close_dialog()
                UIManager:close(self_fc.file_dialog)
            end

            local function refresh()
                self_fc:refreshPath()
            end

            -- ── Edit submenu ──────────────────────────────────────────────────────────
            local function showEditSubmenu()
                close_dialog()
                local edit_dialog

                local edit_buttons = {
                    {
                        {
                            text     = _("Select"),
                            align    = "left",
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:onToggleSelectMode()
                                if is_file then
                                    file_manager.selected_files[file] = true
                                    item.dim = true
                                    self_fc:updateItems(1, true)
                                end
                            end,
                        },
                    },
                    {
                        {
                            text     = _("Delete"),
                            align    = "left",
                            enabled  = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:showDeleteFileDialog(file, refresh)
                            end,
                        },
                    },
                    {
                        {
                            text     = _("Cut"),
                            align    = "left",
                            enabled  = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:cutFile(file)
                            end,
                        },
                    },
                    {
                        {
                            text     = C_("File", "Copy"),
                            align    = "left",
                            enabled  = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:copyFile(file)
                            end,
                        },
                    },
                    {
                        {
                            text     = C_("File", "Paste"),
                            align    = "left",
                            enabled  = file_manager.clipboard and true or false,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:pasteFileFromClipboard(file)
                            end,
                        },
                    },
                }

                edit_dialog = ButtonDialog:new{
                    buttons = edit_buttons,
                }
                UIManager:show(edit_dialog)
            end

            -- ── Main dialog ───────────────────────────────────────────────────
            local buttons = {}

            if is_not_parent_folder then
                table.insert(buttons, {
                    {
                        text     = _("Rename"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            file_manager:showRenameFileDialog(file, is_file)
                        end,
                    },
                })
            end

            table.insert(buttons, {
                {
                    text     = _("New folder"),
                    align    = "left",
                    callback = function()
                        close_dialog()
                        file_manager:createFolder()
                    end,
                },
            })

            if is_file and is_not_parent_folder then
                -- Move: open a folder picker then immediately execute the move
                table.insert(buttons, {
                    {
                        text     = _("Move"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            local ffiUtil        = require("ffi/util")
                            local DocSettings    = require("docsettings")
                            local ReadHistory    = require("readhistory")
                            local ReadCollection = require("readcollection")
                            local lfs            = require("libs/libkoreader-lfs")
                            local src            = ffiUtil.realpath(file)
                            if not src then return end
                            local home_dir = (G_reader_settings and G_reader_settings:readSetting("home_dir"))
                                or file_chooser.path
                            if not home_dir then return end
                            local src_dir = ffiUtil.realpath(ffiUtil.dirname(src))
                            local chooser = MoveChooser:new{
                                select_directory = true,
                                select_file      = false,
                                show_files       = false,
                                title            = _("Move to…"),
                                path             = home_dir,
                                src_dir          = src_dir,
                                onConfirm        = function(dest_dir_real)
                                    local name      = ffiUtil.basename(src)
                                    local dest_file = ffiUtil.joinPath(dest_dir_real, name)
                                    if lfs.attributes(dest_file) then
                                        local InfoMessage = require("ui/widget/infomessage")
                                        UIManager:show(InfoMessage:new{
                                            text = _("An item with that name already exists."),
                                            icon = "notice-warning",
                                        })
                                        return
                                    end
                                    if file_manager:moveFile(src, dest_dir_real) then
                                        if is_file then
                                            DocSettings.updateLocation(src, dest_file)
                                            ReadHistory:updateItem(src, dest_file)
                                            ReadCollection:updateItem(src, dest_file)
                                        else
                                            ReadHistory:updateItemsByPath(src, dest_file)
                                            ReadCollection:updateItemsByPath(src, dest_file)
                                        end
                                        -- If the current directory is now empty and we're
                                        -- in a subfolder, navigate home to avoid a blank screen.
                                        local real_cur  = ffiUtil.realpath(file_chooser.path)
                                        local real_home = ffiUtil.realpath(home_dir)
                                        local at_home   = real_cur == real_home
                                        local n = 0
                                        if not at_home then
                                            local ok3, iter3, dir3 = pcall(lfs.dir, file_chooser.path)
                                            if ok3 then
                                                for f3 in iter3, dir3 do
                                                    if f3 ~= "." and f3 ~= ".." then n = n + 1 end
                                                end
                                            end
                                        end
                                        if not at_home and n == 0 then
                                            UIManager:nextTick(function()
                                                file_chooser:changeToPath(home_dir)
                                            end)
                                        else
                                            refresh()
                                        end
                                    else
                                        local InfoMessage = require("ui/widget/infomessage")
                                        UIManager:show(InfoMessage:new{
                                            text = _("Move failed."),
                                            icon = "notice-warning",
                                        })
                                    end
                                end,
                            }
                            UIManager:show(chooser)
                        end,
                    },
                })
            end

            if is_file then
                local ReadCollection = require("readcollection")
                local default_coll   = ReadCollection.default_collection_name
                local is_fav         = ReadCollection:isFileInCollection(file, default_coll)

                table.insert(buttons, {
                    {
                        text = is_fav and _("Remove from favorites") or _("Add to favorites"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            if is_fav then
                                ReadCollection:removeItem(file, default_coll)
                            else
                                ReadCollection:addItem(file, default_coll)
                            end
                            ReadCollection:write({ [default_coll] = true })
                        end,
                    },
                })
            end

            if is_file and is_not_parent_folder then
                -- Book status submenu
                table.insert(buttons, {
                    {
                        text     = _("Book status  ▶"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            local filemanagerutil = require("apps/filemanager/filemanagerutil")
                            local DocSettings     = require("docsettings")
                            local doc_settings    = DocSettings:open(file)
                            local status_dialog
                            local status_row = filemanagerutil.genStatusButtonsRow(
                                doc_settings,
                                function()
                                    UIManager:close(status_dialog)
                                    refresh()
                                end
                            )
                            status_dialog = ButtonDialog:new{
                                title        = BD.filename(file:match("([^/]+)$")),
                                title_align  = "center",
                                buttons      = { status_row },
                            }
                            UIManager:show(status_dialog)
                        end,
                    },
                })
            end

            table.insert(buttons, {
                {
                    text     = _("Edit  ▶"),
                    align    = "left",
                    callback = showEditSubmenu,
                },
            })

            self_fc.file_dialog = ButtonDialog:new{
                title       = is_file
                    and BD.filename(file:match("([^/]+)$"))
                    or  BD.directory(file:match("([^/]+)$")),
                title_align = "center",
                buttons     = buttons,
            }
            UIManager:show(self_fc.file_dialog)
            return true
        end
    end
end

return apply_context_menu

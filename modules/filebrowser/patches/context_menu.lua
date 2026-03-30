local function apply_context_menu()
    --[[
        Replaces the long-hold file/folder context menu in the file browser with
        a clean, minimal layout:

            New folder
            Move          (opens PathChooser to pick destination, then moves immediately)
            Add/Remove from favorites
            Book status ▶ (files only: Unread · Reading · On hold · Finished)
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
    local zen_plugin   = rawget(_G, "__ZEN_UI_PLUGIN")

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

            -- Build dialog header: cover left / text right (OverlapGroup) when a cover is
            -- available; text-only otherwise.  dialog_title is always set (used by the
            -- status sub-dialog and the text-only fallback).
            local dialog_title, dialog_cover_widget
            do
                local Screen   = Device.screen
                local SizeR    = require("ui/size")
                local border   = SizeR.border.thin
                local gap      = Screen:scaleBySize(8)
                local dlg_w    = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
                -- inner width available to _added_widgets inside ButtonDialog
                local avail_w  = dlg_w - 2 * (SizeR.border.window + SizeR.padding.button)
                                       - 2 * (SizeR.padding.default + SizeR.margin.default)
                local cover_max_w = Screen:scaleBySize(80)
                local cover_max_h = Screen:scaleBySize(120)

                -- Build an OverlapGroup with cover at left edge, text at right edge.
                local function makeSideBySide(cover_bb, src_w, src_h, sf, text_str)
                    local rendered_w  = math.floor(src_w * sf)
                    local rendered_h  = math.floor(src_h * sf)
                    local framed_h    = rendered_h + 2 * border
                    local text_col_w  = math.max(avail_w - rendered_w - 2 * border - gap,
                                                 Screen:scaleBySize(60))
                    local ImageWidget    = require("ui/widget/imagewidget")
                    local FrameContainer = require("ui/widget/container/framecontainer")
                    local OverlapGroup   = require("ui/widget/overlapgroup")
                    local LeftContainer  = require("ui/widget/container/leftcontainer")
                    local RightContainer = require("ui/widget/container/rightcontainer")
                    local TextBoxWidget  = require("ui/widget/textboxwidget")
                    local Font           = require("ui/font")
                    local Geom           = require("ui/geometry")
                    local row_dimen      = Geom:new{ w = avail_w, h = framed_h }
                    return OverlapGroup:new{
                        dimen         = row_dimen,
                        not_focusable = true,
                        LeftContainer:new{
                            dimen = row_dimen,
                            FrameContainer:new{
                                padding    = 0,
                                bordersize = border,
                                ImageWidget:new{
                                    image            = cover_bb,
                                    image_disposable = true,
                                    scale_factor     = sf,
                                },
                            },
                        },
                        RightContainer:new{
                            dimen = row_dimen,
                            TextBoxWidget:new{
                                text      = text_str,
                                face      = Font:getFace("infofont"),
                                width     = text_col_w,
                                alignment = "left",
                            },
                        },
                    }
                end

                if is_file then
                    local ok, BookInfoManager = pcall(require, "bookinfomanager")
                    local text_str
                    if ok then
                        local bookinfo = BookInfoManager:getBookInfo(file, true)
                        if bookinfo then
                            if not bookinfo.ignore_meta and bookinfo.title then
                                text_str = BD.auto(bookinfo.title)
                                if bookinfo.authors then
                                    text_str = text_str .. "\n" .. BD.auto(bookinfo.authors)
                                end
                            end
                            if bookinfo.cover_bb and bookinfo.has_cover
                                and not bookinfo.ignore_cover then
                                local _, _, sf = BookInfoManager.getCachedCoverSize(
                                    bookinfo.cover_w, bookinfo.cover_h,
                                    cover_max_w, cover_max_h)
                                dialog_cover_widget = makeSideBySide(
                                    bookinfo.cover_bb,
                                    bookinfo.cover_w, bookinfo.cover_h,
                                    sf,
                                    text_str or BD.filename(file:match("([^/]+)$")))
                            end
                        end
                    end
                    dialog_title = text_str or BD.filename(file:match("([^/]+)$"))
                else
                    -- folder
                    local name = (file:match("([^/]+)/?$") or file):gsub("/$", "")
                    local text_str = BD.directory(name)
                    local count = item.mandatory and tostring(item.mandatory):match("^%s*(%d+)")
                    if count then
                        local n = tonumber(count) or 0
                        text_str = text_str .. "\n"
                            .. (n == 1 and _("1 book") or (n .. " " .. _("books")))
                    end
                    dialog_title = text_str
                    -- Try to show cover of first book inside the folder.
                    local ok, BookInfoManager = pcall(require, "bookinfomanager")
                    if ok then
                        local lfs         = require("libs/libkoreader-lfs")
                        local DocRegistry = require("document/documentregistry")
                        local dir_files   = {}
                        local ok_dir, iter, dir_obj = pcall(lfs.dir, file)
                        if ok_dir then
                            for fname in iter, dir_obj do
                                if fname ~= "." and fname ~= ".." and not fname:match("^%.") then
                                    local fpath = file .. "/" .. fname
                                    if lfs.attributes(fpath, "mode") == "file"
                                        and DocRegistry:hasProvider(fpath) then
                                        table.insert(dir_files, fpath)
                                    end
                                end
                            end
                            if #dir_files > 0 then
                                table.sort(dir_files)
                                local bookinfo = BookInfoManager:getBookInfo(dir_files[1], true)
                                if bookinfo and bookinfo.has_cover
                                    and bookinfo.cover_bb and not bookinfo.ignore_cover then
                                    local _, _, sf = BookInfoManager.getCachedCoverSize(
                                        bookinfo.cover_w, bookinfo.cover_h,
                                        cover_max_w, cover_max_h)
                                    dialog_cover_widget = makeSideBySide(
                                        bookinfo.cover_bb,
                                        bookinfo.cover_w, bookinfo.cover_h,
                                        sf, text_str)
                                end
                            end
                        end
                    end
                end
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
                local allow_delete = zen_plugin
                    and type(zen_plugin.config) == "table"
                    and type(zen_plugin.config.context_menu) == "table"
                    and zen_plugin.config.context_menu.allow_delete == true
                if allow_delete then
                    table.insert(edit_buttons, {
                        {
                            text     = _("Delete"),
                            align    = "left",
                            enabled  = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:showDeleteFileDialog(file, refresh)
                            end,
                        },
                    })
                end

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
                -- Read status submenu
                table.insert(buttons, {
                    {
                        text     = _("Read status  ▶"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            local filemanagerutil = require("apps/filemanager/filemanagerutil")
                            local BookList        = require("ui/widget/booklist")
                            local DocSettings     = require("docsettings")
                            local doc_settings    = DocSettings:open(file)
                            local summary         = doc_settings:readSetting("summary") or {}
                            local current_status  = summary.status
                            local status_dialog
                            local caller_cb = function()
                                UIManager:close(status_dialog)
                                refresh()
                            end
                            local status_row = filemanagerutil.genStatusButtonsRow(doc_settings, caller_cb)
                            local is_unread = not current_status or current_status == ""
                            table.insert(status_row, 1, {
                                text     = _("Unread") .. (is_unread and "  ✓" or ""),
                                enabled  = not is_unread,
                                callback = function()
                                    summary.status = nil
                                    doc_settings:delSetting("percent_finished")
                                    doc_settings:delSetting("last_page")
                                    doc_settings:delSetting("last_xpointer")
                                    filemanagerutil.saveSummary(doc_settings, summary)
                                    BookList.setBookInfoCacheProperty(file, "status", nil)
                                    BookList.setBookInfoCacheProperty(file, "percent_finished", nil)
                                    caller_cb()
                                end,
                            })
                            status_dialog = ButtonDialog:new{
                                title        = _("Read status"),
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

            -- NOTE: using an explicit local avoids the Lua `A and nil or B` gotcha
            -- where `nil` is falsy so the expression always returns B.
            local dlg_title = dialog_cover_widget and "" or dialog_title
            self_fc.file_dialog = ButtonDialog:new{
                title          = dlg_title ~= "" and dlg_title or nil,
                title_align    = "center",
                buttons        = buttons,
                _added_widgets = dialog_cover_widget and { dialog_cover_widget } or nil,
            }
            UIManager:show(self_fc.file_dialog)
            return true
        end
    end
end

return apply_context_menu

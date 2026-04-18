local function apply_context_menu()
    --[[
        Replaces the long-hold file/folder context menu in the file browser with
        a clean, minimal layout:

            New folder
            Move          (opens PathChooser to pick destination, then moves immediately)
            Add/Remove from favorites
            Description   (files only: shows book description if one exists)
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
    -- _zen_no_forced_repaint: opt out of the partial_page_repaint forced flush.
    -- MoveChooser is a transient overlay — the full-page E-ink flash it causes
    -- when folder count < perpage is visually jarring and unnecessary.
    local MoveChooser = PathChooser:extend{ _zen_no_forced_repaint = true }

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

        -- Capture the original showFileDialog installed by setupLayout so we
        -- can delegate to it when not in the home directory.
        local orig_showFileDialog = file_chooser.showFileDialog

        -- Replace the instance-level showFileDialog defined by setupLayout
        file_chooser.showFileDialog = function(self_fc, item)
            -- Delegate to the stock KOReader dialog outside the home directory.
            local g_settings = rawget(_G, "G_reader_settings")
            local home_dir   = g_settings and g_settings:readSetting("home_dir")
            local cur_path   = self_fc.path or ""
            if home_dir then
                local norm_home = home_dir:gsub("/$", "")
                local norm_cur  = cur_path:gsub("/$", "")
                local is_at_or_under_home = norm_cur == norm_home
                    or norm_cur:sub(1, #norm_home + 1) == norm_home .. "/"
                if not is_at_or_under_home then
                    return orig_showFileDialog(self_fc, item)
                end
            end

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
            local dialog_title, dialog_cover_widget, book_description
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

                -- Build an OverlapGroup with cover at left edge, text stack at right edge.
                local function makeSideBySide(cover_bb, src_w, src_h, sf, title_str, authors_str, tags_str_arg)
                    local rendered_w  = math.floor(src_w * sf)
                    local rendered_h  = math.floor(src_h * sf)
                    local framed_h    = rendered_h + 2 * border
                    local text_col_w  = math.max(avail_w - rendered_w - 2 * border - gap,
                                                 Screen:scaleBySize(60))
                    local ImageWidget     = require("ui/widget/imagewidget")
                    local FrameContainer  = require("ui/widget/container/framecontainer")
                    local LeftContainer   = require("ui/widget/container/leftcontainer")
                    local HorizontalGroup = require("ui/widget/horizontalgroup")
                    local HorizontalSpan  = require("ui/widget/horizontalspan")
                    local TextWidget      = require("ui/widget/textwidget")
                    local VerticalGroup   = require("ui/widget/verticalgroup")
                    local VerticalSpan    = require("ui/widget/verticalspan")
                    local Font            = require("ui/font")
                    local Blitbuffer      = require("ffi/blitbuffer")
                    local Geom            = require("ui/geometry")
                    -- Raw point sizes (not pre-scaled) to match KOReader dialog conventions.
                    local fs_title   = 20
                    local fs_authors = 17
                    local fs_tags    = 14
                    local vstack = VerticalGroup:new{ align = "left" }
                    if title_str then
                        table.insert(vstack, TextWidget:new{
                            text      = title_str,
                            face      = Font:getFace("cfont", fs_title),
                            bold      = true,
                            max_width = text_col_w,
                        })
                    end
                    if authors_str then
                        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                        table.insert(vstack, TextWidget:new{
                            text      = authors_str,
                            face      = Font:getFace("cfont", fs_authors),
                            max_width = text_col_w,
                        })
                    end
                    if tags_str_arg and tags_str_arg ~= "" then
                        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(3) })
                        table.insert(vstack, TextWidget:new{
                            text      = tags_str_arg,
                            face      = Font:getFace("cfont", fs_tags),
                            fgcolor   = Blitbuffer.COLOR_GRAY_3,
                            max_width = text_col_w,
                        })
                    end
                    return LeftContainer:new{
                        dimen = Geom:new{ w = avail_w, h = framed_h },
                        HorizontalGroup:new{
                            align = "top",
                            FrameContainer:new{
                                padding    = 0,
                                bordersize = border,
                                ImageWidget:new{
                                    image            = cover_bb,
                                    image_disposable = true,
                                    scale_factor     = sf,
                                },
                            },
                            HorizontalSpan:new{ width = gap },
                            vstack,
                        },
                    }
                end

                if is_file then
                    local ok, BookInfoManager = pcall(require, "bookinfomanager")
                    local title_str, authors_str, tags_str_local
                    if ok then
                        local bookinfo = BookInfoManager:getBookInfo(file, true)
                        if bookinfo then
                            if not bookinfo.ignore_meta then
                                if bookinfo.title then
                                    title_str   = BD.auto(bookinfo.title)
                                    authors_str = bookinfo.authors and BD.auto(bookinfo.authors) or nil
                                end
                                if bookinfo.keywords and bookinfo.keywords ~= "" then
                                    tags_str_local = bookinfo.keywords
                                        :gsub("%s*[\n;]%s*", ", ")
                                        :gsub("%s+\xC2\xB7%s+", ", ")
                                        :gsub("^,%s*", ""):gsub(",%s*$", "")
                                end
                            end
                            if not bookinfo.ignore_meta and bookinfo.description
                                and bookinfo.description ~= "" then
                                book_description = bookinfo.description
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
                                    title_str or BD.filename(file:match("([^/]+)$")),
                                    authors_str,
                                    tags_str_local)
                            end
                        end
                    end
                    -- dialog_title is the plain text fallback used by the text-only header
                    -- and the status sub-dialog: keep it as "title\nauthors"
                    local text_str
                    if title_str then
                        text_str = title_str
                        if authors_str then text_str = text_str .. "\n" .. authors_str end
                    end
                    dialog_title = text_str or BD.filename(file:match("([^/]+)$"))
                else
                    -- folder
                    local name = (file:match("([^/]+)/?$") or file):gsub("/$", "")
                    local folder_name_str = BD.directory(name)
                    local count = item.mandatory and tostring(item.mandatory):match("^%s*(%d+)")
                    local folder_count_str
                    if count then
                        local n = tonumber(count) or 0
                        folder_count_str = n == 1 and _("1 book") or (n .. " " .. _("books"))
                    end
                    -- Plain-text fallback for text-only header (no cover)
                    dialog_title = folder_count_str
                        and (folder_name_str .. "\n" .. folder_count_str)
                        or folder_name_str
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
                                        sf, folder_name_str, folder_count_str, nil)
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
                            text     = "\u{F14A}  " .. _("Select"),
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
                            text     = "\u{F0C4}  " .. _("Cut"),
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
                            text     = "\u{F0C5}  " .. C_("File", "Copy"),
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
                            text     = "\u{F0EA}  " .. C_("File", "Paste"),
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
                            text     = "\u{F1F8}  " .. _("Delete"),
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
                        text     = "\u{F031}  " .. _("Rename"),
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
                    text     = "\u{F07B}  " .. _("New folder"),
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
                        text     = "\u{F047}  " .. _("Move"),
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
                                            -- Migrate cover/metadata DB entry to the new path so
                                            -- folder covers and list metadata update immediately
                                            -- without requiring full re-extraction.
                                            local ok_bim2, bim2 = pcall(require, "bookinfomanager")
                                            if ok_bim2 and bim2
                                                    and type(bim2.onFileManagerFileRenamed) == "function" then
                                                pcall(bim2.onFileManagerFileRenamed, bim2, src, dest_file)
                                            end
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
                        text = is_fav and ("\u{F006}  " .. _("Remove from favorites")) or ("\u{F005}  " .. _("Add to favorites")),
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

            if is_file and is_not_parent_folder and book_description then
                table.insert(buttons, {
                    {
                        text     = "\u{F129}  " .. _("Description"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            local util       = require("util")
                            local TextViewer = require("ui/widget/textviewer")
                            UIManager:show(TextViewer:new{
                                title     = _("Description:"),
                                text      = util.htmlToPlainTextIfHtml(book_description),
                                text_type = "book_info",
                            })
                        end,
                    },
                })
            end

            if is_file and is_not_parent_folder then
                -- Read status submenu
                table.insert(buttons, {
                    {
                        text     = "\u{F02D}  " .. _("Read status  ▶"),
                        align    = "left",
                        callback = function()
                            close_dialog()
                            local filemanagerutil = require("apps/filemanager/filemanagerutil")
                            local BookList        = require("ui/widget/booklist")
                            local DocSettings     = require("docsettings")
                            local doc_settings    = DocSettings:open(file)
                            local summary         = doc_settings:readSetting("summary") or {}
                            local current_status  = summary.status
                            local is_unread       = not current_status or current_status == ""
                            local status_dialog

                            local function setStatus(to_status)
                                if to_status == nil then
                                    summary.status = nil
                                    doc_settings:delSetting("percent_finished")
                                    doc_settings:delSetting("last_page")
                                    doc_settings:delSetting("last_xpointer")
                                    BookList.setBookInfoCacheProperty(file, "percent_finished", nil)
                                else
                                    summary.status = to_status
                                end
                                filemanagerutil.saveSummary(doc_settings, summary)
                                BookList.setBookInfoCacheProperty(file, "status", to_status)
                                UIManager:close(status_dialog)
                                refresh()
                            end

                            local function statusBtn(icon, label, to_status)
                                local is_cur = (to_status == nil and is_unread)
                                    or (to_status ~= nil and current_status == to_status)
                                return {{
                                    text     = icon .. "  " .. label .. (is_cur and "  \u{2713}" or ""),
                                    align    = "left",
                                    enabled  = not is_cur,
                                    callback = function() setStatus(to_status) end,
                                }}
                            end

                            status_dialog = ButtonDialog:new{
                                title       = _("Read status"),
                                title_align = "center",
                                buttons     = {
                                    statusBtn("\u{F02D}", _("Unread"),   nil),
                                    statusBtn("\u{F02E}", _("Reading"),  "reading"),
                                    statusBtn("\u{F04C}", _("On hold"),  "abandoned"),
                                    statusBtn("\u{F00C}", _("Finished"), "complete"),
                                },
                            }
                            UIManager:show(status_dialog)
                        end,
                    },
                })
            end

            -- ── Per-folder sort override (folders only) ───────────────────────────
            if not is_file and is_not_parent_folder then
                local fsd_api = rawget(_G, "__ZEN_FOLDER_SORT")
                if fsd_api then
                    local ffiUtil_fsd = require("ffi/util")
                    local real_folder = ffiUtil_fsd.realpath(file) or file

                    local folder_sort_options = {
                        { key = "title",   text = "\u{F031}  " .. _("Title")    },
                        { key = "authors", text = "\u{F007}  " .. _("Authors")  },
                        { key = "series",  text = "\u{F0CB}  " .. _("Series")   },
                        { key = "keywords",text = "\u{F02C}  " .. _("Keywords") },
                    }

                    table.insert(buttons, {
                        {
                            text     = "\u{F0DC}  " .. _("Sort folder  ▶"),
                            align    = "left",
                            callback = function()
                                close_dialog()
                                local sort_dialog
                                local sort_buttons = {}
                                local current_override = fsd_api.get(real_folder)
                                for _, opt in ipairs(folder_sort_options) do
                                    local is_active = current_override == opt.key
                                    table.insert(sort_buttons, {{
                                        text     = opt.text .. (is_active and "  \u{2713}" or ""),
                                        align    = "left",
                                        enabled  = not is_active,
                                        callback = function()
                                            fsd_api.set(real_folder, opt.key)
                                            UIManager:close(sort_dialog)
                                        end,
                                    }})
                                end
                                -- "Clear" row — only shown when an override is active
                                if current_override then
                                    table.insert(sort_buttons, {{
                                        text     = "\u{F0E2}  " .. _("Clear"),
                                        align    = "left",
                                        callback = function()
                                            fsd_api.clear(real_folder)
                                            UIManager:close(sort_dialog)
                                        end,
                                    }})
                                end
                                sort_dialog = ButtonDialog:new{
                                    title       = _("Sort folder by"),
                                    title_align = "center",
                                    buttons     = sort_buttons,
                                }
                                UIManager:show(sort_dialog)
                            end,
                        },
                    })
                end
            end

            table.insert(buttons, {
                {
                    text     = "\u{F040}  " .. _("Edit  ▶"),
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

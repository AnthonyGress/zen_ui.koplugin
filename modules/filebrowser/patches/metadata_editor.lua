local function apply_metadata_editor()
    local BookInfo = require("apps/filemanager/filemanagerbookinfo")
    if BookInfo._zen_metadata_editor_patched then return end
    BookInfo._zen_metadata_editor_patched = true

    local Editor = require("modules/filebrowser/metadata_editor")
    local Service = require("modules/filebrowser/metadata/service")
    local TokenStore = require("config/hardcover_token")
    local DocSettings = require("docsettings")
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    local logger = require("common/zen_logger").new("metadata_editor")
    local _ = require("gettext")
    local T = require("ffi/util").template
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local utils = require("common/utils")
    local _icons_dir
    do
        local src = debug.getinfo(1, "S").source or ""
        if src:sub(1, 1) == "@" then
            local root = src:sub(2):match("^(.*)/modules/")
            if root then _icons_dir = root .. "/icons/" end
        end
    end
    local search_icon = utils.resolveLocalIcon(_icons_dir, "quick_search")
    local close_icon = utils.resolveLocalIcon(
        lfs.currentdir() .. "/resources/icons/mdlight/", "close")

    local error_messages = {
        invalid_file = _("This file is no longer available."),
        open_book = _("Close this book before editing its metadata."),
        invalid_epub = _("This EPUB could not be read."),
        invalid_series_index = _("Series position must be a number."),
        missing_title = _("An EPUB title is required."),
        missing_language = _("An EPUB language is required."),
        sidecar_write_failed = _("The KOReader metadata override could not be saved."),
    }

    local function error_text(err, fallback)
        return error_messages[err] or fallback
    end

    local function show_error(err)
        UIManager:show(InfoMessage:new{
            text = error_text(err, _("Metadata could not be loaded.")),
        })
    end

    local function call_service(name, ...)
        local file = select(1, ...)
        logger.dbg("metadata service start operation=", name, " file=", tostring(file))
        local ok, result, err = pcall(Service[name], ...)
        if not ok then
            logger.warn("metadata service crashed operation=", name, " error=", tostring(result))
            return nil, result
        end
        if result == nil or result == false then
            logger.warn("metadata service failed operation=", name, " error=", tostring(err))
        else
            logger.dbg("metadata service complete operation=", name)
        end
        return result, err
    end

    local function resolve_file(doc_settings_or_file)
        if type(doc_settings_or_file) == "table"
                and type(doc_settings_or_file.readSetting) == "function" then
            return doc_settings_or_file:readSetting("doc_path")
        end
        return doc_settings_or_file
    end

    local function trim(value)
        return tostring(value or ""):match("^%s*(.-)%s*$") or ""
    end

    local function join_parts(values, separator)
        local parts = {}
        for _i, value in ipairs(values) do
            value = trim(value)
            if value ~= "" then parts[#parts + 1] = value end
        end
        return table.concat(parts, separator or " · ")
    end

    local function token()
        return TokenStore.get()
    end

    local function metadata_config()
        local config = zen_plugin and zen_plugin.config
        return type(config) == "table" and type(config.metadata) == "table"
            and config.metadata or {}
    end

    local function open_metadata_settings()
        if not zen_plugin then
            UIManager:show(InfoMessage:new{
                text = _("Open Zen UI Settings → Library → Metadata to set a Hardcover token."),
            })
            return
        end
        require("modules/settings/zen_settings_page").show(zen_plugin, {
            path = {
                { key = "_zen_settings_root", value = "library" },
                { key = "_zen_metadata_settings", value = true },
            },
        })
    end

    local function offer_token_settings(text)
        local ConfirmBox = require("ui/widget/confirmbox")
        UIManager:show(ConfirmBox:new{
            text = text,
            cancel_text = _("Keep editing"),
            ok_text = _("Open settings"),
            ok_callback = open_metadata_settings,
        })
    end

    local hardcover_errors = {
        offline = _("Connect to a network before searching Hardcover."),
        rate_limited = _("Hardcover is rate-limiting requests. Try again later."),
        server = _("Hardcover is unavailable right now. Try again later."),
        malformed = _("Hardcover returned an unreadable response."),
        no_match = _("No Hardcover matches were found."),
        network = _("Could not reach Hardcover."),
    }

    local function show_hardcover_error(err)
        local kind = type(err) == "table" and err.kind or nil
        logger.warn("Hardcover request failed kind=", tostring(kind),
            " status=", tostring(type(err) == "table" and err.status or nil),
            " retry_after=", tostring(type(err) == "table" and err.retry_after or nil))
        if kind == "unauthorized" or kind == "forbidden" then
            offer_token_settings(_("The Hardcover token was rejected. Check that it has read:catalog access."))
            return
        end
        UIManager:show(InfoMessage:new{
            text = hardcover_errors[kind] or _("Hardcover lookup failed."),
        })
    end

    local function run_hardcover_request(text, task, on_success)
        local Trapper = require("ui/trapper")
        Trapper:wrap(function()
            logger.dbg("Hardcover task start:", text)
            local notice = InfoMessage:new{ text = text }
            UIManager:show(notice)
            if UIManager.forceRePaint then UIManager:forceRePaint() end
            local completed, result, err = Trapper:dismissableRunInSubprocess(task, notice)
            local function close_notice()
                UIManager:close(notice)
                if UIManager.forceRePaint then UIManager:forceRePaint() end
            end
            if not completed then
                close_notice()
                logger.dbg("Hardcover task cancelled:", text)
                return
            end
            if result == nil then
                close_notice()
                show_hardcover_error(err)
                return
            end
            logger.dbg("Hardcover task complete:", text)
            local ok, callback_err = pcall(on_success, result)
            close_notice()
            if not ok then
                logger.warn("Hardcover result handling failed:", tostring(callback_err))
                show_hardcover_error({ kind = "malformed" })
            end
        end)
    end

    local function first_author(draft)
        return type(draft.authors) == "table" and trim(draft.authors[1]) or ""
    end

    local function series_label(work)
        local name = trim(work.series_name)
        if name == "" then return "" end
        local index = trim(work.series_index)
        return index == "" and name or name .. " #" .. index
    end

    local function work_secondary(work)
        local parts = {}
        if work.exact_edition then parts[#parts + 1] = _("Exact ISBN match") end
        parts[#parts + 1] = table.concat(
            type(work.authors) == "table" and work.authors or {}, ", ")
        if work.release_year then parts[#parts + 1] = work.release_year end
        parts[#parts + 1] = series_label(work)
        return join_parts(parts)
    end

    local function language_label(code)
        code = trim(code)
        if code == "" then return "" end
        local name = require("common/language_name").get(code)
        return name ~= code and T(_("%1 (%2)"), name, code) or code
    end

    local function edition_primary(edition)
        local value = join_parts({ edition.edition_format, edition.release_year }, ", ")
        return value ~= "" and value or _("Edition")
    end

    local function edition_secondary(edition)
        local pages = tonumber(edition.pages)
        return join_parts({
            edition.publisher,
            language_label(edition.language),
            pages and T(_("%1 pages"), pages) or "",
        })
    end

    local function edition_summary(edition)
        local summary = join_parts({ edition_primary(edition), edition.publisher })
        return summary ~= "" and summary or _("Selected edition")
    end

    local start_hardcover_search
    local show_search_dialog
    local cover_download_serial = 0

    local function usable_cover(path)
        local RenderImage = require("ui/renderimage")
        local ok_cover, cover = pcall(RenderImage.renderImageFile,
            RenderImage, path, false, 32, 48)
        if cover and type(cover.free) == "function" then pcall(cover.free, cover) end
        return ok_cover and cover ~= nil
    end

    local function normalized_downloaded_cover(path)
        local file = io.open(path, "rb")
        if not file then return nil end
        local header = file:read(12) or ""
        file:close()
        local suffix
        if header:sub(1, 2) == "\255\216" then
            suffix = "jpg"
        elseif header:sub(1, 4) == "\137PNG" then
            suffix = "png"
        elseif header:sub(1, 4) == "GIF8" then
            suffix = "gif"
        elseif header:sub(1, 4) == "RIFF" and header:sub(9, 12) == "WEBP" then
            suffix = "webp"
        end
        if not suffix then return nil end
        local normalized = path:gsub("%.[^./]+$", "") .. "." .. suffix
        if normalized ~= path then
            os.remove(normalized)
            if not os.rename(path, normalized) then return nil end
        end
        if usable_cover(normalized) then return normalized end
        os.remove(normalized)
        return nil
    end

    local function next_cover_destination()
        local cache_dir = require("datastorage"):getDataDir() .. "/cache"
        lfs.mkdir(cache_dir)
        cover_download_serial = cover_download_serial + 1
        return ffiUtil.joinPath(cache_dir,
            "zen-metadata-cover-" .. cover_download_serial .. ".img")
    end

    local function stage_hardcover_cover(editor, edition, path)
        local original = path
        path = normalized_downloaded_cover(original)
        if not path then
            os.remove(original)
            editor:showError(_("The cover image could not be saved."))
            return
        end
        edition._cover_path = nil
        editor:setPendingCover(path, true, "hardcover")
        if type(editor._refreshCoverPicker) == "function" then
            editor._refreshCoverPicker()
        end
        logger.dbg("Hardcover cover staged edition_id=", tostring(edition.id))
    end

    local function download_hardcover_cover(editor, edition, show_missing_error)
        if trim(edition.image_url) == "" then
            if show_missing_error then show_hardcover_error({ kind = "no_match" }) end
            return
        end
        if edition._cover_path then
            stage_hardcover_cover(editor, edition, edition._cover_path)
            return
        end
        local destination = next_cover_destination()
        run_hardcover_request(_("Downloading cover…"), function()
            return require("modules/filebrowser/metadata/hardcover")
                .downloadCover(edition.image_url, destination)
        end, function(path)
            stage_hardcover_cover(editor, edition, path)
        end)
    end

    local function apply_hardcover_selection(editor, work, edition, cover_only)
        if cover_only then
            download_hardcover_cover(editor, edition, true)
            return
        end
        local Client = require("modules/filebrowser/metadata/hardcover")
        local metadata, err = Client.draft(work, edition)
        if not metadata then
            show_hardcover_error(err)
            return
        end
        local retained = editor:applyHardcover(metadata, edition_summary(edition))
        logger.dbg("Hardcover metadata staged work_id=", tostring(work.id),
            " edition_id=", tostring(edition.id), " retained=", tostring(retained))
        if trim(edition.image_url) ~= ""
                and editor:getPendingCoverSource() ~= "manual" then
            download_hardcover_cover(editor, edition, false)
        end
    end

    local function cover_editions(editions)
        local result = {}
        for _i, edition in ipairs(editions) do
            if trim(edition.image_url) ~= "" then result[#result + 1] = edition end
        end
        return result
    end

    local function cleanup_cover_previews(editions, keep)
        for _i, edition in ipairs(editions) do
            local path = edition._cover_path
            if path and path ~= keep then os.remove(path) end
            if path ~= keep then edition._cover_path = nil end
        end
    end

    local function prepare_cover_previews(
            editor, editions, callback, require_cover, notice_text)
        local downloads = {}
        for index, edition in ipairs(editions) do
            if trim(edition.image_url) ~= "" then
                downloads[#downloads + 1] = {
                    index = index,
                    url = edition.image_url,
                    destination = next_cover_destination(),
                }
            end
        end
        if #downloads == 0 then
            if require_cover then
                editor:showError(_("The cover image could not be saved."))
            else
                callback(editions)
            end
            return
        end
        run_hardcover_request(notice_text, function()
            local Client = require("modules/filebrowser/metadata/hardcover")
            local completed = {}
            for _i, download in ipairs(downloads) do
                local path = Client.downloadCover(download.url, download.destination)
                if path then
                    completed[#completed + 1] = { index = download.index, path = path }
                end
            end
            return completed
        end, function(completed)
            local ready = require_cover and {} or editions
            for _i, download in ipairs(completed) do
                local edition = editions[download.index]
                local path = normalized_downloaded_cover(download.path)
                if edition and path then
                    edition._cover_path = path
                    if require_cover then ready[#ready + 1] = edition end
                else
                    os.remove(download.path)
                end
            end
            if require_cover and #ready == 0 then
                editor:showError(_("The cover image could not be saved."))
                return
            end
            callback(ready)
        end)
    end

    local function present_edition_picker(editor, draft, work, editions, cover_only)
        local items = {}
        for _i, edition in ipairs(editions) do
            items[#items + 1] = {
                text = edition_primary(edition),
                secondary_text = edition_secondary(edition),
                image_file = edition._cover_path,
                edition = edition,
            }
        end
        local picker
        picker = require("common/ui/zen_menu_picker"){
            title = _("Choose a Hardcover edition"),
            items = items,
            rows_per_page = 5,
            black_text = true,
            title_action_icon = search_icon,
            title_action_keep_open = true,
            title_action_callback = function()
                show_search_dialog(editor, draft, cover_only, function()
                    picker:onCancelOrClose()
                end)
            end,
            back_hold_callback = function() return true end,
            on_close = function(item)
                local keep = item and item.edition and item.edition._cover_path
                cleanup_cover_previews(editions, keep)
            end,
            on_select = function(item)
                apply_hardcover_selection(editor, work, item.edition, cover_only)
            end,
        }
    end

    local function show_edition_picker(editor, draft, work, editions, cover_only)
        if cover_only then editions = cover_editions(editions) end
        if #editions == 0 then
            show_hardcover_error({ kind = "no_match" })
            return
        end
        prepare_cover_previews(editor, editions, function(ready)
            present_edition_picker(editor, draft, work, ready, cover_only)
        end, cover_only, _("Finding Hardcover editions…"))
    end

    local function select_work(editor, draft, work, cover_only, auto_pick)
        if work.exact_edition and not cover_only then
            apply_hardcover_selection(editor, work, work.exact_edition)
            return
        end
        local lookup_token = token()
        run_hardcover_request(_("Finding Hardcover editions…"), function()
            return require("modules/filebrowser/metadata/hardcover")
                .editions(lookup_token, work)
        end, function(editions)
            if cover_only then editions = cover_editions(editions) end
            if auto_pick then
                local best
                for _i, edition in ipairs(editions) do
                    if edition.is_audio ~= true then
                        best = edition
                        break
                    end
                end
                if best then
                    apply_hardcover_selection(editor, work, best, cover_only)
                elseif #editions > 0 then
                    show_edition_picker(editor, draft, work, editions, cover_only)
                else
                    show_hardcover_error({ kind = "no_match" })
                end
            elseif #editions == 1 and editions[1].is_audio ~= true then
                apply_hardcover_selection(editor, work, editions[1], cover_only)
            else
                show_edition_picker(editor, draft, work, editions, cover_only)
            end
        end)
    end

    local function show_work_picker(editor, draft, works, cover_only)
        prepare_cover_previews(editor, works, function(ready)
            local items = {}
            for _i, work in ipairs(ready) do
                items[#items + 1] = {
                    text = work.title,
                    secondary_text = work_secondary(work),
                    image_file = work._cover_path,
                    bold = work.exact_edition ~= nil,
                    work = work,
                }
            end
            local picker
            picker = require("common/ui/zen_menu_picker"){
                title = _("Hardcover results"),
                items = items,
                rows_per_page = 5,
                black_text = true,
                title_action_icon = search_icon,
                title_action_keep_open = true,
                title_action_callback = function()
                    show_search_dialog(editor, draft, cover_only, function()
                        picker:onCancelOrClose()
                    end)
                end,
                back_hold_callback = function() return true end,
                on_close = function() cleanup_cover_previews(works) end,
                on_select = function(item)
                    select_work(editor, draft, item.work, cover_only)
                end,
            }
        end, false, _("Searching Hardcover…"))
    end

    start_hardcover_search = function(editor, draft, query, cover_only, replace_callback)
        local lookup_token = token()
        if lookup_token == "" then
            offer_token_settings(_("No Hardcover token is saved. Open metadata settings to add one?"))
            return
        end
        local auto_pick = metadata_config().hardcover_auto_match ~= false
        local explicit_query = query ~= nil
        query = query or draft
        if not auto_pick then
            query = {
                title = query.title,
                author = explicit_query and query.author or nil,
                isbn = query.isbn,
                limit = query.limit,
                include_title_results = true,
            }
        end
        logger.dbg("Hardcover search requested cover_only=", tostring(cover_only == true),
            " auto_pick=", tostring(auto_pick),
            " isbn=", trim(query.isbn) ~= "" and "yes" or "no")
        run_hardcover_request(_("Searching Hardcover…"), function()
            return require("modules/filebrowser/metadata/hardcover")
                .search(lookup_token, query)
        end, function(works)
            if replace_callback then replace_callback() end
            if auto_pick then
                if works[1] then
                    select_work(editor, draft, works[1], cover_only, true)
                else
                    show_hardcover_error({ kind = "no_match" })
                end
            else
                show_work_picker(editor, draft, works, cover_only)
            end
        end)
    end

    show_search_dialog = function(editor, draft, cover_only, replace_callback)
        local MultiInputDialog = require("ui/widget/multiinputdialog")
        local ZenModalClose = require("common/ui/zen_modal_close")
        local dialog
        local function close()
            UIManager:close(dialog)
            return true
        end
        local function search()
            local fields = dialog:getFields()
            local title = trim(fields[1])
            if title == "" then
                editor:showError(_("Enter a title to search Hardcover."))
                return
            end
            local query = { title = title, author = trim(fields[2]) }
            UIManager:close(dialog)
            UIManager:nextTick(function()
                start_hardcover_search(
                    editor, draft, query, cover_only, replace_callback)
            end)
        end
        dialog = MultiInputDialog:new{
            title = _("Search Hardcover"),
            fields = {
                { description = _("Title"), text = draft.title },
                { description = _("Author"), text = first_author(draft) },
            },
            buttons = {{
                { text = _("Cancel"), id = "close", callback = close },
                { text = _("Search"), is_enter_default = true, callback = search },
            }},
        }
        ZenModalClose.installDialog(dialog, close)
        UIManager:show(dialog)
        dialog:onShowKeyboard()
    end

    local function native_hardcover(draft, editor)
        if (metadata_config().hardcover_auto_match == false
                and trim(editor.edition_summary) ~= "")
                or trim(draft.title) == "" then
            show_search_dialog(editor, draft)
            return
        end
        start_hardcover_search(editor, draft)
    end

    function BookInfo:showFromBookDetails(doc_settings_or_file, book_props, options)
        options = type(options) == "table" and options or {}
        local file = resolve_file(doc_settings_or_file)
        local draft, load_err = call_service("load", file)
        if not draft then
            show_error(load_err)
            return false
        end

        local is_epub = Service.isEpub(file) == true
        local can_restore = false
        if is_epub then
            local ok_restore, available = pcall(Service.canRestore, file)
            can_restore = ok_restore and available == true
        end
        local current_cover
        if type(self.getCoverImage) == "function" then
            local ok_cover, cover = pcall(self.getCoverImage, self, nil, file)
            if ok_cover then current_cover = cover end
        end

        return Editor.show{
            file = file,
            metadata = draft,
            is_epub = is_epub,
            can_restore = can_restore,
            has_custom_cover = DocSettings:findCustomCoverFile(file) ~= nil,
            current_cover = current_cover,
            edition_summary = options.edition_summary,
            on_hardcover = options.on_hardcover or native_hardcover,
            on_open_with = self.ui and type(self.ui.showOpenWithDialog) == "function"
                and function(editor)
                    self.ui:showOpenWithDialog(editor.file)
                end or nil,
            on_cover = function(editor)
                local show_picker
                local function refresh_picker()
                    local current = editor._cover_picker
                    if current and type(current.onCancelOrClose) == "function" then
                        current:onCancelOrClose()
                    end
                    UIManager:nextTick(show_picker)
                end
                show_picker = function()
                    local footer_buttons = {
                        {
                            text = _("Choose image"),
                            action = "image",
                            keep_open = true,
                            filled = false,
                        },
                        {
                            text = _("Find on Hardcover"),
                            action = "hardcover",
                            keep_open = true,
                            filled = true,
                        },
                    }
                    if editor:getPendingCover() then
                        footer_buttons[#footer_buttons + 1] = {
                            text = _("Clear"),
                            action = "discard",
                            filled = false,
                        }
                    end
                    local cover_picker
                    cover_picker = require("common/ui/zen_menu_picker"){
                        title = _("Cover"),
                        items = {},
                        footer_buttons = footer_buttons,
                        footer_buttons_under_header = true,
                        hide_header_divider = true,
                        title_action_icon = close_icon,
                        title_action_callback = function()
                            if type(editor._requestClose) == "function" then
                                editor:_requestClose(true)
                            end
                        end,
                        header_height = type(editor.getCoverComparisonHeight) == "function"
                            and editor:getCoverComparisonHeight() or nil,
                        paint_header = type(editor.paintCoverComparison) == "function"
                            and function(bb, x, y, width, height)
                                editor:paintCoverComparison(bb, x, y, width, height)
                            end or nil,
                        on_header_tap = type(editor.showCoverFullscreen) == "function"
                            and function(x, _y, width)
                                return editor:showCoverFullscreen(x, width)
                            end or nil,
                        back_hold_callback = function() return true end,
                        on_close = function()
                            if editor._cover_picker == cover_picker then
                                editor._cover_picker = nil
                                editor._refreshCoverPicker = nil
                            end
                        end,
                        on_select = function(item)
                            if item.action == "hardcover" then
                                start_hardcover_search(editor, editor:getDraft(), nil, true)
                            elseif item.action == "discard" then
                                editor:clearPendingCover()
                                refresh_picker()
                            else
                                local PathChooser = require("ui/widget/pathchooser")
                                local DocumentRegistry = require("document/documentregistry")
                                UIManager:show(PathChooser:new{
                                    select_directory = false,
                                    file_filter = function(filename)
                                        return DocumentRegistry:isImageFile(filename)
                                    end,
                                    onConfirm = function(image_file)
                                        if not usable_cover(image_file) then
                                            editor:showError(_("The cover image could not be saved."))
                                            return
                                        end
                                        editor:setPendingCover(image_file, false, "manual")
                                        refresh_picker()
                                    end,
                                })
                            end
                        end,
                    }
                    editor._cover_picker = cover_picker
                    editor._refreshCoverPicker = refresh_picker
                end
                show_picker()
            end,
            on_rename = self.ui and type(self.ui.renameFile) == "function"
                and function(basename, editor)
                    local source = editor.file
                    local destination = ffiUtil.joinPath(ffiUtil.dirname(source), basename)
                    if lfs.symlinkattributes(destination) then
                        return nil, _("A file with this name already exists.")
                    end
                    local backup_ok, moved_backup = Service.moveEpubBackup(
                        source, destination)
                    if not backup_ok then
                        return nil, _("The EPUB backup could not be moved.")
                    end
                    local called = pcall(self.ui.renameFile,
                        self.ui, source, basename, true)
                    local renamed = called
                        and not lfs.symlinkattributes(source)
                        and lfs.attributes(destination, "mode") == "file"
                    if not renamed then
                        if moved_backup then
                            Service.moveEpubBackup(destination, source)
                        end
                        return nil, _("Renaming the file failed.")
                    end
                    if type(options.on_renamed) == "function" then
                        options.on_renamed(destination, editor)
                    end
                    return destination
                end or nil,
            on_save = function(next_draft, editor)
                local target = editor.file
                local metadata_dirty = editor:isMetadataDirty()
                local keep_backup = metadata_config().epub_backup == true
                logger.dbg("metadata save requested file=", tostring(target),
                    " metadata_dirty=", tostring(metadata_dirty),
                    " cover_dirty=", tostring(editor:getPendingCover() ~= nil))
                local function save_all()
                    if metadata_dirty then
                        local saved, save_err = call_service("save", target, next_draft, {
                            keep_backup = keep_backup,
                        })
                        if not saved then
                            return nil, error_text(save_err,
                                _("Metadata could not be saved."))
                        end
                    end
                    local cover_file = editor:getPendingCover()
                    if cover_file then
                        local cover_ok, cover_err = pcall(self.setCustomCoverFromImage,
                            self, target, cover_file)
                        if not cover_ok or not DocSettings:findCustomCoverFile(target) then
                            logger.warn("cover update failed file=", tostring(target),
                                " error=", tostring(cover_err))
                            if metadata_dirty then editor:markMetadataSaved() end
                            return nil, metadata_dirty
                                and _("Metadata was saved, but the cover image could not be saved.")
                                or _("The cover image could not be saved.")
                        end
                        if type(options.on_cover_changed) == "function" then
                            options.on_cover_changed(target, editor)
                        end
                        logger.dbg("cover update complete file=", tostring(target))
                    end
                    if type(options.on_saved) == "function" then
                        options.on_saved(target, next_draft, editor)
                    end
                    logger.dbg("metadata save complete file=", tostring(target))
                    return true
                end
                if is_epub and metadata_dirty then
                    local ConfirmBox = require("ui/widget/confirmbox")
                    UIManager:show(ConfirmBox:new{
                        text = keep_backup
                            and _("Save these changes inside the EPUB? ZenOS will keep one restorable backup.")
                            or _("Save these changes inside the EPUB?"),
                        cancel_text = _("Cancel"),
                        ok_text = _("Save EPUB"),
                        flush_events_on_show = true,
                        cancel_callback = function() editor:cancelSave() end,
                        ok_callback = function()
                            local overlay = InfoMessage:new{
                                text = _("Saving metadata…"),
                                dismissable = false,
                            }
                            UIManager:show(overlay)
                            if UIManager.forceRePaint then UIManager:forceRePaint() end
                            UIManager:nextTick(function()
                                local saved, save_err = save_all()
                                UIManager:close(overlay)
                                if saved then
                                    editor:setRestoreAvailable(keep_backup)
                                end
                                editor:completeSave(saved, save_err)
                            end)
                        end,
                    })
                    return
                end
                return save_all()
            end,
            on_restore = function(editor)
                local target = editor.file
                local restored, restore_err = call_service("restore", target)
                if restored and type(options.on_restored) == "function" then
                    options.on_restored(target, editor)
                end
                return restored, error_text(restore_err, _("Metadata could not be restored."))
            end,
            on_back = options.back_callback,
            on_close_all = options.close_parent_callback,
        }
    end
end

return apply_metadata_editor

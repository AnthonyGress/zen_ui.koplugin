local function apply_context_menu()
    --[[
        Replaces the long-hold file/folder context menu with a minimal layout.
        Always active; delegates to stock KOReader outside home_dir.
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
    local book_status  = require("common/book_status")
    local paths        = require("common/paths")
    local icons        = require("common/inline_icon_map")
    local zen_plugin   = rawget(_G, "__ZEN_UI_PLUGIN")
    local Cover        = require("common/cover_utils")
    local VerticalGroup   = require("ui/widget/verticalgroup")
    local VerticalSpan    = require("ui/widget/verticalspan")
    local LeftContainer   = require("ui/widget/container/leftcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local FrameContainer  = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan  = require("ui/widget/horizontalspan")
    local TextWidget      = require("ui/widget/textwidget")
    local Font            = require("ui/font")
    local Geom            = require("ui/geometry")
    local Blitbuffer      = require("ffi/blitbuffer")
    local library_font    = require("common/library_font")

    local function apply_button_group_font(button_rows, nominal_size)
        if type(button_rows) ~= "table" then return button_rows end
        for _i, row in ipairs(button_rows) do
            if type(row) == "table" then
                for _j, btn in ipairs(row) do
                    if type(btn) == "table" and type(btn.text) == "string" then
                        local face = btn.font_face or btn.text_font_face or library_font.getFontName()
                        btn.font_face = face
                    end
                end
            end
        end
        return button_rows
    end

    local function get_title_face_for_textviewer()
        local default_title_face = Font:getFace("x_smalltfont")
        local title_size = default_title_face and default_title_face.orig_size or 20
        return Font:getFace(library_font.getFontName(), title_size)
    end

    local function apply_textviewer_body_font_family(tv)
        if type(tv) ~= "table" then return end
        if not tv.scroll_text_w then return end
        local ScrollTextWidget = require("ui/widget/scrolltextwidget")
        local body_size = tv.text_font_size
        if type(body_size) ~= "number" or body_size <= 0 then
            local text_widget = tv.scroll_text_w and tv.scroll_text_w.text_widget
            body_size = text_widget and text_widget.face and text_widget.face.orig_size or 20
        end

        local textw_height = tv.height - tv.titlebar:getHeight() - tv.button_table:getSize().h
        local new_scroll = ScrollTextWidget:new{
            text = tv.text,
            face = Font:getFace(library_font.getFontName(), body_size),
            fgcolor = tv.fgcolor,
            width = tv.width - 2 * tv.text_padding - 2 * tv.text_margin,
            height = textw_height - 2 * tv.text_padding - 2 * tv.text_margin,
            dialog = tv,
            alignment = tv.alignment,
            justified = tv.justified,
            lang = tv.lang,
            para_direction_rtl = tv.para_direction_rtl,
            auto_para_direction = tv.auto_para_direction,
            alignment_strict = tv.alignment_strict,
            scroll_callback = tv._buttons_scroll_callback,
        }

        pcall(function()
            if type(tv.scroll_text_w.free) == "function" then
                tv.scroll_text_w:free(false)
            end
        end)
        tv.scroll_text_w = new_scroll
        if type(tv.textw) == "table" then
            tv.textw[1] = new_scroll
        end
    end

    -- MoveChooser
    local MoveChooser = PathChooser:extend{ _zen_no_forced_repaint = true }

    function MoveChooser:genItemTableFromPath(path)
        local ffiUtil3 = require("ffi/util")
        local lfs3     = require("libs/libkoreader-lfs")
        local BD3      = require("ui/bidi")
        local root     = ffiUtil3.realpath(path) or path
        local MAX_DEPTH = 3
        local items    = {}

        if not self.src_dir or self.src_dir ~= root then
            table.insert(items, {
                text           = ffiUtil3.basename(root),
                path           = root,
                is_file        = false,
                bidi_wrap_func = BD3.directory,
                mandatory      = self:getMenuItemMandatory({ path = root }),
            })
        end

        local function scan(dir_path, depth, base, prefix, skip_set)
            base = base or root
            local ok3, iter3, dir_obj3 = pcall(lfs3.dir, dir_path)
            if not ok3 then return end
            local subdirs = {}
            for fname in iter3, dir_obj3 do
                if fname ~= "." and fname ~= ".."
                        and not fname:match("^%.")
                        and self:show_dir(fname) then
                    local fpath = dir_path .. "/" .. fname
                    if lfs3.attributes(fpath, "mode") == "directory" then
                        table.insert(subdirs, { name = fname, path = fpath })
                    end
                end
            end
            table.sort(subdirs, function(a, b) return a.name < b.name end)
            for _i, sub in ipairs(subdirs) do
                local sub_real = ffiUtil3.realpath(sub.path) or sub.path
                if not (skip_set and skip_set[sub_real]) then
                    local rel = sub.path:sub(#base + 2)
                    local display = prefix and (prefix .. "/" .. rel) or rel
                    table.insert(items, {
                        text           = display,
                        path           = sub.path,
                        is_file        = false,
                        bidi_wrap_func = BD3.directory,
                        mandatory      = self:getMenuItemMandatory({ path = sub.path }),
                    })
                    if depth < MAX_DEPTH then
                        scan(sub.path, depth + 1, base, prefix, skip_set)
                    end
                end
            end
        end

        scan(root, 1)

        if type(self.extra_roots) == "table" then
            local skip_set = { [root] = true }
            for _i, er_path in ipairs(self.extra_roots) do
                local er = ffiUtil3.realpath(er_path) or er_path
                skip_set[er] = true
            end

            for _i, er_path in ipairs(self.extra_roots) do
                local er = ffiUtil3.realpath(er_path) or er_path
                if er ~= root then
                    local er_name = ffiUtil3.basename(er)
                    if not self.src_dir or self.src_dir ~= er then
                        table.insert(items, {
                            text           = er_name,
                            path           = er,
                            is_file        = false,
                            bidi_wrap_func = BD3.directory,
                            mandatory      = self:getMenuItemMandatory({ path = er }),
                        })
                    end
                    scan(er, 1, er, er_name, skip_set)
                end
            end
        end

        return items
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

    function MoveChooser:init()
        PathChooser.init(self)
        local tb = self.title_bar
        if tb and tb.has_left_icon then
            tb:clear()
            tb.left_icon = nil
            tb.has_left_icon = false
            tb.left_button = nil
            tb:init()
        end
    end

    local orig_setupLayout = FileManager.setupLayout

    if type(FileChooser.show_file) == "function" and not FileChooser._zen_status_filter_patched then
        local orig_show_file = FileChooser.show_file
        FileChooser._zen_status_filter_patched = true

        function FileChooser:show_file(filename, fullpath)
            if self.name ~= "filemanager" then
                return orig_show_file(self, filename, fullpath)
            end

            local status_filter = FileChooser.show_filter and FileChooser.show_filter.status
            if not status_filter or fullpath == nil then
                return orig_show_file(self, filename, fullpath)
            end

            local saved_status_filter = FileChooser.show_filter.status
            FileChooser.show_filter.status = nil
            local ok_show, should_show = pcall(orig_show_file, self, filename, fullpath)
            FileChooser.show_filter.status = saved_status_filter
            if not ok_show or not should_show then
                return false
            end

            local effective_status = book_status.getEffectiveStatusFromFile(fullpath)
            return status_filter[effective_status] and true or false
        end
    end

    FileManager.setupLayout = function(self)
        orig_setupLayout(self)

        local file_chooser = self.file_chooser
        local file_manager = self
        local logger = require("logger")
        local ffiUtil_sel = require("ffi/util")

        local orig_showFileDialog = file_chooser.showFileDialog
        local orig_onFileSelect = file_chooser.onFileSelect

        local function resolveItemKey(item)
            if type(item) ~= "table" then return nil end
            return item.path or item.file or item.filepath
        end

        local function normalizeItemKey(key)
            if type(key) ~= "string" or key == "" then return nil end
            return ffiUtil_sel.realpath(key) or key
        end

        local function keysMatch(a, b, a_norm)
            if not a or not b then return false end
            if a == b then return true end
            local an = a_norm or normalizeItemKey(a)
            if not an then return false end
            local bn = normalizeItemKey(b)
            return bn and an == bn or false
        end

        local function findVisibleWidgetByKey(self_fc, item_key)
            local item_norm = normalizeItemKey(item_key)

            local layout = self_fc and self_fc.layout
            if type(layout) == "table" then
                for r, row in ipairs(layout) do
                    if type(row) == "table" then
                        for c, w in ipairs(row) do
                            local entry = w and w.entry
                            local entry_key = resolveItemKey(entry)
                            if keysMatch(item_key, entry_key, item_norm) then
                                return w, "layout", r, c
                            end
                        end
                    end
                end
            end

            local ig = self_fc and self_fc.item_group
            if ig then
                for i, w in ipairs(ig) do
                    local entry = w and w.entry
                    local entry_key = resolveItemKey(entry)
                    if keysMatch(item_key, entry_key, item_norm) then
                        return w, "item_group", i, nil
                    end
                    if type(w) == "table" then
                        for j, child in ipairs(w) do
                            local child_entry = child and child.entry
                            local child_key = resolveItemKey(child_entry)
                            if keysMatch(item_key, child_key, item_norm) then
                                return child, "item_group_nested", i, j
                            end
                        end
                    end
                end
            end

            return nil, nil, nil, nil
        end

        if type(orig_onFileSelect) == "function" then
            file_chooser.onFileSelect = function(self_fc, item)
                logger.dbg("zen-ui:context_menu:onFileSelect",
                    "select_mode=", tostring(file_manager.selected_files ~= nil),
                    "is_file=", tostring(item and item.is_file),
                    "path=", tostring(item and item.path),
                    "file=", tostring(item and item.file),
                    "filepath=", tostring(item and item.filepath),
                    "dim_before=", tostring(item and item.dim))

                if file_manager.selected_files then
                    local item_key = resolveItemKey(item)
                    if not item_key then
                        logger.dbg("zen-ui:context_menu:onFileSelect", "no item key, fallback to original")
                        return orig_onFileSelect(self_fc, item)
                    end

                    local widget, source, i1, i2 = findVisibleWidgetByKey(self_fc, item_key)
                    logger.dbg("zen-ui:context_menu:onFileSelect",
                        "item_key=", tostring(item_key),
                        "layout_rows=", tostring(self_fc and self_fc.layout and #self_fc.layout or 0),
                        "visible_items=", tostring(self_fc and self_fc.item_group and #self_fc.item_group or 0),
                        "matched_source=", tostring(source),
                        "idx1=", tostring(i1),
                        "idx2=", tostring(i2))

                    if not widget then
                        logger.dbg("zen-ui:context_menu:onFileSelect", "no visible match, fallback to original (single toggle)")
                        local ret = orig_onFileSelect(self_fc, item)
                        logger.dbg("zen-ui:context_menu:onFileSelect",
                            "fallback_return=", tostring(ret),
                            "dim_after_fallback=", tostring(item and item.dim),
                            "selected_after_fallback=", tostring(file_manager.selected_files[item_key]))
                        return ret
                    end

                    item.dim = not item.dim and true or nil
                    file_manager.selected_files[item_key] = item.dim
                    logger.dbg("zen-ui:context_menu:onFileSelect",
                        "dim_after=", tostring(item.dim),
                        "selected_entry=", tostring(file_manager.selected_files[item_key]))

                    local entry = widget.entry
                    if entry then
                        entry.dim = item.dim
                        local entry_key = resolveItemKey(entry)
                        if entry_key and entry_key ~= item_key then
                            file_manager.selected_files[entry_key] = item.dim
                        end
                    end
                    widget.dim = item.dim

                    local d = (widget[1] and widget[1].dimen) or widget.dimen
                    if d then
                        local dirty_owner = self_fc.show_parent or self_fc
                        UIManager:setDirty(dirty_owner, function()
                            return "ui", d, dirty_owner.dithered
                        end)
                    end
                    logger.dbg("zen-ui:context_menu:onFileSelect", "fast-path return true")
                    return true
                end
                local ret = orig_onFileSelect(self_fc, item)
                logger.dbg("zen-ui:context_menu:onFileSelect",
                    "not_in_select_mode_return=", tostring(ret),
                    "dim_after=", tostring(item and item.dim))
                return ret
            end
        end

        file_chooser.showSortOrderDialog = function(self_fc, opts)
            local UIManager_sod    = require("ui/uimanager")
            local ButtonDialog_sod = require("ui/widget/buttondialog")
            local _sod             = require("gettext")
            local cur_rev          = opts.current_reverse or false
            local order_dialog
            order_dialog = ButtonDialog_sod:new{
                title       = opts.title or _sod("Sort order"),
                title_align = "center",
                buttons     = {
                    {{
                        text     = "\u{F15D}  " .. _sod("Ascending") .. (not cur_rev and "  \u{2713}" or ""),
                        align    = "left",
                        enabled  = cur_rev,
                        callback = function()
                            UIManager_sod:close(order_dialog)
                            opts.on_select(false)
                        end,
                    }},
                    {{
                        text     = "\u{F15E}  " .. _sod("Descending") .. (cur_rev and "  \u{2713}" or ""),
                        align    = "left",
                        enabled  = not cur_rev,
                        callback = function()
                            UIManager_sod:close(order_dialog)
                            opts.on_select(true)
                        end,
                    }},
                },
            }
            UIManager_sod:show(order_dialog)
        end

        file_chooser.showFileDialog = function(self_fc, item)
            if item.is_go_up then return end

            if zen_plugin then
                local features = zen_plugin.config and zen_plugin.config.features
                local lc = zen_plugin.config and zen_plugin.config.lockdown
                if type(features) == "table" and features.lockdown_mode == true
                        and type(lc) == "table" and lc.disable_context_menu == true then
                    return  -- suppress context menu entirely in lockdown
                end
            end

            -- Group context menu (authors/series views)
            if item._zen_group_files then
                local group_files = item._zen_group_files
                local group_name  = item._zen_group_name or ""
                local sort_cb     = item._zen_sort_cb
                local display_cb  = item._zen_display_cb
                local Screen   = Device.screen
                local SizeR    = require("ui/size")
                local border   = SizeR.border.thin
                local gap      = Screen:scaleBySize(8)
                local dlg_w    = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
                local avail_w  = dlg_w - 2 * (SizeR.border.window + SizeR.padding.button)
                                        - 2 * (SizeR.padding.default + SizeR.margin.default)

                -- Calculate cover dimensions respecting uniform_cover_ratio
                local ratio = Cover.getRatio()
                local cover_max_h = Screen:scaleBySize(140)
                local cover_max_w = math.floor(cover_max_h * ratio)

                -- Build fake chooser for group files
                local fake_chooser = {
                    genItemTableFromPath = function()
                        local entries = {}
                        for _i, fpath in ipairs(group_files) do
                            table.insert(entries, { path = fpath, is_file = true })
                        end
                        return entries
                    end
                }

                -- Use unified makeCover for folder (gallery mode)
                local cover_widget = Cover.makeCover(group_name, fake_chooser, {
                    is_folder = true,
                    max_w = cover_max_w,
                    max_h = cover_max_h,
                    folder_name = group_name,
                })

                local framed_gallery = cover_widget or FrameContainer:new{
                    padding    = 0,
                    bordersize = border,
                    width      = cover_max_w + 2 * border,
                    height     = cover_max_h + 2 * border,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    CenterContainer:new{
                        dimen = Geom:new{ w = cover_max_w, h = cover_max_h },
                        VerticalSpan:new{ width = 1 },
                    },
                }

                -- Apply rounded corners
                local plug = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
                if plug and type(plug.config) == "table"
                    and type(plug.config.features) == "table"
                    and plug.config.features.browser_cover_rounded_corners == true then
                    local r = Screen:scaleBySize(6)
                    local r_inner = r - border
                    local orig_pt = framed_gallery.paintTo
                    framed_gallery.paintTo = function(frame_self, bb, x, y)
                        orig_pt(frame_self, bb, x, y)
                        if not (frame_self.dimen and frame_self.dimen.x) then return end
                        local tx, ty = frame_self.dimen.x, frame_self.dimen.y
                        local tw, th = frame_self.dimen.w, frame_self.dimen.h
                        local wh = Blitbuffer.COLOR_WHITE
                        local blk = Blitbuffer.COLOR_BLACK
                        for j = 0, r - 1 do
                            local inner = math.sqrt(r * r - (r - j) * (r - j))
                            local cut = math.ceil(r - inner)
                            if cut > 0 then
                                bb:paintRect(tx, ty + j, cut, 1, wh)
                                bb:paintRect(tx + tw - cut, ty + j, cut, 1, wh)
                                bb:paintRect(tx, ty + th - 1 - j, cut, 1, wh)
                                bb:paintRect(tx + tw - cut, ty + th - 1 - j, cut, 1, wh)
                            end
                        end
                        for j = 0, r - 1 do
                            for c = 0, r - 1 do
                                local dx, dy = r - c - 0.5, r - j - 0.5
                                local dist = math.sqrt(dx * dx + dy * dy)
                                if dist >= r_inner and dist <= r then
                                    bb:paintRect(tx + c, ty + j, 1, 1, blk)
                                    bb:paintRect(tx + tw - 1 - c, ty + j, 1, 1, blk)
                                    bb:paintRect(tx + c, ty + th - 1 - j, 1, 1, blk)
                                    bb:paintRect(tx + tw - 1 - c, ty + th - 1 - j, 1, 1, blk)
                                end
                            end
                        end
                    end
                end

                local framed_h = cover_max_h + 2 * border
                local text_col_w = math.max(avail_w - cover_max_w - 2 * border - gap, Screen:scaleBySize(60))
                local n_files = #group_files
                local subtitle = item._zen_group_subtitle
                    or (n_files == 1 and _("1 book") or (tostring(n_files) .. " " .. _("books")))
                local vstack = VerticalGroup:new{ align = "left" }
                table.insert(vstack, TextWidget:new{
                    text = BD.auto(group_name),
                    face = library_font.getFace(20),
                    bold = true,
                    max_width = text_col_w,
                })
                table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                table.insert(vstack, TextWidget:new{
                    text = subtitle,
                    face = library_font.getFace(17),
                    max_width = text_col_w,
                })

                local header_widget = LeftContainer:new{
                    dimen = Geom:new{ w = avail_w, h = framed_h },
                    HorizontalGroup:new{
                        align = "center",
                        framed_gallery,
                        HorizontalSpan:new{ width = gap },
                        vstack,
                    },
                }

                local buttons = {}
                if item._zen_prepend_buttons then
                    for _, row in ipairs(item._zen_prepend_buttons) do
                        table.insert(buttons, row)
                    end
                end
                if display_cb then
                    table.insert(buttons, {{
                        text = "\u{F06D0}  " .. _("Display") .. "  \u{25B8}",
                        align = "left",
                        callback = function()
                            UIManager:close(self_fc.file_dialog)
                            display_cb()
                        end,
                    }})
                end
                if sort_cb then
                    table.insert(buttons, {{
                        text = "\u{F04BF}  " .. _("Sort") .. "  \u{25B8}",
                        align = "left",
                        callback = function()
                            UIManager:close(self_fc.file_dialog)
                            sort_cb()
                        end,
                    }})
                end

                local function showGroupFilterDialog()
                    local cur_st = FileChooser.show_filter and FileChooser.show_filter.status
                    local is_all = cur_st == nil
                    local filter_dialog
                    local function setGlobalFilter(new_status)
                        if not FileChooser.show_filter then FileChooser.show_filter = {} end
                        FileChooser.show_filter.status = new_status
                        local gs = rawget(_G, "G_reader_settings")
                        if gs then
                            gs:saveSetting("show_filter", FileChooser.show_filter)
                            pcall(gs.flush, gs)
                        end
                        self_fc:refreshPath()
                        if item._zen_filter_refresh_cb then item._zen_filter_refresh_cb() end
                    end
                    local STATUS_OPTS = {
                        { key = "new", icon = icons.status, label = _("Unread") },
                        { key = "reading", icon = icons.reading, label = _("Reading") },
                        { key = "abandoned", icon = icons.tbr, label = _("To Be Read") },
                        { key = "complete", icon = icons.finished, label = _("Finished") },
                    }
                    local fbts = {}
                    table.insert(fbts, {{
                        text = _("All") .. (is_all and "  " .. icons.check or ""),
                        align = "left",
                        enabled = not is_all,
                        callback = function()
                            UIManager:close(filter_dialog)
                            setGlobalFilter(nil)
                        end,
                    }})
                    for _i, st in ipairs(STATUS_OPTS) do
                        local is_active = cur_st and cur_st[st.key] == true
                        table.insert(fbts, {{
                            text = st.icon .. "  " .. st.label
                                .. (is_active and "  " .. icons.check or ""),
                            align = "left",
                            callback = function()
                                UIManager:close(filter_dialog)
                                local new_st = {}
                                if cur_st then
                                    for _k, v in pairs(cur_st) do new_st[_k] = v end
                                end
                                if new_st[st.key] then new_st[st.key] = nil
                                else new_st[st.key] = true end
                                local n = 0
                                for _k, v in pairs(new_st) do if v then n = n + 1 end end
                                if n == 0 or n == 4 then setGlobalFilter(nil)
                                else setGlobalFilter(new_st) end
                                UIManager:nextTick(showGroupFilterDialog)
                            end,
                        }})
                    end
                    filter_dialog = ButtonDialog:new{
                        title = _("Filter by status"),
                        title_align = "center",
                        buttons = apply_button_group_font(fbts),
                    }
                    UIManager:show(filter_dialog)
                end

                if item._zen_is_folder_view then
                    local n_gf = 0
                    if FileChooser.show_filter and FileChooser.show_filter.status then
                        for _k, v in pairs(FileChooser.show_filter.status) do
                            if v then n_gf = n_gf + 1 end
                        end
                    end
                    table.insert(buttons, {{
                        text = icons.filter .. "  " .. _("Filter")
                            .. (n_gf > 0 and " (" .. n_gf .. ")" or "")
                            .. "  \u{25B8}",
                        align = "left",
                        callback = function()
                            UIManager:close(self_fc.file_dialog)
                            UIManager:nextTick(showGroupFilterDialog)
                        end,
                    }})
                end

                if item._zen_extra_buttons then
                    for _, row in ipairs(item._zen_extra_buttons) do
                        table.insert(buttons, row)
                    end
                end

                self_fc.file_dialog = ButtonDialog:new{
                    buttons = apply_button_group_font(buttons),
                    _added_widgets = { header_widget },
                }
                UIManager:show(self_fc.file_dialog)
                return true
            end

            local home_dir = paths.getHomeDir()
            local cur_path = self_fc.path or ""
            if home_dir and not item._zen_collection_name then
                if not paths.isInHomeDir(cur_path) then
                    return orig_showFileDialog(self_fc, item)
                end
            end

            local file               = item.path
            local is_file            = item.is_file
            local is_not_parent_folder = not item.is_go_up
            local is_home_dir = (not is_file) and paths.isHomeRoot(file)

            local function close_dialog()
                UIManager:close(self_fc.file_dialog)
            end

            local function refresh()
                UIManager:nextTick(function()
                    self_fc:refreshPath()
                end)
            end

            local dialog_title, dialog_cover_widget, book_description

            local function showCoverFullscreen(cover_path)
                local ok2, bim2 = pcall(require, "bookinfomanager")
                if not ok2 then return end
                local bi2 = bim2:getBookInfo(cover_path, true)
                if not bi2 or not bi2.cover_bb or not bi2.has_cover
                    or bi2.ignore_cover then return end
                local ImageViewer = require("ui/widget/imageviewer")
                local iv = ImageViewer:new{
                    image = bi2.cover_bb,
                    image_disposable = false,
                    fullscreen = true,
                    with_title_bar = false,
                }
                iv.onTap = function(iv_self)
                    iv_self:onClose()
                    return true
                end
                UIManager:show(iv)
            end

            do
                local Screen = Device.screen
                local SizeR = require("ui/size")
                local border = SizeR.border.thin
                local gap = Screen:scaleBySize(8)
                local dlg_w = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
                local avail_w = dlg_w - 2 * (SizeR.border.window + SizeR.padding.button)
                                       - 2 * (SizeR.padding.default + SizeR.margin.default)

                -- Calculate cover dimensions respecting uniform_cover_ratio
                local ratio = Cover.getRatio()
                local cover_max_h = Screen:scaleBySize(140)
                local cover_max_w = math.floor(cover_max_h * ratio)

                local function _zen_apply_rounded_cover(frame_widget, bsz)
                    local plug = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
                    if not (plug
                        and type(plug.config) == "table"
                        and type(plug.config.features) == "table"
                        and plug.config.features.browser_cover_rounded_corners == true)
                    then
                        return
                    end
                    local r = Screen:scaleBySize(6)
                    local r_inner = r - bsz
                    local orig_pt = frame_widget.paintTo
                    frame_widget.paintTo = function(frame_self, bb, x, y)
                        orig_pt(frame_self, bb, x, y)
                        if not (frame_self.dimen and frame_self.dimen.x) then return end
                        local tx, ty = frame_self.dimen.x, frame_self.dimen.y
                        local tw, th = frame_self.dimen.w, frame_self.dimen.h
                        local Blitbuffer_rc = require("ffi/blitbuffer")
                        local wh = Blitbuffer_rc.COLOR_WHITE
                        local blk = Blitbuffer_rc.COLOR_BLACK
                        for j = 0, r - 1 do
                            local inner = math.sqrt(r * r - (r - j) * (r - j))
                            local cut = math.ceil(r - inner)
                            if cut > 0 then
                                bb:paintRect(tx, ty + j, cut, 1, wh)
                                bb:paintRect(tx + tw - cut, ty + j, cut, 1, wh)
                                bb:paintRect(tx, ty + th - 1 - j, cut, 1, wh)
                                bb:paintRect(tx + tw - cut, ty + th - 1 - j, cut, 1, wh)
                            end
                        end
                        for j = 0, r - 1 do
                            for c = 0, r - 1 do
                                local dx = r - c - 0.5
                                local dy = r - j - 0.5
                                local dist = math.sqrt(dx * dx + dy * dy)
                                if dist >= r_inner and dist <= r then
                                    bb:paintRect(tx + c, ty + j, 1, 1, blk)
                                    bb:paintRect(tx + tw - 1 - c, ty + j, 1, 1, blk)
                                    bb:paintRect(tx + c, ty + th - 1 - j, 1, 1, blk)
                                    bb:paintRect(tx + tw - 1 - c, ty + th - 1 - j, 1, 1, blk)
                                end
                            end
                        end
                    end
                end

                local function makeSideBySide(cover_bb, src_w, src_h, sf, title_str, authors_str, series_str_arg, tags_str_arg, pages_str_arg, on_cover_tap)
                    local rendered_w = math.floor(src_w * sf)
                    local rendered_h = math.floor(src_h * sf)
                    local framed_h = rendered_h + 2 * border
                    local text_col_w = math.max(avail_w - rendered_w - 2 * border - gap,
                                                 Screen:scaleBySize(60))
                    local ImageWidget = require("ui/widget/imagewidget")
                    local fs_title = 20
                    local fs_authors = 17
                    local fs_tags = 14
                    local vstack = VerticalGroup:new{ align = "left" }
                    if title_str then
                        table.insert(vstack, TextWidget:new{
                            text = title_str,
                            face = library_font.getFace(fs_title),
                            bold = true,
                            max_width = text_col_w,
                        })
                    end
                    if authors_str then
                        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                        table.insert(vstack, TextWidget:new{
                            text = authors_str,
                            face = library_font.getFace(fs_authors),
                            max_width = text_col_w,
                        })
                    end
                    if series_str_arg then
                        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                        table.insert(vstack, TextWidget:new{
                            text = series_str_arg,
                            face = library_font.getFace(fs_authors),
                            fgcolor = Blitbuffer.COLOR_GRAY_3,
                            max_width = text_col_w,
                        })
                    end
                    if tags_str_arg and tags_str_arg ~= "" then
                        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(3) })
                        table.insert(vstack, TextWidget:new{
                            text = tags_str_arg,
                            face = library_font.getFace(fs_tags),
                            fgcolor = Blitbuffer.COLOR_GRAY_3,
                            max_width = text_col_w,
                        })
                    end
                    if pages_str_arg then
                        table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(3) })
                        table.insert(vstack, TextWidget:new{
                            text = pages_str_arg,
                            face = library_font.getFace(fs_tags),
                            fgcolor = Blitbuffer.COLOR_GRAY_3,
                            max_width = text_col_w,
                        })
                    end
                    local cover_frame = FrameContainer:new{
                        padding = 0,
                        bordersize = border,
                        ImageWidget:new{
                            image = cover_bb,
                            image_disposable = true,
                            scale_factor = sf,
                        },
                    }
                    _zen_apply_rounded_cover(cover_frame, border)
                    local cover_component
                    if on_cover_tap then
                        local InputContainer2 = require("ui/widget/container/inputcontainer")
                        local GestureRange2 = require("ui/gesturerange")
                        local cw = rendered_w + 2 * border
                        local wrapper = InputContainer2:new{
                            dimen = Geom:new{ w = cw, h = framed_h },
                            ges_events = {
                                TapCover = {
                                    GestureRange2:new{
                                        ges = "tap",
                                        range = Geom:new{
                                            x = 0, y = 0,
                                            w = Screen:getWidth(),
                                            h = Screen:getHeight(),
                                        },
                                    },
                                },
                            },
                        }
                        wrapper.onTapCover = function(wrapper_self, _arg, ges)
                            if not wrapper_self.dimen or not ges or not ges.pos then
                                return false
                            end
                            if not wrapper_self.dimen:contains(ges.pos) then
                                return false
                            end
                            on_cover_tap()
                            return true
                        end
                        wrapper[1] = cover_frame
                        cover_component = wrapper
                    else
                        cover_component = cover_frame
                    end
                    return LeftContainer:new{
                        dimen = Geom:new{ w = avail_w, h = framed_h },
                        HorizontalGroup:new{
                            align = "center",
                            cover_component,
                            HorizontalSpan:new{ width = gap },
                            vstack,
                        },
                    }
                end

                local pages_str
                if is_file then
                    local ok, BookInfoManager = pcall(require, "bookinfomanager")
                    local title_str, authors_str, tags_str_local, series_str_local
                    if ok then
                        local bookinfo = BookInfoManager:getBookInfo(file, true)
                        if bookinfo then
                            if not bookinfo.ignore_meta then
                                if bookinfo.title then
                                    title_str = BD.auto(bookinfo.title)
                                    authors_str = bookinfo.authors and BD.auto(bookinfo.authors:gsub("\n", ", ")) or nil
                                end
                                if bookinfo.series then
                                    local s = BD.auto(bookinfo.series)
                                    if bookinfo.series_index then
                                        series_str_local = string.format("#%.4g – %s", bookinfo.series_index, s)
                                    else
                                        series_str_local = s
                                    end
                                end
                                if bookinfo.keywords and bookinfo.keywords ~= "" then
                                    tags_str_local = bookinfo.keywords
                                        :gsub("%s*[\n;]%s*", ", ")
                                        :gsub("%s+\xC2\xB7%s+", ", ")
                                        :gsub("^,%s*", ""):gsub(",%s*$", "")
                                end
                                local n_pages = tonumber(bookinfo.pages)
                                if not (n_pages and n_pages > 0) then
                                    local ok_ds, DocSettings = pcall(require, "docsettings")
                                    if ok_ds then
                                        pcall(function()
                                            local ds = DocSettings:open(file)
                                            local p = tonumber(ds:readSetting("doc_pages"))
                                            if p and p > 0 then n_pages = p end
                                        end)
                                    end
                                end
                                if n_pages and n_pages > 0 then
                                    pages_str = n_pages .. " " .. _("pages")
                                end
                            end
                            if not bookinfo.ignore_meta and bookinfo.description
                                and bookinfo.description ~= "" then
                                book_description = bookinfo.description
                            end

                            -- Use unified makeCover for single book (with proper scaling)
                            local cover_bb, w, h = Cover.makeCover(file, nil, {
                                is_folder = false,
                                width = cover_max_w,
                                height = cover_max_h,
                            })

                            if cover_bb then
                                -- cover_bb is already scaled to target dimensions, so sf = 1.0
                                dialog_cover_widget = makeSideBySide(
                                    cover_bb, w, h, 1.0,
                                    title_str or BD.filename(file:match("([^/]+)$")),
                                    authors_str,
                                    series_str_local,
                                    tags_str_local,
                                    pages_str,
                                    function() showCoverFullscreen(file) end)
                            end
                        end
                    end
                    local text_str
                    if title_str then
                        text_str = title_str
                        if authors_str then text_str = text_str .. "\n" .. authors_str end
                        if series_str_local then text_str = text_str .. "\n" .. series_str_local end
                    end
                    dialog_title = text_str or BD.filename(file:match("([^/]+)$"))
                else
                    -- folder
                    local name = (file:match("([^/]+)/?$") or file):gsub("/$", "")
                    local folder_name_str = BD.directory(name)
                    local lfs = require("libs/libkoreader-lfs")
                    local DocReg = require("document/documentregistry")

                    -- Use real FileChooser so cover order/scope matches the browser
                    local _fm = require("apps/filemanager/filemanager")
                    local _cover_chooser = _fm.instance and _fm.instance.file_chooser
                    if not _cover_chooser then
                        -- Fallback: non-recursive immediate-dir listing
                        _cover_chooser = {
                            genItemTableFromPath = function(_, dir)
                                local entries = {}
                                local ok_d, it, obj = pcall(lfs.dir, dir)
                                if ok_d then
                                    for fname in it, obj do
                                        if fname ~= "." and fname ~= ".." then
                                            local fpath = dir .. "/" .. fname
                                            if lfs.attributes(fpath, "mode") == "file"
                                                    and DocReg:hasProvider(fpath) then
                                                table.insert(entries, { path = fpath, is_file = true })
                                            end
                                        end
                                    end
                                end
                                table.sort(entries, function(a, b) return (a.path or "") < (b.path or "") end)
                                return entries
                            end
                        }
                    end

                    -- Use unified makeCover for folder
                    local cover_widget = Cover.makeCover(file, _cover_chooser, {
                        is_folder = true,
                        max_w = cover_max_w,
                        max_h = cover_max_h,
                        folder_name = folder_name_str,
                    })

                 -- Apply rounded corners
                if cover_widget and _zen_apply_rounded_cover then
                    _zen_apply_rounded_cover(cover_widget, border)
                end

                    if cover_widget then
                        -- Count books recursively for the display label
                        local n_books = 0
                        local function _cnt(dir, depth)
                            if depth > 5 then return end
                            local ok_d, it, obj = pcall(lfs.dir, dir)
                            if not ok_d then return end
                            for fname in it, obj do
                                if fname ~= "." and fname ~= ".." and not fname:match("^%.") then
                                    local fpath = dir .. "/" .. fname
                                    local fmode = lfs.attributes(fpath, "mode")
                                    if fmode == "file" and DocReg:hasProvider(fpath) then
                                        n_books = n_books + 1
                                    elseif fmode == "directory" then
                                        _cnt(fpath, depth + 1)
                                    end
                                end
                            end
                        end
                        _cnt(file, 0)
                        local folder_count_str = n_books > 0
                            and (n_books == 1 and _("1 book") or (tostring(n_books) .. " " .. _("books")))
                            or nil
                        dialog_title = folder_count_str
                            and (folder_name_str .. "\n" .. folder_count_str)
                            or folder_name_str

                        local framed_h = cover_max_h + 2 * border
                        local text_col_w = math.max(avail_w - cover_max_w - 2 * border - gap, Screen:scaleBySize(60))
                        local vstack = VerticalGroup:new{ align = "left" }
                        table.insert(vstack, TextWidget:new{
                            text = folder_name_str,
                            face = library_font.getFace(20),
                            bold = true,
                            max_width = text_col_w,
                        })
                        if folder_count_str then
                            table.insert(vstack, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                            table.insert(vstack, TextWidget:new{
                                text = folder_count_str,
                                face = library_font.getFace(17),
                                max_width = text_col_w,
                            })
                        end

                        dialog_cover_widget = LeftContainer:new{
                            dimen = Geom:new{ w = avail_w, h = framed_h },
                            HorizontalGroup:new{
                                align = "center",
                                cover_widget,
                                HorizontalSpan:new{ width = gap },
                                vstack,
                            },
                        }
                    end
                end

                -- Placeholder cover (when no cover widget yet)
                if not dialog_cover_widget then
                    local Blitbuffer2 = require("ffi/blitbuffer")
                    local CenterContainer2 = require("ui/widget/container/centercontainer")
                    local FrameContainer2 = require("ui/widget/container/framecontainer")
                    local Geom2 = require("ui/geometry")
                    local HorizontalGroup2 = require("ui/widget/horizontalgroup")
                    local HorizontalSpan2 = require("ui/widget/horizontalspan")
                    local LeftContainer2 = require("ui/widget/container/leftcontainer")
                    local ImageWidget2 = require("ui/widget/imagewidget")
                    local TextWidget2 = require("ui/widget/textwidget")
                    local VerticalGroup2 = require("ui/widget/verticalgroup")
                    local VerticalSpan2 = require("ui/widget/verticalspan")

                    local ph_w = cover_max_w
                    local ph_h = math.floor(ph_w / ratio)  -- Respect ratio
                    local framed_h = ph_h + 2 * border

                    local final_bb = Cover.genCover(file, ph_w, ph_h)

                    local cover_img = ImageWidget2:new{
                        image = final_bb,
                        width = ph_w,
                        height = ph_h,
                    }

                    local ph_frame = FrameContainer2:new{
                        padding = 0,
                        bordersize = border,
                        width = ph_w + 2 * border,
                        height = ph_h + 2 * border,
                        background = Blitbuffer2.COLOR_WHITE,
                        CenterContainer2:new{
                            dimen = Geom2:new{ w = ph_w, h = ph_h },
                            cover_img,
                        },
                    }

                    local function apply_rounded(widget, bsz)
                        local plug = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
                        if not (plug and type(plug.config) == "table"
                            and type(plug.config.features) == "table"
                            and plug.config.features.browser_cover_rounded_corners == true)
                        then
                            return
                        end
                        local r = Screen:scaleBySize(6)
                        local r_inner = r - bsz
                        local orig_pt = widget.paintTo
                        widget.paintTo = function(widget_self, bb, x, y)
                            orig_pt(widget_self, bb, x, y)
                            if not (widget_self.dimen and widget_self.dimen.x) then return end
                            local tx, ty = widget_self.dimen.x, widget_self.dimen.y
                            local tw, th = widget_self.dimen.w, widget_self.dimen.h
                            local wh = Blitbuffer2.COLOR_WHITE
                            local blk = Blitbuffer2.COLOR_BLACK
                            for j = 0, r - 1 do
                                local inner = math.sqrt(r * r - (r - j) * (r - j))
                                local cut = math.ceil(r - inner)
                                if cut > 0 then
                                    bb:paintRect(tx, ty + j, cut, 1, wh)
                                    bb:paintRect(tx + tw - cut, ty + j, cut, 1, wh)
                                    bb:paintRect(tx, ty + th - 1 - j, cut, 1, wh)
                                    bb:paintRect(tx + tw - cut, ty + th - 1 - j, cut, 1, wh)
                                end
                            end
                            for j = 0, r - 1 do
                                for c = 0, r - 1 do
                                    local dx = r - c - 0.5
                                    local dy = r - j - 0.5
                                    local dist = math.sqrt(dx * dx + dy * dy)
                                    if dist >= r_inner and dist <= r then
                                        bb:paintRect(tx + c, ty + j, 1, 1, blk)
                                        bb:paintRect(tx + tw - 1 - c, ty + j, 1, 1, blk)
                                        bb:paintRect(tx + c, ty + th - 1 - j, 1, 1, blk)
                                        bb:paintRect(tx + tw - 1 - c, ty + th - 1 - j, 1, 1, blk)
                                    end
                                end
                            end
                        end
                    end
                    apply_rounded(ph_frame, border)

                    local text_col_w = math.max(
                        avail_w - ph_w - 2 * border - gap,
                        Screen:scaleBySize(60))
                    local vstack = VerticalGroup2:new{ align = "left" }

                    local title_line, sub_line = dialog_title, nil
                    if dialog_title then
                        local nl = dialog_title:find("\n")
                        if nl then
                            title_line = dialog_title:sub(1, nl - 1)
                            sub_line = dialog_title:sub(nl + 1)
                        end
                    end

                    if title_line then
                        table.insert(vstack, TextWidget2:new{
                            text = title_line,
                            face = library_font.getFace(20),
                            bold = true,
                            max_width = text_col_w,
                        })
                    end
                    if sub_line then
                        table.insert(vstack, VerticalSpan2:new{ width = Screen:scaleBySize(2) })
                        table.insert(vstack, TextWidget2:new{
                            text = sub_line,
                            face = library_font.getFace(17),
                            max_width = text_col_w,
                        })
                    end
                    if pages_str then
                        table.insert(vstack, VerticalSpan2:new{ width = Screen:scaleBySize(3) })
                        table.insert(vstack, TextWidget2:new{
                            text = pages_str,
                            face = library_font.getFace(14),
                            fgcolor = Blitbuffer2.COLOR_GRAY_3,
                            max_width = text_col_w,
                        })
                    end

                    dialog_cover_widget = LeftContainer2:new{
                        dimen = Geom2:new{ w = avail_w, h = framed_h },
                        HorizontalGroup2:new{
                            align = "center",
                            ph_frame,
                            HorizontalSpan2:new{ width = gap },
                            vstack,
                        },
                    }
                end
            end

            -- Edit submenu (unchanged)
            local function showEditSubmenu()
                close_dialog()
                local edit_dialog

                if is_home_dir then
                    edit_dialog = ButtonDialog:new{
                        buttons = apply_button_group_font({
                            {{
                                text = "\u{F0192}  " .. C_("File", "Paste"),
                                align = "left",
                                enabled = file_manager.clipboard and true or false,
                                callback = function()
                                    UIManager:close(edit_dialog)
                                    file_manager:pasteFileFromClipboard(file)
                                end,
                            }},
                        }),
                    }
                    UIManager:show(edit_dialog)
                    return
                end

                local edit_buttons = {
                    {
                        {
                            text = "\u{F0190}  " .. _("Cut"),
                            align = "left",
                            enabled = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:cutFile(file)
                            end,
                        },
                    },
                    {
                        {
                            text = "\u{F018F}  " .. C_("File", "Copy"),
                            align = "left",
                            enabled = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:copyFile(file)
                            end,
                        },
                    },
                    {
                        {
                            text = "\u{F0192}  " .. C_("File", "Paste"),
                            align = "left",
                            enabled = file_manager.clipboard and true or false,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:pasteFileFromClipboard(file)
                            end,
                        },
                    },
                }
                if not item._zen_collection_name and not item._zen_disable_select then
                    table.insert(edit_buttons, 1, {
                        {
                            text = "\u{F0489}  " .. _("Select"),
                            align = "left",
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:onToggleSelectMode()
                                if is_file and type(self_fc.onFileSelect) == "function" then
                                    self_fc:onFileSelect(item)
                                end
                            end,
                        },
                    })
                end
                if is_file then
                    table.insert(edit_buttons, {
                        {
                            text = icons.refresh .. "  " .. _("Refresh"),
                            align = "left",
                            callback = function()
                                UIManager:close(edit_dialog)
                                local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
                                if ok_bim then
                                    BookInfoManager:deleteBookInfo(file)
                                    if self_fc.filemanager_menu then
                                        self_fc.filemanager_menu.files_updated = true
                                    end
                                    refresh()
                                end
                            end,
                        },
                    })
                end

                local allow_delete = zen_plugin
                    and type(zen_plugin.config) == "table"
                    and type(zen_plugin.config.context_menu) == "table"
                    and zen_plugin.config.context_menu.allow_delete == true
                if allow_delete then
                    table.insert(edit_buttons, {
                        {
                            text = "\u{F0156}  " .. _("Delete"),
                            align = "left",
                            enabled = is_not_parent_folder,
                            callback = function()
                                UIManager:close(edit_dialog)
                                file_manager:showDeleteFileDialog(file, refresh)
                            end,
                        },
                    })
                end

                edit_dialog = ButtonDialog:new{
                    buttons = apply_button_group_font(edit_buttons),
                }
                UIManager:show(edit_dialog)
            end

            -- Main dialog buttons
            local buttons = {}

            if is_file and is_not_parent_folder then
                table.insert(buttons, {
                    {
                        text = "\u{F02FD}  " .. _("Details"),
                        align = "left",
                        callback = function()
                            close_dialog()
                            local util = require("util")
                            local TextViewer = require("ui/widget/textviewer")
                            local desc_text = book_description
                                and util.htmlToPlainTextIfHtml(book_description)
                                or _("No description.")
                            local tv
                            tv = TextViewer:new{
                                title = _("Description"),
                                title_face = get_title_face_for_textviewer(),
                                text = desc_text,
                                text_type = "book_info",
                                buttons_table = {
                                    {{
                                        text = "\u{F02FD} " .. _("Book information"),
                                        font_face = library_font.getFontName(),
                                        callback = function()
                                            UIManager:close(tv)
                                            file_manager.bookinfo:show(file)
                                        end,
                                    }},
                                },
                            }
                            apply_textviewer_body_font_family(tv)
                            UIManager:show(tv)
                        end,
                    },
                })
            end

            if not is_file and is_not_parent_folder and not is_home_dir then
                table.insert(buttons, {
                    {
                        text = "\u{F0CB6}  " .. _("Rename"),
                        align = "left",
                        callback = function()
                            close_dialog()
                            file_manager:showRenameFileDialog(file, is_file)
                        end,
                    },
                })
            end

            if item._is_current_dir then
                table.insert(buttons, {
                    {
                        text = "\u{F0B9D}  " .. _("New folder"),
                        align = "left",
                        callback = function()
                            close_dialog()
                            file_manager:createFolder()
                        end,
                    },
                })
            end

            if is_file and is_not_parent_folder then
                table.insert(buttons, {
                    {
                        text = "\u{F01BE}  " .. _("Move"),
                        align = "left",
                        callback = function()
                            close_dialog()
                            local ffiUtil = require("ffi/util")
                            local DocSettings = require("docsettings")
                            local ReadHistory = require("readhistory")
                            local ReadCollection = require("readcollection")
                            local lfs = require("libs/libkoreader-lfs")
                            local src = ffiUtil.realpath(file)
                            if not src then return end
                            local move_home_dir = paths.getHomeDir()
                                or file_chooser.path
                            if not move_home_dir then return end
                            local src_dir = ffiUtil.realpath(ffiUtil.dirname(src))
                            local _g = rawget(_G, "G_reader_settings")
                            local _zen_cfg = _g and _g:readSetting("zen_ui_config")
                            local _extra = type(_zen_cfg) == "table"
                                and type(_zen_cfg.additional_home_dirs) == "table"
                                and _zen_cfg.additional_home_dirs or nil
                            local chooser = MoveChooser:new{
                                select_directory = true,
                                select_file = false,
                                show_files = true,
                                title = _("Move to…"),
                                path = move_home_dir,
                                src_dir = src_dir,
                                extra_roots = _extra,
                                onConfirm = function(dest_dir_real)
                                    local name = ffiUtil.basename(src)
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
                                            local ok_bim2, bim2 = pcall(require, "bookinfomanager")
                                            if ok_bim2 and bim2 then
                                                local new_dir = ffiUtil.realpath(dest_dir_real)
                                                if new_dir then
                                                    pcall(bim2.setBookInfoProperties, bim2, src,
                                                        { directory = new_dir .. "/" })
                                                end
                                            end
                                        else
                                            ReadHistory:updateItemsByPath(src, dest_file)
                                            ReadCollection:updateItemsByPath(src, dest_file)
                                        end
                                        local real_cur = ffiUtil.realpath(file_chooser.path)
                                        local real_home = ffiUtil.realpath(home_dir)
                                        local at_home = real_cur == real_home
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

                if item._zen_collection_name then
                    local coll_name = item._zen_collection_name
                    table.insert(buttons, {
                        {
                            text = "\u{F04D2}  " .. _("Remove from collection"),
                            align = "left",
                            callback = function()
                                close_dialog()
                                ReadCollection:removeItem(file, coll_name)
                                ReadCollection:write({ [coll_name] = true })
                                if item._zen_collection_refresh then
                                    UIManager:nextTick(item._zen_collection_refresh)
                                end
                            end,
                        },
                    })
                end

                if not item._zen_collection_name then
                    table.insert(buttons, {
                        {
                            text = "\u{F04CE}  " .. _("Add to collection") .. "  \u{25B6}",
                            align = "left",
                            callback = function()
                                close_dialog()
                                local Menu_cp = require("ui/widget/menu")
                                local default_coll = ReadCollection.default_collection_name
                                local all_colls = {}
                                for cn, _v in pairs(ReadCollection.coll) do
                                    table.insert(all_colls, cn)
                                end
                                table.sort(all_colls, function(a, b)
                                    if a == default_coll then return true end
                                    if b == default_coll then return false end
                                    return a < b
                                end)
                                local items = {}
                                for _i, cn in ipairs(all_colls) do
                                    local display = cn == default_coll and _("Favorites") or cn
                                    local already_in = ReadCollection:isFileInCollection(file, cn)
                                    table.insert(items, {
                                        text = display .. (already_in and "  \u{2713}" or ""),
                                        mandatory = already_in and _("added") or nil,
                                        dim = already_in,
                                        _cn = cn,
                                    })
                                end
                                local coll_picker
                                coll_picker = Menu_cp:new{
                                    title = _("Add to collection"),
                                    item_table = items,
                                    is_borderless = true,
                                    is_popout = false,
                                    onMenuSelect = function(self_m, item_m)
                                        if item_m.dim then return true end
                                        UIManager:close(coll_picker)
                                        ReadCollection:addItem(file, item_m._cn)
                                        ReadCollection:write({ [item_m._cn] = true })
                                        return true
                                    end,
                                    close_callback = function()
                                        UIManager:close(coll_picker)
                                    end,
                                }
                                UIManager:show(coll_picker)
                            end,
                        },
                    })
                end
            end

            if is_file and is_not_parent_folder then
                table.insert(buttons, {
                    {
                        text = "\u{F0B64}  " .. _("Read status") .. "  ▶",
                        align = "left",
                        callback = function()
                            close_dialog()
                            local filemanagerutil = require("apps/filemanager/filemanagerutil")
                            local BookList = require("ui/widget/booklist")
                            local DocSettings = require("docsettings")
                            local doc_settings = DocSettings:open(file)
                            local summary = doc_settings:readSetting("summary") or {}
                            local current_status = summary.status
                            local is_unread = not current_status or current_status == ""
                            local status_dialog

                            local function setStatus(to_status)
                                if to_status == nil then
                                    summary.status = nil
                                    doc_settings:delSetting("percent_finished")
                                    doc_settings:delSetting("last_page")
                                    doc_settings:delSetting("last_xpointer")
                                else
                                    summary.status = to_status
                                end
                                filemanagerutil.saveSummary(doc_settings, summary)
                                BookList.setBookInfoCacheProperty(file, "status", to_status)
                                if to_status == nil then
                                    -- Snapshot pages before reset: setBookInfoCacheProperty("been_opened", false)
                                    -- replaces the whole cache entry with {been_opened=false}, losing pages.
                                    local saved_pages = BookList.book_info_cache
                                        and BookList.book_info_cache[file]
                                        and BookList.book_info_cache[file].pages
                                    BookList.setBookInfoCacheProperty(file, "been_opened", false)
                                    if saved_pages then
                                        BookList.book_info_cache[file].pages = saved_pages
                                    end
                                end
                                UIManager:close(status_dialog)
                                refresh()
                            end

                            local function statusBtn(icon, label, to_status)
                                local is_cur = (to_status == nil and is_unread)
                                    or (to_status ~= nil and current_status == to_status)
                                return {{
                                    text = icon .. "  " .. label .. (is_cur and "  \u{2713}" or ""),
                                    align = "left",
                                    enabled = not is_cur,
                                    callback = function() setStatus(to_status) end,
                                }}
                            end

                            status_dialog = ButtonDialog:new{
                                title = _("Read status"),
                                title_align = "center",
                                buttons = apply_button_group_font({
                                    statusBtn("\u{F0B64}", _("Unread"), nil),
                                    statusBtn("\u{F0B63}", _("Reading"), "reading"),
                                    statusBtn("\u{F0150}", _("To Be Read"), "abandoned"),
                                    statusBtn("\u{F012C}", _("Finished"), "complete"),
                                }),
                            }
                            UIManager:show(status_dialog)
                        end,
                    },
                })
            end

            if item._is_current_dir then
                local function showViewSubmenu()
                    close_dialog()
                    local ok_fm, FM = pcall(require, "apps/filemanager/filemanager")
                    local fm = ok_fm and FM and FM.instance
                    local ok_bim, bim = pcall(require, "bookinfomanager")
                    local cur_mode
                    if ok_bim and bim then
                        local ok3, m = pcall(function()
                            return bim:getSetting("filemanager_display_mode")
                        end)
                        if ok3 then cur_mode = m end
                    end
                    local function apply_mode(mode)
                        if fm and type(fm.onSetDisplayMode) == "function" then
                            pcall(fm.onSetDisplayMode, fm, mode)
                        elseif ok_bim and bim then
                            pcall(bim.saveSetting, bim, "filemanager_display_mode", mode)
                        end
                    end
                    local view_dialog
                    local function viewBtn(label, icon, mode)
                        local active = cur_mode == mode
                        return {{
                            text = icon .. "  " .. label .. (active and "  \u{2713}" or ""),
                            align = "left",
                            enabled = not active,
                            callback = function()
                                UIManager:close(view_dialog)
                                apply_mode(mode)
                            end,
                        }}
                    end
                    view_dialog = ButtonDialog:new{
                        title = _("Display mode"),
                        title_align = "center",
                        buttons = apply_button_group_font({
                            viewBtn(_("Mosaic"), "\u{F11D9}", "mosaic_image"),
                            viewBtn(_("List (detailed)"), "\u{F148B}", "list_image_meta"),
                            viewBtn(_("List (basic)"), "\u{F0279}", "list_image_filename"),
                        }),
                    }
                    UIManager:show(view_dialog)
                end

                table.insert(buttons, {
                    {
                        text = "\u{F06D0}  " .. _("Display") .. "  ▶",
                        align = "left",
                        callback = showViewSubmenu,
                    },
                })
            end

            if not is_file and is_not_parent_folder then
                local SORT_OPTIONS = {
                    { key = "title", text = "\u{F04BB}  " .. _("Title") },
                    { key = "authors", text = "\u{F0013}  " .. _("Authors") },
                    { key = "series", text = "\u{F0436}  " .. _("Series") },
                    { key = "access", text = "\u{F02DA}  " .. _("Recently read") },
                }

                if is_home_dir then
                    local g_sort = rawget(_G, "G_reader_settings")
                    if g_sort then
                        table.insert(buttons, {
                            {
                                text = "\u{F04BF}  " .. _("Sort library") .. "  ▶",
                                align = "left",
                                callback = function()
                                    close_dialog()
                                    local sort_dialog
                                    local sort_buttons = {}
                                    local cur = g_sort:readSetting("collate", "strcoll")
                                    local cur_reverse = g_sort:isTrue("reverse_collate")
                                    if cur == "strcoll" then cur = "title" end
                                    for _, opt in ipairs(SORT_OPTIONS) do
                                        local is_active = cur == opt.key
                                        table.insert(sort_buttons, {{
                                            text = opt.text .. (is_active and "  \u{2713}" or ""),
                                            align = "left",
                                            enabled = not is_active,
                                            callback = function()
                                                g_sort:saveSetting("collate", opt.key)
                                                UIManager:close(sort_dialog)
                                                self_fc:refreshPath()
                                            end,
                                        }})
                                    end
                                    table.insert(sort_buttons, {{
                                        text = "\u{F04BF}  " .. _("Order") .. "  ▶",
                                        align = "left",
                                        callback = function()
                                            UIManager:close(sort_dialog)
                                            self_fc:showSortOrderDialog({
                                                current_reverse = cur_reverse,
                                                on_select = function(reverse)
                                                    if reverse then
                                                        g_sort:saveSetting("reverse_collate", true)
                                                    else
                                                        g_sort:delSetting("reverse_collate")
                                                    end
                                                    self_fc:refreshPath()
                                                end,
                                            })
                                        end,
                                    }})
                                    sort_dialog = ButtonDialog:new{
                                        title = _("Sort library by"),
                                        title_align = "center",
                                        buttons = apply_button_group_font(sort_buttons),
                                    }
                                    UIManager:show(sort_dialog)
                                end,
                            },
                        })
                    end
                else
                    local fsd_api = rawget(_G, "__ZEN_FOLDER_SORT")
                    if fsd_api then
                        local ffiUtil_fsd = require("ffi/util")
                        local real_folder = ffiUtil_fsd.realpath(file) or file

                        table.insert(buttons, {
                            {
                                text = "\u{F04BF}  " .. _("Sort folder") .. "  ▶",
                                align = "left",
                                callback = function()
                                    close_dialog()
                                    local sort_dialog
                                    local sort_buttons = {}
                                    local current_override = fsd_api.get(real_folder)
                                    local cur_collate = current_override and current_override.collate
                                    local cur_reverse = current_override and current_override.reverse or false
                                    for _, opt in ipairs(SORT_OPTIONS) do
                                        local is_active = cur_collate == opt.key
                                        table.insert(sort_buttons, {{
                                            text = opt.text .. (is_active and "  \u{2713}" or ""),
                                            align = "left",
                                            enabled = not is_active,
                                            callback = function()
                                                fsd_api.set(real_folder, opt.key, cur_reverse)
                                                UIManager:close(sort_dialog)
                                                self_fc:refreshPath()
                                            end,
                                        }})
                                    end
                                    table.insert(sort_buttons, {{
                                        text = "\u{F04BF}  " .. _("Order") .. "  ▶",
                                        align = "left",
                                        callback = function()
                                            UIManager:close(sort_dialog)
                                            self_fc:showSortOrderDialog({
                                                current_reverse = cur_reverse,
                                                on_select = function(reverse)
                                                    if cur_collate then
                                                        fsd_api.set(real_folder, cur_collate, reverse)
                                                        self_fc:refreshPath()
                                                    end
                                                end,
                                            })
                                        end,
                                    }})
                                    if current_override then
                                        table.insert(sort_buttons, {})
                                        table.insert(sort_buttons, {{
                                            text = "\u{F099B}  " .. _("Clear"),
                                            align = "left",
                                            callback = function()
                                                fsd_api.clear(real_folder)
                                                UIManager:close(sort_dialog)
                                                self_fc:refreshPath()
                                            end,
                                        }})
                                    end
                                    sort_dialog = ButtonDialog:new{
                                        title = _("Sort folder by"),
                                        title_align = "center",
                                        buttons = apply_button_group_font(sort_buttons),
                                    }
                                    UIManager:show(sort_dialog)
                                end,
                            },
                        })
                    end
                end
            end

            if item._is_current_dir then
                local function showFilterDialog()
                    local cur_st = FileChooser.show_filter and FileChooser.show_filter.status
                    local is_all = cur_st == nil
                    local filter_dialog

                    local function setFilter(new_status)
                        FileChooser.show_filter.status = new_status
                        local gs = rawget(_G, "G_reader_settings")
                        if gs then
                            gs:saveSetting("show_filter", FileChooser.show_filter)
                            pcall(gs.flush, gs)
                        end
                        self_fc:refreshPath()
                    end

                    local STATUS_OPTS = {
                        { key = "new", icon = icons.status, label = _("Unread") },
                        { key = "reading", icon = icons.reading, label = _("Reading") },
                        { key = "abandoned", icon = icons.tbr, label = _("To Be Read") },
                        { key = "complete", icon = icons.finished, label = _("Finished") },
                    }

                    local fbts = {}
                    table.insert(fbts, {{
                        text = _("All") .. (is_all and "  " .. icons.check or ""),
                        align = "left",
                        enabled = not is_all,
                        callback = function()
                            UIManager:close(filter_dialog)
                            setFilter(nil)
                        end,
                    }})
                    for _, st in ipairs(STATUS_OPTS) do
                        local is_active = cur_st and cur_st[st.key] == true
                        table.insert(fbts, {{
                            text = st.icon .. "  " .. st.label .. (is_active and "  " .. icons.check or ""),
                            align = "left",
                            callback = function()
                                UIManager:close(filter_dialog)
                                local new_st = {}
                                if cur_st then
                                    for k, v in pairs(cur_st) do new_st[k] = v end
                                end
                                if new_st[st.key] then
                                    new_st[st.key] = nil
                                else
                                    new_st[st.key] = true
                                end
                                local n = 0
                                for _, v in pairs(new_st) do if v then n = n + 1 end end
                                if n == 0 or n == 4 then setFilter(nil)
                                else setFilter(new_st) end
                                UIManager:nextTick(showFilterDialog)
                            end,
                        }})
                    end

                    filter_dialog = ButtonDialog:new{
                        title = _("Filter by status"),
                        title_align = "center",
                        buttons = apply_button_group_font(fbts),
                    }
                    UIManager:show(filter_dialog)
                end

                local n_active = 0
                if FileChooser.show_filter and FileChooser.show_filter.status then
                    for _, v in pairs(FileChooser.show_filter.status) do
                        if v then n_active = n_active + 1 end
                    end
                end
                table.insert(buttons, {
                    {
                        text = icons.filter .. "  " .. _("Filter")
                            .. (n_active > 0 and " (" .. n_active .. ")" or "")
                            .. "  ▶",
                        align = "left",
                        callback = function()
                            close_dialog()
                            UIManager:nextTick(showFilterDialog)
                        end,
                    },
                })
            end

            table.insert(buttons, {
                {
                    text = "\u{F090C}  " .. _("Edit") .. "  ▶",
                    align = "left",
                    callback = showEditSubmenu,
                },
            })

            if item._zen_extra_buttons then
                for _, row in ipairs(item._zen_extra_buttons) do
                    table.insert(buttons, row)
                end
            end

            local dlg_title = dialog_cover_widget and "" or dialog_title
            self_fc.file_dialog = ButtonDialog:new{
                title = dlg_title ~= "" and dlg_title or nil,
                title_align = "center",
                buttons = apply_button_group_font(buttons),
                _added_widgets = dialog_cover_widget and { dialog_cover_widget } or nil,
            }
            UIManager:show(self_fc.file_dialog)
            return true
        end

        if Device:isTouchDevice() then
            local GestureRange_bh = require("ui/gesturerange")
            local Geom_bh = require("ui/geometry")
            if not file_chooser.ges_events then
                file_chooser.ges_events = {}
            end
            file_chooser.ges_events.ZenBlankHold = {
                GestureRange_bh:new{
                    ges = "hold",
                    range = Geom_bh:new{
                        x = 0, y = 0,
                        w = Device.screen:getWidth(),
                        h = Device.screen:getHeight(),
                    },
                },
            }
            file_chooser.onZenBlankHold = function(fc, arg, ges)
                local home_dir_bh = paths.getHomeDir()
                local cur_path_bh = fc.path or ""
                if home_dir_bh then
                    if not paths.isInHomeDir(cur_path_bh) then return false end
                end
                local ffiUtil_bh = require("ffi/util")
                local cur_real = ffiUtil_bh.realpath(cur_path_bh) or cur_path_bh
                fc:showFileDialog({
                    path = cur_real,
                    is_file = false,
                    is_go_up = false,
                    text = ffiUtil_bh.basename(cur_real),
                    bidi_wrap_func = BD.directory,
                    _is_current_dir = true,
                })
                return true
            end
        end
    end
end

return apply_context_menu

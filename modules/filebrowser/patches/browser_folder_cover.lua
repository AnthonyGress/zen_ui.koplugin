local function apply_browser_folder_cover()
    local AlphaContainer = require("ui/widget/container/alphacontainer")
    local BD = require("ui/bidi")
    local Blitbuffer = require("ffi/blitbuffer")
    local BottomContainer = require("ui/widget/container/bottomcontainer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local FileChooser = require("ui/widget/filechooser")
    local Font = require("ui/font")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local ImageWidget = require("ui/widget/imagewidget")
    local LeftContainer = require("ui/widget/container/leftcontainer")
    local LineWidget = require("ui/widget/linewidget")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local Size = require("ui/size")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local TopContainer = require("ui/widget/container/topcontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local lfs = require("libs/libkoreader-lfs")
    local util = require("util")

    local _ = require("gettext")
    local Screen = Device.screen

    local FolderCover = {
        name = ".cover",
        exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
    }

    local function findCover(dir_path)
        local path = dir_path .. "/" .. FolderCover.name
        for _, ext in ipairs(FolderCover.exts) do
            local fname = path .. ext
            if util.fileExists(fname) then return fname end
        end
    end

    local function getMenuItem(menu, ...) -- path
        local function findItem(sub_items, texts)
            local find = {}
            local texts = type(texts) == "table" and texts or { texts }
            -- stylua: ignore
            for _, text in ipairs(texts) do find[text] = true end
            for _, item in ipairs(sub_items) do
                local text = item.text or (item.text_func and item.text_func())
                if text and find[text] then return item end
            end
        end

        local sub_items, item
        for _, texts in ipairs { ... } do -- walk path
            sub_items = (item or menu).sub_item_table
            if not sub_items then return end
            item = findItem(sub_items, texts)
            if not item then return end
        end
        return item
    end

    local function toKey(...)
        local keys = {}
        for _, key in pairs { ... } do
            if type(key) == "table" then
                table.insert(keys, "table")
                for k, v in pairs(key) do
                    table.insert(keys, tostring(k))
                    table.insert(keys, tostring(v))
                end
            else
                table.insert(keys, tostring(key))
            end
        end
        return table.concat(keys, "")
    end

    local orig_FileChooser_getListItem = FileChooser.getListItem
    local cached_list = {}

    function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
        -- For directory items under a time-based collate ("last read date" / "date modified"),
        -- skip the cache and compute the sort key as the maximum access/modification time
        -- among files directly inside the folder.  A folder's own filesystem atime is NOT
        -- updated when a book inside it is read, so without this the folder would never move
        -- to the front of a "most recently read" list.
        if attributes.mode == "directory" and collate
                and collate.can_collate_mixed and collate.mandatory_func and not collate.item_func then
            local item = orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
            local ok, iter, dir_obj = pcall(lfs.dir, fullpath)
            if ok then
                local max_access = attributes.access or 0
                local max_modification = attributes.modification or 0
                for fname in iter, dir_obj do
                    if fname ~= "." and fname ~= ".." then
                        local fattr = lfs.attributes(fullpath .. "/" .. fname)
                        if fattr and fattr.mode == "file" then
                            if fattr.access > max_access then
                                max_access = fattr.access
                            end
                            if fattr.modification > max_modification then
                                max_modification = fattr.modification
                            end
                        end
                    end
                end
                local new_attr = {}
                for k, v in pairs(attributes) do new_attr[k] = v end
                new_attr.access = max_access
                new_attr.modification = max_modification
                item.attr = new_attr
            end
            return item
        end
        local key = toKey(dirpath, f, fullpath, attributes, collate, self.show_filter.status)
        cached_list[key] = cached_list[key] or orig_FileChooser_getListItem(self, dirpath, f, fullpath, attributes, collate)
        return cached_list[key]
    end

    -- Invalidate the list-item cache whenever the file chooser rescans a directory
    -- (non-dummy call).  Without this the cache grows unbounded across all
    -- directories visited during a session.
    local orig_FileChooser_genItemTableFromPath = FileChooser.genItemTableFromPath

    function FileChooser:genItemTableFromPath(path)
        if not self._dummy then
            cached_list = {}
        end
        return orig_FileChooser_genItemTableFromPath(self, path)
    end

    local function capitalize(sentence)
        local words = {}
        for word in sentence:gmatch("%S+") do
            table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
        end
        return table.concat(words, " ")
    end

    local Folder = {
        edge = {
            thick = Screen:scaleBySize(2.5),
            margin = Size.line.medium,
            color = Blitbuffer.COLOR_GRAY_4,
            width = 0.97,
        },
        face = {
            border_size = Size.border.thin,
            alpha = 0.75,
            nb_items_font_size = 15,
            nb_items_badge_size = Screen:scaleBySize(22),  -- fixed circle diameter
            nb_items_offset = Screen:scaleBySize(5),       -- push badge down from top edge
            dir_max_font_size = 25,
        },
    }

    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then
            return nil
        end
        for i = 1, 64 do
            local upname, value = debug.getupvalue(fn, i)
            if not upname then
                break
            end
            if upname == name then
                return value
            end
        end
    end

    local function patchCoverBrowser(plugin)
        local MosaicMenu = require("mosaicmenu")
        local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
        if not MosaicMenuItem then return end -- Protect against remnants of project title
        local BookInfoManager = get_upvalue(MosaicMenuItem.update, "BookInfoManager")
        local original_update = MosaicMenuItem.update

        -- setting
        function BooleanSetting(text, name, default)
            local self = { text = text }
            self.get = function()
                local setting = BookInfoManager:getSetting(name)
                if default then return not setting end -- false is stored as nil, so we need or own logic for boolean default
                return setting
            end
            self.toggle = function() return BookInfoManager:toggleSetting(name) end
            return self
        end

        local settings = {
            crop_to_fit = BooleanSetting(_("Crop folder custom image"), "folder_crop_custom_image", true),
            name_centered = BooleanSetting(_("Folder name centered"), "folder_name_centered", true),
            show_folder_name = BooleanSetting(_("Show folder name"), "folder_name_show", true),
        }

        -- cover item
        function MosaicMenuItem:update(...)
            original_update(self, ...)
            if self._foldercover_processed or self.menu.no_refresh_covers or not self.do_cover_image then return end

            if self.entry.is_file or self.entry.file or not self.mandatory then return end -- it's a file
            local dir_path = self.entry and self.entry.path
            if not dir_path then return end

            self._foldercover_processed = true

            local cover_file = findCover(dir_path) --custom
            if cover_file then
                local success, w, h = pcall(function()
                    local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
                    tmp_img:_render()
                    local orig_w = tmp_img:getOriginalWidth()
                    local orig_h = tmp_img:getOriginalHeight()
                    tmp_img:free()
                    return orig_w, orig_h
                end)
                if success then
                    self:_setFolderCover { file = cover_file, w = w, h = h, scale_to_fit = settings.crop_to_fit.get() }
                    return
                end
            end

            self.menu._dummy = true
            local entries = self.menu:genItemTableFromPath(dir_path) -- sorted
            self.menu._dummy = false
            if not entries then return end

            local found_cover = false
            for _, entry in ipairs(entries) do
                if entry.is_file or entry.file then
                    local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                    if
                        bookinfo
                        and bookinfo.cover_bb
                        and bookinfo.has_cover
                        and bookinfo.cover_fetched
                        and not bookinfo.ignore_cover
                        and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs)
                    then
                        self:_setFolderCover { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h }
                        found_cover = true
                        break
                    end
                end
            end
            if not found_cover then
                self:_setFolderCover { no_image = true }
            end
        end

        function MosaicMenuItem:_setFolderCover(img)
            local top_h = 2 * (Folder.edge.thick + Folder.edge.margin)

            -- ── Portrait box: matches browser_cover_mosaic_uniform.lua exactly ──
            -- Book covers: portrait_w = floor((self.height - 2*border.thin) * 2/3)
            -- Folder frames use the same border.thin so widths are identical.
            -- portrait_h = available space below the tab lines.
            local border     = Folder.face.border_size  -- Size.border.thin
            local bh         = self.height - 2 * border
            local portrait_w = math.floor(bh * (2 / 3))
            local portrait_h = bh - top_h               -- space below the tab

            local size  = { w = portrait_w, h = portrait_h }
            local dimen = { w = portrait_w + 2 * border, h = portrait_h + 2 * border }

            -- All images are fit-to-box (width=portrait_w, height=portrait_h, no
            -- explicit scale_factor) so KOReader auto-scales to min(w,h) ratio.
            -- This guarantees zero overflow regardless of source aspect ratio.
            local image_widget
            if img.no_image then
                image_widget = FrameContainer:new {
                    padding = 0,
                    bordersize = border,
                    width = dimen.w, height = dimen.h,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    CenterContainer:new {
                        dimen = { w = portrait_w, h = portrait_h },
                        VerticalSpan:new { width = 1 },
                    },
                    overlap_align = "center",
                }
            else
                image_widget = FrameContainer:new {
                    padding = 0,
                    bordersize = border,
                    width = dimen.w, height = dimen.h,
                    background = Blitbuffer.COLOR_LIGHT_GRAY,
                    CenterContainer:new {
                        dimen = { w = portrait_w, h = portrait_h },
                        ImageWidget:new {
                            file   = img.file,
                            image  = img.data,
                            width  = portrait_w,
                            height = portrait_h,
                        },
                    },
                    overlap_align = "center",
                }
            end

            -- Pass inner image dimensions; the FrameContainer (bordersize) brings the
            -- banner flush with the outer cover edge (dimen.w = size.w + 2*border_size).
            local directory, nbitems = self:_getTextBoxes { w = size.w, h = size.h }
            -- Fixed circle diameter, independent of font size.
            local badge_d = Folder.face.nb_items_badge_size
            local badge_offset = Folder.face.nb_items_offset

            local folder_name_widget
            if settings.show_folder_name.get() then
                local NameContainer = settings.name_centered.get() and CenterContainer or BottomContainer
                folder_name_widget = NameContainer:new {
                    dimen = dimen,
                    FrameContainer:new {
                        padding = 0,
                        bordersize = Folder.face.border_size,
                        background = Blitbuffer.COLOR_WHITE,
                        directory,
                    },
                    overlap_align = "center",
                }
            else
                folder_name_widget = VerticalSpan:new { width = 0 }
            end

            local nbitems_widget
            if nbitems.text ~= "" then
                nbitems_widget = TopContainer:new {
                    dimen = dimen,
                    RightContainer:new {
                        dimen = {
                            w = dimen.w - Screen:scaleBySize(4),
                            h = badge_d + badge_offset,
                        },
                        VerticalGroup:new {
                            VerticalSpan:new{ width = badge_offset },
                            FrameContainer:new {
                                padding = 0,
                                bordersize = 0,
                                radius = math.floor(badge_d / 2),
                                background = Blitbuffer.COLOR_WHITE,
                                CenterContainer:new { dimen = { w = badge_d, h = badge_d }, nbitems },
                            },
                        },
                    },
                    overlap_align = "center",
                }
            else
                nbitems_widget = VerticalSpan:new { width = 0 }
            end

            local widget = CenterContainer:new {
                dimen = { w = self.width, h = self.height },
                VerticalGroup:new {
                    VerticalSpan:new { width = math.max(0, math.ceil((self.height - (top_h + dimen.h)) * 0.5)) },
                    LineWidget:new {
                        background = Folder.edge.color,
                        dimen = { w = math.floor(dimen.w * (Folder.edge.width ^ 2)), h = Folder.edge.thick },
                    },
                    VerticalSpan:new { width = Folder.edge.margin },
                    LineWidget:new {
                        background = Folder.edge.color,
                        dimen = { w = math.floor(dimen.w * Folder.edge.width), h = Folder.edge.thick },
                    },
                    VerticalSpan:new { width = Folder.edge.margin },
                    OverlapGroup:new {
                        dimen = { w = self.width, h = self.height - top_h },
                        image_widget,
                        folder_name_widget,
                        nbitems_widget,
                    },
                },
            }
            if self._underline_container[1] then
                local previous_widget = self._underline_container[1]
                previous_widget:free()
            end

            self._underline_container[1] = widget
        end

        function MosaicMenuItem:_getTextBoxes(dimen)
            local nbitems = TextWidget:new {
                text = self.mandatory:match("(%d+) \u{F016}") or "", -- nb books
                face = Font:getFace("cfont", Folder.face.nb_items_font_size),
                bold = true,
                padding = 0,
            }

            -- Always reserve the same badge height so the title font stays
            -- consistent whether the folder is empty or not.
            local badge_ref = TextWidget:new {
                text = "0",
                face = Font:getFace("cfont", Folder.face.nb_items_font_size),
                bold = true,
                padding = 0,
            }
            local badge_h = badge_ref:getSize().h
            badge_ref:free()

            local text = self.text
            if text:match("/$") then text = text:sub(1, -2) end -- remove "/"
            text = BD.directory(capitalize(text))
            local available_height = dimen.h - 2 * badge_h
            local dir_font_size = Folder.face.dir_max_font_size
            local directory

            while true do
                if directory then directory:free(true) end
                directory = TextBoxWidget:new {
                    text = text,
                    face = Font:getFace("cfont", dir_font_size),
                    width = dimen.w,
                    alignment = "center",
                    bold = true,
                }
                if directory:getSize().h <= available_height then break end
                dir_font_size = dir_font_size - 1
                if dir_font_size < 10 then -- don't go too low
                    directory:free()
                    directory.height = available_height
                    directory.height_adjust = true
                    directory.height_overflow_show_ellipsis = true
                    directory:init()
                    break
                end
            end

            return directory, nbitems
        end

        -- list mode cover
        do
            local ListMenu = require("listmenu")
            local ListMenuItem = get_upvalue(ListMenu._updateItemsBuildUI, "ListMenuItem")
            if ListMenuItem then
                local original_list_update = ListMenuItem.update

                function ListMenuItem:update(...)
                    original_list_update(self, ...)
                    if self._foldercover_processed or self.menu.no_refresh_covers or not self.do_cover_image then return end
                    if self.entry.is_file or self.entry.file or not self.mandatory then return end
                    local dir_path = self.entry and self.entry.path
                    if not dir_path then return end

                    self._foldercover_processed = true

                    local cover_file = findCover(dir_path)
                    if cover_file then
                        local success, w, h = pcall(function()
                            local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
                            tmp_img:_render()
                            local orig_w = tmp_img:getOriginalWidth()
                            local orig_h = tmp_img:getOriginalHeight()
                            tmp_img:free()
                            return orig_w, orig_h
                        end)
                        if success then
                            self:_setListFolderCover { file = cover_file, w = w, h = h, scale_to_fit = settings.crop_to_fit.get() }
                            return
                        end
                    end

                    self.menu._dummy = true
                    local entries = self.menu:genItemTableFromPath(dir_path)
                    self.menu._dummy = false
                    if not entries then return end

                    local found_cover = false
                    for _, entry in ipairs(entries) do
                        if entry.is_file or entry.file then
                            local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                            if
                                bookinfo
                                and bookinfo.cover_bb
                                and bookinfo.has_cover
                                and bookinfo.cover_fetched
                                and not bookinfo.ignore_cover
                                and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs)
                            then
                                self:_setListFolderCover { data = bookinfo.cover_bb, w = bookinfo.cover_w, h = bookinfo.cover_h }
                                found_cover = true
                                break
                            end
                        end
                    end
                    if not found_cover then
                        self:_setListFolderCover { no_image = true }
                    end
                end

                function ListMenuItem:_setListFolderCover(img)
                    local underline_h = 1 -- same as self.underline_h = 1 set in ListMenuItem:init()
                    local border_size = Size.border.thin
                    local dimen_h = self.height - 2 * underline_h
                    local cover_zone_w = dimen_h -- squared, matches book cover zone in list mode
                    local max_img = dimen_h - 2 * border_size

                    -- Font sizes scaled to item height, matching ListMenuItem's _fontSize formula.
                    local scale_by_size = Screen:scaleBySize(1000000) * (1 / 1000000)
                    local function _fontSize(nominal, max_size)
                        local fs = math.floor(nominal * dimen_h * (1 / 64) / scale_by_size)
                        if max_size and fs >= max_size then return max_size end
                        return fs
                    end

                    -- Build the cover image widget (left side, squared zone, same as book covers).
                    -- spine_x = left edge of the cover image within the cover zone (for spine line placement).
                    local wleft
                    local spine_x
                    if img.no_image then
                        local fake_w = math.floor(max_img * 0.6)
                        local cover_w = fake_w + 2 * border_size
                        spine_x = math.max(0, math.floor((cover_zone_w - cover_w) / 2))
                        wleft = CenterContainer:new {
                            dimen = { w = cover_zone_w, h = dimen_h },
                            FrameContainer:new {
                                width = cover_w,
                                height = max_img + 2 * border_size,
                                margin = 0, padding = 0, bordersize = border_size,
                                CenterContainer:new {
                                    dimen = { w = fake_w, h = max_img },
                                    VerticalSpan:new { width = 1 },
                                },
                            },
                        }
                    else
                        local img_options = { file = img.file, image = img.data }
                        if img.scale_to_fit then
                            img_options.scale_factor = math.max(max_img / img.w, max_img / img.h)
                            img_options.width = max_img
                            img_options.height = max_img
                        else
                            img_options.scale_factor = math.min(max_img / img.w, max_img / img.h)
                        end
                        local image = ImageWidget:new(img_options)
                        image:_render()
                        local image_size = image:getSize()
                        local cover_w = image_size.w + 2 * border_size
                        spine_x = math.max(0, math.floor((cover_zone_w - cover_w) / 2))
                        wleft = CenterContainer:new {
                            dimen = { w = cover_zone_w, h = dimen_h },
                            FrameContainer:new {
                                width = cover_w,
                                height = image_size.h + 2 * border_size,
                                margin = 0, padding = 0, bordersize = border_size,
                                image,
                            },
                        }
                    end

                    -- Spine lines slightly offset from the left edge of the cover image.
                    local spine_gap = Screen:scaleBySize(8)
                    wleft = OverlapGroup:new {
                        dimen = { w = cover_zone_w, h = dimen_h },
                        wleft,
                        LeftContainer:new {
                            dimen = { w = cover_zone_w, h = dimen_h },
                            HorizontalGroup:new {
                                HorizontalSpan:new { width = math.max(0, spine_x - spine_gap) },
                                LineWidget:new {
                                    background = Folder.edge.color,
                                    dimen = { w = Folder.edge.thick, h = dimen_h },
                                },
                                HorizontalSpan:new { width = Folder.edge.margin },
                                LineWidget:new {
                                    background = Folder.edge.color,
                                    dimen = { w = Folder.edge.thick, h = dimen_h },
                                },
                            },
                        },
                    }

                    -- Right-side item count widget.
                    local pad = Screen:scaleBySize(10)
                    local wmain_left_pad = Screen:scaleBySize(5) -- narrower padding when cover present
                    -- mandatory may contain a trailing icon glyph (e.g. "3 \u{F016}"), strip to digits only
                    local count_num = tonumber((self.mandatory or "0"):match("^%s*(%d+)")) or 0
                    local fs_right = _fontSize(16, 20)
                    local label_str = tostring(count_num) .. " " .. (count_num == 1 and _("Book") or _("Books"))
                    local wright = TextWidget:new{
                        text = label_str,
                        face = Font:getFace("cfont", fs_right),
                        padding = 0,
                    }
                    local wright_w = wright:getWidth()
                    local wright_right_pad = pad

                    -- Folder name widget (middle area).
                    local text = self.text
                    if text:match("/$") then text = text:sub(1, -2) end
                    text = BD.directory(capitalize(text))
                    local wmain_w = self.width - cover_zone_w - wmain_left_pad - pad - wright_w - wright_right_pad
                    local wname = TextBoxWidget:new {
                        text = text,
                        face = Font:getFace("cfont", _fontSize(20, 24)),
                        width = math.max(wmain_w, 0),
                        alignment = "left",
                        bold = true,
                        height = dimen_h,
                        height_adjust = true,
                        height_overflow_show_ellipsis = true,
                    }

                    local dimen = { w = self.width, h = dimen_h }
                    local widget = OverlapGroup:new {
                        dimen = dimen,
                        wleft,
                        LeftContainer:new {
                            dimen = dimen,
                            HorizontalGroup:new {
                                HorizontalSpan:new { width = cover_zone_w },
                                HorizontalSpan:new { width = wmain_left_pad },
                                wname,
                            },
                        },
                        RightContainer:new {
                            dimen = dimen,
                            HorizontalGroup:new {
                                wright,
                                HorizontalSpan:new { width = wright_right_pad },
                            },
                        },
                    }

                    if self._underline_container[1] then
                        local previous_widget = self._underline_container[1]
                        previous_widget:free()
                    end
                    self._underline_container[1] = VerticalGroup:new {
                        VerticalSpan:new { width = underline_h },
                        widget,
                    }
                end
            end
        end

        -- menu
        local orig_CoverBrowser_addToMainMenu = plugin.addToMainMenu

        function plugin:addToMainMenu(menu_items)
            orig_CoverBrowser_addToMainMenu(self, menu_items)
            if menu_items.filebrowser_settings == nil then return end

            local item = getMenuItem(menu_items.filebrowser_settings, _("Mosaic and detailed list settings"))
            if item then
                item.sub_item_table[#item.sub_item_table].separator = true
                for i, setting in pairs(settings) do
                    if
                        not getMenuItem( -- already exists ?
                            menu_items.filebrowser_settings,
                            _("Mosaic and detailed list settings"),
                            setting.text
                        )
                    then
                        table.insert(item.sub_item_table, {
                            text = setting.text,
                            checked_func = function() return setting.get() end,
                            callback = function()
                                setting.toggle()
                                self.ui.file_chooser:updateItems()
                            end,
                        })
                    end
                end
            end
        end
    end

    -- `require("coverbrowser")` fails at plugin-init time because the plugin
    -- hasn't been instantiated yet.  By the time FileManager:setupLayout() runs
    -- (inside FileManager:init()), all plugins — including coverbrowser — have
    -- already been registered on `self`.  Hook there instead.
    local FileManager = require("apps/filemanager/filemanager")
    local orig_fm_setupLayout = FileManager.setupLayout
    local coverbrowser_patched = false

    FileManager.setupLayout = function(self)
        orig_fm_setupLayout(self)
        if not coverbrowser_patched and self.coverbrowser then
            patchCoverBrowser(self.coverbrowser)
            coverbrowser_patched = true
            -- The file list may have already rendered before patching completed.
            -- Schedule a refresh so our cover rendering runs on all visible items.
            local UIManager = require("ui/uimanager")
            UIManager:scheduleIn(0, function()
                if self.file_chooser then
                    self.file_chooser:updateItems()
                end
            end)
        end
    end
end


return apply_browser_folder_cover

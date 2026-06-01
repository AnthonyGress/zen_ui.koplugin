--[[
    mosaic_title_strip.lua
    Renders title (bold) and/or author text in a strip below cover images in
    mosaic mode. Space is reserved by reducing the effective image height so
    the grid layout is not disturbed.
    Requires restart to take effect (strip height is fixed at apply time).
]]

local function apply_mosaic_title_strip()
    local logger = require("logger")
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim or not BookInfoManager then
        logger.warn("zen-ui:mosaic_title_strip: BookInfoManager not available")
        return
    end

    local Screen = require("device").screen

    local _plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local function cfg()
        local p = _plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        return p
            and type(p.config) == "table"
            and type(p.config.mosaic_title_strip) == "table"
            and p.config.mosaic_title_strip or nil
    end

    -- Read at apply time; determines strip geometry for the session.
    local c = cfg()
    local _show_title  = c and c.show_title  == true or false
    local _show_author = c and c.show_author == true or false
    logger.dbg("zen-ui:mosaic_title_strip: apply, show_title=", _show_title, "show_author=", _show_author)
    if not _show_title and not _show_author then
        logger.dbg("zen-ui:mosaic_title_strip: both disabled, skipping apply")
        return
    end

    local function get_upvalue(fn, name)
        if type(fn) ~= "function" then return nil end
        for i = 1, 128 do
            local n, v = debug.getupvalue(fn, i)
            if not n then break end
            if n == name then return v end
        end
    end

    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = get_upvalue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then
        logger.warn("zen-ui:mosaic_title_strip: could not find MosaicMenuItem upvalue")
        return
    end

    if MosaicMenuItem._zen_title_strip_patched then
        logger.dbg("zen-ui:mosaic_title_strip: already patched, skipping")
        return
    end
    MosaicMenuItem._zen_title_strip_patched = true
    logger.dbg("zen-ui:mosaic_title_strip: patching MosaicMenuItem")

    local Blitbuffer = require("ffi/blitbuffer")
    local TextWidget = require("ui/widget/textwidget")
    local BD         = require("ui/bidi")
    local library_font = require("common/library_font")

    local TITLE_FONT  = library_font.scaleValue(16)
    local AUTHOR_FONT = library_font.scaleValue(13)
    local PAD         = Screen:scaleBySize(3)
    local GAP         = Screen:scaleBySize(2)  -- space between title and author rows
    local PAD_H       = Screen:scaleBySize(6)  -- horizontal text margin (device constant)

    -- Measure actual pixel line heights for the chosen fonts at this device's DPI.
    local function measure_line_h(font_size, bold)
        local tw = TextWidget:new{ text = "Ag", face = library_font.getFace(font_size),
            bold = bold, padding = 0 }
        local h = tw:getSize().h
        tw:free()
        return h
    end
    local TITLE_LINE  = measure_line_h(TITLE_FONT, true)
    local AUTHOR_LINE = measure_line_h(AUTHOR_FONT, false)

    local STRIP_H = PAD
    if _show_title  then STRIP_H = STRIP_H + TITLE_LINE end
    if _show_title and _show_author then STRIP_H = STRIP_H + GAP end
    if _show_author then STRIP_H = STRIP_H + AUTHOR_LINE end
    STRIP_H = STRIP_H + PAD
    logger.dbg("zen-ui:mosaic_title_strip: STRIP_H=", STRIP_H)
    -- Shared with browser_folder_cover so _setFolderCover can use the correct effective height.
    MosaicMenuItem._zen_strip_h = STRIP_H

    -- Flag to prevent double height reduction when init calls update internally.
    local _in_init = false

    -- Wrap init: reduce self.height so browser_cover_mosaic_uniform (already
    -- patched at this point) computes max_img_h against the reduced height.
    local orig_init = MosaicMenuItem.init
    function MosaicMenuItem:init()
        logger.dbg("zen-ui:mosaic_title_strip:init: self.height before=", self.height, "STRIP_H=", STRIP_H)
        self.height = self.height - STRIP_H
        _in_init = true
        MosaicMenuItem._zen_in_init = true
        orig_init(self)
        _in_init = false
        MosaicMenuItem._zen_in_init = false
        self.height = self.height + STRIP_H
        logger.dbg("zen-ui:mosaic_title_strip:init: self.height after restore=", self.height)
    end

    -- Wrap update: rebuild the cover widget within the reduced height on any
    -- call (lazy cover fetches, layout refreshes, etc.).
    local orig_update = MosaicMenuItem.update
    function MosaicMenuItem:update()
        if not _in_init then
            logger.dbg("zen-ui:mosaic_title_strip:update: reducing height by STRIP_H=", STRIP_H, "from=", self.height)
            self.height = self.height - STRIP_H
        end
        self._zen_strip_data = nil -- reset text/render cache on cover reload
        if self._zen_strip_bb then
            self._zen_strip_bb:free()
            self._zen_strip_bb = nil
        end
        orig_update(self)
        if not _in_init then
            self.height = self.height + STRIP_H
            logger.dbg("zen-ui:mosaic_title_strip:update: restored height=", self.height)
        end
    end

    -- Deferred paintTo via FileManager.setupLayout — must run AFTER browser_cover_badges
    -- patches paintTo in its own setupLayout hook. badges calls InputContainer.paintTo
    -- directly (not orig_paintTo), so strip must wrap badges from the outside.
    -- Patching at apply-time would cause badges to capture strip_paintTo as orig_paintTo,
    -- breaking uv_idx upvalue lookup (corner_mark_size etc. not present in strip's closure).
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    if not ok_fm or not FileManager then
        logger.warn("zen-ui:mosaic_title_strip: FileManager not available for paintTo patch")
        return
    end

    local orig_setupLayout = FileManager.setupLayout
    local _paintTo_patched = false

    FileManager.setupLayout = function(fm, ...)
        orig_setupLayout(fm, ...)
        if _paintTo_patched or not fm.coverbrowser then return end
        _paintTo_patched = true
        logger.dbg("zen-ui:mosaic_title_strip: patching paintTo via setupLayout")

        local orig_paintTo = MosaicMenuItem.paintTo
        local _logged_chain = false

        function MosaicMenuItem:paintTo(bb, x, y)
            if not _logged_chain then
                _logged_chain = true
                logger.dbg("zen-ui:mosaic_title_strip:paintTo: chain=", tostring(orig_paintTo),
                    "self.height=", self.height, "STRIP_H=", STRIP_H,
                    "is_directory=", tostring(self.is_directory),
                    "bookinfo_found=", tostring(self.bookinfo_found))
            end

            orig_paintTo(self, bb, x, y)

            -- Directories: show folder name in strip (either setting enabled means strip is active).
            if self.is_directory then
                local folder_name = self.text and self.text:gsub("/$", "") or ""
                if folder_name == "" then return end
                -- Render and cache the directory name strip on first paint.
                if not self._zen_strip_bb then
                    local strip_w  = self.width
                    local strip_bb = Blitbuffer.new(strip_w, STRIP_H, bb:getType())
                    strip_bb:fill(Blitbuffer.COLOR_WHITE)
                    local tw = TextWidget:new{
                        text                   = BD.auto(folder_name),
                        face                   = library_font.getFace(TITLE_FONT),
                        bold                   = true,
                        padding                = 0,
                        fgcolor                = Blitbuffer.COLOR_BLACK,
                        max_width              = strip_w - 2 * PAD_H,
                        truncate_with_ellipsis = true,
                    }
                    local tsz = tw:getSize()
                    tw:paintTo(strip_bb, math.floor((strip_w - tsz.w) / 2),
                        math.floor((STRIP_H - tsz.h) / 2))
                    tw:free()
                    self._zen_strip_bb = strip_bb
                end
                bb:blitFrom(self._zen_strip_bb, x, y + self.height - STRIP_H, 0, 0, self.width, STRIP_H)
                return
            end

            -- Per-instance bookinfo cache; cleared by update() on cover reload.
            if self._zen_strip_data == nil then
                if not self.bookinfo_found then return end
                local info = BookInfoManager:getBookInfo(self.filepath, false)
                local title   = info and not info.ignore_meta and info.title   or nil
                local authors = info and not info.ignore_meta and info.authors or nil
                if authors and authors:find("\n") then
                    authors = authors:match("^([^\n]+)")
                end
                -- Filename fallback for title once metadata is confirmed loaded.
                if not title and self.filepath then
                    local fname = self.filepath:match("([^/]+)$") or ""
                    fname = fname:gsub("%.[^%.]+$", "")
                    if fname ~= "" then title = fname end
                end
                if title or authors then
                    self._zen_strip_data = { title = title, authors = authors }
                    logger.dbg("zen-ui:mosaic_title_strip:paintTo: cached title=",
                        tostring(title), "authors=", tostring(authors))
                else
                    self._zen_strip_data = false
                end
            end
            if not self._zen_strip_data then return end

            -- Render and cache the text strip blitbuffer on first paint after a data change.
            if not self._zen_strip_bb then
                local strip_w  = self.width
                local text_w   = strip_w - 2 * PAD_H
                local strip_bb = Blitbuffer.new(strip_w, STRIP_H, bb:getType())
                strip_bb:fill(Blitbuffer.COLOR_WHITE)
                local cur_y = PAD

                if _show_title then
                    local title_str = self._zen_strip_data.title
                    if title_str then
                        local tw = TextWidget:new{
                            text                   = BD.auto(title_str),
                            face                   = library_font.getFace(TITLE_FONT),
                            bold                   = true,
                            padding                = 0,
                            fgcolor                = Blitbuffer.COLOR_BLACK,
                            max_width              = text_w,
                            truncate_with_ellipsis = true,
                        }
                        local tsz = tw:getSize()
                        tw:paintTo(strip_bb, math.floor((strip_w - tsz.w) / 2), cur_y)
                        tw:free()
                    end
                    if _show_author then cur_y = cur_y + TITLE_LINE + GAP end
                end

                if _show_author then
                    local authors_str = self._zen_strip_data.authors
                    if authors_str then
                        local aw = TextWidget:new{
                            text                   = BD.auto(authors_str),
                            face                   = library_font.getFace(AUTHOR_FONT),
                            bold                   = false,
                            padding                = 0,
                            fgcolor                = Blitbuffer.COLOR_BLACK,
                            max_width              = text_w,
                            truncate_with_ellipsis = true,
                        }
                        local asz = aw:getSize()
                        aw:paintTo(strip_bb, math.floor((strip_w - asz.w) / 2), cur_y)
                        aw:free()
                    end
                end

                self._zen_strip_bb = strip_bb
            end

            bb:blitFrom(self._zen_strip_bb, x, y + self.height - STRIP_H, 0, 0, self.width, STRIP_H)
        end
    end
end

return apply_mosaic_title_strip

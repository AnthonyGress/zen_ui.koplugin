local M = {}

local function launcher_config(config)
    return type(config) == "table" and config or {}
end

function M.isEnabled(config, library_context)
    return library_context ~= true
        and launcher_config(config).show_book_details == true
end

function M.rendererOptions(config)
    config = type(config) == "table" and config or {}
    local features = type(config.features) == "table" and config.features or {}
    return { uniform = features.browser_cover_mosaic_uniform == true }
end

local function load_cover(book, width, height)
    if not (book and book.path) then return end
    local ok_cover, Cover = pcall(require, "common/cover_utils")
    if not ok_cover or type(Cover.makeCover) ~= "function" then return end
    local cover = { Cover.makeCover(book.path, nil, {
        is_folder = false,
        width = width,
        height = height,
        need_copy = true,
    }) }
    book.cover_bb = cover[1]
    book.cover_w = cover[2]
    book.cover_h = cover[3]
    book.has_real_cover = cover[5] == "real_cover"
end

function M.build(opts)
    opts = opts or {}
    local Blitbuffer = require("ffi/blitbuffer")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local Device = require("device")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local GestureRange = require("ui/gesturerange")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local BookProgress = require("common/ui/book_progress")
    local BookDetails = require("modules/reader/book_details")
    local BookSwitcherPage = require("modules/menu/app_launcher/book_switcher_page")
    local cover_common = require("modules/filebrowser/patches/home/widgets/cover_common")
    local library_font = require("modules/filebrowser/patches/library_font")
    local _ = require("gettext")

    local Screen = Device.screen
    local width = math.max(1, tonumber(opts.width) or Screen:getWidth())
    local height = math.max(1, tonumber(opts.height) or Screen:getHeight())
    local layout = BookSwitcherPage.layout{
        width = width, height = height, config = opts.config,
    }
    local padding = layout.padding
    local inner_w = layout.inner_w
    local book = opts.book or BookDetails.getSummary(opts.ui)
    local refs = { buttons = {}, layout_rows = {} }

    if not book then
        local message = TextBoxWidget:new{
            text = _("Book details"),
            face = Font:getFace("smallinfofont", Screen:scaleBySize(18)),
            width = math.max(1, inner_w - padding * 2),
            alignment = "center",
            alignment_strict = true,
            height_adjust = true,
        }
        return CenterContainer:new{ dimen = Geom:new{ w = width, h = height }, message }, refs
    end

    local gap = math.max(6, Screen:scaleBySize(18))
    local cover_max_w = layout.cover_max_w
    local cover_max_h = layout.cover_max_h
    if not book.cover_bb then load_cover(book, cover_max_w, cover_max_h) end
    local cover, cover_w = cover_common.make_cover_widget(
        book, cover_max_w, cover_max_h, {
            border = cover_common.BORDER_SIZE,
            background = Blitbuffer.COLOR_LIGHT_GRAY,
            uniform = M.rendererOptions(opts.config).uniform,
        })
    local text_w = math.max(1, inner_w - cover_w - gap)
    local title_face = library_font.getFace(library_font.scaleValue(22))
    local metadata_face = library_font.getFace(library_font.scaleValue(19))
    local title = TextBoxWidget:new{
        text = book.title or "",
        face = title_face,
        bold = true,
        width = text_w,
        alignment = "left",
        alignment_strict = true,
        height_adjust = true,
    }
    local details = VerticalGroup:new{ align = "left", title }
    if book.authors and book.authors ~= "" then
        details[#details + 1] = VerticalSpan:new{ width = Screen:scaleBySize(6) }
        details[#details + 1] = TextBoxWidget:new{
            text = book.authors:gsub("%s*\n%s*", ", "),
            face = metadata_face,
            width = text_w,
            alignment = "left",
            alignment_strict = true,
            height_adjust = true,
        }
    end
    local function add_metadata(text)
        if text and text ~= "" then
            details[#details + 1] = VerticalSpan:new{ width = Screen:scaleBySize(3) }
            details[#details + 1] = TextBoxWidget:new{
                text = text,
                face = metadata_face,
                width = text_w,
                alignment = "left",
                alignment_strict = true,
                height_adjust = true,
            }
        end
    end
    add_metadata(book.series)
    add_metadata(book.genres)
    add_metadata(book.page_text)
    local progress = BookProgress.build{
        ratio = book.progress,
        pages = book.pages,
        right_text = "",
        width = text_w,
        bar_height = math.max(2, Screen:scaleBySize(7)),
        face = metadata_face,
    }
    if progress then
        details[#details + 1] = VerticalSpan:new{ width = Screen:scaleBySize(18) }
        details[#details + 1] = progress
    end

    local content_h = layout.cover_area_h
    local detail_row = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = cover_w, h = content_h }, cover },
        HorizontalSpan:new{ width = gap },
        CenterContainer:new{ dimen = Geom:new{ w = text_w, h = content_h }, details },
    }
    local content = VerticalGroup:new{ align = "center", detail_row }
    if layout.strip_h > 0 then
        content[#content + 1] = VerticalSpan:new{ width = layout.strip_h }
    end

    local DetailsCell = InputContainer:extend{}
    function DetailsCell:init()
        self.dimen = self.dimen or Geom:new{ w = self.width, h = self.height }
        self.ges_events = {
            TapSelect = { GestureRange:new{ ges = "tap", range = self.dimen } },
        }
    end
    function DetailsCell:paintTo(bb, x, y)
        self.dimen.x, self.dimen.y = x, y
        self[1]:paintTo(bb, x, y)
        if self.focused then
            local line = math.max(1, Screen:scaleBySize(2))
            bb:paintRect(x, y + self.height - line, self.width, line,
                Blitbuffer.COLOR_BLACK)
        end
    end
    function DetailsCell:onTapSelect()
        if self.callback then self.callback() end
        return true
    end
    function DetailsCell:onFocus()
        self.focused = true
        UIManager:setDirty(nil, "fast", self.dimen)
        return true
    end
    function DetailsCell:onUnfocus()
        self.focused = false
        UIManager:setDirty(nil, "fast", self.dimen)
        return true
    end

    local callback = function()
        if type(opts.open_details) == "function" then opts.open_details() end
    end
    local cell = DetailsCell:new{
        width = inner_w,
        height = layout.cell_h,
        dimen = Geom:new{ w = inner_w, h = layout.cell_h },
        callback = callback,
        content,
    }
    refs.buttons[1] = { widget = cell, callback = callback }
    refs.layout_rows[1] = { cell }

    return VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = layout.top_padding },
        CenterContainer:new{ dimen = Geom:new{ w = width, h = layout.cell_h }, cell },
        VerticalSpan:new{ width = padding },
    }, refs
end

return M

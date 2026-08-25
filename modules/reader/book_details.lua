local Device = require("device")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local Cover = require("common/cover_utils")
local LanguageName = require("common/language_name")
local LibraryFont = require("modules/filebrowser/patches/library_font")
local ReaderFont = require("common/reader_font")
local utils = require("common/utils")
local T = require("ffi/util").template
local _ = require("gettext")

local M = {}

local function read_setting(settings, key)
    if not (settings and type(settings.readSetting) == "function") then return nil end
    local ok, value = pcall(settings.readSetting, settings, key)
    return ok and value or nil
end

local function positive_number(value)
    value = tonumber(value)
    return value and value > 0 and value or nil
end

local function is_present(text)
    if text == nil then return false end
    text = tostring(text):match("^%s*(.-)%s*$")
    return text ~= "" and text:lower() ~= "n/a"
end

local function current_page_info(ui)
    local footer = ui and ui.view and ui.view.footer
    local document = ui and ui.document
    local current = footer and positive_number(footer.pageno)
    local total = footer and positive_number(footer.pages)
    if not current and document and type(document.getCurrentPage) == "function" then
        local ok, value = pcall(document.getCurrentPage, document)
        if ok then current = positive_number(value) end
    end
    if not total and document and type(document.getPageCount) == "function" then
        local ok, value = pcall(document.getPageCount, document)
        if ok then total = positive_number(value) end
    end
    return current, total
end

local function page_map_labels(ui, settings)
    local pagemap = ui and ui.pagemap
    local uses_labels = read_setting(settings, "pagemap_use_page_labels") == true
    if pagemap and type(pagemap.wantsPageLabels) == "function" then
        local ok, value = pcall(pagemap.wantsPageLabels, pagemap)
        if ok and value then uses_labels = true end
    end
    if not uses_labels then return nil, nil end

    local current, total
    if pagemap and type(pagemap.getCurrentPageLabel) == "function" then
        local ok, value = pcall(pagemap.getCurrentPageLabel, pagemap, true)
        if ok and is_present(value) then current = value end
    end
    if pagemap and type(pagemap.getLastPageLabel) == "function" then
        local ok, value = pcall(pagemap.getLastPageLabel, pagemap, true)
        if ok and is_present(value) then total = value end
    end
    current = current or read_setting(settings, "pagemap_current_page_label")
    total = total or read_setting(settings, "pagemap_last_page_label")
    return is_present(current) and current or nil, is_present(total) and total or nil
end

local function format_series(series, index)
    if not is_present(series) then return nil end
    series = tostring(series)
    index = tonumber(index)
    if not index then return series end
    local index_text = index == math.floor(index)
        and tostring(math.floor(index)) or string.format("%.10g", index)
    return series .. " #" .. index_text
end

local function format_genres(keywords)
    if not is_present(keywords) then return nil end
    return tostring(keywords)
        :gsub("%s*[\n;]%s*", ", ")
        :gsub("%s+\xC2\xB7%s+", ", ")
        :gsub("^,%s*", ""):gsub(",%s*$", "")
end

function M.formatPageText(current, total)
    if not (is_present(current) and is_present(total)) then return nil end
    return T(_("Page %1 of %2"), tostring(current), tostring(total))
end

function M.getProgress(ui)
    local settings = ui and ui.doc_settings
    local footer = ui and ui.view and ui.view.footer
    local ratio = footer and tonumber(footer.percent_finished)
    if ratio == nil and footer and type(footer.getBookProgress) == "function" then
        local ok, value = pcall(footer.getBookProgress, footer)
        if ok then ratio = tonumber(value) end
    end
    local current, document_pages = current_page_info(ui)
    if ratio == nil and current and document_pages then ratio = current / document_pages end
    if ratio == nil then ratio = tonumber(read_setting(settings, "percent_finished")) end
    if ratio ~= nil then
        if ratio < 0 then ratio = 0 elseif ratio > 1 then ratio = 1 end
    end

    local pages
    if read_setting(settings, "pagemap_use_page_labels") == true then
        pages = positive_number(read_setting(settings, "pagemap_doc_pages"))
            or positive_number(read_setting(settings, "pagemap_last_page_label"))
    end
    pages = pages
        or positive_number(read_setting(settings, "doc_pages"))
        or positive_number(ui and ui.doc_props and ui.doc_props.pages)
        or document_pages
    if not pages and ui and ui.document and ui.document.file then
        pages = positive_number(utils.getStablePageCount(
            ui.document.file, nil, { doc_settings = settings, sidecar_checked = true }))
    end
    local page_current, page_total = page_map_labels(ui, settings)
    page_total = page_total or pages
    if not page_current then
        page_current = current
        if pages and ratio and (not page_current or pages ~= document_pages) then
            page_current = math.floor(pages * ratio + 0.5)
            if ratio > 0 and page_current < 1 then page_current = 1 end
            if page_current > pages then page_current = pages end
        end
    end
    return ratio, pages, page_current, page_total
end

function M.getReadingTimes(ui)
    local stats = ui and ui.statistics
    if type(stats) ~= "table" or type(stats.getStatsBookStatus) ~= "function" then
        return nil, nil
    end

    local ok, status = pcall(stats.getStatsBookStatus, stats)
    if not ok or type(status) ~= "table" then return nil, nil end

    local read_time = tonumber(status.time)
    if not (read_time and read_time >= 0 and read_time < math.huge) then
        read_time = nil
    end

    local time_left
    local avg_time = tonumber(stats.avg_time)
    local current_page, total_pages = current_page_info(ui)
    if avg_time and avg_time > 0 and avg_time < math.huge
            and current_page and total_pages and current_page <= total_pages then
        time_left = math.floor((total_pages - current_page) * avg_time + 0.5)
    end
    return time_left, read_time
end

function M.getSummary(ui)
    local file = ui and ui.document and ui.document.file
    if not file then return nil end
    local props = type(ui.doc_props) == "table" and ui.doc_props or {}
    local ratio, pages, current_page, page_total = M.getProgress(ui)
    return {
        path = file,
        title = is_present(props.title) and props.title or file:match("([^/]+)$"),
        authors = is_present(props.authors) and props.authors or "",
        series = format_series(props.series, props.series_index),
        genres = format_genres(props.keywords),
        pages = pages,
        current_page = current_page,
        page_total = page_total,
        page_text = M.formatPageText(current_page, page_total),
        progress = ratio,
        bookinfo = props,
    }
end

local function rounded_covers_enabled(config)
    config = type(config) == "table" and config
        or rawget(_G, "__ZEN_UI_PLUGIN") and rawget(_G, "__ZEN_UI_PLUGIN").config
    return type(config) == "table" and type(config.features) == "table"
        and config.features.browser_cover_rounded_corners == true
end

function M.buildSpec(ui, opts)
    opts = opts or {}
    local summary = M.getSummary(ui)
    if not summary then return nil end

    local file = summary.path
    local props = type(ui.doc_props) == "table" and ui.doc_props or {}
    local settings = ui.doc_settings
    local book_summary = read_setting(settings, "summary")
    if type(book_summary) ~= "table" then book_summary = {} end
    local annotations = ui.annotation and ui.annotation.annotations
    if type(annotations) ~= "table" then
        annotations = read_setting(settings, "annotations")
    end
    local description = props.description
    local ok_util, util = pcall(require, "util")
    if description and ok_util and util.htmlToPlainTextIfHtml then
        description = util.htmlToPlainTextIfHtml(description)
    end

    local details = {}
    local function add_detail(text, style, bold, gap_before)
        if is_present(text) then
            details[#details + 1] = {
                text = tostring(text),
                style = style,
                bold = bold,
                gap_before = gap_before,
            }
        end
    end

    add_detail(summary.title, "title", true)
    add_detail(summary.authors, "author", false, 2)
    add_detail(summary.series, "secondary", false, 2)
    add_detail(summary.genres, "tags", false, 3)
    add_detail(LanguageName.get(props.language), "secondary", false, 3)
    local rating = book_summary.rating
    local numeric_rating = tonumber(rating)
    if (not numeric_rating or numeric_rating > 0) and is_present(rating) then
        local ok_list, BookList = pcall(require, "ui/widget/booklist")
        local rating_text = ok_list and BookList and BookList.getBookRatingString
            and BookList.getBookRatingString(rating) or rating
        add_detail(rating_text, "secondary", false, 3)
    end
    local annotation_count = type(annotations) == "table" and #annotations or 0
    if annotation_count > 0 then
        add_detail(tostring(annotation_count) .. " " .. _("Annotations"),
            "secondary", false, 3)
    end
    add_detail(book_summary.note, "secondary", false, 3)
    add_detail(summary.page_text, "page", false, 3)

    local reader_font_size = ReaderFont.getInfo(ui,
        (Font.sizemap and Font.sizemap.cfont) or 16).size
    local library_face = LibraryFont.getFace(reader_font_size)
    local metadata_face = LibraryFont.getFace(math.max(1,
        math.floor(reader_font_size * 18 / 20 + 0.5)))
    local text_faces = {
        title = library_face,
        author = metadata_face,
        tags = metadata_face,
        page = metadata_face,
        secondary = metadata_face,
    }

    local cover_bb, cover_w, cover_h, cover_kind
    if Cover and Cover.makeCover then
        local target_h = math.floor(Device.screen:getHeight() * 0.30)
        local target_w = math.floor(target_h * Cover.getRatio())
        local cover = { Cover.makeCover(file, nil, {
            is_folder = false,
            width = target_w,
            height = target_h,
            need_copy = true,
        }) }
        cover_bb, cover_w, cover_h, cover_kind = cover[1], cover[2], cover[3], cover[5]
        if cover_bb and cover_kind ~= "real_cover" and cover_bb.copy then
            cover_bb = cover_bb:copy()
        end
    end

    local function show_cover_fullscreen()
        local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
        if not ok_bim then return end
        local bookinfo = BookInfoManager:getBookInfo(file, true)
        if not bookinfo or not bookinfo.cover_bb or not bookinfo.has_cover
                or bookinfo.ignore_cover then return end
        local ImageViewer = require("ui/widget/imageviewer")
        local viewer = ImageViewer:new{
            image = bookinfo.cover_bb,
            image_disposable = false,
            fullscreen = true,
            with_title_bar = false,
        }
        viewer.onTap = function(viewer_self)
            viewer_self:onClose()
            return true
        end
        UIManager:show(viewer)
    end

    return {
        title = _("Book details"),
        details = details,
        description = description or "",
        cover = cover_bb,
        cover_width = cover_w,
        cover_height = cover_h,
        cover_tap_callback = show_cover_fullscreen,
        rounded_cover = rounded_covers_enabled(opts.config),
        text_face = library_face,
        text_size = reader_font_size,
        text_faces = text_faces,
        progress = summary.progress,
        progress_pages = summary.pages,
        progress_right_text = "",
        edit_callback = opts.edit_callback,
        close_all_callback = opts.close_all_callback,
    }
end

function M.show(ui, opts)
    local spec = M.buildSpec(ui, opts)
    if not spec then return false end
    local BookInfoWidget = require("modules/reader/book_info_widget")
    UIManager:show(BookInfoWidget:new(spec))
    return true
end

function M.showFile(file, opts)
    if type(file) ~= "string" or file == "" then return false end

    local props = {}
    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if ok_bim and BookInfoManager and type(BookInfoManager.getBookInfo) == "function" then
        local ok_info, bookinfo = pcall(BookInfoManager.getBookInfo,
            BookInfoManager, file, false)
        if ok_info and type(bookinfo) == "table" and not bookinfo.ignore_meta then
            props = bookinfo
        end
    end

    local doc_settings
    local ok_settings, DocSettings = pcall(require, "docsettings")
    if ok_settings and DocSettings and type(DocSettings.open) == "function" then
        local ok_open, settings = pcall(DocSettings.open, DocSettings, file)
        if ok_open then doc_settings = settings end
    end

    return M.show({
        document = { file = file },
        doc_props = props,
        doc_settings = doc_settings,
    }, opts)
end

return M

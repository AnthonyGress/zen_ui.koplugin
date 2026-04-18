local function apply_reader_clock()
    --[[
        Paints a configurable header line at the top of the reader screen (reflowable docs only).
        Wraps ReaderView.paintTo. Config via config.reader_clock.
    --]]

    local Blitbuffer = require("ffi/blitbuffer")
    local TextWidget = require("ui/widget/textwidget")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local BD = require("ui/bidi")
    local Size = require("ui/size")
    local Geom = require("ui/geometry")
    local Device = require("device")
    local Font = require("ui/font")
    local util = require("util")
    local datetime = require("datetime")
    local UIManager = require("ui/uimanager")
    local Screen = Device.screen
    local _ = require("gettext")
    local T = require("ffi/util").template
    local ReaderView = require("apps/reader/modules/readerview")
    local _ReaderView_paintTo_orig = ReaderView.paintTo
    local header_settings = G_reader_settings:readSetting("footer")
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local plugin = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        local features = plugin and plugin.config and plugin.config.features
        return type(features) == "table" and features.reader_clock == true
    end

    ReaderView.paintTo = function(self, bb, x, y)
        _ReaderView_paintTo_orig(self, bb, x, y)
        if not is_enabled() then return end
        if self.render_mode ~= nil then return end -- Show only for epub-likes and never on pdf-likes
        if not self.document then return end -- document not yet loaded or being torn down
        -- Guard: don't paint when reader is not the topmost widget (prevents clock bleed on close)
        local _stack = UIManager._window_stack
        if not _stack then return end -- UIManager reinitialising (e.g. restart); skip to be safe
        local _top = _stack[#_stack]
        local _w = _top and _top.widget
        if _w ~= self.ui and _w ~= (self.ui and self.ui.show_parent) then
            return
        end
        -- don't change anything above this line
        local screen_width = Screen:getWidth() -- always fresh
        local zen_clock_config = zen_plugin and zen_plugin.config and zen_plugin.config.reader_clock



        -- ===========================!!!!!!!!!!!!!!!=========================== -
        -- Configure formatting options for header here, if desired
        local clock_face_cfg = type(zen_clock_config) == "table" and zen_clock_config.font_face or "default"
        local header_font_face
        if clock_face_cfg == "default" then
            header_font_face = (header_settings and header_settings.text_font_face) or "NotoSans-Regular.ttf"
        else
            header_font_face = clock_face_cfg
        end
        local header_font_size = (type(zen_clock_config) == "table" and zen_clock_config.font_size) or 14
        local header_font_bold = header_settings and header_settings.text_font_bold or false
        local header_font_color = Blitbuffer.COLOR_BLACK -- 16 shades of gray available
        local header_top_padding = Size.padding.small -- small/default/large
        local header_use_book_margins = true
        local header_margin = Size.padding.large -- used when header_use_book_margins is false
        local header_max_width_pct = 100 -- max width before truncating
        local separator = {
            bar     = "|",
            bullet  = "•",
            dot     = "·",
            em_dash = "—",
            en_dash = "-",
        }
        -- ===========================!!!!!!!!!!!!!!!=========================== -



        -- You probably don't need to change anything in the section below this line
        local book_title = ""
        local book_author = ""
        if self.ui.doc_props then
            book_title = self.ui.doc_props.display_title or ""
            book_author = self.ui.doc_props.authors or ""
            if book_author:find("\n") then -- Show first author if multiple authors
                book_author =  T(_("%1 et al."), util.splitToArray(book_author, "\n")[1] .. ",")
            end
        end
        -- Page count and percentage
        local pageno = self.state.page or 1
        local pages = self.ui.doc_settings.data.doc_pages or 1
        local page_progress = ("%d / %d"):format(pageno, pages)
        local pages_left_book  = pages - pageno
        local percentage = (pageno / pages) * 100 -- Format like %.1f in header_string below
        -- Chapter Info
        local book_chapter = ""
        local pages_chapter = 0
        local pages_left = 0
        local pages_done = 0
        if self.ui.toc then
            book_chapter = self.ui.toc:getTocTitleByPage(pageno) or ""
            pages_chapter = self.ui.toc:getChapterPageCount(pageno) or pages
            pages_left = self.ui.toc:getChapterPagesLeft(pageno) or self.ui.document:getTotalPagesLeft(pageno)
            pages_done = self.ui.toc:getChapterPagesDone(pageno) or 0
        end
        pages_done = pages_done + 1 -- include current page
        local chapter_progress = pages_done .. " ⁄⁄ " .. pages_chapter
        -- Clock:
        local use_12h = G_reader_settings:isTrue("twelve_hour_clock")
        local clock_position = (type(zen_clock_config) == "table" and zen_clock_config.position) or "center"
        local time = datetime.secondsToHour(os.time(), use_12h) or ""
        -- Battery:
        local battery = ""
        if Device:hasBattery() then
            local power_dev = Device:getPowerDevice()
            local batt_lvl = power_dev:getCapacity() or 0
            local is_charging = power_dev:isCharging() or false
            local batt_prefix = power_dev:getBatterySymbol(power_dev:isCharged(), is_charging, batt_lvl) or ""
            battery = batt_prefix .. batt_lvl .. "%"
        end
        -- You probably don't need to change anything in the section above this line



        -- ===========================!!!!!!!!!!!!!!!=========================== -
        -- What you put here will show in the header:
        local centered_header = string.format("%s", time)
        -- ===========================!!!!!!!!!!!!!!!=========================== -



        -- don't change anything below this line
        local margins = 0
        local left_margin = header_margin
        local right_margin = header_margin
        if header_use_book_margins then -- Set width % based on R + L margins
            left_margin = self.document:getPageMargins().left or header_margin
            right_margin = self.document:getPageMargins().right or header_margin
        end
        margins = left_margin + right_margin
        local avail_width = screen_width - margins -- deduct margins from width
        local function getFittedText(text, max_width_pct)
            if text == nil or text == "" then
                return ""
            end
            local text_widget = TextWidget:new{
                text = text:gsub(" ", "\u{00A0}"), -- no-break-space
                max_width = avail_width * max_width_pct * (1/100),
                face = Font:getFace(header_font_face, header_font_size),
                bold = header_font_bold,
                padding = 0,
            }
            local fitted_text, add_ellipsis = text_widget:getFittedText()
            text_widget:free()
            if add_ellipsis then
                fitted_text = fitted_text .. "…"
            end
            return BD.auto(fitted_text)
        end
        centered_header = getFittedText(centered_header, header_max_width_pct)
        local header_text = TextWidget:new {
            text = centered_header,
            face = Font:getFace(header_font_face, header_font_size),
            bold = header_font_bold,
            fgcolor = header_font_color,
            padding = 0,
        }
        local header_h = header_text:getSize().h + header_top_padding
        local text_inner = VerticalGroup:new {
            VerticalSpan:new { width = header_top_padding },
            header_text,
        }
        local header
        if clock_position == "left" then
            header = HorizontalGroup:new {
                align = "top",
                HorizontalSpan:new { width = left_margin },
                text_inner,
            }
        elseif clock_position == "right" then
            local text_w = header_text:getSize().w
            header = HorizontalGroup:new {
                align = "top",
                HorizontalSpan:new { width = screen_width - right_margin - text_w },
                text_inner,
            }
        else -- center
            header = CenterContainer:new {
                dimen = Geom:new{ w = screen_width, h = header_h },
                text_inner,
            }
        end
        header:paintTo(bb, x, y)

        -- Periodic refresh so the clock updates even when idle
        if not self._header_clock_refresh then
            self._header_clock_refresh = true
            local view = self
            local function autoRefresh()
                if view.ui and view.ui.document then
                    -- Only dirty the reader when it's the topmost widget; prevents
                    -- the clock from bleeding over fullscreen modals like BookStatusWidget
                    local stack = UIManager._window_stack
                    local top = stack and stack[#stack]
                    if top then
                        local w = top.widget
                        if w == view.ui or w == view.ui.show_parent then
                            UIManager:setDirty(view.ui.show_parent or view.ui, "ui")
                        end
                    end
                    UIManager:scheduleIn(60, autoRefresh)
                end
            end
            UIManager:scheduleIn(60, autoRefresh)
        end
    end
end

return apply_reader_clock

local function apply_reader_clock()
    --[[
        This Zen UI feature adds a "header" into the reader display, similar to the footer at the bottom.

        It draws all configured items at the top of the screen, centered, and with a small padding
        between the text and the top edge. It is only drawn for "reflowable" documents like EPUB
        and not for "fixed layout" documents like PDF and CBZ.

        It is up to you to provide enough of a top margin so that your book contents are not
        obscured by the header. You'll know right away if you need to increase the top margin.

        Right now the header is configured manually, see the comments in the code below for details.
        The set of variable names I added below match their equivalents in ReaderFooter, for better
        or worse. I provided a set of "status bar items" that I thought made the most sense.

        If someone wanted to make a whole settings UI, I think that'd be great. Maybe even use the
        built-in ReaderFooter UI somehow? With the new "status bar presets", maybe saving one with a
        special name like "header_preset" and parsing it for what to display.

        But until someone does that, if what you want isn't already included here, then you can view
        the existing ReaderFooter code at the link below. Anything it can do, this can do too, but
        accessing values is a little different. The examples I've provided should give plenty of hints.

        https://github.com/koreader/koreader/blob/master/frontend/apps/reader/modules/readerfooter.lua
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
        local screen_width = Screen:getWidth() -- always fresh (handles rotation and early-init edge cases)
        local zen_clock_config = zen_plugin and zen_plugin.config and zen_plugin.config.reader_clock



        -- ===========================!!!!!!!!!!!!!!!=========================== -
        -- Configure formatting options for header here, if desired
        local header_font_face = (type(zen_clock_config) == "table" and zen_clock_config.font_face) or "NotoSans-Bold.ttf"
        local header_font_size = (type(zen_clock_config) == "table" and zen_clock_config.font_size) or 14
        local header_font_bold = header_settings.text_font_bold or false -- Will use your footer setting if available
        local header_font_color = Blitbuffer.COLOR_BLACK -- black is the default, but there's 15 other shades to try
        local header_top_padding = Size.padding.small -- replace small with default or large for more space at the top
        local header_use_book_margins = true -- Use same margins as book for header
        local header_margin = Size.padding.large -- Use this instead, if book margins is set to false
        local header_max_width_pct = 100 -- this % is how much space the header can use before "truncating..."
        local separator = {
            bar     = "|",
            bullet  = "•",
            dot     = "·",
            em_dash = "—",
            en_dash = "-",
        }
        -- ===========================!!!!!!!!!!!!!!!=========================== -



        -- You probably don't need to change anything in the section below this line
        -- Title and Author(s):
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
        local pageno = self.state.page or 1 -- Current page
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
            book_chapter = self.ui.toc:getTocTitleByPage(pageno) or "" -- Chapter name
            pages_chapter = self.ui.toc:getChapterPageCount(pageno) or pages
            pages_left = self.ui.toc:getChapterPagesLeft(pageno) or self.ui.document:getTotalPagesLeft(pageno)
            pages_done = self.ui.toc:getChapterPagesDone(pageno) or 0
        end
        pages_done = pages_done + 1 -- This +1 is to include the page you're looking at
        local chapter_progress = pages_done .. " ⁄⁄ " .. pages_chapter
        -- Clock:
        local use_24h = type(zen_clock_config) == "table" and zen_clock_config.use_24h == true
        local clock_position = (type(zen_clock_config) == "table" and zen_clock_config.position) or "center"
        local time = datetime.secondsToHour(os.time(), not use_24h) or ""
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
        -- Look up "string.format" in Lua if you need help.
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

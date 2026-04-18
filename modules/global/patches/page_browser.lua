-- zen_ui: page_browser patch
-- Intercepts swipe-north from the bottom 14% of the reader screen and
-- opens KOReader's native PageBrowserWidget.

local function apply_page_browser()

    -- -----------------------------------------------------------------------
    -- Dependencies
    -- -----------------------------------------------------------------------
    local UIManager    = require("ui/uimanager")
    local Event        = require("ui/event")
    local ZenTocWidget = require("common/zen_toc_widget")
    local utils        = require("common/utils")

    -- -----------------------------------------------------------------------
    -- Resolve plugin icons/ dir from this file's path at apply-time
    -- -----------------------------------------------------------------------
    local _icons_dir
    do
        local src = debug.getinfo(1, "S").source or ""
        if src:sub(1,1) == "@" then
            local root = src:sub(2):match("^(.*)/modules/")
            if root then _icons_dir = root .. "/icons/" end
        end
    end

    -- -----------------------------------------------------------------------
    -- Feature guard
    -- -----------------------------------------------------------------------
    -- Capture the plugin reference NOW (while __ZEN_UI_PLUGIN is set by
    -- run_patch). After apply_page_browser() returns the global is cleared,
    -- so reading it inside gesture handlers would always return nil.
    local _plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")
    local function is_enabled()
        local features = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.features
        return type(features) == "table" and features.page_browser == true
    end

    -- -----------------------------------------------------------------------
    -- Zen UI customisations applied once to PageBrowserWidget
    -- -----------------------------------------------------------------------
    local _zen_pbw_patched = false

    local function zen_patch_page_browser_widget()
        if _zen_pbw_patched then return end
        _zen_pbw_patched = true

        local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
        local Device     = require("device")
        local Font       = require("ui/font")
        local Geom       = require("ui/geometry")
        local IconButton = require("ui/widget/iconbutton")
        local IconWidget = require("ui/widget/iconwidget")
        local HorizontalGroup = require("ui/widget/horizontalgroup")
        local HorizontalSpan  = require("ui/widget/horizontalspan")
        local VerticalGroup   = require("ui/widget/verticalgroup")
        local VerticalSpan    = require("ui/widget/verticalspan")
        local TextWidget      = require("ui/widget/textwidget")
        local FrameContainer  = require("ui/widget/container/framecontainer")
        local CenterContainer = require("ui/widget/container/centercontainer")
        local OverlapGroup    = require("ui/widget/overlapgroup")
        local Blitbuffer      = require("ffi/blitbuffer")
        local Size            = require("ui/size")
        local Screen          = Device.screen
        local GestureRange    = require("ui/gesturerange")
        local ZenSlider       = require("common/zen_slider")
        local ZenIconButton   = require("common/zen_icon_button")
        local logger          = require("logger")

        -- ----------------------------------------------------------------
        -- 1. Patch init: blank title, X to left, 3 icons on right
        -- ----------------------------------------------------------------
        local _orig_init = PageBrowserWidget.init
        PageBrowserWidget.init = function(self)
            _orig_init(self)
            -- Register pan_release so onPanRelease fires when the user lifts
            -- their finger after dragging the slider.  PageBrowserWidget does
            -- not include pan_release in its native ges_events.
            self.ges_events.PanRelease = {
                GestureRange:new{
                    ges   = "pan_release",
                    range = Geom:new{ x = 0, y = 0,
                                      w = Screen:getWidth(), h = Screen:getHeight() },
                }
            }
            -- Store original grid dimensions so view-toggle buttons can restore them.
            self._zen_orig_nb_cols = self.nb_cols
            self._zen_orig_nb_rows = self.nb_rows
            -- Block slider input until the opening swipe gesture completes so
            -- the northward swipe that opens us doesn't immediately move the
            -- slider (which appears right where the finger lifted).
            self._zen_slider_locked = true
            UIManager:scheduleIn(0.35, function()
                self._zen_slider_locked = false
            end)

            -- Blank the title text (no "Page browser" label)
            self.title_bar:setTitle("")

            local btn_sz  = Screen:scaleBySize(32)
            local btn_pad = self.title_bar.button_padding or Screen:scaleBySize(11)

            -- Remove the hamburger (left_button)
            if self.title_bar.left_button then
                for i = #self.title_bar, 1, -1 do
                    if self.title_bar[i] == self.title_bar.left_button then
                        table.remove(self.title_bar, i)
                        break
                    end
                end
                self.title_bar.left_button   = nil
                self.title_bar.has_left_icon = false
            end

            -- Move the close button (right_button) to the LEFT side.
            -- Extract the close callback before removing it.
            local close_cb, close_hold_cb
            if self.title_bar.right_button then
                close_cb      = self.title_bar.right_button.callback
                close_hold_cb = self.title_bar.right_button.hold_callback
                for i = #self.title_bar, 1, -1 do
                    if self.title_bar[i] == self.title_bar.right_button then
                        table.remove(self.title_bar, i)
                        break
                    end
                end
                self.title_bar.right_button   = nil
                self.title_bar.has_right_icon = false
            end

            -- Re-add close at left (overlap_align="left", tap zone extends right)
            table.insert(self.title_bar, IconButton:new{
                icon           = "close",
                width          = btn_sz,
                height         = btn_sz,
                padding        = btn_pad,
                padding_right  = 2 * btn_sz,
                padding_bottom = btn_sz,
                overlap_align  = "left",
                allow_flash    = false,
                show_parent    = self,
                callback       = close_cb or function() self:onClose() end,
                hold_callback  = close_hold_cb,
            })

            -- Add 3 icon buttons on the RIGHT side (font, toc, search)
            local slot_w  = btn_sz + btn_pad * 2
            local right_x = Screen:getWidth()

            local _toc_icon_path = _icons_dir and utils.resolveLocalIcon(_icons_dir, "toc")

            local function make_right_btn(icon, x_pos, cb, file_path)
                local cls = file_path and ZenIconButton or IconButton
                return cls:new{
                    file           = file_path,
                    icon           = icon,
                    width          = btn_sz,
                    height         = btn_sz,
                    padding        = btn_pad,
                    padding_bottom = btn_sz,
                    overlap_offset = { x_pos, 0 },
                    overlap_align  = "left",
                    allow_flash    = true,
                    show_parent    = self,
                    callback       = cb or function() end,
                }
            end

            -- TOC button opens ZenTocWidget
            local pbw_ref = self
            local function open_toc()
                -- Close the page browser first so the TOC renders over the reader.
                pbw_ref:onClose()
                UIManager:show(ZenTocWidget:new{
                    ui         = pbw_ref.ui,
                    focus_page = pbw_ref.focus_page or pbw_ref.cur_page or 1,
                    on_goto    = function(page)
                        -- Navigate directly in the book (PBW is already closed).
                        if pbw_ref.ui.link then
                            pbw_ref.ui.link:addCurrentLocationToStack()
                        end
                        pbw_ref.ui:handleEvent(Event:new("GotoPage", page))
                    end,
                })
            end
            local function open_search()
                -- Use onClose() (synchronous) so the page browser is removed
                -- from the widget stack before the search dialog appears,
                -- matching how open_font_menu closes the PBW.
                pbw_ref:onClose()
                pbw_ref.ui:handleEvent(Event:new("ShowFulltextSearchInput"))
            end
            local function open_bookmarks()
                -- Close page browser and open bookmarks list
                pbw_ref:onClose()
                if pbw_ref.ui.bookmark then
                    pbw_ref.ui.bookmark:onShowBookmark()
                end
            end

            -- Helper: read current font size from all possible sources.
            local function read_cur_font_size(font_module, FONT_MIN, FONT_MAX)
                local ds = pbw_ref.ui and pbw_ref.ui.doc_settings
                local sz = font_module.configurable and font_module.configurable.font_size
                if not sz or sz == 0 then
                    sz = ds and ds:readSetting("font_size")
                end
                if not sz or sz == 0 then
                    sz = G_reader_settings and G_reader_settings:readSetting("copt_font_size")
                end
                return math.max(FONT_MIN, math.min(FONT_MAX, sz or 22))
            end

            local function open_font_menu()
                local font_module = pbw_ref.ui and pbw_ref.ui.font
                if not font_module then return end

                local FONT_MIN     = 12
                local FONT_MAX     = 44
                local PRESET_SIZES = {12, 16, 20, 22, 24, 26, 28, 30, 34, 38, 44}

                local cur_size = read_cur_font_size(font_module, FONT_MIN, FONT_MAX)

                -- Close page browser so book text is visible behind the dialog.
                pbw_ref:onClose()

                -- ButtonTable maps font_size → text_font_size, font_bold → text_font_bold.
                -- It hardcodes bordersize=0 on every button (no dividers).
                -- Button default is text_font_bold=true, so font_bold must be explicit.
                local ButtonDialog = require("ui/widget/buttondialog")
                local dialog
                local show_dialog

                -- Returns the largest preset ≤ cur_size.
                -- When cur_size sits between two presets (e.g. 23 or 22.5), this
                -- bolds the lower neighbour (22), matching the "-1 step" convention.
                local function bold_preset()
                    local best = PRESET_SIZES[1]
                    for _, sz in ipairs(PRESET_SIZES) do
                        if sz <= cur_size then best = sz end
                    end
                    return best
                end

                -- Modules needed only for the custom title bar widget.
                local Size           = require("ui/size")
                local RightContainer = require("ui/widget/container/rightcontainer")
                local Button         = require("ui/widget/button")

                show_dialog = function()
                    if dialog then UIManager:close(dialog) end

                    local bold_sz = bold_preset()

                    -- ⋮ sub-menu defined here so it can close `dialog` via upvalue.
                    local function open_sub()
                        local sub
                        sub = ButtonDialog:new{
                            buttons = {
                                {{
                                    text     = "Reset to Default",
                                    callback = function()
                                        local default_size =
                                            (G_defaults and G_defaults:readSetting("DCREREADER_CONFIG_FONT_SIZE"))
                                            or 22
                                        cur_size = math.max(FONT_MIN, math.min(FONT_MAX, default_size))
                                        font_module:onSetFontSize(cur_size)
                                        UIManager:close(sub)
                                        show_dialog()
                                    end,
                                }},
                                {{
                                    text     = "Apply to All Books",
                                    callback = function()
                                        if G_reader_settings then
                                            G_reader_settings:saveSetting("copt_font_size", cur_size)
                                        end
                                        local ds = pbw_ref.ui and pbw_ref.ui.doc_settings
                                        if ds then
                                            ds:delSetting("font_size")
                                            ds:delSetting("copt_font_size")
                                        end
                                        UIManager:close(sub)
                                        UIManager:close(dialog)
                                    end,
                                }},
                                {{
                                    text     = "Cancel",
                                    callback = function() UIManager:close(sub) end,
                                }},
                            },
                        }
                        UIManager:show(sub)
                    end

                    -- Custom title bar: "Font Size" centered, ⋮ pinned to far right.
                    --
                    -- ButtonDialog._added_widgets are placed in its title area VerticalGroup
                    -- before the button table. We pre-compute the width to exactly match
                    -- what ButtonDialog derives internally:
                    --   dialog_w  → explicit width we pass
                    --   inner_w   = dialog_w - 2*border - 2*btn_pad   (ButtonTable width)
                    --   title_w   = inner_w - 2*(info_padding+info_margin)   (title_group_width)
                    local dialog_w = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.9)
                    local inner_w  = dialog_w - 2 * Size.border.window - 2 * Size.padding.button
                    local title_w  = inner_w  - 2 * (Size.padding.default + Size.margin.default)
                    local title_h  = Screen:scaleBySize(44)

                    local title_header = OverlapGroup:new{
                        dimen         = Geom:new{ w = title_w, h = title_h },
                        not_focusable = true,   -- let ButtonDialog skip focus registration
                        -- Centered label
                        CenterContainer:new{
                            dimen = Geom:new{ w = title_w, h = title_h },
                            TextWidget:new{
                                text = "Font Size",
                                face = Font:getFace("cfont", 18),
                                bold = true,
                            },
                        },
                        -- ⋮ anchored to the right edge
                        RightContainer:new{
                            dimen = Geom:new{ w = title_w, h = title_h },
                            Button:new{
                                text      = "⋮",
                                font_size = 18,
                                bordersize = 0,
                                padding   = Screen:scaleBySize(6),
                                callback  = open_sub,
                            },
                        },
                    }

                    local size_row = {}
                    for _, sz in ipairs(PRESET_SIZES) do
                        size_row[#size_row + 1] = {
                            text      = tostring(sz),
                            font_size = sz,
                            font_bold = (sz == bold_sz),
                            callback  = function()
                                cur_size = sz
                                font_module:onSetFontSize(cur_size)
                                show_dialog()
                            end,
                        }
                    end

                    dialog = ButtonDialog:new{
                        width          = dialog_w,
                        _added_widgets = { title_header },
                        buttons = {
                            size_row,
                            {
                                {
                                    text     = "−",
                                    enabled  = cur_size > FONT_MIN,
                                    callback = function()
                                        cur_size = math.max(FONT_MIN, cur_size - 1)
                                        font_module:onSetFontSize(cur_size)
                                        show_dialog()
                                    end,
                                },
                                {
                                    text     = "+",
                                    enabled  = cur_size < FONT_MAX,
                                    callback = function()
                                        cur_size = math.min(FONT_MAX, cur_size + 1)
                                        font_module:onSetFontSize(cur_size)
                                        show_dialog()
                                    end,
                                },
                            },
                            {{
                                text     = "Done",
                                callback = function() UIManager:close(dialog) end,
                            }},
                        },
                    }
                    UIManager:show(dialog)
                end
                show_dialog()
            end

            -- Left to right: TOC, Bookmark, Font, Search
            table.insert(self.title_bar, make_right_btn("appbar.search",     right_x - slot_w,     open_search))
            table.insert(self.title_bar, make_right_btn("appbar.textsize",   right_x - slot_w * 2, open_font_menu))
            table.insert(self.title_bar, make_right_btn("bookmark",          right_x - slot_w * 3, open_bookmarks))
            table.insert(self.title_bar, make_right_btn("appbar.navigation", right_x - slot_w * 4, open_toc, _toc_icon_path))

            -- Restore last-used layout; default to single page if no preference saved.
            local _saved_layout = G_reader_settings
                and G_reader_settings:readSetting("zen_page_browser_layout")
            if _saved_layout ~= "grid" then
                self._zen_nb_cols_override = 1
                self._zen_nb_rows_override = 1
                self:updateLayout()
            end
        end

        -- ----------------------------------------------------------------
        -- 2. Patch updateLayout: swap BookMapRow ribbon for ZenSlider+labels
        -- ----------------------------------------------------------------
        local _orig_updateLayout = PageBrowserWidget.updateLayout

        -- Pre-measure panel height once so we can inject it as row_height
        -- before _orig_updateLayout runs. This means the native code computes
        -- grid_height = screen_h - title_h - panel_h, sizes thumbnails to fit
        -- that exact space, and positions them with correct offsets. No
        -- post-hoc shrinking = no thumbnail overlap.
        local zen_icon_size = Screen:scaleBySize(24)
        local zen_icon_pad_h = Screen:scaleBySize(20)  -- horizontal padding (wider buttons)
        local zen_icon_pad_v = Screen:scaleBySize(10)  -- vertical padding (taller buttons)
        local zen_panel_pad_v = Screen:scaleBySize(6)  -- panel vertical padding (between elements)
        local zen_panel_pad_top = Screen:scaleBySize(12)  -- extra top padding
        local zen_panel_pad_bottom = Screen:scaleBySize(12)  -- extra bottom padding

        local function zen_measure_panel_h(nb_pages)
            local knob_r   = Screen:scaleBySize(16.5)  -- matches ZenSlider default
            local slider_h = knob_r * 2 + Screen:scaleBySize(6)
            -- Measure label height from a live TextWidget
            local tw = TextWidget:new{ text = "Wg",
                                       face = Font:getFace("cfont", 14),
                                       padding = 0 }
            local lh = tw:getSize().h
            tw:free()
            -- Button group: icon + vert padding * 2 + border * 2
            local btn_h = zen_icon_size + zen_icon_pad_v * 2 + Screen:scaleBySize(2) * 2
            -- top_pad + panel_pads + 1× label + (optional slider) + 1× icon row + bottom_pad
            -- Only include slider height and spacing if there's more than 1 page
            if nb_pages and nb_pages > 1 then
                return zen_panel_pad_top + 2 * zen_panel_pad_v + lh + slider_h + btn_h + zen_panel_pad_bottom
            else
                return zen_panel_pad_top + zen_panel_pad_v + lh + btn_h + zen_panel_pad_bottom
            end
        end

        PageBrowserWidget.updateLayout = function(self)
            -- Free any panel we built in a previous updateLayout call.
            if self._zen_row_panel then
                if self._zen_row_panel.free then self._zen_row_panel:free() end
                self._zen_row_panel = nil
            end

            -- Inject our required panel height as row_height BEFORE calling
            -- _orig_updateLayout. The native code uses self.row_height if it
            -- is already set — but it recomputes it unconditionally, so we
            -- must monkey-patch span_height temporarily to coerce the result.
            -- Simpler: just call _orig_updateLayout, then rebuild the grid
            -- from scratch with the correct height. Instead we use the cleanest
            -- approach: override nb_toc_spans to 0 via a temporary shim so
            -- the native row_height formula yields the minimum, then fix up.
            --
            -- Actually the cleanest approach: run _orig_updateLayout normally,
            -- then rebuild self.grid (OverlapGroup) with the corrected height.
            -- The native code rebuilds self.grid from scratch inside
            -- _orig_updateLayout, so we just need to redo that part.
            local zen_panel_h = zen_measure_panel_h(self.nb_pages or 1)

            -- The native row_height formula is:
            --   ceil((nb_toc_spans + page_slots_height_ratio + 1) * span_height + 2*border)
            -- where page_slots_height_ratio = 0.2 (stats off, toc > 0) or 1 (otherwise).
            -- On books with many TOC levels (e.g. nb_toc_spans = 10) the naive
            -- approach of inflating span_height to fit zen_panel_h at factor=2
            -- blows row_height up 5-6x.  Pre-compute nb_toc_spans from settings
            -- (same path as native updateLayout) to solve for the exact span_height
            -- that targets row_height = zen_panel_h + top_pad.
            local top_pad    = Screen:scaleBySize(6)
            local nb_toc_pre
            if self.ui.handmade and self.ui.handmade:isHandmadeTocEnabled() then
                nb_toc_pre = self.ui.doc_settings:readSetting("page_browser_toc_depth_handmade_toc") or self.max_toc_depth
            else
                nb_toc_pre = self.ui.doc_settings:readSetting("page_browser_toc_depth") or self.max_toc_depth
            end
            nb_toc_pre = nb_toc_pre or 0
            local stats_on = self.ui.statistics and self.ui.statistics:isEnabled()
            local psr      = (not stats_on and nb_toc_pre > 0) and 0.2 or 1
            local BookMapRow = require("ui/widget/bookmapwidget").BookMapRow
            local border2    = 2 * BookMapRow.pages_frame_border
            local factor     = nb_toc_pre + psr + 1
            -- Solve: factor * span_height + border2 = zen_panel_h + top_pad
            local target_span = math.max(1, math.floor((zen_panel_h + top_pad - border2) / factor))
            local orig_span_h = self.span_height
            self.span_height  = target_span

            -- _orig_updateLayout UNCONDITIONALLY overwrites self.nb_cols/nb_rows
            -- by reading from doc_settings (key: "page_browser_nb_cols/rows").
            -- Temporarily patch those keys so our forced layout survives.
            local ds = self.ui and self.ui.doc_settings
            local _saved_ds_cols, _saved_ds_rows, _zen_ds_patched
            if self._zen_nb_cols_override then
                local nc = self._zen_nb_cols_override
                local nr = self._zen_nb_rows_override or nc
                self._zen_nb_cols_override = nil
                self._zen_nb_rows_override = nil
                logger.dbg("ZenUI page_browser: forcing cols="..nc.." rows="..nr)
                if ds then
                    _saved_ds_cols = ds:readSetting("page_browser_nb_cols")
                    _saved_ds_rows = ds:readSetting("page_browser_nb_rows")
                    logger.dbg("ZenUI page_browser: saved ds cols="..tostring(_saved_ds_cols).." rows="..tostring(_saved_ds_rows))
                    ds:saveSetting("page_browser_nb_cols", nc)
                    ds:saveSetting("page_browser_nb_rows", nr)
                    _zen_ds_patched = true
                else
                    -- no doc_settings: set directly (won't be overwritten)
                    self.nb_cols = nc
                    self.nb_rows = nr
                end
            end

            -- Reset cached tile size; the new layout will re-seed it on
            -- the first showTile call.
            self._zen_tile_size = nil

            _orig_updateLayout(self)

            logger.dbg("ZenUI page_browser: after orig nb_cols="..tostring(self.nb_cols).." nb_rows="..tostring(self.nb_rows).." nb_grid_items="..tostring(self.nb_grid_items))

            -- Restore span_height so the detached BookMapRow is self-consistent.
            self.span_height = orig_span_h
            -- Restore doc_settings to original values (undo temporary patch).
            -- If the key didn't exist before, delete it rather than saveSetting(nil).
            if _zen_ds_patched and ds then
                if _saved_ds_cols ~= nil then
                    ds:saveSetting("page_browser_nb_cols", _saved_ds_cols)
                else
                    ds:delSetting("page_browser_nb_cols")
                end
                if _saved_ds_rows ~= nil then
                    ds:saveSetting("page_browser_nb_rows", _saved_ds_rows)
                else
                    ds:delSetting("page_browser_nb_rows")
                end
                logger.dbg("ZenUI page_browser: restored ds cols="..tostring(_saved_ds_cols).." rows="..tostring(_saved_ds_rows))
            end

            -- Suppress native left-side page number widgets: we draw our own
            -- badges in paintTo() instead.  showTile() checks show_pagenum on
            -- the FrameContainer before inserting a TextBoxWidget; clearing it
            -- here stops future insertions.  Then remove any already inserted
            -- during the update() call that _orig_updateLayout makes internally.
            for i = 1, (self.nb_grid_items or 0) do
                if self.grid[i] then
                    self.grid[i].show_pagenum = false
                end
            end
            for i = #self.grid, 1, -1 do
                if self.grid[i] and self.grid[i].is_page_num_widget then
                    if self.grid[i].free then self.grid[i]:free() end
                    table.remove(self.grid, i)
                end
            end

            -- After _orig_updateLayout:
            --  self.row_height  ≈ zen_panel_h + top_pad
            --  self.grid_height  = screen_h - title_h - zen_panel_h - top_pad
            --  self.grid         = OverlapGroup sized to grid_height (correct)
            --  self.row          = CenterContainer (kept detached)

            -- Cache the grid screen region for targeted dirty calls while
            -- scrubbing.  Expand by Size.border.thin on the top edge so that
            -- the first row's border overflow is included in every screen flush.
            local _gd_bs = Size.border.thin
            local _scrub_top = math.max(0, self.dimen.y + (self.title_bar_h or 0) + top_pad - _gd_bs)
            self._zen_grid_dimen = Geom:new{
                x = self.dimen.x,
                y = _scrub_top,
                w = self.grid_width or self.dimen.w,
                h = (self.grid_height or 0) + _gd_bs,
            }
            -- Combined region covering grid + panel (including the slider).
            -- Using one dirty call with the correct waveform is crucial: the
            -- "fast" (A2) waveform is black/white-only and corrupts the gray
            -- badge backgrounds; "ui" (GL16) handles gray correctly.
            self._zen_scrub_dimen = Geom:new{
                x = self.dimen.x,
                y = _scrub_top,
                w = self.dimen.w,
                h = self.dimen.h + self.dimen.y - _scrub_top,
            }

            local nb_pages  = self.nb_pages  or 1
            local cur_page  = self.focus_page or self.cur_page or 1
            local grid_w    = self.grid_width or Screen:getWidth()

            -- Derive the thumbnail-span width from the actual layout, then use
            -- roughly half of that for the slider so it sits as a short centred
            -- track rather than spanning edge-to-edge.
            local outer_margin = (self.grid[1] and self.grid[1].overlap_offset
                                  and self.grid[1].overlap_offset[1]) or 0
            local thumb_span = math.max(1, grid_w - 2 * outer_margin)
            local slider_w   = math.floor(thumb_span * 0.95)

            local function chapter_title(pg)
                if not self.ui or not self.ui.toc then return "" end
                return self.ui.toc:getTocTitleByPage(pg) or ""
            end

            local label_face = Font:getFace("cfont", 14)
            local pad_v      = zen_panel_pad_v

            -- Use focus_page consistently so slider position doesn't jump when switching views
            local cp = self.focus_page or cur_page
            local chap_label = TextWidget:new{
                text      = chapter_title(cp),
                face      = label_face,
                max_width = slider_w,
                padding   = 0,
            }

            -- Throttle interval for setDirty during drag (seconds).
            -- GL16 takes ~450ms on Kobo; firing faster than this just queues
            -- competing waveform cycles that produce artifacts.
            local SCRUB_DIRTY_INTERVAL = 0.15

            -- Deferred full update used to debounce thumbnail re-render during drag.
            -- Fires after 250 ms of slider inactivity regardless of whether the
            -- finger is still down; if the user resumes dragging, on_change will
            -- re-enable scrubbing and reschedule.
            self._zen_deferred_update = function()
                self._zen_scrubbing = false
                self._zen_placeholders_painted = false
                self._zen_last_scrub_dirty = nil
                self._zen_post_scrub = true
                UIManager:unschedule(self._zen_post_scrub_clear)
                UIManager:scheduleIn(0.4, self._zen_post_scrub_clear)
                self:update()
            end

            -- Clears post-scrub suppression and fires one clean repaint to show
            -- all tiles that loaded during the suppression window without flashing.
            self._zen_post_scrub_clear = function()
                self._zen_post_scrub = false
                UIManager:setDirty(self, "ui", self._zen_scrub_dimen or self.dimen)
            end

            -- Paint the slider (and optionally chapter label) directly to
            -- Screen.bb, bypassing the widget tree.  Then queue an
            -- A2-waveform hardware refresh of just the slider area via
            -- setDirty(nil, ...) — nil means "don't repaint any widgets."
            -- A2 completes in ~60ms so frames can't pile up.
            local function directPaintSlider(sl, label, label_text)
                if not sl or not sl.dimen or not sl.dimen.x then return end
                sl:paintTo(Screen.bb, sl.dimen.x, sl.dimen.y)
                if label and label_text then
                    -- TextWidget doesn't set self.dimen in paintTo, so we
                    -- compute label position from the slider (which does).
                    -- Layout order: chapter label → pad_v → slider.
                    local lh = label:getSize().h
                    local label_y = sl.dimen.y - pad_v - lh
                    -- Erase the full slider_w row, then paint centred text.
                    Screen.bb:paintRect(sl.dimen.x, label_y, slider_w, lh,
                                        Blitbuffer.COLOR_WHITE)
                    label:setText(label_text)
                    local new_w = label:getSize().w
                    local label_x = sl.dimen.x + math.floor((slider_w - new_w) / 2)
                    label:paintTo(Screen.bb, label_x, label_y)
                end
                -- A2 refresh scoped to slider + chapter label so the grid's
                -- large area A2 doesn't flash the thin track ends.
                local sl_dimen = sl.dimen
                if label then
                    local lh = label:getSize().h
                    sl_dimen = Geom:new{
                        x = sl.dimen.x,
                        y = sl.dimen.y - pad_v - lh,
                        w = math.max(sl.dimen.w, slider_w),
                        h = sl.dimen.h + pad_v + lh,
                    }
                end
                UIManager:setDirty(nil, "fast", sl_dimen)
            end

            -- Paint blank placeholders with page-number badges directly to
            -- Screen.bb for all grid cells, then push one A2 refresh over
            -- the combined grid + slider region.
            --
            -- On the FIRST call after scrubbing starts, erase thumbnails and
            -- draw the static borders (they never move).  On subsequent calls,
            -- only erase + repaint the small badge area at the bottom of each
            -- cell — the borders stay untouched in the framebuffer.
            local badge_face_s = Font:getFace("cfont", 11)
            local ph_s         = Screen:scaleBySize(4)
            local pv_s         = Screen:scaleBySize(2)
            local bg_color_s   = Blitbuffer.gray(0x33)
            local fg_color_s   = Blitbuffer.gray(0xFF)
            local gap_bot_s    = Screen:scaleBySize(6)
            local bs_s         = Size.border.thin

            -- Pre-measure the maximum badge height (constant for all cells).
            local _badge_h_sample = TextWidget:new{
                text = "0", face = badge_face_s, padding = 0,
            }
            local badge_max_h = _badge_h_sample:getSize().h + 2 * pv_s
            _badge_h_sample:free()

            local function directPaintScrub(focus_pg, chap_text)
                local pbw  = self
                local bb   = Screen.bb
                local sl   = pbw._zen_slider
                local clbl = pbw._zen_chap_label
                local grid = pbw.grid
                if not grid then return end

                local fp    = focus_pg or pbw.focus_page or 1
                local shift = pbw.focus_page_shift or 0
                local np    = pbw.nb_pages or 1
                local n     = pbw.nb_grid_items or 0

                -- Grid top-left in blitbuffer space
                local title_h = (pbw.title_bar and pbw.title_bar:getSize().h) or 0
                local gx = pbw.dimen.x or 0
                local gy = (pbw.dimen.y or 0) + title_h + Screen:scaleBySize(6)

                local first_frame = not pbw._zen_placeholders_painted

                for i = 1, n do
                    local item = grid[i]
                    if item and item.overlap_offset then
                        local page_num = fp - shift + (i - 1)
                        local ox = item.overlap_offset[1]
                        local oy = item.overlap_offset[2]
                        local sz = item:getSize()

                        if first_frame then
                            -- Erase cell + draw static border (once)
                            bb:paintRect(gx + ox - bs_s, gy + oy - bs_s,
                                         sz.w + 2 * bs_s, sz.h + 2 * bs_s,
                                         Blitbuffer.COLOR_WHITE)
                            local tw = (pbw._zen_tile_size and pbw._zen_tile_size.w) or sz.w
                            local th = (pbw._zen_tile_size and pbw._zen_tile_size.h) or sz.h
                            local pdx = math.floor((sz.w - tw) / 2)
                            local pdy = math.floor((sz.h - th) / 2)
                            bb:paintBorder(gx + ox + pdx - bs_s, gy + oy + pdy - bs_s,
                                           tw + 2 * bs_s, th + 2 * bs_s,
                                           bs_s, Blitbuffer.COLOR_BLACK, 0)
                        end

                        -- Badge area: erase + repaint (every frame)
                        -- Clip to the interior of the border so we never
                        -- overwrite the bottom line or corner pixels.
                        local tw = (pbw._zen_tile_size and pbw._zen_tile_size.w) or sz.w
                        local th = (pbw._zen_tile_size and pbw._zen_tile_size.h) or sz.h
                        local pdx = math.floor((sz.w - tw) / 2)
                        local pdy = math.floor((sz.h - th) / 2)
                        local inner_x = gx + ox + pdx
                        local inner_bottom = gy + oy + pdy + th
                        local badge_y = gy + oy + sz.h - badge_max_h - gap_bot_s
                        local erase_h = math.max(0, inner_bottom - badge_y)
                        if erase_h > 0 then
                            bb:paintRect(inner_x, badge_y, tw, erase_h,
                                     Blitbuffer.COLOR_WHITE)
                        end

                        if page_num >= 1 and page_num <= np then
                            local lbl = TextWidget:new{
                                text    = tostring(page_num),
                                face    = badge_face_s,
                                fgcolor = fg_color_s,
                                padding = 0,
                            }
                            local lsz = lbl:getSize()
                            local bh  = lsz.h + 2 * pv_s
                            local bw  = math.max(lsz.w + 2 * ph_s, bh)
                            local bx  = gx + ox + math.floor((sz.w - bw) / 2)
                            local by  = gy + oy + sz.h - bh - gap_bot_s

                            local r_p = bh / 2
                            for row = 0, bh - 1 do
                                local dy = math.abs(row + 0.5 - r_p)
                                local dx = math.sqrt(math.max(0, r_p * r_p - dy * dy))
                                local x0 = math.ceil(bx + r_p - dx)
                                local x1 = math.floor(bx + bw - r_p + dx)
                                local w  = x1 - x0
                                if w > 0 then bb:paintRect(x0, by + row, w, 1, bg_color_s) end
                            end

                            lbl:paintTo(bb,
                                bx + math.floor((bw - lsz.w) / 2),
                                by + math.floor((bh - lsz.h) / 2))
                            lbl:free()
                        end
                    end
                end

                pbw._zen_placeholders_painted = true

                -- Paint slider + chapter label
                directPaintSlider(sl, clbl, chap_text)

                -- A2 refresh on grid only — slider has its own A2 call
                -- inside directPaintSlider (scoped to sl.dimen, matching
                -- the brightness/warmth slider pattern).
                UIManager:setDirty(nil, "fast", pbw._zen_grid_dimen or pbw.dimen)
            end

            -- Deferred scrub dirty: fires the throttled setDirty at the end
            -- of the throttle window so the most recent state is displayed.
            self._zen_scrub_dirty_func = function()
                if not self._zen_scrubbing then return end
                self._zen_last_scrub_dirty = os.clock()
                directPaintScrub(self.focus_page or self.cur_page or 1,
                    chapter_title(self.focus_page or self.cur_page or 1))
            end

            -- Only create slider if there's more than 1 page
            local zen_slider
            if nb_pages > 1 then
                zen_slider = ZenSlider:new{
                    width       = slider_w,
                    value       = cp,
                    value_min   = 1,
                    value_max   = math.max(nb_pages, 1),
                    on_change   = function(v)
                        -- Set scrubbing BEFORE updateFocusPage so that any
                        -- showTile callbacks it triggers are already suppressed,
                        -- preventing a flash of stale tile bitmaps on drag start.
                        local dragging = self._zen_slider and self._zen_slider._dragging
                        if dragging then
                            self._zen_scrubbing = true
                            -- Cancel any pending post-scrub clear so resuming a
                            -- drag after a pause doesn't re-enable tile refreshes.
                            UIManager:unschedule(self._zen_post_scrub_clear)
                        end
                        if self:updateFocusPage(v, false) then
                            if dragging then
                                UIManager:unschedule(self._zen_deferred_update)
                                UIManager:scheduleIn(0.25, self._zen_deferred_update)
                                -- Paint grid placeholders + slider + label
                                -- directly to Screen.bb and push one A2 refresh.
                                directPaintScrub(v, chapter_title(v))
                            else
                                UIManager:unschedule(self._zen_deferred_update)
                                UIManager:unschedule(self._zen_scrub_dirty_func)
                                self._zen_scrubbing = false
                                self._zen_placeholders_painted = false
                                self._zen_last_scrub_dirty = nil
                                self._zen_post_scrub = true
                                UIManager:unschedule(self._zen_post_scrub_clear)
                                UIManager:scheduleIn(0.4, self._zen_post_scrub_clear)
                                self:update()
                            end
                        end
                    end,
                }
            end

            self._zen_slider     = zen_slider
            self._zen_chap_label = chap_label

            -- View-mode toggle buttons: single page / grid.
            -- Create a unified button group with divider and active state styling.
            local pbw = self

            -- Determine current layout mode
            local is_single_page = (self.nb_cols == 1 and self.nb_rows == 1)

            local grid_slide_path = _icons_dir and utils.resolveLocalIcon(_icons_dir, "grid_slide")
            local grid_path = _icons_dir and utils.resolveLocalIcon(_icons_dir, "grid")

            -- Create icon widgets with active state styling
            local icon_size = zen_icon_size
            local icon_pad_h = zen_icon_pad_h
            local icon_pad_v = zen_icon_pad_v

            local icon_view = IconWidget:new{
                file   = grid_slide_path,
                icon   = grid_slide_path and nil or "grid_slide",
                width  = icon_size,
                height = icon_size,
                alpha  = not is_single_page, -- opaque when active, alpha when inactive
            }

            local icon_grid = IconWidget:new{
                file   = grid_path,
                icon   = grid_path and nil or "grid",
                width  = icon_size,
                height = icon_size,
                alpha  = is_single_page, -- opaque when active, alpha when inactive
            }

            -- Invert the active icon (white icon on black bg)
            if is_single_page then
                icon_view:_render()
                if icon_view._bb then
                    local bb_copy = icon_view._bb:copy()
                    bb_copy:invertRect(0, 0, bb_copy:getWidth(), bb_copy:getHeight())
                    icon_view._bb = bb_copy
                end
            else
                icon_grid:_render()
                if icon_grid._bb then
                    local bb_copy = icon_grid._bb:copy()
                    bb_copy:invertRect(0, 0, bb_copy:getWidth(), bb_copy:getHeight())
                    icon_grid._bb = bb_copy
                end
            end

            -- Wrap icons in fixed-width containers to ensure perfect centering
            local CenterContainer_ic = require("ui/widget/container/centercontainer")
            local icon_view_centered = CenterContainer_ic:new{
                dimen = Geom:new{ w = icon_size, h = icon_size },
                icon_view,
            }
            local icon_grid_centered = CenterContainer_ic:new{
                dimen = Geom:new{ w = icon_size, h = icon_size },
                icon_grid,
            }

            -- Container for left button (single page view) - no rounded inner corners
            local btn_view_frame = FrameContainer:new{
                padding_top    = icon_pad_v,
                padding_bottom = icon_pad_v,
                padding_left   = icon_pad_h,
                padding_right  = icon_pad_h,
                bordersize     = 0,
                background     = is_single_page and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
                icon_view_centered,
            }

            -- Container for right button (grid view) - no rounded inner corners
            local btn_grid_frame = FrameContainer:new{
                padding_top    = icon_pad_v,
                padding_bottom = icon_pad_v,
                padding_left   = icon_pad_h,
                padding_right  = icon_pad_h,
                bordersize     = 0,
                background     = is_single_page and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
                icon_grid_centered,
            }

            -- Vertical divider
            local LineWidget = require("ui/widget/linewidget")
            local divider = LineWidget:new{
                dimen          = Geom:new{
                    w = Screen:scaleBySize(1),
                    h = icon_size + icon_pad_v * 2,
                },
                background     = Blitbuffer.COLOR_DARK_GRAY,
                direction      = "vert",
            }

            -- Unified button group
            local btn_group = HorizontalGroup:new{
                align = "center",
                btn_view_frame,
                divider,
                btn_grid_frame,
            }

            -- Wrap in frame with border and rounded corners
            local btn_row = FrameContainer:new{
                padding        = 0,
                margin         = 0,
                bordersize     = Screen:scaleBySize(2),
                background     = Blitbuffer.COLOR_WHITE,
                radius         = Screen:scaleBySize(4),
                btn_group,
            }

            -- Switch callbacks
            local _switch_single = function()
                pbw._zen_nb_cols_override = 1
                pbw._zen_nb_rows_override = 1
                if G_reader_settings then
                    G_reader_settings:saveSetting("zen_page_browser_layout", "single")
                end
                logger.dbg("ZenUI page_browser: switch to single page")
                pbw:updateLayout()
                UIManager:setDirty(pbw, function() return "partial", pbw.dimen end)
            end
            local _switch_grid = function()
                pbw._zen_nb_cols_override = pbw._zen_orig_nb_cols or 3
                pbw._zen_nb_rows_override = pbw._zen_orig_nb_rows or 5
                if G_reader_settings then
                    G_reader_settings:saveSetting("zen_page_browser_layout", "grid")
                end
                logger.dbg("ZenUI page_browser: switch to grid")
                pbw:updateLayout()
                UIManager:setDirty(pbw, function() return "partial", pbw.dimen end)
            end
            self._zen_switch_single = _switch_single
            self._zen_switch_grid   = _switch_grid

            -- Store button group reference for tap handling
            self._zen_btn_group = btn_row
            self._zen_btn_view_frame = btn_view_frame
            self._zen_btn_grid_frame = btn_grid_frame

            -- Compute hit zones analytically from known panel layout.
            -- The button group is a unified widget, split into left/right tap zones.
            -- Panel top Y (screen-absolute):
            local panel_abs_y = (self.dimen.y or 0) + self.dimen.h - zen_panel_h
            -- Stack the VerticalGroup rows to find btn_row top:
            local btn_zone_y = panel_abs_y
                + zen_panel_pad_top
                + chap_label:getSize().h
                + pad_v

            -- Only add slider height if slider exists
            if zen_slider then
                btn_zone_y = btn_zone_y + zen_slider:getSize().h + pad_v
            end

            -- btn_row is CenterContainer'd horizontally in grid_w
            local btn_row_sz = btn_row:getSize()
            local btn_row_w = btn_row_sz.w
            local btn_row_h = btn_row_sz.h
            local btn_origin_x = (self.dimen.x or 0) + math.floor((grid_w - btn_row_w) / 2)

            -- Split button group into left (view) and right (grid) hit zones
            local half_w = math.floor(btn_row_w / 2)

            self._zen_btn_view_zone = Geom:new{
                x = btn_origin_x,
                y = btn_zone_y,
                w = half_w,
                h = btn_row_h,
            }
            self._zen_btn_grid_zone = Geom:new{
                x = btn_origin_x + half_w,
                y = btn_zone_y,
                w = btn_row_w - half_w,
                h = btn_row_h,
            }
            logger.dbg("ZenUI page_browser: btn_view_zone x="..self._zen_btn_view_zone.x.." y="..self._zen_btn_view_zone.y.." w="..self._zen_btn_view_zone.w.." h="..self._zen_btn_view_zone.h)
            logger.dbg("ZenUI page_browser: btn_grid_zone x="..self._zen_btn_grid_zone.x.." y="..self._zen_btn_grid_zone.y.." w="..self._zen_btn_grid_zone.w.." h="..self._zen_btn_grid_zone.h)

            -- Store panel height for onHold suppression.
            self._zen_panel_h = zen_panel_h

            -- Tighten the scrub dirty region so that the button row below
            -- the slider is never included in the A2/GL16 refresh during
            -- drag.  btn_zone_y is the top of the button group.
            self._zen_scrub_dimen.h = math.max(1, btn_zone_y - self._zen_scrub_dimen.y)

            -- Panel spans full grid width, pinned to the absolute bottom of
            -- the screen via OverlapGroup offset (set below).  Height is the
            -- measured content height, not the (larger) native row_height.

            -- Build panel content dynamically based on whether slider should be shown
            local panel_content = {
                align = "center",
                VerticalSpan:new{ width = zen_panel_pad_top },
                CenterContainer:new{
                    dimen = Geom:new{ w = grid_w, h = chap_label:getSize().h },
                    chap_label,
                },
            }

            -- Only add slider and its spacing if there's more than 1 page
            if zen_slider then
                table.insert(panel_content, VerticalSpan:new{ width = pad_v })
                table.insert(panel_content, CenterContainer:new{
                    dimen = Geom:new{ w = grid_w, h = zen_slider:getSize().h },
                    zen_slider,
                })
            end

            -- Add button group
            table.insert(panel_content, VerticalSpan:new{ width = pad_v })
            table.insert(panel_content, CenterContainer:new{
                dimen = Geom:new{ w = grid_w, h = btn_row:getSize().h },
                btn_row,
            })
            table.insert(panel_content, VerticalSpan:new{ width = zen_panel_pad_bottom })

            local panel = FrameContainer:new{
                width      = grid_w,
                height     = zen_panel_h,
                padding    = 0,
                margin     = 0,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                VerticalGroup:new(panel_content),
            }
            -- Pin panel to absolute screen bottom; grid gets the full space above.
            panel.overlap_offset = { 0, self.dimen.h - zen_panel_h }
            self._zen_row_panel = panel

            -- Use an OverlapGroup so the panel hovers over the bottom of the
            -- screen independently of the grid's natural height.  The
            -- VerticalGroup (title + small gap + grid) occupies the upper
            -- portion; the panel is drawn over the dead space below the grid.
            self[1] = FrameContainer:new{
                width      = self.dimen.w,
                height     = self.dimen.h,
                padding    = 0,
                margin     = 0,
                bordersize = 0,
                background = Blitbuffer.COLOR_WHITE,
                OverlapGroup:new{
                    dimen = Geom:new{ w = self.dimen.w, h = self.dimen.h },
                    VerticalGroup:new{
                        align = "center",
                        self.title_bar,
                        VerticalSpan:new{ width = top_pad },
                        self.grid,
                    },
                    panel,
                }
            }
        end

        -- ----------------------------------------------------------------
        -- 3. Update slider/labels whenever the focus page changes
        -- ----------------------------------------------------------------
        local _orig_update = PageBrowserWidget.update
        PageBrowserWidget.update = function(self)
            -- On the very first call (focus_page is nil, init → updateLayout → update),
            -- pre-initialise focus_page from cur_page with clamping so the grid
            -- never displays blank leading/trailing slots.  Subsequent calls
            -- (slider drag, scroll) already carry a valid focus_page and don't
            -- need adjustment.
            local shift = self.focus_page_shift
            local items = self.nb_grid_items
            local total = self.nb_pages
            if not self.focus_page and shift and items and total and total >= items then
                local fp     = self.cur_page or 1
                local min_fp = shift + 1
                local max_fp = math.max(min_fp, total - items + 1 + shift)
                self.focus_page = math.max(min_fp, math.min(max_fp, fp))
            end

            -- Block showTile() from re-adding native page number widgets.
            for i = 1, (self.nb_grid_items or 0) do
                if self.grid[i] then self.grid[i].show_pagenum = false end
            end

            -- _orig_update writes BookMapRow into self.row (detached CenterContainer)
            _orig_update(self)

            -- Clean up any page num widgets that slipped through (e.g. async tiles).
            for i = #self.grid, 1, -1 do
                if self.grid[i] and self.grid[i].is_page_num_widget then
                    if self.grid[i].free then self.grid[i]:free() end
                    table.remove(self.grid, i)
                end
            end

            -- Display info for the focus page.
            local fp    = self.focus_page or self.cur_page or 1
            local np    = self.nb_pages or 1
            local cp    = math.max(1, math.min(np, fp))

            if self._zen_slider then
                self._zen_slider:setValue(cp)
            end
            if self._zen_chap_label then
                local title = ""
                if self.ui and self.ui.toc then
                    title = self.ui.toc:getTocTitleByPage(cp) or ""
                end
                self._zen_chap_label:setText(title)
            end
        end

        -- ----------------------------------------------------------------
        -- 3a. showTile: cache actual tile pixel dimensions so scrubbing
        --     placeholders can draw borders at the correct centred position.
        -- ----------------------------------------------------------------
        local _orig_showTile = PageBrowserWidget.showTile
        PageBrowserWidget.showTile = function(self, grid_idx, page, tile, do_refresh)
            if tile and tile.bb and not self._zen_tile_size then
                self._zen_tile_size = {
                    w = tile.bb:getWidth(),
                    h = tile.bb:getHeight(),
                }
            end
            -- During scrubbing and for one full repaint cycle after scrubbing
            -- ends, suppress per-tile display refreshes.  Without this, each
            -- async tile that loads fires its own hardware update, producing
            -- the multi-flash artifact on the panel area.
            -- _zen_post_scrub is cleared by the next paintTo call.
            if (self._zen_scrubbing or self._zen_post_scrub) and do_refresh then
                return _orig_showTile(self, grid_idx, page, tile, false)
            end
            return _orig_showTile(self, grid_idx, page, tile, do_refresh)
        end

        -- ----------------------------------------------------------------
        -- 4. paintTo: suppress the viewfinder overlay; page-number badges
        -- ----------------------------------------------------------------
        PageBrowserWidget.paintTo = function(self, bb, x, y)
            local InputContainer = require("ui/widget/container/inputcontainer")
            InputContainer.paintTo(self, bb, x, y)
            -- viewfinder border and row-lines intentionally omitted

            if not (self.grid and self.focus_page) then return end

            local fp    = self.focus_page
            local shift = self.focus_page_shift or 0
            local np    = self.nb_pages or 1

            -- Grid top-left in blitbuffer coordinate space.
            -- OverlapGroup child 1 = VerticalGroup: title_bar → span(top_pad) → grid.
            local title_h = (self.title_bar and self.title_bar:getSize().h) or 0
            local gx      = x
            local gy      = y + title_h + Screen:scaleBySize(6) -- top_pad

            local badge_face = Font:getFace("cfont", 11)
            local ph         = Screen:scaleBySize(4)   -- badge horiz padding
            local pv         = Screen:scaleBySize(2)   -- badge vert  padding
            local bg_color   = Blitbuffer.gray(0x33)   -- dark badge fill
            local fg_color   = Blitbuffer.gray(0xFF)   -- white badge text
            local gap_bot    = Screen:scaleBySize(6)   -- badge offset from thumb bottom

            -- paintPill: horizontal capsule (rounded left/right, flat top/bottom).
            -- Ported from browser_page_count.lua.
            local function paintPill(bx, by, bw, bh, color)
                local r = bh / 2
                for row = 0, bh - 1 do
                    local dy = math.abs(row + 0.5 - r)
                    local dx = math.sqrt(math.max(0, r * r - dy * dy))
                    local x0 = math.ceil(bx + r - dx)
                    local x1 = math.floor(bx + bw - r + dx)
                    local w  = x1 - x0
                    if w > 0 then bb:paintRect(x0, by + row, w, 1, color) end
                end
            end

            -- Only iterate the real thumbnail slots (1..nb_grid_items).
            local n = self.nb_grid_items or 0
            for i = 1, n do
                local item = self.grid[i]
                if item and item.overlap_offset then
                    local page_num = fp - shift + (i - 1)
                    if page_num >= 1 and page_num <= np then
                        local ox = item.overlap_offset[1]
                        local oy = item.overlap_offset[2]
                        local sz = item:getSize()

                        -- While scrubbing: blank the cell then draw a bordered
                        -- placeholder sized to match the actual thumbnail.
                        if self._zen_scrubbing then
                            local bs = Size.border.thin
                            -- Erase full cell + overflow so stale thumbnail +
                            -- its border are completely hidden.
                            bb:paintRect(gx + ox - bs, gy + oy - bs,
                                         sz.w + 2 * bs, sz.h + 2 * bs,
                                         Blitbuffer.COLOR_WHITE)
                            -- Border sized to the cached tile pixel dimensions,
                            -- centred in the cell exactly as CenterContainer would.
                            -- Falls back to full cell until the first tile is seen.
                            local tw = (self._zen_tile_size and self._zen_tile_size.w) or sz.w
                            local th = (self._zen_tile_size and self._zen_tile_size.h) or sz.h
                            local pdx = math.floor((sz.w - tw) / 2)
                            local pdy = math.floor((sz.h - th) / 2)
                            bb:paintBorder(gx + ox + pdx - bs, gy + oy + pdy - bs,
                                           tw + 2 * bs, th + 2 * bs,
                                           bs, Blitbuffer.COLOR_BLACK, 0)
                        end

                        local label = TextWidget:new{
                            text    = tostring(page_num),
                            face    = badge_face,
                            fgcolor = fg_color,
                            padding = 0,
                        }
                        local lsz = label:getSize()
                        local bh  = lsz.h + 2 * pv
                        local bw  = math.max(lsz.w + 2 * ph, bh)  -- never narrower than a circle
                        local bx  = gx + ox + math.floor((sz.w - bw) / 2)
                        local by  = gy + oy + sz.h - bh - gap_bot

                        paintPill(bx, by, bw, bh, bg_color)
                        label:paintTo(bb,
                            bx + math.floor((bw - lsz.w) / 2),
                            by + math.floor((bh - lsz.h) / 2))
                        label:free()
                    end
                end
            end
        end

        -- ----------------------------------------------------------------
        -- 5. Gesture handling: slider, view-toggle buttons, panel boundary
        -- ----------------------------------------------------------------
        local _orig_onTap = PageBrowserWidget.onTap
        PageBrowserWidget.onTap = function(self, arg, ges)
            logger.dbg("ZenUI page_browser: onTap at "..ges.pos.x..","..ges.pos.y)
            -- 1. Slider tap → navigate to that page.
            if self._zen_slider and self._zen_slider:handleTap(ges) then
                logger.dbg("ZenUI page_browser: onTap → slider")
                return true
            end
            -- 2. View-toggle buttons: fallback for taps before the first paintTo,
            --    when btn.dimen.x/y are still 0 so the button's own ges_events
            --    won't match.  After first paint, the IconButton's onTapIconButton
            --    fires the callback directly (children-first propagation).
            --    Use zone:contains() — GestureRange also uses contains() for
            --    matching, so zero-area tap points on a border stay inclusive.
            if self._zen_btn_view_zone
               and self._zen_btn_view_zone:contains(ges.pos) then
                logger.dbg("ZenUI page_browser: onTap → btn_view (single)")
                if self._zen_switch_single then self._zen_switch_single() end
                return true
            end
            if self._zen_btn_grid_zone
               and self._zen_btn_grid_zone:contains(ges.pos) then
                logger.dbg("ZenUI page_browser: onTap → btn_grid")
                if self._zen_switch_grid then self._zen_switch_grid() end
                return true
            end
            -- 3. Any tap inside the panel strip → swallow.  Without this a
            --    tap falls through to _orig_onTap which hits the thumbnail
            --    behind the panel, navigates the page, and the slider jumps.
            local panel_h = self._zen_panel_h or 0
            if panel_h > 0 and self.dimen
               and ges.pos.y >= (self.dimen.y + self.dimen.h - panel_h) then
                return true
            end
            -- 4. Thumbnail grid area → native handler.
            return _orig_onTap(self, arg, ges)
        end

        PageBrowserWidget.onPan = function(self, arg, ges)
            if self._zen_slider and not self._zen_slider_locked then
                if self._zen_slider:handlePan(ges) then return true end
            end
            return true  -- swallow all other pans
        end

        PageBrowserWidget.onPanRelease = function(self, arg, ges)
            if self._zen_slider
               and self._zen_slider:handlePanRelease(ges, self, self.dimen) then
                -- handlePanRelease fires on_change only when the slider value
                -- actually changes; if the release lands on the same page as
                -- the last pan, on_change won't fire and _zen_scrubbing would
                -- stay true until the 250 ms deferred fires.  Always clean up
                -- here so thumbnails reload immediately on finger lift.
                if self._zen_scrubbing then
                    UIManager:unschedule(self._zen_deferred_update)
                    self._zen_scrubbing = false
                    self._zen_placeholders_painted = false
                    self._zen_post_scrub = true
                    UIManager:unschedule(self._zen_post_scrub_clear)
                    UIManager:scheduleIn(0.4, self._zen_post_scrub_clear)
                    self:update()
                end
                return true
            end
            -- Swallow releases in the panel strip (e.g. near button group).
            local panel_h = self._zen_panel_h or 0
            if panel_h > 0 and self.dimen
               and ges.pos.y >= (self.dimen.y + self.dimen.h - panel_h) then
                return true
            end
            return true
        end

        -- ----------------------------------------------------------------
        -- 6. Gesture lockdown: only horizontal swipe (page prev/next)
        -- ----------------------------------------------------------------
        PageBrowserWidget.onSwipe = function(self, _arg, ges)
            -- A fast drag on the slider is classified as a swipe rather than
            -- pan + pan_release; ZenSlider.handleSwipe covers both cases.
            if self._zen_slider and not self._zen_slider_locked then
                -- Pre-set scrubbing BEFORE handleSwipe so that on_change's
                -- call to updateFocusPage (which triggers async tile loads)
                -- already has the suppress flag set when was_dragging=false.
                -- If handleSwipe doesn't claim the gesture we clear it below.
                self._zen_scrubbing = true
                UIManager:unschedule(self._zen_post_scrub_clear)
                if self._zen_slider:handleSwipe(ges, self, self.dimen) then
                    -- was_dragging=false: on_change already fired and transitioned
                    -- to _zen_post_scrub, so _zen_scrubbing is now false. Nothing to do.
                    -- was_dragging=true: on_change never fires; clean up here.
                    if self._zen_scrubbing then
                        UIManager:unschedule(self._zen_deferred_update)
                        self._zen_scrubbing = false
                        self._zen_placeholders_painted = false
                        self._zen_post_scrub = true
                        UIManager:scheduleIn(0.4, self._zen_post_scrub_clear)
                        self:update()
                    end
                    return true
                end
                -- handleSwipe didn't claim the gesture; undo the pre-set.
                self._zen_scrubbing = false
                self._zen_placeholders_painted = false
            end
            local direction = ges.direction
            if direction == "west" then
                self:onScrollPageDown()
                return true
            elseif direction == "east" then
                self:onScrollPageUp()
                return true
            end
            return true  -- swallow north/south and anything else
        end

        -- Suppress hold gestures in the bottom panel area so they don't
        -- trigger the native book-map-row popup.
        local _orig_onHold = PageBrowserWidget.onHold
        PageBrowserWidget.onHold = function(self, arg, ges)
            local panel_h = self._zen_panel_h or 0
            if panel_h > 0 and self.dimen
               and ges.pos.y >= (self.dimen.y + self.dimen.h - panel_h) then
                return true  -- swallow
            end
            if _orig_onHold then return _orig_onHold(self, arg, ges) end
        end

        PageBrowserWidget.onPinch  = function() return true end
        PageBrowserWidget.onSpread = function() return true end
        PageBrowserWidget.onMultiSwipe = function(self, arg, ges)
            if self._zen_slider then
                self._zen_slider:handleMultiSwipe(ges, self, self.dimen)
            end
            -- handleMultiSwipe can also terminate a drag without firing on_change.
            if self._zen_scrubbing then
                UIManager:unschedule(self._zen_deferred_update)
                self._zen_scrubbing = false
                self._zen_placeholders_painted = false
                self._zen_post_scrub = true
                UIManager:unschedule(self._zen_post_scrub_clear)
                UIManager:scheduleIn(0.4, self._zen_post_scrub_clear)
                self:update()
            end
            -- Swallow all multiswipes; never close the page browser.
            return true
        end
    end

    -- -----------------------------------------------------------------------
    -- Open KOReader's native PageBrowserWidget (with Zen UI tweaks)
    -- -----------------------------------------------------------------------
    local function open_page_browser(ui)
        local PageBrowserWidget = require("ui/widget/pagebrowserwidget")
        zen_patch_page_browser_widget()
        UIManager:show(PageBrowserWidget:new{ ui = ui })
    end

    -- Patch ReaderMenu.initGesListener to register the swipe-up zone
    -- -----------------------------------------------------------------------
    local ReaderMenu = require("apps/reader/modules/readermenu")
    local _orig_initGesListener = ReaderMenu.initGesListener

    local function register_page_browser_zone(ui)
        ui:registerTouchZones({
            {
                id          = "zen_page_browser_reader",
                ges         = "swipe",
                screen_zone = {
                    ratio_x = 0, ratio_y = 0.86, ratio_w = 1, ratio_h = 0.14,
                },
                -- Override the config-menu and page-turn swipe zones so our
                -- north-swipe wins.  We deliberately do NOT override the tap
                -- zones (readerconfigmenu_tap etc.) — those cause unintended
                -- pan/brightness-slider interference via the zone sort order.
                overrides = {
                    "readerconfigmenu_swipe",
                    "readerconfigmenu_ext_swipe",
                    "paging_swipe",
                    "rolling_swipe",
                },
                handler = function(ges)
                    if not is_enabled() then return end
                    if ges.direction == "north" then
                        open_page_browser(ui)
                        ui:handleEvent(Event:new("HandledAsSwipe"))
                        return true
                    end
                end,
            },
        })
    end

    ReaderMenu.initGesListener = function(self_rm)
        if _orig_initGesListener then
            _orig_initGesListener(self_rm)
        end
        register_page_browser_zone(self_rm.ui)
    end

    -- onReaderReady is aliased to initGesListener in KOReader; keep in sync
    ReaderMenu.onReaderReady = ReaderMenu.initGesListener

    -- If a book is already open when this patch is applied (feature toggled
    -- at runtime), register the zone immediately.
    local ok_rui, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok_rui and ReaderUI and ReaderUI.instance then
        pcall(register_page_browser_zone, ReaderUI.instance)
    end

    -- -----------------------------------------------------------------------
    -- Zen UI customisations for fulltext search dialog
    -- -----------------------------------------------------------------------
    local ok_rs, ReaderSearch = pcall(require, "apps/reader/modules/readersearch")
    if ok_rs and ReaderSearch then
        local BD          = require("ui/bidi")
        local InputDialog = require("ui/widget/inputdialog")
        local CheckButton = require("ui/widget/checkbutton")
        local Screen_s    = require("device").screen
        local _           = require("gettext")
        local logger_rs   = require("logger")

        local _orig_onShowFulltextSearchInput = ReaderSearch.onShowFulltextSearchInput

        ReaderSearch.onShowFulltextSearchInput = function(self, search_string)
            local backward_text = "◁"
            local forward_text  = "▷"
            if BD.mirroredUILayout() then
                backward_text, forward_text = forward_text, backward_text
            end
            self.input_dialog = InputDialog:new{
                title = _("Enter text to search for"),
                width = math.floor(math.min(Screen_s:getWidth(), Screen_s:getHeight()) * 0.9),
                input = search_string
                    or self.last_search_text
                    or (self.ui.doc_settings
                        and self.ui.doc_settings:readSetting("fulltext_search_last_search_text")),
                -- X in the title bar replaces the Cancel button
                title_bar_left_icon = "close",
                title_bar_left_icon_tap_callback = function()
                    UIManager:close(self.input_dialog)
                end,
                buttons = {
                    -- Row 1: directional arrows
                    {
                        {
                            text     = backward_text,
                            callback = function()
                                self:searchCallback(1)
                            end,
                        },
                        {
                            text     = forward_text,
                            callback = function()
                                self:searchCallback(0)
                            end,
                        },
                    },
                    -- Row 2: Search (formerly "All" / find-all)
                    {
                        {
                            text             = _("Search"),
                            is_enter_default = true,
                            callback         = function()
                                self:searchCallback()
                            end,
                        },
                    },
                },
            }
            self.check_button_case = CheckButton:new{
                text     = _("Case sensitive"),
                checked  = not self.case_insensitive,
                parent   = self.input_dialog,
            }
            self.input_dialog:addWidget(self.check_button_case)
            -- Regex option intentionally omitted, but searchCallback reads
            -- self.check_button_regex.checked unconditionally, so provide a
            -- stub that always returns false (no regex).
            self.check_button_regex = { checked = false }
            UIManager:show(self.input_dialog)
            self.input_dialog:onShowKeyboard()
        end

        -- Patch onShowFindAllResults: fix reader-content ghosting at the bottom
        -- of the screen when search results are shown.
        --
        -- ROOT CAUSE: Menu:new{} runs while Screen:getHeight() is still reduced
        -- by the virtual keyboard (shown for our search InputDialog). This makes
        -- menu.dimen.h and the internal OverlapGroup dimen height equal to the
        -- keyboard-shrunk height (~1525 vs real 1696 on a Kobo). Menu:init()
        -- creates its FrameContainer WITHOUT an explicit height — so the FC's
        -- paintTo uses `self.height or my_size.h = nil or 1525 = 1525`, filling
        -- only 1525px of white background and leaving the bottom 171px untouched
        -- (showing through the reader content in the framebuffer).
        --
        -- By the time our wrapper runs (after UIManager:show(result_menu) returns),
        -- the keyboard has been dismissed and Screen:getHeight() is back to the
        -- real value. We patch menu.dimen.h (gesture hit range) and set an
        -- explicit menu[1].height (FrameContainer) so its background fill covers
        -- the full screen.  Then forceRePaint() paints the full white background
        -- synchronously before the flashui refresh fires.
        local _orig_onShowFindAllResults = ReaderSearch.onShowFindAllResults
        ReaderSearch.onShowFindAllResults = function(self, not_cached)
            _orig_onShowFindAllResults(self, not_cached)
            local menu = self.result_menu
            if not menu or not UIManager:isWidgetShown(menu) then return end

            local real_h = Screen_s:getHeight()

            -- Fix outer dimen so gesture hit-testing covers the full screen.
            if menu.dimen and menu.dimen.h < real_h then
                logger_rs.info("ZenUI [search] fixing menu height:", menu.dimen.h, "→", real_h)
                menu.dimen.h = real_h
            end

            -- Force an explicit height on the FrameContainer so its white
            -- background fill (container_height = self.height or my_size.h)
            -- extends to the full screen rather than stopping at the
            -- keyboard-shrunk OverlapGroup height.
            local fc = menu[1]
            if fc then
                fc.height = real_h
            end

            UIManager:setDirty(menu, "flashui")
            UIManager:forceRePaint()
        end
    end

    -- -----------------------------------------------------------------------
    -- Primary intercept: patch ReaderConfig.onSwipeShowConfigMenu directly.
    -- More reliable than zone-override ordering since it does not depend on
    -- the dep-graph re-serialisation happening in the right order.
    -- -----------------------------------------------------------------------
    local ok_rc, ReaderConfig = pcall(require, "apps/reader/modules/readerconfig")
    if ok_rc and ReaderConfig then
        local _orig_onSwipeShowConfigMenu = ReaderConfig.onSwipeShowConfigMenu
        ReaderConfig.onSwipeShowConfigMenu = function(self_rc, ges)
            if is_enabled() and ges.direction == "north" then
                open_page_browser(self_rc.ui)
                self_rc.ui:handleEvent(Event:new("HandledAsSwipe"))
                return true
            end
            if _orig_onSwipeShowConfigMenu then
                return _orig_onSwipeShowConfigMenu(self_rc, ges)
            end
        end
    end

end -- apply_page_browser

return apply_page_browser

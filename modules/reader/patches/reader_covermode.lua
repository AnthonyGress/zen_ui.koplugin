-- modules/reader/patches/reader_covermode.lua
local function apply_covermode()
    --[[
    Patch: Cover Mode - Add cover mode for highlights (highlight, underline, strikethrough, invert) for review
    ]]

    local Blitbuffer = require("ffi/blitbuffer")
    local UIManager = require("ui/uimanager")
    local Dispatcher = require("dispatcher")
    local Event = require("ui/event")
    local _ = require("gettext")

    -- Helper function: Check if a point is inside a rectangle
    local function inside_box(pos, box)
        if pos then
            local x, y = pos.x, pos.y
            if box.x <= x and box.y <= y
                and box.x + box.w >= x
                and box.y + box.h >= y then
                return true
            end
        end
        return false
    end

    -- Get the actual page number of a rect (for continuous mode)
    local function getPageFromScreenRect(self, rect)
        if not self.page_states then
            return self.state and self.state.page or 1
        end
        
        local y = rect.y
        local y_offset = 0
        local gap = (self.page_gap and self.page_gap.height) or 0
        
        for _, state in ipairs(self.page_states) do
            if y >= y_offset and y < y_offset + state.visible_area.h then
                return state.page
            end
            y_offset = y_offset + state.visible_area.h + gap
        end
        
        return self.page_states[1] and self.page_states[1].page or 1
    end

    -- Master switch
    local function isEnabled()
        return G_reader_settings:readSetting("cover_mode_enabled", true)
    end

    -- Toggle mode: 1 = double-tap, 2 = single-tap (no menu), 3 = single-tap (with menu)
    local function getToggleMode()
        return G_reader_settings:readSetting("cover_mode_toggle_mode", 1)
    end

    -- Get list of drawer types to cover
    local function getCoveredDrawers()
        return G_reader_settings:readSetting("cover_mode_drawers", {lighten = true})
    end

    -- Check if a specific drawer type needs covering
    local function shouldCoverDrawer(drawer)
        if not isEnabled() then
            return false
        end
        local covered = getCoveredDrawers()
        return covered[drawer] == true
    end

    -- Toggle cover state for a specific highlight
    local function toggleHighlight(highlight, index)
        if not isEnabled() then
            return
        end
        highlight._temp_covered = highlight._temp_covered or {}
        local is_covered = highlight._temp_covered[index] == true
        highlight._temp_covered[index] = not is_covered
        
        local ReaderUI = require("apps/reader/readerui")
        if ReaderUI and ReaderUI.instance then
            -- Only mark dirty, do NOT trigger recalculate (avoid page jump in PDF paged mode)
            UIManager:setDirty(ReaderUI.instance.dialog, "ui")
        else
            UIManager:setDirty(nil, "full")
        end
    end

    local drawer_patched = false

    local function patchCoverMode()
        local ReaderHighlight = require("apps/reader/modules/readerhighlight")
        local ReaderView = require("apps/reader/modules/readerview")
        local ReaderUI = require("apps/reader/readerui")
        
        if not ReaderView then
            return
        end
        
        -- ============================================================
        -- 1. Override drawer function - support multiple styles + PDF compatibility
        -- ============================================================
        if not drawer_patched then
            local original_draw = ReaderView.drawHighlightRect
            
            function ReaderView.drawHighlightRect(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
                if shouldCoverDrawer(drawer) then
                    local index = nil
                    -- Method 1: Direct object reference matching (works for EPUB)
                    if self.highlight.visible_boxes then
                        for _, box in ipairs(self.highlight.visible_boxes) do
                            if box.rect == rect then
                                index = box.index
                                break
                            end
                        end
                    end
                    
                    -- Method 2: Coordinate transformation matching (required for PDF)
                    if index == nil and self.highlight.visible_boxes then
                        local current_page = getPageFromScreenRect(self, rect)
                        for _, box in ipairs(self.highlight.visible_boxes) do
                            local screen_rect = self:pageToScreenTransform(current_page, box.rect)
                            if screen_rect and math.abs(screen_rect.x - rect.x) < 2 and math.abs(screen_rect.y - rect.y) < 2 then
                                index = box.index
                                break
                            end
                        end
                    end
                    
                    local is_covered = false
                    if index and self.ui and self.ui.highlight and self.ui.highlight._temp_covered then
                        is_covered = self.ui.highlight._temp_covered[index] == true
                    end
                    
                    local x, y, w, h = rect.x, rect.y, rect.w, rect.h
                    
                    if is_covered then
                        if color then
                            local c = Blitbuffer.ColorRGB32(color.r, color.g, color.b, 0xFF)
                            bb:blendRectRGB32(x, y, w, h, c)
                        else
                            local yellow = Blitbuffer.colorFromName("yellow")
                            if yellow then
                                local c = Blitbuffer.ColorRGB32(yellow.r, yellow.g, yellow.b, 0xFF)
                                bb:blendRectRGB32(x, y, w, h, c)
                            else
                                bb:darkenRect(x, y, w, h, 1)
                            end
                        end
                        return
                    end
                end
                
                if original_draw then
                    original_draw(self, bb, _x, _y, rect, drawer, color, draw_note_mark)
                end
            end
            
            drawer_patched = true
        end
        
        -- ============================================================
        -- 2. Register double-tap gesture (re-register on every book open)
        -- ============================================================
        local original_reader_ready = ReaderHighlight.onReaderReady
        
        function ReaderHighlight:onReaderReady()
            if original_reader_ready then
                original_reader_ready(self)
            end

            -- Re-register gesture on every book open to ensure double-tap works
            self.ui:registerTouchZones({
                {
                    id = "readerhighlight_double_tap",
                    ges = "double_tap",
                    screen_zone = {
                        ratio_x = 0, ratio_y = 0,
                        ratio_w = 1, ratio_h = 1,
                    },
                    handler = function(ges)
                        local mode = getToggleMode()
                        if not isEnabled() or mode ~= 1 then
                            return false
                        end
                        return self:onDoubleTap(ges)
                    end,
                    overrides = {
                        "readerhighlight_tap",
                        "readerhighlight_hold",
                    },
                },
            })
        end
        
        function ReaderHighlight:onDoubleTap(ges)
            if not isEnabled() or getToggleMode() ~= 1 then
                return false
            end
     
            local pos = self.view:screenToPageTransform(ges.pos)
            if not pos then
                return false
            end
            
            local tapped_index = nil
            if self.view.highlight.visible_boxes then
                for _, box in ipairs(self.view.highlight.visible_boxes) do
                    if inside_box(pos, box.rect) then
                        tapped_index = box.index
                        break
                    end
                end
            end
            
            if tapped_index then
                toggleHighlight(self, tapped_index)
                return true
            end
            
            return false
        end
        
        -- ============================================================
        -- 3. Hook onTap (for single-tap modes)
        -- ============================================================
        local original_onTap = ReaderHighlight.onTap
        
        function ReaderHighlight:onTap(_, ges)
            local mode = getToggleMode()
            
            -- Double-tap mode: pass through to original
            if not isEnabled() or mode == 1 then
                return original_onTap(self, _, ges)
            end
            
            -- Single-tap modes (mode 2 or 3)
            local pos = self.view:screenToPageTransform(ges.pos)
            
            local tapped_index = nil
            if self.view.highlight.visible_boxes then
                for _, box in ipairs(self.view.highlight.visible_boxes) do
                    if inside_box(pos, box.rect) then
                        tapped_index = box.index
                        break
                    end
                end
            end
            
           if tapped_index then
                -- Get the annotation item to check its drawer type
                local annotations = self.ui.annotation.annotations
                local item = annotations and annotations[tapped_index]
        
                if item and shouldCoverDrawer(item.drawer) then
                    toggleHighlight(self, tapped_index)
                    if mode == 2 then
                         -- Mode 2: block the original menu only for covered drawer types
                         return true
                      end
                    -- Mode 3: fall through to show original menu (but toggle already applied)
                   end
                 -- If drawer type is not covered, just show the original menu without toggling
               end
            
            return original_onTap(self, _, ges)
        end
        
        -- ============================================================
        -- 4. Batch operation functions
        -- ============================================================
        local function coverAllHighlights(highlight)
            if not isEnabled() then
                return
            end
            highlight._temp_covered = highlight._temp_covered or {}
            local annotations = highlight.ui.annotation.annotations
            for idx, item in ipairs(annotations) do
                if item.drawer then
                    highlight._temp_covered[idx] = true
                end
            end
        end
        
        local function uncoverAllHighlights(highlight)
            if not isEnabled() then
                return
            end
            highlight._temp_covered = highlight._temp_covered or {}
            local annotations = highlight.ui.annotation.annotations
            for idx, item in ipairs(annotations) do
                if item.drawer then
                    highlight._temp_covered[idx] = false
                end
            end
        end
        
        -- ============================================================
        -- 5. Toggle function for ZenUI menu
        -- ============================================================
        function ReaderUI:onToggleCoverMode()
            if not isEnabled() then
                return
            end
            local highlight = self.highlight
            if not highlight then
                return
            end
            
            local has_covered = false
            local annotations = highlight.ui.annotation.annotations
            for idx, item in ipairs(annotations) do
                if item.drawer then
                    local is_cov = highlight._temp_covered and highlight._temp_covered[idx]
                    if is_cov then
                        has_covered = true
                        break
                    end
                end
            end
            
            if has_covered then
                uncoverAllHighlights(highlight)
            else
                coverAllHighlights(highlight)
            end
            
            -- Force redraw
            UIManager:setDirty(self.dialog, "ui")
        end
        
        -- ============================================================
        -- 6. Register Dispatcher gesture action
        -- ============================================================
        Dispatcher:registerAction("toggle_cover_mode_action", {
            category = "none",
            event = "ToggleCoverMode",
            title = _("Cover all / Uncover all"),
            reader = true,
            ui = true,
        })
    end

    patchCoverMode()
end

return apply_covermode

local function apply_reader_footer_time_format()
    --[[
        Displays "time to chapter" as "X mins left in chapter" instead of icon + timestamp.
        Patches ReaderFooter.textGeneratorMap.chapter_time_to_read.
    --]]

    local ReaderFooter = require("apps/reader/modules/readerfooter")
    local _ = require("gettext")
    local T = require("ffi/util").template

    local orig = ReaderFooter.textGeneratorMap.chapter_time_to_read -- luacheck: ignore
    local orig_filler = ReaderFooter.textGeneratorMap.dynamic_filler

    -- Capture at apply time (while __ZEN_UI_PLUGIN is set); fall back to
    -- re-reading the global for late callers (same pattern as reader_clock.lua).
    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_verbose()
        local plugin = zen_plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        local rf_config = plugin and plugin.config and plugin.config.reader_footer
        return type(rf_config) == "table" and rf_config.verbose_chapter_time == true
    end

    -- The dynamic_filler formula adds separator_width back to compensate for the
    -- merged separator, which can push the total over max_width by ~1 space,
    -- causing TextWidget to truncate adjacent items with "...". By removing 6
    -- extra spaces (approx 30px), we guarantee it fits safely without truncation.
    -- Only trim when verbose mode is active.
    --
    -- Named local so we can reference it in the genAllFooterText patch below.
    local zen_filler_wrapper = function(footer)
        local text, merge = orig_filler(footer)
        if is_verbose() and type(text) == "string" and #text > 0 then
            local ct = ReaderFooter.textGeneratorMap.chapter_time_to_read(footer)
            if ct and ct ~= "" then
                if #text > 8 then
                    text = text:sub(1, -7) -- removes 6 spaces
                else
                    text = text:sub(1, 1)  -- fallback to 1 space
                end
            end
        end
        return text, merge
    end

    -- On cold/restart start, footerTextGenerators may hold orig_filler while
    -- footerTextGeneratorMap.dynamic_filler is already zen_filler_wrapper.
    -- The skip-by-reference check in genAllFooterText then fails, causing
    -- infinite recursion. Lazily fix up the stale entry on first call.
    local orig_genAllFooterText = ReaderFooter.genAllFooterText
    ReaderFooter.genAllFooterText = function(self, skip_gen)
        if skip_gen == zen_filler_wrapper and self.footerTextGenerators then
            for i, gen in ipairs(self.footerTextGenerators) do
                if gen == orig_filler then
                    self.footerTextGenerators[i] = zen_filler_wrapper
                end
            end
        end
        return orig_genAllFooterText(self, skip_gen)
    end

    ReaderFooter.textGeneratorMap.dynamic_filler = zen_filler_wrapper

    ReaderFooter.textGeneratorMap.chapter_time_to_read = function(footer)
        -- Only show verbose text when the setting is explicitly enabled.
        if not is_verbose() then
            return orig(footer)
        end

        local stats = footer.ui.statistics
        -- avg_time > 0 also rules out NaN (NaN > 0 is false in LuaJIT)
        if stats and stats.settings and stats.settings.is_enabled
                and stats.avg_time and stats.avg_time > 0 then
            local left = footer.ui.toc:getChapterPagesLeft(footer.pageno, true)
                       or footer.ui.document:getTotalPagesLeft(footer.pageno)
            if left and left > 0 then
                local total_minutes = math.floor(left * stats.avg_time / 60)
                -- Use non-breaking spaces (\u{00A0}) so compact mode's
                -- gsub("%s", hair-space) in genAllFooterText doesn't convert
                -- them. This preserves the true text width for dynamic filler
                -- layout calculation.
                local nbsp = "\u{00A0}"
                -- A leading hair-space (\u{200A}) provides minimal visual
                -- separation from the preceding item (e.g. page numbers)
                -- without doubling the visible gap the separator already
                -- supplies. It is narrower than \u{00A0} and is not an
                -- ASCII space, so the compact_items gsub leaves it alone.
                local hair = "\u{200A}"
                if total_minutes < 1 then
                    return hair .. _("< 1 min left in chapter"):gsub(" ", nbsp)
                elseif total_minutes == 1 then
                    return hair .. _("1 min left in chapter"):gsub(" ", nbsp)
                else
                    return hair .. T(_("%1 mins left in chapter"), total_minutes):gsub(" ", nbsp)
                end
            end
        end
        return ""
    end
end

return apply_reader_footer_time_format

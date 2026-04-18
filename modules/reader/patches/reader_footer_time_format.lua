local function apply_reader_footer_time_format()
    --[[
        Modifies the reader footer to display "time to chapter" in Kindle style:
        "X mins left in chapter" instead of icon + timestamp.

        Patches ReaderFooter.textGeneratorMap.chapter_time_to_read.
        Reads stats.avg_time directly (seconds per page) to avoid depending on
        the user's duration_format string representation.
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
    ReaderFooter.textGeneratorMap.dynamic_filler = function(footer)
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
                if total_minutes < 1 then
                    return _("< 1 min left in chapter"):gsub(" ", nbsp)
                elseif total_minutes == 1 then
                    return _("1 min left in chapter"):gsub(" ", nbsp)
                else
                    return T(_("%1 mins left in chapter"), total_minutes):gsub(" ", nbsp)
                end
            end
        end
        return ""
    end
end

return apply_reader_footer_time_format

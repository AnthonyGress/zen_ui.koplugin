describe("reader footer patches", function()
    local function apply_patch(name)
        ZenSpec.unload(name)
        require(name)()
    end

    before_each(function()
        _G.__ZEN_UI_PLUGIN = nil
        ZenSpec.replace("gettext", function(text) return text end)
        ZenSpec.replace("ffi/util", {
            template = function(text, value)
                return (text:gsub("%%1", tostring(value)))
            end,
        })
    end)

    after_each(function()
        _G.__ZEN_UI_PLUGIN = nil
    end)

    it("formats chapter time for sub-minute, singular, and plural durations", function()
        local ReaderFooter = {
            textGeneratorMap = {
                chapter_time_to_read = function() return "stock" end,
                dynamic_filler = function() return "          ", true end,
            },
            genAllFooterText = function() return "all" end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = {
            config = { reader_footer = { verbose_chapter_time = true } },
        }
        apply_patch("modules/reader/patches/reader_footer_time_format")

        local footer = {
            pageno = 10,
            ui = {
                statistics = { settings = { is_enabled = true }, avg_time = 30 },
                toc = { getChapterPagesLeft = function() return 1 end },
                document = { getTotalPagesLeft = function() return 99 end },
            },
        }
        local nbsp = "\u{00A0}"
        local hair = "\u{200A}"
        assert.are.equal(hair .. "<" .. nbsp .. "1" .. nbsp .. "min" .. nbsp
            .. "left" .. nbsp .. "in" .. nbsp .. "chapter",
            ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))

        footer.ui.statistics.avg_time = 60
        assert.are.equal(hair .. "1" .. nbsp .. "min" .. nbsp .. "left" .. nbsp
            .. "in" .. nbsp .. "chapter",
            ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))

        footer.ui.toc.getChapterPagesLeft = function() return 4 end
        assert.are.equal(hair .. "4" .. nbsp .. "mins" .. nbsp .. "left" .. nbsp
            .. "in" .. nbsp .. "chapter",
            ReaderFooter.textGeneratorMap.chapter_time_to_read(footer))
    end)

    it("uses stock chapter time while verbose mode is disabled", function()
        local ReaderFooter = {
            textGeneratorMap = {
                chapter_time_to_read = function() return "stock" end,
                dynamic_filler = function() return "          ", false end,
            },
            genAllFooterText = function() return "all" end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = {
            config = { reader_footer = { verbose_chapter_time = false } },
        }
        apply_patch("modules/reader/patches/reader_footer_time_format")

        assert.are.equal("stock", ReaderFooter.textGeneratorMap.chapter_time_to_read({}))
        local text, merge = ReaderFooter.textGeneratorMap.dynamic_filler({})
        assert.are.equal("          ", text)
        assert.is_false(merge)
    end)

    it("trims dynamic filler and repairs a stale generator reference", function()
        local original_filler = function() return "          ", true end
        local skipped
        local ReaderFooter = {
            textGeneratorMap = {
                chapter_time_to_read = function() return "stock" end,
                dynamic_filler = original_filler,
            },
            genAllFooterText = function(_, skip_gen)
                skipped = skip_gen
                return "all"
            end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = {
            config = { reader_footer = { verbose_chapter_time = true } },
        }
        apply_patch("modules/reader/patches/reader_footer_time_format")

        local footer = {
            pageno = 1,
            footerTextGenerators = { original_filler },
            ui = {
                statistics = { settings = { is_enabled = true }, avg_time = 60 },
                toc = { getChapterPagesLeft = function() return 1 end },
                document = { getTotalPagesLeft = function() return 1 end },
            },
        }
        local wrapper = ReaderFooter.textGeneratorMap.dynamic_filler
        local text, merge = wrapper(footer)
        assert.are.equal("    ", text)
        assert.is_true(merge)

        assert.are.equal("all", ReaderFooter.genAllFooterText(footer, wrapper))
        assert.are.equal(wrapper, footer.footerTextGenerators[1])
        assert.are.equal(wrapper, skipped)
    end)

    it("keeps configured image documents hidden after load and footer toggles", function()
        local ready_calls, mode
        local ReaderFooter = {
            onReaderReady = function() ready_calls = (ready_calls or 0) + 1 end,
            applyFooterMode = function(_, value) mode = value end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = { config = { reader_footer = { hide_in_cbz = true } } }
        apply_patch("modules/reader/patches/reader_footer_cbz_hide")

        local refresh_args
        local footer = {
            ui = { document = { file = "/books/Comic.CBZ" } },
            view = { footer_visible = true },
            refreshFooter = function(_, first, second) refresh_args = { first, second } end,
        }
        ReaderFooter.onReaderReady(footer)
        assert.are.equal(1, ready_calls)
        assert.is_false(footer.view.footer_visible)
        assert.same({ true, true }, refresh_args)

        footer.view.footer_visible = true
        ReaderFooter.applyFooterMode(footer, 3)
        assert.are.equal(3, mode)
        assert.is_false(footer.view.footer_visible)
    end)

    it("leaves ordinary documents and disabled image hiding unchanged", function()
        local refreshes = 0
        local ReaderFooter = {
            onReaderReady = function() end,
            applyFooterMode = function(self) self.view.footer_visible = true end,
        }
        ZenSpec.replace("apps/reader/modules/readerfooter", ReaderFooter)
        _G.__ZEN_UI_PLUGIN = { config = { reader_footer = { hide_in_cbz = false } } }
        apply_patch("modules/reader/patches/reader_footer_cbz_hide")

        local footer = {
            ui = { document = { file = "/books/Novel.epub" } },
            view = { footer_visible = true },
            refreshFooter = function() refreshes = refreshes + 1 end,
        }
        ReaderFooter.onReaderReady(footer)
        ReaderFooter.applyFooterMode(footer, 1)
        assert.is_true(footer.view.footer_visible)
        assert.are.equal(0, refreshes)
    end)
end)

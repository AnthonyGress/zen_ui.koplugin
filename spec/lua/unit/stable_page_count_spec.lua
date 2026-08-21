describe("stable page count", function()
    local Utils
    local booklist_reads

    before_each(function()
        booklist_reads = 0
        ZenSpec.replace("ui/widget/booklist", {
            getBookInfo = function()
                booklist_reads = booklist_reads + 1
                return { pages = 999 }
            end,
        })
        ZenSpec.replace("docsettings", {
            hasSidecarFile = function()
                error("supplied sidecar metadata should be reused")
            end,
        })
        ZenSpec.unload("common/utils")
        Utils = require("common/utils")
    end)

    it("prefers page counts from the supplied sidecar", function()
        local trace = {}
        local values = {
            pagemap_use_page_labels = false,
            doc_pages = 321,
            stats = { pages = 654 },
        }
        local doc = {
            readSetting = function(_self, key) return values[key] end,
        }

        local pages = Utils.getStablePageCount("/book.epub", 111, {
            doc_settings = doc,
            sidecar_checked = true,
            book_info = { pages = 222 },
            book_info_checked = true,
            trace = trace,
        })

        assert.are.equal(321, pages)
        assert.are.equal(0, booklist_reads)
        assert.is_nil(trace.sidecar_opens)
        assert.is_nil(trace.booklist_reads)
    end)

    it("uses supplied book metadata and numeric fallback without BookList I/O", function()
        local trace = {}
        assert.are.equal(222, Utils.getStablePageCount("/book.epub", 111, {
            sidecar_checked = true,
            book_info = { pages = 222 },
            book_info_checked = true,
            trace = trace,
        }))
        assert.are.equal(111, Utils.getStablePageCount("/book.epub", 111, {
            sidecar_checked = true,
            trace = trace,
        }))
        assert.are.equal(0, booklist_reads)
        assert.is_nil(trace.sidecar_opens)
        assert.is_nil(trace.booklist_reads)
    end)

    it("consults BookList only when the caller supplied no usable count", function()
        local trace = {}
        assert.are.equal(999, Utils.getStablePageCount("/book.epub", nil, {
            sidecar_checked = true,
            trace = trace,
        }))
        assert.are.equal(1, booklist_reads)
        assert.are.equal(1, trace.booklist_reads)
        assert.is_nil(trace.sidecar_opens)
    end)

    it("opens a sidecar only when the caller supplied no sidecar context", function()
        local sidecar_opens = 0
        ZenSpec.replace("docsettings", {
            hasSidecarFile = function() return true end,
            open = function()
                sidecar_opens = sidecar_opens + 1
                return {
                    readSetting = function(_self, key)
                        return key == "doc_pages" and 444 or nil
                    end,
                }
            end,
        })
        local trace = {}

        assert.are.equal(444, Utils.getStablePageCount("/book.epub", nil, {
            trace = trace,
        }))
        assert.are.equal(1, sidecar_opens)
        assert.are.equal(1, trace.sidecar_opens)
        assert.is_nil(trace.booklist_reads)
    end)
end)

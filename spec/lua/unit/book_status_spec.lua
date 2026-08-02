local function settings(initial)
    local data = initial or {}
    return {
        data = { doc_path = "/books/book.epub" },
        readSetting = function(_self, key) return data[key] end,
        saveSetting = function(_self, key, value) data[key] = value end,
        delSetting = function(_self, key) data[key] = nil end,
    }, data
end

describe("book status", function()
    before_each(function()
        ZenSpec.unload("common/book_status")
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, attribute)
                local values = {
                    ["/books/book.epub"] = { mode = "file", modification = 200 },
                    ["/books/book.sdr/metadata.lua"] = { mode = "file", modification = 150 },
                }
                local value = values[path]
                return attribute and value and value[attribute] or value
            end,
        })
        ZenSpec.replace("docsettings", {
            findSidecarFile = function() return "/books/book.sdr/metadata.lua" end,
            hasSidecarFile = function() return true end,
        })
    end)

    it("normalizes explicit, inferred, and image statuses", function()
        local BookStatus = require("common/book_status")
        assert.are.equal("new", BookStatus.getEffectiveStatus(nil, nil))
        assert.are.equal("reading", BookStatus.getEffectiveStatus(nil, 0))
        assert.are.equal("complete", BookStatus.getEffectiveStatus("complete", nil))
        assert.is_true(BookStatus.isImageFile("COVER.JPEG"))
        assert.is_false(BookStatus.isImageFile("book.epub"))
        assert.is_false(BookStatus.isImageFile(nil))
    end)

    it("derives the TBR display status from the collection or new-book setting", function()
        local include_new = false
        ZenSpec.replace("config/manager", {
            get = function()
                return { group_view = { include_new_in_tbr = include_new } }
            end,
        })
        ZenSpec.replace("common/tbr_index", {
            isExplicit = function(path) return path == "/books/queued.epub" end,
        })
        local BookStatus = require("common/book_status")

        assert.are.equal("tbr", BookStatus.getDisplayStatus("/books/queued.epub", "reading"))
        assert.are.equal("new", BookStatus.getDisplayStatus("/books/new.epub", "new"))

        include_new = true
        assert.are.equal("tbr", BookStatus.getDisplayStatus("/books/new.epub", "new"))
    end)

    it("detects a changed book from its sidecar or acknowledgment marker", function()
        local BookStatus = require("common/book_status")
        local doc, data = settings({ percent_finished = 0.5 })

        assert.are.equal("new", BookStatus.getComputedStatus(
            "/books/book.epub", nil, 0.5, doc
        ))
        data.zen_new_mtime = 200
        assert.are.equal("reading", BookStatus.getComputedStatus(
            "/books/book.epub", nil, 0.5, doc
        ))
        data.zen_new_mtime = 100
        assert.are.equal("new", BookStatus.getComputedStatus(
            "/books/book.epub", nil, 0.5, doc
        ))
        assert.are.equal("reading", BookStatus.getComputedStatus(
            "/books/cover.png", nil, 0.5, doc
        ))
    end)

    it("acknowledges the current file version and removes the legacy marker", function()
        local BookStatus = require("common/book_status")
        local doc, data = settings({ zen_auto_tbr_mtime = 100 })

        assert.is_true(BookStatus.acknowledgeNewVersion(doc))
        assert.are.equal(200, data.zen_new_mtime)
        assert.is_nil(data.zen_auto_tbr_mtime)
        assert.is_false(BookStatus.acknowledgeNewVersion(doc))
    end)

    it("uses safe defaults for missing book information", function()
        local BookStatus = require("common/book_status")
        assert.are.equal("new", BookStatus.getEffectiveStatusFromInfo(nil))
        assert.are.equal("reading", BookStatus.getEffectiveStatusFromInfo({
            percent_finished = 0.25,
        }))
    end)

    it("reuses authoritative sidecar status until explicitly invalidated", function()
        local opens = 0
        local booklist_reads = 0
        local doc, data = settings({
            summary = { status = "reading" },
            percent_finished = 0.5,
            zen_new_mtime = 200,
        })
        ZenSpec.replace("docsettings", {
            findSidecarFile = function() return "/books/book.sdr/metadata.lua" end,
            hasSidecarFile = function() return true end,
            open = function()
                opens = opens + 1
                return doc
            end,
        })
        ZenSpec.replace("ui/widget/booklist", {
            getBookInfo = function()
                booklist_reads = booklist_reads + 1
                return { status = "complete", percent_finished = 1 }
            end,
        })
        local BookStatus = require("common/book_status")

        assert.are.equal("reading", BookStatus.getEffectiveStatusFromFile("/books/book.epub"))
        assert.are.equal(1, opens)
        assert.are.equal(0, booklist_reads)

        data.zen_new_mtime = 100
        assert.are.equal("reading", BookStatus.getEffectiveStatusFromFile("/books/book.epub"))
        assert.are.equal(1, opens)
        BookStatus.invalidate("/books/book.epub")
        assert.are.equal("new", BookStatus.getEffectiveStatusFromFile("/books/book.epub"))
        assert.are.equal(2, opens)
        assert.are.equal(0, booklist_reads)
    end)

    it("refreshes cached status when the sidecar modification time changes", function()
        local sidecar_mtime = 150
        local opens = 0
        local doc, data = settings({
            summary = { status = "reading" },
            percent_finished = 0.5,
            zen_new_mtime = 200,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path, attribute)
                local value = path == "/books/book.epub"
                    and { mode = "file", modification = 200 }
                    or { mode = "file", modification = sidecar_mtime }
                return attribute and value[attribute] or value
            end,
        })
        ZenSpec.replace("docsettings", {
            findSidecarFile = function() return "/books/book.sdr/metadata.lua" end,
            hasSidecarFile = function() return true end,
            open = function()
                opens = opens + 1
                return doc
            end,
        })
        local BookStatus = require("common/book_status")

        assert.are.equal("reading", BookStatus.getEffectiveStatusFromFile("/books/book.epub"))
        data.summary.status = "complete"
        assert.are.equal("reading", BookStatus.getEffectiveStatusFromFile("/books/book.epub"))
        sidecar_mtime = 151
        assert.are.equal("complete", BookStatus.getEffectiveStatusFromFile("/books/book.epub"))
        assert.are.equal(2, opens)
    end)

    it("consults BookList once when no sidecar is available", function()
        local booklist_reads = 0
        ZenSpec.replace("docsettings", {
            hasSidecarFile = function() return false end,
        })
        ZenSpec.replace("ui/widget/booklist", {
            getBookInfo = function()
                booklist_reads = booklist_reads + 1
                return { status = "complete", percent_finished = 1 }
            end,
        })
        local BookStatus = require("common/book_status")

        assert.are.equal("complete", BookStatus.getEffectiveStatusFromFile("/books/book.epub"))
        assert.are.equal(1, booklist_reads)
    end)
end)

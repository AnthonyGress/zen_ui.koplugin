describe("Rakuyomi availability", function()
    local original_filemanager
    local original_bookinfomanager
    local original_documentregistry
    local original_cbz_document

    before_each(function()
        original_filemanager = package.loaded["apps/filemanager/filemanager"]
        original_bookinfomanager = package.loaded.bookinfomanager
        original_documentregistry = package.loaded["document/documentregistry"]
        original_cbz_document = package.loaded["extensions/CbzDocument"]
        ZenSpec.unload("common/rakuyomi")
    end)

    after_each(function()
        package.loaded["apps/filemanager/filemanager"] = original_filemanager
        package.loaded.bookinfomanager = original_bookinfomanager
        package.loaded["document/documentregistry"] = original_documentregistry
        package.loaded["extensions/CbzDocument"] = original_cbz_document
        ZenSpec.unload("common/rakuyomi")
    end)

    it("exports the availability API used by Zen UI initialization", function()
        package.loaded["apps/filemanager/filemanager"] = {
            instance = { rakuyomi = {} },
        }

        local Rakuyomi = require("common/rakuyomi")

        assert.is_table(Rakuyomi)
        assert.is_function(Rakuyomi.is_available)
        assert.is_true(Rakuyomi.is_available())
    end)

    it("uses Rakuyomi's CBZ reader only for chapter metadata extraction", function()
        local default_provider = {}
        local cbz_provider = {}
        local DocumentRegistry = {
            getProvider = function() return default_provider end,
        }
        local seen_provider
        local BookInfoManager = {
            extractBookInfo = function(_, filepath)
                seen_provider = DocumentRegistry:getProvider(filepath)
                return true
            end,
            getBookInfo = function() return { title = "Cached" } end,
            deleteBookInfo = function() end,
        }
        ZenSpec.replace("bookinfomanager", BookInfoManager)
        ZenSpec.replace("document/documentregistry", DocumentRegistry)
        ZenSpec.replace("extensions/CbzDocument", cbz_provider)

        local Rakuyomi = require("common/rakuyomi")
        Rakuyomi.isChapterFile = function(path)
            return path == "/library/chapter.cbz"
        end

        assert.is_true(Rakuyomi.installMetadataIntegration())
        assert.is_true(BookInfoManager:extractBookInfo("/library/chapter.cbz"))
        assert.is_true(rawequal(cbz_provider, seen_provider))
        assert.is_true(rawequal(default_provider, DocumentRegistry:getProvider("/library/book.cbz")))

        assert.is_true(BookInfoManager:extractBookInfo("/library/book.cbz"))
        assert.is_true(rawequal(default_provider, seen_provider))
    end)

    it("reads and caches the metadata fields needed by home widgets", function()
        local reads = 0
        ZenSpec.replace("extensions/CbzDocument", {
            _getComicBookInfoJSONFromBinary = function(_, path)
                reads = reads + 1
                assert.is_nil(path)
                return "metadata"
            end,
            _parseMetadata = function(_, json)
                assert.equals("metadata", json)
                return {
                    title = "Chapter title",
                    author = "Manga Author",
                    series = "Manga Series",
                    series_index = "4.5",
                    notes = "Chapter description",
                }
            end,
        })

        local Rakuyomi = require("common/rakuyomi")
        Rakuyomi.isChapterFile = function() return true end

        local metadata = Rakuyomi.getMetadata("/library/chapter.cbz")
        assert.are.same({
            title = "Chapter title",
            authors = "Manga Author",
            series = "Manga Series",
            series_index = 4.5,
            description = "Chapter description",
        }, metadata)
        assert.is_true(rawequal(metadata, Rakuyomi.getMetadata("/library/chapter.cbz")))
        assert.equals(1, reads)
        assert.is_nil(Rakuyomi.getMetadata("/library/chapter.epub"))
    end)

    it("restores provider lookup when Rakuyomi metadata extraction fails", function()
        local original_get_provider = function() return "default" end
        local DocumentRegistry = { getProvider = original_get_provider }
        local BookInfoManager = {
            extractBookInfo = function(_, filepath)
                DocumentRegistry:getProvider(filepath)
                error("broken CBZ")
            end,
        }
        ZenSpec.replace("bookinfomanager", BookInfoManager)
        ZenSpec.replace("document/documentregistry", DocumentRegistry)
        ZenSpec.replace("extensions/CbzDocument", {})

        local Rakuyomi = require("common/rakuyomi")
        Rakuyomi.isChapterFile = function() return true end
        assert.is_true(Rakuyomi.installMetadataIntegration())

        local ok, err = pcall(BookInfoManager.extractBookInfo,
            BookInfoManager, "/library/chapter.cbz")
        assert.is_false(ok)
        assert.matches("broken CBZ", err, 1, true)
        assert.is_true(rawequal(original_get_provider, DocumentRegistry.getProvider))
    end)

    it("drops a legacy title-less cache row once so it can be re-extracted", function()
        local deletes = 0
        local BookInfoManager = {
            extractBookInfo = function() return true end,
            getBookInfo = function() return { title = nil, has_meta = "Y" } end,
            deleteBookInfo = function() deletes = deletes + 1 end,
        }
        ZenSpec.replace("bookinfomanager", BookInfoManager)
        ZenSpec.replace("document/documentregistry", {
            getProvider = function() return {} end,
        })
        ZenSpec.replace("extensions/CbzDocument", {})

        local Rakuyomi = require("common/rakuyomi")
        Rakuyomi.isChapterFile = function() return true end
        assert.is_true(Rakuyomi.installMetadataIntegration())

        assert.is_nil(BookInfoManager:getBookInfo("/library/chapter.cbz"))
        assert.equals(1, deletes)
        assert.is_table(BookInfoManager:getBookInfo("/library/chapter.cbz"))
        assert.equals(1, deletes)
    end)
end)

describe("persistent TBR status index", function()
    local test_dir
    local scheduled
    local attrs
    local sidecars
    local docs
    local opens
    local open_fail
    local db_rows

    local function run_scheduled()
        local iterations = 0
        while #scheduled > 0 and iterations < 100 do
            iterations = iterations + 1
            table.remove(scheduled, 1)()
        end
        assert.is_true(iterations < 100)
    end

    before_each(function()
        local host_lfs = require("lfs")
        test_dir = os.tmpname()
        os.remove(test_dir)
        assert(host_lfs.mkdir(test_dir))
        scheduled = {}
        opens = 0
        open_fail = nil
        db_rows = {}
        attrs = {
            ["/books/a.epub"] = { mode = "file", size = 10, modification = 1, access = 30 },
            ["/books/b.epub"] = { mode = "file", size = 10, modification = 1, access = 20 },
            ["/books/c.epub"] = { mode = "file", size = 10, modification = 1, access = 10 },
            ["/sidecars/a.lua"] = { mode = "file", size = 10, modification = 1 },
            ["/sidecars/b.lua"] = { mode = "file", size = 10, modification = 1 },
            ["/sidecars/c.lua"] = { mode = "file", size = 10, modification = 1 },
        }
        sidecars = {
            ["/books/a.epub"] = "/sidecars/a.lua",
            ["/books/b.epub"] = "/sidecars/b.lua",
            ["/books/c.epub"] = "/sidecars/c.lua",
        }
        local statuses = {
            ["/books/a.epub"] = "abandoned",
            ["/books/b.epub"] = "reading",
            ["/books/c.epub"] = "abandoned",
        }
        docs = {}
        for path, status in pairs(statuses) do
            docs[path] = {
                data = { doc_path = path },
                readSetting = function(_self, key)
                    if key == "summary" then return { status = statuses[path] } end
                    if key == "percent_finished" then return status == "reading" and 0.4 or nil end
                end,
            }
        end

        ZenSpec.replace("datastorage", { getSettingsDir = function() return test_dir end })
        ZenSpec.replace("common/paths", { getHomeDir = function() return "/books" end })
        ZenSpec.replace("lua-ljsqlite3/init", {
            open = function()
                local database = {}
                function database:exec() end
                function database:close() end
                function database:prepare(sql)
                    local stmt = { bound = {}, done = false }
                    function stmt:bind(...)
                        self.bound = { ... }
                        return self
                    end
                    local function qualifies(row)
                        local matched = row.status == "abandoned"
                            or (sql:find("effective_status = 'new'", 1, true)
                                and row.effective_status == "new")
                        local exclude = sql:find("path != ?", 1, true) and stmt.bound[2]
                        return row.home_root == stmt.bound[1] and matched and row.path ~= exclude
                    end
                    function stmt:step()
                        if sql:find("INSERT OR REPLACE", 1, true) then
                            db_rows[self.bound[1]] = {
                                path = self.bound[1], signature = self.bound[2],
                                home_root = self.bound[3], status = self.bound[4],
                                percent_finished = self.bound[5], effective_status = self.bound[6],
                                sort_title = self.bound[7], series_index = self.bound[8],
                                access_time = self.bound[9],
                            }
                            return true
                        elseif sql:find("DELETE FROM", 1, true) then
                            db_rows[self.bound[1]] = nil
                            return true
                        elseif sql:find("SELECT signature", 1, true) then
                            if self.done then return nil end
                            self.done = true
                            local row = db_rows[self.bound[1]]
                            if not row then return nil end
                            return {
                                row.signature, row.status, row.percent_finished,
                                row.effective_status, row.sort_title,
                                row.series_index, row.access_time,
                            }
                        elseif sql:find("SELECT COUNT", 1, true) then
                            if self.done then return nil end
                            self.done = true
                            local count = 0
                            for _path, row in pairs(db_rows) do
                                if qualifies(row) then count = count + 1 end
                            end
                            return { count }
                        elseif sql:find("SELECT path", 1, true) then
                            if not self.result then
                                self.result = {}
                                for _path, row in pairs(db_rows) do
                                    if qualifies(row) then self.result[#self.result + 1] = row end
                                end
                                table.sort(self.result, function(a, b)
                                    if sql:find("sort_title", 1, true) then
                                        if a.sort_title ~= b.sort_title then
                                            local descending = sql:find("sort_title COLLATE NOCASE DESC", 1, true)
                                            return descending and a.sort_title > b.sort_title
                                                or not descending and a.sort_title < b.sort_title
                                        end
                                    end
                                    return a.path < b.path
                                end)
                                local bind_offset = sql:find("path != ?", 1, true) and 2 or 1
                                self.limit = self.bound[bind_offset + 1]
                                self.offset = self.bound[bind_offset + 2]
                                self.position = 1
                            end
                            local index = self.offset + self.position
                            if self.position > self.limit or not self.result[index] then return nil end
                            self.position = self.position + 1
                            return { self.result[index].path }
                        end
                    end
                    function stmt:clearbind() return self end
                    function stmt:reset()
                        self.done = false
                        self.result = nil
                        return self
                    end
                    return stmt
                end
                return database
            end,
        })
        ZenSpec.replace("libs/libkoreader-lfs", {
            attributes = function(path) return attrs[path] end,
        })
        ZenSpec.replace("docsettings", {
            findSidecarFile = function(_self, path) return sidecars[path] end,
            open = function(_self, path)
                opens = opens + 1
                if open_fail == path then error("sidecar read failed") end
                return docs[path]
            end,
        })
        ZenSpec.replace("ui/uimanager", {
            scheduleIn = function(_self, _delay, fn) scheduled[#scheduled + 1] = fn end,
            unschedule = function(_self, fn)
                for index = #scheduled, 1, -1 do
                    if scheduled[index] == fn then table.remove(scheduled, index) end
                end
            end,
        })
        ZenSpec.replace("common/book_status", {
            includeNewInTBREnabled = function() return false end,
            isImageFile = function() return false end,
            migrateLegacyMarker = function(_path, status) return status end,
            getComputedStatus = function(_path, status)
                return status or "new"
            end,
        })
        ZenSpec.replace("common/title_sort", {
            key = function(value) return tostring(value) end,
        })
        local tick = 0
        ZenSpec.replace("common/zen_logger", {
            now = function()
                tick = tick + 0.001
                return tick
            end,
            new = function()
                return {
                    warn = function() end,
                    measure = function() end,
                }
            end,
        })
        ZenSpec.unload("common/tbr_index")
    end)

    after_each(function()
        local index = package.loaded["common/tbr_index"]
        if index and index.close then index.close() end
        ZenSpec.unload("common/tbr_index")
        os.remove(test_dir .. "/docprops_cache.sqlite")
        os.remove(test_dir .. "/docprops_cache.sqlite-journal")
        require("lfs").rmdir(test_dir)
    end)

    local function candidates()
        return {
            { path = "/books/a.epub", title = "Zulu", series_index = 3 },
            { path = "/books/b.epub", title = "Bravo", series_index = 2 },
            { path = "/books/c.epub", title = "Alpha", series_index = 1 },
        }
    end

    it("persists paged TBR rows and reopens only changed sidecars", function()
        local Index = require("common/tbr_index")
        assert.is_true(Index.scheduleAudit(candidates()))
        run_scheduled()

        assert.are.equal(3, opens)
        assert.are.equal(2, Index.getCount())
        local first = Index.getPage(0, 1, { collate = "title" })
        assert.are.same({ "/books/c.epub" }, first)

        Index.close()
        ZenSpec.unload("common/tbr_index")
        opens = 0
        Index = require("common/tbr_index")
        Index.scheduleAudit(candidates())
        run_scheduled()
        assert.are.equal(0, opens)
        assert.are.equal(2, Index.getCount())

        attrs["/sidecars/a.lua"].modification = 2
        docs["/books/a.epub"].readSetting = function(_self, key)
            if key == "summary" then return { status = "reading" } end
            if key == "percent_finished" then return 0.2 end
        end
        Index.scheduleAudit(candidates())
        run_scheduled()
        assert.are.equal(1, opens)
        assert.are.equal(1, Index.getCount())
    end)

    it("updates one status synchronously without auditing the library", function()
        local Index = require("common/tbr_index")
        Index.refreshPath("/books/a.epub", docs["/books/a.epub"], candidates()[1])

        assert.are.equal(0, opens)
        assert.are.equal(1, Index.getCount())
        assert.are.same({ "/books/a.epub" }, Index.getPage(0, 4))
    end)

    it("keeps the cached status when a changed sidecar cannot be read", function()
        local Index = require("common/tbr_index")
        Index.scheduleAudit(candidates())
        run_scheduled()
        assert.are.equal(2, Index.getCount())

        attrs["/sidecars/a.lua"].modification = 2
        open_fail = "/books/a.epub"
        Index.scheduleAudit(candidates())
        run_scheduled()

        assert.are.equal(2, Index.getCount())
    end)

    it("notifies every view waiting on the same audit", function()
        local Index = require("common/tbr_index")
        local changes = 0
        local completions = 0
        Index.scheduleAudit(candidates(), function()
            changes = changes + 1
        end, function()
            completions = completions + 1
        end)
        Index.scheduleAudit(candidates(), function()
            changes = changes + 1
        end, function()
            completions = completions + 1
        end)
        run_scheduled()

        assert.are.equal(2, changes)
        assert.are.equal(2, completions)
        assert.is_true(Index.isAuditComplete())
    end)
end)

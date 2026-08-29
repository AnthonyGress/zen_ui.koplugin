local logger = require("common/zen_logger").new("read_index")
local DataStorage = require("datastorage")
local sqlite3 = require("lua-ljsqlite3/init")

local ReadIndex = {}
local DB_PATH = DataStorage:getSettingsDir() .. "/docprops_cache.sqlite"

function ReadIndex.getAll(opts)
    local results = {}
    local ok, err = pcall(function()
        local db = sqlite3.open(DB_PATH)
        if db then
            local stmt = db:prepare([[SELECT path FROM zen_doc_status_cache WHERE effective_status = 'complete']])
            if stmt then
                while true do
                    local row = stmt:step()
                    if not row then break end
                    table.insert(results, row[1])
                end
                stmt:clearbind():reset()
            end
            db:close()
        end
    end)
    if not ok then logger.warn("read_index getAll failed: ", err) end
    return results
end

return ReadIndex

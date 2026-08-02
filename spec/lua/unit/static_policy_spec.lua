local lfs = require("lfs")

local function walk(path, out)
    for entry in lfs.dir(path) do
        if entry ~= "." and entry ~= ".." then
            local full = path .. "/" .. entry
            local attr = lfs.attributes(full)
            if attr.mode == "directory" then
                walk(full, out)
            elseif entry:sub(-4) == ".lua" then
                out[#out + 1] = full
            end
        end
    end
end

describe("source safety policy", function()
    it("never shadows gettext with a Lua loop discard variable", function()
        local files = {}
        walk(ZenSpec.root .. "/common", files)
        walk(ZenSpec.root .. "/config", files)
        walk(ZenSpec.root .. "/modules", files)
        table.insert(files, ZenSpec.root .. "/main.lua")
        for _i, path in ipairs(files) do
            local file = assert(io.open(path, "r"))
            local source = file:read("*a")
            file:close()
            assert.is_nil(source:match("for%s+_%s*,"), path)
        end
    end)
end)

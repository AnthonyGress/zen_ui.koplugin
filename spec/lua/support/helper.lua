local root = assert(os.getenv("ZEN_UI_ROOT"), "ZEN_UI_ROOT must point to the Zen UI checkout")

package.path = table.concat({
    root .. "/?.lua",
    root .. "/?/init.lua",
    root .. "/spec/lua/support/?.lua",
    package.path,
}, ";")

local function memory_settings(initial)
    local data = initial or {}
    return {
        data = data,
        readSetting = function(_, key) return data[key] end,
        saveSetting = function(_, key, value) data[key] = value end,
        delSetting = function(_, key) data[key] = nil end,
        isTrue = function(_, key) return data[key] == true end,
        reset = function(_, values) data = values or {} end,
    }
end

_G.ZenSpec = {
    root = root,
    memorySettings = memory_settings,
    unload = function(name)
        package.loaded[name] = nil
        _G[name] = nil
    end,
    replace = function(name, module)
        package.loaded[name] = module
    end,
}

_G.G_reader_settings = memory_settings()

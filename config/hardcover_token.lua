local M = {}
local FILE_NAME = "hardcover_token.txt"
local MAX_LENGTH = 4096

local function clean(value)
    value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
    if value == "" or #value > MAX_LENGTH or value:find("%s") then return nil end
    return value
end

local function replace_file(source, destination)
    local ffi = require("ffi")
    if ffi.os ~= "Windows" then return os.rename(source, destination) end
    pcall(ffi.cdef, [[
        int MultiByteToWideChar(unsigned int code_page, unsigned long flags,
            const char *source, int source_length, wchar_t *destination,
            int destination_length);
        int MoveFileExW(const wchar_t *existing, const wchar_t *replacement,
            unsigned long flags);
    ]])
    local function wide(value)
        local size = ffi.C.MultiByteToWideChar(65001, 0, value, -1, nil, 0)
        if size <= 0 then return end
        local buffer = ffi.new("wchar_t[?]", size)
        if ffi.C.MultiByteToWideChar(65001, 0, value, -1, buffer, size) <= 0 then
            return
        end
        return buffer
    end
    local source_w, destination_w = wide(source), wide(destination)
    if not source_w or not destination_w then return nil, "invalid token path" end
    local called, replaced = pcall(function()
        return ffi.C.MoveFileExW(source_w, destination_w, 0x1 + 0x8)
    end)
    if not called or replaced == 0 then return nil, "atomic replacement failed" end
    return true
end

local function write_atomic(path, content)
    local stage = path .. ".zen-write"
    os.remove(stage)
    local file, err = io.open(stage, "wb")
    if not file then return nil, err end
    local wrote, write_err = file:write(content)
    local flushed, flush_err
    if wrote then flushed, flush_err = file:flush() end
    local ffiutil = require("ffi/util")
    local synced, sync_err
    if flushed then synced, sync_err = ffiutil.fsyncOpenedFile(file, true) end
    local closed, close_err = file:close()
    if not wrote or not flushed or synced ~= true or closed == nil then
        os.remove(stage)
        return nil, write_err or flush_err or sync_err or close_err
    end
    local check = io.open(stage, "rb")
    local saved = check and check:read("*a")
    if check then check:close() end
    if saved ~= content then
        os.remove(stage)
        return nil, "token write verification failed"
    end
    local replaced, replace_err = replace_file(stage, path)
    if not replaced then
        os.remove(stage)
        return nil, replace_err
    end
    local directory_synced, directory_err = ffiutil.fsyncDirectory(ffiutil.dirname(path))
    if directory_synced ~= true then return nil, directory_err end
    return true
end

function M.path()
    return require("config/preset_store").rootDir() .. "/" .. FILE_NAME
end

function M.ensureFile()
    local path = M.path()
    local existing = io.open(path, "rb")
    if existing then
        existing:close()
        return false
    end
    local file, err = io.open(path, "ab")
    if not file then return nil, err end
    local closed, close_err = file:close()
    if closed == nil then return nil, close_err end
    local ffiutil = require("ffi/util")
    local synced, sync_err = ffiutil.fsyncDirectory(ffiutil.dirname(path))
    if synced ~= true then return nil, sync_err end
    return true
end

function M.get()
    local file = io.open(M.path(), "rb")
    if not file then
        M.ensureFile()
        return ""
    end
    local value = file:read(MAX_LENGTH + 2)
    file:close()
    return clean(value) or ""
end

function M.save(value)
    value = clean(value)
    if not value then return nil, "invalid Hardcover token" end
    return write_atomic(M.path(), value .. "\n")
end

function M.clear()
    local path = M.path()
    local file = io.open(path, "rb")
    if not file then return true end
    file:close()
    local removed, err = os.remove(path)
    if not removed then return nil, err end
    local ffiutil = require("ffi/util")
    local synced, sync_err = ffiutil.fsyncDirectory(ffiutil.dirname(path))
    if synced ~= true then return nil, sync_err end
    return true
end

M.clean = clean

return M

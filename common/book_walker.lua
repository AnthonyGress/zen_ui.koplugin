local lfs = require("libs/libkoreader-lfs")
local logger = require("common/zen_logger").new("book_walker")

local M = {}

M.DEFAULT_MAX_DEPTH = 3
M.SKIP_DIRS = {
    [".adds"] = true,
    [".kobo"] = true,
    ["dev"] = true,
    ["lost+found"] = true,
    ["proc"] = true,
    ["run"] = true,
    ["sys"] = true,
    ["system"] = true,
    ["temp"] = true,
    ["tmp"] = true,
}

function M.walk(roots, opts)
    local started_at = os.clock()
    local scanned_dirs = 0
    local scanned_files = 0
    local failed_dirs = 0
    opts = opts or {}
    local max_depth = tonumber(opts.max_depth) or M.DEFAULT_MAX_DEPTH
    local include_hidden = opts.include_hidden == true
    local on_dir = opts.on_dir
    local on_file = opts.on_file
    local on_scan_dir = opts.on_scan_dir

    local function join_path(path, name)
        if path == "/" then return "/" .. name end
        return path .. "/" .. name
    end

    local function scan(path, depth, path_attributes)
        if depth > max_depth then return false end
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if not ok then
            failed_dirs = failed_dirs + 1
            return false
        end
        scanned_dirs = scanned_dirs + 1
        if on_scan_dir then
            on_scan_dir(path, path_attributes or lfs.attributes(path), depth)
        end

        for name in iter, dir_obj do
            if name ~= "." and name ~= ".."
                    and (include_hidden or name:sub(1, 1) ~= ".") then
                local fullpath = join_path(path, name)
                local attributes = lfs.attributes(fullpath)
                if attributes and attributes.mode == "directory" then
                    local should_scan = not M.SKIP_DIRS[name] and not name:match("%.sdr$")
                    if should_scan and (not on_dir or on_dir(name, fullpath, attributes, depth) ~= false)
                            and scan(fullpath, depth + 1, attributes) then
                        return true
                    end
                elseif attributes and attributes.mode == "file" and not name:match("^%._") then
                    scanned_files = scanned_files + 1
                    if on_file and on_file(name, fullpath, attributes, depth, path) then
                        return true
                    end
                end
            end
        end
        return false
    end

    local stopped = false
    if type(roots) == "string" then
        stopped = scan(roots, 0)
    elseif type(roots) == "table" then
        for _i, root in ipairs(roots) do
            if type(root) == "string" and scan(root, 0) then
                stopped = true
                break
            end
        end
    end
    logger.perf("Walk completed", (os.clock() - started_at) * 1000,
        "dirs=", scanned_dirs, "files=", scanned_files,
        "failed_dirs=", failed_dirs, "stopped=", tostring(stopped))
    return stopped
end

return M

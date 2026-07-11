local function apply_browser_flat_view_compat()
    local FileChooser = require("ui/widget/filechooser")
    local ffiUtil = require("ffi/util")
    local lfs = require("libs/libkoreader-lfs")
    local paths = require("common/paths")
    local util = require("util")

    local MAX_DEPTH = 2
    local SKIP_DIRS = {
        [".sdr"] = true,
        [".adds"] = true,
        [".kobo"] = true,
        ["dev"] = true,
        ["koreader"] = true,
        ["proc"] = true,
        ["run"] = true,
        ["sys"] = true,
        ["system"] = true,
        ["tmp"] = true,
        ["temp"] = true,
        ["lost+found"] = true,
    }

    if FileChooser._zen_flat_view_compat_patched then return end
    FileChooser._zen_flat_view_compat_patched = true

    local has_native_flat_view = FileChooser.show_flat_view ~= nil

    local function is_in_home(path)
        if type(path) ~= "string" then return false end
        return paths.isInHomeDir(ffiUtil.realpath(path) or path)
    end

    local function sync_flat_view_flag()
        local enabled = G_reader_settings:isTrue("show_flat_view")
        if enabled and paths.hasUnsafeFlatViewHomeRoot() then
            enabled = false
            G_reader_settings:saveSetting("show_flat_view", false)
        end
        FileChooser.show_flat_view = enabled
        return enabled
    end

    sync_flat_view_flag()

    if has_native_flat_view then return end

    local function flat_view_enabled(path)
        return sync_flat_view_flag() and is_in_home(path)
    end

    local function show_hidden(self)
        if FileChooser.show_hidden ~= nil then
            return FileChooser.show_hidden
        end
        return self.show_hidden == true
    end

    local function should_scan_dir(name)
        if SKIP_DIRS[name] or name:match("%.sdr$") then return false end
        return true
    end

    local function scan_flat(self, path, collate, dirs, files, depth)
        depth = depth or 0
        if depth > MAX_DEPTH then return end
        local ok, iter, dir_obj = pcall(lfs.dir, path)
        if not ok then return end

        for f in iter, dir_obj do
            if show_hidden(self) or not util.stringStartsWith(f, ".") then
                local fullpath = path .. "/" .. f
                local attributes = lfs.attributes(fullpath) or {}
                if attributes.mode == "directory" and f ~= "." and f ~= ".."
                        and should_scan_dir(f) and self:show_dir(f) then
                    scan_flat(self, fullpath, collate, dirs, files, depth + 1)
                elseif attributes.mode == "file"
                        and not util.stringStartsWith(f, "._")
                        and self:show_file(f, fullpath) then
                    local item = true
                    if collate then
                        item = self:getListItem(path, f, fullpath, attributes, collate)
                    end
                    table.insert(files, item)
                end
            end
        end
    end

    if type(FileChooser.getPathList) == "function" then
        local orig_getPathList = FileChooser.getPathList
        FileChooser.getPathList = function(self, path, collate, dirs, files, ...)
            if flat_view_enabled(path) then
                return scan_flat(self, path, collate, dirs, files)
            end
            return orig_getPathList(self, path, collate, dirs, files, ...)
        end
    elseif type(FileChooser.getList) == "function" then
        local orig_getList = FileChooser.getList
        FileChooser.getList = function(self, path, collate, ...)
            if flat_view_enabled(path) then
                local dirs, files = {}, {}
                scan_flat(self, path, collate, dirs, files)
                return dirs, files
            end
            return orig_getList(self, path, collate, ...)
        end
    end
end

return apply_browser_flat_view_compat

-- coverbrowser_subprocess_compat.lua
-- Guard CoverBrowser cover extraction on KOReader builds where DrawContext
-- does not expose setIsolateSMask (older/newer API mismatch).

local function apply_coverbrowser_subprocess_compat()
    local logger = require("common/zen_logger").new("coverbrowser_subprocess_compat")

    local ok_bim, BookInfoManager = pcall(require, "bookinfomanager")
    if not ok_bim or not BookInfoManager then return end
    if BookInfoManager.__zen_cover_subprocess_compat_applied then return end
    BookInfoManager.__zen_cover_subprocess_compat_applied = true

    local function is_known_incompat(err)
        local msg = tostring(err)
        return msg:find("setIsolateSMask", 1, true) ~= nil
    end

    local function wrap_method(method_name)
        local orig = BookInfoManager[method_name]
        if type(orig) ~= "function" then return end

        BookInfoManager[method_name] = function(self, ...)
            local ok, a, b, c, d, e = pcall(orig, self, ...)
            if ok then
                return a, b, c, d, e
            end

            if is_known_incompat(a) then
                logger.warn("cover extraction compatibility fallback (" .. method_name .. "): " .. tostring(a))
                return nil
            end

            error(a)
        end
    end

    -- Both paths are used depending on caller/context.
    wrap_method("extractBookInfo")
    wrap_method("extractInBackground")
end

return apply_coverbrowser_subprocess_compat

local Font = require("ui/font")
local logger = require("common/zen_logger").new("library_font")

local M = {}

local DEFAULT_FACE = "cfont"
local DEFAULT_BASE_SIZE = 18
local checked_face
local resolved_face

local function get_cfg()
    local cached = rawget(_G, "__ZEN_UI_LIBRARY_FONT_CFG")
    if type(cached) == "table" then
        return cached
    end

    local p = rawget(_G, "__ZEN_UI_PLUGIN")
    if p and type(p.config) == "table" and type(p.config.library_font) == "table" then
        return p.config.library_font
    end

    local cfg = require("config/manager").get()
    if type(cfg) == "table" and type(cfg.library_font) == "table" then
        return cfg.library_font
    end

    return nil
end

function M.getBaseSize()
    local cfg = get_cfg()
    local sz = cfg and tonumber(cfg.font_size) or DEFAULT_BASE_SIZE
    if not sz then sz = DEFAULT_BASE_SIZE end
    sz = math.floor(sz + 0.5)
    if sz < 10 then sz = 10 end
    if sz > 40 then sz = 40 end
    return sz
end

function M.getScale(base_nominal)
    base_nominal = tonumber(base_nominal) or DEFAULT_BASE_SIZE
    if base_nominal <= 0 then base_nominal = DEFAULT_BASE_SIZE end
    return M.getBaseSize() / base_nominal
end

function M.scaleValue(value, base_nominal)
    if type(value) ~= "number" then return value end
    local scaled = value * M.getScale(base_nominal)
    return math.max(1, math.floor(scaled + 0.5))
end

function M.getFontName()
    local cfg = get_cfg()
    local face = cfg and cfg.font_face
    if not face or face == "" or face == "default" or face == DEFAULT_FACE then
        return DEFAULT_FACE
    end
    if face ~= checked_face then
        local ok, loaded_face = pcall(Font.getFace, Font, face, DEFAULT_BASE_SIZE)
        checked_face = face
        resolved_face = ok and loaded_face and face or DEFAULT_FACE
        if resolved_face == DEFAULT_FACE then
            logger.warn("configured library font unavailable; using default", face)
        end
    end
    return resolved_face
end

function M.getFace(size)
    return Font:getFace(M.getFontName(), math.max(1, math.floor(size)))
end

return M

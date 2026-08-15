local Font = require("ui/font")
local logger = require("common/zen_logger").new("library_font")
local defaults = require("config/defaults")
local LibraryFontPath = require("common/library_font_path")

local M = {}

local DEFAULT_FACE = "cfont"
local DEFAULT_BASE_SIZE = 18
local checked_face
local resolved_face

local function persist_cfg(cfg)
    local ok_manager, ConfigManager = pcall(require, "config/manager")
    if not ok_manager or type(ConfigManager.get) ~= "function"
            or type(ConfigManager.save) ~= "function" then
        return
    end
    local config = ConfigManager.get()
    if type(config) == "table" and config.library_font == cfg then
        local ok_save, err = pcall(ConfigManager.save, config)
        if not ok_save then logger.warn("failed to persist library font fallback", err) end
    end
end

local function probe(font_face)
    local resolved = LibraryFontPath.resolve(font_face)
    local ok, loaded_face = pcall(Font.getFace, Font, resolved, DEFAULT_BASE_SIZE)
    return ok and loaded_face ~= nil, resolved
end

local function restore_default(cfg)
    local default_face = defaults.library_font.font_face
    local fallback_face = DEFAULT_FACE
    if default_face ~= "default" and default_face ~= DEFAULT_FACE then
        local available, resolved = probe(default_face)
        if available then
            fallback_face = resolved
        else
            logger.warn("default library font unavailable; using KOReader default", resolved)
            default_face = "default"
        end
    end
    if cfg then
        cfg.font_face = default_face
        persist_cfg(cfg)
    end
    return default_face, fallback_face
end

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
        local available, candidate = probe(face)
        if available then
            checked_face = face
            resolved_face = candidate
        else
            logger.warn("configured library font unavailable; using default", face)
            checked_face, resolved_face = restore_default(cfg)
        end
    end
    return resolved_face
end

function M.getFace(size)
    return Font:getFace(M.getFontName(), math.max(1, math.floor(size)))
end

return M

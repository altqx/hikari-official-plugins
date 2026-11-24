local M = {}

local FADES = {{200, 200}, {300, 300}, {500, 500}, {0, 500}, {500, 0}}

local NAMES = {
    "fscx", "fscy", "bord", "shad", "blur", "move", "fsp", "fad", "frz", "pos", "org",
    "kf", "ko", "fn", "fs", "fr", "be", "an", "k", "K", "b", "i",
}
local KEY = {fr = "frz", kf = "k", ko = "k", K = "k"}

function M.units_of(text, bytes)
    local units = 0
    for i = 1, bytes do
        local b = text:byte(i)
        if b < 0x80 or b >= 0xC0 then
            units = units + (b >= 0xF0 and 2 or 1)
        end
    end
    return units
end

function M.bytes_of(text, units)
    local seen, i = 0, 1
    while seen < units and i <= #text do
        local b = text:byte(i)
        local length = b < 0x80 and 1 or b < 0xE0 and 2 or b < 0xF0 and 3 or 4
        seen = seen + (length == 4 and 2 or 1)
        i = i + length
    end
    return i - 1
end

local function in_block(before)
    local open = before:match(".*(){")
    local close = before:match(".*()}")
    return open ~= nil and (close == nil or close < open)
end

local function fades(args, offset, t)
    local from = offset - #args
    local items = {}
    if args == "" then
        items[1] = {label = t("fade-snippet"), insert = "${1:200},${2:200})", snippet = true, from = from, to = offset}
    end
    for _, fade in ipairs(FADES) do
        local insert = fade[1] .. "," .. fade[2] .. ")"
        if insert:sub(1, #args) == args then
            items[#items + 1] = {label = fade[1] .. "," .. fade[2], insert = insert, detail = t("fade-preset", fade[1], fade[2]),
                from = from, to = offset}
        end
    end
    return items
end

local function fonts(name, offset, t, styleFonts)
    local from = offset - M.units_of(name, #name)
    local typed = name:lower()
    local items = {}
    for _, font in ipairs(styleFonts()) do
        if font:lower():sub(1, #typed) == typed then
            items[#items + 1] = {label = font, insert = font, detail = t("font"), from = from, to = offset}
        end
    end
    return items
end

function M.complete(text, offset, t, styleFonts)
    local before = text:sub(1, M.bytes_of(text, offset))
    if not in_block(before) then
        return nil
    end
    local args = before:match("\\fad%(([%d,]*)$")
    if args then
        return fades(args, offset, t)
    end
    local name = before:match("\\fn([^\\}]*)$")
    if name then
        return fonts(name, offset, t, styleFonts)
    end
    return nil
end

local function numbers(args, count)
    local out = {}
    for part in (args .. ","):gmatch("([^,]*),") do
        out[#out + 1] = tonumber(part)
        if not out[#out] then
            return nil
        end
    end
    return #out >= count and out or nil
end

local function describe(name, arg, t)
    local key = KEY[name] or name
    if key == "fn" then
        return arg ~= "" and t("fn", arg) or nil
    end
    local inner = arg:match("^%((.-)%)?$")
    if key == "fad" or key == "pos" or key == "org" or key == "move" then
        local n = inner and numbers(inner, key == "move" and 4 or 2)
        return n and t(key, n[1], n[2], n[3], n[4]) or nil
    end
    local value = tonumber(arg)
    if not value then
        return nil
    end
    if key == "b" or key == "i" then
        return t(key, value == 1 and t("on") or value == 0 and t("off") or arg)
    end
    if key == "k" then
        return t("k", math.floor(value * 10))
    end
    if key == "an" and not (value >= 1 and value <= 9 and value % 1 == 0) then
        return nil
    end
    return t(key, arg)
end

function M.hover(text, offset, t)
    local at = M.bytes_of(text, offset) + 1
    if at > #text then
        return nil
    end
    local before = text:sub(1, at)
    if not in_block(before) then
        return nil
    end
    local start = before:match(".*()\\")
    if not start then
        return nil
    end
    local tag = text:match("^[^\\}]*", start + 1)
    if at > start + #tag then
        return nil
    end
    for _, name in ipairs(NAMES) do
        if tag:sub(1, #name) == name then
            local about = describe(name, tag:sub(#name + 1), t)
            if not about then
                return nil
            end
            return {text = about, from = M.units_of(text, start - 1), to = M.units_of(text, start + #tag)}
        end
    end
    return nil
end

return M

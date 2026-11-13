local M = {}

local array_mt = { __jsonarray = true }

function M.array(t)
    return setmetatable(t or {}, array_mt)
end

function M.is_array(t)
    if getmetatable(t) == array_mt then
        return true
    end
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n > 0 and n == #t
end

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function encode_string(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return escapes[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function encode(value, out, seen)
    local kind = type(value)
    if kind == "nil" then
        out[#out + 1] = "null"
    elseif kind == "boolean" then
        out[#out + 1] = tostring(value)
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("json: a number must be finite")
        end
        out[#out + 1] = (value == math.floor(value) and math.abs(value) < 2 ^ 53) and string.format("%d", value)
            or string.format("%.17g", value)
    elseif kind == "string" then
        out[#out + 1] = encode_string(value)
    elseif kind == "table" then
        if seen[value] then
            error("json: a table holds itself")
        end
        seen[value] = true
        if M.is_array(value) then
            out[#out + 1] = "["
            for i, v in ipairs(value) do
                if i > 1 then
                    out[#out + 1] = ","
                end
                encode(v, out, seen)
            end
            out[#out + 1] = "]"
        else
            local keys = {}
            for k in pairs(value) do
                if type(k) ~= "string" then
                    error("json: an object key must be text")
                end
                keys[#keys + 1] = k
            end
            table.sort(keys)
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then
                    out[#out + 1] = ","
                end
                out[#out + 1] = encode_string(k)
                out[#out + 1] = ":"
                encode(value[k], out, seen)
            end
            out[#out + 1] = "}"
        end
        seen[value] = nil
    else
        error("json: can't encode a " .. kind)
    end
end

function M.encode(value)
    local out = {}
    encode(value, out, {})
    return table.concat(out)
end

local function utf8_char(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

function M.decode(text)
    local pos = 1

    local function fail(what)
        error(string.format("json: %s at character %d", what, pos), 0)
    end

    local function skip()
        pos = text:find("[^ \t\r\n]", pos) or #text + 1
    end

    local value

    local function string_value()
        local parts = {}
        pos = pos + 1
        while true do
            local c = text:sub(pos, pos)
            if c == "" then
                fail("unfinished text")
            elseif c == '"' then
                pos = pos + 1
                return table.concat(parts)
            elseif c == "\\" then
                local e = text:sub(pos + 1, pos + 1)
                local simple = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
                if simple[e] then
                    parts[#parts + 1] = simple[e]
                    pos = pos + 2
                elseif e == "u" then
                    local code = tonumber(text:sub(pos + 2, pos + 5), 16)
                    if not code then
                        fail("bad \\u escape")
                    end
                    pos = pos + 6
                    if code >= 0xD800 and code < 0xDC00 and text:sub(pos, pos + 1) == "\\u" then
                        local low = tonumber(text:sub(pos + 2, pos + 5), 16)
                        if low and low >= 0xDC00 and low < 0xE000 then
                            code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
                            pos = pos + 6
                        end
                    end
                    parts[#parts + 1] = utf8_char(code)
                else
                    fail("bad escape")
                end
            else
                local stop = text:find('["\\]', pos) or #text + 1
                parts[#parts + 1] = text:sub(pos, stop - 1)
                pos = stop
            end
        end
    end

    function value()
        skip()
        local c = text:sub(pos, pos)
        if c == "{" then
            local out = {}
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == "}" then
                pos = pos + 1
                return out
            end
            while true do
                skip()
                if text:sub(pos, pos) ~= '"' then
                    fail("expected a key")
                end
                local k = string_value()
                skip()
                if text:sub(pos, pos) ~= ":" then
                    fail("expected ':'")
                end
                pos = pos + 1
                out[k] = value()
                skip()
                local sep = text:sub(pos, pos)
                pos = pos + 1
                if sep == "}" then
                    return out
                elseif sep ~= "," then
                    fail("expected ',' or '}'")
                end
            end
        elseif c == "[" then
            local out = M.array({})
            pos = pos + 1
            skip()
            if text:sub(pos, pos) == "]" then
                pos = pos + 1
                return out
            end
            while true do
                out[#out + 1] = value()
                skip()
                local sep = text:sub(pos, pos)
                pos = pos + 1
                if sep == "]" then
                    return out
                elseif sep ~= "," then
                    fail("expected ',' or ']'")
                end
            end
        elseif c == '"' then
            return string_value()
        elseif text:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif text:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif text:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        end
        local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        if not number or number == "" or number == "-" then
            fail("unexpected character")
        end
        pos = pos + #number
        return tonumber(number) or fail("bad number")
    end

    local ok, result = pcall(function()
        local v = value()
        skip()
        if pos <= #text then
            fail("text after the value")
        end
        return v
    end)
    if not ok then
        return nil, result
    end
    return result
end

return M

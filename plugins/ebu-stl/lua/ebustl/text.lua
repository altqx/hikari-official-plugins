local charset = require "ebustl.charset"

local M = {}

M.ROW_CHARS = 40
M.ROWS = 2

local function chars(s)
    local out = {}
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        out[#out + 1] = ch
    end
    return out
end

local function codepoint(ch)
    local b = {ch:byte(1, -1)}
    if #b == 1 then return b[1] end
    if #b == 2 then return (b[1] % 32) * 64 + b[2] % 64 end
    if #b == 3 then return (b[1] % 16) * 4096 + (b[2] % 64) * 64 + b[3] % 64 end
    return ((b[1] % 8) * 262144) + (b[2] % 64) * 4096 + (b[3] % 64) * 64 + b[4] % 64
end

local function on(value)
    return value == true or value == "-1" or value == "1" or value == -1 or value == 1
end

-- The Line's rows as cells {ch, italic, underline}, its alignment (1–9) and whether it had a drawing.
function M.parse(text, style)
    style = style or {}
    local base = {italic = on(style.italic), underline = on(style.underline)}
    local state = {italic = base.italic, underline = base.underline, drawing = false}
    local align = tonumber(style.alignment) or 2
    local rows, row = {}, {}
    local function put(ch)
        if not state.drawing then
            row[#row + 1] = {ch = ch, italic = state.italic, underline = state.underline}
        end
    end
    local i, n = 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c == "{" and text:find("}", i, true) then
            local close = text:find("}", i, true)
            local block = text:sub(i + 1, close - 1)
            for tag, arg in block:gmatch("\\(%a+)([^\\]*)") do
                if tag == "i" and arg:match("^%d") then
                    state.italic = arg:sub(1, 1) ~= "0"
                elseif tag == "u" and arg:match("^%d") then
                    state.underline = arg:sub(1, 1) ~= "0"
                elseif tag == "r" then
                    state.italic, state.underline = base.italic, base.underline
                elseif tag == "p" and arg:match("^%d") then
                    state.drawing = tonumber(arg:match("^%d+")) > 0
                elseif tag == "an" and arg:match("^[1-9]") then
                    align = tonumber(arg:sub(1, 1))
                elseif tag == "a" and arg:match("^%d") then
                    local legacy = {[1] = 1, [2] = 2, [3] = 3, [5] = 7, [6] = 8, [7] = 9, [9] = 4, [10] = 5, [11] = 6}
                    align = legacy[tonumber(arg:match("^%d+"))] or align
                end
            end
            i = close + 1
        elseif c == "\\" and text:sub(i + 1, i + 1) == "N" then
            rows[#rows + 1] = row
            row = {}
            i = i + 2
        elseif c == "\\" and (text:sub(i + 1, i + 1) == "n" or text:sub(i + 1, i + 1) == "h") then
            put(" ")
            i = i + 2
        else
            local ch = text:match("^[%z\1-\127\194-\244][\128-\191]*", i)
            put(ch)
            i = i + #ch
        end
    end
    rows[#rows + 1] = row
    return rows, align
end

local function trimmed(row)
    local first, last = 1, #row
    while first <= last and row[first].ch == " " do first = first + 1 end
    while last >= first and row[last].ch == " " do last = last - 1 end
    local out = {}
    for k = first, last do out[#out + 1] = row[k] end
    return out
end

-- Rows of at most ROW_CHARS cells, broken at spaces where it can; empty rows are dropped.
function M.wrap(rows)
    local out = {}
    for _, source in ipairs(rows) do
        local row = trimmed(source)
        while #row > M.ROW_CHARS do
            local cut = M.ROW_CHARS + 1
            while cut > 1 and row[cut].ch ~= " " do cut = cut - 1 end
            if cut == 1 then cut = M.ROW_CHARS + 1 end
            local head = {}
            for k = 1, cut - 1 do head[k] = row[k] end
            out[#out + 1] = trimmed(head)
            local rest = {}
            for k = cut, #row do rest[#rest + 1] = row[k] end
            row = trimmed(rest)
        end
        if #row > 0 then out[#out + 1] = row end
    end
    return out
end

-- One cell's bytes in Latin table 00, or nil when the table has no such character.
function M.encode(ch)
    if ch == "$" then return "\164" end
    if #ch == 1 and ch:byte() >= 32 and ch:byte() < 127 then return ch end
    return charset.teletext[codepoint(ch)]
end

-- `text` in code page 850, at most `size` bytes, padded with spaces; characters it lacks become "?".
function M.cp850(text, size)
    local out = {}
    for _, ch in ipairs(chars(text or "")) do
        local byte = #ch == 1 and ch:byte() < 128 and ch or charset.cp850[codepoint(ch)] or "?"
        if #table.concat(out) + #byte > size then break end
        out[#out + 1] = byte
    end
    local s = table.concat(out)
    return s .. string.rep(" ", size - #s)
end

return M

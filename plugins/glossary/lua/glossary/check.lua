local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.rules(rows)
    local rules = {}
    for _, row in ipairs(rows or {}) do
        if type(row) == "string" then
            local avoid, prefer = row:match("^(.-)%s*→%s*(.*)$")
            if not avoid then
                avoid, prefer = row:match("^(.-)%s*%->%s*(.*)$")
            end
            avoid = trim(avoid or row)
            prefer = prefer and trim(prefer) or ""
            if avoid ~= "" then
                rules[#rules + 1] = {avoid = avoid, prefer = prefer ~= "" and prefer or nil}
            end
        end
    end
    table.sort(rules, function(a, b)
        if #a.avoid ~= #b.avoid then
            return #a.avoid > #b.avoid
        end
        return a.avoid < b.avoid
    end)
    return rules
end

-- Override blocks and the \N, \n and \h escapes become spaces, so they never match and count as word breaks.
local function plain(text)
    local masked = text:gsub("{[^}]*}", function(block)
        return string.rep(" ", #block)
    end)
    return (masked:gsub("\\[Nnh]", "  "))
end

local function word_byte(text, at)
    local b = text:byte(at)
    return b ~= nil and (b >= 0x80 or text:sub(at, at):match("[%w_]") ~= nil)
end

local function utf16(text, bytes)
    local units = 0
    for i = 1, bytes do
        local b = text:byte(i)
        if b < 0x80 or b >= 0xC0 then
            units = units + (b >= 0xF0 and 2 or 1)
        end
    end
    return units
end

local function cased(found, prefer)
    if found:match("^%u[%u%A]*$") and found:match("%u%u") then
        return prefer:upper()
    end
    if found:match("^%u") then
        return prefer:sub(1, 1):upper() .. prefer:sub(2)
    end
    return prefer
end

function M.find(text, rules, matchCase)
    local hay = plain(text)
    if not matchCase then
        hay = hay:lower()
    end
    local taken, found = {}, {}
    for _, rule in ipairs(rules) do
        local needle = matchCase and rule.avoid or rule.avoid:lower()
        local start = 1
        while true do
            local s, e = hay:find(needle, start, true)
            if not s then
                break
            end
            start = s + 1
            local free = true
            for _, t in ipairs(taken) do
                if s <= t[2] and e >= t[1] then
                    free = false
                    break
                end
            end
            if free and not word_byte(hay, s - 1) and not word_byte(hay, e + 1) then
                taken[#taken + 1] = {s, e}
                local original = text:sub(s, e)
                found[#found + 1] = {
                    from = utf16(text, s - 1),
                    to = utf16(text, e),
                    avoid = original,
                    prefer = rule.prefer and cased(original, rule.prefer) or nil,
                }
            end
        end
    end
    table.sort(found, function(a, b) return a.from < b.from end)
    return found
end

function M.problems(lines, rules, matchCase, severity, t, most)
    local out = {}
    for _, line in ipairs(lines) do
        if not line.comment and type(line.text) == "string" then
            for _, hit in ipairs(M.find(line.text, rules, matchCase)) do
                if #out >= most then
                    return out
                end
                local p = {line = line.id, from = hit.from, to = hit.to, severity = severity, code = "glossary"}
                if hit.prefer then
                    p.message = t("use", hit.prefer, hit.avoid)
                    p.fixes = {{title = t("fix", hit.prefer), edits = {{from = hit.from, to = hit.to, insert = hit.prefer}}}}
                else
                    p.message = t("avoid", hit.avoid)
                end
                out[#out + 1] = p
            end
        end
    end
    return out
end

return M

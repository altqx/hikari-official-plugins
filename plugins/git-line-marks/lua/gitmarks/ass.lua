local M = {}

local DEFAULT_FORMAT = {"layer", "start", "end", "style", "name", "marginl", "marginr", "marginv", "effect", "text"}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parse_format(value)
    local fields = {}
    for field in value:gmatch("[^,]+") do
        fields[#fields + 1] = trim(field):lower()
    end
    return fields
end

function M.time(text)
    local h, m, s = text:match("^%s*(%d+):(%d+):([%d.]+)%s*$")
    if not h then
        return 0
    end
    local seconds = tonumber(s) or 0
    return math.floor(((tonumber(h) * 60 + tonumber(m)) * 60 + seconds) * 1000 + 0.5)
end

local function integer(text)
    return math.floor(tonumber(text and trim(text) or "") or 0)
end

local function event(kind, value, format)
    local fields = {}
    local rest = value
    for i = 1, #format - 1 do
        local comma = rest:find(",", 1, true)
        if not comma then
            fields[format[i]] = rest
            rest = nil
            break
        end
        fields[format[i]] = rest:sub(1, comma - 1)
        rest = rest:sub(comma + 1)
    end
    if rest then
        fields[format[#format]] = rest
    end
    local layer = fields.layer or (fields.marked and "0")
    return {
        comment = kind == "comment",
        layer = integer(layer),
        start = M.time(fields.start or ""),
        ["end"] = M.time(fields["end"] or ""),
        style = trim(fields.style or ""),
        actor = trim(fields.name or fields.actor or ""),
        marginL = integer(fields.marginl),
        marginR = integer(fields.marginr),
        marginV = integer(fields.marginv),
        effect = trim(fields.effect or ""),
        text = fields.text or "",
    }
end

function M.lines(text)
    text = text:gsub("^\239\187\191", "")
    local lines, section, format, found = {}, nil, DEFAULT_FORMAT, false
    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = raw:gsub("\r$", "")
        local header = line:match("^%s*%[(.-)%]%s*$")
        if header then
            section = header:lower()
            if section == "events" then
                found = true
            end
        elseif section == "events" then
            local key, value = line:match("^%s*([%a]+)%s*:%s*(.*)$")
            if key then
                key = key:lower()
                if key == "format" then
                    format = parse_format(value)
                elseif key == "dialogue" or key == "comment" then
                    lines[#lines + 1] = event(key, value, format)
                end
            end
        end
    end
    if not found then
        return nil
    end
    return lines
end

return M

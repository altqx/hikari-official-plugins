local M = {}

M.COLOURS = {added = "success", changed = "warning", removed = "danger"}

local TOOLTIP_LIMIT = 200

local function utf8_prefix(s, bytes)
    if #s <= bytes then return s end
    local cut = bytes
    while cut > 0 and s:byte(cut + 1) and s:byte(cut + 1) >= 0x80 and s:byte(cut + 1) < 0xC0 do
        cut = cut - 1
    end
    return s:sub(1, cut)
end

function M.label(ref)
    if ref:match("^%x+$") and #ref >= 12 then
        return ref:sub(1, 7)
    end
    if #ref > 40 then
        return utf8_prefix(ref, 39) .. "…"
    end
    return ref
end

local function fields_text(t, fields)
    local names = {}
    for n, field in ipairs(fields) do names[n] = t("field." .. field) end
    return table.concat(names, t("field.separator"))
end

local function removed_phrase(t, count, where)
    if count == 1 then return t("removed." .. where .. ".one") end
    return t("removed." .. where .. ".many", count)
end

local function describe(t, prefix, ref, status)
    if status.kind == "added" then
        return t(prefix .. "added", ref)
    end
    if #status.fields == 0 then
        return t(prefix .. "moved", ref)
    end
    local what = fields_text(t, status.fields)
    if status.moved then
        return t(prefix .. "moved_changed", ref, what)
    end
    return t(prefix .. "changed", ref, what)
end

local function each(result, lines, ref, t, prefix)
    local label = ref and M.label(ref)
    local out = {}
    for j, line in ipairs(lines) do
        local status = result.status[j]
        local above = result.removedAbove[j]
        local below = j == #lines and result.removedBelow > 0 and result.removedBelow or nil
        local parts, colour = {}, nil
        if status then
            parts[#parts + 1] = describe(t, prefix, label or "", status)
            colour = M.COLOURS[status.kind]
        end
        for _, gone in ipairs({{above, "above"}, {below, "below"}}) do
            if gone[1] then
                local phrase = removed_phrase(t, gone[1], gone[2])
                parts[#parts + 1] = (#parts == 0 and label) and t("removed", label, phrase) or phrase
                colour = M.COLOURS.removed
            end
        end
        if colour then
            out[#out + 1] = {line = line.id, row = j, colour = colour, text = table.concat(parts, t("joined"))}
        end
    end
    return out
end

function M.build(result, lines, ref, t)
    local marks = {}
    for n, e in ipairs(each(result, lines, ref, t, "")) do
        marks[n] = {line = e.line, colour = e.colour, tooltip = utf8_prefix(e.text, TOOLTIP_LIMIT)}
    end
    return marks
end

function M.entries(result, lines, t)
    return each(result, lines, nil, t, "list.")
end

return M

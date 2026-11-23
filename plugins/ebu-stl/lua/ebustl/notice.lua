local M = {}

local function rows(list, t)
    local names = {}
    for k, row in ipairs(list) do names[k] = tostring(row) end
    return table.concat(names, t("separator"))
end

-- The warning for a report from stl.build, or nil when nothing was lost.
function M.text(report, t)
    local parts = {}
    if #report.cut == 1 then
        parts[#parts + 1] = t("cut.one", rows(report.cut, t))
    elseif #report.cut > 1 then
        parts[#parts + 1] = t("cut.many", rows(report.cut, t))
    end
    if #report.unsupported == 1 then
        parts[#parts + 1] = t("unsupported.one", rows(report.unsupported, t))
    elseif #report.unsupported > 1 then
        parts[#parts + 1] = t("unsupported.many", rows(report.unsupported, t))
    end
    return #parts > 0 and table.concat(parts, " ") or nil
end

return M

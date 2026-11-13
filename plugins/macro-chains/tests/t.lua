local M = { passed = 0, failed = {} }

local function show(v, depth)
    depth = depth or 0
    if type(v) == "string" then
        return string.format("%q", v)
    elseif type(v) ~= "table" or depth > 3 then
        return tostring(v)
    end
    local keys = {}
    for k in pairs(v) do
        keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = tostring(k) .. "=" .. show(v[k], depth + 1)
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end
M.show = show

local function same(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not same(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end
M.same = same

function M.eq(actual, expected, what)
    if not same(actual, expected) then
        error(string.format("%s\n  expected %s\n  got      %s", what or "values differ", show(expected), show(actual)), 2)
    end
end

function M.ok(value, what)
    if not value then
        error(what or "expected a true value", 2)
    end
end

function M.fails(fn, pattern)
    local ok, err = pcall(fn)
    if ok then
        error("expected an error matching " .. pattern, 2)
    end
    if not tostring(err):find(pattern) then
        error("the error " .. tostring(err) .. " doesn't match " .. pattern, 2)
    end
end

function M.test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        M.passed = M.passed + 1
    else
        M.failed[#M.failed + 1] = name .. ": " .. tostring(err)
    end
end

function M.finish()
    for _, f in ipairs(M.failed) do
        print("FAIL " .. f)
    end
    print(string.format("%d tests passed, %d failed", M.passed, #M.failed))
    return #M.failed == 0
end

return M

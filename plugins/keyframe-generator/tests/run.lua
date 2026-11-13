package.path = "lua/?.lua;" .. package.path
bit = bit or require("bit")

local base64 = require("keyframes.base64")
local detect = require("keyframes.detect")

local tests, passed = {}, 0
local function test(name, fn)
    tests[#tests + 1] = {name = name, fn = fn}
end

local function encode(bytes)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local function at(shift)
            local k = math.floor(v / 2 ^ shift) % 64
            return alphabet:sub(k + 1, k + 1)
        end
        out[#out + 1] = at(18) .. at(12) .. (b and at(6) or "=") .. (c and at(0) or "=")
    end
    return table.concat(out)
end

local function same(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

local SIZE = 64 * 36

local function shot(seed)
    local pixels = {}
    for i = 1, SIZE do
        pixels[i] = (seed * 37 + (i % 64) * seed + math.floor(i / 64) * 3) % 256
    end
    return pixels
end

local function moving(base, frame)
    local pixels = {}
    for i = 1, SIZE do
        pixels[i] = math.min(255, base[i] + frame % 3)
    end
    return pixels
end

local function scan(cuts, length, options)
    local d = detect.new(options)
    local seed = 1
    for frame = 0, length - 1 do
        if cuts[frame] then
            seed = seed + 1
        end
        d:push(frame, moving(shot(seed), frame), SIZE)
    end
    return d.keyframes
end

test("base64 decodes every padding length", function()
    for _, bytes in ipairs({{}, {0}, {255, 1}, {1, 2, 3}, {9, 200, 17, 4}, {0, 0, 0, 0, 0}}) do
        local out, n = base64.bytes(encode(bytes))
        assert(n == #bytes, "length " .. #bytes)
        for i = 1, n do
            assert(out[i] == bytes[i])
        end
    end
end)

test("base64 decodes all byte values", function()
    local bytes = {}
    for i = 0, 255 do
        bytes[#bytes + 1] = i
    end
    local out, n = base64.bytes(encode(bytes))
    assert(n == 256 and out[256] == 255 and out[1] == 0)
end)

test("the first frame is a keyframe", function()
    assert(same(scan({}, 20), {0}))
end)

test("hard cuts become keyframes", function()
    assert(same(scan({[30] = true, [75] = true}, 120), {0, 30, 75}))
end)

test("motion within a shot is not a cut", function()
    local d = detect.new()
    for frame = 0, 59 do
        d:push(frame, moving(shot(3), frame), SIZE)
    end
    assert(same(d.keyframes, {0}))
end)

test("the minimum gap drops a cut too close to the last", function()
    assert(same(scan({[30] = true, [34] = true}, 60, {minGap = 10}), {0, 30}))
    assert(same(scan({[30] = true, [34] = true}, 60, {minGap = 2}), {0, 30, 34}))
end)

test("higher sensitivity lowers the thresholds", function()
    local low, high = detect.thresholds(20), detect.thresholds(80)
    assert(high.difference < detect.thresholds(50).difference and detect.thresholds(50).difference < low.difference)
    assert(high.histogram < low.histogram)
end)

for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
    else
        print("FAIL " .. t.name .. ": " .. tostring(err))
    end
end
print(passed .. " of " .. #tests .. " tests passed")
os.exit(passed == #tests and 0 or 1)

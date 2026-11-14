package.path = "lua/?.lua;" .. package.path
bit = bit or require("bit")

local base64 = require("keyframes.base64")
local detect = require("keyframes.detect")
local scanner = require("keyframes.scan")
local view = require("keyframes.view")

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


local function fakeVideo(length, cuts)
    local shots, seed = {}, 1
    for frame = 0, length - 1 do
        if cuts[frame] then
            seed = seed + 1
        end
        shots[frame] = seed
    end
    local calls = {}
    local function call(op, p)
        calls[#calls + 1] = op
        if op == "video.info" then
            return {open = length > 0, width = 1920, height = 1080}
        elseif op == "video.time_of_frame" then
            return {time = math.floor(p.frame * 1001 / 24)}
        elseif op == "video.frames" then
            if p.from >= length or p.to >= length then
                return nil, {code = "unavailable", message = "no frame"}
            end
            local frames = {}
            for frame = p.from, p.to do
                local pixels = moving(shot(shots[frame]), frame)
                local bytes = {}
                for i = 1, #pixels do
                    bytes[i] = pixels[i]
                end
                frames[#frames + 1] = {frame = frame, data = encode(bytes)}
            end
            return {width = 64, height = 36, format = "luma", frames = frames}
        end
    end
    return call, calls
end

local function job(cancelAfter)
    local seen = {progress = {}}
    local polls = 0
    seen.progress_fn = function(fraction, text)
        seen.progress[#seen.progress + 1] = text
    end
    return {
        progress = seen.progress_fn,
        cancelled = function()
            polls = polls + 1
            return cancelAfter ~= nil and polls > cancelAfter
        end,
    }, seen
end

test("the frame count is found without one in video.info", function()
    for _, length in ipairs({1, 2, 3, 255, 256, 257, 600}) do
        local call = fakeVideo(length, {})
        assert(scanner.frameCount(call) == length, "length " .. length)
    end
end)

test("a scan reads every frame in batches and finds the cuts", function()
    local call = fakeVideo(600, {[100] = true, [300] = true, [450] = true})
    local j, seen = job()
    local result = scanner.run(call, j, {sensitivity = 50, minGap = 10})
    assert(result.status == "found")
    assert(result.frames == 600)
    assert(same(result.keyframes, {0, 100, 300, 450}))
    assert(result.sensitivity == 50 and result.minGap == 10)
    assert(math.abs(result.duration - 600 * 1001 / 24) < 50)
    assert(seen.progress[1] == "Counting frames")
    assert(seen.progress[#seen.progress] == "Frame 512 of 600")
end)

test("cancel stops the scan between batches", function()
    local call = fakeVideo(600, {[100] = true})
    local j = job(1)
    local result = scanner.run(call, j, {})
    assert(result.status == "cancelled" and result.at == 256 and result.frames == 600)
end)

test("without a video the scan reads nothing", function()
    local call, calls = fakeVideo(0, {})
    local result = scanner.run(call, job(), {})
    assert(result.status == "novideo" and #calls == 1)
end)

test("the same video is the one with its size and length", function()
    local call = fakeVideo(300, {})
    assert(scanner.sameVideo(call, {width = 1920, height = 1080, frames = 300}))
    assert(not scanner.sameVideo(call, {width = 1920, height = 1080, frames = 301}))
    assert(not scanner.sameVideo(call, {width = 1280, height = 720, frames = 300}))
end)

test("counts group their thousands", function()
    assert(scanner.formatCount(7) == "7" and scanner.formatCount(820) == "820")
    assert(scanner.formatCount(34046) == "34,046" and scanner.formatCount(1234567) == "1,234,567")
end)

local function find(tree, id)
    if tree.id == id then
        return tree
    end
    for _, child in ipairs(tree.children or {}) do
        local found = find(child, id)
        if found then
            return found
        end
    end
end

local function texts(tree, out)
    out = out or {}
    out[#out + 1] = tree.text or tree.title
    for _, child in ipairs(tree.children or {}) do
        texts(child, out)
    end
    return out
end

local function has(tree, text)
    for _, t in ipairs(texts(tree)) do
        if t:find(text, 1, true) then
            return true
        end
    end
    return false
end

local SETTINGS = {sensitivity = 50, minGap = 10}
local RESULT = {frames = 34046, keyframes = {}, duration = 1420000, sensitivity = 50, minGap = 10}
for i = 1, 412 do
    RESULT.keyframes[i] = i * 80
end

test("the panel waits for a video", function()
    local tree = view.tree({video = false}, SETTINGS)
    assert(tree.children[1].kind == "empty")
    assert(find(tree, "find").disabled and find(tree, "sensitivity").disabled)
end)

test("the panel shows the settings and Find keyframes", function()
    local tree = view.tree({video = true}, SETTINGS)
    local button = find(tree, "find")
    assert(not button.disabled and button.style == "primary" and button.text == "Find keyframes")
    assert(find(tree, "sensitivity").value == 50 and find(tree, "min-gap").value == 10)
    assert(find(tree, "set") == nil)
end)

test("while it scans the controls wait and the job card has Cancel", function()
    local tree = view.tree({video = true, busy = true, result = RESULT}, SETTINGS)
    assert(find(tree, "find").disabled and find(tree, "min-gap").disabled)
    assert(has(tree, "Cancel it in the card") and find(tree, "set") == nil)
end)

test("the result changes nothing until Set or Save", function()
    local tree = view.tree({video = true, result = RESULT}, SETTINGS)
    assert(has(tree, "Found 412 keyframes"))
    assert(has(tree, "In 34,046 frames: a shot every 3.4 s on average."))
    assert(has(tree, "Sensitivity 50 · minimum gap 10 frames"))
    assert(not find(tree, "set").disabled and find(tree, "save"))
    assert(find(tree, "find").text == "Find keyframes again")
end)

test("after saving the panel says where", function()
    local tree = view.tree({video = true, result = RESULT, applied = {saved = "ep05_keyframes.txt"}}, SETTINGS)
    assert(has(tree, "Saved as ep05_keyframes.txt.") and find(tree, "set").disabled)
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

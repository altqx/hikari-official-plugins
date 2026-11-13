local base64 = require("keyframes.base64")
local detect = require("keyframes.detect")

local BATCH = 256
local EDGE = 64

local function lastFrame()
    local low, high = 0, 1
    while hikari.call("video.frames", {from = high, to = high, maxEdge = 16}) do
        low, high = high, high * 2
    end
    while high - low > 1 do
        local mid = math.floor((low + high) / 2)
        if hikari.call("video.frames", {from = mid, to = mid, maxEdge = 16}) then
            low = mid
        else
            high = mid
        end
    end
    return low
end

local function report(name, text)
    local file = hikari.files.open("data", "spike/" .. name)
    hikari.files.write(file, text)
end

local function scan(analyse)
    local info = hikari.call("video.info", {})
    if not info or not info.open then
        hikari.notify("Open a video first.", "warning")
        return
    end
    hikari.job.begin{title = "Finding keyframes"}
    local last = lastFrame()
    local detector = detect.new({
        sensitivity = hikari.settings.get("sensitivity"),
        minGap = hikari.settings.get("min-gap"),
    })
    local pixels = {}
    for from = 0, last, BATCH do
        if hikari.job.cancelled() then
            report("result.txt", "cancelled at " .. from .. "\n")
            return
        end
        hikari.job.progress(from / (last + 1), "Frame " .. from .. " of " .. (last + 1))
        local batch, err = hikari.call("video.frames", {from = from, to = math.min(from + BATCH - 1, last), maxEdge = EDGE})
        if not batch then
            report("result.txt", "failed at " .. from .. ": " .. tostring(err and err.message) .. "\n")
            return
        end
        if analyse then
            local count = batch.width * batch.height
            for _, f in ipairs(batch.frames) do
                pixels = base64.bytes(f.data, {})
                detector:push(f.frame, pixels, count)
            end
        end
    end
    local lines = {"frames " .. (last + 1), "keyframes " .. #detector.keyframes}
    for _, k in ipairs(detector.keyframes) do
        lines[#lines + 1] = tostring(k)
    end
    if analyse then
        hikari.call("video.set_keyframes", {frames = hikari.array(detector.keyframes)})
    end
    report("result.txt", table.concat(lines, "\n") .. "\n")
end

hikari.commands.register("scan", function() scan(true) end)
hikari.commands.register("fetch", function() scan(false) end)

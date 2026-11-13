local base64 = require("keyframes.base64")
local detect = require("keyframes.detect")

local scan = {}

local BATCH = 256
local EDGE = 64

local function exists(call, frame)
    return call("video.frames", {from = frame, to = frame, maxEdge = 16}) ~= nil
end

-- video.info has no frame count, so it is found by asking for single frames.
function scan.frameCount(call)
    if not exists(call, 0) then
        return 0
    end
    local low, high = 0, 1
    while exists(call, high) do
        low, high = high, high * 2
    end
    while high - low > 1 do
        local mid = math.floor((low + high) / 2)
        if exists(call, mid) then
            low = mid
        else
            high = mid
        end
    end
    return low + 1
end

function scan.video(call)
    local info = call("video.info", {})
    if not info or not info.open then
        return nil
    end
    return {width = info.width, height = info.height}
end

-- The open video is the scanned one when its size matches and it ends on the same frame.
function scan.sameVideo(call, scanned)
    local now = scan.video(call)
    return now ~= nil and now.width == scanned.width and now.height == scanned.height
        and exists(call, scanned.frames - 1) and not exists(call, scanned.frames)
end

local function duration(call, frames)
    if frames < 2 then
        return nil
    end
    local last = call("video.time_of_frame", {frame = frames - 1})
    local first = call("video.time_of_frame", {frame = 0})
    if not last or not first then
        return nil
    end
    return (last.time - first.time) * frames / (frames - 1)
end

function scan.formatCount(n)
    local text = tostring(n)
    while true do
        local grouped, count = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
        text = grouped
        if count == 0 then
            return text
        end
    end
end

-- job: {progress = fn(fraction, text), cancelled = fn() -> bool}
function scan.run(call, job, options)
    local video = scan.video(call)
    if not video then
        return {status = "novideo"}
    end
    job.progress(nil, "Counting frames")
    local frames = scan.frameCount(call)
    if frames == 0 then
        return {status = "failed", message = "The video has no frames HikariSub can read."}
    end
    video.frames = frames
    local detector = detect.new(options)
    for from = 0, frames - 1, BATCH do
        if job.cancelled() then
            return {status = "cancelled", at = from, frames = frames}
        end
        job.progress(from / frames, "Frame " .. scan.formatCount(from) .. " of " .. scan.formatCount(frames))
        local to = math.min(from + BATCH - 1, frames - 1)
        local batch, err = call("video.frames", {from = from, to = to, maxEdge = EDGE})
        if not batch then
            return {status = "failed", message = err and err.message or "HikariSub didn't give the frames."}
        end
        local count = batch.width * batch.height
        for _, f in ipairs(batch.frames) do
            detector:push(f.frame, base64.bytes(f.data), count)
        end
    end
    return {
        status = "found",
        video = video,
        frames = frames,
        keyframes = detector.keyframes,
        duration = duration(call, frames),
        sensitivity = detector.sensitivity,
        minGap = detector.minGap,
    }
end

return scan

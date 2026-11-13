local detect = {}

local BINS = 32
local HISTORY = 12

detect.defaults = {sensitivity = 50, minGap = 10}

function detect.thresholds(sensitivity)
    local scale = 2 ^ ((50 - sensitivity) / 25)
    return {
        difference = 0.12 * scale,
        histogram = 0.35 * scale,
        contrast = 2.2,
    }
end

function detect.new(options)
    options = options or {}
    local self = {
        limits = detect.thresholds(options.sensitivity or detect.defaults.sensitivity),
        minGap = options.minGap or detect.defaults.minGap,
        previous = nil,
        previousHistogram = nil,
        history = {},
        last = nil,
        keyframes = {},
    }
    return setmetatable(self, {__index = detect})
end

local function histogram(pixels, count)
    local bins = {}
    for i = 0, BINS - 1 do
        bins[i] = 0
    end
    local shift = 256 / BINS
    for i = 1, count do
        local b = math.floor(pixels[i] / shift)
        bins[b] = bins[b] + 1
    end
    return bins
end

local function mean(values)
    local sum = 0
    for i = 1, #values do
        sum = sum + values[i]
    end
    return #values > 0 and sum / #values or 0
end

function detect.measure(previous, pixels, count, previousHistogram, bins)
    local difference = 0
    for i = 1, count do
        local d = pixels[i] - previous[i]
        difference = difference + (d < 0 and -d or d)
    end
    local spread = 0
    for i = 0, BINS - 1 do
        local d = bins[i] - previousHistogram[i]
        spread = spread + (d < 0 and -d or d)
    end
    return difference / (count * 255), spread / (2 * count)
end

function detect:push(frame, pixels, count)
    local bins = histogram(pixels, count)
    local cut = false
    if not self.previous then
        cut = true
    else
        local difference, spread = detect.measure(self.previous, pixels, count, self.previousHistogram, bins)
        local score = difference + spread / 4
        local usual = mean(self.history)
        local limits = self.limits
        local stands_out = #self.history == 0 or score >= limits.contrast * usual
        cut = (difference >= limits.difference or spread >= limits.histogram) and stands_out
        if cut and self.last and frame - self.last < self.minGap then
            cut = false
        end
        table.insert(self.history, score)
        if #self.history > HISTORY then
            table.remove(self.history, 1)
        end
    end
    if cut then
        self.last = frame
        self.keyframes[#self.keyframes + 1] = frame
    end
    self.previous, self.previousHistogram = pixels, bins
    return cut
end

return detect

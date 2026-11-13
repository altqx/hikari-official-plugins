local byte = string.byte
local band, rshift, lshift, bor = bit.band, bit.rshift, bit.lshift, bit.bor

local values = {}
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
for i = 1, #alphabet do
    values[byte(alphabet, i)] = i - 1
end

local base64 = {}

function base64.bytes(text, out)
    out = out or {}
    local n = 0
    local length = #text
    while length > 0 and byte(text, length) == 61 do
        length = length - 1
    end
    local i = 1
    while i + 3 <= length do
        local a, b, c, d = byte(text, i, i + 3)
        local v = bor(lshift(values[a], 18), lshift(values[b], 12), lshift(values[c], 6), values[d])
        out[n + 1] = rshift(v, 16)
        out[n + 2] = band(rshift(v, 8), 255)
        out[n + 3] = band(v, 255)
        n = n + 3
        i = i + 4
    end
    local rest = length - i + 1
    if rest >= 2 then
        local a, b, c = byte(text, i, length)
        local v = bor(lshift(values[a], 18), lshift(values[b], 12), c and lshift(values[c], 6) or 0)
        out[n + 1] = rshift(v, 16)
        n = n + 1
        if rest == 3 then
            out[n + 1] = band(rshift(v, 8), 255)
            n = n + 1
        end
    end
    return out, n
end

return base64

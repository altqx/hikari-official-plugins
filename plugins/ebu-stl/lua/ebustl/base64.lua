local M = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function M.encode(data)
    local out = {}
    for i = 1, #data, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local s = {}
        for k = 4, 1, -1 do
            local index = n % 64
            s[k] = ALPHABET:sub(index + 1, index + 1)
            n = math.floor(n / 64)
        end
        if not c then s[4] = "=" end
        if not b then s[3] = "=" end
        out[#out + 1] = table.concat(s)
    end
    return table.concat(out)
end

return M

local M = {}

local SMALL_BLOCK = 40000
local WINDOW = 8
local SIMILAR = 0.5

M.FIELDS = {"text", "time", "style", "actor", "layer", "margins", "effect", "comment"}

local function key(line)
    return table.concat({
        line.comment and "1" or "0", line.layer, line.start, line["end"], line.style, line.actor,
        line.marginL, line.marginR, line.marginV, line.effect, line.text,
    }, "\0")
end

local function differences(old, new)
    local fields = {}
    if old.text ~= new.text then fields[#fields + 1] = "text" end
    if old.start ~= new.start or old["end"] ~= new["end"] then fields[#fields + 1] = "time" end
    if old.style ~= new.style then fields[#fields + 1] = "style" end
    if old.actor ~= new.actor then fields[#fields + 1] = "actor" end
    if old.layer ~= new.layer then fields[#fields + 1] = "layer" end
    if old.marginL ~= new.marginL or old.marginR ~= new.marginR or old.marginV ~= new.marginV then
        fields[#fields + 1] = "margins"
    end
    if old.effect ~= new.effect then fields[#fields + 1] = "effect" end
    if old.comment ~= new.comment then fields[#fields + 1] = "comment" end
    return fields
end

local function longest_increasing(seq)
    local tails, links = {}, {}
    for n, pair in ipairs(seq) do
        local lo, hi = 1, #tails
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if seq[tails[mid]][2] < pair[2] then lo = mid + 1 else hi = mid - 1 end
        end
        tails[lo] = n
        links[n] = lo > 1 and tails[lo - 1] or nil
    end
    local chain, n = {}, tails[#tails]
    while n do
        table.insert(chain, 1, seq[n])
        n = links[n]
    end
    return chain
end

local function small_lcs(a, b, alo, ahi, blo, bhi, match)
    local n, m = ahi - alo + 1, bhi - blo + 1
    local width = m + 1
    local table_ = {}
    for i = n, 0, -1 do
        for j = m, 0, -1 do
            local v = 0
            if i < n and j < m then
                if a[alo + i] == b[blo + j] then
                    v = table_[(i + 1) * width + j + 1] + 1
                else
                    local down, right = table_[(i + 1) * width + j], table_[i * width + j + 1]
                    v = down > right and down or right
                end
            end
            table_[i * width + j] = v
        end
    end
    local i, j = 0, 0
    while i < n and j < m do
        if a[alo + i] == b[blo + j] then
            match[alo + i] = blo + j
            i, j = i + 1, j + 1
        elseif table_[(i + 1) * width + j] >= table_[i * width + j + 1] then
            i = i + 1
        else
            j = j + 1
        end
    end
end

local function common_subsequence(a, b)
    local match = {}
    local stack = {{1, #a, 1, #b}}
    while #stack > 0 do
        local alo, ahi, blo, bhi = unpack(table.remove(stack))
        while alo <= ahi and blo <= bhi and a[alo] == b[blo] do
            match[alo] = blo
            alo, blo = alo + 1, blo + 1
        end
        while alo <= ahi and blo <= bhi and a[ahi] == b[bhi] do
            match[ahi] = bhi
            ahi, bhi = ahi - 1, bhi - 1
        end
        if alo <= ahi and blo <= bhi then
            local countA, countB, posB = {}, {}, {}
            for i = alo, ahi do countA[a[i]] = (countA[a[i]] or 0) + 1 end
            for j = blo, bhi do
                countB[b[j]] = (countB[b[j]] or 0) + 1
                posB[b[j]] = j
            end
            local seq = {}
            for i = alo, ahi do
                local k = a[i]
                if countA[k] == 1 and countB[k] == 1 then seq[#seq + 1] = {i, posB[k]} end
            end
            if #seq == 0 then
                if (ahi - alo + 1) * (bhi - blo + 1) <= SMALL_BLOCK then
                    small_lcs(a, b, alo, ahi, blo, bhi, match)
                end
            else
                local pi, pj = alo, blo
                for _, anchor in ipairs(longest_increasing(seq)) do
                    local i, j = anchor[1], anchor[2]
                    match[i] = j
                    stack[#stack + 1] = {pi, i - 1, pj, j - 1}
                    pi, pj = i + 1, j + 1
                end
                stack[#stack + 1] = {pi, ahi, pj, bhi}
            end
        end
    end
    return match
end

local function bigrams(s)
    local set, total = {}, 0
    for i = 1, math.min(#s, 400) - 1 do
        local g = s:sub(i, i + 1)
        set[g] = (set[g] or 0) + 1
        total = total + 1
    end
    return set, total
end

local function similarity(x, y)
    if x == y then return 1 end
    local sx, nx = bigrams(x)
    local sy, ny = bigrams(y)
    if nx + ny == 0 then return 0 end
    local shared = 0
    for g, c in pairs(sx) do
        local d = sy[g]
        if d then shared = shared + (c < d and c or d) end
    end
    return 2 * shared / (nx + ny)
end

local function same_slot(o, n)
    return o.start == n.start and o["end"] == n["end"] and o.style == n.style
end

local function gaps(count, matched)
    local gap, g = {}, 1
    for i = 1, count do
        gap[i] = g
        if matched[i] then g = g + 1 end
    end
    return gap
end

function M.compare(old, new)
    local a, b = {}, {}
    for i, line in ipairs(old) do a[i] = key(line) end
    for j, line in ipairs(new) do b[j] = key(line) end

    local pair = common_subsequence(a, b)
    local paired = {}
    for i, j in pairs(pair) do paired[j] = i end
    local gapOld = gaps(#a, pair)
    local gapNew = gaps(#b, paired)
    local anchorsNew = {}
    for j = 1, #b do
        if paired[j] then anchorsNew[gapNew[j]] = j end
    end

    local moved = {}
    local function link(i, j)
        pair[i], paired[j] = j, i
        moved[j] = gapOld[i] ~= gapNew[j]
    end

    local function pool(field)
        local byOld, byNewCount = {}, {}
        for i = 1, #a do
            if not pair[i] then
                local k = field(old[i], a[i])
                byOld[k] = byOld[k] or {}
                table.insert(byOld[k], i)
            end
        end
        for j = 1, #b do
            if not paired[j] then
                local k = field(new[j], b[j])
                byNewCount[k] = (byNewCount[k] or 0) + 1
            end
        end
        for j = 1, #b do
            if not paired[j] then
                local k = field(new[j], b[j])
                local candidates = byOld[k]
                if candidates and #candidates > 0 then
                    local pick
                    for n, i in ipairs(candidates) do
                        if gapOld[i] == gapNew[j] then pick = n break end
                    end
                    if not pick and #candidates == 1 and byNewCount[k] == 1 then pick = 1 end
                    if pick then
                        link(table.remove(candidates, pick), j)
                    end
                end
            end
        end
    end
    pool(function(_, k) return k end)
    pool(function(line) return line.text end)

    local looseOld, looseNew = {}, {}
    for i = 1, #a do
        if not pair[i] then
            local g = gapOld[i]
            looseOld[g] = looseOld[g] or {}
            table.insert(looseOld[g], i)
        end
    end
    for j = 1, #b do
        if not paired[j] then
            local g = gapNew[j]
            looseNew[g] = looseNew[g] or {}
            table.insert(looseNew[g], j)
        end
    end
    for g, js in pairs(looseNew) do
        local is = looseOld[g]
        if is then
            if #is == 1 and #js == 1 then
                link(is[1], js[1])
            else
                local from = 1
                for _, j in ipairs(js) do
                    local best, bestScore = nil, SIMILAR
                    for n = from, math.min(#is, from + WINDOW - 1) do
                        local i = is[n]
                        local score = same_slot(old[i], new[j]) and 1 or similarity(old[i].text, new[j].text)
                        if score >= bestScore then best, bestScore = n, score end
                    end
                    if best then
                        link(is[best], j)
                        from = best + 1
                    end
                end
            end
        end
    end

    local result = {status = {}, removedAbove = {}, removedBelow = 0, added = 0, changed = 0, removed = 0}
    for j = 1, #b do
        local i = paired[j]
        if not i then
            result.status[j] = {kind = "added"}
            result.added = result.added + 1
        elseif a[i] ~= b[j] or moved[j] then
            result.status[j] = {kind = "changed", fields = differences(old[i], new[j]), moved = moved[j]}
            result.changed = result.changed + 1
        end
    end

    local previous = 0
    for i = 1, #a do
        local j = pair[i]
        if j then
            if gapNew[j] == gapOld[i] then previous = j end
        else
            local target = math.max(previous, anchorsNew[gapOld[i] - 1] or 0) + 1
            result.removed = result.removed + 1
            if target > #b then
                result.removedBelow = result.removedBelow + 1
            else
                result.removedAbove[target] = (result.removedAbove[target] or 0) + 1
            end
        end
    end
    return result
end

return M

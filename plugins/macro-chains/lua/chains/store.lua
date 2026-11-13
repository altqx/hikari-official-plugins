local json = require "chains.json"
local model = require "chains.model"

local M = {}
M.__index = M

M.FILE = "chains.json"

function M.open(files)
    local self = setmetatable({ files = files, chains = json.array() }, M)
    local text = files.read(M.FILE)
    if not text then
        return self
    end
    local data, err = json.decode(text)
    if type(data) ~= "table" or type(data.chains) ~= "table" then
        files.write("chains.unreadable.json", text)
        self.problem = err or "no chains"
        return self
    end
    for _, chain in ipairs(data.chains) do
        if model.validate(chain) then
            self.chains[#self.chains + 1] = chain
        end
    end
    return self
end

function M:save()
    return self.files.write(M.FILE, json.encode({ format = model.FORMAT, chains = self.chains }))
end

function M:find(name)
    for i, chain in ipairs(self.chains) do
        if chain.name == name then
            return chain, i
        end
    end
end

function M:unique(name, except)
    local function taken(candidate)
        local found = self:find(candidate)
        return found ~= nil and found ~= except
    end
    if not taken(name) then
        return name
    end
    local n = 2
    while taken(string.format("%s (%d)", name, n)) do
        n = n + 1
    end
    return string.format("%s (%d)", name, n)
end

function M:add(chain)
    chain.name = self:unique(chain.name)
    self.chains[#self.chains + 1] = chain
    return chain
end

function M:remove(name)
    local _, i = self:find(name)
    if i then
        table.remove(self.chains, i)
    end
    return i ~= nil
end

function M:rename(old, new)
    local chain = self:find(old)
    if not chain or new == "" then
        return false
    end
    if new ~= old then
        chain.name = self:unique(new, chain)
    end
    return true
end

return M

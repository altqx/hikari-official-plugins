local json = require "chains.json"
local model = require "chains.model"

local M = {}
M.__index = M

local SKIPPED = { GLOBAL_UNDO = true, GLOBAL_REDO = true }

function M.new(own)
    return setmetatable({ own = own, chain = nil, undone = {} }, M)
end

function M:recording()
    return self.chain ~= nil
end

function M:start(name)
    self.chain = model.new_chain(name)
    self.undone = {}
end

function M:stop()
    local chain = self.chain
    self.chain = nil
    return chain
end

function M:push(step)
    local steps = self.chain.steps
    steps[#steps + 1] = step
    self.undone = {}
end

function M:macro_ran(data)
    if self.chain and data.ok then
        self:push(model.macro_step(data))
    end
end

function M:command_ran(data, name)
    if not self.chain or not data.ok then
        return
    end
    local steps = self.chain.steps
    if data.command == "GLOBAL_UNDO" then
        if #steps > 0 then
            self.undone[#self.undone + 1] = table.remove(steps)
        end
    elseif data.command == "GLOBAL_REDO" then
        if #self.undone > 0 then
            steps[#steps + 1] = table.remove(self.undone)
        end
    elseif not SKIPPED[data.command] and not data.command:find("^macro:") and data.command:sub(1, #self.own) ~= self.own then
        self:push(model.command_step(data.command, name))
    end
end

function M:steps()
    return self.chain and self.chain.steps or json.array()
end

return M

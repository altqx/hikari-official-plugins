local json = require "chains.json"
local model = require "chains.model"

local M = {}

local MODES = { const = "constant", user = "ask", exclude = "exclude" }
local SELECT = { macro = "macro", keep = "keep", changed = "changed" }

local function list(t)
    if type(t) ~= "table" then
        return {}
    end
    if json.is_array(t) then
        return t
    end
    local keys = {}
    for k in pairs(t) do
        if tonumber(k) then
            keys[#keys + 1] = tonumber(k)
        end
    end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        out[#out + 1] = t[tostring(k)] or t[k]
    end
    return out
end

local function chains_in(root)
    if type(root) ~= "table" then
        return nil
    end
    if type(root.config) == "table" and type(root.config.chains) == "table" then
        return root.config.chains
    end
    if type(root.chains) == "table" and not json.is_array(root.chains) then
        return root.chains
    end
    for _, v in pairs(root) do
        if type(v) == "table" and type(list(v)[1]) == "table" and list(v)[1].macro then
            return root
        end
    end
    return nil
end

local function resolve(name, macros)
    local leaf = name:match("([^/]+)$")
    local by_leaf
    for _, m in ipairs(macros) do
        if m.macro == name then
            return m
        end
        if not by_leaf and m.macro:match("([^/]+)$") == leaf then
            by_leaf = m
        end
    end
    return by_leaf
end

local function dialog_of(saved)
    local fields = json.array()
    local names = {}
    for name in pairs(type(saved.values) == "table" and saved.values or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local v = saved.values[name]
        local mode = MODES[v.mode]
        if mode and mode ~= "exclude" then
            local value = v.value
            if value == nil then
                value = v.text
            end
            fields[#fields + 1] = { name = name, kind = v.class, mode = mode, value = value,
                title = v.flabel or name,
                control = { name = name, kind = v.class, hint = v.hint, items = v.items, min = v.min, max = v.max, step = v.step } }
        end
    end
    local button = type(saved.button) == "table" and saved.button or {}
    return { partial = true, controls = json.array(), button = type(button.value) == "string" and button.value or "",
        fields = fields }, button.mode
end

function M.read(text, macros)
    local root, err = json.decode(text)
    if root == nil then
        return nil, "not_json", err
    end
    local saved = chains_in(root)
    if not saved then
        return nil, "no_chains"
    end
    local names = {}
    for name in pairs(saved) do
        names[#names + 1] = name
    end
    table.sort(names)
    local chains, problems = json.array(), json.array()
    for _, name in ipairs(names) do
        local chain = model.new_chain(name)
        for i, s in ipairs(list(saved[name])) do
            local step = { kind = "macro", macro = tostring(s.macro or ""), select = SELECT[s.select] or "macro",
                show = false, learn = true, dialogs = json.array() }
            local found = resolve(step.macro, macros)
            if found then
                step.file, step.macro = found.file, found.macro
            else
                step.missing = true
                problems[#problems + 1] = { chain = name, step = i, problem = "missing_macro", macro = step.macro }
            end
            for _, d in ipairs(list(s.dialogs)) do
                local dialog, button_mode = dialog_of(d)
                if button_mode == "passthrough" or button_mode == "passthrough_defaults" then
                    step.show = true
                elseif button_mode == "user" then
                    problems[#problems + 1] = { chain = name, step = i, problem = "asked_button" }
                end
                step.dialogs[#step.dialogs + 1] = dialog
            end
            chain.steps[#chain.steps + 1] = step
        end
        chains[#chains + 1] = chain
    end
    return { chains = chains, problems = problems }
end

return M

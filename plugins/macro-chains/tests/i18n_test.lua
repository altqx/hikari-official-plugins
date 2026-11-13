local t = require "t"
local json = require "chains.json"
local model = require "chains.model"

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local en = assert(json.decode(read("i18n/en.json")))

t.test("every text the code asks for is in en.json", function()
    local missing = {}
    local sources = { "main.lua" }
    for _, name in ipairs({ "app", "view", "replay" }) do
        sources[#sources + 1] = "lua/chains/" .. name .. ".lua"
    end
    for _, path in ipairs(sources) do
        for key in read(path):gmatch("[^%w_]t%(\"([%w_]+)\"") do
            if en[key] == nil and not key:find("_$") then
                missing[#missing + 1] = path .. ": " .. key
            end
        end
    end
    for mode in pairs(model.FIELD_MODES) do
        if not en["mode_" .. mode] then
            missing[#missing + 1] = "mode_" .. mode
        end
    end
    for mode in pairs(model.SELECT_MODES) do
        if not en["select_" .. mode] then
            missing[#missing + 1] = "select_" .. mode
        end
    end
    for _, why in ipairs({ "not_json", "no_chains" }) do
        if not en["import_" .. why] then
            missing[#missing + 1] = "import_" .. why
        end
    end
    table.sort(missing)
    t.eq(missing, {})
end)

t.test("the credit names AegisubChain and its author", function()
    t.eq(en.credit, "Inspired by AegisubChain by arch1t3cht.")
end)

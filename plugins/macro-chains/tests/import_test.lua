local t = require "t"
local import = require "chains.import"
local replay = require "chains.replay"
local fake = require "fake_host"

local macros = {
    { file = "fade.lua", macro = "Typesetting/Fade", script = "Fade" },
    { file = "kara.lua", macro = "Karaoke/Split", script = "Kara" },
}

local config = [[{"config": {"chain_menu": "AegisubChain Chains/", "chains": {
  "Signs": [
    {"macro": "Typesetting/Fade", "select": "keep", "dialogs": [
      {"values": {"in": {"value": 200, "mode": "const"},
                  "out": {"value": 300, "mode": "user", "flabel": "Fade out", "class": "intedit", "min": 0, "max": 5000},
                  "skip": {"value": true, "mode": "exclude"}},
       "button": {"value": "Apply", "mode": "const"}}]},
    {"macro": "Split", "select": "changed", "dialogs": [{"button": {"mode": "passthrough"}}]}
  ],
  "Lost": [{"macro": "Gone/Away", "dialogs": [{"values": {}, "button": {"value": "OK", "mode": "user"}}]}]
}}}]]

t.test("an AegisubChain config imports every chain with its modes, selection and scripts", function()
    local result = assert(import.read(config, macros))
    t.eq(#result.chains, 2)
    local signs = result.chains[2]
    t.eq(signs.name, "Signs")
    local fade = signs.steps[1]
    t.eq({ fade.file, fade.macro, fade.select, fade.learn, fade.show }, { "fade.lua", "Typesetting/Fade", "keep", true, false })
    local fields = fade.dialogs[1].fields
    t.eq(#fields, 2)
    t.eq({ fields[1].name, fields[1].mode, fields[1].value }, { "in", "constant", 200 })
    t.eq({ fields[2].name, fields[2].mode, fields[2].title, fields[2].control.max }, { "out", "ask", "Fade out", 5000 })
    t.eq(fade.dialogs[1].button, "Apply")
    local split = signs.steps[2]
    t.eq({ split.file, split.macro, split.select, split.show }, { "kara.lua", "Karaoke/Split", "changed", true })
end)

t.test("what can't come across is named, and the chain is still kept", function()
    local result = assert(import.read(config, macros))
    local lost = result.chains[1]
    t.eq({ lost.name, lost.steps[1].missing, lost.steps[1].macro }, { "Lost", true, "Gone/Away" })
    t.eq(result.problems, { { chain = "Lost", step = 1, problem = "missing_macro", macro = "Gone/Away" },
        { chain = "Lost", step = 1, problem = "asked_button" } })
end)

t.test("an exported selection of chains imports too", function()
    local result = assert(import.read([[{"Quick": [{"macro": "Typesetting/Fade", "dialogs": []}]}]], macros))
    t.eq({ result.chains[1].name, result.chains[1].steps[1].file, result.chains[1].steps[1].select }, { "Quick", "fade.lua", "macro" })
end)

t.test("text that isn't a chain file is refused with the reason", function()
    t.eq({ import.read("{not json", macros) }, { nil, "not_json", "json: expected a key at character 2" })
    t.eq({ import.read('{"config": {"path": ""}}', macros) }, { nil, "no_chains" })
end)

t.test("an imported dialog is answered by its field names until a run teaches it the real controls", function()
    local chain = assert(import.read(config, macros)).chains[2]
    local host = fake.new({ "a" })
    host.macros["Typesetting/Fade"] = function() end
    host.macros["Karaoke/Split"] = function() end
    host.answer = { "run", { ["s1-d1-out"] = 400 } }
    t.eq(replay.run(chain, host, fake.t).outcome, "applied")
    local answer = host.requests[1].answers[1]
    t.eq(answer.values, { ["in"] = 200, out = 400 })
    t.eq(answer.controls, { { kind = "edit", name = "in" }, { kind = "intedit", name = "out" } })
    t.eq(host.requests[2].show, "prefilled")
end)

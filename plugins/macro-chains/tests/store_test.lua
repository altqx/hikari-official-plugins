local t = require "t"
local store = require "chains.store"
local model = require "chains.model"

local function folder(initial)
    local files = { data = initial or {} }
    function files.read(path) return files.data[path] end
    function files.write(path, text) files.data[path] = text return true end
    return files
end

t.test("chains survive a save and a fresh open", function()
    local files = folder()
    local s = store.open(files)
    local chain = model.new_chain("Signs")
    chain.steps = { model.command_step("EDIT_LINE_DUPLICATE", "Duplicate") }
    s:add(chain)
    s:add(model.new_chain("Empty"))
    assert(s:save())
    local again = store.open(files)
    t.eq(#again.chains, 2)
    t.eq(again:find("Signs").steps[1].command, "EDIT_LINE_DUPLICATE")
    t.ok(files.data["chains.json"]:find('"steps":[]', 1, true))
end)

t.test("names stay unique when adding and renaming", function()
    local s = store.open(folder())
    s:add(model.new_chain("Signs"))
    t.eq(s:add(model.new_chain("Signs")).name, "Signs (2)")
    t.eq(s:add(model.new_chain("Signs")).name, "Signs (3)")
    t.ok(s:rename("Signs (3)", "Signs"))
    t.eq(s.chains[3].name, "Signs (3)")
    t.ok(not s:rename("Nope", "x"))
    t.ok(s:remove("Signs (2)"))
    t.eq(#s.chains, 2)
end)

t.test("an unreadable file is kept aside and the plugin starts with no chains", function()
    local files = folder({ ["chains.json"] = "{broken" })
    local s = store.open(files)
    t.eq(#s.chains, 0)
    t.ok(s.problem)
    t.eq(files.data["chains.unreadable.json"], "{broken")
end)

t.test("a stored chain that no longer validates is dropped, the others load", function()
    local files = folder({ ["chains.json"] = '{"format":1,"chains":[{"name":"ok","steps":[]},{"name":"","steps":[]}]}' })
    t.eq(#store.open(files).chains, 1)
end)

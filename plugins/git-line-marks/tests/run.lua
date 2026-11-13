package.path = "lua/?.lua;lua/?/init.lua;tests/?.lua;" .. package.path

local ass = require "gitmarks.ass"
local diff = require "gitmarks.diff"
local marks = require "gitmarks.marks"
local compare = require "gitmarks.compare"
local panel = require "gitmarks.panel"
local repo = require "repo"

local passed, failed = 0, {}

local function test(name, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then
        passed = passed + 1
    else
        failed[#failed + 1] = name .. ": " .. tostring(err)
    end
end

local function show(v)
    if type(v) == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(x, y) return tostring(x) < tostring(y) end)
        local parts = {}
        for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k]) end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return type(v) == "string" and string.format("%q", v) or tostring(v)
end

local function eq(actual, expected, what)
    if show(actual) ~= show(expected) then
        error((what or "value") .. "\n  expected " .. show(expected) .. "\n  actual   " .. show(actual), 2)
    end
end

local strings = {}
do
    local f = assert(io.open("i18n/en.json", "rb"))
    for k, v in f:read("*a"):gmatch('"([^"]+)":%s*"([^"]*)"') do strings[k] = v end
    f:close()
end

local function t(key, ...)
    local args = {...}
    local text = strings[key] or key
    return (text:gsub("%%(%d)", function(n) return tostring(args[tonumber(n)]) end))
end

local HEADER = table.concat({
    "[Script Info]", "ScriptType: v4.00+", "", "[V4+ Styles]",
    "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, "
        .. "Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, "
        .. "MarginL, MarginR, MarginV, Encoding",
    "Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,2,2,10,10,10,1",
    "", "[Events]", "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
}, "\n")

local function stamp(ms)
    local cs = math.floor(ms / 10)
    return string.format("%d:%02d:%02d.%02d", math.floor(cs / 360000), math.floor(cs / 6000) % 60,
        math.floor(cs / 100) % 60, cs % 100)
end

local function L(start, text, fields)
    fields = fields or {}
    return {
        comment = fields.comment or false, layer = fields.layer or 0, start = start,
        ["end"] = fields["end"] or start + 2000, style = fields.style or "Default", actor = fields.actor or "",
        marginL = 0, marginR = 0, marginV = 0, effect = fields.effect or "", text = text,
    }
end

local function file(lines)
    local out = {HEADER}
    for _, l in ipairs(lines) do
        out[#out + 1] = string.format("%s: %d,%s,%s,%s,%s,%d,%d,%d,%s,%s", l.comment and "Comment" or "Dialogue",
            l.layer, stamp(l.start), stamp(l["end"]), l.style, l.actor, l.marginL, l.marginR, l.marginV, l.effect, l.text)
    end
    return table.concat(out, "\n") .. "\n"
end

local function with_ids(lines)
    for n, l in ipairs(lines) do l.id, l.row = 100 + n, n end
    return lines
end

local function base()
    return {
        L(1000, "The lantern swings over the quiet pier."),
        L(4000, "Someone left the gate open again."),
        L(7000, "Mind the third step, it creaks."),
        L(10000, "We should have taken the early ferry."),
        L(13000, "The tide tables say otherwise."),
        L(16000, "Fine. Tomorrow, then."),
    }
end

local function copy(lines)
    local out = {}
    for n, l in ipairs(lines) do
        local c = {}
        for k, v in pairs(l) do c[k] = v end
        out[n] = c
    end
    return out
end

local function summary(result, count)
    local out = {}
    for j = 1, count do
        local s = result.status[j]
        local entry = s and (s.kind == "added" and "added" or ("changed:" .. table.concat(s.fields, "+")
            .. (s.moved and ":moved" or ""))) or nil
        if result.removedAbove[j] then entry = (entry and entry .. " " or "") .. "removed" .. result.removedAbove[j] end
        if entry then out[j] = entry end
    end
    if result.removedBelow > 0 then out.below = result.removedBelow end
    return out
end

test("ass: reads Dialogue and Comment Events with their fields", function()
    local lines = ass.lines("\239\187\191[Script Info]\r\nTitle: x\r\n\r\n[Events]\r\n"
        .. "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\r\n"
        .. "Dialogue: 2,0:00:01.50,0:01:02.07,Sign,Mira,1,2,3,fx,Hello, world {\\i1}again\r\n"
        .. "Comment: 0,1:00:00.00,1:00:00.10,Default,,0,0,0,,note\r\n")
    eq(#lines, 2, "count")
    eq(lines[1], {comment = false, layer = 2, start = 1500, ["end"] = 62070, style = "Sign", actor = "Mira",
        marginL = 1, marginR = 2, marginV = 3, effect = "fx", text = "Hello, world {\\i1}again"})
    eq(lines[2].comment, true, "comment")
    eq(lines[2].start, 3600000, "hours")
end)

test("ass: follows the Format line's order and SSA's Marked field", function()
    local lines = ass.lines("[Events]\nFormat: Marked, Start, End, Name, Style, MarginL, MarginR, MarginV, Effect, Text\n"
        .. "Dialogue: Marked=0,0:00:00.00,0:00:01.00,Kai,Main,0,0,0,,Hi\n")
    eq(lines[1].style, "Main", "style")
    eq(lines[1].actor, "Kai", "actor")
    eq(lines[1].layer, 0, "layer")
end)

test("ass: a file without Events is not ASS", function()
    eq(ass.lines("1\n00:00:01,000 --> 00:00:02,000\nHello\n"), nil)
end)

test("ass: an Events section with no Lines is empty", function()
    eq(#ass.lines("[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"), 0)
end)

test("diff: the same Lines give nothing", function()
    local r = diff.compare(base(), with_ids(base()))
    eq(summary(r, 6), {})
    eq({r.added, r.changed, r.removed}, {0, 0, 0})
end)

test("diff: an inserted Line is added", function()
    local new = base()
    table.insert(new, 3, L(5500, "A gull lands on the railing."))
    eq(summary(diff.compare(base(), new), #new), {[3] = "added"})
end)

test("diff: an edited text is changed, not removed and added", function()
    local new = base()
    new[2].text = "Somebody left the gate open again."
    eq(summary(diff.compare(base(), new), #new), {[2] = "changed:text"})
end)

test("diff: a Line replaced in place by another is changed", function()
    local new = base()
    new[4] = L(10000, "Completely different words here.")
    eq(summary(diff.compare(base(), new), #new), {[4] = "changed:text"})
end)

test("diff: a retimed file is changed in time only", function()
    local new = base()
    for _, l in ipairs(new) do l.start, l["end"] = l.start + 120, l["end"] + 120 end
    local r = diff.compare(base(), new)
    local expected = {}
    for j = 1, 6 do expected[j] = "changed:time" end
    eq(summary(r, 6), expected)
    eq({r.added, r.removed}, {0, 0})
end)

test("diff: a moved Line is changed and moved, not removed and added", function()
    local new = base()
    local line = table.remove(new, 2)
    table.insert(new, 5, line)
    local r = diff.compare(base(), new)
    eq(summary(r, #new), {[5] = "changed::moved"})
    eq({r.added, r.removed}, {0, 0})
end)

test("diff: a moved and retimed Line names the time", function()
    local new = base()
    local line = table.remove(new, 1)
    line.start, line["end"] = 17000, 18000
    table.insert(new, line)
    eq(summary(diff.compare(base(), new), #new), {[6] = "changed:time:moved"})
end)

test("diff: two swapped Lines are one move", function()
    local new = base()
    new[3], new[4] = new[4], new[3]
    local r = diff.compare(base(), new)
    eq(r.changed, 1, "changed")
    eq({r.added, r.removed}, {0, 0})
end)

test("diff: style, actor, layer, margins, effect and Comment count as changes", function()
    local new = base()
    new[1].style = "Sign"
    new[2].actor = "Mira"
    new[3].layer = 1
    new[4].marginV = 40
    new[5].effect = "karaoke"
    new[6].comment = true
    eq(summary(diff.compare(base(), new), 6), {"changed:style", "changed:actor", "changed:layer",
        "changed:margins", "changed:effect", "changed:comment"})
end)

test("diff: a removed Line marks the next Line", function()
    local new = base()
    table.remove(new, 3)
    local r = diff.compare(base(), new)
    eq(summary(r, #new), {[3] = "removed1"})
    eq(r.removed, 1)
end)

test("diff: removed Lines at the start and end", function()
    local new = base()
    table.remove(new, 6)
    table.remove(new, 1)
    eq(summary(diff.compare(base(), new), #new), {[1] = "removed1", below = 1})
end)

test("diff: two removed Lines in a row count once on the next Line", function()
    local new = base()
    table.remove(new, 3)
    table.remove(new, 3)
    eq(summary(diff.compare(base(), new), #new), {[3] = "removed2"})
end)

test("diff: a removed Line before a changed one marks it twice", function()
    local new = base()
    table.remove(new, 3)
    new[3].text = "We should have taken the late ferry."
    eq(summary(diff.compare(base(), new), #new), {[3] = "changed:text removed1"})
end)

test("diff: one more copy of a repeated Line is one added", function()
    local old = {L(1000, "♪"), L(1000, "♪"), L(3000, "Lalala")}
    local new = {L(1000, "♪"), L(1000, "♪"), L(1000, "♪"), L(3000, "Lalala")}
    local r = diff.compare(old, new)
    eq({r.added, r.changed, r.removed}, {1, 0, 0})
end)

test("diff: a common text far away is not taken for a move", function()
    local old = {L(1000, "Yes."), L(2000, "One"), L(3000, "Two"), L(4000, "Three")}
    local new = {L(2000, "One"), L(3000, "Two"), L(4000, "Three"), L(9000, "Yes."), L(9500, "Yes.")}
    local r = diff.compare(old, new)
    eq(r.removed + r.added + r.changed > 0, true)
    eq(r.changed <= 1, true, "at most one pairing")
end)

test("diff: an empty Document only removes", function()
    local r = diff.compare(base(), {})
    eq({r.removed, r.removedBelow}, {6, 6})
end)

test("diff: an empty ref adds everything", function()
    eq(diff.compare({}, base()).added, 6)
end)

test("marks: colours and tooltips", function()
    local new = with_ids(base())
    new[2].text = "Somebody left the gate open again."
    table.insert(new, 4, L(8500, "A gull lands on the railing."))
    with_ids(new)
    table.remove(new, 6)
    with_ids(new)
    local list = marks.build(diff.compare(base(), new), new, "v1.0", t)
    eq(list, {
        {line = 102, colour = "warning", tooltip = "Changed since v1.0: text"},
        {line = 104, colour = "success", tooltip = "Added since v1.0"},
        {line = 106, colour = "danger", tooltip = "1 Line removed above since v1.0"},
    })
end)

test("marks: removed above a changed Line, and below the last", function()
    local new = base()
    table.remove(new, 3)
    new[3].start = 10100
    table.remove(new)
    with_ids(new)
    local list = marks.build(diff.compare(base(), new), new, "main", t)
    eq(list, {
        {line = 103, colour = "danger", tooltip = "Changed since main: time; 1 Line removed above"},
        {line = 104, colour = "danger", tooltip = "1 Line removed below since main"},
    })
end)

test("marks: a moved Line, a long commit and a long ref", function()
    local new = base()
    new[1], new[2] = new[2], new[1]
    with_ids(new)
    local list = marks.build(diff.compare(base(), new), new, "0123456789abcdef0123456789abcdef01234567", t)
    eq(list[1].tooltip:find("since 0123456", 1, true) ~= nil, true, list[1].tooltip)
    eq(marks.label(string.rep("release/", 10)):len() <= 42, true)
    eq(marks.label("HEAD~2"), "HEAD~2")
end)

test("marks: every tooltip fits 200 characters", function()
    local long = string.rep("ü", 300)
    local status = {status = {{kind = "changed", fields = diff.FIELDS, moved = true}}, removedAbove = {[1] = 9},
        removedBelow = 4}
    local list = marks.build(status, with_ids({L(0, "x")}), long, function(key, ...)
        return t(key, ...) .. long
    end)
    eq(#list[1].tooltip <= 200, true, "length")
    eq(list[1].tooltip:find("[\128-\191]$") == nil or list[1].tooltip:find("ü$") ~= nil, true, "whole characters")
end)

local function host_for(dir, path, current)
    local host = {set = {}, cleared = 0}
    host.vcs = {show = function(ref)
        local text, err = repo.show(dir, ref, path)
        if not text then return nil, err end
        return text, {ref = ref, commit = repo.commit(dir, ref), path = path, text = text}
    end}
    host.document = {read = function()
        return {document = 1, revision = 7, format = "ass", lines = with_ids(ass.lines(current()))}
    end}
    host.marks = {
        clear = function() host.cleared = host.cleared + 1; host.set = {} end,
        set = function(list) host.set = list; return {marked = #list} end,
    }
    return host
end

if repo.available() then
    test("git: marks against a tag, a branch and HEAD in a generated repository", function()
        local dir = repo.create()
        local path = "ep01.ass"
        repo.write(dir, path, file(base()))
        repo.commit_all(dir, "First draft")
        repo.git(dir, "tag v1")
        local edited = base()
        edited[2].text = "Somebody left the gate open again."
        edited[3].start, edited[3]["end"] = 7250, 9250
        local moved = table.remove(edited, 5)
        table.insert(edited, 1, moved)
        table.insert(edited, 4, L(8000, "A gull lands on the railing."))
        table.remove(edited)
        repo.write(dir, path, file(edited))
        local host = host_for(dir, path, function() return repo.read(dir, path) end)

        local done = assert(compare.run(host, "v1", nil, t))
        eq({done.result.added, done.result.changed, done.result.removed}, {1, 3, 1}, "counts")
        local got = {}
        for _, m in ipairs(host.set) do got[m.line - 100] = m.colour .. " " .. m.tooltip end
        eq(got, {
            [1] = "warning Moved since v1",
            [3] = "warning Changed since v1: text",
            [4] = "success Added since v1",
            [5] = "warning Changed since v1: time",
            [6] = "danger 1 Line removed below since v1",
        })

        repo.commit_all(dir, "Second draft")
        local again = assert(compare.run(host, "HEAD", nil, t))
        eq(#again.marks, 0, "HEAD has no marks")
        eq(host.cleared, 2, "each run clears first")

        repo.git(dir, "branch first-draft v1")
        repo.git(dir, "checkout -q -b retime v1")
        local retimed = base()
        for _, l in ipairs(retimed) do l.start, l["end"] = l.start + 40, l["end"] + 40 end
        repo.write(dir, path, file(retimed))
        local all = assert(compare.run(host, "first-draft", nil, t))
        eq(all.result.changed, 6, "against the other branch")
        repo.remove(dir)
    end)

    test("git: a missing ref and a file not at that ref", function()
        local dir = repo.create()
        repo.write(dir, "a.ass", file(base()))
        repo.commit_all(dir, "First")
        local host = host_for(dir, "b.ass", function() return file(base()) end)
        local _, problem = compare.run(host, "HEAD", nil, t)
        eq(problem.state, "no_file")
        host = host_for(dir, "a.ass", function() return file(base()) end)
        _, problem = compare.run(host, "v9", nil, t)
        eq(problem.state, "no_ref")
        repo.remove(dir)
    end)
else
    failed[#failed + 1] = "git: not on PATH, so the repository tests could not run"
end

test("compare: the API's error reasons name the state", function()
    for _, reason in ipairs({"no_git", "no_repository", "unsafe_repository", "no_path", "no_file", "no_ref"}) do
        eq(compare.problem({code = "x", data = {reason = reason}}), reason)
    end
    eq(compare.problem({code = "not_granted", message = "no"}), "not_granted")
    eq(compare.problem({code = "unavailable", data = {reason = "something new"}}), "failed")
    eq(compare.problem(nil), "failed")
end)

test("compare: an SRT at the ref, and an SRT Document, are not ASS", function()
    local host = {
        vcs = {show = function() return "1\n00:00:01,000 --> 00:00:02,000\nHi\n", {} end},
        document = {read = function() return {document = 1, format = "ass", lines = {}} end},
    }
    local _, problem = compare.run(host, "HEAD", nil, t)
    eq(problem.state, "not_ass_at_ref")
    host.document.read = function() return {document = 1, format = "srt", lines = {}} end
    _, problem = compare.run(host, "HEAD", nil, t)
    eq(problem.state, "not_ass")
end)

test("marks: the panel's list names the change without the ref", function()
    local new = base()
    table.remove(new, 3)
    new[3].text = "We should have taken the late ferry."
    new[1].start = 1100
    with_ids(new)
    local entries = marks.entries(diff.compare(base(), new), new, t)
    eq(entries, {
        {line = 101, row = 1, colour = "warning", text = "Changed: time"},
        {line = 103, row = 3, colour = "danger", text = "Changed: text; 1 Line removed above"},
    })
end)


local function find(tree, id)
    if tree.id == id then return tree end
    for _, child in ipairs(tree.children or {}) do
        local hit = find(child, id)
        if hit then return hit end
    end
end

local function texts(tree, out)
    out = out or {}
    if tree.text then out[#out + 1] = tree.text end
    if tree.title then out[#out + 1] = tree.title end
    for _, child in ipairs(tree.children or {}) do texts(child, out) end
    return out
end

local REFS = {
    root = "/w", path = "ep01.ass", head = {ref = "main", commit = string.rep("a", 40)},
    branches = {
        {name = "typeset-pass", commit = "77d0b13" .. string.rep("0", 33), current = false},
        {name = "main", commit = "a41c9e2" .. string.rep("0", 33), current = true},
    },
    tags = {{name = "v1.0", commit = "3f2a1c9" .. string.rep("0", 33)}, {name = "tl-check", commit = "9be4410" .. string.rep("0", 33)}},
    commits = {
        {commit = "a41c9e2" .. string.rep("0", 33), summary = "Fix the ferry scene timing", author = "Kai", time = 1794560400},
        {commit = "3f2a1c9" .. string.rep("0", 33), summary = "First draft", author = "Mira", time = 1760227200},
    },
}

test("panel: dates without os.date", function()
    eq({panel.civil(0)}, {1970, 1, 1})
    eq({panel.civil(951782400)}, {2000, 2, 29})
    eq(panel.date(1760227200, 1794560400), "12 Oct 2025")
    eq(panel.date(1794560400, 1794560400), "13 Nov")
end)

test("panel: the picker puts the current branch first and collapses commits", function()
    local rows, selected = panel.refs_tree(REFS, "", "v1.0", t)
    eq(rows[1].text, "Branches")
    eq(rows[1].children[1].text, "main")
    eq(rows[1].children[1].detail, "current · a41c9e2 · 13 Nov")
    eq(rows[2].children[1].detail, "3f2a1c9 · 12 Oct 2025")
    eq(rows[3].text, "Recent commits (2)")
    eq(rows[3].expanded, false)
    eq(selected, "ref:v1.0")
end)

test("panel: search matches names, summaries and short hashes, and opens commits", function()
    local rows = panel.refs_tree(REFS, "FERRY", nil, t)
    eq(#rows, 1)
    eq(rows[1].children[1].id, "ref:" .. REFS.commits[1].commit)
    eq(rows[1].expanded, true)
    rows = panel.refs_tree(REFS, "9be44", nil, t)
    eq(rows[1].children[1].text, "tl-check")
end)

test("panel: nothing matching offers the typed text", function()
    local tree = panel.tree({title = "ep01.ass", refs = REFS, search = "HEAD~2"}, t)
    eq(find(tree, "refs"), nil)
    local all = table.concat(texts(tree), "|")
    eq(all:find("Press Enter to compare with it as typed", 1, true) ~= nil, true, all)
end)

test("panel: Compare waits for a pick", function()
    eq(find(panel.tree({title = "a.ass", refs = REFS}, t), "compare").disabled, true)
    eq(find(panel.tree({title = "a.ass", refs = REFS, picked = "main"}, t), "compare").disabled, false)
end)

test("panel: each problem says what helps", function()
    local function body(state, extra)
        local s = {title = "ep01.ass", ref = "v0.9", problem = {state = state}}
        for k, v in pairs(extra or {}) do s.problem[k] = v end
        return panel.tree(s, t)
    end
    local unsafe = body("unsafe_repository", {folder = "/srv/subs", command = "git config --global --add safe.directory /srv/subs"})
    eq(find(unsafe, "safe-command").value, "git config --global --add safe.directory /srv/subs")
    eq(find(unsafe, "reload") ~= nil, true)
    eq(find(body("no_path"), "save") ~= nil, true)
    eq(find(body("no_git"), "reload") ~= nil, true)
    for _, state in ipairs({"no_git", "no_repository", "unsafe_repository", "no_path", "no_file", "no_ref", "not_ass",
        "not_ass_at_ref", "timed_out", "too_large", "not_text", "not_granted", "failed"}) do
        for _, text in ipairs(texts(body(state))) do
            eq(text:find("problem%.") == nil, true, state .. " has no string: " .. text)
        end
    end
end)

test("panel: the picker stays for a file not at that ref", function()
    local tree = panel.tree({title = "ep01.ass", refs = REFS, picked = "v0.9", problem = {state = "no_file"}}, t)
    eq(find(tree, "refs") ~= nil, true)
    eq(table.concat(texts(tree), "|"):find("ep01.ass isn’t in", 1, true) ~= nil, true)
end)

test("panel: the result lists each marked Line", function()
    local new = base()
    new[2].text = "Somebody left the gate open again."
    with_ids(new)
    local result = diff.compare(base(), new)
    local entries = marks.entries(result, new, t)
    local tree = panel.tree({title = "ep01.ass", refs = REFS, picked = "v1.0", compared = "v1.0",
        done = {result = result, entries = entries, marks = entries, found = #entries, commit = REFS.tags[1].commit}}, t)
    local list = find(tree, "changes")
    eq(list.rows, {{id = "102", text = "Line 2", detail = "Changed: text"}})
    local all = table.concat(texts(tree), "|")
    eq(all:find("Compared with v1.0", 1, true) ~= nil, true, all)
    eq(all:find("3f2a1c9 · Lines marked: 1", 1, true) ~= nil, true, all)
end)

local timings = {}
test("timing: 5,000 Lines", function()
    local old = {}
    for n = 1, 5000 do
        old[n] = L(n * 1500, string.format("Line %d says something {\\i1}about the harbour%s", n,
            n % 7 == 0 and "." or "!"), {actor = n % 3 == 0 and "Mira" or "Kai"})
    end
    local edits = copy(old)
    for n = 50, 5000, 97 do edits[n].text = edits[n].text .. " Edited." end
    for n = 4900, 30, -211 do table.remove(edits, n) end
    for n = 70, 5000, 251 do table.insert(edits, n, L(n * 1500 + 700, "Inserted line " .. n)) end
    for n = 200, 4800, 600 do table.insert(edits, n + 300, table.remove(edits, n)) end
    with_ids(edits)
    local retimed = copy(old)
    for _, l in ipairs(retimed) do l.start, l["end"] = l.start + 80, l["end"] + 80 end
    with_ids(retimed)
    local reversed = {}
    for n = #old, 1, -1 do reversed[#reversed + 1] = old[n] end
    with_ids(reversed)
    local text = file(old)

    for _, case in ipairs({{"edited", edits}, {"retimed", retimed}, {"reversed", reversed}}) do
        local clock = os.clock()
        local parsed = ass.lines(text)
        local result = diff.compare(parsed, case[2])
        local list = marks.build(result, case[2], "v1.0", t)
        local ms = (os.clock() - clock) * 1000
        timings[#timings + 1] = string.format("%s %d ms (%d marks: %d added, %d changed, %d removed)", case[1], ms,
            #list, result.added, result.changed, result.removed)
        eq(ms < 3000, true, case[1] .. " took " .. ms .. " ms")
        if case[1] == "retimed" then eq({result.changed, result.added, result.removed}, {5000, 0, 0}) end
        if case[1] == "reversed" then eq({result.added, result.removed}, {0, 0}) end
    end
end)

for _, line in ipairs(timings) do print("timing: 5,000 Lines, " .. line) end
if #failed > 0 then
    for _, f in ipairs(failed) do io.stderr:write("FAIL ", f, "\n") end
    print(string.format("%d tests passed, %d failed", passed, #failed))
    os.exit(1)
end
print(string.format("%d tests passed", passed))

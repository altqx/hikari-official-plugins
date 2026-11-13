local M = {}

M.ID = "marks"

local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

function M.civil(seconds)
    local z = math.floor(seconds / 86400) + 719468
    local era = math.floor(z / 146097)
    local doe = z - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local day = doy - math.floor((153 * mp + 2) / 5) + 1
    local month = mp < 10 and mp + 3 or mp - 9
    local year = yoe + era * 400 + (month <= 2 and 1 or 0)
    return year, month, day
end

function M.date(seconds, newest)
    local year, month, day = M.civil(seconds)
    local thisYear = M.civil(newest or seconds)
    if year == thisYear then
        return string.format("%d %s", day, MONTHS[month])
    end
    return string.format("%d %s %d", day, MONTHS[month], year)
end

local function short(commit)
    return commit:sub(1, 7)
end

local function matches(search, ...)
    if search == "" then return true end
    for _, text in ipairs({...}) do
        if text and text:lower():find(search, 1, true) then return true end
    end
    return false
end

function M.refs_tree(refs, search, picked, t)
    search = (search or ""):lower()
    local newest = 0
    for _, c in ipairs(refs.commits) do newest = math.max(newest, c.time) end
    local times = {}
    for _, c in ipairs(refs.commits) do times[c.commit] = c.time end
    local function when(commit)
        return times[commit] and (" · " .. M.date(times[commit], newest)) or ""
    end

    local branches, tags, commits = {}, {}, {}
    local ordered = {}
    for _, b in ipairs(refs.branches) do
        if b.current then table.insert(ordered, 1, b) else ordered[#ordered + 1] = b end
    end
    for _, b in ipairs(ordered) do
        if matches(search, b.name, short(b.commit)) then
            branches[#branches + 1] = {id = "ref:" .. b.name, text = b.name,
                detail = (b.current and t("picker.current") .. " · " or "") .. short(b.commit) .. when(b.commit)}
        end
    end
    for _, tag in ipairs(refs.tags) do
        if matches(search, tag.name, short(tag.commit)) then
            tags[#tags + 1] = {id = "ref:" .. tag.name, text = tag.name, detail = short(tag.commit) .. when(tag.commit)}
        end
    end
    for _, c in ipairs(refs.commits) do
        if matches(search, c.summary, c.commit, c.author) then
            commits[#commits + 1] = {id = "ref:" .. c.commit, text = c.summary,
                detail = short(c.commit) .. " · " .. c.author .. " · " .. M.date(c.time, newest)}
        end
    end

    local rows = {}
    local function group(id, title, children, expanded)
        if #children > 0 then
            rows[#rows + 1] = {id = id, text = title, children = children, expanded = expanded}
        end
    end
    group("group:branches", t("picker.branches"), branches, true)
    group("group:tags", t("picker.tags"), tags, true)
    group("group:commits", t("picker.commits", #refs.commits), commits, search ~= "")
    local selected = picked and ("ref:" .. picked) or nil
    return rows, selected
end

local function legend(result, t)
    local items = {
        {"success", t("summary.added", result.added)},
        {"warning", t("summary.changed", result.changed)},
        {"danger", t("summary.removed", result.removed)},
    }
    local draw, x = {}, 0
    for _, item in ipairs(items) do
        draw[#draw + 1] = {op = "rect", x = x, y = 3, w = 4, h = 14, fill = item[1]}
        draw[#draw + 1] = {op = "text", x = x + 10, y = 15, text = item[2], fill = "text"}
        x = x + 18 + 7 * #item[2]
    end
    local spoken = {}
    for n, item in ipairs(items) do spoken[n] = item[2] end
    return {kind = "canvas", id = "legend", height = 20, draw = draw, name = t("summary.name"),
        description = table.concat(spoken, ", ")}
end

local function problem_body(state, t)
    local p = state.problem
    local s = p.state
    local name = state.title or ""
    local children = {
        {kind = "label", style = "heading", text = t("problem." .. s .. ".title", name, state.ref or "")},
        {kind = "label", style = "muted", wrap = true, text = t("problem." .. s .. ".body", name, state.ref or "",
            p.folder or "", p.message or "")},
    }
    if s == "unsafe_repository" then
        children[#children + 1] = {kind = "text_area", id = "safe-command", rows = 2,
            label = t("problem.unsafe_repository.command"), value = p.command or ""}
    end
    if s == "no_path" then
        children[#children + 1] = {kind = "button", id = "save", icon = "save", text = t("action.save")}
    elseif s ~= "no_file" and s ~= "no_ref" and s ~= "not_ass_at_ref" and s ~= "not_ass" then
        children[#children + 1] = {kind = "button", id = "reload", icon = "refresh", text = t("action.refresh")}
    end
    return {kind = "column", children = children}
end

local PICKER_STAYS = {no_file = true, no_ref = true, not_ass_at_ref = true, failed = true, timed_out = true,
    too_large = true, not_text = true}

function M.tree(state, t)
    local children = {
        {kind = "label", style = "muted", text = t("panel.compare_with", state.title or "")},
    }
    local p = state.problem
    if state.refs and not (p and not PICKER_STAYS[p.state]) then
        local rows, selected = M.refs_tree(state.refs, state.search, state.picked, t)
        children[#children + 1] = {kind = "text", id = "search", value = state.search or "",
            placeholder = t("picker.search"), name = t("picker.search")}
        if #rows == 0 and (state.search or "") ~= "" then
            children[#children + 1] = {kind = "empty", text = t("picker.typed", state.search)}
        else
            children[#children + 1] = {kind = "tree", id = "refs", rows = rows, selected = selected, height = 200,
                name = t("picker.name")}
        end
        children[#children + 1] = {kind = "row", children = {
            {kind = "button", id = "compare", text = t("action.compare"), style = "primary",
                disabled = not state.picked or state.busy == true},
            {kind = "label", text = "", grow = true},
            {kind = "icon_button", id = "refresh", icon = "refresh", name = t("action.refresh")},
            {kind = "icon_button", id = "clear", icon = "clear", name = t("action.clear")},
        }}
        children[#children + 1] = {kind = "check", id = "on-save", text = t("action.on_save"),
            value = state.onSave ~= false}
    end
    if state.busy then
        children[#children + 1] = {kind = "progress", text = t("panel.comparing", state.picked or "")}
    elseif p then
        children[#children + 1] = problem_body(state, t)
    elseif state.done then
        local d = state.done
        local rows = {}
        for n, e in ipairs(d.entries) do
            rows[n] = {id = tostring(e.line), text = t("list.line", e.row), detail = e.text}
        end
        children[#children + 1] = {kind = "group", title = t("summary.title", state.compared), children = {
            legend(d.result, t),
            {kind = "label", style = "small", text = t("summary.detail", short(d.commit), #d.entries)},
        }}
        if d.found > #d.marks then
            children[#children + 1] = {kind = "label", style = "small", wrap = true,
                text = t("summary.capped", #d.marks, d.found)}
        end
        if #rows > 0 then
            children[#children + 1] = {kind = "list", id = "changes", rows = rows, grow = true, name = t("list.name")}
        else
            children[#children + 1] = {kind = "empty", text = t("summary.none", state.compared)}
        end
    elseif state.refs then
        children[#children + 1] = {kind = "empty", text = t("panel.pick")}
    end
    return {kind = "column", children = children}
end

return M

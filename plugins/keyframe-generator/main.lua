local scan = require("keyframes.scan")
local view = require("keyframes.view")

local PANEL = "keyframes"

local state = {video = false, busy = false}

local function settings()
    return {sensitivity = hikari.settings.get("sensitivity"), minGap = hikari.settings.get("min-gap")}
end

local function render()
    hikari.panels.render(PANEL, view.tree(state, settings()))
end

local function refresh()
    state.video = scan.video(hikari.call) ~= nil
    render()
end

local function find()
    state.busy, state.note, state.applied = true, nil, nil
    state.video = true
    render()
    local result = scan.run(hikari.call, hikari.job, settings())
    state.busy = false
    if result.status == "found" then
        state.result = result
    elseif result.status == "cancelled" then
        state.note = {text = "Cancelled at frame " .. scan.formatCount(result.at) .. " of "
            .. scan.formatCount(result.frames) .. ". Nothing was changed.", style = "muted"}
    elseif result.status == "novideo" then
        state.video = false
    else
        state.note = {text = "Couldn’t finish: " .. result.message}
    end
    render()
end

local function begin()
    return hikari.job.begin{title = "Finding keyframes"}
end

local function stillTheVideo()
    if scan.sameVideo(hikari.call, state.result.video) then
        return true
    end
    state.result, state.applied = nil, nil
    state.note = {text = "The open video changed since the scan. Find keyframes again."}
    refresh()
    return false
end

local function setKeyframes(file)
    local done, err = hikari.call("video.set_keyframes", {frames = hikari.array(state.result.keyframes), file = file})
    if not done then
        hikari.notify("Couldn’t set the keyframes: " .. tostring(err and err.message), "error")
        return false
    end
    return true
end

local actions = {}

function actions.find()
    if not begin() then
        hikari.notify("Run Automation › Keyframe generator › Find keyframes: this HikariSub can’t scan from the panel.",
                      "warning")
        return
    end
    find()
end

function actions.set()
    if state.result and stillTheVideo() and setKeyframes(nil) then
        state.applied = {}
        render()
    end
end

function actions.save()
    if not (state.result and stillTheVideo()) then
        return
    end
    local picked = hikari.files.pick{title = "Save keyframes", save = true, name = "keyframes.txt",
                                     filters = {{name = "Keyframes", patterns = {"*.txt"}}}}
    if picked and setKeyframes(picked.file) then
        state.applied = {saved = picked.name}
        render()
    end
end

hikari.panels.on(PANEL, function(e)
    if e.kind == "show" then
        refresh()
    elseif e.kind == "change" and e.widget == "sensitivity" then
        hikari.settings.set("sensitivity", math.floor(e.value + 0.5))
    elseif e.kind == "change" and e.widget == "min-gap" then
        hikari.settings.set("min-gap", math.floor(e.value + 0.5))
    elseif e.kind == "click" and actions[e.widget] then
        actions[e.widget]()
    end
end)

hikari.commands.register("scan", function()
    hikari.panels.show(PANEL)
    begin()
    find()
end)

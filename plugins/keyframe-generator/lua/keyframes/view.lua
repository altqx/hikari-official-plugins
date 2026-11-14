local scan = require("keyframes.scan")

local view = {}

local function controls(settings, off)
    return {
        {kind = "slider", id = "sensitivity", label = "Sensitivity", value = settings.sensitivity,
         minimum = 0, maximum = 100, step = 1, disabled = off,
         tooltip = "Higher finds more cuts, lower only the clearest."},
        {kind = "row", children = {
            {kind = "label", text = "Fewer cuts", style = "small", grow = true},
            {kind = "label", text = "More cuts", style = "small"},
        }},
        {kind = "number", id = "min-gap", label = "Minimum gap", value = settings.minGap, minimum = 1,
         maximum = 1000, step = 1, unit = "frames", disabled = off},
    }
end

local function shotLength(result)
    local count = #result.keyframes
    if count == 0 then
        return nil
    end
    if result.duration then
        return string.format("a shot every %.1f s on average", result.duration / count / 1000)
    end
    return string.format("a shot every %d frames on average", math.floor(result.frames / count + 0.5))
end

local function summary(result, applied)
    local count = #result.keyframes
    local title = count == 1 and "Found 1 keyframe" or ("Found " .. scan.formatCount(count) .. " keyframes")
    local children = {}
    if applied then
        local text = applied.saved and ("The video’s keyframes now. Saved as " .. applied.saved .. ".")
            or "The video’s keyframes now."
        children[#children + 1] = {kind = "label", text = text, wrap = true}
    else
        local detail = "In " .. scan.formatCount(result.frames) .. " frames"
        local shots = shotLength(result)
        children[#children + 1] = {kind = "label", style = "muted", wrap = true,
                                   text = shots and (detail .. ": " .. shots .. ".") or (detail .. ".")}
        children[#children + 1] = {kind = "label", style = "small", wrap = true,
                                   text = "Sensitivity " .. result.sensitivity .. " · minimum gap "
                                       .. result.minGap .. (result.minGap == 1 and " frame" or " frames")}
    end
    children[#children + 1] = {kind = "row", children = {
        {kind = "button", id = "set", text = "Set keyframes", style = "primary", disabled = applied ~= nil},
        {kind = "button", id = "save", text = "Save as keyframes file…"},
    }}
    return {kind = "group", title = title, children = children}
end

-- state: {video, busy, result, applied, note}; settings: {sensitivity, minGap}
function view.tree(state, settings)
    local children = {}
    if not state.video then
        children[#children + 1] = {kind = "empty", text = "Open a video to find its keyframes."}
    end
    local off = state.busy or not state.video
    for _, widget in ipairs(controls(settings, off)) do
        children[#children + 1] = widget
    end
    local again = state.result ~= nil and not state.busy
    children[#children + 1] = {kind = "row", children = {
        {kind = "button", id = "find", text = again and "Find keyframes again" or "Find keyframes",
         style = again and "normal" or "primary", disabled = off},
    }}
    if state.busy then
        children[#children + 1] = {kind = "label", style = "muted", wrap = true,
                                   text = "Finding keyframes… Cancel it in the card above the status bar."}
    elseif not state.result and state.video and not state.note then
        children[#children + 1] = {kind = "label", style = "small", wrap = true,
                                   text = "Reads every frame of the open video. Keyframes you have now stay until you set the new ones."}
    end
    if state.note then
        children[#children + 1] = {kind = "label", style = state.note.style or "body", wrap = true,
                                   text = state.note.text}
    end
    if state.result and not state.busy then
        children[#children + 1] = summary(state.result, state.applied)
    end
    return {kind = "column", children = children}
end

return view

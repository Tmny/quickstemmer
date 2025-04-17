local ctx = reaper.ImGui_CreateContext('Stem Export Tool')
local visible = true
local lastExportFolder = nil

-- Generic Track State Manager
local TrackStateManager = {
    savedStates = {}
}

function TrackStateManager:save(track, properties)
    if not self.savedStates[track] then self.savedStates[track] = {} end

    for _, prop in ipairs(properties) do
        if prop:sub(1, 2) == "P_" then -- string property
            local _, val = reaper.GetSetMediaTrackInfo_String(track, prop, "", false)
            self.savedStates[track][prop] = val
        else -- numeric property
            self.savedStates[track][prop] = reaper.GetMediaTrackInfo_Value(track, prop)
        end
    end
end

function TrackStateManager:restore()
    for track, props in pairs(self.savedStates) do
        for prop, val in pairs(props) do
            if prop:sub(1, 2) == "P_" then
                reaper.GetSetMediaTrackInfo_String(track, prop, val, true)
            else
                reaper.SetMediaTrackInfo_Value(track, prop, val)
            end
        end
    end
end


local function getDateTimeString()
    return os.date("%Y-%m-%d_%H-%M-%S")
end

local function hasMediaItems(track)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        if reaper.GetMediaItemInfo_Value(item, "D_LENGTH") > 0 then
            return true
        end
    end
    return false
end

local function prepareTracks(trackCount, includeMuted)
    local prefixLevels = { [0] = 1 }
    local currentDepth = 0

    TrackStateManager.savedStates = {} -- Clear old state

    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local _, origName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local isMuted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
        local folderDepthChange = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        if (includeMuted or isMuted == 0) and hasMediaItems(track) then
            reaper.SetTrackSelected(track, true)

            -- Save current state
            TrackStateManager:save(track, { "B_MUTE", "P_NAME" })

            -- Temporarily unmute if needed
            if isMuted == 1 then
                reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
            end

            local prefix = table.concat((function()
                local parts = {}
                for d = 0, currentDepth do
                    table.insert(parts, string.format("%02d", prefixLevels[d]))
                end
                return parts
            end)(), "-")

            reaper.GetSetMediaTrackInfo_String(track, "P_NAME", prefix .. " " .. origName, true)

            for d = currentDepth + 1, #prefixLevels do
                prefixLevels[d] = nil
            end
        end

        if folderDepthChange == 1 then
            currentDepth = currentDepth + 1
            prefixLevels[currentDepth] = 1
        elseif folderDepthChange < 0 then
            for d = currentDepth - folderDepthChange, #prefixLevels do
                prefixLevels[d] = nil
            end
            currentDepth = currentDepth - math.abs(folderDepthChange)
            prefixLevels[currentDepth] = (prefixLevels[currentDepth] or 0) + 1
        elseif folderDepthChange == 0 then
            prefixLevels[currentDepth] = prefixLevels[currentDepth] + 1
        end
    end
end


local function checkTracksSelected(trackCount)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.IsTrackSelected(track) then return true end
    end
    return false
end

local function getProjectDirectory()
    local _, projPathWithName = reaper.EnumProjects(-1, "")
    return projPathWithName:match("^(.*)[\\/][^\\/]-%.rpp$")
end

local function getMaxEndTime()
    local maxEnd = 0
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        for j = 0, reaper.CountTrackMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            local endTime = reaper.GetMediaItemInfo_Value(item, "D_POSITION") + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            maxEnd = math.max(maxEnd, endTime)
        end
    end
    return maxEnd
end

local function renderStems(stemsFolder)
    local maxEndTime = getMaxEndTime()
    reaper.GetSet_LoopTimeRange(true, false, 0, maxEndTime, false)
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", stemsFolder, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$track", true)
    reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 3, true)
    reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
    reaper.GetSetProjectInfo(0, "RENDER_SRATE_USE", 0, true)
    reaper.Main_OnCommand(42230, 0) -- Render quietly
end

local function restoreOriginalNames()
    TrackStateManager:restore()
end

local function getSortedStemFiles(folder)
    local p = io.popen('dir "' .. folder .. '" /b /a-d')
    local files = {}
    for file in p:lines() do
        if file:match("%.wav$") then table.insert(files, file) end
    end
    p:close()

    table.sort(files, function(a, b)
        local aparts = { a:match("^(%d+)-?(%d*)-?(%d*)") }
        local bparts = { b:match("^(%d+)-?(%d*)-?(%d*)") }
        for i = 1, 3 do
            local anum, bnum = tonumber(aparts[i]) or 0, tonumber(bparts[i]) or 0
            if anum ~= bnum then return anum < bnum end
        end
        return a < b
    end)

    return files
end

local function importStemsWithNesting(folder, stemFiles)
    local depthStack = {}
    local prevDepth = 0

    for i, file in ipairs(stemFiles) do
        local path = folder .. "/" .. file
        local prefix = file:match("^(%d[%d%-]*)[%s%-]")
        local depth = 0
        if prefix then for _ in prefix:gmatch("%d+") do depth = depth + 1 end end

        reaper.Main_OnCommand(40297, 0)
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local idx = reaper.CountTracks(0) - 1
        local track = reaper.GetTrack(0, idx)

        local name = file:match("^%d[%d%-]*[%- ]+(.+)%..+$") or file:gsub("%.wav$", "")
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)

        reaper.SetEditCurPos(0, false, false)
        reaper.SetOnlyTrackSelected(track)
        reaper.InsertMedia(path, 0)

        if i > 1 then
            if depth > prevDepth then
                local lastTrack = reaper.GetTrack(0, idx - 1)
                reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", 1)
                reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
                table.insert(depthStack, lastTrack)
            elseif depth < prevDepth then
                local lastTrack = reaper.GetTrack(0, idx - 1)
                reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", depth - prevDepth)
            end
        end
        prevDepth = depth
    end
end

--main function
local function runStemExporter(includeMuted)
    reaper.Main_OnCommand(40026, 0) -- Save
    reaper.Main_OnCommand(40297, 0) -- Unselect all

    local trackCount = reaper.CountTracks(0)
    if trackCount == 0 then
        reaper.ShowMessageBox("No tracks found!", "Error", 0)
        return
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local originalNames = prepareTracks(trackCount, includeMuted)

    if not checkTracksSelected(trackCount) then
        reaper.ShowMessageBox("No suitable tracks found.", "Error", 0)
        reaper.PreventUIRefresh(-1)
        reaper.Undo_EndBlock("Stem Export", -1)
        return
    end

    local projectDir = getProjectDirectory()
    if not projectDir then
        reaper.ShowMessageBox("Please save your project first.", "Export Error", 0)
        return
    end

    local dateTime = getDateTimeString()
    local stemsFolder = projectDir .. "/Stems/" .. dateTime
    lastExportFolder = stemsFolder

    os.execute('mkdir "' .. stemsFolder .. '"')

    renderStems(stemsFolder)
    restoreOriginalNames(originalNames)

    reaper.Main_OnCommand(40859, 0) -- New project

    local files = getSortedStemFiles(stemsFolder)
    importStemsWithNesting(stemsFolder, files)

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Stem Export", -1)
    --reaper.ShowConsoleMsg("✅ Stems imported into new project with hierarchy.\n")
end



--util
local function openInExplorer(path)
    local osName = reaper.GetOS()
    if osName:match("Win") then
        os.execute('start "" "' .. path .. '"')
    elseif osName:match("OSX") then
        os.execute('open "' .. path .. '"')
    else -- Linux
        os.execute('xdg-open "' .. path .. '"')
    end
end

local function cleanUpStemFilenames(folder)
    local p = io.popen('dir "' .. folder .. '" /b /a-d')
    for file in p:lines() do
        if file:match("%.wav$") then
            local cleanName = file:gsub("^%d[%d%-]*[%s%-]+", ""):gsub("%.wav$", "")
            if cleanName ~= file then
                local oldPath = folder .. "/" .. file
                local newPath = folder .. "/" .. cleanName .. ".wav"
                os.rename(oldPath, newPath)
            end
        end
    end
    p:close()
end

--Filter in GUI
local includeMuted = false -- default off

-- GUI Loop
function loop()
    if not visible then return end
    reaper.ImGui_SetNextWindowSize(ctx, 300, 150, reaper.ImGui_Cond_FirstUseEver())
    local rv
    rv, visible = reaper.ImGui_Begin(ctx, "Quickstem", true)
    if rv then
        reaper.ImGui_Text(ctx, "Export stems with hierarchy:")
        _, includeMuted = reaper.ImGui_Checkbox(ctx, "Include muted tracks", includeMuted)
        if reaper.ImGui_Button(ctx, 'Run Stem Export') then
            runStemExporter(includeMuted)
        end
        if lastExportFolder then
            if reaper.ImGui_Button(ctx, 'Open Stem Folder') then
                openInExplorer(lastExportFolder)
            end
            if reaper.ImGui_Button(ctx, 'Remove Prefixes in last Stem Folder') then
                cleanUpStemFilenames(lastExportFolder)
            end
        end
        
        reaper.ImGui_End(ctx)
    end
    reaper.defer(loop)
end

reaper.defer(loop)




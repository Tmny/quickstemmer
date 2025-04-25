local ctx = reaper.ImGui_CreateContext('Stem Export Tool')
local visible = true
local lastExportFolder = nil
local safeSeparator = "__"


--==============================================================
--###################### UTILITY FUNCTIONS #####################
--==============================================================

-- Splits strings by a delimiter
function string.split(s, delimiter)
    local result = {}
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match) 
    end
    return result
end

-- Check if a track has media items
local function hasMediaItems(track)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        if reaper.GetMediaItemInfo_Value(item, "D_LENGTH") > 0 then
            return true
        end
    end
    return false
end

-- Returns the current date and time as a string
local function getDateTimeString()
    return os.date("%Y-%m-%d_%H-%M-%S")
end

-- Checks if any track is selected
local function checkTracksSelected(trackCount)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.IsTrackSelected(track) then return true end
    end
    return false
end

-- Gets the directory of the current project
local function getProjectDirectory()
    local proj = reaper.EnumProjects(-1, "")
    return reaper.GetProjectPathEx(proj)
end


-- Finds the maximum end time across all media items
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

-- Opens a given path in the file explorer
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

-- Removes prefixes from stem filenames
local function cleanUpStemFilenames(folder)
    local p = io.popen('dir "' .. folder .. '" /b /a-d')
    for file in p:lines() do
        if file:match("%.wav$") then
            local cleanName = file:gsub("^%d[%d%-]*__%s*", ""):gsub("%.wav$", "")
            if cleanName ~= file then
                local oldPath = folder .. "/" .. file
                local newPath = folder .. "/" .. cleanName .. ".wav"
                os.rename(oldPath, newPath)
            end
        end
    end
    p:close()
end

--==============================================================
--##################### TRACK STATE MANAGER ####################
--==============================================================

local TrackStateManager = {
    savedStates = {}
}

function TrackStateManager:save(track, properties)
    if not self.savedStates[track] then self.savedStates[track] = {} end
    for _, prop in ipairs(properties) do
        if prop:sub(1, 2) == "P_" then
            local _, val = reaper.GetSetMediaTrackInfo_String(track, prop, "", false)
            self.savedStates[track][prop] = val
        else
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

function TrackStateManager:flattenHierarchy(trackCount)
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        self:save(track, { "I_FOLDERDEPTH" }) -- Save original
        reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0) -- Flatten
    end
end


function TrackStateManager.prepareTracks(self, trackCount, includeMuted, safeSeparator)
    reaper.ShowConsoleMsg("includeMuted (actual value): " .. tostring(includeMuted) .. "\n")

    local prefixLevels = { [0] = 1 }
    local currentDepth = 0
    local pendingFolderDepth = 0
    self.savedStates = {}

    reaper.ShowConsoleMsg("Starting for loop ---------------\n")

    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local _, origName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local isMuted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
        local includeThisTrack = includeMuted or isMuted == 0
        local folderDepthChange = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")

        reaper.ShowConsoleMsg("Track: " .. origName .. ", Include: " .. tostring(includeThisTrack) .. ", Has Media Items: " .. tostring(hasMediaItems(track)) .. "\n")


        if pendingFolderDepth ~= 0 then
            currentDepth = math.max(0, currentDepth + pendingFolderDepth)
            for d = currentDepth + 1, #prefixLevels do
                prefixLevels[d] = nil
            end
            pendingFolderDepth = 0
        end

        if includeThisTrack and hasMediaItems(track) then
            reaper.SetTrackSelected(track, true)
            self:save(track, { "B_MUTE", "P_NAME", "I_FOLDERDEPTH" })
            if isMuted == 1 then
                reaper.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
            end

            local prefix = table.concat((function()
                local parts = {}
                for d = 0, currentDepth do
                    table.insert(parts, string.format("%02d", prefixLevels[d] or 1))
                end
                return parts
            end)(), "-")

            reaper.GetSetMediaTrackInfo_String(track, "P_NAME", prefix .. safeSeparator .. origName, true)
            for d = currentDepth + 1, #prefixLevels do
                prefixLevels[d] = nil
            end
        end

        if includeThisTrack then
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
                prefixLevels[currentDepth] = (prefixLevels[currentDepth] or 0) + 1
            end
        else
            pendingFolderDepth = pendingFolderDepth + folderDepthChange
        end
    end

    reaper.ShowConsoleMsg("Ending for loop ---------------\n")
end

--==============================================================
--##################### STEM EXPORT FUNCTIONS ##################
--==============================================================

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

local function getSortedStemFiles(folder)
    local p = io.popen('dir "' .. folder .. '" /b /a-d')
    local files = {}
    for file in p:lines() do
        if file:match("%.wav$") then table.insert(files, file) end
    end
    p:close()

    table.sort(files, function(a, b)
        local aparts = { a:match("^(%d+[%d%-]*)(__.*)$") }
        local bparts = { b:match("^(%d+[%d%-]*)(__.*)$") }

        aparts = aparts[1] and aparts[1]:split('-') or {}
        bparts = bparts[1] and bparts[1]:split('-') or {}

        for i = 1, math.min(#aparts, #bparts) do
            local anum, bnum = tonumber(aparts[i]) or 0, tonumber(bparts[i]) or 0
            if anum ~= bnum then return anum < bnum end
        end
        return #aparts < #bparts
    end)

    return files
end

local function importStemsWithNesting(folder, stemFiles)
    local depthStack = {}
    local prevPrefix = ""
    local prevDepth = 0

    reaper.ShowConsoleMsg("----- Importing stems with nesting -----\n")

    for i, file in ipairs(stemFiles) do
        local path = folder .. "/" .. file
        local prefix = file:match("^(%d[%d%-]*)__")
        local depth = 0
        if prefix then
            for _ in prefix:gmatch("%d+") do depth = depth + 1 end
        end

        reaper.ShowConsoleMsg(string.format("\n[%d] File: %s\n", i, file))
        reaper.ShowConsoleMsg("Prefix: " .. tostring(prefix) .. "\n")
        reaper.ShowConsoleMsg("Calculated Depth: " .. tostring(depth) .. "\n")

        -- Create track
        reaper.Main_OnCommand(40297, 0)
        reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
        local idx = reaper.CountTracks(0) - 1
        local track = reaper.GetTrack(0, idx)

        local name = file:match("^%d[%d%-]*__%s*(.+)%..+$") or file:gsub("%.wav$", "")
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)

        reaper.SetEditCurPos(0, false, false)
        reaper.SetOnlyTrackSelected(track)
        reaper.InsertMedia(path, 0)

        -- Logic to validate nesting
        local function isValidChild(childPrefix, parentPrefix)
            return parentPrefix ~= "" and childPrefix:sub(1, #parentPrefix) == parentPrefix
        end

        if i > 1 then
            if depth > prevDepth and isValidChild(prefix, prevPrefix) then
                -- Valid nesting under previous track
                local lastTrack = reaper.GetTrack(0, idx - 1)
                reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", 1)
                reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
                table.insert(depthStack, lastTrack)
                reaper.ShowConsoleMsg("↑ Increased depth & valid prefix match: Set folder start\n")
            elseif depth < prevDepth then
                local lastTrack = reaper.GetTrack(0, idx - 1)
                local folderDepthChange = depth - prevDepth
                reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", folderDepthChange)
                reaper.ShowConsoleMsg("↓ Decreased depth: Set folder close depth " .. folderDepthChange .. "\n")
            else
                reaper.ShowConsoleMsg("→ Same depth or invalid nesting: no folder structure change\n")
            end
        else
            reaper.ShowConsoleMsg("First track, no nesting applied\n")
        end

        prevDepth = depth
        prevPrefix = prefix or ""
    end

    reaper.ShowConsoleMsg("----- Done importing stems -----\n")
end

--==============================================================
--########################## MAIN ##############################
--==============================================================

local function runStemExporter(includeMuted, sumToBus)
    reaper.ClearConsole()
    reaper.Main_OnCommand(40026, 0) -- Save
    reaper.Main_OnCommand(40297, 0) -- Unselect all

    local trackCount = reaper.CountTracks(0)
    if trackCount == 0 then
        reaper.ShowMessageBox("No tracks found!", "Error", 0)
        return
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    TrackStateManager:prepareTracks(trackCount, includeMuted, safeSeparator)

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

    -- Conditionally flatten or keep bus based on the "Sum to Bus" filter
    reaper.ShowConsoleMsg("\nsumToBus: " .. tostring(sumToBus) .. "\n")
    if not sumToBus then
        TrackStateManager:flattenHierarchy(trackCount)
    end
    renderStems(stemsFolder)
    TrackStateManager:restore()

    reaper.Main_OnCommand(40859, 0) -- New project

    local files = getSortedStemFiles(stemsFolder)
    importStemsWithNesting(stemsFolder, files)

    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Stem Export", -1)
end



--==============================================================
--########################## GUI ###############################
--==============================================================
-- Filter in GUI
local includeMuted = false -- default off
local sumToBus = false -- default off for Sum to Bus


-- GUI Loop
function loop()
    if not visible then return end
    reaper.ImGui_SetNextWindowSize(ctx, 500, 300, reaper.ImGui_Cond_FirstUseEver())
    local rv
    rv, visible = reaper.ImGui_Begin(ctx, "Quickstemmer", true)
    if rv then
        -- Column 1 Width
        local columnWidth = 200

        -- Start creating the two columns layout manually
        -- Column 1 (Include checkboxes)
        reaper.ImGui_PushFont(ctx, fontBold)
        reaper.ImGui_Text(ctx, "Include:")
        reaper.ImGui_PopFont(ctx)
        _, includeMuted = reaper.ImGui_Checkbox(ctx, "Muted Tracks", includeMuted)

        -- Start second column (Other configurations)
        reaper.ImGui_SameLine(ctx, columnWidth)  -- Move to the same line at columnWidth distance
        
        -- Add "Configuration" Heading
        reaper.ImGui_PushFont(ctx, fontBold)
        reaper.ImGui_Text(ctx, "Configuration")
        reaper.ImGui_PopFont(ctx)

        -- Sum to Bus Checkbox
        _, sumToBus = reaper.ImGui_Checkbox(ctx, "Sum to Bus", sumToBus)

        -- Run Button
        if reaper.ImGui_Button(ctx, 'RUN') then
            runStemExporter(includeMuted, sumToBus)  -- Pass updated values explicitly
        end

        reaper.ImGui_Dummy(ctx, 0, 10)  -- width = 0, height = 10 pixels
        
        -- Column 2 (Last export path and folder options)
        reaper.ImGui_SameLine(ctx, columnWidth)  -- Move to the same line at columnWidth distance
        
        -- Display the last export path with an editable text input field
        reaper.ImGui_Text(ctx, "Last Export Path:")
        local pathBuffer = lastExportFolder or ""
        _, pathBuffer = reaper.ImGui_InputText(ctx, "##ExportPath", pathBuffer, 200)
        lastExportFolder = pathBuffer  -- Update the variable with the edited text

        -- Show buttons only if path is valid
        local function folderExists(path)
            local info = reaper.EnumerateFiles(path, 0) or reaper.EnumerateSubdirectories(path, 0)
            return info ~= nil
        end

        if lastExportFolder and lastExportFolder ~= "" and folderExists(lastExportFolder) then
            if reaper.ImGui_Button(ctx, "Open") then
                openInExplorer(lastExportFolder)
            end

            reaper.ImGui_SameLine(ctx)

            if reaper.ImGui_Button(ctx, "Remove Prefixes in last Stem Folder") then
                cleanUpStemFilenames(lastExportFolder)
            end
        end
        
        reaper.ImGui_End(ctx)
    end

    reaper.defer(loop)
end






reaper.defer(loop)





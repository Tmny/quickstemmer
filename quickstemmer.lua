local ctx = reaper.ImGui_CreateContext('Stem Export Tool') -- window title
local visible = true

-- Put your entire stem-export code into a function
local function runStemExporter()
    reaper.ShowConsoleMsg("������ Running stem exporter...\n")
    -- Save current project path
    local originalProject = reaper.GetProjectPath("")
    local originalProjTab = reaper.EnumProjects(-1, "")
    
    -- Get current date and time
    local function getDateTimeString()
        return os.date("%Y-%m-%d_%H-%M-%S")
    end
    
    -- Step 1: Save the project (prompts if unsaved)
    reaper.Main_OnCommand(40026, 0) -- File: Save project
    
    -- Step 2: Unselect all tracks
    reaper.Main_OnCommand(40297, 0) -- Track: Unselect all tracks
    
    -- Step 3: Get total track count safely
    local trackCount = reaper.CountTracks(0)
    if not trackCount or trackCount == 0 then
        reaper.ShowMessageBox("No tracks found in the project!", "Error", 0)
        return
    end
    
    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)
    
    local trackCount = reaper.CountTracks(0)
    reaper.Main_OnCommand(40297, 0) -- Unselect all
    
    local prefixLevels = {}
    local currentDepth = 0
    prefixLevels[currentDepth] = 1
    local originalNames = {}
    
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)
        local _, origName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
        local isMuted = reaper.GetMediaTrackInfo_Value(track, "B_MUTE")
        local folderDepthChange = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    
        reaper.ShowConsoleMsg("loop start: " ..  origName .. " folderDepthChange: " .. folderDepthChange .. ": Current Depth: " .. currentDepth .. ", currentPrefixLevel: " .. prefixLevels[currentDepth] .. "\n")
        
        if isMuted == 0 then
            local hasMediaItems = false
            local numItems = reaper.CountTrackMediaItems(track)
            for j = 0, numItems - 1 do
                local item = reaper.GetTrackMediaItem(track, j)
                if reaper.GetMediaItemInfo_Value(item, "D_LENGTH") > 0 then
                    hasMediaItems = true
                    break
                end
            end
    
            if hasMediaItems then
                reaper.SetTrackSelected(track, true)
    
                -- Store original track name
                originalNames[track] = origName
    
                -- Build prefix based on prefixLevels
                local prefixParts = {}
                for d = 0, currentDepth do
                    reaper.ShowConsoleMsg(" - prefix level of: " .. d .. " : " .. prefixLevels[d])
                    if prefixLevels[d] then
                        table.insert(prefixParts, string.format("%02d", prefixLevels[d]))
                    end
                end
                reaper.ShowConsoleMsg("\n")
                local prefix = table.concat(prefixParts, "-")
    
                -- Temporarily rename the track with the prefix
                reaper.GetSetMediaTrackInfo_String(track, "P_NAME", prefix .. " " .. origName, true)
    
                for d = currentDepth + 1, #prefixLevels do
                    prefixLevels[d] = nil
                end
            end
        end
    
        -- Handle folder depth change (going to a child folder)
        if folderDepthChange == 1 then
            -- Before going deeper, reset prefixLevels for the next child
            currentDepth = currentDepth + 1
            if not prefixLevels[currentDepth] then
                prefixLevels[currentDepth] = 1 -- The first child folder should start at 1
            end
        
        elseif folderDepthChange < 0 then
            for d = currentDepth - folderDepthChange, #prefixLevels do
                prefixLevels[d] = nil
            end
            reaper.ShowConsoleMsg("current Depth: " .. currentDepth .. "\n")
            reaper.ShowConsoleMsg("folder Depth Change: " .. folderDepthChange .. "\n")
            currentDepth = currentDepth - math.abs(folderDepthChange)
            prefixLevels[currentDepth] = prefixLevels[currentDepth] + 1
            reaper.ShowConsoleMsg("currentDepth reduced to " .. currentDepth)
        
            -- Increment for the next sibling track and clear lower levels
        elseif folderDepthChange == 0 then
            prefixLevels[currentDepth] = prefixLevels[currentDepth] + 1
        end
    end
    
    
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock("Temporarily prefix track names", -1)
    
    
    -- Step 5: Get current project path correctly (remove .rpp from string)
    local projIdx, projPathWithName = reaper.EnumProjects(-1, "")
    local projectDir = projPathWithName:match("^(.*)[\\/][^\\/]-%.rpp$")
    if not projPathWithName:match("%.rpp$") then
        reaper.ShowMessageBox("Please save your project before exporting stems.", "Export Error", 0)
        return
    end
    
    local projectDir = projPathWithName:match("^(.*)[\\/][^\\/]-%.rpp$")
    if not projectDir then
        reaper.ShowMessageBox("Could not determine project directory.", "Export Error", 0)
        return
    end
    
    local dateTime = getDateTimeString()
    local stemsFolder = projectDir .. "/Stems/" .. dateTime
    
    
    -- Create the "Stems" folder if it doesn't exist
    os.execute('mkdir "' .. stemsFolder .. '"')
    
    -- Step 6: Calculate full project length by checking the end of all items
    local maxEndTime = 0
    local numTracks = reaper.CountTracks(0)
    
    for i = 0, numTracks - 1 do
        local track = reaper.GetTrack(0, i)
        local numItems = reaper.CountTrackMediaItems(track)
    
        for j = 0, numItems - 1 do
            local item = reaper.GetTrackMediaItem(track, j)
            local itemEnd = reaper.GetMediaItemInfo_Value(item, "D_POSITION") +
                            reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
            if itemEnd > maxEndTime then
                maxEndTime = itemEnd
            end
        end
    end
    
    -- Set time selection from 0 to max project length
    reaper.GetSet_LoopTimeRange(true, false, 0, maxEndTime, false)
    
    -- Set render bounds to "time selection"
    reaper.GetSetProjectInfo(0, "RENDER_BOUNDSFLAG", 1, true)
    
    -- Set up render output directory and filename pattern
    reaper.GetSetProjectInfo_String(0, "RENDER_FILE", stemsFolder, true)
    reaper.GetSetProjectInfo_String(0, "RENDER_PATTERN", "$track", true)
    
    -- Set render mode to "Stems (selected tracks)", post-fader (no FX)
    reaper.GetSetProjectInfo(0, "RENDER_SETTINGS", 3, true)
    
    -- Format: stereo, use project sample rate
    reaper.GetSetProjectInfo(0, "RENDER_CHANNELS", 2, true)
    reaper.GetSetProjectInfo(0, "RENDER_SRATE_USE", 0, true)
    
    -- Silent render to disk (obeys render settings)
    reaper.Main_OnCommand(42230, 0) -- File: Render project, using the most recent render settings, quietly
    
    
    -- ⏪ Restore original track names after render
    for track, name in pairs(originalNames) do
        reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
    end
    
    
    
    
    
    
    
    
    
    
    
    
    --IMPORT TO NEW PROJECT
    -- Step 1: Create a new project
    reaper.Main_OnCommand(40859, 0)  -- New project (Ctrl + N)
    
    -- Step 2: Get all stem files from the folder and sort them by prefix
    local function getSortedStemFiles(folder)
        local stemFiles = {}
    
        -- Open folder and find all .wav files (adjust based on render format)
        local p = io.popen('dir "' .. folder .. '" /b /a-d')
        local files = p:lines()
        for file in files do
            if file:match("%.wav$") then  -- You can adjust this if you use another format (e.g., .aif, .flac)
                reaper.ShowConsoleMsg(file .. ",\n")
                table.insert(stemFiles, file)
            end
        end
        p:close()
    
        -- Sort the files based on the prefix (numeric order)
        table.sort(stemFiles, function(a, b)
            local aparts = { a:match("^(%d+)-?(%d*)-?(%d*)") }
            local bparts = { b:match("^(%d+)-?(%d*)-?(%d*)") }
        
            for i = 1, 3 do
                local anum = tonumber(aparts[i]) or 0
                local bnum = tonumber(bparts[i]) or 0
                if anum ~= bnum then return anum < bnum end
            end
            return a < b
        end)
    
        return stemFiles
    end
    
    
    
    -- Step 3: Insert media and nest tracks based on prefix
    local function importStemsWithNesting(stemsFolder, stemFiles)
        local depthStack = {}  -- This will keep track of current folder structure
        local prevDepth = 0
    
        for i, file in ipairs(stemFiles) do
            local filePath = stemsFolder .. "/" .. file
    
            -- Parse prefix like 01-01-02 etc.
            local prefix = file:match("^(%d[%d%-]*)[%s%-]")  -- Match prefix
            local depth = 0
            if prefix then
                -- Count how many numeric parts are in the prefix to determine depth
                for _ in prefix:gmatch("%d+") do
                    depth = depth + 1
                end
            end
    
            -- Debugging: Show what we're importing and the depth level
            reaper.ShowConsoleMsg(string.format("Importing: %s, Prefix: %s, Depth: %d\n", file, prefix, depth))
    
            -- Deselect all tracks before inserting a new one
            reaper.Main_OnCommand(40297, 0)  -- Unselect all tracks
    
            -- Insert new track
            reaper.InsertTrackAtIndex(reaper.CountTracks(0), true)
            local trackIndex = reaper.CountTracks(0) - 1
            local newTrack = reaper.GetTrack(0, trackIndex)
    
            -- Name it based on the stem filename (without extension)
            -- Remove the prefix and extension to get the original name
            local name = file:match("^%d[%d%-]*[%- ]+(.+)%..+$") or file:gsub("%.wav$", "")
    
            reaper.GetSetMediaTrackInfo_String(newTrack, "P_NAME", name, true)
    
            -- Insert media into this track
            reaper.SetEditCurPos(0, false, false) -- Move edit cursor to 0 (do not seek, do not add undo point)
            reaper.SetOnlyTrackSelected(newTrack)
            reaper.InsertMedia(filePath, 0) -- Insert at cursor (now at time 0)
    
            -- Debugging: Log current track info
            reaper.ShowConsoleMsg(string.format("Inserted: %s into track %d\n", name, trackIndex + 1))
    
            if i > 1 then
              -- Handle nesting based on depth
              if depth > prevDepth then
                  -- Create a new folder track (mark the previous one as a parent folder)
                      local lastTrack = reaper.GetTrack(0, trackIndex - 1)
                      local _, lastTrackName = reaper.GetTrackName(lastTrack)
                      reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", 1)  -- Set it as folder
                      reaper.SetMediaTrackInfo_Value(newTrack, "I_FOLDERDEPTH", 0)  -- Normal track
                      table.insert(depthStack, lastTrack)  -- Add it to the depth stack
                      
                      local folderDepthLastTrack = reaper.GetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH")  -- Get the I_FOLDERDEPTH value
                      local folderDepthNewTrack = reaper.GetMediaTrackInfo_Value(newTrack, "I_FOLDERDEPTH")  -- Get the I_FOLDERDEPTH value
                      reaper.ShowConsoleMsg(string.format("Created folder: trackindex %d for track %s | folderDepthLastTrack: %s | folderDepthNewTrack %s \n", 
                        trackIndex + 1, lastTrackName, folderDepthLastTrack, folderDepthNewTrack))
            
                  
              -- reduce folderdepth based on depth difference
              elseif depth < prevDepth then
                  local lastTrack = reaper.GetTrack(0, trackIndex - 1)
                  reaper.SetMediaTrackInfo_Value(lastTrack, "I_FOLDERDEPTH", depth - prevDepth)  -- Set it as folder
              
              end
            end
    
            prevDepth = depth
        end
    
    end
    
    
    
    
    -- Step 4: Get stem files and import them with nesting
    local stemFiles = getSortedStemFiles(stemsFolder)
    importStemsWithNesting(stemsFolder, stemFiles)
    
    -- Loop through all tracks and print the I_FOLDERDEPTH value
    local trackCount = reaper.CountTracks(0)
    
    for i = 0, trackCount - 1 do
        local track = reaper.GetTrack(0, i)  -- Get the track
        local _, trackname = reaper.GetTrackName(track)
        local folderDepth = reaper.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")  -- Get the I_FOLDERDEPTH value
    
        -- Print the track index and its folder depth to the console
        reaper.ShowConsoleMsg(string.format("Track %s, I_FOLDERDEPTH: %d\n",trackname, folderDepth))
    end
    
    
    
    reaper.ShowConsoleMsg("✅ Stems imported into new project with hierarchy based on prefixes.\n")
end














--GUI
function loop()
    if not visible then return end

    reaper.ImGui_SetNextWindowSize(ctx, 300, 150, reaper.ImGui_Cond_FirstUseEver())

    local rv
    rv, visible = reaper.ImGui_Begin(ctx,"Quickstem", true)
    if rv then
        reaper.ImGui_Text(ctx, "Export stems with hierarchy:")
        if reaper.ImGui_Button(ctx, 'Run Export') then
            runStemExporter()
        end
        reaper.ImGui_End(ctx)
    end

    -- ������ This is crucial: keeps the UI alive
    reaper.defer(loop)
end

reaper.defer(loop)



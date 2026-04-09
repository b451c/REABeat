-- ReaBeat Actions: REAPER API calls for tempo map and stretch markers
-- All actions wrapped in undo blocks. Warns before destructive operations.

local actions = {}

--- Insert tempo/time signature markers at detected bar positions.
-- @return Number of markers inserted, or 0 if cancelled
function actions.insert_tempo_map(beats, downbeats, tempo, ts_num, ts_denom, item, variable)
    if not downbeats or #downbeats == 0 then return 0 end

    -- Warn if existing tempo markers will be affected
    local existing = reaper.CountTempoTimeSigMarkers(0)
    if existing > 1 then
        local ok = reaper.ShowMessageBox(
            string.format(
                "Project has %d existing tempo markers.\n\n" ..
                "ReaBeat will ADD new markers (existing ones stay).\n" ..
                "Use Ctrl+Z to undo if needed.\n\nContinue?",
                existing),
            "ReaBeat — Tempo Map", 1)
        if ok ~= 1 then return 0 end
    end

    local item_pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    item_pos = math.max(0, item_pos)  -- Clamp negative positions

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    local count = 0

    if not variable then
        -- Constant tempo: single marker at item start
        reaper.SetTempoTimeSigMarker(0, -1,
            item_pos, -1, -1,
            tempo,
            math.floor(ts_num),
            math.floor(ts_denom),
            false)
        count = 1
    else
        -- Variable tempo: one marker per bar
        for i = 1, #downbeats do
            local bar_time = item_pos + downbeats[i]
            local bar_bpm = tempo

            if i < #downbeats then
                local bar_duration = downbeats[i + 1] - downbeats[i]
                if bar_duration > 0 then
                    bar_bpm = (ts_num / bar_duration) * 60.0
                    bar_bpm = math.max(30, math.min(300, bar_bpm))
                end
            end

            local set_ts = (i == 1)
            reaper.SetTempoTimeSigMarker(0, -1,
                bar_time, -1, -1,
                bar_bpm,
                set_ts and math.floor(ts_num) or 0,
                set_ts and math.floor(ts_denom) or 0,
                true)
            count = count + 1
        end
    end

    reaper.UpdateTimeline()
    reaper.PreventUIRefresh(-1)

    local label = variable
        and string.format("ReaBeat: Insert variable tempo map (%d markers)", count)
        or string.format("ReaBeat: Insert constant tempo (%.1f BPM)", tempo)
    reaper.Undo_EndBlock(label, -1)

    return count
end

--- Insert stretch markers at detected beat positions.
-- @return Number of markers inserted, or 0 if cancelled
function actions.insert_stretch_markers(take, beat_times, item)
    if not take or not beat_times or #beat_times == 0 then return 0 end

    -- Warn if existing stretch markers will be replaced
    local existing = reaper.GetTakeNumStretchMarkers(take)
    if existing > 0 then
        local ok = reaper.ShowMessageBox(
            string.format(
                "Item has %d existing stretch markers.\n\n" ..
                "ReaBeat will REPLACE them with %d new markers.\n" ..
                "Use Ctrl+Z to undo if needed.\n\nContinue?",
                existing, #beat_times),
            "ReaBeat — Stretch Markers", 1)
        if ok ~= 1 then return 0 end
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- Clear existing stretch markers
    if existing > 0 then
        reaper.DeleteTakeStretchMarkers(take, 0, existing)
    end

    local count = 0
    local take_offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")

    for _, bt in ipairs(beat_times) do
        local pos = bt + take_offset
        local idx = reaper.SetTakeStretchMarker(take, -1, pos)
        if idx >= 0 then
            count = count + 1
        end
    end

    reaper.UpdateItemInProject(item)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(
        string.format("ReaBeat: Insert %d stretch markers", count), -1)

    return count
end

--- Get current project BPM.
-- @return number BPM
function actions.get_project_bpm()
    local bpm, bpi = reaper.GetProjectTimeSignature2(0)
    return bpm
end

--- Match item tempo to target BPM by adjusting playrate.
-- Preserves pitch using REAPER's élastique engine.
-- @param take Media item take
-- @param item Media item
-- @param detected_bpm Detected source BPM
-- @param target_bpm Target BPM to match
-- @return boolean success
function actions.match_tempo(take, item, detected_bpm, target_bpm)
    if not take or not item then return false end
    if detected_bpm <= 0 or target_bpm <= 0 then return false end

    local rate = target_bpm / detected_bpm

    -- Sanity check: don't allow extreme rates (0.25x to 4x)
    if rate < 0.25 or rate > 4.0 then
        reaper.ShowMessageBox(
            string.format(
                "Tempo ratio too extreme: %.1f BPM -> %.1f BPM (%.1fx)\n\n" ..
                "Supported range: 0.25x to 4.0x",
                detected_bpm, target_bpm, rate),
            "ReaBeat — Match Tempo", 0)
        return false
    end

    reaper.Undo_BeginBlock()
    reaper.PreventUIRefresh(1)

    -- Set playrate and preserve pitch
    reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
    reaper.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)  -- preserve pitch ON

    -- Adjust item length to match new rate
    local source = reaper.GetMediaItemTake_Source(take)
    if source then
        local source_len = reaper.GetMediaSourceLength(source)
        local offset = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
        local new_len = (source_len - offset) / rate
        reaper.SetMediaItemInfo_Value(item, "D_LENGTH", new_len)
    end

    reaper.UpdateItemInProject(item)
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(
        string.format("ReaBeat: Match tempo %.1f -> %.1f BPM", detected_bpm, target_bpm), -1)

    return true
end

return actions

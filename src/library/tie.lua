--[[
$module Tie

This library encapsulates Finale's behavior for initializing FCTieMod endpoints,
as well as providing other useful information about ties. 
]] --
local tie = {}

-- returns the equal note in the next closest entry or nil if none
local equal_note = function(entry, target_note, for_tieend)
    if entry:IsRest() then
        return nil
    end
    -- By using CalcStaffPosition we can support a key change in the middle of a tie. But it is at the cost
    -- of not supporting a clef change in the middle of the tie. A calculation comparing normalized concert
    -- pitch is *much* more complicated code, and clef changes in the middle of ties seem like a very limited
    -- use case.
    local target_staffline = target_note:CalcStaffPosition()
    for note in each(entry) do
        local this_staffline = note:CalcStaffPosition()
        if this_staffline == target_staffline then
            if for_tieend then
                if note.TieBackwards then
                    return note
                end
            else
                if note.Tie then
                    return note
                end
            end
        end
    end
    return nil
end

-- returns the note that the input note is tied to.
-- for this function to work, note must be from a FCNoteEntryLayer
-- instance constructed by function tie_span.
local function tied_to(note)
    if not note then
        return nil
    end
    local next_entry = note.Entry
    if next_entry then
        next_entry = next_entry:Next()
        if next_entry and not next_entry.GraceNote then
            local tied_to_note = equal_note(next_entry, note, true)
            if tied_to_note then
                return tied_to_note
            end
            if next_entry.Voice2Launch then
                local next_v2_entry = next_entry:Next()
                tied_to_note = equal_note(next_v2_entry, note, true)
                if tied_to_note then
                    return tied_to_note
                end
            end
        end
    end
    return nil
end

-- returns the note that the input note is tied from.
-- for this function to work, note must be from a FCNoteEntryLayer
-- instance constructed by function tie_span.
local function tied_from(note)
    if not note then
        return nil
    end
    local entry = note.Entry
    while true do
        entry = entry:Previous()
        if not entry then
            break
        end
        tied_from_note = equal_note(entry, note, false)
        if tied_from_note then
            return tied_from_note
        end
    end
end

-- returns FCNoteEntryLayer, along with start and end FCNotes for the tie that
--      are contained within the FCNoteEntryLayer.
local tie_span = function(note, for_tieend)
    local start_measnum = (for_tieend and note.Entry.Measure > 1) and note.Entry.Measure - 1 or note.Entry.Measure
    local end_measnum = for_tieend and note.Entry.Measure or note.Entry.Measure + 1
    local note_entry_layer = finale.FCNoteEntryLayer(note.Entry.LayerNumber - 1, note.Entry.Staff, start_measnum, end_measnum)
    note_entry_layer:Load()
    local same_entry
    for entry in each(note_entry_layer) do
        if entry.EntryNumber == note.Entry.EntryNumber then
            same_entry = entry
            break
        end
    end
    if not same_entry then
        return note_entry_layer
    end
    local note_entry_layer_note = same_entry:GetItemAt(note.NoteIndex)
    local start_note = for_tieend and tied_from(note_entry_layer_note) or note_entry_layer_note
    local end_note = for_tieend and note_entry_layer_note or tied_to(note_entry_layer_note)
    return note_entry_layer, start_note, end_note
end

--[[
% calc_default_direction

Calculates the default direction of a tie based on context and FCTiePrefs but ignoring multi-voice
and multi-layer overrides. It also does not take into account the direction being overridden in
FCTieMods. Use tie.calc_direction to calculate the actual current tie direction.

@ note (FCNote) the note for which to return the tie direction.
@ for_tieend (boolean) specifies that this request is for a tie_end.
@ [tie_prefs] (FCTiePrefs) use these tie prefs if supplied
: (number) Returns either TIEMODDIR_UNDER or TIEMODDIR_OVER. If the input note has no applicable tie, it returns 0.
]]
function tie.calc_default_direction(note, for_tieend, tie_prefs)
    if for_tieend then
        if not note.TieBackwards then
            return 0
        end
    else
        if not note.Tie then
            return 0
        end
    end
    if not tie_prefs then
        tie_prefs = finale.FCTiePrefs()
        tie_prefs:Load(0)
    end
    local stemdir = note.Entry:CalcStemUp() and 1 or -1
    if note.Entry.Count > 1 then
        -- This code depends on observed Finale behavior that the notes are always sorted
        -- from lowest-to-highest inside the entry. If Finale's behavior ever changes, this
        -- code is screwed.

        -- If note is outer, tie-direction is unaffected by tie_prefs
        if note.NoteIndex == 0 then
            return finale.TIEMODDIR_UNDER
        end
        if note.NoteIndex == note.Entry.Count - 1 then
            return finale.TIEMODDIR_OVER
        end

        local inner_default = 0

        if tie_prefs.ChordDirectionType ~= finale.TIECHORDDIR_STEMREVERSAL then
            if note.NoteIndex < math.floor(note.Entry.Count / 2) then
                inner_default = finale.TIEMODDIR_UNDER
            end
            if note.NoteIndex >= math.floor((note.Entry.Count + 1) / 2) then
                inner_default = finale.TIEMODDIR_OVER
            end
            if tie_prefs.ChordDirectionType == finale.TIECHORDDIR_OUTSIDEINSIDE then
                inner_default = (stemdir > 0) and finale.TIEMODDIR_UNDER or finale.TIEMODDIR_OVER
            end
        end
        if inner_default == 0 or tie_prefs.ChordDirectionType == finale.TIECHORDDIR_STEMREVERSAL then
            local staff_position = note:CalcStaffPosition()
            local curr_staff = finale.FCCurrentStaffSpec()
            curr_staff:LoadForEntry(note.Entry)
            inner_default = staff_position < curr_staff.StemReversalPosition and finale.TIEMODDIR_UNDER or finale.TIEMODDIR_OVER
        end
        if inner_default ~= 0 then
            if tie_prefs.ChordDirectionOpposingSeconds then
                if inner_default == finale.TIEMODDIR_OVER and not note:IsUpper2nd() and note:IsLower2nd() then
                    return finale.TIEMODDIR_UNDER
                end
                if inner_default == finale.TIEMODDIR_UNDER and note:IsUpper2nd() and not note:IsLower2nd() then
                    return finale.TIEMODDIR_OVER
                end
            end
            return inner_default
        end
    else
        local adjacent_stemdir = 0
        local note_entry_layer, start_note, end_note = tie_span(note, for_tieend)
        if for_tieend then
            -- There seems to be a "bug" in how Finale determines mixed-stem values for Tie-Ends.
            -- It looks at the stem direction of the immediately preceding entry, even if that entry
            -- is not the entry that started the tie. Therefore, do not use tied_from_note to
            -- get the stem direction.
            if end_note then
                local start_entry = end_note.Entry:Previous()
                if start_entry then
                    adjacent_stemdir = start_entry:CalcStemUp() and 1 or -1
                end
            end
        else
            if end_note then
                adjacent_stemdir = end_note.Entry:CalcStemUp() and 1 or -1
            end
            if adjacent_stemdir == 0 and start_note then
                -- Finale (as of v2K) has the following Mickey Mouse behavior. When no Tie-To note exists,
                -- it determines the mixed stem value based on
                --		1. If the next entry is a rest, the adjStemDir is indeterminate so use stemDir (i.e., fall thru to bottom)
                --		2. If the next entry is a note with its stem frozen, use it
                --		3. If the next entry floats, but it has a V2Launch, then if EITHER the V1 or
                --				the V2 has a stem in the opposite direction, use it.
                local next_entry = start_note.Entry:Next()
                if next_entry and not next_entry:IsRest() then
                    adjacent_stemdir = next_entry:CalcStemUp() and 1 or -1
                    if not next_entry.FreezeStem and next_entry.Voice2Launch and adjacent_stemdir == stemdir then
                        next_entry = next_entry:Next()
                        if next_entry then
                            adjacent_stemdir = next_entry:CalcStemUp() and 1 or -1
                        end
                    end
                end
            end
            if adjacent_stemdir ~= 0 and adjacent_stemdir ~= stemdir then
                if tie_prefs.MixedStemDirectionType == finale.TIEMIXEDSTEM_OVER then
                    return finale.TIEMODDIR_OVER
                elseif tie_prefs.MixedStemDirectionType == finale.TIEMIXEDSTEM_UNDER then
                    return finale.TIEMODDIR_UNDER
                end
            end
        end
    end

    return (stemdir > 0) and finale.TIEMODDIR_UNDER or finale.TIEMODDIR_OVER

end -- function tie.default_direction

local calc_layer_is_visible = function(staff, layer_number)
    local altnotation_layer = staff.AltNotationLayer
    if layer_number ~= altnotation_layer then
        return staff.AltShowOtherNotes
    end

    local hider_altnotation_types = {finale.ALTSTAFF_BLANKNOTATION, finale.ALTSTAFF_SLASHBEATS, finale.ALTSTAFF_ONEBARREPEAT, finale.ALTSTAFF_TWOBARREPEAT, finale.ALTSTAFF_BLANKNOTATIONRESTS}
    local altnotation_type = staff.AltNotationStyle
    for _, v in pairs(hider_altnotation_types) do
        if v == altnotation_type then
            return false
        end
    end

    return true
end

local calc_other_layers_visible = function(entry)
    local staff = finale.FCCurrentStaffSpec()
    staff:LoadForEntry(entry)
    for layer = 1, finale.FCLayerPrefs.GetMaxLayers() do
        if layer ~= entry.LayerNumber and calc_layer_is_visible(staff, layer) then
            local layer_prefs = finale.FCLayerPrefs()
            if layer_prefs:Load(layer - 1) and not layer_prefs.HideWhenInactive then
                local layer_entries = finale.FCNoteEntryLayer(layer - 1, entry.Staff, entry.Measure, entry.Measure)
                if layer_entries:Load() then
                    for layer_entry in each(layer_entries) do
                        if layer_entry.Visible then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local layer_stem_direction = function(layer_prefs, entry)
    if layer_prefs.UseFreezeStemsTies then
        if layer_prefs.UseRestOffsetInMultiple then -- UseRestOffsetInMultiple controls a lot more than just rests
            if not entry:CalcMultiLayeredCell() then
                return 0
            end
            if layer_prefs.IgnoreHiddenNotes and not calc_other_layers_visible(entry) then
                return 0
            end
        end
        return layer_prefs.FreezeStemsUp and 1 or -1
    end
    return 0
end

local layer_tie_direction = function(entry)
    local layer_prefs = finale.FCLayerPrefs()
    if not layer_prefs:Load(entry.LayerNumber - 1) then
        return 0
    end
    local layer_stemdir = layer_stem_direction(layer_prefs, entry)
    if layer_stemdir ~= 0 and layer_prefs.FreezeTiesSameDirection then
        return layer_stemdir > 0 and finale.TIEMODDIR_OVER or finale.TIEMODDIR_UNDER
    end
    return 0
end

--[[
% calc_direction

Calculates the current direction of a tie based on context and FCTiePrefs, taking into account multi-voice
and multi-layer overrides. It also takes into account if the direction has been overridden in
FCTieMods.

@ note (FCNote) the note for which to return the tie direction.
@ tie_mod (FCTieMod) the tie mods for the note, if any.
@ [tie_prefs] (FCTiePrefs) use these tie prefs if supplied
: (number) Returns either TIEMODDIR_UNDER or TIEMODDIR_OVER. If the input note has no applicable tie, it returns 0.
]]
function tie.calc_direction(note, tie_mod, tie_prefs)
    -- much of this code works even if the note doesn't (yet) have a tie, so
    -- skip the check to see if we actually have a tie.
    if tie_mod.TieDirection ~= finale.TIEMODDIR_AUTOMATIC then
        return tie_mod.TieDirection
    end
    if note.Entry.SplitStem then
        return note.UpstemSplit and finale.TIEMODDIR_OVER or finale.TIEMODDIR_UNDER
    end
    local layer_tiedir = layer_tie_direction(note.Entry)
    if layer_tiedir ~= 0 then
        return layer_tiedir
    end
    if note.Entry.Voice2Launch or note.Entry.Voice2 then
        return note.Entry:CalcStemUp() and finale.TIEMODDIR_OVER or finale.TIEMODDIR_UNDER
    end
    if note.Entry.FlipTie then
        return note.Entry:CalcStemUp() and finale.TIEMODDIR_OVER or finale.TIEMODDIR_UNDER
    end

    return tie.calc_default_direction(note, not tie_mod:IsStartTie(), tie_prefs)
end -- function tie.calc_direction

local calc_is_end_of_system = function(note, for_pageview)
    if not note.Entry:Next() then
        local region = finale.FCMusicRegion()
        region:SetFullDocument()
        if note.Entry.Measure == region.EndMeasure then
            return true
        end
    end
    if for_pageview then
        local note_entry_layer, start_note, end_note = tie_span(note, false)
        if start_note and end_note then
            local systems = finale.FCStaffSystems()
            systems:LoadAll()
            local start_system = systems:FindMeasureNumber(start_note.Entry.Measure)
            local end_system = systems:FindMeasureNumber(end_note.Entry.Measure)
            return start_system.ItemNo ~= end_system.ItemNo
        end
    end
    return false
end

local has_nonaligned_2nd = function(entry)
    for note in each(entry) do
        if note:IsNonAligned2nd() then
            return true
        end
    end
    return false
end

--[[
% calc_connection_code

Calculates the correct connection code for activating a Tie Placement Start Point or End Point
in FCTieMod.

@ note (FCNote) the note for which to return the code
@ placement (number) one of the TIEPLACEMENT_INDEXES values
@ direction (number) one of the TIEMOD_DIRECTION values
@ for_endpoint (boolean) if true, calculate the end point code, otherwise the start point code
@ for_tieend (boolean) if true, calculate the code for a tie end
@ for_pageview (boolean) if true, calculate the code for page view, otherwise for scroll/studio view
@ [tie_prefs] (FCTiePrefs) use these tie prefs if supplied
: (number) Returns one of TIEMOD_CONNECTION_CODES. If the input note has no applicable tie, it returns TIEMODCNCT_NONE.
]]
function tie.calc_connection_code(note, placement, direction, for_endpoint, for_tieend, for_pageview, tie_prefs)
    -- As of now, I haven't found any use for the connection codes:
    --      TIEMODCNCT_ENTRYCENTER_NOTEBOTTOM
    --      TIEMODCNCT_ENTRYCENTER_NOTETOP
    -- The other 15 are accounted for here. RGP 5/11/2022
    if not tie_prefs then
        tie_prefs = finale.FCTiePrefs()
        tie_prefs:Load(0)
    end
    if not for_endpoint and for_tieend then
        return finale.TIEMODCNCT_SYSTEMSTART
    end
    if for_endpoint and not for_tieend and calc_is_end_of_system(note, for_pageview) then
        return finale.TIEMODCNCT_SYSTEMEND
    end
    if placement == finale.TIEPLACE_OVERINNER or placement == finale.TIEPLACE_UNDERINNER then
        local stemdir = note.Entry:CalcStemUp() and 1 or -1
        if for_endpoint then
            if tie_prefs.BeforeSingleAccidental and note.Entry.Count == 1 and note:CalcAccidental() then
                return finale.TIEMODCNCT_ACCILEFT_NOTECENTER
            end
            if has_nonaligned_2nd(note.Entry) then
                if (stemdir > 0 and direction ~= finale.TIEMODDIR_UNDER and note:IsNonAligned2nd()) or (stemdir < 0 and not note:IsNonAligned2nd()) then
                    return finale.TIEMODCNCT_NOTELEFT_NOTECENTER
                end
            end
            return finale.TIEMODCNCT_ENTRYLEFT_NOTECENTER
        else
            local num_dots = note.Entry:CalcDots()
            if (tie_prefs.AfterSingleDot and num_dots == 1) or (tie_prefs.AfterMultipleDots and num_dots > 1) then
                return finale.TIEMODCNCT_DOTRIGHT_NOTECENTER
            end
            if has_nonaligned_2nd(note.Entry) then
                if (stemdir > 0 and not note:IsNonAligned2nd()) or (stemdir < 0 and direction ~= finale.TIEMODDIR_OVER and note:IsNonAligned2nd()) then
                    return finale.TIEMODCNCT_NOTERIGHT_NOTECENTER
                end
            end
            return finale.TIEMODCNCT_ENTRYRIGHT_NOTECENTER
        end
    elseif placement == finale.TIEPLACE_OVEROUTERNOTE then
        return finale.TIEMODCNCT_NOTECENTER_NOTETOP
    elseif placement == finale.TIEPLACE_UNDEROUTERNOTE then
        return finale.TIEMODCNCT_NOTECENTER_NOTEBOTTOM
    elseif placement == finale.TIEPLACE_OVEROUTERSTEM then
        return for_endpoint and finale.TIEMODCNCT_NOTELEFT_NOTETOP or finale.TIEMODCNCT_NOTERIGHT_NOTETOP
    elseif placement == finale.TIEPLACE_UNDEROUTERSTEM then
        return for_endpoint and finale.TIEMODCNCT_NOTELEFT_NOTEBOTTOM or finale.TIEMODCNCT_NOTERIGHT_NOTEBOTTOM
    end
    return finale.TIEMODCNCT_NONE
end

local calc_placement_for_endpoint = function(note, tie_mod, tie_prefs, direction, stemdir, for_endpoint, end_note_slot, end_num_notes, end_upstem2nd, end_downstem2nd)
    local note_slot = end_note_slot and end_note_slot or note.NoteIndex
    local num_notes = end_num_notes and end_num_notes or note.Entry.Count
    local upstem2nd = end_upstem2nd ~= nil and end_upstem2nd or note.Upstem2nd
    local downstem2nd = end_downstem2nd ~= nil and end_downstem2nd or note.Downstem2nd
    if (note_slot == 0 and direction == finale.TIEMODDIR_UNDER) or (note_slot == num_notes - 1 and direction == finale.TIEMODDIR_OVER) then
        local use_outer = false
        local manual_override = false
        if tie_mod.OuterPlacement ~= finale.TIEMODSEL_DEFAULT then
            manual_override = true
            if tie_mod.OuterPlacement == finale.TIEMODSEL_ON then
                use_outer = true
            end
        end
        if not manual_override and tie_prefs.UseOuterPlacement then
            use_outer = true
        end
        if use_outer then
            if note.Entry.Duration < finale.WHOLE_NOTE then
                if for_endpoint then
                    -- A downstem 2nd is always treated as OuterNote
                    -- An upstem 2nd is always treated as OuterStem
                    if stemdir < 0 and direction == finale.TIEMODDIR_UNDER and not downstem2nd then
                        return finale.TIEPLACE_UNDEROUTERSTEM
                    end
                    if stemdir > 0 and direction == finale.TIEMODDIR_OVER and upstem2nd then
                        return finale.TIEPLACE_OVEROUTERSTEM
                    end
                else
                    -- see comments above and take their opposites
                    if stemdir > 0 and direction == finale.TIEMODDIR_OVER and not upstem2nd then
                        return finale.TIEPLACE_OVEROUTERSTEM
                    end
                    if stemdir < 0 and direction == finale.TIEMODDIR_UNDER and downstem2nd then
                        return finale.TIEPLACE_UNDEROUTERSTEM
                    end
                end
            end
            return direction == finale.TIEMODDIR_UNDER and finale.TIEPLACE_UNDEROUTERNOTE or finale.TIEPLACE_OVEROUTERNOTE
        end
    end
    return direction == finale.TIEMODDIR_UNDER and finale.TIEPLACE_UNDERINNER or finale.TIEPLACE_OVERINNER
end

--[[
% calc_placement

Calculates the current placement of a tie based on context and FCTiePrefs.

@ note (FCNote) the note for which to return the tie direction.
@ tie_mod (FCTieMod) the tie mods for the note, if any.
@ for_pageview (bool) true if calculating for Page View, false for Scroll/Studio View
@ direction (number) one of the TIEMOD_DIRECTION values or nil (if you don't know it yet)
@ [tie_prefs] (FCTiePrefs) use these tie prefs if supplied
: (number) TIEPLACEMENT_INDEXES value for start point
: (number) TIEPLACEMENT_INDEXES value for end point
]]
function tie.calc_placement(note, tie_mod, for_pageview, direction, tie_prefs)
    if not tie_prefs then
        tie_prefs = finale.FCTiePrefs()
        tie_prefs:Load(0)
    end
    direction = direction and direction ~= finale.TIEMODDIR_AUTOMATIC and direction or tie.calc_direction(note, tie_mod, tie_prefs)
    local stemdir = note.Entry:CalcStemUp() and 1 or -1
    local start_placement, end_placement
    if not tie_mod:IsStartTie() then
        start_placement = calc_placement_for_endpoint(note, tie_mod, tie_prefs, direction, stemdir, false)
        end_placement = calc_placement_for_endpoint(note, tie_mod, tie_prefs, direction, stemdir, true)
    else
        start_placement = calc_placement_for_endpoint(note, tie_mod, tie_prefs, direction, stemdir, false)
        end_placement = start_placement -- initialize it with something
        local note_entry_layer, start_note, end_note = tie_span(note, false)
        if end_note then
            local next_stemdir = end_note.Entry:CalcStemUp() and 1 or -1
            end_placement = calc_placement_for_endpoint(end_note, tie_mod, tie_prefs, direction, next_stemdir, true)
        else
            -- more reverse-engineered logic. Here is the observed Finale behavior:
            -- 1. Ties to rests and nothing have StemOuter placement at their endpoint.
            -- 2. Ties to an adjacent empty bar have inner placement on both ends. (weird but true)
            -- 3. Ties to notes are Inner if the down-tied-to entry has a note that is lower or
            --			an up-tied-to entry has a note that is higher.
            --			The flakiest behavior is with with under-ties to downstem chords containing 2nds.
            --			In this case, we must pass in the UPSTEM 2nd bit or'ed from all notes in the chord.
            local next_entry = start_note.Entry:Next() -- start_note is from note_entry_layer, which includes the next bar
            if next_entry then
                if not next_entry:IsRest() and next_entry.Count > 0 then
                    if direction == finale.TIEMODDIR_UNDER then
                        local next_note = next_entry:GetItemAt(0)
                        if next_note.Displacment < note.Displacement then
                            end_placement = finale.TIEPLACE_UNDERINNER
                        else
                            local next_stemdir = next_entry:CalcStemUp() and 1 or -1
                            end_placement = calc_placement_for_endpoint(next_note, tie_mod, tie_prefs, direction, next_stemdir, true)
                        end
                    else
                        local next_note = next_entry:GetItemAt(next_entry.Count - 1)
                        if next_note.Displacment > note.Displacement then
                            end_placement = finale.TIEPLACE_OVERINNER
                        else
                            -- flaky behavior alert: this code might not work in a future release but
                            -- so far it it has held up. This is the Finale 2000 behavior.
                            -- If the entry is downstem, OR together all the Upstem 2nd bits.
                            -- Finale is so flaky that it does not do this for Scroll View at less than 130%.
                            -- However, it seems to do it consistently in Page View.
                            local upstem2nd = next_note.Upstem2nd
                            if next_entry:CalcStemUp() then
                                for check_note in each(next_entry) do
                                    if check_note.Upstem2nd then
                                        upstem2nd = true
                                    end
                                end
                                local next_stemdir = direction == finale.TIEMODDIR_UNDER and -1 or 1
                                end_placement = calc_placement_for_endpoint(next_note, tie_mod, tie_prefs, direction, next_stemdir, true, next_note.NoteIndex, next_entry.Count, upstem2nd, next_note.Downstem2nd)
                            end
                        end
                    end
                else
                    local next_stemdir = direction == finale.TIEMODDIR_UNDER and -1 or 1
                    end_placement = calc_placement_for_endpoint(note, tie_mod, tie_prefs, direction, next_stemdir, true, note.NoteIndex, note.Entry.Count, false, false)
                end
            else
                if calc_is_end_of_system(note, for_pageview) then
                    end_placement = direction == finale.TIEMODDIR_UNDER and finale.TIEPLACE_UNDEROUTERSTEM or finale.TIEPLACE_OVEROUTERSTEM
                else
                    end_placement = direction == finale.TIEMODDIR_UNDER and finale.TIEPLACE_UNDERINNER or finale.TIEPLACE_OVERINNER
                end
            end
        end
    end

    -- if either of the endpoints is inner, make both of them inner.
    if start_placement == finale.TIEPLACE_OVERINNER or start_placement == finale.TIEPLACE_UNDERINNER then
        end_placement = start_placement
    elseif end_placement == finale.TIEPLACE_OVERINNER or end_placement == finale.TIEPLACE_UNDERINNER then
        start_placement = end_placement
    end

    return start_placement, end_placement
end

return tie

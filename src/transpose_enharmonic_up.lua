function plugindef()
    finaleplugin.RequireSelection = true
    finaleplugin.Author = "Robert Patterson"
    finaleplugin.Copyright = "CC0 https://creativecommons.org/publicdomain/zero/1.0/"
    finaleplugin.Version = "1.0"
    finaleplugin.Date = "March 25, 2021"
    finaleplugin.CategoryTags = "Pitch"
    return "Enharmonic Transpose Up", "Enharmonic Transpose Up",
           "Transpose up enharmonically all notes in selected regions."
end

--[[
In normal 12-note music, enharmonically transposing is the same as transposing by a diminished 2nd.
However, in some microtone systems (specifically 19-EDO and 31-EDO), enharmonic transposition produces a different result
than chromatic transposition. As an example, in 12-tone systems C is equivalent to Dbb. But in 31-EDO, C is five microsteps
lower than D, whereas Dbb is four microsteps lower than D. Transposing C up a diminished 2nd gives Dbb in either system, but
in 31-EDO, Dbb is not the same pitch as C.

For this script to function correctly with custom key signatures, you must create a custom_key_sig.config.txt file in the
the script_settings folder with the following two options for the custom key signature you are using. Unfortunately,
the current version of JW Lua does allow scripts to read this information from the Finale document.

(This example is for 31-EDO.)

number_of_steps = 31
diatonic_steps = {0, 5, 10, 13, 18, 23, 28}
]]

local transposition = require("library.transposition")

function transpose_enharmonic_up()
    local success = true
    for entry in eachentrysaved(finenv.Region()) do
        for note in each(entry) do
            if not transposition.enharmonic_transpose(note, 1) then
                success = false
            end
        end
    end
    if not success then
        finenv.UI():AlertError("Finale is unable to represent some of the transposed pitches. These pitches were left at their original value.", "Transposition Error")
    end
end

transpose_enharmonic_up()

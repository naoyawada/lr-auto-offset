local LrBinding = import 'LrBinding'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrPrefs = import 'LrPrefs'
local LrView = import 'LrView'

local Helpers = require 'Helpers'

local Dialog = {}

-- Shows the offset dialog. Returns the validated offset in stops,
-- or nil if the user cancels. Persists the last-used value in plugin prefs.
function Dialog.askForOffset()
    local prefs = LrPrefs.prefsForPlugin()
    local currentText = tostring(prefs.lastOffset or 0.5)

    while true do
        local enteredText = nil

        LrFunctionContext.callWithContext('autoOffsetDialog', function(context)
            local f = LrView.osFactory()
            local props = LrBinding.makePropertyTable(context)
            props.offsetText = currentText

            local contents = f:row {
                spacing = f:label_spacing(),
                bind_to_object = props,
                f:static_text { title = 'Exposure offset (stops):' },
                f:edit_field {
                    value = LrView.bind 'offsetText',
                    width_in_chars = 6,
                    immediate = true,
                },
            }

            local result = LrDialogs.presentModalDialog {
                title = 'Auto Tone + Exposure Offset',
                contents = contents,
                actionVerb = 'Apply',
            }

            if result == 'ok' then
                enteredText = props.offsetText
            end
        end)

        if enteredText == nil then
            return nil -- user canceled
        end

        local offset, err = Helpers.parseOffset(enteredText)
        if offset then
            prefs.lastOffset = offset
            return offset
        end

        currentText = enteredText -- keep their input so they can correct it
        LrDialogs.message('Invalid offset', err, 'warning')
    end
end

return Dialog

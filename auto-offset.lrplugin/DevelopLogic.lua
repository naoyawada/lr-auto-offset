local LrApplication = import 'LrApplication'

local DevelopLogic = {}

-- The AutoTone flag in a develop preset triggers Lightroom's Auto algorithm
-- (same as the Develop module's Auto button) when the preset is applied.
local autoTonePreset

local function getAutoTonePreset()
    if autoTonePreset == nil then
        autoTonePreset = LrApplication.addDevelopPresetForPlugin(
            _PLUGIN, 'Auto Tone (lr-auto-offset)', { AutoTone = true })
    end
    return autoTonePreset
end

-- Applies Auto Tone then a relative exposure offset (in stops) to one photo.
-- Each photo gets its own named write transaction = one undo step per photo,
-- so a canceled batch leaves already-processed photos individually undoable.
-- Returns true if processed, false if skipped (videos can't take develop settings).
function DevelopLogic.processPhoto(catalog, photo, offset)
    if photo:getRawMetadata('fileFormat') == 'VIDEO' then
        return false
    end

    catalog:withWriteAccessDo('Auto Tone + Exposure Offset', function()
        photo:applyDevelopPreset(getAutoTonePreset(), _PLUGIN)
        if offset ~= 0 then
            photo:quickDevelopAdjustImage('Exposure', offset)
        end
    end, { timeout = 15 })

    return true
end

return DevelopLogic

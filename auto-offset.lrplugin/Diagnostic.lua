-- TEMPORARY diagnostic for the auto+offset ordering bug. Runs on the single
-- most-selected photo: applies Auto Tone and a +0.5 offset in SEPARATE write
-- transactions, waiting for each to settle, and reports the stored exposure
-- at every boundary. Remove this file (and its Info.lua entry) once resolved.
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrTasks = import 'LrTasks'

local DevelopLogic = require 'DevelopLogic'

local function exposureOf(photo)
    local s = photo:getDevelopSettings()
    if s == nil then
        return nil
    end
    return s.Exposure2012
end

-- Polls until the stored exposure differs from oldValue or maxSeconds passes.
local function waitForChange(photo, oldValue, maxSeconds)
    local waited = 0
    while waited < maxSeconds do
        LrTasks.sleep(0.2)
        waited = waited + 0.2
        local now = exposureOf(photo)
        if now ~= oldValue then
            return now, waited
        end
    end
    return exposureOf(photo), waited
end

LrFunctionContext.postAsyncTaskWithContext('autoOffsetDiag', function(context)
    local catalog = LrApplication.activeCatalog()
    local photo = catalog:getTargetPhoto()
    if photo == nil then
        LrDialogs.message('Auto Offset Diagnostic',
            'Select exactly one photo first.', 'info')
        return
    end

    local before = exposureOf(photo)

    catalog:withWriteAccessDo('Diag: Auto Tone only', function()
        photo:applyDevelopPreset(DevelopLogic.getAutoTonePreset(), _PLUGIN)
    end, { timeout = 15 })
    local afterAuto, autoWait = waitForChange(photo, before, 5)

    catalog:withWriteAccessDo('Diag: Offset only', function()
        photo:quickDevelopAdjustImage('Exposure', 0.5)
    end, { timeout = 15 })
    local afterOffset, offsetWait = waitForChange(photo, afterAuto, 5)

    LrDialogs.message('Auto Offset Diagnostic',
        string.format(
            'Stored Exposure2012 at each step:\n\n' ..
            'Before: %s\n' ..
            'After Auto preset (changed after %.1fs): %s\n' ..
            'After +0.5 offset (changed after %.1fs): %s\n\n' ..
            'If split transactions work, the last value should be\n' ..
            'the auto value + 0.5.',
            tostring(before), autoWait, tostring(afterAuto),
            offsetWait, tostring(afterOffset)),
        'info')
end)

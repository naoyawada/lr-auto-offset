-- TEMPORARY diagnostic v3. Findings so far:
--   v1: AutoTone preset stores Exposure2012 = -999999 placeholder, resolved async.
--   v2: after resolution (-0.17), quickDevelopAdjustImage('Exposure', 0.5)
--       moved exposure only +0.01 -- likely a no-op (drift = auto refinement).
-- v3 runs two isolated experiments on a RESET photo:
--   A) quickDevelopAdjustImage alone on the reset photo (no auto in play).
--   B) auto preset -> wait for resolution -> absolute write of
--      Exposure2012 = auto + 0.5 via applyDevelopSettings.
-- Remove this file (and its Info.lua entry) once resolved.
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

local function isResolved(v)
    return v ~= nil and v > -100 and v < 100
end

local function waitForResolved(photo, maxSeconds)
    local waited = 0
    while waited < maxSeconds do
        local v = exposureOf(photo)
        if isResolved(v) then
            return v, waited, true
        end
        LrTasks.sleep(0.2)
        waited = waited + 0.2
    end
    return exposureOf(photo), waited, false
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

    -- Experiment A: quickDevelopAdjustImage alone, no auto involved.
    catalog:withWriteAccessDo('Diag A: quickDev only', function()
        photo:quickDevelopAdjustImage('Exposure', 0.5)
    end, { timeout = 15 })
    LrTasks.sleep(1)
    local afterQuickDev = exposureOf(photo)

    -- Experiment B: auto preset, wait for resolution, absolute write.
    catalog:withWriteAccessDo('Diag B1: Auto Tone', function()
        photo:applyDevelopPreset(DevelopLogic.getAutoTonePreset(), _PLUGIN)
    end, { timeout = 15 })

    local autoValue, autoWait, resolved = waitForResolved(photo, 5)
    if not resolved then
        photo:requestJpegThumbnail(320, 320, function() end)
        autoValue, autoWait, resolved = waitForResolved(photo, 10)
        autoWait = autoWait + 5
    end

    local final = nil
    if resolved then
        catalog:withWriteAccessDo('Diag B2: absolute exposure write', function()
            photo:applyDevelopSettings({ Exposure2012 = autoValue + 0.5 })
        end, { timeout = 15 })
        LrTasks.sleep(1)
        final = exposureOf(photo)
    end

    local verdictA
    if afterQuickDev ~= nil and before ~= nil
            and math.abs(afterQuickDev - (before + 0.5)) < 0.005 then
        verdictA = 'A: quickDevelopAdjustImage WORKS in isolation.'
    else
        verdictA = 'A: quickDevelopAdjustImage did NOT apply +0.5 in isolation.'
    end

    local verdictB
    if not resolved then
        verdictB = 'B: auto never resolved; absolute write not attempted.'
    elseif final ~= nil and math.abs(final - (autoValue + 0.5)) < 0.005 then
        verdictB = 'B: SUCCESS - absolute write after resolution gives auto + 0.5.'
    else
        verdictB = 'B: absolute write FAILED to stick.'
    end

    LrDialogs.message('Auto Offset Diagnostic v3',
        string.format(
            'Before (reset photo): %s\n' ..
            'A) After quickDev +0.5 (no auto): %s\n' ..
            'B) Auto resolved: %s (waited %.1fs)\n' ..
            'B) After absolute write of auto+0.5: %s\n\n%s\n%s',
            tostring(before), tostring(afterQuickDev),
            tostring(autoValue), autoWait, tostring(final),
            verdictA, verdictB),
        'info')
end)

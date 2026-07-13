-- TEMPORARY diagnostic v2 for the auto+offset ordering bug. Finding from v1:
-- applying the AutoTone preset stores Exposure2012 = -999999, a placeholder
-- Lightroom resolves asynchronously. v2 waits for the placeholder to resolve
-- into a real value BEFORE applying the offset, forcing a render if needed.
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

-- The AutoTone placeholder is -999999; any sane exposure is within ±100.
local function isResolved(v)
    return v ~= nil and v > -100 and v < 100
end

-- Polls until the stored exposure is a real (non-placeholder) value.
-- Returns value, secondsWaited, resolvedBoolean.
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

    -- Step 1: auto preset in its own transaction
    catalog:withWriteAccessDo('Diag: Auto Tone only', function()
        photo:applyDevelopPreset(DevelopLogic.getAutoTonePreset(), _PLUGIN)
    end, { timeout = 15 })

    -- Step 2: wait for the -999999 placeholder to resolve; if idle waiting
    -- doesn't resolve it, request a thumbnail to force the develop engine
    -- to render (and therefore compute) the auto settings.
    local autoValue, autoWait, resolved = waitForResolved(photo, 5)
    local forcedRender = false
    if not resolved then
        forcedRender = true
        photo:requestJpegThumbnail(320, 320, function() end)
        autoValue, autoWait, resolved = waitForResolved(photo, 10)
        autoWait = autoWait + 5
    end

    -- Step 3: offset in its own transaction, only after resolution
    catalog:withWriteAccessDo('Diag: Offset only', function()
        photo:quickDevelopAdjustImage('Exposure', 0.5)
    end, { timeout = 15 })
    LrTasks.sleep(1)
    local final = exposureOf(photo)

    local verdict
    if resolved and final ~= nil and math.abs(final - (autoValue + 0.5)) < 0.005 then
        verdict = 'SUCCESS: final = auto + 0.5. Waiting for resolution fixes it.'
    elseif not resolved then
        verdict = 'Auto never resolved from the placeholder, even after forcing a render.'
    else
        verdict = 'Offset still lost or wrong even after resolution.'
    end

    LrDialogs.message('Auto Offset Diagnostic v2',
        string.format(
            'Before: %s\n' ..
            'Auto resolved: %s (waited %.1fs%s)\n' ..
            'After +0.5 offset: %s\n\n%s',
            tostring(before),
            tostring(autoValue), autoWait,
            forcedRender and ', needed forced render' or '',
            tostring(final),
            verdict),
        'info')
end)

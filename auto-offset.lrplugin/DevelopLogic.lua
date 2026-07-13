local LrApplication = import 'LrApplication'
local LrTasks = import 'LrTasks'

local Helpers = require 'Helpers'

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

-- Reads the photo's stored exposure (Exposure2012), or nil.
local function exposureOf(photo)
    local settings = photo:getDevelopSettings()
    if settings == nil then
        return nil
    end
    return settings.Exposure2012
end

-- Pass 1: queue Auto Tone. Lightroom writes a -999999 placeholder into
-- Exposure2012 synchronously within this gate (verified empirically on
-- LR Classic v13) and computes the real auto values asynchronously.
-- waitForAutoExposure relies on that synchronous placeholder write: if a
-- future LR version deferred it, a stale pre-auto exposure could be
-- mistaken for a resolved auto value.
-- Returns true if applied, false if skipped (videos) or the write gate
-- couldn't be acquired.
function DevelopLogic.applyAutoTone(catalog, photo)
    if photo:getRawMetadata('fileFormat') == 'VIDEO' then
        return false
    end

    local status = catalog:withWriteAccessDo('Auto Tone (lr-auto-offset)', function()
        photo:applyDevelopPreset(getAutoTonePreset(), _PLUGIN)
    end, { timeout = 15 })

    return status == 'executed'
end

-- Pass 2a: wait for the auto placeholder to resolve into a real exposure.
-- Halfway through the wait, request a thumbnail render once — rendering
-- forces Lightroom's develop engine to compute the pending auto settings.
-- Returns the resolved auto exposure, or nil on timeout.
function DevelopLogic.waitForAutoExposure(photo, maxSeconds)
    local waited = 0
    -- The handle must stay referenced for the whole wait: the SDK may
    -- cancel the render if the request object is garbage-collected.
    local thumbnailRequest = nil
    local renderRequested = false
    while waited < maxSeconds do
        local v = exposureOf(photo)
        if Helpers.isResolvedExposure(v) then
            return v
        end
        if not renderRequested and waited >= maxSeconds / 2 then
            renderRequested = true
            thumbnailRequest = photo:requestJpegThumbnail(320, 320, function() end)
        end
        LrTasks.sleep(0.2)
        waited = waited + 0.2
    end
    -- Explicitly release the render request only now, at timeout.
    thumbnailRequest = nil
    return nil
end

-- Pass 2b: set the photo's exposure to an absolute value.
-- NOTE: quickDevelopAdjustImage('Exposure', n) is NOT used because it
-- applies roughly n/50 in practice (measured: +0.5 moved exposure +0.01),
-- contrary to its documentation. An absolute applyDevelopSettings write of
-- resolvedAuto + offset is deterministic and verified to work.
-- Returns true if the write gate executed.
function DevelopLogic.applyExposure(catalog, photo, exposure)
    local status = catalog:withWriteAccessDo('Exposure Offset (lr-auto-offset)', function()
        photo:applyDevelopSettings({ Exposure2012 = exposure })
    end, { timeout = 15 })

    return status == 'executed'
end

return DevelopLogic

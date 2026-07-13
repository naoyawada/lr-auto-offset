local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'

local Dialog = require 'Dialog'
local DevelopLogic = require 'DevelopLogic'
local Helpers = require 'Helpers'

-- How long to wait (per photo) for Lightroom to resolve the Auto Tone
-- placeholder before giving up and counting the photo as skipped.
local RESOLVE_TIMEOUT_SECONDS = 10

LrFunctionContext.postAsyncTaskWithContext('autoOffset', function(context)
    local catalog = LrApplication.activeCatalog()
    -- getTargetPhotos() falls back to the whole filmstrip when nothing is
    -- selected; getTargetPhoto() is nil in that case, so it is the sentinel.
    local photos = catalog:getTargetPhoto() and catalog:getTargetPhotos() or {}

    if #photos == 0 then
        LrDialogs.message('No photos selected',
            'Select one or more photos in the Library grid, then run this again.',
            'info')
        return
    end

    local offset = Dialog.askForOffset()
    if offset == nil then
        return
    end

    local progress = LrProgressScope {
        title = string.format('Auto Tone %+.2f stops (%d photos)', offset, #photos),
        functionContext = context,
    }
    progress:setCancelable(true)

    -- Two passes: queue every Auto Tone first (Lightroom computes them
    -- concurrently in the background), then resolve + write each offset.
    -- Progress spans both passes.
    local totalSteps = #photos * 2
    local step = 0

    -- Pass 1: queue Auto Tone on every photo.
    -- Counting semantics: "skipped" = untouched (videos, gate failures,
    -- never reached); "autoOnly" = Auto Tone applied but offset never
    -- written (cancel, resolution timeout, write failure); "processed" =
    -- fully done.
    local queued, skipped = {}, 0
    for _, photo in ipairs(photos) do
        if progress:isCanceled() then
            break
        end
        local ok, applied = LrTasks.pcall(DevelopLogic.applyAutoTone, catalog, photo)
        if ok and applied then
            queued[#queued + 1] = photo
        else
            skipped = skipped + 1
        end
        step = step + 1
        progress:setPortionComplete(step, totalSteps)
        LrTasks.yield()
    end

    -- A pass-1 cancel leaves the remaining photos unreached (untouched):
    -- count them as skipped so the summary always accounts for the whole
    -- selection.
    if progress:isCanceled() then
        skipped = skipped + (#photos - step)
    end

    -- Photos skipped (or never reached) in pass 1 take no pass-2 step;
    -- shrink the denominator so the bar can reach 100%.
    totalSteps = step + #queued

    -- Pass 2: wait for each photo's auto to resolve, then write auto + offset.
    local processed, autoOnly = 0, 0
    if offset == 0 then
        -- Nothing to write on top of Auto — queued photos are complete
        -- as-is; no need to wait for resolution.
        processed = #queued
        step = step + #queued
        if totalSteps > 0 then
            progress:setPortionComplete(step, totalSteps)
        end
    else
        for _, photo in ipairs(queued) do
            if progress:isCanceled() then
                -- Auto Tone is already queued on this photo; without the
                -- offset write it must be reported, not silently dropped.
                autoOnly = autoOnly + 1
            else
                local ok, autoValue = LrTasks.pcall(
                    DevelopLogic.waitForAutoExposure, photo, RESOLVE_TIMEOUT_SECONDS)
                local written = false
                if ok and autoValue ~= nil then
                    local ok2, result = LrTasks.pcall(
                        DevelopLogic.applyExposure, catalog, photo, autoValue + offset)
                    written = ok2 == true and result == true
                end
                if written then
                    processed = processed + 1
                else
                    autoOnly = autoOnly + 1
                end
                step = step + 1
                progress:setPortionComplete(step, totalSteps)
                LrTasks.yield()
            end
        end
    end
    progress:done()

    LrDialogs.message('Auto Tone + Exposure Offset',
        Helpers.formatSummary(processed, skipped)
            .. Helpers.formatAutoOnlyNote(autoOnly), 'info')
end)

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrFunctionContext = import 'LrFunctionContext'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'

local Dialog = require 'Dialog'
local DevelopLogic = require 'DevelopLogic'
local Helpers = require 'Helpers'

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

    local processed, skipped = 0, 0
    for i, photo in ipairs(photos) do
        if progress:isCanceled() then
            break
        end
        local ok, result = LrTasks.pcall(DevelopLogic.processPhoto, catalog, photo, offset)
        if ok and result then
            processed = processed + 1
        else
            skipped = skipped + 1
        end
        progress:setPortionComplete(i, #photos)
        LrTasks.yield()
    end
    progress:done()

    LrDialogs.message('Auto Tone + Exposure Offset',
        Helpers.formatSummary(processed, skipped), 'info')
end)

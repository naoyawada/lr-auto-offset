local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrProgressScope = import 'LrProgressScope'
local LrTasks = import 'LrTasks'

local Dialog = require 'Dialog'
local DevelopLogic = require 'DevelopLogic'
local Helpers = require 'Helpers'

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()

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
    }
    progress:setCancelable(true)

    local processed, skipped = 0, 0
    for i, photo in ipairs(photos) do
        if progress:isCanceled() then
            break
        end
        if DevelopLogic.processPhoto(catalog, photo, offset) then
            processed = processed + 1
        else
            skipped = skipped + 1
        end
        progress:setPortionComplete(i, #photos)
    end
    progress:done()

    LrDialogs.message('Auto Tone + Exposure Offset',
        Helpers.formatSummary(processed, skipped), 'info')
end)

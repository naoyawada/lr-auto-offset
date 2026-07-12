-- Temporary smoke-test stub — replaced with the real flow in Task 4.
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

local Dialog = require 'Dialog'

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()

    local offset = Dialog.askForOffset()
    if offset == nil then
        return
    end

    LrDialogs.message('Auto Tone + Exposure Offset',
        string.format('Would apply Auto Tone %+.2f stops to %d photo(s).',
            offset, #photos), 'info')
end)

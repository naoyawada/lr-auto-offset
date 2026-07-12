-- Temporary smoke-test stub — replaced with the real flow in Task 4.
local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'

LrTasks.startAsyncTask(function()
    local catalog = LrApplication.activeCatalog()
    local photos = catalog:getTargetPhotos()
    LrDialogs.message('Auto Tone + Exposure Offset',
        string.format('Plugin loaded. %d photo(s) selected.', #photos), 'info')
end)

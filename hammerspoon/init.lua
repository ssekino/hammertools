-- Always start in read-only preview mode. No preference changes on startup.
scrollToggle = require('scroll-toggle')

-- Read-only runtime check after the first HID scan. No system settings writes.
hs.timer.doAfter(2, function()
    local f = io.open(hs.configdir .. '/preview-status.txt', 'w')
    if f then
        f:write('Preview enabled: ', tostring(not scrollToggle.enabled), '\n')
        f:write('External mouse detected: ', tostring(scrollToggle.last), '\n')
        f:write('Natural scrolling: ', hs.mouse.scrollDirection(), '\n')
        f:write('Last error: ', tostring(scrollToggle.lastError), '\n')
        f:close()
    end
end)

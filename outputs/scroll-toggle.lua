-- Hammerspoon 1.x (Lua). Loading starts read-only preview mode.
local M = { enabled = false, busy = false, last = nil, repeats = 0 }
local log = hs.logger.new('scrollToggle', 'info')
local match = '{"PrimaryUsagePage":1,"PrimaryUsage":2}'

-- The actual System Settings control is used so the live setting takes effect.
-- English UI required. No defaults-write or undocumented notification tricks.
local function setNatural(wanted)
    local script = [[
        tell application "System Settings"
            activate
            open location "x-apple.systempreferences:com.apple.Trackpad-Settings.extension"
        end tell
        tell application "System Events"
            tell process "System Settings"
                repeat 30 times
                    try
                        set nodes to entire contents of window 1
                        repeat with n in nodes
                            if role of n is "AXButton" or role of n is "AXRadioButton" then
                                if name of n is "Scroll & Zoom" then click n
                            end if
                        end repeat
                        set nodes to entire contents of window 1
                        repeat with n in nodes
                            if role of n is "AXCheckBox" then
                                if name of n is "Natural scrolling" then
                                    if (value of n as integer) is not WANTED then click n
                                    return "applied"
                                end if
                            end if
                        end repeat
                    end try
                    delay 0.2
                end repeat
            end tell
        end tell
        error "Natural scrolling checkbox not found; no fallback writes performed."
    ]]
    script = script:gsub('WANTED', wanted and '1' or '0')
    -- Use a background process: don't block Hammerspoon during UI navigation.
    M.setter = hs.task.new('/usr/bin/osascript', function(code, out, err)
        M.busy = false
        M.setter = nil
        if code ~= 0 or hs.mouse.scrollDirection() ~= (wanted and 'natural' or 'normal') then
            M.enabled = false
            log.e('Setting change failed or could not be verified. Preview restored. ' .. (err or ''))
            hs.alert.show('Scroll toggle stopped: inspect Hammerspoon Console')
        else
            log.i('Verified natural scrolling = ' .. tostring(wanted))
        end
    end, {'-e', script})
    M.busy = true
    if not M.setter:start() then
        M.busy = false
        M.enabled = false
        log.e('Could not launch setting helper; preview restored')
    end
end

function M.scan()
    if M.busy or M.scanner then return end
    M.scanner = hs.task.new('/usr/bin/hidutil', function(code, out, err)
        M.scanner = nil
        if code ~= 0 then
            log.e('Detection failed; leaving scrolling unchanged: ' .. (err or ''))
            M.last = nil; M.repeats = 0
            return
        end
        local external, names = false, {}
        for line in out:gmatch('[^\r\n]+') do
            local ok, d = pcall(hs.json.decode, line)
            if not ok or type(d) ~= 'table' then
                log.e('Unexpected hidutil output; leaving scrolling unchanged')
                M.last = nil; M.repeats = 0
                return
            end
            if d.type == 'device' and d.PrimaryUsagePage == 1 and d.PrimaryUsage == 2 then
                local builtIn = d['Built-In'] == true or d['Built-In'] == 1
                if not builtIn then
                    external = true
                    table.insert(names, (d.Product or 'Unnamed mouse') .. ' [' .. (d.Transport or '?') .. ']')
                end
            end
        end
        if M.last == external then M.repeats = M.repeats + 1
        else
            M.last = external; M.repeats = 1
            log.i('External mouse = ' .. tostring(external) .. ' ' .. table.concat(names, ', '))
        end
        -- Require two consecutive matching samples to avoid brief disconnects.
        if M.enabled and M.repeats >= 2 then
            local wanted = not external
            if hs.mouse.scrollDirection() ~= (wanted and 'natural' or 'normal') then
                setNatural(wanted)
            end
        end
    end, {'list', '--ndjson', '--matching', match})
    if not M.scanner:start() then M.scanner = nil; log.e('Could not start detector') end
end

function M.enable()
    M.enabled = true; M.last = nil; M.repeats = 0
    log.i('Automation enabled explicitly; changes begin after two samples')
    M.scan()
end
function M.disable()
    M.enabled = false
    if M.setter then M.setter:terminate(); M.setter = nil; M.busy = false end
    log.i('Preview mode; current scrolling setting retained')
end
M.timer = hs.timer.doEvery(5, M.scan)
M.scan()
return M

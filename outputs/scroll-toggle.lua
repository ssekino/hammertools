-- Hammerspoon 1.x (Lua). Loading starts read-only preview mode.
local M = { enabled = false, busy = false, last = nil, repeats = 0, lastError = nil }
local log = hs.logger.new('scrollToggle', 'info')
local match = '{"PrimaryUsagePage":1,"PrimaryUsage":2}'

-- Match controls by stable identifiers, with accessible-label fallback.
local function labelMatches(e, label)
    if e:attributeValue('AXTitle') == label or e:attributeValue('AXDescription') == label then return true end
    local title = e:attributeValue('AXTitleUIElement')
    return title and (title:attributeValue('AXValue') == label or title:attributeValue('AXTitle') == label)
end

local function findControl(root, predicate)
    if not root then return nil end
    local queue, index = {root}, 1
    while index <= #queue and index <= 1000 do
        local e = queue[index]; index = index + 1
        local role = e:attributeValue('AXRole')
        if predicate(e, role) then return e end
        -- Sidebar rows cannot contain the Trackpad controls.
        if role ~= 'AXOutline' then
            for _, child in ipairs(e:attributeValue('AXChildren') or {}) do
                queue[#queue + 1] = child
            end
        end
    end
end

function M.setNatural(wanted)
    assert(type(wanted) == 'boolean', 'setNatural requires a boolean')
    if M.busy then return false end
    if not hs.accessibilityState() then
        M.enabled = false
        M.lastError = 'Accessibility access required: System Settings > Privacy & Security > Accessibility > Hammerspoon'
        log.e(M.lastError)
        return false
    end
    M.generation = (M.generation or 0) + 1
    local generation = M.generation
    M.busy = true
    M.lastError = nil
    local deadline = hs.timer.secondsSinceEpoch() + 20
    local pressed = false
    local function finish(err)
        if M.generation ~= generation then return end
        if M.watchdog then M.watchdog:stop(); M.watchdog = nil end
        M.busy = false
        M.navigationTimer = nil
        if err then
            M.enabled = false
            M.lastError = err
            log.e('Scrolling automation paused: ' .. err)
            hs.alert.show('Scroll toggle paused: inspect Hammerspoon Console')
        else
            M.lastVerified = wanted
            log.i('Verified natural scrolling = ' .. tostring(wanted))
        end
    end
    local function navigate()
        if not M.busy or M.generation ~= generation then return end
        if not hs.accessibilityState() then
            finish('Accessibility permission was removed'); return
        end
        local app = hs.application.get('com.apple.systempreferences')
        local root = app and hs.axuielement.applicationElement(app)
        if root then root:setTimeout(0.25) end
        local windows = root and root:attributeValue('AXWindows') or {}
        local window = windows and windows[1]
        local switch = findControl(window, function(e, role)
            return role == 'AXCheckBox' and
                (e:attributeValue('AXIdentifier') == 'NaturalScrollingToggle' or labelMatches(e, 'Natural scrolling'))
        end)
        if switch then
            local value = switch:attributeValue('AXValue')
            if value == (wanted and 1 or 0) then
                if hs.mouse.scrollDirection() == (wanted and 'natural' or 'normal') then finish(); return end
            elseif not pressed and (value == 0 or value == 1) then
                local ok, err = switch:performAction('AXPress')
                if not ok then finish('Could not press Natural scrolling: ' .. tostring(err)); return end
                pressed = true
            end
        else
            local tab = findControl(window, function(e, role)
                return (role == 'AXRadioButton' or role == 'AXButton') and labelMatches(e, 'Scroll & Zoom')
            end)
            if tab and tab:attributeValue('AXValue') ~= 1 then
                local ok, err = tab:performAction('AXPress')
                if not ok then finish('Could not select Scroll & Zoom: ' .. tostring(err)); return end
            end
        end
        if hs.timer.secondsSinceEpoch() >= deadline then
            finish('Could not find or verify Natural scrolling in Trackpad > Scroll & Zoom. Check navigation, language, and permissions.')
            return
        end
        -- Re-read the accessibility tree after tab selection and allow the
        -- live system scrolling direction to catch up after one switch press.
        M.navigationTimer = hs.timer.doAfter(0.25, navigate)
    end
    M.setter = hs.task.new('/usr/bin/osascript', function(code, _, err)
        M.setter = nil
        if not M.busy or M.generation ~= generation then return end
        if code ~= 0 then finish('Could not open Trackpad settings: ' .. (err or '')); return end
        navigate()
    end, {'-e', 'tell application "System Settings"\nactivate\nreveal pane id "com.apple.Trackpad-Settings.extension"\nend tell'})
    M.watchdog = hs.timer.doAfter(25, function()
        if M.generation ~= generation then return end
        if M.setter then M.setter:terminate(); M.setter = nil end
        if M.navigationTimer then M.navigationTimer:stop(); M.navigationTimer = nil end
        finish('System Settings navigation timed out')
    end)
    if not M.setter:start() then finish('Could not launch Trackpad navigation'); return false end
    return true
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
                M.setNatural(wanted)
            end
        end
    end, {'list', '--ndjson', '--matching', match})
    if not M.scanner:start() then M.scanner = nil; log.e('Could not start detector') end
end

function M.enable()
    M.lastError = nil
    M.enabled = true; M.last = nil; M.repeats = 0
    log.i('Automation enabled explicitly; changes begin after two samples')
    M.scan()
end
function M.disable()
    M.generation = (M.generation or 0) + 1
    M.enabled = false
    if M.watchdog then M.watchdog:stop(); M.watchdog = nil end
    if M.navigationTimer then M.navigationTimer:stop(); M.navigationTimer = nil end
    if M.setter then M.setter:terminate(); M.setter = nil end
    M.busy = false
    log.i('Preview mode; current scrolling setting retained')
end
M.timer = hs.timer.doEvery(5, M.scan)
M.scan()
return M

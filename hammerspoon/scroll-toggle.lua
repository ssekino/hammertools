-- Hammerspoon 1.x (Lua). Loading starts read-only preview mode.
local M = { enabled = false, busy = false, last = nil, repeats = 0, lastError = nil }
local log = hs.logger.new('scrollToggle', 'info')
local match = '{"PrimaryUsagePage":1,"PrimaryUsage":2}'

-- Read fresh Accessibility elements on every step; never keep controls across
-- pane changes or a System Settings process restart.
local function attr(e, key)
    if not e then return nil end
    local ok, value, err = pcall(e.attributeValue, e, key)
    if ok then return value, err end
    return nil, tostring(value)
end

local function labelMatches(e, label)
    if attr(e, 'AXTitle') == label or attr(e, 'AXDescription') == label then return true end
    local title = attr(e, 'AXTitleUIElement')
    return title and (attr(title, 'AXValue') == label or attr(title, 'AXTitle') == label)
end

local function walk(root, predicate, includeSidebar)
    if not root then return nil end
    local queue, index = {root}, 1
    while index <= #queue and index <= 600 do
        local e = queue[index]; index = index + 1
        local role = attr(e, 'AXRole')
        if predicate(e, role, index) then return e end
        if includeSidebar or role ~= 'AXOutline' then
            for _, child in ipairs(attr(e, 'AXChildren') or {}) do queue[#queue + 1] = child end
        end
    end
end

local function settingsUI()
    local app = hs.application.get('com.apple.systempreferences')
    if not app then return nil, nil, {}, nil end
    local root = hs.axuielement.applicationElement(app)
    if not root then return app, nil, {}, nil end
    root:setTimeout(0.5)
    -- AXWindows can be empty during a cold launch. Main/focused windows can
    -- still be usable, and must be tried before waiting for the window list.
    local listed, listError = attr(root, 'AXWindows')
    local windows = {}
    local main, mainError = attr(root, 'AXMainWindow')
    local focused, focusError = attr(root, 'AXFocusedWindow')
    local function add(window)
        if not window then return end
        for _, known in ipairs(windows) do if known == window then return end end
        windows[#windows + 1] = window
    end
    add(main); add(focused)
    for _, window in ipairs(listed or {}) do add(window) end
    return app, main or focused or windows[1], windows, root, {
        listedCount = listed and #listed or 0, mainAvailable = main ~= nil,
        focusedAvailable = focused ~= nil, windowListError = listError,
        mainWindowError = mainError, focusedWindowError = focusError,
    }
end

local function snapshot()
    local app, _, windows, root, discovery = settingsUI()
    local result = {
        time = os.date('!%Y-%m-%dT%H:%M:%SZ'), accessibility = hs.accessibilityState(),
        direction = hs.mouse.scrollDirection(), windows = {},
        pid = app and app:pid(), frontmost = attr(root, 'AXFrontmost'), windowDiscovery = discovery,
        locked = (hs.caffeinate.sessionProperties() or {}).CGSSessionScreenIsLocked == true,
    }
    for wi, window in ipairs(windows) do
        local data = {title = attr(window, 'AXTitle'), identifier = attr(window, 'AXIdentifier'), controls = {}}
        result.windows[wi] = data
        walk(window, function(e, role, index)
            local node = {index = index, role = role, title = attr(e, 'AXTitle'),
                description = attr(e, 'AXDescription'), identifier = attr(e, 'AXIdentifier'),
                enabled = attr(e, 'AXEnabled')}
            local label = attr(e, 'AXTitleUIElement')
            node.label = attr(label, 'AXValue') or attr(label, 'AXTitle')
            -- Record control state, but never record editable field contents.
            if role == 'AXRadioButton' or role == 'AXCheckBox' or role == 'AXRow' then
                node.value = attr(e, 'AXValue'); node.selected = attr(e, 'AXSelected')
            elseif role == 'AXStaticText' then node.label = attr(e, 'AXValue') end
            data.controls[#data.controls + 1] = node
            return false
        end, true)
    end
    return result
end

local function writeDiagnostic(attempt, failed)
    local dir = hs.configdir .. '/scroll-toggle-diagnostics'
    if not hs.fs.attributes(dir) then hs.fs.mkdir(dir) end
    local ok, result = pcall(hs.json.write, attempt, dir .. '/latest-attempt.json', true, true)
    if not ok or not result then log.e('Could not write navigation diagnostics'); return end
    if failed then
        hs.json.write(attempt, dir .. '/last-failure.json', true, true)
        M.lastDiagnostic = dir .. '/last-failure.json'
        log.e('Failure pane and controls saved to ' .. M.lastDiagnostic)
    end
end

function M.captureDiagnostics(reason)
    local result = {reason = reason or 'manual capture', final = snapshot()}
    writeDiagnostic(result, true)
    return result
end

function M.setNatural(wanted)
    assert(type(wanted) == 'boolean', 'setNatural requires a boolean')
    if M.busy then return false end
    if not hs.accessibilityState() then
        M.enabled = false
        M.lastError = 'Accessibility access required: System Settings > Privacy & Security > Accessibility > Hammerspoon'
        M.captureDiagnostics(M.lastError)
        log.e(M.lastError)
        return false
    end
    if (hs.caffeinate.sessionProperties() or {}).CGSSessionScreenIsLocked then
        M.retryAt = hs.timer.secondsSinceEpoch() + 5
        return false -- A locked session cannot safely navigate Settings.
    end
    M.generation = (M.generation or 0) + 1
    local generation = M.generation
    local started = hs.timer.secondsSinceEpoch()
    local deadline = started + 35
    local attempt = {wanted = wanted, initial = snapshot(), steps = {}}
    M.busy = true; M.lastError = nil
    local phase, stable, presses, lastPress = 'opening', 0, 0, 0
    local reveals, lastReveal, paneRequested = 0, 0, false
    local function note(stage, detail)
        phase = stage; M.phase = stage
        attempt.steps[#attempt.steps + 1] = {seconds = hs.timer.secondsSinceEpoch() - started, stage = stage, detail = detail}
    end
    local function finish(err, permanent)
        if M.generation ~= generation then return end
        if M.watchdog then M.watchdog:stop(); M.watchdog = nil end
        if M.navigationTimer then M.navigationTimer:stop(); M.navigationTimer = nil end
        if M.setter then M.setter:terminate(); M.setter = nil end
        M.busy = false
        attempt.error = err; attempt.phase = phase; attempt.presses = presses
        attempt.final = snapshot()
        writeDiagnostic(attempt, err ~= nil)
        if err then
            M.lastError = err
            M.failures = (M.failures or 0) + 1
            if permanent or M.failures >= 3 then
                M.enabled = false
                log.e('Scrolling automation paused: ' .. err)
                hs.alert.show('Scroll toggle paused: inspect Hammerspoon Console')
            else
                M.retryAt = hs.timer.secondsSinceEpoch() + 30
                log.e('Navigation failed; retrying after 30 seconds: ' .. err)
            end
        else
            M.lastVerified = wanted; M.failures = 0; M.retryAt = nil
            log.i('Verified natural scrolling = ' .. tostring(wanted))
        end
    end
    local function current() return M.busy and M.generation == generation end
    local function task(args, callback)
        if M.setter then return end
        M.setter = hs.task.new(args[1], function(code, out, err)
            if not current() then return end
            M.setter = nil
            callback(code, out, err)
        end, {table.unpack(args, 2)})
        if not M.setter:start() then M.setter = nil; finish('Could not start Settings navigation', true) end
    end
    local function reveal()
        reveals = reveals + 1; lastReveal = hs.timer.secondsSinceEpoch(); stable = 0
        note('opening Trackpad pane', 'request ' .. reveals)
        task({'/usr/bin/osascript', '-e', 'tell application "System Settings" to reveal pane id "com.apple.Trackpad-Settings.extension"'}, function(code, _, err)
            if code ~= 0 then finish('Could not open Trackpad pane: ' .. (err or ''), true)
            else paneRequested = true; note('waiting for Trackpad pane') end
        end)
    end
    local navigate
    navigate = function()
        if not current() then return end
        local now = hs.timer.secondsSinceEpoch()
        if not hs.accessibilityState() then finish('Accessibility permission was removed', true); return end
        if (hs.caffeinate.sessionProperties() or {}).CGSSessionScreenIsLocked then
            finish('Session locked while navigating Settings'); return
        end
        local app, window = settingsUI()
        local switch = walk(window, function(e, role)
            return role == 'AXCheckBox' and
                (attr(e, 'AXIdentifier') == 'NaturalScrollingToggle' or labelMatches(e, 'Natural scrolling'))
        end)
        local tab = walk(window, function(e, role)
            return (role == 'AXRadioButton' or role == 'AXButton') and labelMatches(e, 'Scroll & Zoom')
        end)
        if not M.setter then
            if not app or not window then
                stable = 0
                if now - lastReveal >= 5 and reveals < 3 then
                    note('opening Settings window')
                    lastReveal = now
                    task({'/usr/bin/open', '-b', 'com.apple.systempreferences'}, function(code, _, err)
                        if code ~= 0 then finish('Could not open System Settings: ' .. (err or '')) end
                    end)
                end
            elseif switch and attr(switch, 'AXEnabled') ~= false then
                -- Require the pane request to finish, and two fresh reads of
                -- its controls. Cold-launch controls can initially be stale.
                stable = stable + 1
                local value = attr(switch, 'AXValue')
                if value == (wanted and 1 or 0) then
                    note('verifying live direction', 'checkbox=' .. tostring(value))
                    if hs.mouse.scrollDirection() == (wanted and 'natural' or 'normal') then finish(); return end
                elseif stable >= 2 and presses < 3 and (presses == 0 or now - lastPress >= 2) and (value == 0 or value == 1) then
                    presses = presses + 1; lastPress = now
                    note('pressing Natural scrolling', 'press=' .. presses .. ', value=' .. value)
                    local ok, err = switch:performAction('AXPress')
                    if not ok then note('switch press failed', tostring(err)) end
                    stable = 0
                end
            elseif tab then
                stable = 0
                if attr(tab, 'AXValue') ~= 1 and now - lastPress >= 1 then
                    lastPress = now; note('selecting Scroll & Zoom')
                    local ok, err = tab:performAction('AXPress')
                    if not ok then note('tab press failed', tostring(err)) end
                end
            elseif not paneRequested or (now - lastReveal >= 5 and reveals < 3) then
                reveal()
            end
        end
        if now >= deadline then finish('Timed out at ' .. phase .. '; exact pane and controls saved'); return end
        M.navigationTimer = hs.timer.doAfter(0.5, function()
            local ok, err = pcall(navigate)
            if not ok then finish('Navigation error: ' .. tostring(err)) end
        end)
    end
    M.watchdog = hs.timer.doAfter(40, function() finish('System Settings operation timed out at ' .. phase) end)
    -- Launch first, then reveal only after a main/focused window exists.
    -- Sending reveal during cold startup can be lost while General loads.
    lastReveal = started
    task({'/usr/bin/open', '-b', 'com.apple.systempreferences'}, function(code, _, err)
        if code ~= 0 then finish('Could not launch System Settings: ' .. (err or '')) end
    end)
    M.navigationTimer = hs.timer.doAfter(0.5, navigate)
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
        if M.enabled and M.repeats >= 2 and (not M.retryAt or hs.timer.secondsSinceEpoch() >= M.retryAt) then
            local wanted = not external
            if hs.mouse.scrollDirection() ~= (wanted and 'natural' or 'normal') then
                M.setNatural(wanted)
            end
        end
    end, {'list', '--ndjson', '--matching', match})
    if not M.scanner:start() then M.scanner = nil; log.e('Could not start detector') end
end

function M.enable()
    M.lastError = nil; M.retryAt = nil; M.failures = 0
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

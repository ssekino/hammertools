-- Run with Lua 5.4, or dofile this file in Hammerspoon Console.
-- All timers, processes, Accessibility elements and file writes are mocked.
local source = debug.getinfo(1, 'S').source:sub(2)
local module = source:gsub('tests/scroll%-toggle%-test.lua$', 'hammerspoon/scroll-toggle.lua')
local results = {}
local function scenario(name, options, check)
    local now, timers, writes, launches, reveals, clicks = 100, {}, {}, 0, 0, 0
    local direction, exists, pane = 'normal', options.open or false, options.pane or 'General'
    local switch, tab, window, root, app
    local function element(attributes, action)
        return {attributeValue=function(_,key) return attributes[key] end,
            setTimeout=function() end,
            performAction=function(_,name) assert(name=='AXPress'); return action() end,
            attrs=attributes}
    end
    switch=element({AXRole='AXCheckBox',AXIdentifier='NaturalScrollingToggle',AXEnabled=true,AXValue=0},function()
        clicks=clicks+1
        if clicks > (options.ignoredPresses or 0) then
            switch.attrs.AXValue=1-switch.attrs.AXValue
            direction=switch.attrs.AXValue==1 and 'natural' or 'normal'
        end
        return switch
    end)
    tab=element({AXRole='AXRadioButton',AXDescription='Scroll & Zoom',AXValue=0},function()
        tab.attrs.AXValue=1
        window.attrs.AXChildren={tab,switch}
        return tab
    end)
    window=element({AXRole='AXWindow',AXTitle=pane,AXIdentifier='main',AXChildren={}})
    root=element({AXRole='AXApplication',AXWindows={},AXMainWindow=window})
    app={pid=function() return 123 end}
    if pane=='Trackpad' and not options.missingControls then window.attrs.AXChildren={tab} end
    if options.noMain then root.attrs.AXMainWindow=nil;root.attrs.AXFocusedWindow=window end
    local function schedule(delay,fn,interval)
        local t={at=now+delay,fn=fn,interval=interval,active=true}
        function t:stop() self.active=false end
        timers[#timers+1]=t
        return t
    end
    local fake={configdir='/mock',logger={new=function() return {i=function()end,e=function()end} end},
        accessibilityState=function()return not options.noPermission end,
        application={get=function()if exists then return app end end},
        axuielement={applicationElement=function()return root end},
        mouse={scrollDirection=function()return direction end},
        caffeinate={sessionProperties=function()return {CGSSessionScreenIsLocked=options.locked or false} end},
        alert={show=function()end},fs={attributes=function()return true end,mkdir=function()end},
        json={write=function(data,path)writes[path]=data;return true end,decode=function()return {}end},
        timer={secondsSinceEpoch=function()return now end,
            doAfter=function(delay,fn)return schedule(delay,fn)end,
            doEvery=function(delay,fn)return schedule(delay,fn,delay)end},task={}}
    function fake.task.new(binary,callback,args)
        local task={active=true}
        function task:start()
            if binary=='/usr/bin/hidutil' then schedule(0.01,function()if self.active then callback(0,'','')end end)
            elseif binary=='/usr/bin/open' then
                launches=launches+1
                schedule(0.1,function()if self.active then callback(0,'','')end end)
                schedule(1,function()if self.active then exists=true end end)
            else
                assert(binary=='/usr/bin/osascript')
                assert(exists,'Reveal was sent before the app/window existed')
                reveals=reveals+1
                schedule(0.1,function()
                    if not self.active then return end
                    window.attrs.AXTitle='Trackpad'
                    if not options.missingControls then window.attrs.AXChildren={tab} end
                    callback(0,'','')
                end)
            end
            return self
        end
        function task:terminate() self.active=false end
        return task
    end
    local env=setmetatable({hs=fake},{__index=_G})
    local m=assert(loadfile(module,'t',env))()
    m.timer:stop()
    local started=m.setNatural(true)
    if options.cancel then m.disable() end
    local count=0
    while count<1000 do
        local nextTimer
        for _,t in ipairs(timers)do if t.active and(not nextTimer or t.at<nextTimer.at)then nextTimer=t end end
        if not nextTimer or nextTimer.at>145 then break end
        now=nextTimer.at
        if nextTimer.interval then nextTimer.at=now+nextTimer.interval else nextTimer.active=false end
        nextTimer.fn();count=count+1
    end
    check({module=m,started=started,direction=direction,writes=writes,launches=launches,reveals=reveals,clicks=clicks})
    results[#results+1]=name
end
local function passed(x)
    assert(not x.module.busy and not x.module.lastError)
    assert(x.direction=='natural' and x.module.lastVerified==true)
end
scenario('cold launch, empty AXWindows, wait before reveal',{},function(x)passed(x);assert(x.reveals>=1)end)
scenario('focused-window fallback and nameless tab',{open=true,pane='Trackpad',noMain=true},function(x)
    passed(x)
    local d=assert(x.writes['/mock/scroll-toggle-diagnostics/latest-attempt.json'])
    assert(d.final.windowDiscovery.listedCount==0 and d.final.windowDiscovery.focusedAvailable)
end)
scenario('acknowledged but ignored switch press is retried',{open=true,pane='Trackpad',ignoredPresses=1},function(x)passed(x);assert(x.clicks==2)end)
scenario('missing controls preserve pane and control evidence',{open=true,missingControls=true},function(x)
    assert(x.module.lastError and not x.module.busy)
    local d=assert(x.writes['/mock/scroll-toggle-diagnostics/last-failure.json'])
    assert(d.final.windows[1].title=='Trackpad' and d.phase and #d.steps>0)
    assert(x.clicks==0)
end)
scenario('ignored presses stop at three and preserve switch value',{open=true,pane='Trackpad',ignoredPresses=99},function(x)
    assert(x.clicks==3 and x.module.lastError and not x.module.busy)
    local d=assert(x.writes['/mock/scroll-toggle-diagnostics/last-failure.json'])
    local found=false
    for _,c in ipairs(d.final.windows[1].controls)do
        if c.identifier=='NaturalScrollingToggle' then assert(c.value==0);found=true end
    end
    assert(found)
end)
scenario('permission failure does not launch Settings',{noPermission=true},function(x)
    assert(not x.started and x.launches==0 and x.module.lastError:match('Accessibility'))
    assert(x.writes['/mock/scroll-toggle-diagnostics/last-failure.json'])
end)
scenario('locked session defers without disabling',{locked=true},function(x)
    assert(not x.started and x.launches==0 and not x.module.lastError and x.module.retryAt)
end)
scenario('cancel ignores stale launch callback',{cancel=true},function(x)
    assert(not x.module.busy and not x.module.enabled and x.clicks==0 and not x.module.lastError)
end)
return 'Passed '..#results..' regression tests: '..table.concat(results,'; ')

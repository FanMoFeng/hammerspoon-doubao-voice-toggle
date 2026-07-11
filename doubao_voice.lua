-- Hammerspoon Doubao Voice Toggle
-- 右 Command 第一次单击：切换豆包输入法并启动语音输入。
-- 右 Command 第二次单击：停止语音输入并恢复之前的输入法。
--
-- 使用前请在豆包输入法中将“单击左 Option”设为语音输入快捷键。

local TARGET_METHOD = "豆包输入法"
local RIGHT_COMMAND_KEYCODE = 54

local SWITCH_TIMEOUT = 3.0
local SWITCH_POLL_INTERVAL = 0.05
local DOUBAO_READY_DELAY = 0.35
local OPTION_HOLD_TIME = 0.06
local MIN_OPTION_INTERVAL = 1.10
local RESTORE_DELAY = 0.80
local RIGHT_COMMAND_DEBOUNCE = 0.20
local VOICE_START_GUARD = 1.50

local log = hs.logger.new("RightCmdIME", "debug")

-- A reload must stop every watcher/timer created by the previous version.
if _G.rightCmdWatcher then
    _G.rightCmdWatcher:stop()
    _G.rightCmdWatcher = nil
end

if _G.rightCmdVoiceController then
    local old = _G.rightCmdVoiceController
    if old.watcher then old.watcher:stop() end
    if old.timers then
        for _, timer in pairs(old.timers) do
            if timer then timer:stop() end
        end
    end
    -- Avoid leaving Option logically held if a reload happened mid-tap.
    hs.eventtap.event.newKeyEvent(hs.keycodes.map.alt, false):post()
end

local controller = {
    state = "idle", -- idle, switching, listening, stopping
    rightCommandDown = false,
    previousSourceID = nil,
    targetSourceID = nil,
    lastOptionAt = 0,
    lastToggleAt = 0,
    listeningSince = 0,
    generation = 0,
    timers = {},
    watcher = nil,
}
_G.rightCmdVoiceController = controller

local function monotonicSeconds()
    return hs.timer.absoluteTime() / 1000000000
end

local function cancelTimer(name)
    local timer = controller.timers[name]
    if timer then
        timer:stop()
        controller.timers[name] = nil
    end
end

local function setTimer(name, delay, callback)
    cancelTimer(name)
    local timer
    timer = hs.timer.doAfter(delay, function()
        if controller.timers[name] == timer then
            controller.timers[name] = nil
        end
        callback()
    end)
    controller.timers[name] = timer
end

local function targetIsActive()
    if controller.targetSourceID and
       hs.keycodes.currentSourceID() == controller.targetSourceID then
        return true
    end
    return hs.keycodes.currentMethod() == TARGET_METHOD
end

local function requestTargetInputSource()
    if targetIsActive() then return true end

    if controller.targetSourceID then
        local ok = hs.keycodes.currentSourceID(controller.targetSourceID)
        log.df("使用 source ID 切换豆包，结果=%s", tostring(ok))
        if ok then return true end
    end

    local ok = hs.keycodes.setMethod(TARGET_METHOD)
    log.df("使用名称切换豆包，结果=%s", tostring(ok))
    return ok
end

local function waitForTarget(token, onReady, onTimeout)
    local deadline = monotonicSeconds() + SWITCH_TIMEOUT

    local function check()
        if token ~= controller.generation then return end

        if targetIsActive() then
            controller.targetSourceID = hs.keycodes.currentSourceID()
            log.df("豆包输入法已经生效，sourceID=%s",
                tostring(controller.targetSourceID))
            setTimer("ready", DOUBAO_READY_DELAY, function()
                if token == controller.generation then onReady() end
            end)
            return
        end

        if monotonicSeconds() >= deadline then
            onTimeout()
            return
        end

        setTimer("poll", SWITCH_POLL_INTERVAL, check)
    end

    check()
end

local function tapLeftOptionSafely(token, callback)
    local elapsed = monotonicSeconds() - controller.lastOptionAt
    local wait = math.max(0, MIN_OPTION_INTERVAL - elapsed)

    setTimer("optionDown", wait, function()
        if token ~= controller.generation then return end

        controller.lastOptionAt = monotonicSeconds()
        log.df("单击左 Option，state=%s", controller.state)
        hs.eventtap.event.newKeyEvent(hs.keycodes.map.alt, true):post()

        setTimer("optionUp", OPTION_HOLD_TIME, function()
            hs.eventtap.event.newKeyEvent(hs.keycodes.map.alt, false):post()
            if token == controller.generation then callback() end
        end)
    end)
end

local function failAndReset(message)
    controller.generation = controller.generation + 1
    controller.state = "idle"
    if controller.previousSourceID then
        hs.keycodes.currentSourceID(controller.previousSourceID)
    end
    controller.previousSourceID = nil
    hs.alert.show(message)
    log.e(message)
end

local function startVoiceInput()
    if controller.state ~= "idle" then return end

    controller.state = "switching"
    controller.generation = controller.generation + 1
    local token = controller.generation
    controller.previousSourceID = hs.keycodes.currentSourceID()

    log.df("开始：原输入源=%s", tostring(controller.previousSourceID))

    if not requestTargetInputSource() then
        failAndReset("无法切换到豆包输入法")
        return
    end

    waitForTarget(token, function()
        tapLeftOptionSafely(token, function()
            controller.state = "listening"
            controller.listeningSince = monotonicSeconds()
            log.i("豆包语音输入已启动")
        end)
    end, function()
        failAndReset("等待豆包输入法超时")
    end)
end

local function finishStop(token)
    tapLeftOptionSafely(token, function()
        log.i("豆包语音输入已停止")

        setTimer("restore", RESTORE_DELAY, function()
            if token ~= controller.generation then return end

            local sourceID = controller.previousSourceID
            controller.previousSourceID = nil
            if sourceID then
                local ok = hs.keycodes.currentSourceID(sourceID)
                log.df("恢复原输入源=%s，结果=%s",
                    tostring(sourceID), tostring(ok))
            end
            controller.state = "idle"
        end)
    end)
end

local function stopVoiceInput()
    if controller.state ~= "listening" then return end

    controller.state = "stopping"
    controller.generation = controller.generation + 1
    local token = controller.generation

    -- Normally Doubao is still active. If the user changed input methods
    -- manually, return to Doubao before sending its stop shortcut.
    if targetIsActive() then
        finishStop(token)
        return
    end

    if not requestTargetInputSource() then
        failAndReset("停止语音时无法切回豆包输入法")
        return
    end

    waitForTarget(token, function()
        finishStop(token)
    end, function()
        failAndReset("停止语音时等待豆包输入法超时")
    end)
end

local function toggleVoiceInput()
    if controller.state == "idle" then
        startVoiceInput()
    elseif controller.state == "listening" then
        local listeningFor = monotonicSeconds() - controller.listeningSince
        if listeningFor < VOICE_START_GUARD then
            log.df("忽略启动保护期内的停止请求，已启动 %.2f 秒", listeningFor)
        else
            stopVoiceInput()
        end
    else
        -- Ignore presses while switching/stopping, preventing Option double taps.
        log.df("忽略重复按键，当前状态=%s", controller.state)
    end
end

local function handleRightCommand(event)
    if event:getKeyCode() ~= RIGHT_COMMAND_KEYCODE then return false end

    local commandFlag = event:getFlags().cmd == true
    log.df("右 Command 事件：cmd=%s, recordedDown=%s, state=%s",
        tostring(commandFlag), tostring(controller.rightCommandDown),
        controller.state)

    if not controller.rightCommandDown and commandFlag then
        controller.rightCommandDown = true
        return true
    end

    -- Only a real cmd=false event may release Right Command. Duplicate
    -- cmd=true modifier events are ignored instead of being treated as a
    -- release, which prevents one physical press from becoming two toggles.
    if controller.rightCommandDown and not commandFlag then
        controller.rightCommandDown = false
        local now = monotonicSeconds()
        if now - controller.lastToggleAt >= RIGHT_COMMAND_DEBOUNCE then
            controller.lastToggleAt = now
            toggleVoiceInput()
        end
        return true
    end

    log.df("忽略重复或游离的右 Command 修饰键事件")
    return true
end

local function safeHandler(event)
    local ok, result = xpcall(function()
        return handleRightCommand(event)
    end, debug.traceback)

    if not ok then
        log.ef("键盘监听出错：\n%s", tostring(result))
        controller.rightCommandDown = false
        return true
    end
    return result
end

controller.watcher = hs.eventtap.new(
    {hs.eventtap.event.types.flagsChanged},
    safeHandler
)
controller.watcher:start()

hs.alert.show("右 Command 豆包语音开关已启动")
log.i("脚本已启动：等待输入法确认，并启用 Option 防双击")

return controller

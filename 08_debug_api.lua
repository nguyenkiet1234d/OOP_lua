-- ============================================================
-- Psych Object API — module: PsychObject.Debug public table + shutdownDebug
-- Đây là 1 phần được dofile() từ init.lua, KHÔNG dofile file này riêng lẻ.
-- ============================================================
-- ============================================================
-- Localized natives (perf): local access nhanh hơn tra cứu _G.
-- File này là 1 phần của Psych Object API (được dofile từ init.lua),
-- các bảng/hàm KHÔNG có "local" ở file khác (PsychObject, ReferenceResolver,
-- objectProxy, debugXxx, ...) là biến toàn cục dùng CHUNG giữa các file.
-- ============================================================
local type, tostring, pairs, ipairs = type, tostring, pairs, ipairs
local setmetatable, assert, print = setmetatable, assert, print
local string, table, os, io = string, table, os, io
local sFormat, sGmatch = string.format, string.gmatch
local tInsert, tRemove, tConcat = table.insert, table.remove, table.concat

local getProperty, setProperty, callMethod = getProperty, setProperty, callMethod
local getPropertyFromClass, setPropertyFromClass, callMethodFromClass = getPropertyFromClass, setPropertyFromClass, callMethodFromClass
local getPropertyFromGroup, setPropertyFromGroup = getPropertyFromGroup, setPropertyFromGroup
local debugPrint = debugPrint

local makeLuaSprite, makeAnimatedLuaSprite, makeGraphic = makeLuaSprite, makeAnimatedLuaSprite, makeGraphic
local addLuaSprite, removeLuaSprite = addLuaSprite, removeLuaSprite
local addAnimationByPrefix, addAnimationByIndices, playAnim = addAnimationByPrefix, addAnimationByIndices, playAnim
local setScrollFactor, scaleObject, setObjectCamera, setBlendMode, screenCenter = setScrollFactor, scaleObject, setObjectCamera, setBlendMode, screenCenter

local setSpriteShader, removeSpriteShader, initLuaShader = setSpriteShader, removeSpriteShader, initLuaShader
local setShaderFloat, setShaderInt, setShaderBool = setShaderFloat, setShaderInt, setShaderBool
local setShaderFloatArray, setShaderIntArray, setShaderBoolArray = setShaderFloatArray, setShaderIntArray, setShaderBoolArray
local setShaderSampler2D = setShaderSampler2D

local makeLuaText, addLuaText, removeLuaText = makeLuaText, addLuaText, removeLuaText
local setTextString, setTextSize, setTextWidth, setTextHeight = setTextString, setTextSize, setTextWidth, setTextHeight
local setTextColor, setTextFont, setTextBorder, setTextAlignment = setTextColor, setTextFont, setTextBorder, setTextAlignment

local cameraSetTarget, getMouseX, getMouseY = cameraSetTarget, getMouseX, getMouseY
local noteTweenX, noteTweenY, noteTweenAngle, noteTweenAlpha, noteTweenDirection = noteTweenX, noteTweenY, noteTweenAngle, noteTweenAlpha, noteTweenDirection

local doTweenX, doTweenY, doTweenAngle, doTweenAlpha = doTweenX, doTweenY, doTweenAngle, doTweenAlpha
local doTweenZoom, doTweenColor, cancelTween = doTweenZoom, doTweenColor, cancelTween
local runTimer, cancelTimer = runTimer, cancelTimer
local playSound, pauseSound, resumeSound, stopSound, playMusic = playSound, pauseSound, resumeSound, stopSound, playMusic

local runHaxeCode = runHaxeCode

PsychObject.Debug = {
    enable = function(value)
        debugEnabled = value ~= false
        if debugEnabled then
            debugWrite('info', 'debug', DEBUG_CREDIT, 'FFD700')
            debugWrite('info', 'debug', 'debug enabled', '55AAFF', {
                level = debugLevel,
                mode = debugMode,
                history = debugHistoryLimit
            })
        end
        return debugEnabled
    end,

    isEnabled = function()
        return debugEnabled
    end,

    log = function(level, message, context, category)
        return debugWrite(level, category or 'user', message, 'FFFFFF', context)
    end,

    trace = function(message, context, category)
        return debugWrite('trace', category or 'user', message, 'AAAAAA', context)
    end,

    debug = function(message, context, category)
        return debugWrite('debug', category or 'user', message, 'CCCCCC', context)
    end,

    info = function(message, context, category)
        return debugWrite('info', category or 'user', message, 'FFFFFF', context)
    end,

    warn = function(message, context, category)
        return debugWrite('warn', category or 'user', message, 'FFAA00', context)
    end,

    error = function(message, context, category)
        return debugWrite('error', category or 'user', message, 'FF5555', context)
    end,

    mode = function(value)
        assert(
            value == 'console' or value == 'file' or value == 'both',
            "Debug mode must be 'console', 'file', or 'both'"
        )
        debugMode = value
        if debugEnabled then
            debugWrite('info', 'config', 'output mode = ' .. value, '55AAFF')
        end
        return debugMode
    end,

    getMode = function()
        return debugMode
    end,

    level = function(value)
        if value == nil then return debugLevel end
        value = debugNormalizeLevel(value)
        debugLevel = value
        if debugEnabled and value ~= 'off' then
            debugWrite('info', 'config', 'log level = ' .. value, '55AAFF')
        end
        return debugLevel
    end,

    getLevel = function()
        return debugLevel
    end,

    category = function(value)
        if value == nil then return debugCategoryFilter end

        if type(value) == 'string' then
            local filter = {}
            for item in string.gmatch(value, '[^,%s]+') do
                filter[item] = true
            end
            debugCategoryFilter = filter
        elseif type(value) == 'table' then
            debugCategoryFilter = {}
            for key, item in pairs(value) do
                if item == true then debugCategoryFilter[tostring(key)] = true end
                if type(key) == 'number' and type(item) == 'string' then
                    debugCategoryFilter[item] = true
                end
            end
        else
            error('Debug.category expects string or table')
        end

        return debugCategoryFilter
    end,

    clearCategory = function()
        debugCategoryFilter = nil
        return true
    end,

    caller = function(value)
        if value == nil then return debugCallerEnabled end
        debugCallerEnabled = value == true
        return debugCallerEnabled
    end,

    timestamp = function(value)
        if value == nil then return debugTimestampEnabled end
        debugTimestampEnabled = value ~= false
        return debugTimestampEnabled
    end,

    step = function(value)
        if value == nil then return debugStepEnabled end
        debugStepEnabled = value ~= false
        return debugStepEnabled
    end,

    context = function(value)
        if value == nil then return debugContextEnabled end
        debugContextEnabled = value ~= false
        return debugContextEnabled
    end,

    history = function(limit)
        if limit == nil then return debugHistory end

        limit = math.max(0, math.floor(tonumber(limit) or debugHistoryLimit))
        local result = {}
        local startIndex = math.max(1, #debugHistory - limit + 1)

        for i = startIndex, #debugHistory do
            tInsert(result, debugHistory[i])
        end

        return result
    end,

    last = function()
        return debugHistory[#debugHistory]
    end,

    clear = function()
        debugHistory = {}
        return true
    end,

    stats = function()
        local result = {}
        for key, value in pairs(debugStats) do
            if key == 'byCategory' then
                result[key] = {}
                for category, count in pairs(value) do
                    result[key][category] = count
                end
            else
                result[key] = value
            end
        end
        return result
    end,

    resetStats = function()
        debugStats = {
            total = 0,
            trace = 0,
            debug = 0,
            info = 0,
            warn = 0,
            error = 0,
            failed = 0,
            byCategory = {}
        }
        return true
    end,

    profileStart = function(name, category)
        if not debugEnabled then return false end
        return debugStartProfile(name, category)
    end,

    profileStop = function(name)
        if not debugEnabled then return nil end
        return debugStopProfile(name)
    end,

    profiles = function()
        local result = {}
        for name, profile in pairs(debugProfiles) do
            result[name] = {
                name = profile.name,
                category = profile.category,
                calls = profile.calls,
                total = profile.total,
                average = profile.calls > 0 and (profile.total / profile.calls) or 0,
                min = profile.min,
                max = profile.max,
                last = profile.last
            }
        end
        return result
    end,

    profileClear = function()
        debugProfiles = {}
        debugActiveProfiles = {}
        return true
    end,

    dump = function(value)
        return debugValue(value)
    end,

    assert = function(condition, message, context)
        if condition then return true end
        debugWrite('error', 'assert', message or 'Debug assertion failed', 'FF5555', context)
        return false
    end,

    mute = function(value)
        if value == nil then return debugMuted end
        debugMuted = value == true
        return debugMuted
    end,

    getVersion = function()
        return debugVersion
    end,

    uptime = function()
        return os.clock() - debugStartedAt
    end,

    flush = function()
        if debugFileHandle then
            local ok = pcall(function() debugFileHandle:flush() end)
            return ok
        end
        return true
    end,

    file = function(path, clear)
        assert(type(path) == 'string' and path ~= '', 'Debug log path must be a non-empty string')
        closeDebugFile()
        debugLogPath = path

        if clear then
            local file = io.open(debugLogPath, 'w')
            if file then file:close() end
        end

        return debugLogPath
    end
}

function PsychObject.shutdownDebug()
    closeDebugFile()
    debugEnabled = false
    return true
end

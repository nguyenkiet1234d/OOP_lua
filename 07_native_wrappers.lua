-- ============================================================
-- Psych Object API — module: Camera/Note/Tween/Timer/Sound/Shader/Haxe wrappers
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

---@class PsychCameraAPI
---@field game PsychCamProxy camera game
---@field hud PsychCamProxy camera HUD
---@field other PsychCamProxy camera khác
---@field follow PsychProxy proxy camFollow
---@field followPos PsychProxy proxy camFollowPos
---@field target fun(x:number, y:number): any đặt mục tiêu camera
---@field mouseX fun(camera?:string): number lấy X chuột
---@field mouseY fun(camera?:string): number lấy Y chuột
-- Camera proxies và các wrapper native dùng chung cho toàn bộ API.
PsychObject.Camera = {
    game = objectProxy('camGame', {scroll = {}, scale = {}}, createCamFilterHelpers('camGame')),
    hud = objectProxy('camHUD', {scroll = {}, scale = {}}, createCamFilterHelpers('camHUD')),
    other = objectProxy('camOther', {scroll = {}, scale = {}}, createCamFilterHelpers('camOther')),
    follow = objectProxy('camFollow'),
    followPos = objectProxy('camFollowPos'),
    target = cameraSetTarget,
    mouseX = getMouseX,
    mouseY = getMouseY
}

---@class PsychNoteAPI
---@field player fun(index: integer): table proxy strum của người chơi (playerStrums[index])
---@field opponent fun(index: integer): table proxy strum đối thủ (opponentStrums[index])
---@field all fun(index: integer): table proxy note trong strumLineNotes[index]
---@field unspawn fun(index: integer): table proxy note trong unspawnNotes[index]
---@field note fun(index: integer): table proxy note trong notes[index]
---@field tweenX fun(tag: string, target: number, duration: number, ease?: string)
---@field tweenY fun(tag: string, target: number, duration: number, ease?: string)
---@field tweenAngle fun(tag: string, target: number, duration: number, ease?: string)
---@field tweenAlpha fun(tag: string, target: number, duration: number, ease?: string)
---@field tweenDirection fun(tag: string, x: number, y: number, angle: number, duration: number, ease?: string)
PsychObject.Note = {
    player = function(index) return PsychObject.group('playerStrums', index) end,
    opponent = function(index) return PsychObject.group('opponentStrums', index) end,
    all = function(index) return PsychObject.group('strumLineNotes', index) end,
    unspawn = function(index) return PsychObject.group('unspawnNotes', index) end,
    note = function(index) return PsychObject.group('notes', index) end,
    tweenX = noteTweenX,
    tweenY = noteTweenY,
    tweenAngle = noteTweenAngle,
    tweenAlpha = noteTweenAlpha,
    tweenDirection = noteTweenDirection
}

---@class PsychTweenAPI
---@field tween fun(target: any, values: table, duration: number, options?: table): any
---@field fromTo fun(target: any, from: number, to: number, duration: number, options?: table): any
---@field x fun(tag: string, target: number, duration: number, ease?: string)
---@field y fun(tag: string, target: number, duration: number, ease?: string)
---@field angle fun(tag: string, target: number, duration: number, ease?: string)
---@field alpha fun(tag: string, target: number, duration: number, ease?: string)
---@field zoom fun(camera: string, target: number, duration: number, ease?: string)
---@field color fun(tag: string, duration: number, color: string, ease?: string)
---@field cancel fun(tag: string, forceEnd?: boolean)
PsychObject.Tween = { -- Native Engine Tween Wrappers
    tween = function(target, values, duration, options)
        return ReferenceResolver.executeClassCall('FlxTween', 'tween', {target, values, duration, options})
    end,
    fromTo = function(target, from, to, duration, options)
        return ReferenceResolver.executeClassCall('FlxTween', 'fromTo', {target, from, to, duration, options})
    end,
    x = doTweenX,
    y = doTweenY,
    angle = doTweenAngle,
    alpha = doTweenAlpha,
    zoom = doTweenZoom,
    color = doTweenColor,
    cancel = cancelTween
}

---@class PsychTimerAPI
---@field start fun(tag: string, time: number, loops?: integer): boolean
---@field cancel fun(tag: string): boolean
PsychObject.Timer = { -- Native Engine Timer Wrappers
    start = runTimer,
    cancel = cancelTimer
}

---@class PsychSoundAPI
---@field play fun(tag: string, path: string, volume?: number, loop?: boolean)
---@field music fun(path: string, volume?: number, loop?: boolean)
---@field pause fun(tag: string)
---@field resume fun(tag: string)
---@field stop fun(tag: string)
PsychObject.Sound = { -- Native Engine Sound Wrappers
    play = playSound,
    music = playMusic,
    pause = pauseSound,
    resume = resumeSound,
    stop = stopSound
}

---@class PsychShaderAPI
---@field load fun(shaderName: string) preload "shaders/shaderName.frag" (initLuaShader)
---@field attach fun(tag: string, shaderName: string): boolean gắn shader lên object tag
---@field detach fun(tag: string): boolean gỡ shader khỏi object tag
---@field float fun(tag: string, uniform: string, value: number)
---@field floats fun(tag: string, uniform: string, values: number[])
---@field int fun(tag: string, uniform: string, value: integer)
---@field ints fun(tag: string, uniform: string, values: integer[])
---@field bool fun(tag: string, uniform: string, value: boolean)
---@field bools fun(tag: string, uniform: string, values: boolean[])
---@field texture fun(tag: string, uniform: string, imagePath: string)
PsychObject.Shader = {
    load = initLuaShader,
    attach = setSpriteShader,
    detach = removeSpriteShader,
    float = setShaderFloat,
    floats = setShaderFloatArray,
    int = setShaderInt,
    ints = setShaderIntArray,
    bool = setShaderBool,
    bools = setShaderBoolArray,
    texture = setShaderSampler2D
}

---@class PsychHaxeAPI
---@field run fun(code: string): any chạy 1 đoạn Haxe (runHaxeCode)
---@field eval fun(expr: string): any chạy 'return expr;' và lấy kết quả
PsychObject.Haxe = {
    run = function(code)
        if debugEnabled then
            debugOutput('[HAXE_RUN] code: ' .. tostring(code), '55AAFF')
        end

        local ok, result = pcall(runHaxeCode, code)

        if debugEnabled then
            if not ok then
                debugOutput('[HAXE_RUN] -> FAILED: ' .. tostring(result), 'FF5555')
            elseif result == nil then
                debugOutput('[HAXE_RUN] -> OK (no return value)', '55FF88')
            else
                debugOutput('[HAXE_RUN] -> OK | result: ' .. debugValue(result), '55FF88')
            end
        end

        return ok and result or nil
    end,
    eval = function(expr)
        local code = 'return ' .. expr .. ';'

        if debugEnabled then
            debugOutput('[HAXE_EVAL] expr: ' .. tostring(expr), '55AAFF')
        end

        local ok, result = pcall(runHaxeCode, code)

        if debugEnabled then
            if not ok then
                debugOutput('[HAXE_EVAL] -> FAILED: ' .. tostring(result), 'FF5555')
            else
                debugOutput('[HAXE_EVAL] -> OK | result: ' .. debugValue(result), '55FF88')
            end
        end

        return ok and result or nil
    end
}

-- Chuỗi credit hiển thị trong log debug (xem 08_debug_api.lua) — đổi ở đây nếu bạn fork lại.
DEBUG_CREDIT = "Psych Object API - by kietNguyen (tea)"

---@class PsychDebugAPI
---@field enable fun(value?: boolean)
---@field isEnabled fun(): boolean
---@field log fun(level: string, message: any, context?: table, category?: string)
---@field trace fun(message: any, context?: table, category?: string)
---@field debug fun(message: any, context?: table, category?: string)
---@field info fun(message: any, context?: table, category?: string)
---@field warn fun(message: any, context?: table, category?: string)
---@field error fun(message: any, context?: table, category?: string)
---@field mode fun(value: 'console'|'file'|'both')
---@field getMode fun(): string
---@field level fun(value?: string): string
---@field getLevel fun(): string
---@field category fun(category?: string|table): any
---@field clearCategory fun(): boolean
---@field caller fun(value?: boolean): boolean
---@field timestamp fun(value?: boolean): boolean
---@field step fun(value?: boolean): boolean
---@field context fun(value?: boolean): boolean
---@field history fun(limit?: number): table
---@field last fun(): table|nil
---@field clear fun(): boolean
---@field stats fun(): table
---@field resetStats fun(): boolean
---@field profileStart fun(name: string, category?: string): boolean
---@field profileStop fun(name: string): number|nil
---@field profiles fun(): table
---@field profileClear fun(): boolean
---@field dump fun(value: any): string
---@field assert fun(condition: boolean, message?: string, context?: table): boolean
---@field mute fun(value?: boolean): boolean
---@field getVersion fun(): string
---@field uptime fun(): number
---@field flush fun(): boolean
---@field file fun(path: string, clear?: boolean): string

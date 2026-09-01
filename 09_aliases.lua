-- ============================================================
-- Psych Object API — module: gameRootChildren + aliases (bf/dad/game/...) + class proxies + return
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

-- Haxe-like `game` root child schema.
-- Known object roots become real proxies so chains such as:
--   game.camFollow.x
--   game.camGame.zoom
--   game.boyfriend.animation.curAnim.name
-- work naturally. Unknown/scalar fields still use the native getProperty fallback.
gameRootChildren = {
    boyfriend = characterChildren,
    dad = characterChildren,
    gf = characterChildren,

    camGame = {scroll = {}, scale = {}},
    camHUD = {scroll = {}, scale = {}},
    camOther = {scroll = {}, scale = {}},

    camFollow = {},
    camFollowPos = {},

    iconP1 = uiChildren,
    iconP2 = uiChildren,
    healthBar = uiChildren,
    healthBarBG = uiChildren,
    scoreTxt = uiChildren,
    timeTxt = uiChildren,
    botplayTxt = uiChildren
}

gameRootChildHelpers = {
    camGame = createCamFilterHelpers('camGame'),
    camHUD = createCamFilterHelpers('camHUD'),
    camOther = createCamFilterHelpers('camOther')
}

-- ============================================================
-- GAME OBJECT ALIASES (Bổ sung toàn bộ UI / Elements)
-- ============================================================
---@type PsychProxy
bf = objectProxy('boyfriend', characterChildren)
---@type PsychProxy
dad = objectProxy('dad', characterChildren)
---@type PsychProxy
gf = objectProxy('gf', characterChildren)
---@type PsychProxy
game = objectProxy('', gameRootChildren, nil, gameRootChildHelpers)

-- Core UI Elements
---@type PsychProxy
iconP1 = objectProxy('iconP1', uiChildren)
---@type PsychProxy
iconP2 = objectProxy('iconP2', uiChildren)
---@type PsychProxy
healthBar = objectProxy('healthBar', uiChildren)
---@type PsychProxy
healthBarBG = objectProxy('healthBarBG', uiChildren)
---@type PsychProxy
scoreTxt = objectProxy('scoreTxt', uiChildren)
---@type PsychProxy
timeTxt = objectProxy('timeTxt', uiChildren)
---@type PsychProxy
botplayTxt = objectProxy('botplayTxt', uiChildren)

-- Main Cameras
---@type PsychCamProxy
camGame = PsychObject.Camera.game
---@type PsychCamProxy
camHUD = PsychObject.Camera.hud
---@type PsychCamProxy
camOther = PsychObject.Camera.other

-- ============================================================
-- CLASS PROXIES (Bổ sung đầy đủ cho Psych 1.0.4)
-- ============================================================
---@type PsychProxy
FlxG = classProxy('FlxG', flxGChildren)
---@type PsychProxy
Conductor = classProxy('backend.Conductor')
---@type PsychProxy
ClientPrefs = classProxy('backend.ClientPrefs', {data = {}, defaultData = {}})
---@type PsychProxy
PlayState = classProxy('states.PlayState')
---@type PsychProxy
Paths = classProxy('Paths')
---@type PsychProxy
CoolUtil = classProxy('CoolUtil')
---@type PsychProxy
Language = classProxy('backend.Language')
---@type PsychProxy
Difficulty = classProxy('backend.Difficulty')
---@type PsychProxy
Mods = classProxy('backend.Mods')
---@type PsychProxy
Highscore = classProxy('backend.Highscore')
---@type PsychProxy
Song = classProxy('backend.Song')

-- Flixel Utilities
-- Khai báo classProxy với full path của HaxeFlixel
---@type PsychProxy
Math = classProxy('Math')
---@type PsychProxy
FlxMath  = classProxy('FlxMath')
---@type PsychProxy
FlxEase  = classProxy('FlxEase')
---@type PsychProxy
FlxTween = classProxy('FlxTween')
---@type PsychProxy
FlxColor = classProxy('FlxColor')
---@type PsychProxy
FlxTimer = classProxy('FlxTimer')

-- Base Game Objects (Dành cho việc ép kiểu/tham chiếu Haxe)
Character = classProxy('Character')
BGSprite = classProxy('BGSprite')
FlxSprite = classProxy('FlxSprite')

-- System Namespaces

Psych = PsychObject
Sprite = PsychObject.Sprite
Text = PsychObject.Text
---@type PsychCameraAPI
Camera = PsychObject.Camera
---@type PsychNoteAPI
Note = PsychObject.Note
---@type PsychShaderAPI
Shader = PsychObject.Shader
---@type PsychTweenAPI
Tween = PsychObject.Tween
---@type PsychTimerAPI
Timer = PsychObject.Timer
---@type PsychSoundAPI
Sound = PsychObject.Sound
---@type PsychHaxeAPI
Haxe = PsychObject.Haxe
RuntimeShader = PsychObject.RuntimeShader
---@type PsychDebugAPI
Debug = PsychObject.Debug
Ref = PsychObject.Ref

return PsychObject

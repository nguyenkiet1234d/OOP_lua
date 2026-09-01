-- ============================================================
-- Psych Object API — module: Sprite & Text API
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

spriteChildren = {
    animation = {curAnim = {}},
    clipRect = {},
    offset = {},
    origin = {},
    scale = {},
    scrollFactor = {},
    velocity = {},
    acceleration = {},
    drag = {},
    maxVelocity = {},
    colorTransform = {},

}

--- Kiểm tra tag hợp lệ: phải là string khác rỗng và không được chứa dấu chấm (dấu chấm dành riêng cho path lồng nhau).
---@param tag string
---@return nil
function assertTag(tag)
    assert(type(tag) == 'string' and tag ~= '', 'Sprite/Text tag must be a non-empty string')
    assert(not tag:find('.', 1, true), 'Sprite/Text tag cannot contain a dot: ' .. tag)
end

---@class PsychSpriteProxy : PsychProxy
---@field add fun(self: PsychSpriteProxy, inFront?: boolean)
---@field remove fun(self: PsychSpriteProxy, destroy?: boolean, group?: string)
---@field makeGraphic fun(self: PsychSpriteProxy, width: number, height: number, color?: string)
---@field addAnimation fun(self: PsychSpriteProxy, name: string, prefix: string, frameRate?: number, loop?: boolean): boolean
---@field addAnimationByIndices fun(self: PsychSpriteProxy, name: string, prefix: string, indices: number[], frameRate?: number, loop?: boolean): boolean
---@field play fun(self: PsychSpriteProxy, name: string, forced?: boolean, reverse?: boolean, startFrame?: number): boolean
---@field scaleTo fun(self: PsychSpriteProxy, x: number, y?: number, updateHitbox?: boolean)
---@field scroll fun(self: PsychSpriteProxy, x: number, y?: number)
---@field camera fun(self: PsychSpriteProxy, camera?: string)
---@field center fun(self: PsychSpriteProxy, axis?: 'x'|'y'|'xy')
---@field blend fun(self: PsychSpriteProxy, mode?: string)
---@field shader fun(self: PsychSpriteProxy, shaderName: string): boolean gắn shader
---@field removeShader fun(self: PsychSpriteProxy): boolean
---@field shaderFloat fun(self: PsychSpriteProxy, uniform: string, value: number)
---@field shaderInt fun(self: PsychSpriteProxy, uniform: string, value: integer)
---@field shaderBool fun(self: PsychSpriteProxy, uniform: string, value: boolean)
---@field shaderFloats fun(self: PsychSpriteProxy, uniform: string, values: number[])
---@field shaderTexture fun(self: PsychSpriteProxy, uniform: string, imagePath: string)
spriteHelpers = {
    add = function(self, inFront)
        local tag = self:path()
        local result = addLuaSprite(tag, inFront == true)
        if debugEnabled then debugTrace('add sprite ' .. tag, result) end
    end,
    remove = function(self, destroy, group)
        local tag = self:path()
        local result = removeLuaSprite(tag, destroy ~= false, group)
        if debugEnabled then debugTrace('remove sprite ' .. tag, result) end
    end,
    makeGraphic = function(self, width, height, color)
        local tag = self:path()
        local result = makeGraphic(tag, width, height, color or 'FFFFFF')
        if debugEnabled then debugTrace('make graphic ' .. tag, result) end
    end,
    addAnimation = function(self, name, prefix, frameRate, loop)
        local tag = self:path()
        local result = addAnimationByPrefix(tag, name, prefix, frameRate or 24, loop ~= false)
        if debugEnabled then debugTrace('add animation ' .. tag .. '.' .. name, result) end
        return result
    end,
    addAnimationByIndices = function(self, name, prefix, indices, frameRate, loop)
        local tag = self:path()
        local result = addAnimationByIndices(tag, name, prefix, indices, frameRate or 24, loop == true)
        if debugEnabled then debugTrace('add indexed animation ' .. tag .. '.' .. name, result) end
        return result
    end,
    play = function(self, name, forced, reverse, startFrame)
        local tag = self:path()
        local result = playAnim(tag, name, forced == true, reverse == true, startFrame or 0)
        if debugEnabled then debugTrace('play animation ' .. tag .. '.' .. name, result) end
        return result
    end,
    scaleTo = function(self, x, y, updateHitbox)
        local tag = self:path()
        local result = scaleObject(tag, x, y, updateHitbox ~= false)
        if debugEnabled then debugTrace('scale sprite ' .. tag, result) end
    end,
    scroll = function(self, x, y)
        local tag = self:path()
        local result = setScrollFactor(tag, x, y)
        if debugEnabled then debugTrace('scroll factor ' .. tag, result) end
    end,
    camera = function(self, camera)
        local tag = self:path()
        local result = setObjectCamera(tag, camera or 'game')
        if debugEnabled then debugTrace('set camera ' .. tag, result) end
    end,
    center = function(self, axis)
        local tag = self:path()
        local result = screenCenter(tag, axis or 'xy')
        if debugEnabled then debugTrace('center sprite ' .. tag, result) end
    end,
    blend = function(self, mode)
        local tag = self:path()
        local result = setBlendMode(tag, mode or '')
        if debugEnabled then debugTrace('set blend ' .. tag, result) end
    end,
    shader = function(self, shaderName)
        local tag = self:path()
        local result = setSpriteShader(tag, shaderName)
        if debugEnabled then debugTrace('attach shader ' .. shaderName .. ' to ' .. tag, result) end
        return result
    end,
    removeShader = function(self)
        local tag = self:path()
        local result = removeSpriteShader(tag)
        if debugEnabled then debugTrace('detach shader from ' .. tag, result) end
        return result
    end,
    shaderFloat = function(self, uniform, value) return setShaderFloat(self:path(), uniform, value) end,
    shaderInt = function(self, uniform, value) return setShaderInt(self:path(), uniform, value) end,
    shaderBool = function(self, uniform, value) return setShaderBool(self:path(), uniform, value) end,
    shaderFloats = function(self, uniform, values) return setShaderFloatArray(self:path(), uniform, values) end,
    shaderTexture = function(self, uniform, imagePath) return setShaderSampler2D(self:path(), uniform, imagePath) end
}

spriteProxyCache = {}
--- Lấy (hoặc tạo mới, có cache theo tag) proxy PsychSpriteProxy cho 1 Lua sprite.
---@param tag string
---@return PsychSpriteProxy
function spriteProxy(tag)
    local cached = spriteProxyCache[tag]
    if cached then return cached end
    assertTag(tag)
    local proxy = objectProxy(tag, spriteChildren, spriteHelpers)
    spriteProxyCache[tag] = proxy
    return proxy
end

---@class PsychTextProxy : PsychProxy
---@field add fun(self: PsychTextProxy)
---@field remove fun(self: PsychTextProxy, destroy?: boolean)
---@field string fun(self: PsychTextProxy, value: string)
---@field size fun(self: PsychTextProxy, value: number)
---@field width fun(self: PsychTextProxy, value: number)
---@field height fun(self: PsychTextProxy, value: number)
---@field color fun(self: PsychTextProxy, value: string)
---@field font fun(self: PsychTextProxy, value: string)
---@field border fun(self: PsychTextProxy, size: number, color: string, style?: 'outline'|'shadow'|'outline_fast')
---@field align fun(self: PsychTextProxy, value: 'left'|'center'|'right')
---@field camera fun(self: PsychTextProxy, camera?: string)
---@field center fun(self: PsychTextProxy, axis?: 'x'|'y'|'xy')
textHelpers = {
    add = function(self) return addLuaText(self:path()) end,
    remove = function(self, destroy) return removeLuaText(self:path(), destroy ~= false) end,
    string = function(self, value) return setTextString(self:path(), value) end,
    size = function(self, value) return setTextSize(self:path(), value) end,
    width = function(self, value) return setTextWidth(self:path(), value) end,
    height = function(self, value) return setTextHeight(self:path(), value) end,
    color = function(self, value) return setTextColor(self:path(), value) end,
    font = function(self, value) return setTextFont(self:path(), value) end,
    border = function(self, size, color, style) return setTextBorder(self:path(), size, color, style or 'outline') end,
    align = function(self, value) return setTextAlignment(self:path(), value) end,
    camera = function(self, camera) return setObjectCamera(self:path(), camera or 'hud') end,
    center = function(self, axis) return screenCenter(self:path(), axis or 'xy') end
}

textProxyCache = {}
--- Lấy (hoặc tạo mới, có cache theo tag) proxy PsychTextProxy cho 1 Lua text.
---@param tag string
---@return PsychTextProxy
function textProxy(tag)
    local cached = textProxyCache[tag]
    if cached then return cached end
    assertTag(tag)
    local proxy = objectProxy(tag, spriteChildren, textHelpers)
    textProxyCache[tag] = proxy
    return proxy
end

PsychObject.Sprite = {}

--- Lấy proxy của 1 Lua sprite đã tồn tại theo tag.
---@param tag string
---@return PsychSpriteProxy
function PsychObject.Sprite.get(tag) return spriteProxy(tag) end

--- Tạo sprite tĩnh mới (makeLuaSprite).
---@param tag string tag định danh, không chứa dấu chấm
---@param image string? đường dẫn ảnh trong images/
---@param x number?
---@param y number?
---@param options {graphic:number[]?, scrollFactor:number[]?, scale:number[]?, camera:string?, blend:string?, center:(boolean|'x'|'y'|'xy')?, add:boolean?, inFront:boolean?}?
---@return PsychSpriteProxy
function PsychObject.Sprite.new(tag, image, x, y, options)
    assertTag(tag)
    options = options or {}
    makeLuaSprite(tag, image or '', x or 0, y or 0)

    if options.graphic then makeGraphic(tag, options.graphic[1], options.graphic[2], options.graphic[3] or 'FFFFFF') end
    if options.scrollFactor then setScrollFactor(tag, options.scrollFactor[1], options.scrollFactor[2] or options.scrollFactor[1]) end
    if options.scale then scaleObject(tag, options.scale[1], options.scale[2] or options.scale[1], true) end
    if options.camera then setObjectCamera(tag, options.camera) end
    if options.blend then setBlendMode(tag, options.blend) end
    if options.center then screenCenter(tag, options.center == true and 'xy' or options.center) end
    if options.add ~= false then addLuaSprite(tag, options.inFront == true) end

    return spriteProxy(tag)
end

--- Tạo sprite có animation mới (makeAnimatedLuaSprite).
---@param tag string tag định danh, không chứa dấu chấm
---@param image string? đường dẫn ảnh (kèm .xml/.json/.txt cùng tên) trong images/
---@param x number?
---@param y number?
---@param options {spriteType:('auto'|'sparrow'|'packer'|'aseprite')?, animation:{name:string,prefix:string,frameRate:number?,loop:boolean?,play:boolean?}?, scrollFactor:number[]?, scale:number[]?, camera:string?, add:boolean?, inFront:boolean?}?
---@return PsychSpriteProxy
function PsychObject.Sprite.animated(tag, image, x, y, options)
    assertTag(tag)
    options = options or {}
    makeAnimatedLuaSprite(tag, image or '', x or 0, y or 0, options.spriteType or 'auto')

    local sprite = spriteProxy(tag)
    if options.animation then
        sprite:addAnimation(options.animation.name, options.animation.prefix, options.animation.frameRate, options.animation.loop)
        if options.animation.play ~= false then sprite:play(options.animation.name, true) end
    end
    if options.scrollFactor then sprite:scroll(options.scrollFactor[1], options.scrollFactor[2] or options.scrollFactor[1]) end
    if options.scale then sprite:scaleTo(options.scale[1], options.scale[2] or options.scale[1]) end
    if options.camera then sprite:camera(options.camera) end
    if options.add ~= false then sprite:add(options.inFront) end

    return sprite
end

PsychObject.Text = {}

--- Lấy proxy của 1 Lua text đã tồn tại theo tag.
---@param tag string
---@return PsychTextProxy
function PsychObject.Text.get(tag) return textProxy(tag) end

--- Tạo text mới (makeLuaText).
---@param tag string tag định danh, không chứa dấu chấm
---@param value string? nội dung chữ
---@param width number? độ rộng khung chữ (0 = tự co)
---@param x number?
---@param y number?
---@param options {size:number?, color:string?, font:string?, border:{[1]:number,[2]:string,[3]:string?}?, align:string?, camera:string?, add:boolean?}?
---@return PsychTextProxy
function PsychObject.Text.new(tag, value, width, x, y, options)
    assertTag(tag)
    options = options or {}
    makeLuaText(tag, value or '', width or 0, x or 0, y or 0)

    if options.size then setTextSize(tag, options.size) end
    if options.color then setTextColor(tag, options.color) end
    if options.font then setTextFont(tag, options.font) end
    if options.border then setTextBorder(tag, options.border[1], options.border[2], options.border[3] or 'outline') end
    if options.align then setTextAlignment(tag, options.align) end
    if options.camera then setObjectCamera(tag, options.camera) end
    if options.add ~= false then addLuaText(tag) end

    return textProxy(tag)
end

---@class PsychCamProxy : PsychProxy
---@field setFilters fun(self: PsychCamProxy, filters?: string|RuntimeShader|(string|RuntimeShader)[])
---@field clearFilters fun(self: PsychCamProxy)

---@class PsychCameraAPI
---@field game PsychCamProxy camGame
---@field hud PsychCamProxy camHUD
---@field other PsychCamProxy camOther
---@field follow PsychProxy camFollow
---@field followPos PsychProxy camFollowPos
---@field target fun(tag?: string, duration?: number) đặt camera theo target (native cameraSetTarget)
---@field mouseX fun(): number toạ độ X chuột trong world
---@field mouseY fun(): number toạ độ Y chuột trong world

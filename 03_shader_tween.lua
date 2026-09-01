--[[
    Psych Object API — Module: RuntimeShader + Lua Tween Ticker
    ===========================================================
    - RuntimeShader: wrapper for camera/global shaders using hidden Lua sprites
      (no setVar/getVar needed - uses native setShaderFloat/Int/Bool/Array/Sampler2D)
    - Lua tween system: pure-Lua ticker for ClassName.num(from, to, duration, callback) tweens
      MUST call PsychObject.tick(elapsed) from onUpdate() for tweens to animate
    
    GLOBALS CREATED:
    ----------------
    RuntimeShaderMT (metatable with :float, :floats, :int, :ints, :bool, :bools, :texture, :destroy)
    PsychObject.RuntimeShader.new(name, tag?) -> RuntimeShader
    PsychObject.RuntimeShader.get(tag) -> RuntimeShader
    PsychObject.tick(elapsed) - CALL FROM onUpdate(elapsed)
    luaTweens (array of active Lua tweens)
    luaEaseLinear, luaEaseCircOut
    stripLuaCallbacks(tbl) -> tblWithoutCallback, onCompleteFn
    
    @module 03_shader_tween
    @see 06_sprite_text.lua for sprite.shader* methods (different API - for sprite shaders)
]]

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


-- ============================================================
-- RUNTIME SHADER (camera / global shader) — KHÔNG dùng setVar/getVar.
-- Cơ chế: tạo 1 Lua sprite ẩn (ngoài khung hình, không add vào scene)
-- làm "vật chứa"; setSpriteShader gắn shader thật lên sprite đó, nên
-- setShaderFloat/Int/Bool/... theo tag hoạt động thẳng bằng hàm native,
-- không cần runHaxeCode hay biến toàn cục nào.
-- ============================================================
runtimeShaderCounter = 0

---@class RuntimeShader
---@field tag string tag của sprite ẩn đang giữ shader này
---@field name string tên file shader (.frag) trong shaders/
RuntimeShaderMT = {}
RuntimeShaderMT.__index = {
    --- Set uniform kiểu float.
    ---@param uniform string
    ---@param value number
    float = function(self, uniform, value) return setShaderFloat(self.tag, uniform, value) end,
    --- Set uniform kiểu float[].
    ---@param uniform string
    ---@param values number[]
    floats = function(self, uniform, values) return setShaderFloatArray(self.tag, uniform, values) end,
    --- Set uniform kiểu int.
    ---@param uniform string
    ---@param value integer
    int = function(self, uniform, value) return setShaderInt(self.tag, uniform, value) end,
    --- Set uniform kiểu int[].
    ---@param uniform string
    ---@param values integer[]
    ints = function(self, uniform, values) return setShaderIntArray(self.tag, uniform, values) end,
    --- Set uniform kiểu bool.
    ---@param uniform string
    ---@param value boolean
    bool = function(self, uniform, value) return setShaderBool(self.tag, uniform, value) end,
    --- Set uniform kiểu bool[].
    ---@param uniform string
    ---@param values boolean[]
    bools = function(self, uniform, values) return setShaderBoolArray(self.tag, uniform, values) end,
    --- Set uniform kiểu sampler2D (ảnh phụ).
    ---@param uniform string
    ---@param imagePath string
    texture = function(self, uniform, imagePath) return setShaderSampler2D(self.tag, uniform, imagePath) end,
    --- Gỡ shader, giải phóng sprite ẩn.
    destroy = function(self)
        if not self or not self.tag then return false end
        local ok = removeSpriteShader(self.tag)
        self.tag = nil
        return ok
    end
}

--- Tạo 1 RuntimeShader mới (dùng cho camera filter, không gắn hiển thị lên sprite thật).
---@param name string tên file shader trong shaders/ (không kèm đuôi .frag)
---@param tag string? tag tuỳ chỉnh cho sprite ẩn chứa shader, mặc định tự sinh
---@return RuntimeShader
function PsychObject.RuntimeShaderNew(name, tag)
    assert(type(name) == 'string' and name ~= '', 'RuntimeShader name must be non-empty')
    runtimeShaderCounter = runtimeShaderCounter + 1
    tag = tag or ('__psych_rtshader_' .. runtimeShaderCounter)

    if tag and type(tag) == 'string' and tag ~= '' then
        local existing = getProperty(tag)
        if existing ~= nil then
            if debugEnabled then
                debugOutput('RuntimeShader tag already exists: ' .. tag .. ' -> reusing with cleanup', 'FFAA00')
            end
            pcall(removeSpriteShader, tag)
        end
    end

    makeLuaSprite(tag, '', -99999, -99999) -- sprite ẩn, cố tình không addLuaSprite
    initLuaShader(name)
    setSpriteShader(tag, name)
    return setmetatable({ tag = tag, name = name }, RuntimeShaderMT)
end

PsychObject.RuntimeShader = {
    new = PsychObject.RuntimeShaderNew,
    --- Lấy lại wrapper cho 1 RuntimeShader đã tạo trước đó, theo tag của nó.
    ---@param tag string
    ---@return RuntimeShader
    get = function(tag) return setmetatable({ tag = tag }, RuntimeShaderMT) end
}

luaTweens = {}
psychTickCount = 0
--- Hàm easing tuyến tính, dùng làm mặc định cho tween Lua thuần (:num).
---@param t number
---@return number
function luaEaseLinear(t) return t end
--- Hàm easing kiểu circOut, được dùng khi FlxEase.circOut được truyền vào tween Lua thuần (:num).
---@param t number
---@return number
function luaEaseCircOut(t)
    t = t - 1
    return math.sqrt(1 - t * t)
end

--- Cập nhật mỗi frame cho các tween Lua thuần (tạo bởi ClassName.num(...)); PHẢI được gọi từ onUpdate/update phía script chính.
---@param elapsed number
---@return nil
function PsychObject.tick(elapsed)
    if not elapsed then return end
    psychTickCount = psychTickCount + 1
    for i = #luaTweens, 1, -1 do
        local tw = luaTweens[i]
        tw.t = tw.t + elapsed
        local u = tw.duration <= 0 and 1 or (tw.t / tw.duration)
        if u > 1 then u = 1 end
        local e = (tw.ease or luaEaseLinear)(u)
        if tw.onValue then tw.onValue(tw.from + (tw.to - tw.from) * e) end
        if u >= 1 then
            if tw.onComplete then tw.onComplete(tw.to) end
            tRemove(luaTweens, i)
        end
    end
end

--- Tách callback onComplete (hàm Lua) ra khỏi options table trước khi serialize sang Haxe, vì hàm Lua không thể gửi qua runHaxeCode.
---@param tbl table
---@return table, function|nil
function stripLuaCallbacks(tbl)
    if type(tbl) ~= 'table' then return tbl, nil end
    local complete = tbl.onComplete
    if type(complete) ~= 'function' then return tbl, nil end
    local copy = {}
    for k, v in pairs(tbl) do
        if k ~= 'onComplete' then copy[k] = v end
    end
    return copy, complete
end


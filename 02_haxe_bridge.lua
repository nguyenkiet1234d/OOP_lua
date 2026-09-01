--[[
    Psych Object API — Module: Haxe Bridge (Filter Helpers, ReferenceResolver, Ref)
    ==============================================================================
    Provides Haxe interoperability layer:
    - Filter helpers for FlxG.game and cameras (shader filters)
    - Character/FlxG/UI child schemas for nested proxy access
    - ReferenceResolver: compile Lua calls to Haxe code (runHaxeCode)
    - PsychObject.Ref: create Haxe references for fluent chaining
    - Instance management: ClassName.new() creates real Haxe instances in game.variables
    
    GLOBALS CREATED:
    ----------------
    hxQuote, isFilterList, generateFilterCode, resolveFilterArgs
    gameHelpers (setFilters/clearFilters for FlxG.game)
    createCamFilterHelpers(camName) -> {setFilters, clearFilters}
    characterChildren, flxGChildren, uiChildren (schemas)
    appendPath(path, key) -> string
    PsychObject.Ref (callable table: Ref(target, field) -> HaxeRef)
    ReferenceResolver (namespace: needsCompilation, serialize, executeClassCall, executeObjectCall, executeNewCall, releaseInstance)
    isPsychNewInstancePath, getPsychNewInstanceRoot, hasHaxeInstanceRoot
    isPrimitive
    newInstanceCounter
    
    @module 02_haxe_bridge
    @see 04_proxy_core.lua for objectProxy using ReferenceResolver
    @see 05_class_proxy.lua for classProxy using ReferenceResolver
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

local function runFilterHaxe(code)
    local ok, result = pcall(runHaxeCode, code)
    if not ok and debugEnabled then
        debugOutput('[FILTER] Haxe failed: ' .. tostring(result), 'FF5555')
    end
    return ok and result or false
end

-- Forward declarations (defined in 04_proxy_core.lua, used here before load)
local function hasHaxeInstanceRoot(path) end
local function isHaxeInstancePath(path) end

-- ============================================================
-- FILTER HELPERS CHO FLXG VÀ CAMERA
-- ============================================================
--- Escape và bọc 1 giá trị Lua thành literal string Haxe (dùng trong code sinh cho runHaxeCode).
---@param value any
---@return string
function hxQuote(value)
    local text = tostring(value)
    text = text:gsub('\\', '\\\\'):gsub("'", "\\'")
    return "'" .. text .. "'"
end

-- true nếu v là 1 danh sách filter (mảng); false nếu v là 1 filter đơn (string/RuntimeShader)
--- true nếu v là 1 danh sách filter (mảng nhiều filter); false nếu v là 1 filter đơn (string/RuntimeShader).
---@param v any
---@return boolean
function isFilterList(v)
    return type(v) == 'table' and v.tag == nil and v[1] ~= nil
end

--- Sinh đoạn code Haxe gán `.filters` cho targetExpr từ danh sách tên shader / RuntimeShader truyền vào.
---@param targetExpr string
---@param filters string|RuntimeShader|(string|RuntimeShader)[]
---@return string
function generateFilterCode(targetExpr, filters)
    if not isFilterList(filters) then filters = { filters } end
    local parts = { "var filtersArr = [];\n" }
    for _, f in ipairs(filters) do
        if type(f) == 'table' and f.tag then
            -- RuntimeShader: shader thật nằm trên sprite ẩn giữ nó (không setVar/getVar)
            tInsert(parts, sFormat([[
            var rs = game.getLuaObject(%s);
            if (rs != null && rs.shader != null) filtersArr.push(new ShaderFilter(rs.shader));
        ]], hxQuote(f.tag)))
        else
            local shaderName = type(f) == 'string' and f or tostring(f)
            tInsert(parts, sFormat([[
            var s:FlxRuntimeShader = game.createRuntimeShader(%s);
            if (s != null) filtersArr.push(new ShaderFilter(s));
        ]], hxQuote(shaderName)))
        end
    end
    tInsert(parts, targetExpr .. ".filters = filtersArr; return true;")
    return tConcat(parts)
end

--- Chuẩn hoá tham số cho setFilters: nếu gọi kiểu proxy:setFilters(a,b,...) thì dùng self làm danh sách filter, ngược lại dùng args.
---@param self any
---@param args any
---@return any
function resolveFilterArgs(self, args)
    if args ~= nil then return args end
    return self
end

gameHelpers = {
    --- Gán filter shader lên FlxG.game.
    setFilters = function(self, args)
        return runFilterHaxe(generateFilterCode(self:className(), resolveFilterArgs(self, args)))
    end,
    --- Xoá toàn bộ filter đang gán trên FlxG.game.
    clearFilters = function()
        return runFilterHaxe(self:className() .. ".filters = null; return true;")
    end
}

--- Tạo bộ helper setFilters/clearFilters cho 1 camera cụ thể (camGame/camHUD/camOther).
---@param camName string tên biến camera phía Haxe (vd: 'camGame')
--- Tạo cặp hàm setFilters/clearFilters riêng cho 1 camera cụ thể (camGame/camHUD/camOther).
---@param camName string
---@return table<string, function>
function createCamFilterHelpers(camName)
    return {
        --- Gán filter shader lên camera. filters truyền vào self:setFilters(...) hoặc self:setFilters(a, b).
        ---@param args string|RuntimeShader|(string|RuntimeShader)[]?
        setFilters = function(self, args)
            return runFilterHaxe(generateFilterCode("game." .. camName, resolveFilterArgs(self, args)))
        end,
        --- Xoá toàn bộ filter đang gán trên camera.
        clearFilters = function()
            return runFilterHaxe("game." .. camName .. ".filters = null; return true;")
        end
    }
end

-- Mở rộng hệ thống children để tối ưu lookup cache
characterChildren = {
    animation = {curAnim = {}},
    cameraPosition = {},
    offset = {},
    scale = {},
    scrollFactor = {},
    velocity = {},
    colorTransform = {}
}

flxGChildren = {
    camera = {flashSprite = {}, scroll = {}, scale = {}, target = {}},
    sound = {music = {}},
    save = {data = {}},
    keys = {justPressed = {}, pressed = {}, justReleased = {}},
    mouse = {x = {}, y = {}, justPressed = {}, pressed = {}, justReleased = {}},
    random = {},
    game = {}
}

uiChildren = {
    scale = {},
    offset = {},
    scrollFactor = {},

}

--- Nối path Haxe hiện tại (property/object) với 1 field mới, phân tách bằng dấu chấm.
---@param path string|nil
---@param key string|number
---@return string
function appendPath(path, key)
    if path == nil or path == '' then return tostring(key) end
    return path .. '.' .. tostring(key)
end

-- ============================================================
-- REFERENCE RESOLVER (HAXE CALL COMPILER)
-- ============================================================
---@class HaxeRef
---@field __isHaxeRef boolean
---@field expr string Biểu thức Haxe được chèn vào runHaxeCode
PsychObject.Ref = setmetatable({}, {
    __call = function(_, target, field)
        local ok, pType = pcall(function()
            return target:getProxyType()
        end)

        local expr = ''

        if ok and pType == 'class' then
            expr = target:className() .. '.' .. tostring(field)

        elseif ok and pType == 'object' then
            local path = target:path()

            if path == '' then
                expr = 'game.' .. tostring(field)

            elseif isPsychNewInstancePath(path) then
                expr = sFormat(
                    "game.variables.get('%s').%s",
                    path,
                    tostring(field)
                )

            else
                expr = path .. '.' .. tostring(field)
            end

        else
            expr = tostring(target) .. '.' .. tostring(field)
        end

        if debugEnabled then
            debugOutput(
                '[HAXE_REF_CREATE] '
                .. tostring(expr),
                '55AAFF'
            )
        end

        return {
            __isHaxeRef = true,
            expr = expr
        }
    end
})

ReferenceResolver = {}

--- true nếu trong args có chứa object/class proxy hoặc HaxeRef -> cần biên dịch thành code Haxe thay vì gọi hàm native trực tiếp.
function ReferenceResolver.needsCompilation(args)
    if type(args) ~= 'table' then return false end
    for _, v in pairs(args) do
        if type(v) == 'table' then
            local ok, pType = pcall(function() return v:getProxyType() end)
            if ok and (pType == 'object' or pType == 'class') then return true end
            if v.__isHaxeRef then return true end
            if ReferenceResolver.needsCompilation(v) then return true end 
        end
    end
    return false
end
--- true nếu path CHÍNH LÀ field ẩn của 1 instance vừa tạo bằng ClassName.new() (dạng __psychNewInstance_N).
function isPsychNewInstancePath(path)
    return type(path) == 'string'
        and path:match('^__psychNewInstance_%d+$') ~= nil
end

--- Tách path thành (tên field instance ẩn, phần path còn lại phía sau) nếu path bắt đầu bằng __psychNewInstance_N.
function getPsychNewInstanceRoot(path)
    if isPsychNewInstancePath(path) then
        return path, ''
    end

    local instanceName, remainder =
        path:match('^(__psychNewInstance_%d+)%.(.+)$')

    if instanceName and remainder then
        return instanceName, remainder
    end

    return nil, nil
end
--- Serialize 1 giá trị Lua (số/bool/string/proxy/HaxeRef/table) thành literal code Haxe tương ứng để chèn vào runHaxeCode.
function ReferenceResolver.serialize(val)
    if type(val) == 'number' or type(val) == 'boolean' then return tostring(val) end
    if type(val) == 'string' then return sFormat('%q', val) end
    
    if type(val) == 'table' then
        local ok, pType = pcall(function() return val:getProxyType() end)
        if not ok then pType = nil end

        if pType == nil and val.__isHaxeRef then return val.expr end

        if ok then
            if pType == 'class' then
                return val:className()
            elseif pType == 'object' then
                local path = val:path()

                if path == '' then
                    return 'game'
                end

                -- Instance tạo bằng ClassName.new():
                -- hỗ trợ cả root và nested path:
                -- __psychNewInstance_1
                -- __psychNewInstance_1.x
                -- __psychNewInstance_1.position.x
                if isPsychNewInstancePath(path)
                    or hasHaxeInstanceRoot(path) then

                    return resolveObjectHaxeExpr(path)
                end
                if not path:find('.', 1, true) then
                    -- Path đơn = có thể là tag LuaSprite/Text (Sprite.new, Text.new...).
                    -- Ưu tiên getLuaObject(tag); null thì fallback field thật trên game
                    -- (bf, dad, camGame...). Tag không bao giờ chứa dấu chấm (assertTag),
                    -- nên nhánh multi-segment bên dưới chỉ còn lại field path thật.
                    return sFormat(
                        "(game.getLuaObject('%s') != null ? game.getLuaObject('%s') : Reflect.getProperty(game, '%s'))",
                        path, path, path
                    )
                end

                local hxExpr = "game"
                for part in sGmatch(path, "[^%.]+") do
                    hxExpr = "Reflect.getProperty(" .. hxExpr .. ", '" .. part .. "')"
                end
                return hxExpr
            end
        end

        local isArray, count = true, 0
        for k, _ in pairs(val) do
            count = count + 1
            if type(k) ~= 'number' then isArray = false break end
        end
        
        if count == 0 then return '[]' end

        local elements = {}
        if isArray then
            for i = 1, #val do tInsert(elements, ReferenceResolver.serialize(val[i])) end
            return '[' .. tConcat(elements, ', ') .. ']'
        else
            for k, v in pairs(val) do
                tInsert(elements, tostring(k) .. ': ' .. ReferenceResolver.serialize(v))
            end
            return '{' .. tConcat(elements, ', ') .. '}'
        end
    end
    
    return 'null'
end

--- Biên dịch 1 lời gọi static method trên class Haxe thành code và chạy qua runHaxeCode, trả về kết quả (hoặc nil nếu lỗi).
function ReferenceResolver.executeClassCall(className, method, args)
    local haxeArgs = {}
    for i = 1, #(args or {}) do
        tInsert(haxeArgs, ReferenceResolver.serialize(args[i]))
    end
    local argString = tConcat(haxeArgs, ', ')

    local haxeCode = sFormat("return %s.%s(%s);", className, method, argString)

    if debugEnabled then
        debugOutput(
            '[HAXE_CLASS_CALL] ' .. className .. '.' .. method .. ' | code: ' .. haxeCode,
            '55AAFF'
        )
    end

    local ok, result = pcall(runHaxeCode, haxeCode)

    if debugEnabled then
        if not ok then
            debugOutput(
                '[HAXE_CLASS_CALL] ' .. className .. '.' .. method .. ' -> FAILED: ' .. tostring(result),
                'FF5555'
            )
        elseif result == nil then
            debugOutput(
                '[HAXE_CLASS_CALL] ' .. className .. '.' .. method .. ' -> OK (no return value)',
                '55FF88'
            )
        else
            debugOutput(
                '[HAXE_CLASS_CALL] ' .. className .. '.' .. method .. ' -> OK | result: ' .. debugValue(result),
                '55FF88'
            )
        end
    end

    return ok and result or nil
end
--- Tách 1 property path nhiều cấp ('a.b.c') thành (danh sách phần cha, field cuối cùng).
function splitHaxePropertyPath(property)
    local parts = {}

    for part in sGmatch(property, '[^%.]+') do
        tInsert(parts, part)
    end

    local field = parts[#parts]
    tRemove(parts, #parts)

    return parts, field
end
--- Sinh biểu thức Haxe (Reflect.getProperty lồng nhau, hoặc game.variables.get(...) nếu là instance ẩn) trỏ tới object tại path.
function resolveObjectHaxeExpr(path)
    if path == '' then
        return 'game'
    end

    local instanceName, remainder = getPsychNewInstanceRoot(path)

    if instanceName then
        local hxExpr = sFormat(
            "game.variables.get('%s')",
            instanceName
        )

        if remainder ~= '' then
            for part in sGmatch(remainder, '[^%.]+') do
                hxExpr = sFormat(
                    "Reflect.getProperty(%s, '%s')",
                    hxExpr,
                    part
                )
            end
        end

        return hxExpr
    end

    if not path:find('.', 1, true) then
        return sFormat(
            "(game.getLuaObject('%s') != null ? game.getLuaObject('%s') : Reflect.getProperty(game, '%s'))",
            path,
            path,
            path
        )
    end

    local hxExpr = 'game'

    for part in sGmatch(path, '[^%.]+') do
        hxExpr = sFormat(
            "Reflect.getProperty(%s, '%s')",
            hxExpr,
            part
        )
    end

    return hxExpr
end
--- Biên dịch 1 lời gọi method trên object theo path thành code Haxe (Reflect.callMethod) và chạy qua runHaxeCode.

function ReferenceResolver.executeObjectCall(path, method, args)
    local haxeArgs = {}

    for i = 1, #(args or {}) do
        tInsert(
            haxeArgs,
            ReferenceResolver.serialize(args[i])
        )
    end

    local argString = tConcat(haxeArgs, ', ')
    local hxTarget = resolveObjectHaxeExpr(path)

    -- Marker dùng để nhận diện trường hợp Haxe method trả về chính target.
    -- Ví dụ: FlxSprite.makeGraphic(...) trả về this.
    local selfMarker = '__PSYCH_SELF__:' .. path

    local haxeCode = sFormat([[
var __target = %s;
var __result = Reflect.callMethod(
    __target,
    Reflect.getProperty(__target, '%s'),
    [%s]
);

if (__result == __target)
    return %s;

return __result;
]], hxTarget, method, argString, hxQuote(selfMarker))

    if debugEnabled then
        debugOutput(
            '[HAXE_CALL] '
            .. path .. '.' .. method
            .. ' | target: ' .. hxTarget
            .. ' | code:\n'
            .. haxeCode,
            '55AAFF'
        )
    end

    local ok, result = pcall(
        runHaxeCode,
        haxeCode
    )

    -- Haxe method trả lại chính object đang được gọi.
    -- Chuyển marker thành objectProxy để hỗ trợ fluent chaining:
    -- Class.new(...):makeGraphic(...):setPosition(...)
    if ok and result == selfMarker then
        result = objectProxy(path)

        if debugEnabled then
            debugOutput(
                '[HAXE_CALL] '
                .. path .. '.' .. method
                .. ' -> returned self | proxy restored',
                '55FF88'
            )
        end
    end

    if debugEnabled then
        if not ok then
            debugOutput(
                '[HAXE_CALL] '
                .. path .. '.' .. method
                .. ' -> FAILED: '
                .. tostring(result),
                'FF5555'
            )
        elseif result == nil then
            debugOutput(
                '[HAXE_CALL] '
                .. path .. '.' .. method
                .. ' -> OK (no return value)',
                '55FF88'
            )
        elseif result ~= selfMarker then
            debugOutput(
                '[HAXE_CALL] '
                .. path .. '.' .. method
                .. ' -> OK | result: '
                .. debugValue(result),
                '55FF88'
            )
        end
    end

    return ok and result or nil
end


newInstanceCounter = 0

--- Tạo 1 instance Haxe thật (new ClassName(args)) và lưu vào field ẩn trên `game`
--- để về sau vẫn "sống" và tương thích với FlxTween.tween/:call()/... vì nó
--- được resolve như 1 field thật (Reflect.getProperty(game, field)), y hệt bf/dad/camGame.
---@param className string
---@param args table?
---@return string fieldName tên field ẩn trên game giữ tham chiếu instance
function ReferenceResolver.executeNewCall(className, args)
    newInstanceCounter = newInstanceCounter + 1
    local fieldName = '__psychNewInstance_' .. newInstanceCounter

    local haxeArgs = {}

    for i = 1, #(args or {}) do
        tInsert(haxeArgs, ReferenceResolver.serialize(args[i]))
    end

    local argString = tConcat(haxeArgs, ', ')

    local haxeCode = sFormat([[
var __psychInstance:%s = new %s(%s);
game.variables.set('%s', __psychInstance);
return true;
]],
        className,
        className,
        argString,
        fieldName
    )

    if debugEnabled then
        debugOutput(
            '[HAXE_NEW] '
            .. className
            .. ' -> '
            .. fieldName
            .. ' | code:\n'
            .. haxeCode,
            '55AAFF'
        )
    end

    local ok, result = pcall(runHaxeCode, haxeCode)

    if not ok then
        if debugEnabled then
            debugOutput(
                '[HAXE_NEW] '
                .. className
                .. ' -> FAILED (Lua error): '
                .. tostring(result),
                'FF5555'
            )
        end
    elseif debugEnabled then
        if result == false then
            debugOutput(
                '[HAXE_NEW] '
                .. className
                .. ' -> FAILED (returned false)',
                'FF5555'
            )
        else
            debugOutput(
                '[HAXE_NEW] '
                .. className
                .. ' -> OK | stored in variables['
                .. fieldName
                .. ']',
                '55FF88'
            )
        end
    end

    return fieldName
end
--- Xoá thủ công 1 Haxe instance (tạo qua ClassName.new()) khỏi game.variables.
--- KHÔNG tự động gọi ở bất kỳ đâu khác trong file này - lifecycle thật của
--- game.variables trong Psych Engine (có bị reset theo bài hát/scene hay không)
--- CHƯA được xác minh, nên việc gọi hàm này là quyết định của bạn, không phải tự động.
---@param instanceOrPath PsychProxy|string proxy trả về từ ClassName.new(), hoặc field name '__psychNewInstance_N'
---@return boolean
function PsychObject.releaseInstance(instanceOrPath)
    local path = instanceOrPath

    if type(instanceOrPath) == 'table' then
        local ok, p = pcall(function() return instanceOrPath:path() end)
        if ok then path = p end
    end

    if not isPsychNewInstancePath(path) then
        if debugEnabled then
            debugOutput('[RELEASE] ' .. tostring(path) .. ' -> not a psychNewInstance path, skipped', 'FFAA00')
        end
        return false
    end

    local haxeCode = sFormat("game.variables.remove('%s'); return true;", path)
    local ok, result = pcall(runHaxeCode, haxeCode)

    if debugEnabled then
        if ok then
            debugOutput('[RELEASE] ' .. path .. ' -> OK', '55FF88')
        else
            debugOutput('[RELEASE] ' .. path .. ' -> FAILED: ' .. tostring(result), 'FF5555')
        end
    end

    return ok and result or false
end
-- Callable Haxe members: FlxTween.tween(...), FlxG.random.int(...), FlxEase.circOut (as ref)

--- true nếu val là number, boolean hoặc string.
function isPrimitive(val)
    local t = type(val)
    return t == 'number' or t == 'boolean' or t == 'string'
end

--[[
    Psych Object API — Module: Proxy Core (classCallable, objectMethodProxy, objectProxy)
    =============================================================================
    Core proxy engine for Haxe interop:
    - classCallable: callable wrapper for ClassName.member (supports .new(), .num(), method calls)
    - objectMethodProxy: enables obj:method(args) syntax instead of obj:call('method', args)
    - objectProxy: main proxy factory for Haxe objects (game.boyfriend, sprites, custom paths)
    
    PROXY METHODS (all proxies have these):
    -------------------------------------
    :get(property, allowMaps?)          -> value (getProperty)
    :set(property, value, allowMaps?, allowInstances?) -> boolean (setProperty)
    :bulkSet(props, allowMaps?, allowInstances?) -> boolean (multiple sets)
    :call(method, args?)                -> any (callMethod or Haxe compilation)
    :path()                             -> string (full Haxe path)
    :getProxyType()                     -> 'object' | 'class'
    
    DYNAMIC BEHAVIOR:
    -----------------
    - Accessing unknown field -> tries native getProperty
    - If getProperty returns path string -> treats as method (returns method proxy)
    - If getProperty returns table/userdata -> creates nested proxy (cached)
    - For Haxe instances (ClassName.new()): uses runHaxeCode/Reflect for all access
    - Method proxies enable fluent chaining: obj:method1():method2()
    
    GLOBALS CREATED:
    ----------------
    classCallable(className, member) -> callable table
    objectMethodProxy(proxy, method) -> function
    isHaxeInstancePath(path) -> boolean
    hasHaxeInstanceRoot(path) -> boolean
    isHaxeInstanceMethod(path, field) -> boolean (async Haxe call)
    objectProxy(path, children?, helpers?, childHelpers?) -> PsychProxy
    
    @module 04_proxy_core
    @see 05_class_proxy.lua for classProxy (static class proxies)
    @see 02_haxe_bridge.lua for ReferenceResolver used by objectProxy.call
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

--- Tạo 1 'hàm gọi được' đại diện cho ClassName.member phía Haxe: hỗ trợ ClassName.new(...) (tạo instance thật), tween kiểu Lua thuần (:num), và gọi method thường/qua compiler tuỳ tham số truyền vào.
---@param className string Tên class Haxe đầy đủ (vd: 'FlxSprite', 'flixel.FlxG')
---@param member string Tên member (method/static property)
---@return table Callable table với __call metamethod
---@usage
--- FlxSprite.new(100, 200)          -- Tạo instance thật, trả về objectProxy
--- FlxTween.tween(obj, {x=100}, 1) -- Gọi static method (qua Haxe compilation nếu có proxy args)
--- FlxEase.circOut                 -- Trả về HaxeRef để dùng làm easing
--- SomeClass.num(0, 100, 1, fn)    -- Lua tween thuần (cần PsychObject.tick trong onUpdate)
---@class LuaNumOptions
---@field ease HaxeRef|nil Easing reference, ví dụ FlxEase.circOut
---@field onUpdate fun(value:number)|nil Callback Lua mỗi frame
---@field onComplete fun(value:number)|nil Callback Lua khi tween kết thúc
---@class NativeNumOptions
---@field ease HaxeRef|nil Easing reference Haxe
---@field target HaxeRef Target property Haxe cần tween native
---@overload fun(from:number, to:number, duration:number, options:LuaNumOptions):boolean
---@overload fun(from:number, to:number, duration:number, options:NativeNumOptions):boolean
function classCallable(className, member)
    return setmetatable({ __isHaxeRef = true, expr = className .. '.' .. member }, {
        __call = function(_, ...)
            local args = { ... }
            if debugEnabled then
                debugOutput(
                    '[HAXE_REF] created -> ' .. className .. '.' .. member,
                    '55AAFF'
                )
            end
            -- ClassName.new(args) -> tạo instance Haxe thật (new ClassName(args)),
            -- lưu vào field ẩn trên game, trả về objectProxy trỏ field đó để dùng
            -- lại được với FlxTween.tween/:call()/... như 1 object thật.
            if member == 'new' then
                local fieldName = ReferenceResolver.executeNewCall(className, args)
                return PsychObject.object(fieldName)
            end

            local luaFn = nil
            local numComplete = nil
            for i = 1, #args do
                if type(args[i]) == 'function' then
                    luaFn = args[i]
                    break
                end
            end
            if type(args[4]) == 'table' then
                if type(args[4].onUpdate) == 'function' then
                    luaFn = args[4].onUpdate
                    
                end
                if type(args[4].onComplete) == 'function' then
                    numComplete = args[4].onComplete
                end
            end

            ---@type string|nil Biểu thức Haxe của property target cho native num
            local haxeTarget = nil
            if type(args[4]) == 'table' then
                local target = args[4].target
                if type(target) == 'table' and target.__isHaxeRef == true then
                    haxeTarget = target.expr
                end
            end
            local optComplete = nil
            for i = 1, #args do
                if type(args[i]) == 'table' then
                    local isRef = args[i].__isHaxeRef == true
                    if not isRef then
                        local ok, pType = pcall(function() return args[i]:getProxyType() end)
                        isRef = ok and (pType == 'object' or pType == 'class')
                    end
                    if not isRef then
                        args[i], optComplete = stripLuaCallbacks(args[i])
                        if optComplete then break end
                    end
                end
            end

            if member == 'num' and not haxeTarget and (luaFn or numComplete) then
                if type(PsychObject.tick) ~= 'function' then
                    error('FlxTween.num with Lua callbacks requires PsychObject.tick(elapsed) in onUpdate(elapsed)', 2)
                end

                local from, to, duration, opts = args[1], args[2], args[3], args[4]
                local ease = luaEaseLinear
                if type(opts) == 'table' and opts.ease and opts.ease.expr and tostring(opts.ease.expr):find('circOut') then
                    ease = luaEaseCircOut
                end
                tInsert(luaTweens, {
                    from = from, to = to, duration = duration or 0, t = 0,
                    ease = ease, onValue = luaFn, onComplete = numComplete
                })
                return true
            end

            if member == 'num' and haxeTarget then
                local from, to, duration, opts = args[1], args[2], args[3], args[4]
                assert(type(from) == 'number', 'FlxTween.num native target requires numeric from')
                assert(type(to) == 'number', 'FlxTween.num native target requires numeric to')
                assert(type(duration) == 'number', 'FlxTween.num native target requires numeric duration')

                local easeExpr = 'FlxEase.linear'
                if type(opts) == 'table'
                    and type(opts.ease) == 'table'
                    and opts.ease.__isHaxeRef == true then
                    easeExpr = opts.ease.expr
                end

                local haxeCode = sFormat([[
var __numTween:FlxTween = %s.num(%s, %s, %s, {
    ease: %s,
    onUpdate: function(value:Float) {
        %s = value;
    }
});
return true;
]], className, tostring(from), tostring(to), tostring(duration), easeExpr, haxeTarget)

                local ok, result = pcall(runHaxeCode, haxeCode)
                if debugEnabled then
                    debugOutput(
                        '[HAXE_NUM] ' .. className .. '.num -> '
                        .. (ok and 'OK' or 'FAILED: ' .. tostring(result)),
                        ok and '55FF88' or 'FF5555'
                    )
                end
                return ok and result or false
            end

            local result = ReferenceResolver.executeClassCall(className, member, args)
            if optComplete then
                tInsert(luaTweens, {
                    from = 0, to = 1, duration = args[3] or args[2] or 0, t = 0,
                    ease = luaEaseLinear, onComplete = function() optComplete(nil) end
                })
            end
            return result
        end
    })
end
--- Bọc proxy:call(method, args) thành 1 hàm Lua gọi trực tiếp được, cho phép cú pháp obj.method(args) thay vì obj:call('method', {args}).
function objectMethodProxy(proxy, method)
    return function(...)
        local args = { ... }

        if args[1] == proxy then
            table.remove(args, 1)
        end

        if debugEnabled then
            debugOutput(
                '[METHOD] '
                .. debugPath(proxy:path())
                .. '.'
                .. method
                .. '()',
                '55AAFF'
            )
        end

        return proxy:call(method, args)
    end
end
--- true nếu path CHÍNH LÀ field ẩn __psychNewInstance_N (không có phần con phía sau).
function isHaxeInstancePath(path)
    return type(path) == 'string'
        and path:match('^__psychNewInstance_%d+$') ~= nil
end

--- true nếu path bắt đầu bằng __psychNewInstance_N. rồi có phần con phía sau (vd __psychNewInstance_1.x).
function hasHaxeInstanceRoot(path)
    return type(path) == 'string'
        and path:match('^__psychNewInstance_%d+%.') ~= nil
end

--- Hỏi thẳng phía Haxe (qua Reflect.isFunction) xem field trên 1 instance ẩn có phải là hàm hay không.
function isHaxeInstanceMethod(path, field)
    if not isHaxeInstancePath(path) and not hasHaxeInstanceRoot(path) then
        return false
    end

    local instanceName = path:match('^(__psychNewInstance_%d+)')
    if not instanceName then
        return false
    end

    local haxeCode = sFormat([[
var __obj = game.variables.get('%s');
if (__obj == null) return false;
var __member = Reflect.getProperty(__obj, '%s');
return Reflect.isFunction(__member);
]], instanceName, field)

    local ok, result = pcall(runHaxeCode, haxeCode)
    return ok and result == true
end


---@class PsychProxy
---@field get fun(self: PsychProxy, property: string, allowMaps?: boolean): any lấy giá trị property (getProperty)
---@field set fun(self: PsychProxy, property: string, value: any, allowMaps?: boolean, allowInstances?: boolean): boolean gán property (setProperty)
---@field bulkSet fun(self: PsychProxy, props: table, allowMaps?: boolean, allowInstances?: boolean): boolean gán nhiều property 1 lượt
---@field call fun(self: PsychProxy, method: string, args?: table): any gọi 1 hàm phía object (callMethod)
---@field path fun(self: PsychProxy): string đường dẫn Haxe đầy đủ của proxy này

--- Tạo 1 proxy object ánh xạ tới 1 đường dẫn property phía Haxe (dùng getProperty/setProperty/callMethod).
--- Đọc field không có trong `children` sẽ tự fallback thành getter/caller theo tên field đó.
---@param path string đường dẫn gốc (rỗng = 'game')
---@param children table? sơ đồ con để tạo proxy lồng nhau có cache
---@param helpers table? hàm phụ trợ gắn thẳng vào proxy gốc
---@param childHelpers table? helpers riêng cho từng proxy con theo key
---@param localValues table<string, any>? property cục bộ cho PsychObject.object()
---@return PsychProxy
function objectProxy(path, children, helpers, childHelpers, localValues)
    local proxy = {}
    local childCache = {}

    local methods = {
        getProxyType = function()
            return 'object'
        end,

        path = function()
            return path
        end,

        get = function(_, property, allowMaps)
            if localValues and localValues[property] ~= nil then
                return localValues[property]
            end

            local fullPath = appendPath(path, property)

            if getPsychNewInstanceRoot(path) then
                local parts, field = splitHaxePropertyPath(property)

                local hxTarget = resolveObjectHaxeExpr(path)

                for _, part in ipairs(parts) do
                    hxTarget = sFormat(
                        "Reflect.getProperty(%s, '%s')",
                        hxTarget,
                        part
                    )
                end

                local haxeCode = sFormat(
                    "return Reflect.getProperty(%s, '%s');",
                    hxTarget,
                    field
                )

                local ok, result = pcall(runHaxeCode, haxeCode)

                if debugEnabled then
                    if ok then
                        debugOutput(
                            '[HAXE_GET] '
                            .. fullPath
                            .. ' | code: '
                            .. haxeCode
                            .. ' | result: '
                            .. debugValue(result),
                            '55AAFF'
                        )
                    else
                        debugOutput(
                            '[HAXE_GET] '
                            .. fullPath
                            .. ' -> FAILED: '
                            .. tostring(result),
                            'FF5555'
                        )
                    end
                end

                return ok and result or nil
            end

            return getProperty(
                fullPath,
                allowMaps == true
            )
        end,

        set = function(_, property, value, allowMaps, allowInstances)
            if localValues then
                localValues[property] = value
                return true
            end

            local fullPath = appendPath(path, property)

            if getPsychNewInstanceRoot(path) then
                local parts, field = splitHaxePropertyPath(property)

                local hxTarget = resolveObjectHaxeExpr(path)

                for _, part in ipairs(parts) do
                    hxTarget = sFormat(
                        "Reflect.getProperty(%s, '%s')",
                        hxTarget,
                        part
                    )
                end

                local hxValue = ReferenceResolver.serialize(value)

                local haxeCode = sFormat(
                    "Reflect.setProperty(%s, '%s', %s); return true;",
                    hxTarget,
                    field,
                    hxValue
                )

                local ok, result = pcall(runHaxeCode, haxeCode)

                if debugEnabled then
                    if ok then
                        debugOutput(
                            '[HAXE_SET] '
                            .. fullPath
                            .. ' = '
                            .. debugValue(value)
                            .. ' | code: '
                            .. haxeCode,
                            '55AAFF'
                        )
                    else
                        debugOutput(
                            '[HAXE_SET] '
                            .. fullPath
                            .. ' -> FAILED: '
                            .. tostring(result),
                            'FF5555'
                        )
                    end
                end

                return ok and result or false
            end

            local result = setProperty(
                fullPath,
                value,
                allowMaps == true,
                allowInstances == true
            )

            if debugEnabled then
                debugTrace(
                    debugPath(fullPath)
                    .. ' = '
                    .. debugValue(value),
                    result
                )
            end

            return result
        end,

        bulkSet = function(_, props, allowMaps, allowInstances)
            local allSucceeded = true
            for k, v in pairs(props) do
                local fullPath = appendPath(path, k)

                local ok = true

                if hasHaxeInstanceRoot(path) or isHaxeInstancePath(path) then
                    local hxTarget = resolveObjectHaxeExpr(path)
                    local hxValue = ReferenceResolver.serialize(v)

                    local haxeCode = sFormat(
                        "Reflect.setProperty(%s, '%s', %s); return true;",
                        hxTarget,
                        k,
                        hxValue
                    )

                    local hxOk, hxResult = pcall(runHaxeCode, haxeCode)
                    ok = hxOk and hxResult ~= false

                    if debugEnabled then
                        if hxOk then
                            debugOutput(
                                '[HAXE_SET] ' .. fullPath .. ' (bulkSet) | code: ' .. haxeCode,
                                '55AAFF'
                            )
                        else
                            debugOutput(
                                '[HAXE_SET] ' .. fullPath .. ' (bulkSet) -> FAILED: ' .. tostring(hxResult),
                                'FF5555'
                            )
                        end
                    end
                else
                    ok = setProperty(
                        fullPath,
                        v,
                        allowMaps == true,
                        allowInstances == true
                    )
                end

                if not ok then allSucceeded = false end
            end

            if debugEnabled then
                debugTrace(
                    'bulkSet ' .. path,
                    allSucceeded
                )
            end

            return allSucceeded
        end,

        call = function(_, method, args)
            if getPsychNewInstanceRoot(path)
                or ReferenceResolver.needsCompilation(args) then

                return ReferenceResolver.executeObjectCall(
                    path,
                    method,
                    args
                )
            end

            local fullPath = appendPath(path, method)
            local result = callMethod(
                fullPath,
                args or {}
            )

            if debugEnabled then
                debugTrace(
                    'call ' .. fullPath,
                    result
                )
            end

            return result
        end,
    }

    local lookup = methods
    if helpers then
        for k, v in pairs(helpers) do
            if lookup[k] == nil then lookup[k] = v end
        end
    end

    return setmetatable(proxy, {
        __index = function(_, key)
            -- ============================================================
            -- Internal fields
            -- ============================================================
            if type(key) == 'string' and key:sub(1, 2) == '__' then
                return nil
            end

            -- ============================================================
            -- Registered methods / helpers
            -- ============================================================
            local found = lookup[key]
            if found then
                return found
            end

            -- ============================================================
            -- Explicit child proxy
            -- ============================================================
            local child = children and children[key]

            if child then
                local cached = childCache[key]

                if not cached then
                    local childHelper = childHelpers and childHelpers[key] or nil

                    cached = objectProxy(
                        appendPath(path, key),
                        child,
                        childHelper
                    )

                    childCache[key] = cached
                end

                return cached
            end

            local fullPath = appendPath(path, key)

                if localValues and localValues[key] ~= nil then
                    return localValues[key]
                end

            -- ============================================================
            -- HAXE INSTANCE DYNAMIC NESTED PROXY
            --
            -- Cho phép:
            --   sprite.scale.x
            --   sprite.scale.y
            --   sprite.offset.x
            --   sprite.velocity.x
            --   sprite.someObject.someField
            -- ============================================================
            local isInstancePath =
                isHaxeInstancePath(path)
                or hasHaxeInstanceRoot(path)

            if isInstancePath then
                local ok, val = pcall(getProperty, fullPath)

                if ok and val ~= nil then
                    local valueType = type(val)

                    -- ========================================================
                    -- Sentinel: getProperty trả lại chính fullPath.
                    -- Trường hợp này có thể là METHOD hoặc OBJECT.
                    -- Không tự kết luận là method.
                    -- ========================================================
                    if valueType == 'string' and val == fullPath then
                        if isHaxeInstanceMethod(path, key) then
                            if debugEnabled then
                                debugOutput(
                                    '[METHOD_DETECT] '
                                    .. debugPath(fullPath)
                                    .. ' -> confirmed Haxe function',
                                    '55AAFF'
                                )
                            end

                            return objectMethodProxy(proxy, key)
                        end

                        local cached = childCache[key]

                        if not cached then
                            cached = objectProxy(fullPath)
                            childCache[key] = cached
                        end

                        if debugEnabled then
                            debugOutput(
                                '[DYNAMIC_PROXY] '
                                .. debugPath(fullPath)
                                .. ' -> nested Haxe object',
                                '55AAFF'
                            )
                        end

                        return cached
                    end

                    -- ========================================================
                    -- Primitive property -> trả value trực tiếp
                    -- ========================================================
                    if valueType == 'number'
                        or valueType == 'boolean'
                        or valueType == 'string' then

                        if debugEnabled then
                            debugOutput(
                                '[HAXE_PROPERTY_GET] '
                                .. debugPath(fullPath)
                                .. ' | type='
                                .. valueType
                                .. ' | value='
                                .. debugValue(val),
                                '55FF88'
                            )
                        end

                        return val
                    end

                    -- ========================================================
                    -- Object property -> tạo nested proxy
                    -- ========================================================
                    local cached = childCache[key]

                    if not cached then
                        cached = objectProxy(fullPath)
                        childCache[key] = cached
                    end

                    if debugEnabled then
                        debugOutput(
                            '[DYNAMIC_PROXY] '
                            .. debugPath(fullPath)
                            .. ' -> nested object proxy',
                            '55AAFF'
                        )
                    end

                    return cached
                end

                -- ============================================================
                -- Không resolve được:
                -- vẫn tạo proxy để cho phép chain sâu hơn.
                -- ============================================================
                local cached = childCache[key]

                if not cached then
                    cached = objectProxy(fullPath)
                    childCache[key] = cached
                end

                if debugEnabled then
                    debugOutput(
                        '[DYNAMIC_PROXY] '
                        .. debugPath(fullPath)
                        .. ' -> unresolved nested proxy',
                        '55AAFF'
                    )
                end

                return cached
            end

            -- ============================================================
            -- NORMAL OBJECT LOOKUP
            -- ============================================================
            local ok, val = pcall(getProperty, fullPath)

            if ok and val ~= nil then

                -- Psych Engine trả lại chính path khi member không phải
                -- property thật -> coi như method
                if type(val) == 'string' and val == fullPath then

                    if debugEnabled then
                        debugOutput(
                            '[METHOD_DETECT] '
                            .. debugPath(fullPath)
                            .. ' -> native getter returned path; treating as method',
                            '55AAFF'
                        )
                    end

                    return objectMethodProxy(proxy, key)
                end

                if debugEnabled then
                    debugOutput(
                        '[PROPERTY_GET] '
                        .. debugPath(fullPath)
                        .. ' | type='
                        .. type(val)
                        .. ' | value='
                        .. debugValue(val),
                        '55FF88'
                    )
                end

                return val
            end

            -- ============================================================
            -- Native lookup failed -> dynamic method proxy
            -- ============================================================
            if type(key) == 'string' then

                if debugEnabled then
                    debugOutput(
                        '[METHOD_REF] '
                        .. debugPath(fullPath)
                        .. ' -> method proxy',
                        '55AAFF'
                    )
                end

                return objectMethodProxy(proxy, key)
            end

            return nil
        end,
        __newindex = function(_, key, value)
            if localValues then
                localValues[key] = value
                return
            end

            local fullPath = appendPath(path, key)

            if isHaxeInstancePath(path) or hasHaxeInstanceRoot(path) then
                local hxTarget = resolveObjectHaxeExpr(path)
                local hxValue = ReferenceResolver.serialize(value)

                local haxeCode = sFormat(
                    "Reflect.setProperty(%s, '%s', %s); return true;",
                    hxTarget,
                    key,
                    hxValue
                )

                local result = runHaxeCode(haxeCode)

                if debugEnabled then
                    debugOutput(
                        '[HAXE_SET] '
                        .. fullPath
                        .. ' = '
                        .. debugValue(value)
                        .. ' | code: '
                        .. haxeCode,
                        result == false and 'FF5555' or '55AAFF'
                    )
                end

                return
            end

            local result = setProperty(
                fullPath,
                value
            )

            if debugEnabled then
                debugTrace(
                    debugPath(fullPath)
                    .. ' = '
                    .. debugValue(value),
                    result
                )

                if result == false then
                    debugOutput(
                        'set object property '
                        .. debugPath(fullPath)
                        .. ' failed -> false',
                        'FF5555'
                    )
                end
            end
        end
    })
end


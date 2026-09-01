-- ============================================================
-- Psych Object API — module: classProxy + PsychObject.object/class/group
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

--- Tạo 1 proxy đại diện cho 1 class Haxe (static): hỗ trợ get/set/call/bulkSet property tĩnh, children lồng nhau có cache, và ClassName.instance để lấy object proxy gốc.
function classProxy(className, children)
    local proxy = {}
    local childCache = {}

    local function classObjectProxy(path, childNodes, helpers)
        local classObject = {}
        local classChildCache = {}

        local classObjectMethods = {
            getProxyType = function() return 'class' end,
            className = function()
                return className .. (path ~= '' and ('.' .. path) or '')
            end,
            get = function(_, property, allowMaps)
                return getPropertyFromClass(className, appendPath(path, property), allowMaps == true)
            end,
            set = function(_, property, value, allowMaps, allowInstances)
                local fullPath = appendPath(path, property)
                local result = setPropertyFromClass(className, fullPath, value, allowMaps == true, allowInstances == true)
                if debugEnabled then debugTrace('set ' .. className .. '.' .. fullPath, result) end
                return result
            end,
            bulkSet = function(_, props, allowMaps, allowInstances)
                for k, v in pairs(props) do
                    setPropertyFromClass(className, appendPath(path, k), v, allowMaps == true, allowInstances == true)
                end
                if debugEnabled then debugTrace('bulkSet ' .. className .. '.' .. path, true) end
                return true
            end,
            call = function(_, method, args)
                args = args or {}

                local fullMethodPath = appendPath(path, method)
                local result

                if fullMethodPath:find('.', 1, true)
                    or ReferenceResolver.needsCompilation(args) then

                    result = ReferenceResolver.executeClassCall(
                        className,
                        fullMethodPath,
                        args
                    )
                else
                    result = callMethodFromClass(
                        className,
                        fullMethodPath,
                        args
                    )
                end

                if debugEnabled then
                    debugTrace(
                        'call ' .. className .. '.' .. fullMethodPath,
                        result
                    )
                end

                return result
            end
        }

        local lookup = classObjectMethods
        if helpers then
            for k, v in pairs(helpers) do
                if lookup[k] == nil then lookup[k] = v end
            end
        end

        return setmetatable(classObject, {
            __index = function(_, key)
                local found = lookup[key]
                if found then return found end

                local child = childNodes and childNodes[key]
                if child then
                    if not classChildCache[key] then
                        classChildCache[key] = classObjectProxy(appendPath(path, key), child)
                    end
                    return classChildCache[key]
                end

                local fullPath = appendPath(path, key)
                local ok, val = pcall(getPropertyFromClass, className, fullPath)
                if ok and val ~= nil then
                    if type(val) == 'string' then
                        return classCallable(className, fullPath)
                    end

                    return val
                end
                if debugEnabled then
                    debugOutput('missing class property ' .. className .. '.' .. fullPath .. ' -> nil', 'FFAA00')
                end
                return classCallable(className, fullPath)
            end,
            __newindex = function(_, key, value)
                local fullPath = appendPath(path, key)
                local result = setPropertyFromClass(className, fullPath, value)
                if debugEnabled then
                    debugTrace('set ' .. className .. '.' .. fullPath, result)
                    if result == false then
                        debugOutput('set class property ' .. className .. '.' .. fullPath .. ' failed -> false', 'FF5555')
                    end
                end
            end
        })
    end

    local methods = {
        getProxyType = function() return 'class' end,
        get = function(_, property, allowMaps)
            return getPropertyFromClass(className, property, allowMaps == true)
        end,
        set = function(_, property, value, allowMaps, allowInstances)
            local result = setPropertyFromClass(className, property, value, allowMaps == true, allowInstances == true)
            if debugEnabled then debugTrace('set ' .. className .. '.' .. property, result) end
            return result
        end,
        bulkSet = function(_, props, allowMaps, allowInstances)
            for k, v in pairs(props) do
                setPropertyFromClass(className, k, v, allowMaps == true, allowInstances == true)
            end
            if debugEnabled then debugTrace('bulkSet ' .. className, true) end
            return true
        end,
        call = function(_, method, args)
            if ReferenceResolver.needsCompilation(args) then
                return ReferenceResolver.executeClassCall(className, method, args)
            else
                local result = callMethodFromClass(className, method, args or {})
                if debugEnabled then debugTrace('call ' .. className .. '.' .. method, result) end
                return result
            end
        end,
        className = function() return className end,
    }

 

    return setmetatable(proxy, {
            __index = function(_, key)

                -- ============================================================
                -- 1. instance phải được xử lý TRƯỚC khi chặn "__"
                -- ============================================================


                -- Chặn internal fields
                if type(key) == 'string' and key:sub(1, 2) == '__' then
                    return nil
                end

                -- ============================================================
                -- 2. Proxy methods
                -- ============================================================
                if methods[key] then
                    return methods[key]
                end

                -- ============================================================
                -- 3. Explicit child proxy
                -- ============================================================
                local child = children and children[key]
                if child then
                    if not childCache[key] then
                        local helpers = (key == 'game') and gameHelpers or nil
                        childCache[key] = classObjectProxy(key, child, helpers)
                    end

                    if debugEnabled then
                        debugOutput(
                            '[CHILD] ' .. className .. '.' .. tostring(key)
                            .. ' -> proxy',
                            '55AAFF'
                        )
                    end

                    return childCache[key]
                end

                -- ============================================================
                -- 4. Native static property lookup
                -- ============================================================
                local fullPath = key
                local ok, val = pcall(
                    getPropertyFromClass,
                    className,
                    fullPath
                )

                if ok and val ~= nil then
                    -- Psych Engine trả về string tên method cho static function
                    -- wrap thành classCallable để có .expr cho easing detection
                    if type(val) == 'string' then
                        return classCallable(className, fullPath)
                    end
                    if debugEnabled then
                        debugOutput(
                            '[STATIC_GET] '
                            .. className .. '.' .. tostring(fullPath)
                            .. ' -> '
                            .. debugValue(val),
                            '55FF88'
                        )
                    end

                    return val
                end

                -- ============================================================
                -- 5. Native lookup không resolve được:
                --    giữ lại thành Haxe reference
                -- ============================================================
                if debugEnabled then
                    local reason

                    if not ok then
                        reason = 'native lookup raised an error'
                    else
                        reason = 'native lookup returned nil'
                    end

                    debugOutput(
                        '[STATIC_REF] '
                        .. className .. '.' .. tostring(fullPath)
                        .. ' -> Haxe reference'
                        .. ' | reason: ' .. reason,
                        '55AAFF'
                    )
                end

                return classCallable(className, fullPath)
            end,


        __newindex = function(_, key, value)
            local result = setPropertyFromClass(className, key, value)
            if debugEnabled then
                debugTrace('set ' .. className .. '.' .. key, result)
                if result == false then
                    debugOutput('set static property ' .. className .. '.' .. key .. ' failed -> false', 'FF5555')
                end
            end
        end
    })
end

--- Tạo 1 object proxy tuỳ ý theo path property (dùng cho các object không có alias sẵn).
function PsychObject.object(path, children)
    return objectProxy(path, children, nil, nil, {})
end
--- Tạo 1 class proxy tuỳ ý theo tên class Haxe đầy đủ (dùng cho các class không có alias sẵn).
function PsychObject.class(className, children) return classProxy(className, children) end

---@class PsychGroupProxy : PsychProxy
---@field path fun(self: PsychGroupProxy): string đường dẫn dạng groupName..index
---@field get fun(self: PsychGroupProxy, property: string, allowMaps?: boolean): any đọc property của phần tử trong group
---@field set fun(self: PsychGroupProxy, property: string, value: any, allowMaps?: boolean, allowInstances?: boolean): boolean ghi property của phần tử trong group
--- Tạo proxy cho một phần tử trong group Note/Strum.
---@param groupName string tên group phía Haxe
---@param index integer vị trí phần tử trong group
---@return PsychGroupProxy
function newGroupProxy(groupName, index)
    local methods = {
        getProxyType = function()
            return 'object'
        end,
        path = function()
            return groupName .. tostring(index)
        end,
        get = function(_, property, allowMaps)
            return getPropertyFromGroup(groupName, index, property, allowMaps == true)
        end,
        set = function(_, property, value, allowMaps, allowInstances)
            local result = setPropertyFromGroup(groupName, index, property, value, allowMaps == true, allowInstances == true)
            if debugEnabled then debugTrace('set group ' .. groupName .. '[' .. index .. '].' .. property, result) end
            return result
        end
    }

    return setmetatable({}, {
        __index = function(_, key)
            if methods[key] then return methods[key] end
            return getPropertyFromGroup(groupName, index, key)
        end,
        __newindex = function(_, key, value)
            local result = setPropertyFromGroup(groupName, index, key, value)
            if debugEnabled then debugTrace('set group ' .. groupName .. '[' .. index .. '].' .. key, result) end
        end
    })
end

groupProxyCache = {}
--- Lấy proxy cho 1 group Note/Strum. Không truyền index -> tạo proxy mới không cache
--- (dùng để truy cập group như 1 danh sách chung). Có index -> lấy từ cache theo groupName+index.
---@param groupName string tên group phía Haxe (vd 'notes', 'playerStrums', 'unspawnNotes'...)
---@param index integer? vị trí phần tử trong group; nil = trả proxy group chung
function PsychObject.group(groupName, index)
    if index == nil then return newGroupProxy(groupName, index) end
    local cache = groupProxyCache[groupName]
    if not cache then cache = {}; groupProxyCache[groupName] = cache end
    local proxy = cache[index]
    if not proxy then proxy = newGroupProxy(groupName, index); cache[index] = proxy end
    return proxy
end

--- Xoá toàn bộ cache (sprite, text, group, tween Lua) — GỌI TỪ onDestroy() HOẶC onSongStart()
function PsychObject.clearCache()
    if #luaTweens > 0 and psychTickCount == 0 and debugEnabled then
        debugWrite(
            'error',
            'tween',
            'Lua tween was never updated. Add PsychObject.tick(elapsed) to onUpdate(elapsed).',
            'FF5555'
        )
    end

    luaTweens = {}
    spriteProxyCache = {}
    textProxyCache = {}
    groupProxyCache = {}
    if debugEnabled then debugWrite('info', 'cache', 'Cleared all PsychObject caches', '55AAFF') end
    return true
end


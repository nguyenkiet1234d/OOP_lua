--[[
    Psych Object API — Module: Debug Core (v2.0.0)
    ================================================
    Internal logging engine with advanced features:
    - Log levels: trace < debug < info < warn < error < off
    - Categories for filtering
    - Sequence IDs, timestamps, caller info, step tracking
    - Configurable history limit (default 5000 entries)
    - Statistics counters (total, per-level, per-category)
    - Profiling (start/stop with min/max/avg tracking)
    - Output modes: console, file, both
    - Context serialization for tables
    - Recursion protection
    
    GLOBALS CREATED:
    ----------------
    debugEnabled, debugHistory, debugMode, debugLogPath, debugFileHandle
    debugTerminalOpened, debugLevelNames, debugLevel, debugHistoryLimit
    debugVersion, debugStartedAt, debugMuted, debugSequence
    debugWriteInProgress, debugCategoryFilter, debugCallerEnabled
    debugTimestampEnabled, debugStepEnabled, debugContextEnabled
    debugPrefix, debugIndent, debugStats, debugProfiles, debugActiveProfiles
    
    @module 01_debug_core
    @version 2.0.0
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

PsychObject = {}

-- ============================================================
-- MAX DEBUG SYSTEM v2.0
-- ============================================================
-- Backwards-compatible với Debug.enable/info/mode/file/history/clear.
-- Có thêm:
--   levels, categories, sequence id, timestamps, caller, context,
--   history limit, counters, profiling, filtering, dump/assert/flush.
-- ============================================================
---@type boolean Bật/tắt toàn bộ hệ thống debug
debugEnabled = false
---@type table[] Lịch sử log entries (giới hạn debugHistoryLimit)
debugHistory = {}
---@type 'console'|'file'|'both' Chế độ output
debugMode = 'console'
---@type string Đường dẫn file log
debugLogPath = 'mods/psych_object_api.log'
---@type file*|nil Handle file log hiện tại
debugFileHandle = nil
---@type boolean Đã mở terminal debug (dành cho tương lai)
debugTerminalOpened = false

---@type table<string, integer> Map tên level -> priority (thấp = chi tiết hơn)
debugLevelNames = {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
    off = 99
}

---@type string Level hiện tại (trace|debug|info|warn|error|off)
debugLevel = 'trace'
---@type integer Giới hạn số entry trong lịch sử
debugHistoryLimit = 5000
---@type string Phiên bản debug system
debugVersion = '2.0.0'
---@type number Thời điểm khởi tạo (os.clock)
debugStartedAt = os.clock()
---@type boolean Mute tạm thời (không log nhưng vẫn cập nhật stats)
debugMuted = false
---@type integer Sequence ID tự tăng cho mỗi dòng log
debugSequence = 0
---@type boolean Flag chống đệ quy khi log callback gọi lại debugWrite
debugWriteInProgress = false
---@type table<string, boolean>|nil Bộ lọc category (nil = không lọc)
debugCategoryFilter = nil
---@type boolean Bật hiển thị caller (file:line)
debugCallerEnabled = false
---@type boolean Bật timestamp (t=xx.xxxxxx)
debugTimestampEnabled = true
---@type boolean Bật step (curStep)
debugStepEnabled = true
---@type boolean Bật context (ctx={...})
debugContextEnabled = true
---@type string Prefix cho mỗi dòng log
debugPrefix = 'PsychObject'
---@type integer Indent level (dành cho tương lai)
debugIndent = 0
---@type table Thống kê log
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
---@type table<string, table> Profiling data (min/max/avg/calls)
debugProfiles = {}
---@type table<string, table> Active profiling sessions
debugActiveProfiles = {}

--- Lấy mốc thời gian hiện tại (giây), dùng cho timestamp log và profiling.
---@return number Thời gian từ os.clock()
function debugNow()
    return os.clock()
end

--- Chuẩn hoá tên level về chữ thường hợp lệ; trả 'info' nếu level không tồn tại trong debugLevelNames.
---@param level string|nil Tên level (trace/debug/info/warn/error/off)
---@return string Level đã chuẩn hoá
function debugNormalizeLevel(level)
    level = tostring(level or 'info'):lower()
    if debugLevelNames[level] == nil then return 'info' end
    return level
end

--- Kiểm tra 1 dòng log có nên được ghi hay không, dựa vào enable/mute, ngưỡng level và bộ lọc category.
---@param level string Tên level
---@param category string|nil Category của log
---@return boolean True nếu nên ghi log
function debugShouldLog(level, category)
    if not debugEnabled or debugMuted then return false end

    level = debugNormalizeLevel(level)
    if debugLevel == 'off' then return false end
    if debugLevelNames[level] < debugLevelNames[debugLevel] then return false end

    if debugCategoryFilter then
        if debugCategoryFilter[category] ~= true and debugCategoryFilter['*'] ~= true then
            return false
        end
    end

    return true
end

--- Chuyển value thành chuỗi và loại bỏ ký tự xuống dòng để không làm vỡ format 1 dòng log.
---@param value any Giá trị bất kỳ
---@return string Chuỗi đã sanitize
function debugSanitizeString(value)
    local text = tostring(value)
    text = text:gsub('[\r\n]+', ' ')
    return text
end

--- Serialize 1 giá trị bất kỳ (kể cả table lồng nhau, có chống vòng lặp/giới hạn độ sâu) thành chuỗi để in trong log.
---@param value any Giá trị cần serialize
---@param depth integer|nil Độ sâu hiện tại (internal)
---@param seen table|nil Set các table đã thấy (internal, chống vòng lặp)
---@return string Chuỗi biểu diễn giá trị
function debugValue(value, depth, seen)
    if value == nil then return 'nil' end

    local valueType = type(value)

    if valueType == 'string' then
        return sFormat('%q', value)
    end

    if valueType == 'number' or valueType == 'boolean' then
        return tostring(value)
    end

    if valueType == 'function' then
        return '<function>'
    end

    if valueType == 'userdata' then
        return '<userdata:' .. tostring(value) .. '>'
    end

    if valueType ~= 'table' then
        return tostring(value)
    end

    depth = depth or 0
    seen = seen or {}

    if seen[value] then return '<cycle>' end
    if depth >= 3 then return '{...}' end

    seen[value] = true

    local parts = {}
    local count = 0

    for key, item in pairs(value) do
        count = count + 1
        if count > 32 then
            tInsert(parts, '...')
            break
        end
        tInsert(
            parts,
            tostring(key) .. '=' .. debugValue(item, depth + 1, seen)
        )
    end

    seen[value] = nil
    return '{' .. tConcat(parts, ', ') .. '}'
end

--- Rút gọn 'boyfriend...' thành 'bf...' để log ngắn gọn, dễ đọc hơn.
---@param path string Đường dẫn object
---@return string Đường dẫn rút gọn
function debugPath(path)
    path = tostring(path or '')
    if path == 'boyfriend' then return 'bf' end
    if path:sub(1, 10) == 'boyfriend.' then return 'bf' .. path:sub(10) end
    return path
end

--- Lấy vị trí (file:dòng) của nơi gọi log, chỉ hoạt động khi debugCallerEnabled = true.
---@return string|nil Vị trí caller hoặc nil nếu không lấy được
---@note Stack level 4 giả định call chain: user -> Debug.info -> debugWrite -> debugBuildLine -> debugCaller
function debugCaller()
    if not debugCallerEnabled then return nil end
    local ok, info = pcall(function()
        return debug.getinfo(4, 'Sl')
    end)
    if not ok or not info then return nil end

    local source = info.short_src or info.source or '?'
    local line = info.currentline or info.linedefined or 0
    return source .. ':' .. tostring(line)
end

--- Đóng file log hiện tại (nếu đang mở) một cách an toàn, bỏ qua lỗi nếu có.
function closeDebugFile()
    if debugFileHandle then
        pcall(function() debugFileHandle:flush() end)
        pcall(function() debugFileHandle:close() end)
        debugFileHandle = nil
    end
end

--- Mở file log nếu chưa mở; trả về true/false kèm thông báo lỗi nếu mở thất bại.
---@return boolean success
---@return string|nil errorMessage
function ensureDebugFile()
    if debugFileHandle then return true end
    local file, errorMessage = io.open(debugLogPath, 'a')
    if not file then return false, errorMessage end
    debugFileHandle = file
    return true
end

--- Ghi 1 dòng vào file log; tự đóng file nếu ghi lỗi để tránh log rác/handle hỏng.
---@param message string Dòng log cần ghi
---@return boolean success
---@return string|nil errorMessage
function writeDebugFile(message)
    local ok, errorMessage = ensureDebugFile()
    if not ok then return false, errorMessage end

    local success, writeError = pcall(function()
        debugFileHandle:write(message .. '\n')
        debugFileHandle:flush()
    end)

    if not success then
        closeDebugFile()
        return false, writeError
    end

    return true
end

--- Thêm 1 entry vào lịch sử log, tự cắt bớt các entry cũ nhất khi vượt quá debugHistoryLimit.
---@param entry table Entry log (id, time, step, level, category, message, context, line)
function debugPushHistory(entry)
    tInsert(debugHistory, entry)

    while #debugHistory > debugHistoryLimit do
        tRemove(debugHistory, 1)
    end
end

--- Ghép 1 dòng log hoàn chỉnh: prefix, số thứ tự, level, category, timestamp, step, caller, context.
---@param level string Level log
---@param category string|nil Category
---@param message string Nội dung
---@param context any|nil Context data
---@return string Dòng log hoàn chỉnh
function debugBuildLine(level, category, message, context)
    debugSequence = debugSequence + 1

    local now = debugNow()
    local prefix = '[' .. debugPrefix .. ']'
    local seq = sFormat('[#%06d]', debugSequence)
    local levelText = '[' .. string.upper(level) .. ']'
    local categoryText = category and ('[' .. tostring(category) .. ']') or ''

    local meta = {}

    if debugTimestampEnabled then
        tInsert(meta, sFormat('t=%.6f', now))
    end

    if debugStepEnabled then
        tInsert(meta, 'step=' .. tostring(curStep or 0))
    end

    if debugCallerEnabled then
        local caller = debugCaller()
        if caller then tInsert(meta, 'at=' .. caller) end
    end

    local elapsed = now - debugStartedAt
    local line = prefix .. seq .. levelText .. categoryText .. ' ' .. debugSanitizeString(message)
    line = line .. sFormat(' | +%.6fs', elapsed)

    if #meta > 0 then
        line = line .. ' | ' .. tConcat(meta, ' ')
    end

    if debugContextEnabled and context ~= nil then
        line = line .. ' | ctx=' .. debugValue(context)
    end

    return line
end

--- Hàm ghi log lõi: cập nhật thống kê, lưu lịch sử, in console và/hoặc ghi file tuỳ debugMode.
---@param level string Level log
---@param category string|nil Category
---@param message string Nội dung
---@param color string|nil Màu hex (cho Debug.info)
---@param context any|nil Context data
---@return boolean True nếu ghi thành công
function debugWrite(level, category, message, color, context)
    if debugWriteInProgress then
        -- Prevent recursive logging when a logger callback (Debug.info/Debug.warn/etc.) re-enters debugWrite.
        if debugMode == 'console' or debugMode == 'both' then
            pcall(function() print(tostring(message)) end)
        end
        return false
    end

    if not debugShouldLog(level, category) then return false end

    debugWriteInProgress = true

    local ok = pcall(function()
        level = debugNormalizeLevel(level)
        category = category or 'core'
        message = tostring(message)

        debugStats.total = debugStats.total + 1
        debugStats[level] = (debugStats[level] or 0) + 1
        debugStats.byCategory[category] = (debugStats.byCategory[category] or 0) + 1

        if level == 'error' then
            debugStats.failed = debugStats.failed + 1
        end

        local line = debugBuildLine(level, category, message, context)

        local entry = {
            id = debugSequence,
            time = debugNow(),
            step = curStep or 0,
            level = level,
            category = category,
            message = message,
            context = context,
            line = line
        }

        debugPushHistory(entry)

        if debugMode == 'console' or debugMode == 'both' then
            if Debug and Debug.info then
                pcall(function() Debug.info(line, color or 'FFFFFF') end)
            end
            print(line)
        end

        if debugMode == 'file' or debugMode == 'both' then
            local okFile, errorMessage = writeDebugFile(line)
            if not okFile then
                -- Do not recurse through debug logging when file output itself fails.
                print('[PsychObject][ERROR] debug file write failed: ' .. tostring(errorMessage))
            end
        end

        return true
    end)

    debugWriteInProgress = false
    return ok and true or false
end

-- Legacy entry point: existing code can continue calling debugOutput(message, color).
--- Entry point log kiểu cũ (tương thích ngược với code cũ đang gọi debugOutput), uỷ quyền cho debugWrite.
---@param message string Nội dung
---@param color string|nil Màu hex
---@param level string|nil Level (mặc định 'debug')
---@param category string|nil Category (mặc định 'core')
---@param context any|nil Context data
---@return boolean
function debugOutput(message, color, level, category, context)
    return debugWrite(level or 'debug', category or 'core', message, color, context)
end

--- Log nhanh 1 hành động kèm kết quả OK/FAILED (result == false thì tính là FAILED).
---@param action string Mô tả hành động
---@param result boolean|any Kết quả (false = FAILED)
---@return any Trả về result gốc
function debugTrace(action, result)
    local failed = result == false
    local level = failed and 'error' or 'trace'
    local suffix = failed and ' -> FAILED' or ' -> OK'
    debugWrite(level, 'trace', tostring(action) .. suffix, failed and 'FF5555' or '55FF88')
    return result
end

--- Log cảnh báo khi truy cập 1 property/method không tồn tại; luôn trả về nil.
---@param kind string Loại truy cập ('get'|'set'|'call')
---@param path string Đường dẫn property
---@return nil
function debugMissingAccess(kind, path)
    debugWrite(
        'warn',
        'access',
        tostring(kind) .. ' ' .. tostring(path) .. ' -> nil',
        'FFAA00'
    )
    return nil
end

--- Bắt đầu đo thời gian cho 1 profile theo tên (dùng chung với debugStopProfile).
---@param name string Tên profile
---@param category string|nil Category (mặc định 'profile')
---@return boolean True nếu bắt đầu thành công
function debugStartProfile(name, category)
    name = tostring(name)
    debugActiveProfiles[name] = {
        name = name,
        category = category or 'profile',
        started = debugNow(),
        count = 1
    }
    return true
end

--- Kết thúc đo thời gian 1 profile, cập nhật thống kê min/max/avg và ghi log kết quả.
---@param name string Tên profile
---@return number|nil Thời gian elapsed hoặc nil nếu không tìm thấy profile
function debugStopProfile(name)
    name = tostring(name)
    local active = debugActiveProfiles[name]
    if not active then
        debugWrite('warn', 'profile', 'stopProfile without start: ' .. name, 'FFAA00')
        return nil
    end

    local elapsed = debugNow() - active.started
    debugActiveProfiles[name] = nil

    local profile = debugProfiles[name]
    if not profile then
        profile = {
            name = name,
            category = active.category,
            calls = 0,
            total = 0,
            min = nil,
            max = nil,
            last = 0
        }
        debugProfiles[name] = profile
    end

    profile.calls = profile.calls + 1
    profile.total = profile.total + elapsed
    profile.last = elapsed
    profile.min = profile.min == nil and elapsed or math.min(profile.min, elapsed)
    profile.max = profile.max == nil and elapsed or math.max(profile.max, elapsed)

    debugWrite(
        'debug',
        'profile',
        sFormat(
            '%s -> %.6fs (avg %.6fs)',
            name,
            elapsed,
            profile.total / profile.calls
        ),
        'AAAAFF'
    )

    return elapsed
end


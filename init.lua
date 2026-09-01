-- ============================================================
-- Psych Object API for Psych Engine 1.0.4 — bản TÁCH FILE.
-- Load duy nhất file này từ script bài hát/mod của bạn:
--   dofile('mods/My-Mod/data/init.lua')
--
-- File này chỉ dofile() các module con theo ĐÚNG THỨ TỰ bên dưới.
-- KHÔNG đổi thứ tự — nhiều module dùng lại hàm/bảng của module load trước
-- (PsychObject, ReferenceResolver, objectProxy, debugXxx... đều là
-- biến toàn cục dùng chung giữa các file trong cùng thư mục này).
--
-- Nếu bạn đổi tên thư mục mod, chỉ cần sửa MODULE_DIR bên dưới.
-- ============================================================

---@alias PsychProxy table<string, any> Proxy object với các method: get, set, bulkSet, call, path, getProxyType
---@alias PsychSpriteProxy PsychProxy & {add:fun(inFront?:boolean), remove:fun(destroy?:boolean,group?:string), makeGraphic:fun(w:number,h:number,color?:string), addAnimation:fun(name:string,prefix:string,frameRate?:number,loop?:boolean):boolean, addAnimationByIndices:fun(name:string,prefix:string,indices:number[],frameRate?:number,loop?:boolean):boolean, play:fun(name:string,forced?:boolean,reverse?:boolean,startFrame?:number):boolean, scaleTo:fun(x:number,y?:number,updateHitbox?:boolean), scroll:fun(x:number,y?:number), camera:fun(camera?:string), center:fun(axis?:'x'|'y'|'xy'), blend:fun(mode?:string), shader:fun(shaderName:string):boolean, removeShader:fun():boolean, shaderFloat:fun(uniform:string,value:number), shaderInt:fun(uniform:string,value:integer), shaderBool:fun(uniform:string,value:boolean), shaderFloats:fun(uniform:string,values:number[]), shaderTexture:fun(uniform:string,imagePath:string)}
---@alias PsychTextProxy PsychProxy & {add:fun(), remove:fun(destroy?:boolean), string:fun(value:string), size:fun(value:number), width:fun(value:number), height:fun(value:number), color:fun(value:string), font:fun(value:string), border:fun(size:number,color:string,style?:'outline'|'shadow'|'outline_fast'), align:fun(value:'left'|'center'|'right'), camera:fun(camera?:string), center:fun(axis?:'x'|'y'|'xy')}
---@alias PsychCamProxy PsychProxy & {setFilters:fun(filters?:string|RuntimeShader|(string|RuntimeShader)[]), clearFilters:fun()}
---@alias RuntimeShader {tag:string, name:string, float:fun(self,uniform:string,value:number), floats:fun(self,uniform:string,values:number[]), int:fun(self,uniform:string,value:integer), ints:fun(self,uniform:string,values:integer[]), bool:fun(self,uniform:string,value:boolean), bools:fun(self,uniform:string,values:boolean[]), texture:fun(self,uniform:string,imagePath:string), destroy:fun(self):boolean}

---@class PsychObject
---@field Sprite table API tạo/lấy sprite: new, animated, get
---@field Text table API tạo/lấy text: new, get
---@field Camera table Camera API: game, hud, other, follow, followPos, target, mouseX, mouseY
---@field Note table Note API: player, opponent, all, unspawn, note, tweenX, tweenY, tweenAngle, tweenAlpha, tweenDirection
---@field Tween table Tween API native: tween, fromTo, x, y, angle, alpha, zoom, color, cancel
---@field Timer table Timer API: start, cancel
---@field Sound table Sound API: play, music, pause, resume, stop
---@field Shader table Shader API: load, attach, detach, float, floats, int, ints, bool, bools, texture
---@field Haxe table Haxe API: run, eval
---@field RuntimeShader table RuntimeShader API: new, get
---@field Debug table Debug API (xem PsychObject.Debug)
---@field Ref fun(target:PsychProxy, field:string):HaxeRef Tạo Haxe reference
---@field object fun(path:string, children?:table):PsychProxy Tạo proxy object tùy ý
---@field class fun(className:string, children?:table):PsychProxy Tạo proxy class Haxe tĩnh
---@field group fun(groupName:string, index?:integer):PsychGroupProxy Tạo proxy group Note/Strum
---@field releaseInstance fun(instanceOrPath:PsychProxy|string):boolean Xoá instance Haxe (ClassName.new) khỏi game.variables
---@field shutdownDebug fun():boolean Đóng file log, tắt debug
---@field tick fun(elapsed:number) Cần gọi từ onUpdate để cập nhật Lua num tween
---@field clearCache fun():boolean Xoá cache (sprite, text, group, tween Lua) — GỌI TỪ onDestroy/onSongStart

---@type PsychObject
PsychObject = {}

--- CÁCH DÙNG CƠ BẢN:
-- 1. Thêm vào script bài hát (vd: mods/My-Mod/scripts/yourScript.lua):
--    dofile('mods/My-Mod/data/init.lua')
-- 2. Gọi PsychObject.tick(elapsed) trong hàm onUpdate(elapsed) để tween Lua hoạt động:
--    function onUpdate(elapsed) PsychObject.tick(elapsed) end
-- 3. Bật debug (tùy chọn): PsychObject.Debug.enable(true)
-- 4. Sử dụng các alias toàn cục: bf, dad, gf, game, camGame, camHUD, FlxG, Conductor, v.v.
-- 5. Tạo sprite/text: PsychObject.Sprite.new('tag', 'image.png', 100, 200) hoặc PsychObject.Text.new('tag', 'Hello', 0, 100, 100)
-- 6. Dọn cache khi đổi bài: function onDestroy() PsychObject.clearCache() end hoặc function onSongStart() PsychObject.clearCache() end

--- LƯU Ý VẬN HÀNH:
-- - PsychObject.tick() không tự chạy; cần gọi trong onUpdate(elapsed) cho Lua tween.
-- - Cache và instance tạo bằng ClassName.new() cần được dọn theo lifecycle của script.
-- - debugCaller() phụ thuộc call depth nên vị trí caller chỉ mang tính tham khảo.

local MODULE_DIR = 'mods/My-Mod/data/'

local MODULES = {
    '01_debug_core.lua',      -- hệ thống log/debug nội bộ (PsychObject = {} khởi tạo ở đây)
    '02_haxe_bridge.lua',     -- filter helpers, sơ đồ children, ReferenceResolver, PsychObject.Ref
    '03_shader_tween.lua',    -- RuntimeShader + bộ tween Lua thuần (PsychObject.tick)
    '04_proxy_core.lua',      -- lõi objectProxy (get/set/call/__index/__newindex)
    '05_class_proxy.lua',     -- classProxy + PsychObject.object/class/group
    '06_sprite_text.lua',     -- PsychObject.Sprite / PsychObject.Text
    '07_native_wrappers.lua', -- Camera/Note/Tween/Timer/Sound/Shader/Haxe wrappers
    '08_debug_api.lua',       -- bảng PsychObject.Debug (public) + shutdownDebug
    '09_aliases.lua',         -- bf/dad/gf/game/... + class proxies (FlxG, Conductor,...) + return
}

local result = nil
for _, fileName in ipairs(MODULES) do
    local fullPath = MODULE_DIR .. fileName
    local ok, ret = pcall(dofile, fullPath)
    if not ok then
        local msg = '[PsychObject] Lỗi khi load module "' .. fileName .. '": ' .. tostring(ret)
        if debugPrint then debugPrint(msg, 'FF5555') end
        print(msg)
        error(msg, 0)
    end
    result = ret -- module cuối (09_aliases.lua) return PsychObject
end
    addHaxeLibrary('Reflect')

return result
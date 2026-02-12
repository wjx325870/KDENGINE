-- =================================================
-- KD_ENGINE 纯命令行管理器（云端自动更新版）
-- 适用：AndroLua+ 工程 / GitHub Actions 编译
-- 云端已配置为：wjx325870/KDENGINE
-- =================================================

-- ---------- 1. 路径常量 ----------
BASE_PATH = "/storage/emulated/0/KD_ENGINE/"
LUA_PATH = BASE_PATH .. "Your module/"
FUNC_PATH = BASE_PATH .. "function/"
VERSION_FILE = BASE_PATH .. "version.txt"

-- ---------- 2. 云端配置（已改为你的GitHub）----------
GITHUB_USER = "wjx325870"
GITHUB_REPO = "KDENGINE"
VERSION_JSON_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/main/update/version.json"
MAIN_LUA_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/main/update/main.lua"

-- ---------- 3. 全局状态 ----------
current_path = BASE_PATH
lua_modules = {}
func_modules = {}
update_available = false
pending_version = nil
awaiting_update_response = false

-- ---------- 4. 初始化 ----------
function init()
    local dirs = {BASE_PATH, LUA_PATH, FUNC_PATH}
    for _, d in ipairs(dirs) do
        local f = File(d)
        if f and not f.exists() then f.mkdirs() end
    end
    local vf = File(VERSION_FILE)
    if not vf.exists() then
        local f = io.open(VERSION_FILE, "w")
        if f then f:write("0.0.0") f:close() end
    end
    scan_lua_modules()
    scan_func_modules()
end

function scan_lua_modules()
    lua_modules = {}
    local dir = File(LUA_PATH)
    if not dir or not dir.exists() or not dir.isDirectory() then return end
    local files = dir.listFiles()
    if files then
        for i = 0, files.length - 1 do
            local f = files[i]
            local name = f.getName()
            local path = f.getAbsolutePath()
            if name:match("%.lua$") then
                local modname = name:gsub("%.lua$", "")
                lua_modules[modname] = {type="file", path=path, enabled=false, paused=false, env=nil}
            elseif f.isDirectory() then
                local init = File(path, "init.lua")
                if init.exists() then
                    lua_modules[name] = {type="dir", path=init.getAbsolutePath(), dir_path=path, enabled=false, paused=false, env=nil}
                end
            end
        end
    end
end

function scan_func_modules()
    func_modules = {}
    local dir = File(FUNC_PATH)
    if not dir or not dir.exists() or not dir.isDirectory() then return end
    local files = dir.listFiles()
    if files then
        for i = 0, files.length - 1 do
            local f = files[i]
            local name = f.getName()
            func_modules[name] = {path = f.getAbsolutePath(), enabled = false}
        end
    end
end

-- ---------- 5. 路径解析 ----------
function resolve_path(path)
    if not path or path == "" then return current_path end
    if path:sub(1,1) == "/" then return path end
    local cur = current_path
    if cur:sub(-1) ~= "/" then cur = cur .. "/" end
    local parts = {}
    for p in (cur .. path):gmatch("[^/]+") do
        if p == ".." then table.remove(parts)
        elseif p ~= "." then table.insert(parts, p) end
    end
    return "/" .. table.concat(parts, "/")
end

-- ---------- 6. Lua 模块管理 ----------
function enable_lua_module(modname)
    local mod = lua_modules[modname]
    if not mod then return "[错误] 模块不存在：" .. modname end
    if mod.enabled then
        if mod.paused then mod.paused = false return "[恢复] 模块已恢复：" .. modname
        else return "[警告] 模块已启用：" .. modname end
    end
    local env = {_G = _G, print = print, io = io, table = table, string = string, math = math}
    setmetatable(env, {__index = _G})
    local chunk, err = loadfile(mod.path)
    if not chunk then return "[错误] 语法错误：" .. err end
    setfenv(chunk, env)
    local ok, res = pcall(chunk)
    if not ok then return "[错误] 执行错误：" .. tostring(res) end
    mod.env = env; mod.enabled = true; mod.paused = false
    for k, v in pairs(env) do
        if type(v) == "function" and k ~= "_G" then _G[k] = v end
    end
    return "[成功] 已启用模块：" .. modname
end

function pause_lua_module(modname)
    local mod = lua_modules[modname]
    if not mod then return "[错误] 模块不存在" end
    if not mod.enabled then return "[警告] 模块未启用" end
    if mod.paused then return "[警告] 模块已暂停" end
    mod.paused = true; return "[暂停] 模块已暂停：" .. modname
end

function disable_lua_module(modname)
    local mod = lua_modules[modname]
    if not mod then return "[错误] 模块不存在" end
    if not mod.enabled then return "[警告] 模块未启用" end
    for k, v in pairs(mod.env) do
        if type(v) == "function" and k ~= "_G" and _G[k] == v then _G[k] = nil end
    end
    mod.enabled = false; mod.paused = false; mod.env = nil
    return "[卸载] 模块已卸载：" .. modname
end

-- ---------- 7. 云端更新（核心）----------
function get_local_version()
    local f = io.open(VERSION_FILE, "r")
    if f then local v = f:read("*l"); f:close(); return v or "0.0.0" end
    return "0.0.0"
end

function set_local_version(ver)
    local f = io.open(VERSION_FILE, "w")
    if f then f:write(ver); f:close() end
end

function download_file(url, save_path)
    local cmd = 'curl -s -o "' .. save_path .. '" "' .. url .. '" 2>/dev/null'
    local res = os.execute(cmd)
    return res == 0
end

function check_update()
    local tmp_file = "/sdcard/version_check.json"
    if download_file(VERSION_JSON_URL, tmp_file) then
        local f = io.open(tmp_file, "r")
        if f then
            local json = f:read("*a"); f:close()
            os.remove(tmp_file)
            local cloud_ver = json:match('"version":%s*"([^"]+)"')
            if cloud_ver then
                return cloud_ver
            end
        end
    end
    return nil
end

function perform_update()
    add_output("[更新] 正在下载新版本...")
    local tmp_main = "/sdcard/main.lua.new"
    if download_file(MAIN_LUA_URL, tmp_main) then
        os.rename(LUA_PATH .. "main.lua", LUA_PATH .. "main.lua.bak")
        os.rename(tmp_main, LUA_PATH .. "main.lua")
        set_local_version(pending_version)
        add_output("[更新] 下载完成，请重启 KD_ENGINE 以应用新版本。")
        return true
    else
        add_output("[更新] 下载失败，请检查网络")
        return false
    end
end

-- ---------- 8. 命令处理 ----------
function cmd_update()
    add_output("[更新] 正在检查云端版本...")
    local cloud_ver = check_update()
    if not cloud_ver then
        add_output("[更新] 无法连接更新服务器")
        return
    end
    local local_ver = get_local_version()
    if cloud_ver == local_ver then
        add_output("[更新] 当前已是最新版本：" .. local_ver)
    else
        add_output("[更新] 发现新版本：本地 " .. local_ver .. " → 云端 " .. cloud_ver)
        io.write("是否立即更新？(Y/N): ")
        local ans = io.read()
        if ans and ans:upper() == "Y" then
            pending_version = cloud_ver
            perform_update()
        else
            add_output("[更新] 已取消，可随时输入 $/update 手动更新")
        end
    end
end

-- ---------- 9. 其他管理命令（文件操作、ZIP、路径等）----------
function cmd_go_to(args)
    if #args < 1 then return "[错误] 用法：$/go to <路径>" end
    local target = resolve_path(args[1])
    local f = File(target)
    if not f.exists() then return "[错误] 路径不存在：" .. target end
    if not f.isDirectory() then return "[错误] 目标不是文件夹" end
    current_path = target
    if current_path:sub(-1) ~= "/" then current_path = current_path .. "/" end
    return "[路径] 已切换到：" .. current_path
end

function cmd_pwd()
    return "[路径] 当前工作目录：" .. current_path
end

function cmd_list()
    local lines = {}
    lines[1] = "=== Your module 目录（Lua）==="
    for n, m in pairs(lua_modules) do
        local s = m.enabled and (m.paused and "暂停" or "已启用") or "未启用"
        lines[#lines+1] = string.format("  %-20s [%s] %s", n, s, m.type=="dir" and "(文件夹)" or "")
    end
    lines[#lines+1] = "=== function 目录（其他语言）==="
    for n, m in pairs(func_modules) do
        local s = m.enabled and "已启用" or "未启用"
        lines[#lines+1] = string.format("  %-20s [%s]", n, s)
    end
    return table.concat(lines, "\n")
end

-- 文件操作
function cmd_add_file(args)
    if #args < 2 then return "[错误] 用法：$/add file <文件名> [路径] <内容>" end
    local filename = args[2]
    local target_path = current_path
    local content_start = 3
    if #args >= 4 and (args[3]:find("/") or args[3] == "." or args[3] == "..") then
        target_path = resolve_path(args[3])
        content_start = 4
    end
    local fullpath = target_path:match(".*/") and target_path or target_path .. "/"
    fullpath = fullpath .. filename
    local content = table.concat(args, " ", content_start)
    local f = io.open(fullpath, "w")
    if not f then return "[错误] 无法创建文件" end
    f:write(content); f:close()
    if filename:match("%.lua$") and fullpath:find(LUA_PATH, 1, true) then scan_lua_modules() end
    return "[成功] 文件已创建：" .. fullpath
end

function cmd_add_dir(args)
    if #args < 2 then return "[错误] 用法：$/add dir <文件夹名> [路径]" end
    local dirname = args[2]
    local target_path = current_path
    if #args >= 3 then target_path = resolve_path(args[3]) end
    local fullpath = target_path:match(".*/") and target_path or target_path .. "/"
    fullpath = fullpath .. dirname
    local f = File(fullpath)
    if f.exists() then return "[错误] 文件夹已存在" end
    if f.mkdirs() then
        if fullpath:find(LUA_PATH,1,true) or fullpath:find(FUNC_PATH,1,true) then
            scan_lua_modules(); scan_func_modules()
        end
        return "[成功] 文件夹已创建：" .. fullpath
    else return "[错误] 创建失败" end
end

function cmd_remove_file(args)
    if #args < 2 then return "[错误] 用法：$/remove file <文件名> [路径]" end
    local filename = args[2]
    local target_path = current_path
    if #args >= 3 then target_path = resolve_path(args[3]) end
    local fullpath = target_path:match(".*/") and target_path or target_path .. "/"
    fullpath = fullpath .. filename
    local f = File(fullpath)
    if not f.exists() then return "[错误] 文件不存在" end
    if f.isDirectory() then return "[错误] 这是一个文件夹，请使用 remove dir" end
    if f.delete() then
        if filename:match("%.lua$") and fullpath:find(LUA_PATH,1,true) then
            local modname = filename:gsub("%.lua$","")
            lua_modules[modname] = nil
        end
        return "[成功] 文件已删除：" .. fullpath
    else return "[错误] 删除失败" end
end

function cmd_remove_dir(args)
    if #args < 2 then return "[错误] 用法：$/remove dir <文件夹名> [路径]" end
    local dirname = args[2]
    local target_path = current_path
    if #args >= 3 then target_path = resolve_path(args[3]) end
    local fullpath = target_path:match(".*/") and target_path or target_path .. "/"
    fullpath = fullpath .. dirname
    local f = File(fullpath)
    if not f.exists() then return "[错误] 文件夹不存在" end
    if not f.isDirectory() then return "[错误] 这是一个文件，请使用 remove file" end
    if f.delete() then
        if fullpath:find(LUA_PATH,1,true) then scan_lua_modules()
        elseif fullpath:find(FUNC_PATH,1,true) then scan_func_modules() end
        return "[成功] 文件夹已删除：" .. fullpath
    else return "[错误] 删除失败（文件夹可能不为空）" end
end

-- ZIP 操作
function cmd_zip_pack(src, dst)
    src = resolve_path(src); dst = resolve_path(dst)
    local src_f = File(src)
    if not src_f.exists() then return "[错误] 源路径不存在" end
    local zip_out = ZipOutputStream(FileOutputStream(File(dst)))
    local function add(f, base)
        local name = f.getAbsolutePath():sub(#base+2)
        if f.isDirectory() then
            zip_out.putNextEntry(ZipEntry(name.."/"))
            zip_out.closeEntry()
            local cs = f.listFiles()
            if cs then for i=0,cs.length-1 do add(cs[i], base) end end
        else
            zip_out.putNextEntry(ZipEntry(name))
            local fis = FileInputStream(f)
            local buf = ByteArray(1024)
            local len
            while true do len = fis.read(buf); if len<=0 then break end; zip_out.write(buf,0,len) end
            fis.close()
            zip_out.closeEntry()
        end
    end
    add(src_f, src_f.getParent())
    zip_out.close()
    return "[成功] 打包完成：" .. dst
end

function cmd_zip_unpack(zip, target)
    zip = resolve_path(zip); target = resolve_path(target)
    local zf = File(zip)
    if not zf.exists() then return "[错误] ZIP文件不存在" end
    local td = File(target)
    if not td.exists() then td.mkdirs() end
    local zis = ZipInputStream(FileInputStream(zf))
    local entry = zis.getNextEntry()
    while entry do
        local name = entry.getName()
        local out = File(td, name)
        if name:match("/$") then out.mkdirs()
        else
            out.getParentFile().mkdirs()
            local fos = FileOutputStream(out)
            local buf = ByteArray(1024)
            local len
            while true do len = zis.read(buf); if len<=0 then break end; fos.write(buf,0,len) end
            fos.close()
        end
        zis.closeEntry()
        entry = zis.getNextEntry()
    end
    zis.close()
    return "[成功] 解压完成：" .. target
end

-- ---------- 10. 命令分发器 ----------
function execute_command(line)
    line = line:gsub("^%s*(.-)%s*$", "%1")
    if line == "" then return end
    if line:sub(1,6) == "$/close" then
        local lua_code = line:sub(7):gsub("^%s*(.-)%s*$", "%1")
        if lua_code ~= "" then run_lua(lua_code) end
        return
    end
    if line:sub(1,2) == "$/" then
        local cmdline = line:sub(3):gsub("^%s*(.-)%s*$", "%1")
        local args = {}
        for w in cmdline:gmatch("%S+") do table.insert(args, w) end
        if #args == 0 then add_output("[错误] 空命令") return end
        local cmd = args[1]
        table.remove(args, 1)
        if cmd == "enable" then
            if #args >= 1 then
                if args[1] == "function" and #args >= 2 then
                    add_output("[成功] function模块已启用：" .. args[2])
                else add_output(enable_lua_module(args[1])) end
            else add_output("[错误] 用法：$/enable <模块名> 或 $/enable function <名>") end
        elseif cmd == "disable" then
            if #args >= 1 then
                if args[1] == "function" and #args >= 2 then add_output("[禁用] function模块已禁用：" .. args[2])
                else add_output(disable_lua_module(args[1])) end
            else add_output("[错误] 用法：$/disable <模块名>") end
        elseif cmd == "stop" then
            if #args >= 1 then add_output(pause_lua_module(args[1])) else add_output("[错误] 用法：$/stop <模块名>") end
        elseif cmd == "list" then add_output(cmd_list())
        elseif cmd == "update" then cmd_update()
        elseif cmd == "go" and args[1] == "to" then
            if #args >= 2 then add_output(cmd_go_to({args[2]})) else add_output("[错误] 用法：$/go to <路径>") end
        elseif cmd == "pwd" then add_output(cmd_pwd())
        elseif cmd == "add" then
            if #args >= 1 then
                if args[1] == "file" then add_output(cmd_add_file(args))
                elseif args[1] == "dir" then add_output(cmd_add_dir(args))
                else add_output("[错误] 未知 add 类型") end
            else add_output("[错误] 用法：$/add file/dir ...") end
        elseif cmd == "remove" then
            if #args >= 1 then
                if args[1] == "file" then add_output(cmd_remove_file(args))
                elseif args[1] == "dir" then add_output(cmd_remove_dir(args))
                else add_output("[错误] 未知 remove 类型") end
            else add_output("[错误] 用法：$/remove file/dir ...") end
        elseif cmd == "zip" then
            if #args >= 3 then
                if args[1] == "pack" then add_output(cmd_zip_pack(args[2], args[3]))
                elseif args[1] == "unpack" then add_output(cmd_zip_unpack(args[2], args[3]))
                else add_output("[错误] 未知 zip 操作") end
            else add_output("[错误] 用法：$/zip pack <源> <目标zip>  或 $/zip unpack <zip> <目标>") end
        elseif cmd == "help" then show_help()
        else add_output("[错误] 未知管理命令：" .. cmd) end
    else
        run_lua(line)
    end
end

function run_lua(code)
    local f, err = loadstring("return " .. code)
    if not f then f, err = loadstring(code) end
    if f then
        setfenv(f, _G)
        local ok, res = pcall(f)
        if ok then if res ~= nil then add_output(tostring(res)) end
        else add_output("[错误] " .. tostring(res)) end
    else add_output("[语法错误] " .. tostring(err)) end
end

function show_help()
    local h = [[
========== KD_ENGINE 命令帮助 ==========
【原生Lua】直接输入任何Lua 5.1代码执行

【管理命令】(必须以 $/ 开头)
  $/enable <模块名>           - 启用 Your module 中的Lua模块
  $/enable function <名>     - 启用 function 模块（仅标记）
  $/disable <模块名>         - 卸载Lua模块
  $/stop <模块名>            - 暂停已启用的Lua模块
  $/list                    - 列出所有模块状态
  $/update                  - 手动检查并更新

【文件操作】
  $/add file <文件名> [路径] <内容>   - 创建文件并写入内容
  $/add dir <文件夹名> [路径]        - 创建文件夹
  $/remove file <文件名> [路径]      - 删除文件
  $/remove dir <文件夹名> [路径]     - 删除空文件夹

【ZIP打包解压】
  $/zip pack <源路径> <目标zip>     - 打包文件夹为ZIP
  $/zip unpack <zip文件> <目标路径> - 解压ZIP

【路径切换】
  $/go to <路径>    - 切换当前工作路径
  $/pwd            - 显示当前工作路径

【其他】
  $/close <Lua代码> - 将本行剩余内容作为Lua执行
  $/help           - 显示本帮助
=========================================
]]
    add_output(h)
end

function add_output(text)
    activity.output.append("\n" .. text)
    activity.scroller.fullScroll(View.FOCUS_DOWN)
end

-- ---------- 11. UI 界面 ----------
function create_cli()
    activity.setTitle("KD_ENGINE")
    activity.setContentView(loadlayout {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#000000",
        { ScrollView, id = "scroller", layout_width = "fill", layout_height = "0dp", layout_weight = "1",
            { TextView, id = "output", text = "", textColor = "#00FF00", textSize = "14sp",
              typeface = Typeface.MONOSPACE, lineSpacingExtra = "2dp" } },
        { EditText, id = "input", layout_width = "fill", layout_height = "wrap_content",
          backgroundColor = "#000000", textColor = "#00FF00", hint = "> 输入代码 或 $/命令",
          hintTextColor = "#006600", textSize = "14sp", typeface = Typeface.MONOSPACE,
          singleLine = false, maxLines = 3, gravity = "top", padding = "10dp" }
    })
    activity.output.append(">>> KD_ENGINE 命令行已启动")
    activity.output.append(">>> 根目录: " .. BASE_PATH)
    activity.output.append(">>> 当前路径: " .. current_path)
    activity.output.append(">>> 输入 $/help 查看管理命令")
    activity.output.append(">>> 直接输入 Lua 代码立即执行\n")
    scan_lua_modules()
    scan_func_modules()
    activity.output.append("[系统] Your module: " .. #lua_modules .. " 个模块")
    activity.output.append("[系统] function: " .. #func_modules .. " 个文件\n")
    
    -- 自动检查更新
    activity.output.append("[系统] 正在检查更新...")
    local cv = check_update()
    if cv then
        local lv = get_local_version()
        if cv ~= lv then
            activity.output.append("[更新] 发现新版本 " .. cv .. "，是否更新？(Y/N)")
            awaiting_update_response = true
            pending_version = cv
        else
            activity.output.append("[系统] 当前已是最新版本")
        end
    end
    
    activity.input.requestFocus()
    activity.input.setOnKeyListener(function(view, keyCode, event)
        if event.getAction() == KeyEvent.ACTION_DOWN and keyCode == KeyEvent.KEYCODE_ENTER then
            local code = view.getText().toString()
            if code and code ~= "" then
                activity.output.append("\n> " .. code)
                if awaiting_update_response and code:upper() == "Y" then
                    perform_update()
                    awaiting_update_response = false
                elseif awaiting_update_response and code:upper() == "N" then
                    activity.output.append("[更新] 已取消，可随时输入 $/update")
                    awaiting_update_response = false
                else
                    execute_command(code)
                end
                view.setText("")
            end
            return true
        end
        return false
    end)
end

-- 入口
check_permission = function()
    if ContextCompat.checkSelfPermission(activity, Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED then
        init()
        create_cli()
    else
        ActivityCompat.requestPermissions(activity, {Manifest.permission.WRITE_EXTERNAL_STORAGE}, 100)
    end
end
function onRequestPermissionsResult(_, _, grantResults)
    if grantResults and #grantResults > 0 and grantResults[0] == PackageManager.PERMISSION_GRANTED then
        init()
        create_cli()
    else
        toast("[错误] 需要存储权限")
        activity.finish()
    end
end

check_permission()
-- ========== 结束 ==========

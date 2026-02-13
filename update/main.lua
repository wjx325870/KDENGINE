-- =================================================
-- KD ENGINE 纯净中文稳定版
-- 修复：print 输出到命令行 · 错误信息不弹窗 · 完整 Lua 5.1 支持
-- 作者：wjx325870
-- 最后更新：2026-02-13
-- =================================================

require "import"

-- ---------- 强制横屏 ----------
import "android.content.pm.ActivityInfo"
activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE

-- ---------- 导入必要类 ----------
import "android.Manifest"
import "android.content.pm.PackageManager"
import "android.view.KeyEvent"
import "android.graphics.Typeface"
import "android.view.View"
import "android.widget.*"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.util.zip.ZipEntry"
import "java.util.zip.ZipInputStream"
import "java.util.zip.ZipOutputStream"
import "java.lang.reflect.Array"

-- ---------- 路径常量 ----------
BASE_PATH = "/storage/emulated/0/KD_ENGINE/"
LUA_PATH = BASE_PATH .. "Your module/"
FUNC_PATH = BASE_PATH .. "function/"
VERSION_FILE = BASE_PATH .. "version.txt"

-- ---------- 云端配置（改成你自己的 GitHub）----------
GITHUB_USER = "wjx325870"
GITHUB_REPO = "KDENGINE"
VERSION_JSON_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/main/update/version.json"
MAIN_LUA_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/main/update/main.lua"

-- ---------- 全局状态 ----------
current_path = BASE_PATH
lua_modules = {}
func_modules = {}
update_available = false
pending_version = nil
awaiting_update_response = false
has_permission = false

-- ---------- 权限请求 ----------
function check_permission()
    if activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED then
        has_permission = true
        init()
        create_cli()
    else
        activity.requestPermissions({Manifest.permission.WRITE_EXTERNAL_STORAGE}, 100)
    end
end

function onRequestPermissionsResult(requestCode, permissions, grantResults)
    if requestCode == 100 then
        if grantResults and #grantResults > 0 and grantResults[0] == PackageManager.PERMISSION_GRANTED then
            has_permission = true
            init()
            create_cli()
        else
            print("❌ 需要存储权限")
            activity.finish()
        end
    end
end

-- ---------- 初始化目录 ----------
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

-- ---------- 扫描 Lua 模块（文件/文件夹）----------
function scan_lua_modules()
    lua_modules = {}
    local dir = File(LUA_PATH)
    if not dir or not dir.exists() or not dir.isDirectory() then return end
    local files = dir.listFiles()
    if files then
        local len = Array.getLength(files)
        for i = 0, len - 1 do
            local f = files[i]
            local name = f.getName()
            local path = f.getAbsolutePath()
            if name:match("%.lua$") then
                local modname = name:gsub("%.lua$", "")
                lua_modules[modname] = {
                    type = "file",
                    path = path,
                    enabled = false,
                    paused = false,
                    env = nil
                }
            elseif f.isDirectory() then
                local init_file = File(path, "init.lua")
                if init_file.exists() then
                    lua_modules[name] = {
                        type = "dir",
                        path = init_file.getAbsolutePath(),
                        dir_path = path,
                        enabled = false,
                        paused = false,
                        env = nil
                    }
                end
            end
        end
    end
end

-- ---------- 扫描 function 目录 ----------
function scan_func_modules()
    func_modules = {}
    local dir = File(FUNC_PATH)
    if not dir or not dir.exists() or not dir.isDirectory() then return end
    local files = dir.listFiles()
    if files then
        local len = Array.getLength(files)
        for i = 0, len - 1 do
            local f = files[i]
            local name = f.getName()
            func_modules[name] = {
                path = f.getAbsolutePath(),
                enabled = false
            }
        end
    end
end

-- ---------- 路径解析 ----------
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

-- ---------- Lua 模块管理 ----------
function enable_lua_module(modname)
    local mod = lua_modules[modname]
    if not mod then return "[错误] 模块不存在：" .. modname end
    if mod.enabled then
        if mod.paused then
            mod.paused = false
            return "[恢复] 模块已恢复：" .. modname
        else
            return "[警告] 模块已启用：" .. modname
        end
    end
    local env = {_G = _G, print = print, io = io, table = table, string = string, math = math}
    setmetatable(env, {__index = _G})
    local chunk, err = loadfile(mod.path)
    if not chunk then return "[错误] 语法错误：" .. err end
    setfenv(chunk, env)
    local ok, res = pcall(chunk)
    if not ok then return "[错误] 执行错误：" .. tostring(res) end
    mod.env = env
    mod.enabled = true
    mod.paused = false
    for k, v in pairs(env) do
        if type(v) == "function" and k ~= "_G" then
            _G[k] = v
        end
    end
    return "[成功] 已启用模块：" .. modname
end

function pause_lua_module(modname)
    local mod = lua_modules[modname]
    if not mod then return "[错误] 模块不存在" end
    if not mod.enabled then return "[警告] 模块未启用" end
    if mod.paused then return "[警告] 模块已暂停" end
    mod.paused = true
    return "[暂停] 模块已暂停：" .. modname
end

function disable_lua_module(modname)
    local mod = lua_modules[modname]
    if not mod then return "[错误] 模块不存在" end
    if not mod.enabled then return "[警告] 模块未启用" end
    for k, v in pairs(mod.env) do
        if type(v) == "function" and k ~= "_G" and _G[k] == v then
            _G[k] = nil
        end
    end
    mod.enabled = false
    mod.paused = false
    mod.env = nil
    return "[卸载] 模块已卸载：" .. modname
end

-- ---------- Function 模块管理（仅状态）----------
function enable_func_module(modname)
    local mod = func_modules[modname]
    if not mod then return "[错误] function模块不存在：" .. modname end
    if mod.enabled then return "[警告] 模块已启用：" .. modname end
    mod.enabled = true
    return "[成功] function模块已启用：" .. modname
end

function disable_func_module(modname)
    local mod = func_modules[modname]
    if not mod then return "[错误] function模块不存在：" .. modname end
    if not mod.enabled then return "[警告] 模块未启用：" .. modname end
    mod.enabled = false
    return "[禁用] function模块已禁用：" .. modname
end

-- ---------- 列出所有模块 ----------
function cmd_list()
    local lines = {}
    lines[#lines+1] = "=== Your module 目录（Lua）==="
    for name, mod in pairs(lua_modules) do
        local status = "未启用"
        if mod.enabled and not mod.paused then status = "已启用"
        elseif mod.enabled and mod.paused then status = "暂停" end
        lines[#lines+1] = string.format("  %-20s [%s] %s", name, status, mod.type=="dir" and "(文件夹)" or "")
    end
    lines[#lines+1] = "=== function 目录（其他语言）==="
    for name, mod in pairs(func_modules) do
        local status = mod.enabled and "已启用" or "未启用"
        lines[#lines+1] = string.format("  %-20s [%s]", name, status)
    end
    return table.concat(lines, "\n")
end

-- ---------- 云端更新核心 ----------
function get_local_version()
    local f = io.open(VERSION_FILE, "r")
    if f then
        local v = f:read("*l")
        f:close()
        return v or "0.0.0"
    end
    return "0.0.0"
end

function set_local_version(ver)
    local f = io.open(VERSION_FILE, "w")
    if f then
        f:write(ver)
        f:close()
    end
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
            local json = f:read("*a")
            f:close()
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
        add_output("[更新] 下载完成，请重启 KD_ENGINE")
        return true
    else
        add_output("[更新] 下载失败，请检查网络")
        return false
    end
end

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
            add_output("[更新] 已取消，可随时输入 $/update")
        end
    end
end

-- ---------- 路径切换 ----------
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

-- ---------- 文件操作 ----------
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
    f:write(content)
    f:close()
    if filename:match("%.lua$") and fullpath:find(LUA_PATH, 1, true) then
        scan_lua_modules()
    end
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
            scan_lua_modules()
            scan_func_modules()
        end
        return "[成功] 文件夹已创建：" .. fullpath
    else
        return "[错误] 创建失败"
    end
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
    else
        return "[错误] 删除失败"
    end
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
        if fullpath:find(LUA_PATH,1,true) then
            scan_lua_modules()
        elseif fullpath:find(FUNC_PATH,1,true) then
            scan_func_modules()
        end
        return "[成功] 文件夹已删除：" .. fullpath
    else
        return "[错误] 删除失败（文件夹可能不为空）"
    end
end

-- ---------- ZIP 操作 ----------
function cmd_zip_pack(src, dst)
    src = resolve_path(src)
    dst = resolve_path(dst)
    local src_file = File(src)
    if not src_file.exists() then return "[错误] 源路径不存在" end

    local zip_file = File(dst)
    local zip_out = ZipOutputStream(FileOutputStream(zip_file))

    local function add_to_zip(file, base)
        local name = file.getAbsolutePath():sub(#base + 2)
        if file.isDirectory() then
            zip_out.putNextEntry(ZipEntry(name .. "/"))
            zip_out.closeEntry()
            local children = file.listFiles()
            if children then
                local child_len = Array.getLength(children)
                for i = 0, child_len - 1 do
                    add_to_zip(children[i], base)
                end
            end
        else
            zip_out.putNextEntry(ZipEntry(name))
            local fis = FileInputStream(file)
            local buffer = ByteArray(1024)
            local len
            while true do
                len = fis.read(buffer)
                if len <= 0 then break end
                zip_out.write(buffer, 0, len)
            end
            fis.close()
            zip_out.closeEntry()
        end
    end

    add_to_zip(src_file, src_file.getParent())
    zip_out.close()
    return "[成功] ZIP包已创建：" .. dst
end

function cmd_zip_unpack(zip, target)
    zip = resolve_path(zip)
    target = resolve_path(target)
    local zip_file = File(zip)
    if not zip_file.exists() then return "[错误] ZIP文件不存在" end

    local target_dir = File(target)
    if not target_dir.exists() then target_dir.mkdirs() end

    local zis = ZipInputStream(FileInputStream(zip_file))
    local entry = zis.getNextEntry()
    while entry do
        local name = entry.getName()
        local out_file = File(target_dir, name)
        if name:match("/$") then
            out_file.mkdirs()
        else
            out_file.getParentFile().mkdirs()
            local fos = FileOutputStream(out_file)
            local buffer = ByteArray(1024)
            local len
            while true do
                len = zis.read(buffer)
                if len <= 0 then break end
                fos.write(buffer, 0, len)
            end
            fos.close()
        end
        zis.closeEntry()
        entry = zis.getNextEntry()
    end
    zis.close()
    return "[成功] ZIP包已解压到：" .. target
end

-- ---------- 🔥 核心修复：Lua 代码执行（无弹窗 + print 重定向）----------

-- 保存原始 print
local original_print = print

-- 自定义 print：将输出追加到命令行
print = function(...)
    local args = {...}
    local parts = {}
    for i, v in ipairs(args) do
        parts[i] = tostring(v)
    end
    add_output(table.concat(parts, "\t"))
end

-- 执行 Lua 代码，捕获所有错误并显示在输出中（绝不弹窗）
function run_lua(code)
    -- 尝试作为表达式执行（带 return）
    local func, err = loadstring("return " .. code)
    if not func then
        func, err = loadstring(code)
    end
    if func then
        setfenv(func, _G)
        local ok, result = pcall(func)
        if ok then
            if result ~= nil then
                add_output(tostring(result))
            end
        else
            -- 运行时错误：显示在命令行，无弹窗
            add_output("[错误] " .. tostring(result))
        end
    else
        -- 语法错误：显示在命令行，无弹窗
        add_output("[语法错误] " .. tostring(err))
    end
end

-- ---------- 命令解析与执行 ----------
function execute_command(line)
    line = line:gsub("^%s*(.-)%s*$", "%1")
    if line == "" then return end

    -- 处理 $/close：之后全部作为 Lua 代码执行
    if line:sub(1,6) == "$/close" then
        local lua_code = line:sub(7):gsub("^%s*(.-)%s*$", "%1")
        if lua_code ~= "" then
            run_lua(lua_code)
        end
        return
    end

    -- 管理命令
    if line:sub(1,2) == "$/" then
        local cmdline = line:sub(3):gsub("^%s*(.-)%s*$", "%1")
        local args = {}
        for w in cmdline:gmatch("%S+") do
            table.insert(args, w)
        end
        if #args == 0 then
            add_output("[错误] 空命令")
            return
        end
        local cmd = args[1]
        table.remove(args, 1)

        if cmd == "enable" then
            if #args >= 1 then
                if args[1] == "function" and #args >= 2 then
                    add_output(enable_func_module(args[2]))
                else
                    add_output(enable_lua_module(args[1]))
                end
            else
                add_output("[错误] 用法：$/enable <模块名> 或 $/enable function <名>")
            end
        elseif cmd == "disable" then
            if #args >= 1 then
                if args[1] == "function" and #args >= 2 then
                    add_output(disable_func_module(args[2]))
                else
                    add_output(disable_lua_module(args[1]))
                end
            else
                add_output("[错误] 用法：$/disable <模块名>")
            end
        elseif cmd == "stop" then
            if #args >= 1 then
                add_output(pause_lua_module(args[1]))
            else
                add_output("[错误] 用法：$/stop <模块名>")
            end
        elseif cmd == "list" then
            add_output(cmd_list())
        elseif cmd == "update" then
            cmd_update()
        elseif cmd == "go" and args[1] == "to" then
            if #args >= 2 then
                add_output(cmd_go_to({args[2]}))
            else
                add_output("[错误] 用法：$/go to <路径>")
            end
        elseif cmd == "pwd" then
            add_output(cmd_pwd())
        elseif cmd == "add" then
            if #args >= 1 then
                if args[1] == "file" then
                    add_output(cmd_add_file(args))
                elseif args[1] == "dir" then
                    add_output(cmd_add_dir(args))
                else
                    add_output("[错误] 未知 add 类型")
                end
            else
                add_output("[错误] 用法：$/add file/dir ...")
            end
        elseif cmd == "remove" then
            if #args >= 1 then
                if args[1] == "file" then
                    add_output(cmd_remove_file(args))
                elseif args[1] == "dir" then
                    add_output(cmd_remove_dir(args))
                else
                    add_output("[错误] 未知 remove 类型")
                end
            else
                add_output("[错误] 用法：$/remove file/dir ...")
            end
        elseif cmd == "zip" then
            if #args >= 3 then
                if args[1] == "pack" then
                    add_output(cmd_zip_pack(args[2], args[3]))
                elseif args[1] == "unpack" then
                    add_output(cmd_zip_unpack(args[2], args[3]))
                else
                    add_output("[错误] 未知 zip 操作")
                end
            else
                add_output("[错误] 用法：$/zip pack <源> <目标zip>  或 $/zip unpack <zip> <目标>")
            end
        elseif cmd == "help" then
            show_help()
        else
            add_output("[错误] 未知管理命令：" .. cmd)
        end
    else
        -- 原生 Lua 代码执行
        run_lua(line)
    end
end

-- ---------- 帮助信息 ----------
function show_help()
    local help = [[
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
    add_output(help)
end

-- ---------- 输出函数（将文字追加到命令行）----------
function add_output(text)
    if output_view then
        output_view.append("\n" .. text)
        if scroller_view then
            scroller_view.fullScroll(View.FOCUS_DOWN)
        end
    else
        -- 极罕见的降级方案（发生在界面未完全初始化时）
        original_print(text)
    end
end

-- ---------- 创建命令行界面（控件绑定）----------
function create_cli()
    -- 重新导入布局类（确保可用）
    import "android.widget.LinearLayout"
    import "android.widget.ScrollView"
    import "android.widget.TextView"
    import "android.widget.EditText"

    local layout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        backgroundColor = "#000000",
        {
            ScrollView,
            id = "scroller",
            layout_width = "fill",
            layout_height = "0dp",
            layout_weight = "1",
            {
                TextView,
                id = "output",
                text = "",
                textColor = "#00FF00",
                textSize = "14sp",
                typeface = Typeface.MONOSPACE
            }
        },
        {
            EditText,
            id = "input",
            layout_width = "fill",
            layout_height = "wrap_content",
            backgroundColor = "#000000",
            textColor = "#00FF00",
            hint = "> 输入代码 或 $/命令",
            hintTextColor = "#006600",
            textSize = "14sp",
            typeface = Typeface.MONOSPACE,
            singleLine = false,
            maxLines = 3,
            gravity = "top",
            padding = "10dp"
        }
    }

    local vars = {}
    activity.setTitle("KD_ENGINE")
    activity.setContentView(loadlayout(layout, vars))

    output_view = vars.output
    scroller_view = vars.scroller
    input_view = vars.input

    -- 初始化输出
    add_output(">>> KD_ENGINE 命令行已启动")
    add_output(">>> 根目录: " .. BASE_PATH)
    add_output(">>> 当前路径: " .. current_path)
    add_output(">>> 输入 $/help 查看管理命令")
    add_output(">>> 直接输入 Lua 代码立即执行\n")

    scan_lua_modules()
    scan_func_modules()

    local lua_count = 0
    for _ in pairs(lua_modules) do lua_count = lua_count + 1 end
    local func_count = 0
    for _ in pairs(func_modules) do func_count = func_count + 1 end
    add_output("[系统] Your module: " .. lua_count .. " 个模块")
    add_output("[系统] function: " .. func_count .. " 个文件\n")

    -- 自动检查更新
    add_output("[系统] 正在检查更新...")
    local cv = check_update()
    if cv then
        local lv = get_local_version()
        if cv ~= lv then
            add_output("[更新] 发现新版本 " .. cv .. "，是否更新？(Y/N)")
            awaiting_update_response = true
            pending_version = cv
        else
            add_output("[系统] 当前已是最新版本")
        end
    end

    input_view.requestFocus()
    input_view.setOnKeyListener(function(view, keyCode, event)
        if event.getAction() == KeyEvent.ACTION_DOWN and keyCode == KeyEvent.KEYCODE_ENTER then
            local code = view.getText().toString()
            if code and code ~= "" then
                add_output("> " .. code)
                if awaiting_update_response and code:upper() == "Y" then
                    perform_update()
                    awaiting_update_response = false
                elseif awaiting_update_response and code:upper() == "N" then
                    add_output("[更新] 已取消，可随时输入 $/update")
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

-- ---------- 启动 ----------
check_permission()
-- =============================================

-- =================================================
-- KD ENGINE 完整源码 (智能镜像切换版)
-- 版本：5.4.0
-- 功能：自动识别国内外网络，智能选择下载源
-- 作者：wjx325870
-- =================================================

require "import"
import "android.app.*"
import "android.os.*"
import "android.widget.*"
import "android.view.*"
import "android.graphics.*"
import "android.content.pm.PackageManager"
import "android.Manifest"
import "java.io.File"
import "java.io.FileInputStream"
import "java.io.FileOutputStream"
import "java.io.BufferedReader"
import "java.io.InputStreamReader"
import "java.net.URL"
import "java.net.HttpURLConnection"
import "org.json.JSONArray"
import "org.json.JSONObject"
import "java.lang.reflect.Array"
import "java.util.Random"

-- ========== setfenv 兼容层（用于 Lua 5.2/5.3）==========
if not setfenv then
  local function find_env(func, name)
    local i = 1
    while true do
      local n, v = debug.getupvalue(func, i)
      if not n then return nil end
      if n == name then return i, v end
      i = i + 1
    end
  end
  function setfenv(func, env)
    local i = find_env(func, "_ENV")
    if i then
      debug.upvaluejoin(func, i, function() return env end, 1)
    end
    return func
  end
  function getfenv(func)
    local i, env = find_env(func, "_ENV")
    return env or _G
  end
end
-- =======================================================

-- ========== 路径常量 ==========
BASE_PATH = "/storage/emulated/0/KD_ENGINE/"
LUA_PATH = BASE_PATH .. "Your module/"
FUNC_PATH = BASE_PATH .. "function/"
CODE_PATH = BASE_PATH .. "code/"
VERSION_FILE = BASE_PATH .. "version.txt"

-- 系统错误日志
SYS_ERROR_LOG = CODE_PATH .. "error.log"
SYS_ERROR_COUNT = CODE_PATH .. "error_count.txt"
SYS_ERROR_HISTORY = CODE_PATH .. "error_history.txt"

-- 新版本测试错误日志
TEST_ERROR_LOG = CODE_PATH .. "test_error.log"
TEST_ERROR_COUNT = CODE_PATH .. "test_count.txt"
TEST_RESULT_FILE = CODE_PATH .. "test_result.txt"

-- ========== 云端更新配置（多镜像）=========
GITHUB_USER = "wjx325870"
GITHUB_REPO = "KDENGINE"

-- 国内镜像列表
CHINA_MIRRORS = {
    gitee = "https://gitee.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/raw/main/update/",
    ghproxy = "https://ghproxy.com/https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/main/update/",
    jsdelivr = "https://cdn.jsdelivr.net/gh/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "@main/update/"
}

-- 国际直连
INTERNATIONAL_URL = "https://raw.githubusercontent.com/" .. GITHUB_USER .. "/" .. GITHUB_REPO .. "/main/update/"

-- ========== 全局变量 ==========
current_path = BASE_PATH
lua_modules = {}
func_modules = {}
has_permission = false
test_mode = false
current_version = "0.0.0"
kd_cli_output = nil
kd_cli_input = nil
kd_cli_scroller = nil
is_china = nil

local original_print = print

-- ========== 错误统计函数 ==========
function write_sys_log(msg)
    local f = io.open(SYS_ERROR_LOG, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. msg .. "\n")
        f:close()
    end
end

function write_test_log(msg)
    local f = io.open(TEST_ERROR_LOG, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. msg .. "\n")
        f:close()
    end
end

function update_sys_error_count(delta)
    local f = io.open(SYS_ERROR_COUNT, "r")
    local count = 0
    if f then
        count = tonumber(f:read("*a")) or 0
        f:close()
    end
    count = count + delta
    f = io.open(SYS_ERROR_COUNT, "w")
    if f then
        f:write(count)
        f:close()
    end
end

function update_test_error_count(delta)
    local f = io.open(TEST_ERROR_COUNT, "r")
    local count = 0
    if f then
        count = tonumber(f:read("*a")) or 0
        f:close()
    end
    count = count + delta
    f = io.open(TEST_ERROR_COUNT, "w")
    if f then
        f:write(count)
        f:close()
    end
end

function get_sys_error_count()
    local f = io.open(SYS_ERROR_COUNT, "r")
    if f then
        local count = tonumber(f:read("*a")) or 0
        f:close()
        return count
    end
    return 0
end

function get_test_error_count()
    local f = io.open(TEST_ERROR_COUNT, "r")
    if f then
        local count = tonumber(f:read("*a")) or 0
        f:close()
        return count
    end
    return 0
end

function record_native_error_history(count)
    local f = io.open(SYS_ERROR_HISTORY, "a")
    if f then
        local date = os.date("[%Y %m %d]")
        f:write(date .. " Native version error point " .. count .. "\n")
        f:close()
    end
end

function record_new_version_error(version, count)
    local f = io.open(TEST_RESULT_FILE, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. "version " .. version .. " error point " .. count .. "\n")
        f:close()
    end
end

function clear_test_data()
    local f = io.open(TEST_ERROR_COUNT, "w")
    if f then
        f:write("0")
        f:close()
    end
    f = io.open(TEST_ERROR_LOG, "w")
    if f then
        f:close()
    end
end

function detect_network_location()
    local tmp_file = BASE_PATH .. "ipinfo.tmp"
    local api_list = {
        {url = "https://ipapi.co/json/", country_field = "country_code"},
        {url = "https://api.ip.sb/geoip", country_field = "country_code"},
        {url = "https://ipinfo.io/json", country_field = "country"},
        {url = "http://ip-api.com/json", country_field = "countryCode"}
    }
    
    for _, api in ipairs(api_list) do
        local cmd = 'curl -s -L --connect-timeout 3 -o "' .. tmp_file .. '" "' .. api.url .. '" 2>/dev/null'
        local res = os.execute(cmd)
        
        if res == 0 then
            local f = io.open(tmp_file, "r")
            if f then
                local json = f:read("*a")
                f:close()
                os.remove(tmp_file)
                
                local ok, data = pcall(JSONObject, json)
                if ok then
                    local country = data.optString(api.country_field, "")
                    country = country:upper()
                    
                    if country == "CN" or country == "CHN" or country == "156" or country == "中国" then
                        return true
                    else
                        return false
                    end
                end
            end
        end
    end
    return false
end

function check_update_with_mirror()
    local tmp_version = BASE_PATH .. "version.tmp"
    local urls = {}
    
    if is_china == nil then
        is_china = detect_network_location()
    end
    
    if is_china then
        table.insert(urls, CHINA_MIRRORS.gitee .. "version.json")
        table.insert(urls, CHINA_MIRRORS.ghproxy .. "version.json")
        table.insert(urls, CHINA_MIRRORS.jsdelivr .. "version.json")
        table.insert(urls, INTERNATIONAL_URL .. "version.json")
    else
        table.insert(urls, INTERNATIONAL_URL .. "version.json")
        table.insert(urls, CHINA_MIRRORS.jsdelivr .. "version.json")
    end
    
    for _, url in ipairs(urls) do
        local cmd = 'curl -s -L --connect-timeout 8 -o "' .. tmp_version .. '" "' .. url .. '" 2>/dev/null'
        local res = os.execute(cmd)
        
        if res == 0 then
            local f = io.open(tmp_version, "r")
            if f then
                local json = f:read("*a")
                f:close()
                os.remove(tmp_version)
                
                local ok, data = pcall(JSONObject, json)
                if ok then
                    local cloud_version = data.optString("version", "0.0.0")
                    return cloud_version, nil
                end
            end
        end
    end
    
    return nil, "无法连接任何更新服务器"
end

function download_with_mirror(save_path)
    local urls = {}
    
    if is_china then
        table.insert(urls, CHINA_MIRRORS.gitee .. "main.lua")
        table.insert(urls, CHINA_MIRRORS.ghproxy .. "main.lua")
        table.insert(urls, CHINA_MIRRORS.jsdelivr .. "main.lua")
        table.insert(urls, INTERNATIONAL_URL .. "main.lua")
    else
        table.insert(urls, INTERNATIONAL_URL .. "main.lua")
        table.insert(urls, CHINA_MIRRORS.jsdelivr .. "main.lua")
    end
    
    for _, url in ipairs(urls) do
        local cmd = 'curl -s -L --connect-timeout 15 -o "' .. save_path .. '" "' .. url .. '" 2>/dev/null'
        local res = os.execute(cmd)
        if res == 0 then
            return true
        end
    end
    return false
end

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
    current_version = ver
end

function run_stress_test()
    test_mode = true
    local test_commands = {
        "$/list",
        "$/pwd",
        "$/ls",
        "$/ls ~",
        "$/ls ..",
        "print('test')",
        "math.random()",
        "os.date()",
        "string.upper('hello')",
        "table.concat({1,2,3}, ',')"
    }
    
    local lua_snippets = {
        "local x = 10 return x",
        "function test() return 42 end return test()",
        "for i=1,5 do print(i) end",
        "local t = {a=1,b=2} return t.a",
        "math.sqrt(16)",
        "string.reverse('abc')",
        "table.sort({3,1,2})",
        "os.time()",
        "tonumber('123')",
        "type(42)"
    }
    
    local random = Random()
    local total_tests = 50
    
    for i = 1, total_tests do
        local choice = random.nextInt(3)
        
        if choice == 0 then
            local cmd = test_commands[random.nextInt(#test_commands) + 1]
            execute_command(cmd)
        elseif choice == 1 then
            local cmd = lua_snippets[random.nextInt(#lua_snippets) + 1]
            run_lua(cmd)
        else
            if random.nextInt(2) == 0 then
                cmd = "$/ls " .. (random.nextInt(2) == 0 and "~" or "..")
            else
                cmd = "print('stress test " .. i .. "')"
            end
            execute_command(cmd)
        end
        os.execute("sleep 0.1")
    end
    
    test_mode = false
    return get_test_error_count()
end

function silent_update()
    add_output("[系统] 正在检测网络位置...")
    is_china = detect_network_location()
    
    if is_china then
        add_output("[系统] 检测到国内网络，将使用国内镜像")
    else
        add_output("[系统] 检测到海外网络，将使用国际直连")
    end
    
    add_output("[系统] 检查更新...")
    local cloud_ver, err = check_update_with_mirror()
    if not cloud_ver then
        add_output("[系统] " .. (err or "更新失败"))
        return
    end
    
    local local_ver = get_local_version()
    if cloud_ver == local_ver then
        add_output("[系统] 当前已是最新版本")
        return
    end
    
    local current_errors = get_sys_error_count()
    record_native_error_history(current_errors)
    
    add_output("[系统] 发现新版本 " .. cloud_ver .. "，正在下载...")
    local tmp_file = BASE_PATH .. "main.tmp"
    
    local success = download_with_mirror(tmp_file)
    if not success then
        add_output("[系统] 下载失败")
        return
    end
    
    local current_file = activity.getLuaDir() .. "/main.lua"
    if File(current_file).exists() then
        os.rename(current_file, current_file .. ".bak")
    end
    
    local rename_success = os.rename(tmp_file, current_file)
    if not rename_success then
        add_output("[系统] 文件替换失败")
        return
    end
    
    clear_test_data()
    
    add_output("[系统] 新版本已下载，开始压力测试...")
    local test_errors = run_stress_test()
    
    record_new_version_error(cloud_ver, test_errors)
    clear_test_data()
    
    set_local_version(cloud_ver)
    add_output("[系统] 更新完成，版本号: " .. cloud_ver)
    add_output("[系统] 新版本测试错误数: " .. test_errors)
end

function resolve_path(path)
    if not path or path == "" then return current_path end
    if path:sub(1,1) == "~" then
        path = BASE_PATH .. path:sub(2)
    end
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

function scan_lua_modules()
    if not Array then import "java.lang.reflect.Array" end
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
                    injected = {}
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
                        injected = {}
                    }
                end
            end
        end
    end
end

function scan_func_modules()
    if not Array then import "java.lang.reflect.Array" end
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

function enable_lua_module(modname)
    local mod = lua_modules[modname]
    if not mod then
        local err = "[错误] 模块不存在：" .. modname
        add_output(err)
        if test_mode then
            write_test_log(err)
            update_test_error_count(1)
        else
            write_sys_log(err)
            update_sys_error_count(1)
        end
        return err
    end
    if mod.enabled then
        if mod.paused then
            mod.paused = false
            return "[恢复] 模块已恢复：" .. modname
        else
            return "[警告] 模块已启用：" .. modname
        end
    end
    local before = {}
    for k, v in pairs(_G) do
        if type(v) == "function" then before[k] = v end
    end
    local chunk, err = loadfile(mod.path)
    if not chunk then
        local msg = "[错误] 语法错误：" .. err
        add_output(msg)
        if test_mode then
            write_test_log(msg)
            update_test_error_count(1)
        else
            write_sys_log(msg)
            update_sys_error_count(1)
        end
        return msg
    end
    local ok, res = pcall(chunk)
    if not ok then
        local msg = "[错误] 执行错误：" .. tostring(res)
        add_output(msg)
        if test_mode then
            write_test_log(msg)
            update_test_error_count(1)
        else
            write_sys_log(msg)
            update_sys_error_count(1)
        end
        return msg
    end
    local injected = {}
    for k, v in pairs(_G) do
        if type(v) == "function" and before[k] ~= v then injected[k] = v end
    end
    mod.injected = injected
    mod.enabled = true
    mod.paused = false
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
    for k, _ in pairs(mod.injected) do _G[k] = nil end
    mod.injected = {}
    mod.enabled = false
    mod.paused = false
    return "[卸载] 模块已卸载：" .. modname
end

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

function cmd_go_to(args)
    if #args < 1 then return "[错误] 用法：$/go to <路径>" end
    if args[1] == "km" or args[1] == "build" then
        return "[系统] 切换到 KM 模式"
    end
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

function cmd_ls(args)
    local path = args[1] and resolve_path(args[1]) or current_path
    local dir = File(path)
    if not dir.exists() then return "[错误] 路径不存在：" .. path end
    if not dir.isDirectory() then return "[错误] 目标不是文件夹" end
    local files = dir.listFiles()
    if not files or Array.getLength(files) == 0 then return "[信息] 文件夹为空" end
    local result = {"📁 目录：" .. path}
    local len = Array.getLength(files)
    for i = 0, len - 1 do
        local f = files[i]
        local name = f.getName()
        local icon = f.isDirectory() and "📁" or "📄"
        table.insert(result, string.format("%s %s", icon, name))
    end
    return table.concat(result, "\n")
end

function add_output(text)
    if kd_cli_output then
        kd_cli_output.append("\n" .. text)
        if kd_cli_scroller then
            kd_cli_scroller.fullScroll(View.FOCUS_DOWN)
        end
    else
        original_print(text)
    end
end

print = function(...)
    local args = {...}
    local parts = {}
    for i, v in ipairs(args) do
        parts[i] = tostring(v)
    end
    add_output(table.concat(parts, "\t"))
end

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
            return
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
            return
        elseif cmd == "list" then
            add_output(cmd_list())
            return
        elseif cmd == "ls" then
            add_output(cmd_ls(args))
            return
        elseif cmd == "pwd" then
            add_output(cmd_pwd())
            return
        elseif cmd == "go" and args[1] == "to" then
            if #args < 2 then
                add_output("[错误] 用法：$/go to <路径>")
                return
            end
            local result = cmd_go_to({args[2]})
            if result ~= "" then add_output(result) end
            return
        elseif cmd == "update" then
            silent_update()
            return
        elseif cmd == "clear" then
            clear_screen()
            return
        elseif cmd == "check" then
            check_stats()
            return
        elseif cmd == "help" then
            show_help()
            return
        else
            add_output("[错误] 未知命令：" .. cmd)
            return
        end
    end

    run_lua(line)
end

function run_lua(code)
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
            local msg = "[错误] " .. tostring(result)
            add_output(msg)
            if test_mode then
                write_test_log(msg)
                update_test_error_count(1)
            else
                write_sys_log(msg)
                update_sys_error_count(1)
            end
        end
    else
        add_output("[语法错误] " .. tostring(err))
    end
end

function check_stats()
    local sys_count = get_sys_error_count()
    local version = get_local_version()
    
    clear_screen()
    
    add_output("=== 错误统计 ===")
    add_output("当前版本: " .. version)
    add_output("系统错误总数: " .. sys_count)
    
    local f = io.open(SYS_ERROR_HISTORY, "r")
    if f then
        local lines = {}
        for line in f:lines() do
            table.insert(lines, line)
        end
        f:close()
        
        if #lines > 0 then
            add_output("\n=== 老版本历史 ===")
            local start = math.max(1, #lines - 4)
            for i = start, #lines do
                add_output(lines[i])
            end
        end
    end
    
    f = io.open(TEST_RESULT_FILE, "r")
    if f then
        local lines = {}
        for line in f:lines() do
            table.insert(lines, line)
        end
        f:close()
        
        if #lines > 0 then
            add_output("\n=== 新版本测试记录 ===")
            local start = math.max(1, #lines - 4)
            for i = start, #lines do
                add_output(lines[i])
            end
        end
    end
end

function clear_screen()
    if kd_cli_output then
        kd_cli_output.setText("")
        add_output(">>> Kairos Dynamics Engine (KD ENGINE) 命令行已启动")
        add_output(">>> 根目录: " .. BASE_PATH)
        add_output(">>> 当前路径: " .. current_path)
        add_output(">>> 输入 $/help 查看命令，输入 $/update 检查更新")
        add_output(">>> 直接输入 Lua 代码立即执行\n")
        scan_lua_modules()
        scan_func_modules()
        local lua_count = 0
        for _ in pairs(lua_modules) do lua_count = lua_count + 1 end
        local func_count = 0
        for _ in pairs(func_modules) do func_count = func_count + 1 end
        add_output("[系统] Your module: " .. lua_count .. " 个模块")
        add_output("[系统] function: " .. func_count .. " 个文件\n")
    end
end

function show_help()
    local help = [[
========== KD_ENGINE 命令帮助 ==========
【原生Lua】直接输入任何Lua 5.1代码执行

【管理命令】(必须以 $/ 开头)
  $/enable <模块名>           - 启用 Lua 模块
  $/enable function <名>     - 启用 function 模块
  $/disable <模块名>         - 卸载 Lua 模块
  $/list                    - 列出所有模块状态

【文件操作】
  $/ls [路径]                - 列出目录内容
  $/pwd                     - 显示当前路径
  $/go to <路径>             - 切换路径

【系统命令】
  $/update                  - 检查并静默更新
  $/check                   - 查看错误统计（自动清屏）
  $/clear                   - 清屏
  $/help                    - 显示本帮助

【网络状态】
  系统会自动识别国内外网络，选择最优镜像
=========================================
]]
    add_output(help)
end

function create_cli()
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
            hint = "> 输入命令或Lua代码",
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
    activity.setTitle("Kairos Dynamics Engine")
    activity.setContentView(loadlayout(layout, vars))

    kd_cli_output = vars.output
    kd_cli_scroller = vars.scroller
    kd_cli_input = vars.input

    current_version = get_local_version()
    clear_screen()

    kd_cli_input.requestFocus()
    kd_cli_input.setOnKeyListener(function(view, keyCode, event)
        if event.getAction() == KeyEvent.ACTION_DOWN and keyCode == KeyEvent.KEYCODE_ENTER then
            local code = view.getText().toString()
            if code and code ~= "" then
                add_output("> " .. code)
                execute_command(code)
                view.setText("")
            end
            return true
        end
        return false
    end)
    
    activity.getHandler().postDelayed(function()
        silent_update()
    end, 1000)
end

function check_permission()
    if activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED then
        local dirs = {BASE_PATH, LUA_PATH, FUNC_PATH, CODE_PATH}
        for _, d in ipairs(dirs) do
            local f = File(d)
            if f and not f.exists() then f.mkdirs() end
        end
        create_cli()
    else
        activity.requestPermissions({Manifest.permission.WRITE_EXTERNAL_STORAGE}, 100)
    end
end

function onRequestPermissionsResult(requestCode, permissions, grantResults)
    if requestCode == 100 then
        if grantResults and #grantResults > 0 and grantResults[0] == PackageManager.PERMISSION_GRANTED then
            check_permission()
        else
            print("❌ 需要存储权限")
            activity.finish()
        end
    end
end

check_permission()
-- =============================================

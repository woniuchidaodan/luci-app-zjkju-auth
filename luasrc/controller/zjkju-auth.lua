module("luci.controller.zjkju-auth", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/zjkju-auth") then
		return
	end

	entry({"admin", "services", "zjkju-auth"},
		cbi("zjkju-auth/main"),
		_("ZJKJU 校园网认证"), 60).dependent = true

	entry({"admin", "services", "zjkju-auth", "log"},
		call("action_get_log")).leaf = true

	entry({"admin", "services", "zjkju-auth", "restart"},
		call("action_restart")).leaf = true

	entry({"admin", "services", "zjkju-auth", "clearlog"},
		call("action_clear_log")).leaf = true

	entry({"admin", "services", "zjkju-auth", "status"},
		call("action_status")).leaf = true
end

function action_get_log()
	local sys = require "luci.sys"
	local log = sys.exec("logread -e zjkju-auth 2>/dev/null | tail -100")
	if not log or log == "" then
		log = "（暂无日志，服务可能还未启动过）"
	end
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write(log)
end

function action_restart()
	local sys = require "luci.sys"
	sys.call("/etc/init.d/zjkju-auth restart >/dev/null 2>&1")
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write("服务已重启")
end

function action_clear_log()
	local sys = require "luci.sys"
	sys.call("/etc/init.d/log restart >/dev/null 2>&1 &")
	luci.http.prepare_content("text/plain; charset=utf-8")
	luci.http.write("日志已清空")
end

function action_status()
	local sys = require "luci.sys"
	local running = false
	local online = false

	-- ===== 1. 进程检测：用 LuCI 原生 API =====
	-- 兼容不同版本的字段名（COMMAND / cmd / p[5]）
	local ok, procs = pcall(sys.process.list)
	if ok and procs then
		for _, p in ipairs(procs) do
			local cmd = ""
			if type(p) == "table" then
				cmd = p.COMMAND or p.cmd or p[5] or ""
			end
			if cmd ~= "" and (cmd:find("zjkju%-auth%-wrap") or cmd:find("zjkju%-auth%-wrapper")) then
				running = true
				break
			end
		end
	end

	-- 兜底：如果 process.list 失败，用 pidof
	if not running then
		local pid = sys.exec("pidof zjkju-auth-wrapper.sh 2>/dev/null")
		if pid then
			pid = pid:gsub("%s+", "")
			if pid ~= "" then
				running = true
			end
		end
	end

	-- ===== 2. 在线检测：优先 ping，用退出码 =====
	if sys.call("ping -c 1 -W 2 223.5.5.5 >/dev/null 2>&1") == 0 then
		online = true
	elseif sys.call("ping -c 1 -W 2 223.6.6.6 >/dev/null 2>&1") == 0 then
		online = true
	else
		-- 兜底：HTTP 检测
		local body = sys.exec("curl -s --max-time 5 'http://www.msftconnecttest.com/connecttest.txt' 2>/dev/null")
		if body then
			body = body:gsub("%s+", "")
			if body == "MicrosoftConnectTest" then
				online = true
			end
		end
	end

	luci.http.prepare_content("application/json; charset=utf-8")
	luci.http.write_json({
		running = running,
		online = online,
		ts = os.time()
	})
end

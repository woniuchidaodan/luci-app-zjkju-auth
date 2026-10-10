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
	local fs = require "nixio.fs"

	-- 1. 服务是否运行
	local running = false
	if fs.access("/var/run/zjkju-auth.pid") or
	   sys.exec("ps | grep zjkju-auth-wrapper | grep -v grep") ~= "" then
		running = true
	end

	-- 2. 网络是否在线（与 wrapper 的 is_online 逻辑一致）
	local online = false
	local body = sys.exec("curl -s --max-time 5 'http://www.msftconnecttest.com/connecttest.txt' 2>/dev/null | tr -d '\\r\\n'")
	if body and body == "Microsoft Connect Test" then
		online = true
	end

	luci.http.prepare_content("application/json; charset=utf-8")
	luci.http.write_json({
		running = running,
		online = online,
		ts = os.time()
	})
end

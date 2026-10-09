local m, s, o

m = Map("zjkju-auth", translate("ZJKJU 校园网认证"),
	translate("湛江科技学院锐捷 ePortal 自动认证。填写学号和密码后保存，勾选启用以启动服务。"))

s = m:section(NamedSection, "main", "zjkju-auth", translate("基本设置"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("启用"))
o.default = 0
o.rmempty = false
o.description = translate("勾选后保存，服务会自动启动并开机自启。取消勾选并保存，服务会停止。")

o = s:option(Value, "username", translate("学号"))
o.datatype = "string"
o.rmempty = false

o = s:option(Value, "password", translate("密码"))
o.password = true
o.datatype = "string"
o.rmempty = false

o = s:option(Value, "service", translate("服务类型"))
o.default = "%E7%94%B5%E4%BF%A1%E6%A0%A1%E5%9B%AD%E7%BD%91"
o.rmempty = false
o.description = translate("电信校园网请保持默认值：%E7%94%B5%E4%BF%A1%E6%A0%A1%E5%9B%AD%E7%BD%91")

o = s:option(Value, "check_interval", translate("检测间隔（秒）"))
o.datatype = "uinteger"
o.default = 60
o.rmempty = false

o = s:option(TextValue, "manual_url", translate("手动认证 URL（可选）"),
	translate("自动抓取失败时的兜底。留空则自动抓取。可以从浏览器地址栏复制完整认证页 URL 粘贴到这里。"))
o.rows = 3
o.rmempty = true
o.optional = true

-- 运行日志显示区
local sec = m:section(SimpleSection)
sec.template = "zjkju-auth/log"

-- 提交后根据 enabled 状态控制服务
function m.on_after_commit(self)
	local uci = require "luci.model.uci".cursor()
	local enabled = uci:get("zjkju-auth", "main", "enabled")

	if enabled == "1" then
		luci.sys.call("/etc/init.d/zjkju-auth enable >/dev/null 2>&1")
		luci.sys.call("/etc/init.d/zjkju-auth restart >/dev/null 2>&1")
	else
		luci.sys.call("/etc/init.d/zjkju-auth stop >/dev/null 2>&1")
		luci.sys.call("/etc/init.d/zjkju-auth disable >/dev/null 2>&1")
	end
end

return m

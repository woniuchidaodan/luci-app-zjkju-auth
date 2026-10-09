# LuCI App - 湛江科技学院锐捷校园网自动认证 (luci-app-zjkju-auth)

一个用于 ImmortalWrt / OpenWrt 的 LuCI 应用，在后台自动完成湛江科技学院锐捷 ePortal Web 认证，支持断线自动重连、开机自启、Web 界面配置。

本项目的核心认证逻辑基于上游项目 [Micro-Cnhua/Ruijie_Porta_Auth](https://github.com/Micro-Cnhua/Ruijie_Porta_Auth)（该上游又参考了 [Turris-Babel/school_ruijie](https://github.com/Turris-Babel/school_ruijie)）也一定程度上参考了本校前辈的思路[ZJKJU-Network-Login](https://github.com/YaYa404/ZJKJU-Network-Login)。我们在其基础上将其封装为 OpenWrt 软件包，并增加了 LuCI 图形界面和自动重连 wrapper。

> ⚠️ 本项目仅针对湛江科技学院（ZJKJU）锐捷 ePortal Web 认证进行适配。其他学校的锐捷 Web 认证页面如果结构相同，理论上也能使用，但需要自行测试。

## 📷 界面预览

- **菜单**：服务 → ZJKJU 校园网认证
- **配置项**：学号、密码、服务类型（默认电信校园网）、检测间隔、手动认证 URL（可选）
- **运行日志**：实时查看认证日志，每 10 秒自动刷新
![图片](./认证页.png)

## ✨ 特性

- ✅ **图形化配置**：LuCI Web 界面填写学号密码，无需 SSH
- ✅ **自动认证**：开机自启动，断线自动重连
- ✅ **进程守护**：procd 守护，崩溃后自动重启
- ✅ **实时日志**：LuCI 页面内查看运行日志，无需 SSH
- ✅ **三层 URL 兜底**：手动 URL / 自动抓取 / 缓存兜底
- ✅ **严格遵循上游**：认证逻辑 100% 复用上游 Go 二进制，不做任何修改
- ✅ **兼容性好**：专为 ImmortalWrt 24.10 及以上版本编译

## 💻 支持平台

| 项目 | 版本 |
|------|------|
| 系统 | ImmortalWrt / OpenWrt 24.10+ |
| 目标平台 | `mediatek/filogic`（如 WR30U、AX3000T 等 MT7981 路由器） |
| CPU 架构 | `aarch64_cortex-a53` (ARM64) |

如需适配其他平台/架构，修改 `.github/workflows/build.yml` 中的 SDK 下载地址即可。

## 📥 下载预编译版本

进入 GitHub 仓库的 **Releases** 或 **Actions** 页面，下载最新构建产物：

| 文件名 | 适用平台 | 架构 |
|--------|----------|------|
| luci-app-zjkju-auth_1.0.0-r1_all.ipk | ImmortalWrt 24.10 | aarch64_cortex-a53 |

## 🚀 安装

### 1. 上传 ipk 到路由器

```bash
scp luci-app-zjkju-auth_1.0.0-r1_all.ipk root@192.168.1.1:/tmp/
```

### 2. SSH 登录路由器安装

```bash
opkg update
opkg install /tmp/luci-app-zjkju-auth_1.0.0-r1_all.ipk
```

如果提示缺少依赖（`luci-compat`、`curl`），先执行：

```bash
opkg install luci-compat curl
```

### 3. 登录 LuCI 配置

浏览器打开 `http://192.168.1.1` （你真实的路由器后台地址，这里仅供参考）→ **服务 → ZJKJU 校园网认证**

- **启用**：勾选
- **学号**：填你的学号
- **密码**：填你的密码
- **服务类型**：保持默认 `%E7%94%B5%E4%BF%A1%E6%A0%A1%E5%9B%AD%E7%BD%91`（电信校园网）
- **检测间隔（秒）**：默认 60，可改为 120 或 180 减少日志
- **手动认证 URL（可选）**：留空则自动抓取

点击 **保存并应用**，服务会自动启动。

### 4. 查看日志

页面底部"运行日志"区会实时显示认证日志，每 10 秒自动刷新：

```
wrapper started
锐捷认证客户端启动
用户名: 填你的学号
身份类型: %E7%94%B5%E4%BF%A1%E6%A0%A1%E5%9B%AD%E7%BD%91
使用手动指定的认证地址
认证地址: http://10.80.80.249/eportal/index.jsp?wlanuserip=...
提取到queryString (长度: 236)
已联网，无需认证
```

掉线时会自动触发：

```
正在尝试认证...
认证请求URL: http://10.80.80.249/eportal/InterFace.do?method=login
发送POST数据...
响应状态: 200
响应内容: {"userIndex":"...","result":"success",...}
认证成功！
```

## ⚙️ 工作原理

本项目由三个组件构成：

| 组件 | 职责 |
|------|------|
| `ruijie` (Go 二进制) | 执行一次认证，接收 `-u -p -s -m` 参数（严格复用上游） |
| `zjkju-auth-wrapper.sh` | 循环检测在线状态；掉线时抓取最新 URL；调用 `ruijie` |
| LuCI 前端 | 配置界面 + 日志查看 |

### 三层 URL 兜底

1. **手动 URL**：若用户在 LuCI 中填写了手动 URL，优先使用
2. **自动抓取**：访问普通外网（baidu/example/qualcomm），从 302 响应中提取带 `wlanuserip` 的认证页 URL
3. **缓存兜底**：使用上次认证成功时缓存的 URL

### 为什么不用 `-e` 持久化模式？

上游 `ruijie` 的 `-e` 模式进入循环后**永远使用最初传入的 URL**。但学校掉线后 `wlanuserip` 等参数会变化，旧 URL 会失效。因此我们用 wrapper 重新实现了循环，每次掉线都重新抓取最新 URL。

### 为什么不用 `getOnlineUserInfo` 判断在线？

`getOnlineUserInfo` 接口**不带 Cookie 请求时永远返回 fail**，不能反映真实在线状态。我们让 `ruijie` 二进制内部自带的 `checkNetwork()` 判断在线（访问百度/QQ/163）。

## 🛠️ 自行编译

### 使用 GitHub Actions 云编译（推荐）

1. Fork 本仓库
2. 修改 `.github/workflows/build.yml` 中的 SDK 地址（如需适配其他平台）
3. 推送到 `main` 分支，GitHub Actions 会自动编译
4. 在 Actions 页面的 Artifacts 中下载 `luci-app-zjkju-auth-ipk`

### 本地编译（需要 OpenWrt SDK）

```bash
# 1. 下载对应 SDK
wget https://downloads.immortalwrt.org/releases/24.10.6/targets/mediatek/filogic/immortalwrt-sdk-24.10.6-mediatek-filogic_gcc-13.3.0_musl.Linux-x86_64.tar.zst
tar --use-compress-program=unzstd -xf immortalwrt-sdk-*.tar.zst
cd immortalwrt-sdk-*/

# 2. 拉取 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 3. 放置本包
cp -r /path/to/luci-app-zjkju-auth package/

# 4. 编译
make package/luci-app-zjkju-auth/compile V=s

# 5. 产物在 bin/packages/<arch>/base/ 下
```

## 📁 项目结构

```
luci-app-zjkju-auth/
├── .github/workflows/build.yml       # GitHub Actions 云编译配置
├── Makefile                          # OpenWrt 包定义
├── root/                             # 安装到路由器的文件
│   ├── etc/
│   │   ├── config/zjkju-auth         # UCI 默认配置
│   │   ├── init.d/zjkju-auth         # procd 服务脚本
│   │   └── uci-defaults/80_zjkju-auth # 首次安装初始化
│   └── usr/
│       ├── bin/zjkju-auth-wrapper.sh # 自动重连 wrapper（核心）
│       └── share/
│           ├── luci/menu.d/          # LuCI 菜单注册
│           └── rpcd/acl.d/           # LuCI 权限声明
└── luasrc/                           # LuCI 前端源码
    ├── controller/zjkju-auth.lua     # 路由控制器
    ├── model/cbi/zjkju-auth/main.lua # 配置表单
    └── view/zjkju-auth/log.htm       # 日志显示视图
```

## ❓ 常见问题

**Q：为什么日志一直显示"已联网，无需认证"？**

A：说明当前在线。`ruijie` 每次都会调一次，检测到在线就打印这句。可以调大"检测间隔"减少日志。

**Q：为什么清空手动 URL 后一直显示"无可用认证 URL"？**

A：早期版本的 wrapper 在抓不到 URL 时会跳过认证。最新版本已修复——抓不到 URL 时用占位符调用 `ruijie`，让上游自己判断在线状态。

**Q：为什么日志显示"使用手动指定的认证地址"？**

A：这是上游 `ruijie` 二进制的固定输出。只要传了 `-m` 参数就会打印这句，不代表用的就是"手动填的 URL"。实际来源可能是自动抓取或缓存。

**Q：服务无法启动 / 认证一直失败怎么办？**

A：
1. 检查学号和密码是否正确
2. 检查"服务类型"是否为 `%E7%94%B5%E4%BF%A1%E6%A0%A1%E5%9B%AD%E7%BD%91`
3. 从浏览器复制一次有效的认证 URL，粘贴到"手动认证 URL"框，保存并应用
4. 查看日志定位具体错误

**Q：支持其他学校吗？**

A：理论上只要认证页面结构相同就能用。但需要自行测试。主要差异可能在：
- `service` 参数值（本仓库针对"电信校园网"）
- 认证服务器 IP（本仓库针对 `10.80.80.249`）
- 是否需要 RSA 加密密码（本仓库使用明文，`passwordEncrypt=false`）

如需适配其他学校，修改 `root/usr/bin/zjkju-auth-wrapper.sh` 和 `root/etc/config/zjkju-auth` 中的 `service` 与 `AUTH_SERVER` 即可。

## 🙏 致谢

本项目基于以下开源项目：

- [Micro-Cnhua/Ruijie_Porta_Auth](https://github.com/Micro-Cnhua/Ruijie_Porta_Auth) — 锐捷 ePortal 命令行认证工具（本项目核心认证逻辑来源）
- [Turris-Babel/school_ruijie](https://github.com/Turris-Babel/school_ruijie) — 上游的参考项目
- [ZJKJU-Network-Login](https://github.com/YaYa404/ZJKJU-Network-Login) — 本校前人的贡献
- 所有 LuCI 和 OpenWrt 社区的贡献者

## 📄 许可证

本项目遵循上游项目的许可证。使用前请阅读上游仓库的 LICENSE。

## ⚠️ 免责声明

- 本项目仅供学习交流使用，请勿用于商业用途
- 使用本工具可能违反学校网络管理规定，请自行承担风险
- 密码保存在路由器 `/etc/config/zjkju-auth` 中（权限 600，仅 root 可读），请确保路由器安全

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-zjkju-auth
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=no-mips16

GO_PKG:=ruijie-auth

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/luci-app-zjkju-auth
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI app for ZJKJU Ruijie ePortal authentication
  DEPENDS:=$(GO_ARCH_DEPENDS) +luci-base +luci-compat +curl
endef

define Package/luci-app-zjkju-auth/description
  A LuCI application that keeps ZJKJU campus network logged in via Ruijie ePortal web authentication.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./Ruijie_Portal_Auth.go ./go.mod $(PKG_BUILD_DIR)/
endef

define Package/luci-app-zjkju-auth/install
	$(call GoPackage/Package/Install/Bin,$(PKG_INSTALL_DIR))

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/ruijie-auth $(1)/usr/bin/ruijie
	$(INSTALL_BIN) ./root/usr/bin/zjkju-auth-wrapper.sh $(1)/usr/bin/zjkju-auth-wrapper.sh
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/zjkju-auth $(1)/etc/config/zjkju-auth
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/zjkju-auth $(1)/etc/init.d/zjkju-auth
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/80_zjkju-auth $(1)/etc/uci-defaults/80_zjkju-auth
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-zjkju-auth.json $(1)/usr/share/luci/menu.d/luci-app-zjkju-auth.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-zjkju-auth.json $(1)/usr/share/rpcd/acl.d/luci-app-zjkju-auth.json
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/zjkju-auth.lua $(1)/usr/lib/lua/luci/controller/zjkju-auth.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/model/cbi/zjkju-auth
	$(INSTALL_DATA) ./luasrc/model/cbi/zjkju-auth/main.lua $(1)/usr/lib/lua/luci/model/cbi/zjkju-auth/main.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/zjkju-auth
	$(INSTALL_DATA) ./luasrc/view/zjkju-auth/log.htm $(1)/usr/lib/lua/luci/view/zjkju-auth/log.htm
endef

$(eval $(call GoBinPackage,luci-app-zjkju-auth))
$(eval $(call BuildPackage,luci-app-zjkju-auth))

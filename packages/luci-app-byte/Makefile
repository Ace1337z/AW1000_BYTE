include $(TOPDIR)/rules.mk
PKG_NAME:=luci-app-byte
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=Ace1337z
PKG_LICENSE:=GPL-3.0
LUCI_TITLE:=BYTE - one page for the firmware's own services
LUCI_DESCRIPTION:=Integrated control panel: AdGuard Home setup and status, DNS chain, system state and shortcuts to the pages this firmware ships.
# luci-base gives the JS framework, rpcd the exec plugin host, jshn the JSON
# helpers used by /usr/libexec/rpcd/byte.
LUCI_DEPENDS:=+luci-base +rpcd +libubox +jsonfilter +ubus
include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-byte/install
	$(INSTALL_DIR) $(1)/usr/libexec/luci-app-byte
	$(INSTALL_BIN) ./root/usr/libexec/luci-app-byte/agh-passwall2.sh \
		$(1)/usr/libexec/luci-app-byte/agh-passwall2.sh
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/byte $(1)/usr/libexec/rpcd/byte
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-byte.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-byte.json
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-byte.json \
		$(1)/usr/share/luci/menu.d/luci-app-byte.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/byte
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/byte/overview.js \
		$(1)/www/luci-static/resources/view/byte/overview.js
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/90-luci-app-byte \
		$(1)/etc/uci-defaults/90-luci-app-byte
	$(INSTALL_DIR) $(1)/www/luci-static/resources/byte
	$(INSTALL_DATA) ./htdocs/luci-static/resources/byte/byte.css \
		$(1)/www/luci-static/resources/byte/byte.css
endef

$(eval $(call BuildPackage,luci-app-byte))

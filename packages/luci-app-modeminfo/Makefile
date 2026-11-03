include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-modeminfo
PKG_VERSION:=1.2
PKG_RELEASE:=1

PKG_MAINTAINER:=YiZhen Choo <yizhen.c02@gmail.com>
PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE

LUCI_TITLE:=LuCI App for Modem Information
LUCI_DESCRIPTION:=This LuCI app provides modem information in a web interface.
# JS view + rpcd exec plugin; the AT tool is QModem's sms_tool_q (plain
# sms_tool does not exist in this image), and the FXS/qmi drivers come from
# their own packages. $(CHMOD) does not exist in this buildroot - the original
# Makefile line expanded to "755 <file>" and killed the build with Error 127,
# so Package/install uses INSTALL_BIN, which copies AND sets 0755.
LUCI_DEPENDS:=+luci-base +rpcd +libubox +ubus +sms-tool_q +kmod-usb-serial-option

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=luci
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=$(LUCI_TITLE)
	PKGARCH:=all
	DEPENDS:=$(LUCI_DEPENDS)
endef

define Package/$(PKG_NAME)/description
	$(LUCI_DESCRIPTION)
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/modeminfo
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/usr/libexec/rpcd \
		$(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d
	$(INSTALL_BIN) ./files/usr/bin/modeminfo $(1)/usr/bin/modeminfo
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/modeminfo $(1)/usr/libexec/rpcd/modeminfo
	# The menu entry and its ACL are what make the page reachable at all. The
	# old recipe copied ./files/etc and ./files/www only, so both JSON files
	# stayed in the source tree and the app shipped invisible: no menu item,
	# and rpcd answered "Permission denied" because the ACL never existed.
	$(INSTALL_DATA) ./files/usr/share/luci/menu.d/luci-app-modeminfo.json \
		$(1)/usr/share/luci/menu.d/luci-app-modeminfo.json
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/luci-app-modeminfo.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-modeminfo.json
	$(CP) ./files/etc $(1)/
	$(CP) ./files/www $(1)/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
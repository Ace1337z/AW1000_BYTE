include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-modeminfo
PKG_VERSION:=1.1
PKG_RELEASE:=1

PKG_MAINTAINER:=YiZhen Choo <yizhen.c02@gmail.com>
PKG_LICENSE:=GPL-3.0
PKG_LICENSE_FILES:=LICENSE

LUCI_TITLE:=LuCI App for Modem Information
LUCI_DESCRIPTION:=This LuCI app provides modem information in a web interface.
# JS view + rpcd exec plugin; the AT tool is QModem's sms_tool_q (plain
# sms_tool does not exist in this image), and the FXS/qmi drivers come from
# their own packages.
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
	$(CP) ./files/* $(1)/
	$(CHMOD) 755 $(1)/usr/bin/modeminfo $(1)/usr/libexec/rpcd/modeminfo
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
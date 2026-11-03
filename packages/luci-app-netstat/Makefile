include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netstat
PKG_VERSION:=1.2
PKG_RELEASE:=6
PKG_MAINTAINER:=dotycat <support@dotycat.com>
PKG_LICENSE:=GPL-3.0
LUCI_TITLE:=NET Stats
LUCI_DESCRIPTION:=This LuCI app provides net statistic functionality in a web interface.

# Vendored from dotywrt/dotycat-package, branch dotycat, luci-app-netstat.
# Upstream declares DEPENDS:=+vnstat +curl, which cannot resolve here:
# ImmortalWrt 25.12 ships vnstat2 and there is no "vnstat" package in the
# feeds, so defconfig silently dropped the whole app. vnstat2 is the same
# upstream program (2.13), so depend on it. luci-compat is required because
# this app is a Lua controller/template (menu + page are registered in Lua).
LUCI_DEPENDS:=+vnstat2 +curl +luci-compat

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-netstat/install
	$(CP) ./files/* $(1)/
	# vnstat2 owns /etc/config/vnstat; shipping upstream's copy would either
	# be ignored or fight the package for file ownership.
	$(RM) $(1)/etc/config/vnstat
endef

$(eval $(call BuildPackage,luci-app-netstat))

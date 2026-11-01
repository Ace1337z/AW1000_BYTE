include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-netstat
PKG_VERSION:=1.1.5
PKG_RELEASE:=25

PKG_MAINTAINER:=NoobLK <liyanagelsofficial@gmail.com>
PKG_LICENSE:=GPL-3.0

LUCI_TITLE:=NET Stats
LUCI_DESCRIPTION:=This LuCI app provides net statistic functionality in a web interface.
# ImmortalWrt 25.12 ships vnstat2, which CONFLICTS with the old vnstat package
# and does NOT declare PROVIDES:=vnstat (upstream added that later). Depending
# on the bare "+vnstat" here would leave the dependency unresolvable, and
# defconfig then drops the whole app without a word. Depend on the package that
# actually exists and installs /usr/bin/vnstat + /etc/init.d/vnstat.
# luci-lib-nixio is required by the controller (nixio.nanosleep for the CPU
# delta); it happens to be in the image, but state it so it stays that way.
LUCI_DEPENDS:=+vnstat2 +luci-compat +luci-lib-nixio

include $(TOPDIR)/feeds/luci/luci.mk

define Package/luci-app-netstat/install
	$(CP) ./files/* $(1)/
	# vnstat package owns /etc/config/vnstat on newer OpenWrt versions.
	# Remove it here to avoid file ownership conflicts if present in any tree.
	$(RM) $(1)/etc/config/vnstat
endef

$(eval $(call BuildPackage,luci-app-netstat))

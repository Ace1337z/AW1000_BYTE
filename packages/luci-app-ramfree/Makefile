# SPDX-License-Identifier: Apache-2.0
#
# Vendored from immortalwrt/luci applications/luci-app-ramfree.
#
# The luci feed is pinned to 350fc919 (the first pin that carries
# view/dashboard/lib/*), and ImmortalWrt added this app after that pin. Relying
# on the feed would make the package vanish from the image silently and trip the
# CI assert in aw1000_byte.sh. The app is a ucode controller plus two JSON
# files, so vendoring costs ~1 KB and keeps the pin intact.
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-ramfree
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=ImmortalWrt.org

LUCI_TITLE:=LuCI support for RAM free
LUCI_DESCRIPTION:=Adds "Release RAM" under Status: sync and drop caches.
# luci-base supplies the ucode dispatcher the controller registers with.
LUCI_DEPENDS:=+luci-base

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

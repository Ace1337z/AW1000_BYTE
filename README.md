# AW1KBUILDER

## Overview

AW1KBUILDER is a beginner-friendly OpenWrt build script designed for quick deployment and daily use. It comes with a full set of pre-configured packages and system tweaks, making it ideal for users who want a plug-and-play solution without needing to configure everything from scratch.

Firmware produced by this repo is branded **BYTE by ACE** and targets the Arcadyan **AW1000** (`qualcommax/ipq807x`).

## Features

- Beginner Friendly: Automates the entire build process — from dependencies to final firmware output.
- Ready-to-use Preset: Comes with essential packages and system configurations tailored for optimal performance and modem support.
- Customizable via Menuconfig: Offers flexibility to add, remove, or update packages and kernel versions via `make menuconfig`.
- CI build: `.github/workflows/build.yml` builds the firmware on GitHub Actions and publishes a release.

## Preset Tweaks

- BBR congestion control
- ZRAM swap enabled
- CPU frequency scaling (all cores active)
- TTL 64 (for modem/router compatibility)

## Preset Packages

- **VPN / proxy:** `passwall`, `passwall2`, `openclash`
- **DNS ad-blocking:** `adguardhome` (+ LuCI app)
- **Modem:** `qmodem` (replaces 3GInfo Lite / modemband / SMS tools). It supplies the
  Quectel/Fibocom/Simcom vendor QMI drivers, so the packaged
  `kmod-usb-net-qmi-wwan-{quectel,fibocom}` copies are disabled — both ship the same
  `qmi_wwan_q.ko`/`qmi_wwan_f.ko` and would collide at rootfs assembly. Dialing uses
  qmodem's `quectel-CM-M`; `quectel-cm` + `luci-proto-quectel` are therefore off.
- **Phone port:** `kmod-aw1000-fxs`, `fxsd`, `luci-app-fxs` — RJ11 port on the back panel (Services > Phone)
- **NSS offload:** `kmod-qca-nss-drv`, `kmod-qca-nss-ecm`, `nss-firmware` (QSDK 12.5) — hardware NAT/bridge offload
- **System tools:** `htop`, `traffic monitor`, `RAM releaser`, `terminal access`
- **Theme:** `vantage` (default, from the [Ace1337z fork](https://github.com/Ace1337z/luci-theme-vantage)),
  footstrap / Argon / Bootstrap also shipped
- **Extras:** `SFTP (OpenSSH) support`

## Base

- ImmortalWrt `openwrt-25.12`
- Kernel 6.12
- **opkg / ipk** packages (`CONFIG_USE_APK` off) — not apk

## Default WiFi Settings

- **SSID:** `BYTE` (2.4 GHz) / `BYTE` (5 GHz) — both radios
- **Password:** none (open network)

## Phone port (RJ11)

The three `fxs` packages come from the `fxs` feed
([openwrt-aw1000-phone](https://github.com/Ace1337z/openwrt-aw1000-phone)).

The SLIC needs Skyworks' ProSLIC DSP patch after every reset. This build ships it
pre-converted at `/etc/fxs/si3226x_patch.bin` (patch ID `0x05262017`,
`si3226x_patch_C_FB_2017MAY26`), and `fxsd` is enabled on first boot, so the port
works out of the box.

To regenerate the patch file:

1. `wget -O si3226x_patch_C_FB_2017MAY26.c \
   https://raw.githubusercontent.com/olforu/study/03f601ff4e50a383d08443b06cb0f06fd1a1499b/proslic_api/patch_files/si3226x_patch_C_FB_2017MAY26.c`
2. `python3 tools/mkpatch.py si3226x_patch_C_FB_2017MAY26.c si3226x_patch.bin`
   (see `tools/mkpatch.py` in the fxs feed)
3. Place the result at `files/etc/fxs/si3226x_patch.bin` in this repo.

Set the modem PCM interface to slave mode once (fxsd's LuCI page does this, or):
`ubus call at-daemon sendat '{"at_port":"/dev/ttyUSB2","at_cmd":"AT+QDAI=x,1,0,4,0,0,1,1","timeout":3}'`

Enable/disable any time with `/etc/init.d/fxsd enable|start|stop`. The `PHONE` LED
is driven by `fxsd` while the port is active.

> The Skyworks patch is not redistributable; review the ProSLIC licence before
> redistributing images built from this repo.

## NSS hardware offload

Wired NAT and bridge forwarding run on the two NSS cores instead of the CPU
(`qca-nss-drv` + `qca-nss-ecm`, QSDK 12.5, firmware 12.5 "Release 210").

- Feed: [qosmio/nss-packages](https://github.com/qosmio/nss-packages) branch `NSS-12.5-K6.x`
  (the `XT-Martinez` fork predates kernel 6.12 support).
- Kernel side: `nss/` carries the six `06xx` ECM patches, the `ipq8074-nss.dtsi`
  node set, and the AW1000 DTS include. They are copied into
  `target/linux/qualcommax/` at build time by `aw1kbuilder.sh`.
- Software flow offload is disabled (`flow_offloading '0'`) so fw4 and ECM do not
  fight over the same flows. `packet_steering` is off; ECM wants the IRQs where
  the NSS firmware puts them.
- `nf_conntrack_max` is raised to 65536 for proxy workloads.

What this does **not** do: proxied traffic (`passwall`/`passwall2`) is TPROXY'd
into a local socket, so it never reaches NSS — only direct traffic offloads. This
is a property of transparent proxying, not a misconfiguration. Per-connection
CPU cost for proxied flows is unchanged.

### TTL vs NSS offload (important)

The AW1000's only uplink is the cellular modem, and this build needs the TTL
rewrite (carrier/tethering detection). **NSS hardware offload and the netfilter
TTL rewrite are mutually exclusive on the same flow**: the NSS rule struct
(`nss_ipv4_create`) has no TTL/hop-limit field, and once ECM offloads a flow its
packets bypass netfilter — so the TTL rule in `/etc/nftables.d/ttl64.nft` is not
applied to offloaded traffic.

Therefore ECM is **installed but not started by default** (TTL priority). Use the
bundled toggle to switch:

- `nss-offload status` — show current state
- `nss-offload on` — enable NSS/ECM offload (max speed; TTL rewrite bypassed on offloaded flows)
- `nss-offload off` — disable NSS/ECM offload (default; TTL rewrite always applies)

The TTL value itself is configurable in LuCI under **Tools → TTL Config**
(`luci-app-nft-ttl`, default 64 for both IPv4 TTL and IPv6 Hop Limit).

The QSDK NSS driver and firmware are **not** GPL. Firmware blobs are
redistributed by `nss-firmware` from the QCA SDK release; review the Qualcomm
license before redistributing images built from this repo.

## Requirements

- Internet connection
- Ubuntu 22.04 LTS or newer
- Adequate disk space and RAM
- Basic terminal usage knowledge

## Quick Installation

```bash
wget https://raw.githubusercontent.com/Ace1337z/aw1kbuilder/main/aw1kbuilder.sh && chmod +x aw1kbuilder.sh && ./aw1kbuilder.sh
```

# BYTE for the Arcadyan AW1000

Custom ImmortalWrt 25.12.1 firmware (kernel 6.12.94) for the Arcadyan AW1000
(`ipq807x`): Quectel QMI cellular, NSS-accelerated WiFi, RJ11 phone, SMS,
TTL/Hop-Limit normalisation, PassWall2 and a themed LuCI dashboard. Every image
is built, signed and published from CI, together with a self-hosted opkg repo.

[![release](https://img.shields.io/github/v/release/Ace1337z/AW1000_BYTE?style=flat-square&label=release&color=00B5E2)](../../releases/latest)
[![kernel](https://img.shields.io/badge/kernel-6.12.94-8e7cc3?style=flat-square)](#)
[![target](https://img.shields.io/badge/target-ipq807x%2Faw1000-5a6472?style=flat-square)](https://openwrt.org/toh/arcadyan/aw1000)

![Dashboard](docs/screenshots/dashboard.png)
<sub>Dashboard — modem signal, temperature and NSS-offload widgets. Screenshot from
[XT-Martinez/aw1000-feed](https://github.com/XT-Martinez/aw1000-feed), whose widgets this image ports.</sub>

## Quick start

| | |
|---|---|
| **Download** | [Latest release](../../releases/latest) → `BYTE_by_ACE-<version>-qualcommax-ipq807x-arcadyan_aw1000-squashfs-sysupgrade.bin` |
| **Web UI** | <http://192.168.1.1> |
| **Login** | `root`, no password |
| **WiFi** | `BYTE` on 2.4 + 5 GHz, open |
| **SIM** | insert, boot, the APN negotiates itself |

> **Set a root password and a WiFi key right after flashing.** Both ship open so
> a fresh unit is reachable without a sticker.

### Flash

```sh
sha256sum -c sha256sums
sysupgrade -n BYTE_by_ACE-<version>-qualcommax-ipq807x-arcadyan_aw1000-squashfs-sysupgrade.bin
```

- `-n` discards `/etc/config`. Use it when coming from another firmware; drop it
  to keep settings.
- First install or a bricked unit: flash `...-squashfs-factory.ubi` from
  U-Boot/TFTP.
- Non-destructive test: boot `...-initramfs-uImage.itb` straight into RAM first.

> **Keep a recovery path before flashing anything** — serial console or the
> initramfs image under TFTP. An interrupted flash can leave the device
> unbootable without one, and `sysupgrade -n` does not preserve configuration.

## Features

- **Cellular** — QModem 3.3.0 over Quectel vendor QMI: band and cell lock, SMS
  (send, receive, forward to Telegram/webhook), signal and carrier-aggregation
  metrics, live dashboard.
- **TTL / Hop Limit** — one switch in *Network → Modem → TTL Configuration*;
  the rule matches `oifname "wwan*"`, so forwarded **and** router-originated
  traffic is rewritten. FW4 flow offload is held at `0` (hardware `0`) in both
  switch states, because it skips the mangle chain.
- **Phone (RJ11)** — `fxsd` with the SLIC driver built in: HD audio, caller ID,
  DND, call history.
- **WiFi** — NSS-accelerated 2.4/5 GHz; both radios up on first boot.
- **UI** — Footstrap 0.14.19, BYTE logo and icons, a BYTE panel (AdGuard Home ↔
  PassWall2 DNS wiring, system strip, shortcuts), a JS modem-info view, dashboard
  widgets and Netstat backed by persistent vnStat history.
- **Dashboard widgets** — Mobile (status card, signal chart, traffic chart,
  detail tab), Temperature, and NSS offload. The NSS widget stays hidden unless
  `qca-nss-ecm` is loaded, which it is not by default.
- **Proxy** — PassWall2 with Xray; first-run rules in place.
- **Remote** — Tailscale on demand; `tailscaled` starts only once credentials
  exist.
- **Tuning** — see below.

Install more from the published opkg repo (left out of the image to save space):

```sh
opkg update
opkg install luci-app-banip luci-app-smartdns luci-app-mwan3 luci-app-sqm
opkg install luci-app-openclash luci-app-adguardhome luci-app-nikki
opkg install tailscale luci-app-tailscale-community
```

### Tuning defaults

| | |
|---|---|
| Congestion control | `bbr` with `fq` (`kmod-tcp-bbr`), `tcp_slow_start_after_idle=0` |
| Socket buffers | `tcp_rmem`/`tcp_wmem` capped at 4 MB, `tcp_moderate_rcvbuf=1`, `tcp_notsent_lowat=131072` |
| TCP Fast Open | `tcp_fastopen=3` (client + server), blackhole timeout 60 s |
| NAPI / backlog | `netdev_budget=2400`, `netdev_max_backlog=16384`, `dev_weight=64` |
| Packet steering | `packet_steering=1`, `steering_flows=32768`, RPS/RFS on `wwan*`, XPS probed once |
| CPU / memory | `performance` governor, zram, modem IRQs spread across cores |
| Conntrack | 32768 max, 7440 established, keepalive 120/15/4 |
| vnStat | `DatabaseDir=/etc/vnstat` on the overlay, re-asserted every boot |

A boot-time self-check (`byte-selfcheck`) logs each of these and reports a
`MISMATCH` when one did not apply.

## Firmware version

Status → Overview shows, and every image filename carries, the same string:

```
BYTE 25.12(6.12.94) 1.2.8
     │      │        └── patch: commits since FW_BASE (version.env)
     │      └─────────── kernel: KERNEL_PATCHVER → target/linux/generic/kernel-6.12
     └────────────────── release series
```

`version.env` holds `FW_MAJOR`/`FW_MINOR`/`FW_BASE`/`FW_PATCH_FALLBACK`; the
patch is `git rev-list --count FW_BASE..HEAD`, so there is no manual bump. The
build aborts if the kernel version cannot be resolved rather than shipping
`25.12(x)`.

## Build

CI builds on every push to `main` that touches `preset`, `aw1000_byte.sh`,
`version.env`, `files/`, `packages/` or the workflow, and on manual dispatch
(Actions → *Build BYTE by ACE firmware (AW1000)*, input `branch`, default
`v25.12.1`).

Locally, on Debian/Ubuntu:

```sh
git clone https://github.com/Ace1337z/AW1000_BYTE.git && cd AW1000_BYTE
bash aw1000_byte.sh          # interactive menu; CI=1 SKIP_MENUCONFIG=1 for unattended
```

The script clones ImmortalWrt at the pinned tag, adds the qmodem, PassWall2,
NSS, phone, dotycat, nikki and Footstrap feeds (each pinned to a full commit
SHA), applies `preset` as `.config`, derives the version and builds. `files/` is
applied as a custom overlay *after* packages, so theme, logo and view overrides
win.

```
preset                     .config: packages, version, target
aw1000_byte.sh             build script, feed pins, CI assertions
version.env                firmware version inputs
files/                     rootfs overlay (services, views, branding)
packages/                  vendored LuCI packages (byte, netstat, modeminfo)
nss/                       NSS sources + kernel patches
.github/workflows/         CI: build, sign, publish firmware + opkg repo
```

## Known limits

- **Flow offload is always off.** `flow_offloading=0` and `flow_offloading_hw=0`
  with the TTL switch on *and* off. The flowtable accelerates a flow after its
  first packet, so later packets skip the mangle chain and keep the sender's
  TTL: clients that send 64 look right, Windows hosts (128) leak 128 for the
  life of the flow. Enabling it in LuCI re-introduces that leak.
  Router-originated traffic and every flow's first packet are still rewritten.
- **ECM is not shipped.** `kmod-qca-nss-ecm` is unset: its 12.5 tree needs the
  QSDK bonding API (`struct bond_cb`, `bond_register_cb`, `bond_get_id`) that
  mainline 6.12 does not export, and ECM bypasses netfilter, which would defeat
  the TTL rewrite. NSS acceleration of the radios is unaffected.
- **No hardware flow offload.** `flow_offloading_hw` stays `0` — `nss-dp` does
  not implement it, so fw4 would accept a `1` and silently ignore it.

## Credits

ImmortalWrt, OpenWrt, [qosmio/nss-packages](https://github.com/qosmio/nss-packages),
[VizzleTF/luci-theme-footstrap](https://github.com/VizzleTF/luci-theme-footstrap),
[XT-Martinez/aw1000-feed](https://github.com/XT-Martinez/aw1000-feed) (dashboard widgets),
[Perz3us/openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone),
QModem, [Openwrt-Passwall](https://github.com/Openwrt-Passwall),
[nikkinikki/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki),
[dotywrt/dotycat-package](https://github.com/dotywrt/dotycat-package) (LEDs),
[NoobLK/luci-app-netstat](https://github.com/Ace1337z/luci-app-netstat),
[SolomonRicky/luci-app-modeminfo](https://github.com/Ace1337z/luci-app-modeminfo).

**Licensing.** The Skyworks ProSLIC DSP patch is proprietary and not
redistributable; the QCA NSS driver and firmware carry the Qualcomm licence.
Review both before republishing an image built here.

## Changelog

### 1.2.x — 2026-11-02
- Footstrap moved to the upstream standalone repo, pinned to v0.14.19, and the
  luci feed bumped to a commit that carries `view/dashboard/lib/*` — the
  dashboard widgets now render instead of failing their `require` silently.
- Flow offload pinned off (`flow_offloading=0`, hardware `0`) in both TTL
  states; the rule matches forwarded and router-originated egress and the
  self-check asserts the pairing.
- Version string `BYTE 25.12(KERNEL) PATCH` in Status and in every filename,
  derived from the commit count with the kernel read from the target.
- Modem info rewritten as a JS view over an rpcd plugin: on-demand AT sampling
  with `flock` and atomic publish, no cron, no daemon, no external badges.
- Tuning applied and self-checked: BBR/`fq`, BDP-sized buffers, TFO, larger NAPI
  budget, packet steering, RPS/RFS/XPS, vnStat history on the overlay.
- QModem 2.8.9 → 3.3.0, phone 0.4.1 → 0.7.0, netstat vendored against
  `vnstat2`, Vantage removed, Tailscale moved to on-demand.

### Earlier
- 2026-10-26 `FINAL`: tuning baseline, Tailscale on demand, dashboard port,
  AdGuard Home wiring, first opkg repo.
- See `git log` for the full history.

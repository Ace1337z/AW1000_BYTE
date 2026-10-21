# BYTE by ACE — AW1000 Firmware

Custom **ImmortalWrt 25.12** firmware for the **Arcadyan AW1000** (`qualcommax/ipq807x`),
pre-configured so the router works the moment you flash it: WiFi, cellular auto-dial,
the RJ11 phone port, correct TTL, and a working proxy stack.

![Vantage dashboard, dark](docs/screenshots/dashboard-dark.png)

---

## Quick start

| | |
|---|---|
| **WiFi** | SSID `BYTE` on 2.4 GHz and 5 GHz — **no password** |
| **Web UI** | <http://192.168.1.1> |
| **Login** | user `root`, **no password** (set one immediately) |
| **SIM** | insert, boot, done — APN is auto-negotiated |

> ⚠️ Open WiFi and an empty root password. Set both before exposing the device.

---

## Contents

- [What it is](#what-it-is)
- [Features](#features)
- [Default configuration](#default-configuration)
- [The three custom services](#the-three-custom-services)
- [TTL and NSS offload](#ttl-and-nss-offload)
- [Building](#building)
- [Repository layout](#repository-layout)
- [Troubleshooting](#troubleshooting)
- [Licensing and credits](#licensing-and-credits)

---

## What it is

A complete `.config` plus a small rootfs overlay, built against a pinned ImmortalWrt
tree. Nothing is left for you to configure by hand:

- the modem dials on boot and keeps dialling
- the WAN interface is created and repaired automatically
- TTL is rewritten to 64 on modem egress
- the phone port has its SLIC firmware and PCM mode set up

Every package version is pinned by commit SHA, so a rebuild produces the same image.

---

## Features

### Cellular
- **qmodem 2.8.9** with the Quectel vendor QMI driver (`qmi_wwan_q`)
- Auto-dial on boot, **APN `auto`** — negotiated from the SIM, works on any carrier
- `pdp_type ipv4v6`, dual-stack (`wan` + `wanv6`)
- Live signal, bands, temperature, voltage and Connect Status in LuCI
- SMS send/receive via the qmodem SMS app

### WiFi
- `BYTE` on both radios, open by default
- 5 GHz: channel 149, HE80 · 2.4 GHz: channel 1, HE20
- 802.11k/v enabled so clients move to the better radio (both share one SSID)

### Phone (RJ11)
- Skyworks Si32261 SLIC DSP patch shipped at `/etc/fxs/si3226x_patch.bin`
- `fxsd` starts on boot; modem PCM is checked and forced to **slave** mode
- Dial tone, ringing, DTMF, Caller ID

### Proxy
- `passwall` (26.10.16) and `passwall2` (26.4.10)
- **Xray 26.3.27** — the only proxy core shipped (see [size](#size))
- DNS via chinadns-ng + nftset, transparent TCP/UDP proxy

### System
- Theme: **Vantage** (default), plus Footstrap and Bootstrap
- `luci-app-modeminfo` — signal dashboard with NR5G-SA, temperature, revision
- `luci-app-aw1k-led` — AW1000 LED control
- `luci-app-ramfree`, `luci-app-cpufreq`, `luci-app-vnstat2`, `luci-app-ttyd`
- `luci-app-filemanager`, `luci-app-tailscale-community`
- ZRAM swap, BBR + `fq`, tuned TCP buffers

---

## Default configuration

### Network

| Interface | Device | Proto | Notes |
|---|---|---|---|
| `wan` | `wwan0_1` | `dhcp` | default route, metric 11 |
| `wanv6` | `@wan` | `dhcpv6` | `extendprefix 1` |
| `lan` | `br-lan` | `static` | `192.168.1.1/24` |

### qmodem

```
at_port    /dev/ttyUSB3      <- the port that answers on this modem
use_ubus   0                 <- no ubus at-daemon in the 2.8.x line
apn        auto              <- works on any carrier
pdp_type   ipv4v6
```

`override_at_port` and `sms_at_port` are deliberately **unset** — pointing them at
`/dev/ttyUSB2` makes `tom_modem` block forever on the RG500Q, which shows up as an
empty Manufacturer/Revision/Temperature panel and "Disconnected" while the link is up.

### TTL

`/etc/config/qmodem_ttl` — `enable 1`, `ttl4 64`, `hl6 64`, `meta_mode wwan_only`.

---

## The three custom services

These fill gaps that upstream OpenWrt and qmodem leave on this device.

| Service | Problem it solves |
|---|---|
| **`byte-ttl`** | qmodem/LuCI TTL packages write a `postrouting`/`iifname` rule. This writes the correct rule — hook `forward`, match `oifname wwan0_1` — and re-applies it on boot. Regenerates `/etc/nftables.d/ttl64.nft`. |
| **`qmodem-iface-heal`** | qmodem's `hang()` deletes every network section carrying its `modem_config`. If the dial worker never reaches `set_if()` again, `wan`/`wanv6` stay missing and LuCI shows a preset-less interface. This recreates them (with qmodem's own lock) within seconds. |
| **`byte-affinity`** | The USB modem's interrupts all land on one core, and OpenWrt's stock `set-irq-affinity` only covers devices in `board.json` — never `wwan0_1`. This sets RPS/RFS/XPS on `wwan*` so packet processing spreads across all four cores. |

All three start from `rc.local` and `/etc/uci-defaults`, so they survive a
sysupgrade that keeps `/etc/config`.

---

## TTL and NSS offload

On this device the internet only exists over the modem, so **TTL and NSS flow
offload are mutually exclusive** on the same packet:

- NSS/ECM offload forwards established flows entirely in hardware, **bypassing
  netfilter** — a TTL rewrite never sees them.
- NSS has no in-hardware TTL support.

**Default: TTL wins.** ECM is not shipped at all — `qca-nss-ecm` 12.5 does not
compile against kernel 6.12.112 (`struct bond_cb` was reworked upstream).

`qca-nss-drv` is present, so NSS is still used where it does not conflict —
WiFi acceleration, bridge and VLAN managers.

---

## Building

### GitHub Actions (recommended)

Push to `main` (touching `preset`, `aw1000_byte.sh`, `files/**` or the workflow), or
run **Actions → Build BYTE by ACE firmware (AW1000) → Run workflow**.

A run takes roughly **2.5 hours**. The release step verifies the firmware is actually
attached before reporting success.

Output: `BYTE_by_ACE-<branch>-<run>` with

- `...-squashfs-sysupgrade.bin` — flashing an existing OpenWrt
- `...-squashfs-factory.ubi` — recovery / first install
- `...-initramfs-uImage.itb` — RAM boot for recovery

### Locally (Ubuntu 22.04+)

```bash
git clone https://github.com/Ace1337z/AW1000_BYTE.git
cd AW1000_BYTE
bash aw1000_byte.sh
```

Output: `immortalwrt/bin/targets/qualcommax/ipq807x/`.

The script clones ImmortalWrt (`--no-single-branch`, so the release branch exists),
applies `files/` as the rootfs overlay, `nss/` as kernel patches + DTS, and
`packages/` as a local feed, then runs `make defconfig` and builds.

Before compiling, `ci_check_packages` refuses the build if any of the following
regress — this has caught several real breakages:

- a duplicate QMI driver (`kmod-usb-net-qmi-wwan`, `uqmi`) that races `qmi_wwan_q`
- `qca-nss-ecm` or the NSS client modules reappearing
- TTL not set to 64/enabled, or the rule losing `oifname`
- `use_ubus=1` or the `ttyUSB2` overrides returning to the qmodem config
- any trimmed package (sing-box, AdGuardHome, hysteria, argon…) coming back

---

## Repository layout

```
AW1000_BYTE/
├── aw1000_byte.sh              # build entrypoint: feeds, preset, guards, build
├── preset                      # the full .config
├── files/                      # rootfs overlay
│   ├── etc/config/             # network, wireless, firewall, qmodem, qmodem_ttl, …
│   ├── etc/init.d/             # byte-ttl, qmodem-iface-heal, byte-affinity
│   ├── etc/fxs/                # si3226x_patch.bin
│   ├── etc/nftables.d/         # ttl64.nft
│   ├── etc/rc.local            # per-boot phone + service bring-up
│   ├── etc/uci-defaults/       # first-boot enablement
│   └── usr/                    # nss-offload, qmodem-iface-heal
├── nss/                        # kernel patches, DTS, xray-core Makefile overlay
├── packages/                   # local feed (luci-app-modeminfo)
├── docs/screenshots/           # README images
└── .github/workflows/          # CI build + release
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| WAN page shows no preset | qmodem deleted the interface | `qmodem-iface-heal` recreates it in ~20 s; check `logread \| grep qmodem-heal` |
| qmodem panel blank, "Disconnected" but internet works | AT hanging on `/dev/ttyUSB2` | ensure `at_port=/dev/ttyUSB3` and no `override_at_port` |
| Passwall says *"must be run on version 26.7.11+"* | passwall2 newer than 26.4.10 injects `version.min` | stay on the pinned passwall2 26.4.10 |
| Phone has no audio | modem PCM in master mode | `sms_tool -d /dev/ttyUSB3 at 'AT+QDAI?'` must show `x,1,…` |
| Band lock does nothing | AT path broken (see row 2) | fix `at_port`/`use_ubus` first |
| High CPU at ~500 Mbit/s | userspace crypto in xray, single-core IRQ | expected; `byte-affinity` spreads RPS |

Useful commands:

```sh
logread | grep -E 'byte-ttl|qmodem-heal|byte-affinity|fxsd'
/usr/bin/nss-offload status
nft list chain inet fw4 mangle_forward
sms_tool -d /dev/ttyUSB3 at 'AT+QENG="servingcell"'
```

---

## Licensing and credits

The image bundles components with their own licences, some of which restrict
redistribution:

- **Skyworks ProSLIC DSP patch** — proprietary, not redistributable. Review before
  republishing any image built from this repo.
- **QCA NSS driver and firmware** (QSDK 12.5) — Qualcomm licence applies.

Built on the work of:

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) — base distribution
- [FUjr/QModem](https://github.com/FUjr/QModem) — modem management (2.8.9)
- [Perz3us/openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone) — RJ11 driver
- [qosmio/nss-packages](https://github.com/qosmio/nss-packages) — NSS packages
- [Openwrt-Passwall](https://github.com/Openwrt-Passwall) — passwall / passwall2
- [dotywrt/dotycat-package](https://github.com/dotywrt/dotycat-package) — aw1k-led
- [Ace1337z/luci-theme-vantage](https://github.com/Ace1337z/luci-theme-vantage) — theme + dashboard
- [SolomonRicky/luci-app-modeminfo](https://github.com/Ace1337z/luci-app-modeminfo) — modem info

---

<details>
<summary>More screenshots</summary>

![Vantage dashboard, light](docs/screenshots/dashboard-light.png)

</details>

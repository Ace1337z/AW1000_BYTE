# BYTE by ACE — AW1000 Firmware

A maintained, tested custom firmware for the **Arcadyan AW1000** (`ipq807x`), built on
ImmortalWrt 25.12 with the Quectel vendor QMI stack and QCA NSS acceleration.

Cellular, WiFi, the RJ11 phone port, SMS, TTL spoofing, the proxy stack and remote access
all work out of the box — no setup wizards, no manual feed patching.

[![Latest release](https://img.shields.io/github/v/release/Ace1337z/AW1000_BYTE?style=for-the-badge&label=release&color=00B5E2)](../../releases/latest)
[![Platform](https://img.shields.io/badge/AW1000-ipq807x-5a6472?style=for-the-badge)](https://openwrt.org/toh/arcadyan/aw1000)
[![Base](https://img.shields.io/badge/ImmortalWrt-25.12-3d8b40?style=for-the-badge)](https://github.com/immortalwrt/immortalwrt)
[![Kernel](https://img.shields.io/badge/kernel-6.12.112-8e7cc3?style=for-the-badge)](#)

![Vantage dashboard](docs/screenshots/dashboard-dark.png)

---

## Contents

- [Quick start](#quick-start)
- [Features](#features)
- [Changelog](#changelog)
- [Technical reference](#technical-reference)
- [Troubleshooting](#troubleshooting)
- [Credits](#credits)

---

## Quick start

| | |
|---|---|
| **Download** | [Latest release](../../releases/latest) |
| **WiFi** | SSID `BYTE` on 2.4 GHz and 5 GHz — open, no password |
| **Web UI** | <http://192.168.1.1> |
| **Login** | `root`, no password |
| **SIM** | insert, boot — APN is negotiated automatically |

> **Set a root password and a WiFi key immediately after flashing.** Both ship open so a
> fresh install is reachable without hunting for a sticker.

### Flashing

```sh
sha256sum -c sha256sums
sysupgrade -n BYTE_by_ACE-FINAL-25.12-qualcommax-ipq807x-arcadyan_aw1000-squashfs-sysupgrade.bin
```

- `-n` discards `/etc/config` — recommended when coming from another firmware.
- First install or recovery: use `...-squashfs-factory.ubi`.
- Non-destructive test: boot `...-initramfs-uImage.itb` straight into RAM.

---

## Features

### Cellular
- **qmodem** with the Quectel vendor QMI driver (`qmi_wwan_q`)
- Auto-dial on boot, **APN `auto`** — negotiated from the SIM, works on any carrier
- **USB port auto-detection** — the preset targets slot `4-1`; if the modem enumerates
  elsewhere (e.g. `3-1`), the scan finds and dials it
- Dual-stack, with live signal, band, temperature and voltage in LuCI
- **TTL 64** on IPv4 and IPv6, modem egress only
- MTU 1420 applied on every redial

### WiFi
- `BYTE` on both radios, open by default
- 5 GHz channel 149 HE80 · 2.4 GHz channel 1 HE20
- 802.11k/v so clients move to the better radio
- NSS WiFi offload

### Phone (RJ11)
- Skyworks Si32261 SLIC DSP patch pre-installed
- PCM auto-checked and forced to slave mode
- Dial tone, ringing, DTMF, Caller ID, hold, speed dial, blocked numbers, call history
- Upstream `openwrt-aw1000-phone` **v0.4.1**

### Proxy
- **passwall2** pre-configured, Xray core
- DNS via chinadns-ng + nftset, transparent TCP/UDP

### Remote access
- **Tailscale** — reach the router from anywhere, no port forwarding. Starts only once
  credentials exist.

### System
- **Vantage** theme by default (Footstrap and Bootstrap also shipped)
- Modem info panel, AW1000 LED control, CPU frequency, traffic stats, web terminal
- BBR + `fq`, BDP-sized TCP buffers, zram swap, pinned CPU governor
- **Boot-time self-check** that verifies the tuning actually applied

### Install on demand

These are kept out of the image so it stays small, and install cleanly from the configured
feeds:

```sh
opkg update
opkg install luci-app-banip          # ad/blocklist filtering
opkg install luci-app-smartdns       # fast DNS resolver
opkg install luci-app-homeproxy      # sing-box proxy
opkg install luci-app-mwan3          # multi-WAN failover
opkg install luci-app-sqm            # traffic shaping
opkg install luci-app-openclash      # clash/mihomo
opkg install luci-app-adguardhome    # DNS + ad blocking (matching binary published by us)
opkg install luci-app-nikki          # mihomo
```

`luci-app-adguardhome` is the one app upstream feeds cannot supply on their own: the UI
needs a newer `adguardhome` than ImmortalWrt 24.10 carries, so the binary is published
alongside it.

---

## Changelog

Complete history, newest first. Every entry names the symptom it cures.

### 2026-10-26 — FINAL

**Cellular**

| Problem | Cause | Fix |
|---|---|---|
| No carrier, WAN dead, empty modem panel on some units | qmodem was hardcoded to USB slot `4-1`, but some modems enumerate on `3-1`. The scan found nothing at `4-1`, disabled the slot, and never dialed | Preset keeps `4-1` (the common case) and **USB auto-scan is enabled**, so a modem on another port is detected and dialed |
| Log spam `sh: invalid number '0x'`, blank LuCI modem page | Empty cell ID ran `printf "%d" "0x"`, which busybox aborts on | Hex conversion guarded; the optional leading `b` marker is stripped |
| Large transfers and calls stall, small packets pass | Cellular MTU was 1500, which an LTE/NR bearer cannot carry | Pinned to **1420**, re-applied on every redial |

**Package manager**

| Problem | Cause | Fix |
|---|---|---|
| `Signature check failed` for our feed | jsDelivr served a stale `Packages.sig` | Feed now points at **`raw.githubusercontent.com`** by default — no manual `sed` needed |
| `opkg update` fails, nothing installable | Signing key installed *after* the image was compiled | Key installed **before** the build |
| AdGuard Home uninstallable | UI needs a newer binary than upstream feeds carry | Binary published alongside the app |

**HTTP/3**

| | |
|---|---|
| **QUIC support** | `curl`/`libcurl` built with HTTP/3 (nghttp3 + ngtcp2 on OpenSSL). `curl --http3` works |

**Stability & speed**

| Fix | Detail |
|---|---|
| **Hourly stall removed** | A crontab entry ran `drop_caches` and `swapoff -a && swapon -a` every hour, forcing 433 MB of zram to decompress and re-compress. Removed; the kernel reclaims on its own. A CI guard blocks it from returning. |
| **Tuning is now verifiable** | `byte-selfcheck` logs the observed CPU governor, qdisc, MTU, RPS mask and sysctl values against what the image configures, then prints `PASS n checks` or `FAIL n mismatches`. Re-runs on every cellular ifup. |
| **Phone v0.4.1** | Newer upstream call handling and fixes, pinned to the release tag |
| **Defconfig no longer aborts** | The `packages` feed branch moved and added a `weechat-full`/`mihomo-alpha` variant cycle, breaking `make defconfig` before anything compiled. The non-default variants are removed at build time and a CI guard keeps them out |

### Earlier fixes

**Internet & connectivity**

| Problem | Cause | Fix |
|---|---|---|
| "Internet is fine but I can't browse" | Carrier hands out an IPv6 prefix without a routable address; clients prefer IPv6 and every connection hangs | IPv6 health check measures real connectivity and falls back to IPv4 only when IPv6 is genuinely unusable — restores automatically |
| Latency spikes after idle | A read-only kernel key aborted `sysctl -p` mid-file, so latency tuning never applied | Removed; all 33 remaining keys verified accepted |
| Device OOM-kills the proxy | zram configured for `lz4`, which this kernel lacks — silently shipped with zero swap | Switched to `lzo-rle`; 433 MB compressed swap now live |
| WAN page shows "no preset" | qmodem's `hang()` deletes the interface sections and the dial worker may never recreate them | `qmodem-iface-heal` recreates `wan`/`wanv6` on boot and on a timer |
| Single-core ceiling at ~500 Mbit/s | All modem interrupts landed on one CPU | `byte-affinity` spreads RPS/RFS/XPS across all four cores |
| Feed URLs 404 | Feed list hardcoded; enabled feeds drifted from published ones | Derived from `.config` — a feed can never be enabled without being published |
| Build not identifiable | `DISTRIB_REVISION` was a value shared by every build | Reports `FINAL` |

**Stability & maintenance**

| Fix | Detail |
|---|---|
| **RJ11 no longer stuck at "Waiting for the modem"** | The phone daemon talks AT through `ubus at-daemon`, which was missing entirely. Now shipped with correct boot ordering. |
| **SMS works from LuCI** | Added the SMS app, forwarding daemon and AT backend |
| **Tailscale self-heals** | Detects an empty `tailscale0` after boot and restarts the daemon; does not run at all until you have credentials |
| **Passwall v1 removed** | It and passwall2 fight over the same firewall rules — v1 was always torn down and appeared broken. Only passwall2 ships. |
| **qmodem WAN panel blank** | `override_at_port`/`sms_at_port` pointed at a port that blocks the RG500Q | Both unset; `at_port` uses the port that answers |
| **NSS ECM removed** | Cannot compile on kernel 6.12.112, and offload bypasses netfilter, defeating the TTL rewrite | Removed from the tree at build time |
| **CPU/RAM trim** | NSS acceleration took the load off the SoC | `-O2`, `sch_fq`, pinned max clock, fastboot |

**Size**

Removed ~45 MB of packages most users never touch — sing-box, AdGuard Home, hysteria,
naiveproxy, xray/v2ray plugins, OpenClash, ruby, haproxy, argon theme — and published them
to the self-hosted opkg repo instead, installable on demand.

---

## Technical reference

### Network defaults

| Interface | Device | Proto |
|---|---|---|
| `wan` | `wwan0_1` | `dhcp` |
| `wanv6` | `@wan` | `dhcpv6` — health-checked |
| `lan` | `br-lan` | `192.168.1.1/24` |

### qmodem

```
at_port    /dev/ttyUSB3     # the port that answers on this modem
use_ubus   0                # no ubus at-daemon in the 2.8.x line
apn        auto             # works on any carrier
pdp_type   ipv4v6
enable_usb_scan 1           # dial whatever port the modem actually lands on
```

`override_at_port` and `sms_at_port` are deliberately unset — pointing them at
`/dev/ttyUSB2` makes `tom_modem` block forever on the RG500Q, which appears as an empty
modem panel and "Disconnected" while the link is actually up.

### Custom services

| Service | Problem it solves |
|---|---|
| `byte-ttl` | Writes the correct `forward`-hook rule matching `oifname wwan0_1`, re-applies at boot |
| `byte-mtu` | Pins the cellular MTU to 1420, re-applied on every netifd `ifup` |
| `byte-v6` | Measures real IPv6 connectivity before demoting to IPv4 |
| `byte-selfcheck` | Verifies governor, qdisc, MTU, RPS and sysctl took effect; re-runs on ifup |
| `qmodem-iface-heal` | Recreates `wan`/`wanv6` when qmodem's `hang()` deletes them |
| `byte-affinity` | RPS/RFS/XPS across all four cores for modem traffic |
| `byte-tailscale-gate` | Starts `tailscaled` only when credentials exist |

### Tuning

Declared in `files/etc/sysctl.conf`, `files/etc/config/cpufreq` and the `byte-*` services:

- Congestion control **BBR** over **`fq`** (pacing, lower latency under load)
- Socket buffers sized to the link's bandwidth-delay product (4 MB cap)
- `tcp_slow_start_after_idle=0`, keepalive 120/15/4, `netdev_budget=600`
- CPU governor **`performance`**, min = max, so the first packet after idle is not delayed
- MTU 1420 on `wwan0`/`wwan0_1`, re-applied on every redial
- zram swap, `lzo-rle`, 433 MB

**Known ceiling:** the modem's USB interrupt (`xhci-hcd:usb3`) is not spread across
cores — writes to its IRQ affinity make the kernel collapse it back to one CPU, so
`byte-affinity` leaves it alone and distributes packet *processing* with RPS instead.
The interrupt itself stays on a single core. XPS is written but rejected by
`qmi_wwan`; `byte-affinity` probes this once at boot and logs `xps=unsupported`.

---

## Troubleshooting

### `opkg update` reports a signature failure

The image points the feed at `raw.githubusercontent.com` directly, so this should not
happen. If it does, force a clean refresh:

```sh
sed -i 's|https://cdn.jsdelivr.net/gh/Ace1337z/AW1000_BYTE@repo|https://raw.githubusercontent.com/Ace1337z/AW1000_BYTE/repo|g' /etc/opkg/distfeeds.conf
rm -rf /var/opkg-lists
opkg update
```

Success looks like `Signature check passed` for every feed and `Signature check failed`
nowhere. Only then will `opkg install` work.

### Modem does not dial

```sh
logread | grep -i qmodem
uci show qmodem | grep slot
```

The self-check and qmodem both log the slot they found. If the modem sits on a different
USB port, `enable_usb_scan` should pick it up within ~15 s of boot.

### Did the tuning apply?

```sh
logread -e byte-selfcheck
```

Prints one line per check and a final `PASS n checks` or `FAIL n mismatches`.

---

## Credits

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) — base distribution
- [FUjr/QModem](https://github.com/FUjr/QModem) — modem management
- [Perz3us/openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone) — RJ11 driver
- [qosmio/nss-packages](https://github.com/qosmio/nss-packages) — NSS packages
- [Openwrt-Passwall](https://github.com/Openwrt-Passwall) — passwall2
- [nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — nikki
- [dotywrt/dotycat-package](https://github.com/dotywrt/dotycat-package) — AW1000 LED control
- [anothaDev/luci-theme-vantage](https://github.com/anothaDev/luci-theme-vantage) — theme
- [SolomonRicky/luci-app-modeminfo](https://github.com/Ace1337z/luci-app-modeminfo) — modem info

### Licensing

- **Skyworks ProSLIC DSP patch** — proprietary, not redistributable.
- **QCA NSS driver and firmware** (QSDK 12.5) — Qualcomm licence applies.

Review both before republishing any image built from this repository.

<details>
<summary>Screenshots</summary>

![Vantage dashboard, light](docs/screenshots/dashboard-light.png)

</details>

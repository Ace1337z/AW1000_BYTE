# BYTE for the Arcadyan AW1000

Custom firmware for the Arcadyan AW1000 (`ipq807x`), built from ImmortalWrt 25.12.1
(kernel 6.12.94) with Quectel QMI and NSS acceleration. Cellular, WiFi, RJ11 phone,
SMS, TTL handling, proxy and remote access work on a clean flash.

[![release](https://img.shields.io/github/v/release/Ace1337z/AW1000_BYTE?style=flat-square&label=release&color=00B5E2)](../../releases/latest)
[![kernel](https://img.shields.io/badge/kernel-6.12.94-8e7cc3?style=flat-square)](#)
[![target](https://img.shields.io/badge/target-ipq807x%2Faw1000-5a6472?style=flat-square)](https://openwrt.org/toh/arcadyan/aw1000)

![Dashboard](docs/screenshots/dashboard.png)
<sub>Dashboard: modem signal, temperatures, NSS offload. Screenshot from
[XT-Martinez/aw1000-feed](https://github.com/XT-Martinez/aw1000-feed), whose widgets this image ports.</sub>

## Quick start

| | |
|---|---|
| **Download** | [Latest release](../../releases/latest) — `BYTE_by_ACE-<version>-qualcommax-ipq807x-arcadyan_aw1000-*` |
| **Web UI** | <http://192.168.1.1> |
| **Login** | `root`, no password |
| **WiFi** | `BYTE` on 2.4 + 5 GHz, open |
| **SIM** | insert, boot, APN negotiates itself |

**Set a root password and a WiFi key right after flashing.** Both ship open so a
fresh unit is reachable without a sticker.

### Flash

```sh
sha256sum -c sha256sums
sysupgrade -n BYTE_by_ACE-<version>-qualcommax-ipq807x-arcadyan_aw1000-squashfs-sysupgrade.bin
```

- `-n` discards `/etc/config`. Use it when coming from another firmware.
- First install or bricked unit: `...-squashfs-factory.ubi` from U-Boot/TFTP.
- Non-destructive test: boot `...-initramfs-uImage.itb` straight into RAM first.

> Keep a recovery path before flashing anything: serial console or the
> initramfs image under TFTP. `sysupgrade` preserves config, `-n` does not.

## What you get

**Cellular** — QModem 3.3.0, Quectel vendor QMI, band/cell lock, SMS (send,
receive, forward to Telegram/webhook), signal and CA metrics, live dashboard.
**TTL / Hop Limit** — one switch in *Network → Modem → TTL Configuration*;
rule matches `oifname "wwan*"`, so forwarded **and** router-originated traffic is
rewritten. The same switch drives offload: TTL on → `flow_offloading=1`, TTL off → `0`.
**Phone (RJ11)** — `fxsd` + SLIC driver built in, HD audio, caller ID, DND, history.
**WiFi** — NSS-accelerated 2.4/5 GHz, both radios up on first boot.
**UI** — Footstrap theme, BYTE logo/icons, BYTE panel (AdGuard Home wiring, DNS
chain, system strip, shortcuts), JS modem-info view, dashboard widgets, Netstat
with persistent vnStat history.
**Proxy** — PassWall2 with Xray; first-run rules in place.
**Remote** — Tailscale installs on demand, starts only with credentials.
**Tuning** — BBR + `fq`, BDP-sized buffers, zram, `performance` governor, packet
steering, RPS/RFS/XPS, larger NAPI budget, TFO. A boot-time self-check logs
whether each value actually applied.

Install more from the published opkg repo (kept out of the image to save space):

```sh
opkg update
opkg install luci-app-banip luci-app-smartdns luci-app-mwan3 luci-app-sqm
opkg install luci-app-openclash luci-app-adguardhome luci-app-nikki
opkg install tailscale luci-app-tailscale-community
```

## Firmware version

Status → Overview reads, and every image filename carries, the same string:

```
BYTE 25.12(6.12.94) 1.2.5
     │      │        └── patch: commits since FW_BASE (version.env) — bumps every commit
     │      └─────────── kernel: KERNEL_PATCHVER → target/linux/generic/kernel-6.12
     └────────────────── release series
```

`version.env` holds `FW_MAJOR`/`FW_MINOR`/`FW_BASE`/`FW_PATCH_FALLBACK`; the patch is
`git rev-list --count FW_BASE..HEAD`, so there is no manual bump. The build aborts if
the kernel cannot be resolved rather than shipping `25.12(x)`.

## Build

CI builds on every push to `main` that touches `preset`, `aw1000_byte.sh`,
`version.env`, `files/`, `packages/` or the workflow, and on manual dispatch
(Actions → *Build BYTE by ACE firmware (AW1000)*, input `branch`, default `v25.12.1`).

Locally, on Debian/Ubuntu:

```sh
git clone https://github.com/Ace1337z/AW1000_BYTE.git && cd AW1000_BYTE
bash aw1000_byte.sh          # interactive menu; CI=1 SKIP_MENUCONFIG=1 for unattended
```

The script clones ImmortalWrt at the pinned tag, adds the qmodem/passwall2/NSS/phone
feeds, applies `preset` as `.config`, derives the version, and builds. `files/` is
applied as a custom overlay *after* packages, so theme, logo and view overrides win.

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

- **Offload vs TTL.** With `flow_offloading=1`, a flow is accelerated after its first
  packet, so later packets skip the mangle chain and keep the sender's TTL. Clients
  that send 64 look right; Windows hosts (128) leak 128 for that flow's life.
  Router-originated traffic and every flow's first packet are always rewritten.
- **ECM is not shipped.** `kmod-qca-nss-ecm` is unset: its 12.5 build targets the 6.12.9x
  series and it would defeat the TTL rewrite. The `48_nss` widget therefore stays
  dormant (no debugfs counter). NSS data-path acceleration is unaffected.
- **NSS offload is software-only for TTL paths.** `flow_offloading_hw` stays `0`;
  `nss-dp` does not implement it.

## Credits

ImmortalWrt, OpenWrt, [qosmio/nss-packages](https://github.com/qosmio/nss-packages),
[XT-Martinez/aw1000-feed](https://github.com/XT-Martinez/aw1000-feed) (dashboard widgets),
[Perz3us/openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone),
QModem, [Openwrt-Passwall](https://github.com/Openwrt-Passwall),
[nikkinikki/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki),
[dotywrt/dotycat-package](https://github.com/dotywrt/dotycat-package) (LEDs),
[NoobLK/luci-app-netstat](https://github.com/Ace1337z/luci-app-netstat),
[SolomonRicky/luci-app-modeminfo](https://github.com/Ace1337z/luci-app-modeminfo).

**Licensing.** The Skyworks ProSLIC DSP patch is proprietary and not redistributable;
QCA NSS driver and firmware carry the Qualcomm licence. Review both before
republishing an image built here.

## Changelog

### 1.2.x — 2026-11-02
- Version string `BYTE 25.12(KERNEL) PATCH` in Status and in every filename, derived
  from the commit count; kernel read from the target, not the SDK placeholder.
- TTL switch now owns offload (`1` on, `0` off, hw always `0`); rule matches both
  forwarded and router-originated egress; self-check asserts the pairing.
- Fixed the theme: the luci feed pin predated Footstrap, so `defconfig` silently
  dropped it and the image shipped Bootstrap — the BYTE branding had nothing to apply to.
- Fixed CI: signing key is installed by the build script after the clone (the old
  pre-clone step failed every cold-cache run), and scripts that must be executable are.
- Modem info rewritten as a JS view over an rpcd plugin: on-demand AT sampling with
  `flock` and atomic publish, no cron, no daemon, no external badges.
- QModem 2.8.9 → 3.3.0, phone 0.4.1 → 0.7.0, netstat vendored against `vnstat2`,
  vnStat history moved to overlay, Vantage removed.

### Earlier
- 2026-10-26 `FINAL`: tuning baseline, Tailscale on demand, dashboard port,
  AdGuard Home wiring, first opkg repo.
- See `git log` for the full history.

# BYTE by ACE — Arcadyan AW1000 Firmware

[![Final release](https://img.shields.io/badge/release-FINAL%2025.12-00B5E2?style=for-the-badge)](../../releases/latest)
[![Platform](https://img.shields.io/badge/AW1000-ipq807x-5a6472?style=for-the-badge)](https://openwrt.org/toh/arcadyan/aw1000)
[![Base](https://img.shields.io/badge/ImmortalWrt-25.12-3d8b40?style=for-the-badge)](https://github.com/immortalwrt/immortalwrt)
[![Kernel](https://img.shields.io/badge/kernel-6.12.112-8e7cc3?style=for-the-badge)](#)

**BYTE by ACE** is a production-oriented firmware for the **Arcadyan AW1000**
(`qualcommax/ipq807x`). It is built on ImmortalWrt 25.12 with the Quectel vendor
QMI stack and the QCA NSS driver/datapath, and is delivered with working
cellular, WiFi, RJ11 telephony, SMS, TTL normalisation, transparent proxy and
remote-access defaults.

This repository is **final and retired**. The `main` branch now contains this
document and the dashboard screenshots only. The `repo` branch remains online
as the signed opkg feed used by the firmware. No further firmware, package or
source updates will be published.

![BYTE by ACE — Vantage dashboard](docs/screenshots/dashboard-dark.png)

<sub>LuCI dashboard with the Vantage theme: system, memory, mobile, storage, CPU,
temperature and WAN status at a glance.</sub>

---

## Final release

| | |
|---|---|
| **Version** | `BYTE by ACE 25.12 FINAL` |
| **Target** | `qualcommax/ipq807x` — Arcadyan AW1000 |
| **Kernel** | 6.12.112 |
| **Image** | `BYTE_by_ACE_FINAL_25_12_qualcommax_ipq807x_arcadyan_aw1000_squashfs.bin` |
| **SHA-256** | `e13f93027d04d30d1fdf55b42f1bc54325c2d88d0b0ab8dc1ffc5210713f5292` |
| **Format** | sysupgrade archive (`BOARD=arcadyan_aw1000`) |
| **Status** | Final stable release; no further updates |

The final release publishes the **sysupgrade image only**. It does not include a
factory `.ubi` image or an initramfs recovery image. Confirm that the device is
already running an OpenWrt-compatible firmware and that a recovery path is
available before flashing.

---

## Quick start

| | |
|---|---|
| **Download** | [Latest release](../../releases/latest) |
| **Web UI** | <http://192.168.1.1> |
| **Login** | `root`, no password |
| **WiFi** | SSID `BYTE` on 2.4 GHz and 5 GHz — open, no password |
| **SIM** | Insert and boot; the APN is negotiated automatically |

> **Set a root password and a WiFi key immediately after flashing.** Both ship
> open so that a fresh installation is reachable without a sticker. Leaving
> either open exposes the router to anyone within radio or LAN range.

---

## Installation

### Before flashing

1. Keep **serial console access** or a known-good **U-Boot/TFTP recovery path**
   available. An interrupted flash can leave the device unbootable.
2. Back up the current configuration:
   ```sh
   sysupgrade -b /tmp/backup-$(date +%F).tar.gz
   ```
3. Verify the downloaded image:
   ```sh
   sha256sum BYTE_by_ACE_FINAL_25_12_qualcommax_ipq807x_arcadyan_aw1000_squashfs.bin
   ```
   The result must equal the SHA-256 listed above.

### Flash

```sh
cd /tmp
sysupgrade -n /tmp/BYTE_by_ACE_FINAL_25_12_qualcommax_ipq807x_arcadyan_aw1000_squashfs.bin
```

`-n` discards `/etc/config`. Use it when coming from another firmware, or when
a clean configuration is required. Omit `-n` to preserve settings when
upgrading an existing BYTE by ACE installation.

Do not power off the device during the write or the first reboot.

### Verify after boot

```sh
cat /etc/openwrt_release
ubus call system board
logread -e byte-selfcheck
opkg update
```

Expected results:

- `DISTRIB_DESCRIPTION='BYTE by ACE 25.12 FINAL'`
- board `arcadyan_aw1000`, target `qualcommax/ipq807x`
- `byte-selfcheck` reports `PASS n checks`
- `opkg update` reports `Signature check passed` for every feed

---

## Recovery

The final release does not ship a factory or initramfs recovery image. Recovery
depends on the bootloader and on the recovery media prepared **before** flashing.

Recommended preparation:

- Serial console at **115200 8N1**.
- A known-good factory image and TFTP server reachable by U-Boot.
- The AW1000 U-Boot/TFTP recovery procedure for the installed bootloader.
- A copy of the current configuration backup outside the router.

If the device fails to boot after `sysupgrade`:

1. Do not repeatedly power-cycle the device.
2. Connect the serial console and capture the boot log.
3. Interrupt U-Boot and enter the board's TFTP recovery mode.
4. Flash the appropriate factory image, then restore the configuration backup
   only after the device boots successfully.

Do not guess flash offsets, partition sizes or U-Boot environment values. Use
the board documentation and the bootloader's own recovery commands.

---

## Features

### Cellular

- **qmodem 2.8.9** with the Quectel vendor QMI driver (`qmi_wwan_q`)
- Automatic dial on boot; **APN `auto`** negotiated from the SIM
- **USB port auto-scan**, so a modem that enumerates on a port other than the
  preset slot is detected and dialled
- Dual-stack IPv4/IPv6 with live signal, band, temperature and voltage in LuCI
- **TTL 64 and Hop Limit 64** on modem egress only
- **MTU 1420** on the cellular interface, re-applied on every redial
- SMS send, receive and forwarding through LuCI

### WiFi

- QCA NSS accelerated 2.4 GHz and 5 GHz radios
- SSID `BYTE` on both bands, open by default
- 5 GHz: channel 149, HE80 · 2.4 GHz: channel 1, HE20
- 802.11k/v assisted roaming
- Both radios enabled on first boot

### RJ11 telephony

- **fxsd 0.4.1** with the Skyworks Si3226x SLIC patch pre-installed
- Dial tone, ringing, DTMF, Caller ID, hold, speed dial, blocked numbers and
  call history
- PCM link checked and forced to slave mode at boot

### Proxy and DNS

- **PassWall2 26.4.10** with Xray core, pre-configured
- Transparent TCP/UDP redirection
- DNS through **chinadns-ng** and nftsets
- PassWall2 is the only transparent-proxy stack in the image; do not install a
  second stack that competes for port 53 and the same nftables hooks

### Remote access and management

- **Tailscale 1.104.1**; the daemon starts only after credentials exist
- LuCI web interface with the Vantage theme
- Modem information, AW1000 LED control, CPU frequency, traffic statistics,
  file manager and web terminal
- Persistent vnStat2 traffic history

### Performance and stability

- **BBR** congestion control over **`fq`** pacing
- Socket buffers sized to the cellular bandwidth-delay product
- zram swap, `lzo-rle`, 433 MB
- CPU governor pinned to **`performance`** at 2.208 GHz
- Modem interrupts and RPS/RFS spread across all four CPU cores
- Boot-time **`byte-selfcheck`** verifies that governor, qdisc, MTU, RPS and
  sysctl tuning actually applied, then reports `PASS` or `FAIL`

### Package feed

The signed opkg feed remains available from the `repo` branch:

```sh
opkg update
```

The image points its feeds at:

```
https://raw.githubusercontent.com/Ace1337z/AW1000_BYTE/repo
```

Additional packages can be installed on demand, including:

```sh
opkg install luci-app-adguardhome
opkg install luci-app-nikki
```

Available feed content includes AdGuard Home, nikki/mihomo, qmodem QMI drivers,
LuCI dependencies and the AW1000 phone packages. The feed is static: it
will not receive new package versions.

---

## Default configuration

| Setting | Value |
|---|---|
| LAN | `192.168.1.1/24`, bridge `br-lan` |
| WAN | `wwan0_1`, DHCP, modem preset `4_1` |
| WAN IPv6 | `wanv6`, DHCPv6, health-checked |
| WiFi | `BYTE`, open, 2.4 GHz + 5 GHz |
| Hostname | `BYTE_by_ACE` |
| Time zone | `Asia/Kuala_Lumpur` |
| Root login | `root`, no password |

The physical `wan` port is bridged into `br-lan`. IGMP snooping and the
multicast querier are enabled for IPTV, with a larger multicast hash table to
avoid silent flooding.

---

## Technical notes

### qmodem

```
at_port          /dev/ttyUSB3
use_ubus         0
apn              auto
pdp_type         ipv4v6
enable_usb_scan  1
```

`override_at_port` and `sms_at_port` are intentionally unset. Pointing them at
the wrong port can block `tom_modem` and produce an empty modem panel even when
the link is up.

### Custom services

| Service | Purpose |
|---|---|
| `byte-ttl` | Rewrites TTL/Hop Limit on modem egress |
| `byte-mtu` | Pins cellular MTU to 1420 and re-applies it on `ifup` |
| `byte-v6` | Measures IPv6 connectivity and falls back to IPv4 only when IPv6 is unusable |
| `byte-selfcheck` | Verifies governor, qdisc, MTU, RPS and sysctl values |
| `qmodem-iface-heal` | Recreates `wan`/`wanv6` if qmodem removes them |
| `byte-affinity` | Distributes modem RPS/RFS/XPS across all four cores |
| `byte-tailscale-gate` | Starts `tailscaled` only when credentials exist |

### Tuning

Declared in `/etc/sysctl.conf`, `/etc/config/cpufreq` and the `byte-*` services:

- `bbr` with `fq`
- socket buffers capped at 4 MB
- `tcp_slow_start_after_idle=0`
- keepalive 120/15/4
- CPU governor `performance`, minimum = maximum
- MTU 1420 on `wwan0` and `wwan0_1`
- zram swap, `lzo-rle`

Software flow offload is intentionally disabled. It would bypass the mangle
chain after the first packet of a flow and allow client TTL values to leak to
the carrier. Router-originated traffic and every flow's first packet are still
rewritten.

### Known limitations

- The final release provides no factory image and no initramfs image.
- The opkg feed is frozen; package versions will not be updated.
- Flow offload must remain disabled while TTL normalisation is required.
- NSS acceleration covers the WiFi/datapath path; it does not bypass netfilter
  for the modem uplink.
- Hardware flow offload is not supported by this datapath and must remain off.
- IPv6 is probed at bring-up and demoted only while connectivity is genuinely
  broken; it restores itself when the carrier starts passing IPv6 traffic.

---

## Troubleshooting

### `opkg update` reports a signature failure

The image points directly at `raw.githubusercontent.com`. Force a clean refresh:

```sh
sed -i 's|https://cdn.jsdelivr.net/gh/Ace1337z/AW1000_BYTE@repo|https://raw.githubusercontent.com/Ace1337z/AW1000_BYTE/repo|g' /etc/opkg/distfeeds.conf
rm -rf /var/opkg-lists
opkg update
```

Success looks like `Signature check passed` for every feed and no
`Signature check failed` messages.

### Modem does not dial

```sh
logread | grep -i qmodem
uci show qmodem | grep slot
```

The self-check and qmodem both log the USB slot they found. If the modem is on
a different port, `enable_usb_scan` should detect it within roughly 15 seconds
of boot.

### Tuning did not apply

```sh
logread -e byte-selfcheck
```

The service prints one line per check and a final `PASS n checks` or
`FAIL n mismatches`.

### No internet, but the modem link is up

Check the MTU and IPv6 state:

```sh
ip -4 addr show wwan0_1
ip -6 addr show wanv6
ip link show wwan0_1
logread -e byte-mtu
logread -e byte-v6
```

---

## Repository status

| Branch | Contents |
|---|---|
| `main` | This README and the dashboard screenshots |
| `repo` | Signed opkg feed used by the firmware |

The source tree, build scripts, CI workflows, kernel patches and package
sources have been removed. Old releases have been withdrawn. This is the final
stable firmware; no pull requests, builds or updates are planned.

---

## Credits

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) — base distribution
- [FUjr/QModem](https://github.com/FUjr/QModem) — modem management
- [Perz3us/openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone) — RJ11 driver
- [qosmio/nss-packages](https://github.com/qosmio/nss-packages) — NSS packages
- [Openwrt-Passwall](https://github.com/Openwrt-Passwall) — PassWall2
- [nikkinikki-org/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki) — nikki
- [dotywrt/dotycat-package](https://github.com/dotywrt/dotycat-package) — AW1000 LED control
- [anothaDev/luci-theme-vantage](https://github.com/anothaDev/luci-theme-vantage) — theme
- [Ace1337z/luci-app-modeminfo](https://github.com/Ace1337z/luci-app-modeminfo) — modem information

### Licensing

- **Skyworks ProSLIC DSP patch** — proprietary; not redistributable.
- **QCA NSS driver and firmware** (QSDK 12.5) — Qualcomm licence applies.

Review both before republishing an image built from this repository's former
source tree.

<details>
<summary>Dashboard — light theme</summary>

![BYTE by ACE — Vantage dashboard, light theme](docs/screenshots/dashboard-light.png)

</details>

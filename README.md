# AW1000 BYTE

**BYTE by ACE** — a beginner-friendly, feature-rich OpenWrt (ImmortalWrt) firmware
for the **Arcadyan AW1000** (`qualcommax/ipq807x`). Fully pre-configured: flash and
it just works — WiFi, cellular modem auto-dial, NSS hardware offload, the RJ11
phone port, and a full proxy suite.

---

## Highlights

- **Brand:** `BYTE by ACE` (LuCI, terminal banner, release names)
- **Target:** Arcadyan AW1000, `qualcommax/ipq807x`, ImmortalWrt `openwrt-25.12`, kernel 6.12
- **WiFi:** SSID `BYTE` on both 2.4 GHz and 5 GHz — **no password** (open by default)
- **Cellular:** qmodem with Quectel vendor QMI driver — auto-dials the SIM on boot
- **Phone port:** RJ11 SLIC DSP patch **pre-shipped** — the desk-phone port works out of the box
- **NSS hardware offload:** QSDK 12.5 (`qca-nss-drv` + `qca-nss-ecm`, firmware 12.5)
- **TTL:** configurable via LuCI (Tools → TTL Config), default **64** on both IPv4/IPv6
- **Speed:** BBR congestion control, CPU `performance` governor, large TCP buffers
- **Package manager:** opkg / ipk (`CONFIG_USE_APK` off)

---

## Default WiFi

| Band | SSID | Encryption |
|------|------|------------|
| 2.4 GHz | `BYTE` | none (open) |
| 5 GHz | `BYTE` | none (open) |

> **Note:** an open network. Set a password in LuCI (Network → Wireless) once connected.

---

## What's inside

### Modem & cellular (`qmodem`)
- Auto-dial on boot (`enable_dial 1`, `state enabled`), SIM PIN/APN configurable
- Quectel `rg500q-ea` profile: **auto APN** (auto-negotiated from the SIM/carrier — works
  on any telco, not Telstra-specific), `pdp ipv4v6`, QMI data interface
- `luci-app-qmodem-next` — live signal/registration/bands, AT console, SMS
- Vendor QMI drivers (`qmodem_INCLUDE_vendor-qmi-wwan`), NSS-compatible
- `net.dial*` interface: `wan` on `wwan0_1` (dhcp), `wanv6` (dhcpv6)

### RJ11 phone port (`kmod-aw1000-fxs` + `fxsd` + `luci-app-fxs`)
- Skyworks Si32261 SLIC DSP patch **shipped** at `/etc/fxs/si3226x_patch.bin`
  (patch ID `0x05262017`, `si3226x_patch_C_FB_2017MAY26`)
- `fxsd` enabled on first boot; modem PCM set to slave (`AT+QDAI`) automatically
- Incoming/outgoing calls, dial tone, ringing, DTMF, Caller ID (Bellcore/ETSI/DTMF)

### NSS hardware offload & TTL
- Wired NAT/bridge forwarding can run on the two NSS cores (QSDK 12.5)
- **TTL vs offload:** NSS cannot rewrite TTL (its rule struct has no TTL field)
  and offload bypasses netfilter — so they are mutually exclusive on the same
  flow. TTL is prioritised by default; flip with `nss-offload on|off|status`.
- TTL value configurable: LuCI → **Tools → TTL Config** (`luci-app-nft-ttl`)

### Proxy & ad-blocking
- `passwall`, `passwall2`, `openclash` (TPROXY, local socket)
- `adguardhome` + LuCI app
- Cores: `xray-core`, `sing-box`, `hysteria`, `naiveproxy`,
  `shadowsocks-rust`, `v2ray-plugin`, `xray-plugin`
- `xray` binary is the `xray-stdstrx` 26.2.6 aarch64 static build

### System
- `luci-app-ramfree` (release RAM), `luci-app-cpufreq` (performance governor)
- `luci-app-vantage` + `luci-theme-vantage` (default theme), `luci-theme-footstrap`
- `luci-app-vnstat2`, `luci-app-ttyd`, `luci-app-package-manager`
- ZRAM swap (lz4, 433 MB), TTL 64, BBR, large conntrack/buffers
- `luci-app-aw1k-led` — LED controller for the AW1000 (power/5G/signal/wifi/internet/phone)
- `luci-app-modeminfo` — modem information dashboard

### Storage & USB
- ext4, exfat, NTFS3, vfat filesystems; USB 3.0 (DWC3 + QCOM), storage + SCSI
- `block-mount`, `automount`

---

## Build (GitHub Actions)

The `.github/workflows/build.yml` workflow builds the firmware on GitHub Actions and
publishes a release (`BYTE_by_ACE-<branch>-<build>`).

Trigger manually: **Actions → Build BYTE by ACE firmware (AW1000) → Run workflow**,
or push to `main` (paths: `preset`, `aw1000_byte.sh`, `files/**`,
`.github/workflows/build.yml`).

---

## Build locally (Ubuntu 22.04+)

```bash
git clone https://github.com/Ace1337z/AW1000_BYTE.git
cd AW1000_BYTE
bash aw1000_byte.sh
```

Use the menu to select the target branch (`openwrt-25.12`) and start the build.
Output lands in `immortalwrt/bin/targets/qualcommax/ipq807x/`.

> The script clones ImmortalWrt with `--no-single-branch` so the release branch is
> fetched; it applies the `files/` overlay, the `nss/` kernel patches, and the
> `packages/` local feed, then runs `make defconfig` and builds.

---

## Structure

```
AW1000_BYTE/
├── aw1000_byte.sh          # build entrypoint (menu + build orchestration)
├── preset                  # full .config used by the build
├── files/                  # rootfs overlay (configs, banner, scripts, patch)
│   ├── etc/config/         # network, firewall, wireless, qmodem, fxs, nftttl, 5g-led
│   ├── etc/fxs/            # si3226x_patch.bin (shipped SLIC DSP patch)
│   ├── etc/nftables.d/     # TTL nft rules
│   ├── etc/uci-defaults/   # first-boot setup (enable fxsd, PCM slave, etc.)
│   └── usr/bin/            # nss-offload, xray (stdstrx 26.2.6)
├── packages/               # local vendored feed (luci-app-modeminfo)
├── nss/                    # NSS kernel patches + AW1000 DTS (copied into tree)
└── .github/workflows/      # CI build + release
```

---

## Notes & caveats

- **NSS vs TTL** is a hard tradeoff on this device (all internet goes through the
  modem): see the README section above. Default is TTL-priority; use
  `nss-offload on` for max speed when TTL is not needed.
- The Skyworks ProSLIC DSP patch is **not redistributable** — review the ProSLIC
  licence before redistributing images built from this repo.
- `fxsd` needs the modem PCM in slave mode; the first-boot script sets it. If you
  reflash a modem later, re-run that command (or use the LuCI phone page).
- QSDK NSS driver/firmware blobs are from the QCA SDK release; review the Qualcomm
  licence before redistributing.

---

## Credits

- [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) — base distro
- [Perz3us/openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone) — RJ11 phone driver
- [FUjr/QModem](https://github.com/FUjr/QModem) — cellular modem management
- [qosmio/nss-packages](https://github.com/qosmio/nss-packages) — NSS offload packages
- [dotywrt/dotycat-package](https://github.com/dotywrt/dotycat-package) — aw1k-led
- [BootLoopLover/xray-stdstrx](https://github.com/BootLoopLover/xray-stdstrx) — xray binary
- [SolomonRicky/luci-app-modeminfo](https://github.com/Ace1337z/luci-app-modeminfo) — modeminfo
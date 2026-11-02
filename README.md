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
  traffic is rewritten. It runs **while NSS/ECM is accelerating**: the modem
  data netdevs are excluded from acceleration inside ECM itself (patch `0027`),
  so WAN packets always reach netfilter. FW4 flow offload is still held at `0`
  (hardware `0`) in both switch states, because the software flowtable skips
  the mangle chain too.
- **Phone (RJ11)** — `fxsd` with the SLIC driver built in: HD audio, caller ID,
  DND, call history.
- **WiFi** — NSS-accelerated 2.4/5 GHz; both radios up on first boot.
- **UI** — Footstrap 0.14.19, BYTE logo and icons, a BYTE panel (AdGuard Home ↔
  PassWall2 DNS wiring, system strip, shortcuts), a JS modem-info view, dashboard
  widgets and Netstat backed by persistent vnStat history.
- **Dashboard widgets** — Mobile (status card, signal chart, traffic chart,
  detail tab), Temperature, and NSS offload. The NSS widget is live:
  `qca-nss-ecm` ships and stays loaded.
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
- **Hardware offload has a narrow meaning here.** ECM accelerates bridge,
  LAN↔WiFi and local flows in the NSS cores. It does **not** accelerate the
  modem uplink — that is deliberate, and it is what keeps the TTL rewrite
  authoritative. Peak WAN throughput therefore comes from the CPU path plus
  NSS driver queues, not from a flow-offload shortcut.
- **No hardware flow offload.** `flow_offloading_hw` stays `0` — `nss-dp` does
  not implement it, so fw4 would accept a `1` and silently ignore it.

## Engineering log

Running record of the NSS/ECM work. Two policies drive everything here:

1. **NSS always on.** `qca-nss-ecm` is loaded and accelerating regardless of the
   TTL switch. No service stops it, no LuCI toggle parks it.
2. **TTL always wins.** No packet leaves the modem with a TTL the carrier can
   fingerprint — neither forwarded LAN/WiFi traffic nor traffic the router
   originates itself.

### Why this needed source changes

ECM's whole point is to move established flows into the NSS engine, which runs
*below* netfilter. A netfilter `ttl set` rule cannot see an offloaded packet.
The old workarounds were both bad: park ECM while TTL is on (loses all LAN
offload, and the switch becomes a speed toggle), or accept the leak (fails
tethering detection).

The chosen route keeps both: **accelerate everything except the modem egress.**

### Patch `0027` — modem egress excluded from acceleration

`nss/feeds/nss/qca-nss-ecm/patches/0027-ecm-interface-exclude-modem-egress-from-acceleration.patch`

In `ecm_interface_establish_and_ref()`, right after the netdev fields are read,
a `wwan*` / `rmnet*` device is registered through
`ecm_interface_unknown_interface_establish()` with `ae_interface_num = -1`.

- ECM still tracks the connection, so the LAN side classifies normally.
- The NSS front end rejects rule creation for any interface whose accelerator
  id is negative (`ecm_nss_non_ported_ipv4.c`, `from_nss_iface_id < 0 ||
  to_nss_iface_id < 0`), so those flows stay on the host stack.
- Bridge, LAN↔WiFi and local flows are untouched and still accelerated.

Generated against ECM `30fbfa4` (the exact `PKG_SOURCE_VERSION` the feed pins)
and validated on a tree with every feed patch `0001`–`0025` applied: hunks land
at offset 14, clean.

### Bonding front end is compiled out

The package forces `ECM_INTERFACE_BOND_ENABLE=y` whenever `kmod-bonding` is
selected. `ecm_bond_notifier.c` uses `struct bond_cb` and `bond_register_cb()`,
which are QSDK kernel additions — they do not exist in mainline
`v6.12.74`/`v6.12.94`/`v6.12.112` (zero hits in `gregkh/linux`, no declaration
in `include/net/bonding.h` or `netdevice.h`). Enabling it breaks every mainline
build.

`apply_preset()` therefore deletes the `+PACKAGE_kmod-bonding:kmod-bonding`
dependency line and every `ECM_INTERFACE_BOND_ENABLE` line from the package
Makefile, then hard-fails if anything survives. The source Makefile drops
`ecm_bond_notifier.o` on its own; only three externs remain in
`ecm_front_end_common.h`, which is fine. No AW1000 configuration has a bond
device.

### DSCPREMARK conntrack extension

ECM's `KCONFIG:=CONFIG_NF_CONNTRACK_DSCPREMARK_EXT=y` means the kernel must
provide that extension. Patch
`nss/target/linux/qualcommax/patches-6.12/0600-6-qca-nss-ecm-support-netfilter-DSCPREMARK.patch`
restores it, with its Kconfig entry changed from `depends on NETFILTER_ADVANCED`
to `default y`. The generic `config-6.12` leaves that symbol unset, but
`kmod-nf-conntrack` forces `CONFIG_NETFILTER_ADVANCED=y` through its own
`KCONFIG`, so the original dependency would in fact resolve. It is still
removed: an extension ECM links against should not depend on menu visibility
chosen by another package.

`KCONFIG` in a kmod package is written to `$(LINUX_DIR)/.config.override`, not to
the top-level `.config`, so CI cannot grep `.config` for the symbol. It asserts
the wiring instead: the package still carries
`KCONFIG:=CONFIG_NF_CONNTRACK_DSCPREMARK_EXT=y`, and the patch still has
`default y`.

The patch also touches `net/netfilter/xt_DSCP.c`: the DSCP target flags the
connection so ECM can carry the mark into accelerated flows. That makes
`xt_DSCP.ko` import `nf_conntrack.ko`, and `package/kernel`'s ELF dependency
checker aborts the whole build when a module's import has no declared provider
(`Package kmod-ipt-ipopt is missing dependencies for the following libraries:
nf_conntrack.ko`) — it does not care that the provider is already installed,
only that the package never says so. `kmod-ipt-ipopt` is defined in
`package/kernel/linux/modules/netfilter.mk` and `AddDepends/ipt` emits
`DEPENDS+=`, so `apply_preset()` rewrites that one line to
`$(call AddDepends/ipt,+kmod-nf-conntrack)`. No flash cost: `kmod-nf-conntrack`
is in the image regardless.

### Ruby YJIT and the Rust host build (regression, fixed)

`PACKAGE_ruby` ships only so the on-demand OpenClash package can install from
this project's opkg repo; nothing in the image runs Ruby. Its Kconfig entry
`RUBY_ENABLE_YJIT` is `default y if x86_64||aarch64`, so on this target it was
silently on, and `PKG_BUILD_DEPENDS:=ruby/host RUBY_ENABLE_YJIT:rust/host`
dragged the Rust host compiler into every build.

That Rust host build does not compile Rust from scratch: `x.py` fetches a
prebuilt `rust-dev-<ver>-x86_64-unknown-linux-gnu.tar.xz` from
`ci-artifacts.rust-lang.org/rustc-builds/<commit>/` and only builds LLVM if the
download fails. Those artifacts are rotated out over time — a build on
2026-11-02 spent ~3 h and then died with

```
curl: (22) The requested URL returned error: 404
ERROR: failed to download llvm from ci
```

even though nothing in the image is written in Rust. YJIT cannot work here in
any case: Ruby 3.4 does not support cross-compiling YJIT, and the build host is
x86_64 while the target is aarch64, so the interpreter falls back to the
non-JIT path regardless. `preset` now pins
`# CONFIG_RUBY_ENABLE_YJIT is not set`, and CI fails the build if that line
disappears or if `CONFIG_PACKAGE_rust=y` ever shows up.

Note for later: `ruby` + `ruby-yaml` are several megabytes in the image purely
for a package that is not installed. The correct long-term shape is to build
them as on-demand packages (`build-ondemand-packages.sh`) and drop them from
`preset`; that is deferred until the image is confirmed booting.

### ndisc6 1.0.2 is gone (build fix)
`luci-app-qmodem` pulls `ndisc6` and `rdisc6` in (`PACKAGE_luci-app-qmodem_INCLUDE_ndisc6`
/ `_INCLUDE_rdisc6`), so the tarball for them sits on the `make world` critical
path. The qmodem feed copy still asked for `ndisc6-1.0.2.tar.bz2` from
`http://www.remlab.net/files/ndisc6`; remlab keeps only 1.0.8 and 1.0.9 now, so
the URL answers `301` to https and the file itself `410 Gone`. Neither the
ImmortalWrt nor the OpenWrt source mirrors ever carried 1.0.2, so the build ran
out of mirrors:
```
Download failed.
No more mirrors to try - giving up.
```
(run `41400987301`, after ~3 h of compiling).
`apply_preset()` now rewrites the feed `Makefile` in place to `PKG_VERSION:=1.0.8`
(the release Debian itself tracks), `PKG_MD5SUM:=335a810a0180d36a1e2a5a81c425e2d6`,
and `PKG_SOURCE_URL:=https://www.remlab.net/files/ndisc6` — https on purpose,
because the http URL is a `301` and every extra redirect is another way for a
CI fetch to fail. Bumping in place is cheaper than vendoring the tarball: the
package is autotools with a shipped `configure`.
The version bump alone was not enough (run `41438049720`, ~3 h again), because
the feed copy also carries two 1.0.2-only patches and a `-std=c99` flag:
- `100-favor_bsd.patch` inserts `#define __FAVOR_BSD 1` next to `_BSD_SOURCE`
  in `src/trace-{tcp,udp}.c`. 1.0.8 rewrote both files around C11 `alignas` and
  no longer undefines `_GNU_SOURCE`, so `Hunk #1 FAILED at 24` and the patch
  aborted with `.prepared_…` error.
- `110-strverscmp.patch` copies glibc's `strverscmp` into the old `rdnssd/`
  directory (`rdnssd/Makefile.am`, `Makefile.in`, new `strverscmp.c`). 1.0.8
  moved the daemon to `rdnss/` with a different `Makefile.am`, and musl exports
  `strverscmp` in `libc.so` anyway.
- `TARGET_CFLAGS += -std=c99` fails on 1.0.8's aligned payload buffers:
  `src/trace-tcp.c:52: error: expected expression before 'struct'` (`alignas`
  is C11, so the target build needs the default gnu17).
`apply_preset()` therefore drops the whole `patches/` directory and the c99
line alongside the version bump. Verified locally by cross-building
`ndisc6-1.0.8` with an `aarch64-linux-musl` toolchain and CFLAGS `-Os`:
`ndisc6`, `rdisc6` and `rdnssd` all link, `rdnssd`'s `strverscmp` resolves from
musl, and `make install --prefix=/usr` puts them at `/usr/bin/ndisc6`,
`/usr/bin/rdisc6`, `/usr/sbin/rdnssd` — the paths the feed's install rules
expect.
CI asserts the version, the hash, the https URL, that `patches/` is gone and
that the c99 line is gone, since a feed bump would drag all three back.
### qmi_wwan_q and the missing `rmnet_nss_callbacks`
The vendor modem driver `quectel_QMI_WWAN` (qmodem feed, `qmi_wwan_q` 1.5)
defines `CONFIG_QCA_NSS_DRV` unconditionally when the target pinctrl is
IPQ807x/IPQ5018/IPQ8074 — true here — and then references the global
`rmnet_nss_callbacks` that lives in the separate `rmnet_nss.ko`
(`feeds/qmodem/driver/nss/rmnet-nss`). Nothing in the image provides it, and
modpost refuses to link an undefined symbol in a module:
```
ERROR: modpost: "rmnet_nss_callbacks" [qmi_wwan_q-1.5/qmi_wwan_q.ko] undefined!
```
(run `41456411377`, ~1 h in).
`rmnet-nss` looks like the fix, but it cannot be selected: its `DEPENDS` are
`+kmod-qca-nss-drv +@NSS_DRV_RMNET_ENABLE +@NSS_DRV_C2C_ENABLE`, and C2C is
the chip-to-chip NSS path (`config NSS_DRV_C2C_ENABLE`, `default n`, only
prompted for ipq806x/ipq807x). An AW1000 has one SoC, so pulling in the C2C
front end to satisfy a dependency would add code for a topology that does not
exist. Enabling it was rejected for that reason, not because it fails to build.
So the NSS hand-off is compiled out in the driver instead
(`nss/feeds/qmodem/driver/quectel_QMI_WWAN/patches/0001-disable-qca-nss-hook.patch`,
two `#define CONFIG_QCA_NSS_DRV` lines removed, everything else untouched).
What is lost: `qmi_wwan_q` normally hands received modem packets to the NSS
core (`qca_nss_rx_handler` → `nss_cb->nss_tx()`) and creates an NSS context per
QMAP device. Without it the modem path stays on the host stack. That is also
the path this image wants: ECM patch `0027` excludes `wwan*`/`rmnet*` from
acceleration so the TTL rewrite always applies, so no accelerated WAN flow
existed to lose. LAN/WiFi acceleration (the reason NSS ships) is untouched —
`CONFIG_NSS_DRV_RMNET_ENABLE=y` stays because ECM's RAWIP front end uses
`nss_rmnet_rx_get_ifnum`.
The driver keeps its own QMAP implementation (`qmap_mode`/`rx_qmap` module
params, no `rmnet_data` imports), so `wwan*` netdevs are created exactly as
before. Verified by building the patched `qmi_wwan_q.ko` against a kernel tree:
`nm -u qmi_wwan_q.ko | grep rmnet` is empty, and the unpatched source fails
modpost with the symbol above. CI asserts the patch is present in the repo,
that the `nss/` overlay copied it into `feeds/qmodem`, that it still removes
both `#define` lines, that `Build/Prepare` still flattens `./src/*` into
`PKG_BUILD_DIR` (the patch is `-p1` against the build root), and that
`kmod-rmnet-nss` stays out of the image.
### Conntrack events on 6.12 (checked, no action)

ECM registers a conntrack notifier to release state as soon as a connection is
destroyed. That block is behind `CONFIG_NF_CONNTRACK_EVENTS`, which the generic
`config-6.12` leaves unset but `kmod-nf-conntrack-netlink` (shipped, `preset`
line 2570) forces to `y` through its `KCONFIG`, so the code *is* compiled in.

Verified against `v6.12.94`: the API still exists, but lives in
`include/net/netfilter/nf_conntrack_ecache.h` (not `nf_conntrack.h`), with
`.ct_event` as the >= 5.15 member and `nf_conntrack_unregister_notifier(net)`
taking one argument. `ecm_conntrack_notifier.c` reaches it through
`nf_conntrack_core.h`, which it already includes, so the mainline branch of
patch `0026` compiles as-is.

`CONFIG_NF_CONNTRACK_CHAIN_EVENTS` only exists in ImmortalWrt's `hack-6.18`
(`952-net-conntrack-events-support-multiple-registrant.patch`), pulled in by
`fullconenat`; on 6.12 the symbol is undefined, so `0026`'s `notifier_block`
branch is inert here and only pays off if the target ever moves to 6.18.

### Runtime fail-safe

`/etc/init.d/byte-selfcheck` gained `check_nss()`:

- asserts ECM is loaded and `accel_mode == 0` (`ACCEL`);
- dumps ECM's interface table through the state char device (`state_dev_major`
  from debugfs, output mask `16` = `INTERFACES`, restored to `1` afterwards) and
  flags any `ifaces.iface.<subtype>.iface.name` matching `^(wwan|rmnet)` whose
  `ae_interface_identifier >= 0`;
- on a hit, logs `ECM_MODEM_LEAK` and stops `qca-nss-ecm` — losing LAN offload
  is the lesser failure compared to a TTL leak.

`/usr/bin/nss-offload status` shows ECM load state, `accel_mode` and whether the
`byte_ttl` chain is live. `nss-offload off` remains as a panic button and says
so; it no longer claims to fix WAN TTL, because WAN was never accelerated.

### LuCI page

`files/www/luci-static/resources/view/qmodem/ttl.js` overrides the app's page.
Only the wording changes: the stock text warns that enabling TTL disables NSS
offload, which is no longer what happens. The UCI schema, field names and
datatypes are identical, so `luci-app-qmodem-ttlfw4` remains the owner of the
page and of `/etc/config/qmodem_ttl`.

### Open items

- **Untested on hardware.** The changes are build-validated only. Needed on a
  spare unit: `logread | grep byte-selfcheck`, `nss-offload status`, and a
  tcpdump on the modem netdev confirming TTL 64 for both forwarded and
  router-originated traffic.
- **ECM 12.5 on 6.12.94 with bonding off** has not been compiled yet.
- **ECM state device** availability at boot is assumed from source, not seen.
- **Recovery path unconfirmed** on the target unit (no serial session yet), so
  no image has been flashed from this branch.

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
- **Build fix: `qmi_wwan_q` no longer needs `rmnet_nss_callbacks`.** The
  vendor driver defines `CONFIG_QCA_NSS_DRV` on IPQ807x and links against
  `rmnet_nss.ko`, which cannot be selected here (its `+@NSS_DRV_C2C_ENABLE`
  dependency is the chip-to-chip NSS path, useless on a single-SoC AW1000), so
  modpost failed with an undefined symbol. The NSS hand-off is compiled out by
  a feed patch; QMAP mode is unchanged and ECM never accelerated
  `wwan*`/`rmnet*` anyway, so no usable offload is lost.
- **Build fix: `ndisc6` 1.0.2 → 1.0.8.** Upstream removed 1.0.2 and the
  OpenWrt/ImmortalWrt mirrors never had it, so the download ended with "No more
  mirrors to try - giving up" ~3 h into the build. The feed copy is bumped in
  `apply_preset()` with a pinned MD5 and an https source URL, and the feed's two
  1.0.2-only patches (BSD `struct` headers, a `strverscmp` copy) plus the
  `-std=c99` flag are dropped — 1.0.8 is C11 (`alignas`) and needs none of
  them. CI asserts all five.
- **Build fix: `RUBY_ENABLE_YJIT` off.** It defaults to `y` on aarch64 and
  pulls `rust/host` in, whose prebuilt-LLVM download now 404s upstream (build
  dies ~3 h in). YJIT cannot work on a cross-compiled aarch64 target anyway.
  CI rejects a rebuild that turns it back on, and rejects
  `CONFIG_PACKAGE_rust=y`.
- **Build fix: `kmod-ipt-ipopt` declares the conntrack dependency.** The
  DSCPREMARK patch makes `xt_DSCP.ko` import `nf_conntrack.ko`, which the
  kernel-package dependency checker treats as a hard error until the package
  names the provider. `apply_preset()` switches the `ipt-ipopt` block to
  `$(call AddDepends/ipt,+kmod-nf-conntrack)`; CI asserts the rewritten block.
- **NSS/ECM ships and stays on.** `qca-nss-ecm` is back in the image and is
  never stopped by the TTL service. Modem egress (`wwan*`, `rmnet*`) is
  excluded from acceleration by ECM patch `0027`, so the TTL rewrite always
  applies on the WAN while bridge/LAN/WiFi stays offloaded. Bonding front end
  compiled out (`struct bond_cb` is QSDK-only); DSCPREMARK conntrack extension
  restored with `default y`; `byte-selfcheck` detects an accelerated modem
  interface and stops ECM as a fail-safe. See *Engineering log*.
- Menu banner lost the leftover contact line; the NSS status cache no longer
  claims ECM is missing.
- `luci-app-ramfree` is vendored in `packages/`: the luci feed is pinned to the
  first commit that carries `view/dashboard/lib/*`, and ImmortalWrt added the
  app after that pin, so a pinned build dropped it and the *Release RAM* entry
  disappeared. The CI assert for the feed pin was also looking for a literal
  `luci.git^<sha>` that the script never contains (it writes the pin with
  `sed`), so every build failed on a false negative; it now greps the generated
  `feeds.conf.default` line.
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

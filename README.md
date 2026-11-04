# BYTE for the Arcadyan AW1000

Custom ImmortalWrt 25.12.1 firmware (kernel 6.12.94) for the Arcadyan AW1000
(`ipq807x`): Quectel QMI cellular, NSS-accelerated WiFi, RJ11 phone, SMS,
TTL/Hop-Limit normalisation, PassWall2 and a themed LuCI dashboard. Every image
is built, signed and published from CI, together with a self-hosted opkg repo.

[![release](https://img.shields.io/github/v/release/Ace1337z/AW1000_BYTE?style=flat-square&label=release&color=00B5E2)](../../releases/latest)
[![kernel](https://img.shields.io/badge/kernel-6.12.94-8e7cc3?style=flat-square)](#)
[![target](https://img.shields.io/badge/target-ipq807x%2Faw1000-5a6472?style=flat-square)](https://openwrt.org/toh/arcadyan/aw1000)

![Dashboard](docs/screenshots/dashboard.png)
<sub>Dashboard — modem signal, temperature and storage widgets. Screenshot from
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

- **Cellular** — QModem 3.4.0_rc3 (main `b4effcda`) over Quectel vendor QMI:
  band and cell lock, SMS
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
- **SIP calling (experimental, opt-in)** — QModem voice: `qmodem-voip` owns the
  modem audio, `qmodem-sipd` provides the SIP side, `luci-app-qmodem-voip` the
  page. An incoming call rings the RJ11 phone and the SIP apps at the same
  time, and whichever answers first gets it; SIP audio is 8 kHz PCMA/PCMU.
  The packages ship in the image but the service is **configured off**
  (`qmodem_sip.inbound.enabled=0`, `fxs.main.sip=0`): turn it on in *QModem →
  VoIP* and *Services → Phone (RJ11) → Settings*. An open SIP listener with an
  empty password must not exist on every unit by default.
- **IPv6 that cannot hang the LAN** — WAN IPv6 is autodetected (qmodem deletes
  `wanv6` on every redial), probed with real traffic, and demoted to IPv4 only
  while it is broken; it restores itself when the carrier starts working. LAN
  RA/DHCPv6 settings come back exactly as the owner had them.
- **WiFi** — NSS-accelerated 2.4/5 GHz; both radios up on first boot.
- **UI** — Footstrap 0.14.19 only (no second theme ships), BYTE logo and icons,
  a BYTE panel under *Tools* (AdGuard Home ↔ PassWall2 DNS wiring with a live
  install terminal, shortcuts), a JS modem-info view, a dashboard with KPI cards
  and charts, and Netstat backed by persistent vnStat2 history.
- **Dashboard** — KPI cards (Internet, Memory, Mobile, Uptime, **Storage**,
  CPU usage, Temperature, Load) plus five live charts (system load, WAN traffic,
  mobile traffic, mobile signal, temperature). The old bottom detail tabs and
  the layout editor are hidden: the dashboard is read-only, and the capacity
  card reports overlay used/total with a bar.
- **Dashboard widgets** — Mobile, Temperature and Storage. NSS offload is not
  shown: its counter only moves while the NSS clock scales itself, which is off
  here. NSS/ECM still accelerate traffic (`qca-nss-ecm` ships and stays loaded).
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
opkg install luci-app-passwall   # PassWall v1 (Lua); disable passwall2 first
```

### Tuning defaults

| | |
|---|---|
| Congestion control | `bbr` with `fq` (`kmod-tcp-bbr`), `tcp_slow_start_after_idle=0` |
| Socket buffers | `tcp_rmem`/`tcp_wmem` capped at 4 MB, `tcp_moderate_rcvbuf=1`, `tcp_notsent_lowat=131072` |
| TCP Fast Open | `tcp_fastopen=3` (client + server), blackhole timeout 60 s |
| NAPI / backlog | `netdev_budget=2400`, `netdev_max_backlog=16384`, `dev_weight=64`, `napi_defer_hard_irqs=2` + `gro_flush_timeout=20000` ns on `wwan*` |
| WAN egress queue | `fq` sized from the bearer instead of the 10000-packet default: `limit` ≈ 3× BDP (1981 packets at 200 Mbit/40 ms), `flow_limit=100`, `initial_quantum=64 KB`; knobs in `/etc/config/byte` |
| Busy polling | `busy_poll=50`, `busy_read=50` — opt-in per socket (`SO_BUSY_POLL`), so it only affects the router's own services |
| Neighbour tables | `gc_thresh1/2/3 = 512/2048/4096` for IPv4 **and** IPv6 |
| Packet steering | `packet_steering=1`, `steering_flows=32768`, RPS/RFS `0f` on `wwan*`, bounded `fq` on the modem netdev, XPS probed per device |
| Fail-fast | `tcp_no_metrics_save=1`, `tcp_syn_retries=3`, `tcp_synack_retries=3`, `tcp_retries2=8` |
| CPU / memory | `performance` governor, zram, modem IRQs spread across cores |
| Conntrack | 32768 max, 7440 established, keepalive 120/15/4 |
| vnStat | `DatabaseDir=/etc/vnstat` on the overlay, re-asserted every boot |
| Multicast / IPTV | `br-lan`: `igmp_snooping=1`, `multicast_querier=1`, `hash_max=4096` |

A boot-time self-check (`byte-selfcheck`) logs each of these and reports a
`MISMATCH` when one did not apply.

#### IPTV and multicast

The physical `wan` port is a member of `br-lan`, so an ISP set-top box and the
uplink cable sit on the same L2 as `lan1..lan4`. Without snooping the bridge
floods every multicast stream to every port, WiFi AP ports included: one HD
channel saturates the 2.4 GHz airtime and the whole interface stalls. Without a
querier the other half breaks - nobody refreshes group membership, the bridge
ages the group out and playback freezes minutes into a channel.

Both are fixed in the bridge itself, with no daemon:

- `igmp_snooping=1` sends a group only to the ports that joined it.
- `multicast_querier=1` makes the bridge send its own IGMP/MLD queries, so
  group state never times out. No `igmpproxy`, no `udp-broadcast-relay-redux`.
- `hash_max=4096` because netifd's 512-entry default overflows on a full
  channel list; the kernel then logs `br-lan: multicast hash table full` and
  silently falls back to flooding.

`udp-broadcast-relay-redux` is *not* shipped and is gated out of the build: it
re-broadcasts every UDP packet to every bridged port, which is the behaviour
that made IPTV unusable on a busy LAN in the first place. It is only the right
tool for forwarding a single broadcast service across a routed boundary (e.g.
Wake-on-LAN between subnets), never for IPTV.

Optional, not shipped by default:

- `option multicast_fast_leave '1'` on the set-top box's port trims the
  leave-then-join gap when zapping, at the cost of no retransmission if a
  second client is still watching that group.
- IPTV on a separate VLAN/bridge is better than sharing `br-lan` when the ISP
  hands out a tagged IPTV VLAN; keep snooping + querier on that bridge too.
- `igmpproxy` is only needed when multicast has to cross a *routed* hop (the
  source is an interface, not a bridge port). This image does not ship it; the
  bridged layout above does not need it.

#### Branding: BYTE, not OpenWrt, not BYTE_by_ACE

The theme header renders a logo plus the **hostname** as its wordmark, so the
two are set together:

- `hostname` is `BYTE` (it was `BYTE_by_ACE`; a DHCP/DNS-safe single label).
  `91-byte-identity` rewrites the old value on upgrade, because sysupgrade
  without `-n` keeps `/etc/config/system`. A hostname the admin set themselves
  is never touched.
- The logo is a real override:
  `files/usr/share/ucode/luci/template/themes/footstrap/partials/brand.ut`
  replaces the theme's own copy, which hardcodes the **OpenWrt arcs as inline
  SVG** - no CSS rule can swap that, and `logo.svg` only covers the favicon and
  the PWA icon. The override draws the same "B" mark as `logo.svg` (stem plus
  two bowls, counters punched with the even-odd rule, accent underline) in
  `currentColor`, so it works on light and dark palettes without a second
  asset.
- The build fails if the theme stops shipping or including that partial, so an
  upstream rename cannot silently revert the header to the OpenWrt mark.

Caveat: `opkg upgrade luci-theme-footstrap` reinstalls the theme's own
`brand.ut` over the override until the next sysupgrade.

`luci-app-byte` (Tools → *BYTE (AdGuard Home + PassWall2)*) is not a general
settings page; its intro banner says so before any button, because *Install and
wire* moves dnsmasq off port 53.

## Firmware version
Status → Overview shows the short display form; image filenames carry the
filesystem-safe `CONFIG_VERSION_NUMBER`:
```
Status → Overview:  BYTE 25.12 VERSION 1.2.8
Image filename:     ...-25.12.6.12.94-...
                         │    │
                         │    └── kernel of the build
                         └─────── release series
```
`version.env` holds `FW_MAJOR`/`FW_MINOR`/`FW_BASE`/`FW_PATCH_FALLBACK`; the
patch is `git rev-list --count FW_BASE..HEAD`, so there is no manual bump. The
build aborts if the kernel version cannot be resolved rather than shipping
`25.12(x)`.

The two forms are decoupled on purpose. `CONFIG_VERSION_NUMBER` is built as
`25.12.6.12.94` because that string also lands inside every image filename, and
a `(` there breaks `Build/kernel-bin`'s unquoted `rm -f $@` (bash subshell
token). At first boot `98-byte-version` writes `/etc/byte-version`
(`BYTE 25.12 VERSION 1.2.8`) and leaves `DISTRIB_DESCRIPTION` alone, because
sysupgrade and the build metadata derive from it. The Status panel reads
`/etc/byte-version` and falls back to parsing `DISTRIB_DESCRIPTION`.

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
- **WAN IPv6 is autodetected, measured, and demoted only while it is broken.**
  `/usr/libexec/byte-v6-check` recreates `wanv6` (`proto=dhcpv6`,
  `device=@wan`) whenever qmodem has deleted it on a redial, then retries
  `ifup wanv6` until it settles. Connectivity is measured with real traffic,
  never "an address exists": ICMPv6 echo to two anycast resolvers
  (`2001:4860:4860::8888`, `2606:4700:4700::1111`) plus an HTTP GET over IPv6
  (`uclient-fetch -6`) for networks that filter ICMPv6. Every probe uses a
  numeric address, so a broken DNS server cannot look like a broken uplink. On
  PD-only carriers (delegated prefix, no global address on the WAN netdev) the
  ICMPv6 probe is source-bound to the LAN address that came from the delegated
  prefix - the only way to tell "the prefix is routed" from "there is no source
  address". Two consecutive agreeing rounds are required before anything
  changes.
  On this carrier (`wanv6` completes the DHCPv6 exchange - global `/64`,
  delegated `/64`, both ISP resolvers - but nothing past the modem answers: the
  modem's own gateway `fe80::ad53:8745:d045:ba03` replies while the ISP
  resolver behind it does not, `Ip6OutRequests` climbs with `Ip6InReceives`
  flat, and `AT+QMAP="wwan"` reports no IPv6 on the mux
  (`"IPV6","0:0:0:0:0:0:0:0"`)) the verdict is demotion:
  `dhcp.lan.ra`/`dhcpv6` are set to `disabled` so clients stop receiving a
  prefix they cannot use, `gai.conf` prefers IPv4 for any glibc binary added
  later, and `unreachable default metric 1` replaces the black hole with an
  immediate ICMPv6 unreachable. Metric 1 is deliberate: netifd installs its
  own `::/0` at metric 11 and would otherwise re-open the hole on the next
  renew. While demoted the check re-probes every 30 s (300 s when healthy) and
  every interface event kicks it, so as soon as the carrier passes IPv6 the
  original `dhcp.lan.ra`/`dhcpv6` values come back from `/etc/byte/v6.state`
  and traffic returns to IPv6 without a reboot. The br-lan ULA is deliberately
  left alone - it keeps LAN-local IPv6 (router access, PassWall) working, and
  the fail-fast route is what removes the hang, not the missing ULA. A unit
  whose owner set `ra=disabled` gets exactly that value back after a restore.
- **Whoever touches the QMAP mux: it has no link-local unless one is added.**
  `qmi_wwan_q` gives `wwan0_1` the base interface's MAC, so the EUI-64
  link-local the kernel would generate is already owned by `wwan0` and
  `wwan0_1` ends up with no `fe80::` address at all. Without one there is no
  source for `ff02::1:2`/`ff02::2`, so `odhcp6c` only ever logs
  `Failed to send SOLICIT message to ff02::1:2 (Address not available)` and
  `Failed to send RS (Address not available)`, and `wanv6` never comes up -
  which makes a carrier that *does* serve IPv6 look like one that does not.
  `byte-v6-check` now assigns a unique MAC-derived link-local
  (`1e:5d:db:b0:e8:b9` → `fe80::1e5d:dbb0:e8b9`) before it waits for `wanv6`.
  Verified on the unit: with the address present DHCPv6 completes and the
  gateway answers; without it both fail as described.
- **SIP calling is experimental and upstream calls it that.** The voice stack
  is QModem `main`, not a release: upstream's own `version-migration.zh-cn.md`
  marks `v3.4.0_rc3` "not recommended as production firmware". Only the
  Quectel **RG500Q-EA with firmware `RG500QEAAAR13A01M4G` and USB ID
  `2c7c:0800`** is in the voice profile table - the daemon matches model,
  firmware *and* USB ID, so a replacement modem or a firmware flash drops
  voice with a log line, not silently. One call slot, no PBX, no call waiting
  through SIP, no group/paging, SIP audio fixed at 8 kHz PCMA/PCMU (HD audio
  stays a RJ11-only feature), and the SIP password is generated once in LuCI
  and shown once. If it misbehaves, turn off `fxs.main.sip` and the RJ11 phone
  keeps working on its own.

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
(the release Debian itself tracks), `PKG_SOURCE_URL:=https://www.remlab.net/files/ndisc6`
— https on purpose, because the http URL is a `301` and every extra redirect is
another way for a CI fetch to fail — and a pinned `PKG_HASH`
(SHA256 `1f2fb2dc1172770aa5a09d39738a44d8b753cc5e2e25e306ca78682f9fea0b4f`).
The hash key itself moved: OpenWrt renamed `PKG_MD5SUM` to `PKG_HASH` tree-wide
and the qmodem feed copy followed. A sed that rewrites `PKG_MD5SUM:=` then
matches nothing, which is exactly how run `41704830850` died with
`ndisc6: could not pin 1.0.8` before compiling anything. The rewrite is
key-based now (`awk`, one `PKG_HASH` line right after `PKG_SOURCE_URL`, any
`PKG_MD5SUM` line dropped so package.mk does not see two hashes), so it works
with either spelling. Bumping in place is cheaper than vendoring the tarball:
the package is autotools with a shipped `configure`.
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
CI asserts the version, the `PKG_HASH` (or the legacy `PKG_MD5SUM` spelling,
which is then forbidden so the tree cannot end up with both), the https URL,
that `patches/` is gone and that the c99 line is gone, since a feed bump would
drag all three back.
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
So the NSS hand-off is compiled out in the driver instead. That used to mean a
repo patch (`nss/feeds/qmodem/driver/quectel_QMI_WWAN/patches/0001-disable-qca-nss-hook.patch`)
deleting the two `#define CONFIG_QCA_NSS_DRV` lines. The patch is gone: the
qmodem pin `b4effcd` rewrote the driver so it no longer defines the symbol at
all — every use now sits behind `#ifdef CONFIG_QCA_NSS_DRV`, a symbol the kernel
config never sets, so `nss_cb` stays `NULL` and nothing references
`rmnet_nss_callbacks`. The patch had nothing left to patch and stopped applying,
which is how run `41721902711` died 1 h 42 m in:
```
Applying .../patches/0001-disable-qca-nss-hook.patch using plaintext:
patching file qmi_wwan_q.c
Hunk #1 FAILED at 58.
Hunk #2 FAILED at 72.
2 out of 2 hunks FAILED -- saving rejects to file qmi_wwan_q.c.rej
```
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
before. Verified on the built module: `nm -u qmi_wwan_q.ko` has no `nss`
symbol, and the packaged `qmi_wwan_q.c` is byte-identical to the feed source
(`cmp`), i.e. nothing was patched.

Two earlier attempts are worth keeping, because both failed for reasons that a
successful compile would not have caught. **First, the patch was never
applied.** `quectel_QMI_WWAN` defines its own `Build/Prepare`
(`mkdir -p $(PKG_BUILD_DIR)` + `$(CP) ./src/* $(PKG_BUILD_DIR)/`) and, unlike
`Build/Prepare/Default`, it never calls `$(Build/Patch)`. A package that
overrides `Build/Prepare` and skips that call has an inert `patches/` directory:
the file is copied into the feed, listed in the repo, and never read. Run
`41469086214` therefore failed at the same modpost line as `41456411377`, 1 h
50 m in. The hand test that "proved" the patch worked had applied it with
`patch -p1` directly, which validated the *content* and not the build path —
exactly the kind of gap the local gates in
[Local build verification](#local-build-verification-ci-is-the-release-path-not-the-debugger)
exist to close. The fix then was injecting `$(Build/Patch)` into that
`Build/Prepare`; **second**, that fix was already obsolete by the time it
reached CI, because the feed bump that carried the new driver source landed in
the same batch (see below).

`apply_preset()` no longer patches that package. It deletes any `patches/`
directory the old overlay may have left behind (a stale copy only fails the
build again), then asserts the driver source itself: a bare
`#define CONFIG_QCA_NSS_DRV` is an error, and the `#ifdef CONFIG_QCA_NSS_DRV`
guard must exist. Both checks run in seconds, before any compilation, so a feed
bump that reverts to the self-defining driver is caught at the top of the build
instead of at modpost an hour in. The `packages` gate additionally fails on any
`*.rej`/`*.orig` left in `build_dir`, since `$(PATCH)` runs with `-f` and a
non-applying hunk would otherwise be silent.

CI asserts the source is guarded, has no self-define, that
`feeds/qmodem/driver/quectel_QMI_WWAN/patches/` does not exist, and that
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

### NSS feature flags are module flags, not kernel symbols

Worth writing down because it is easy to get wrong: `NSS_DRV_RMNET_ENABLE` and
its ~40 siblings are **not** kernel config symbols. `qca-nss-drv`'s
`KernelPackage` block has no `KCONFIG` at all; the options are
`PKG_CONFIG_DEPENDS` plus `feeds/nss/qca-nss-drv/Config.in`, and the package
Makefile turns each one into a module define:

```make
ifndef CONFIG_NSS_DRV_RMNET_ENABLE
   DRV_MAKE_OPTS += NSS_DRV_RMNET_ENABLE=n
endif
```

Consequences: they never appear in `.config.override` and never in any kernel
`.config`, so `grep CONFIG_NSS_DRV_... .config` proves nothing. What actually
proves the flag took effect is the built module — ECM's RAWIP front end calls
`nss_rmnet_rx_get_ifnum`, so:

```
nm -g build_dir/target-*/linux-qualcommax_ipq807x/qca-nss-drv-*/qca-nss-drv.ko \
  | grep nss_rmnet_rx_get_ifnum
```

must print the symbol. The `packages` gate runs exactly that.

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

### Packet steering has one owner: netifd, not ECM
`packet_steering '1'` + `steering_flows '32768'` were correct in the image from
1.2.1, and `92-byte-steering` fixed units upgraded from <=1.2.0, yet a freshly
flashed 1.2.30 still reported *Packet Steering: Disabled*. The writer was
`qca-nss-ecm`. Its init defined
```sh
disable_packet_steering() {
  uci -q set network.globals.packet_steering=0 && uci commit ...
  uci -q del network.globals.steering_flows    && uci commit ...
  /usr/libexec/network/packet-steering.uc -l 0 0
}
```
and called it from `start_service()` (START=26, one second after netifd's
`packet_steering` at 25) and from `reload_service()` (`network` is a reload
trigger). QSDK parks steering when NSS owns the data path; on this box ECM
excludes `wwan*`/`rmnet*` (patch 0027) and the LAN/WiFi path still benefits
from per-queue CPU assignment, so parking it only cost throughput.
The fix is not "turn it on harder". `92-byte-steering` was already one-shot
and deletes itself, and a whiteout in the preserved overlay hides the next
image's copy, so it cannot repair an upgrade either. Two durable changes:
1. `apply_preset()` rewrites the ECM function to `apply_packet_steering()`,
   which *reads* `network.@globals[0].packet_steering` (default 1) and
   `steering_flows`, then runs `packet-steering.uc` exactly like netifd does.
   No `uci set`, no `commit`, no `del` - one writer, `/etc/config/network`.
2. `/etc/init.d/byte-steering` (START=24) ships
   `files/etc/rc.d/S24byte-steering` in the squashfs, so it runs on every boot
   even though `/etc/rc.local` is in `keep.d` and is the *old* copy after an
   upgrade. It repairs `0`/unset back to `1`, leaves a deliberate `2`
   ("Enabled (all CPUs)") alone, re-asserts `steering_flows=32768`, and commits
   only when something changed.
`packet_steering=1` (not 2) keeps one queue/NAPI thread per CPU, which matches
NSS/ath11k's per-queue model; 2 puts every queue on all four CPUs and only pays
off when a single queue carries most of the load. `steering_flows=32768` is the
same size as `net.core.rps_sock_flow_entries`, so RFS is not clamped.
`steering_flows` is re-asserted on every boot because `byte-affinity` sizes its
RFS table for that value; a `packet_steering` of `0` is treated as the ECM
regression, not as a preference.
Gates: `disable_packet_steering` and `packet_steering=0` must be absent from
the feed init, `apply_packet_steering` must be present, `byte-steering` must be
executable with `START=24`, the `S24` symlink must exist, and the image network
config must still carry both options.

### Four cores: what RPS/RFS can move, and what XPS cannot
The AW1000 has one bottleneck that no sysctl removes: the USB modem's data
interrupt is a single xhci line. On the unit, all `xhci-hcd:usb3` interrupts
land on one CPU, and writing an all-cores mask to that IRQ does not help - the
kernel collapses `effective_affinity` back to one CPU, so the interrupt count
stays on that core regardless. Everything below works *around* that, not on it.
- **RPS** moves packet *processing* off that core: every `queues/rx-*/rps_cpus`
  on `wwan*`/`rmnet*` gets mask `0f` (all four cores, derived from the CPU
  count by `byte-selfcheck`, not asserted as a literal).
- **RFS** keeps a flow on the CPU already handling it: per-queue
  `rps_flow_cnt=32768` and `net.core.rps_sock_flow_entries=32768`, which is the
  same number `steering_flows` carries - a lower global value silently clamps
  the per-queue tables that `packet_steering` writes.
- **NAPI deferral** cuts how often that one IRQ fires at all:
  `napi_defer_hard_irqs=2` with `gro_flush_timeout=20000` (nanoseconds, i.e.
  20 us) on the modem netdev. These are the values
  `netdev_sw_irq_coalesce_default_on()` uses upstream; usbnet never calls it, so
  they are 0 by default here. 20 us is below any measurable RTT - this is an
  interrupt-count win that costs no latency.
- **XPS cannot be spread.** `qmi_wwan`/`qmi_wwan_q` mux netdevs expose a single
  tx queue, and the kernel rejects a multi-CPU `xps_cpus` mask in that case.
  `byte-affinity` therefore counts the tx queues per device, attempts the write
  only when there are two or more, and caches the verdict in
  `/var/run/byte-affinity.xps.<dev>`; the boot log line reports
  `xps=wwan0=unsupported wwan0_1=unsupported` instead of pretending otherwise.
  Retrying a write the kernel will never accept just burns forks every minute.
- **fq on the modem netdev, with a bound.** BBR computes a rate but only
  `sch_fq` paces it. `default_qdisc=fq` covers devices present at boot; the wwan
  mux interface is registered after qmodem dials, so `byte-affinity` checks the
  live qdisc and runs `tc qdisc replace dev wwan0 root fq` when it is not
  already `fq`. It no longer stops at "the qdisc is fq": the parameters are read
  back and re-applied when they differ from the sized ones (see below).
- **The reload no longer churns.** Every sysfs write goes through `set_sysfs`,
  which compares first - numerically for hex masks, because the kernel prints
  `f`, not `0f`, and a string compare would rewrite every time. Rewriting
  `rps_cpus` with an identical value still allocates a new steering map and
  schedules `call_rcu`, so the old 15 s reload was keeping the RCU path busy for
  the life of the boot. The timer is now 60 s (hotplug + the netifd raw trigger
  already cover redial) and steady state does zero writes, zero `tc` forks and
  logs nothing.
No SQM is involved: latency under load stays the job of a bounded `fq` plus BBR
(see the next section), and the added TCP keys only change *time to notice* a
dead path (`tcp_no_metrics_save=1`, `tcp_syn_retries=3`,
`tcp_synack_retries=3`, `tcp_retries2=8`) - none of them touches throughput.
Gates: `RPS_MASK=0f`, `RPS_FLOW=32768`, `START=96`, the NAPI/GRO constants, the
`set_sysfs` helper, the `tc qdisc replace` path, the fq sizing helpers and the
per-device XPS probe must all be present; a `sleep 15` reload is a build
failure.

### The WAN queue is bounded, not shaped
The image ships no SQM, so the only thing standing between a saturated upload
and a 1-second latency spike is the size of the modem's egress queue. It was
the kernel default: `fq` with `limit 10000` packets, i.e. ~15 MB, which is
0.6 s of queue at 200 Mbit/s and 1.2 s at 100 Mbit/s. `flow_limit` (100) already
bounded a *single* flow, but a client running parallel uploads multiplies that
by the number of flows.

The queue is now sized from the bearer instead of left at the default:

```
limit         = 3 * uplink_kbit * rtt_ms / 12112      (packets)
              = 1981 at 200 Mbit/s and 40 ms           (~3 MB, ~120 ms)
flow_limit    = 100                                   (150 KB, <7 ms at 200 Mbit/s)
initial_quantum = 65536                               (slow-start burst, was 15140)
```

`12112` is `8 * 1514`: the divisor that turns kbit/s x ms into 1500-byte
packets. Three times the bandwidth-delay product is the usual compromise -
enough in flight to keep the bearer full, small enough that the queue cannot
hide a second of delay. Nothing is shaped: there is no rate ceiling and no
classification, the qdisc simply refuses to grow past the bound, so a flow that
is not saturating the link never sees it.

Knobs live in `/etc/config/byte` (`byte.fq.uplink_kbit`, `rtt_ms`, `flow_limit`,
`initial_quantum`, `enabled`). Defaults are what this image was tuned with;
`enabled=0` restores the kernel default but keeps `fq` installed, because BBR
still needs pacing. Nothing here needs a reflash to change - hence a config file
rather than constants baked into the init script - and `byte-affinity` logs
`fq=wwan0_1=1981/100` next to the RPS masks so the applied bound is visible in
`logread` without an SSH session.

`byte-fq-measure` reports what the queue is doing: qdisc parameters, backlog and
drops, the live sysctl values, and p50/p95/p99 for the gateway and `1.1.1.1`.
Run it idle and again during a saturating upload; the p99 delta is the number
that matters.

Two things deliberately **not** changed here:

- **`net.core.netdev_budget_usecs`.** The old comment in `sysctl.conf` claimed
  the kernel made it read-only. It does not: `net/core/sysctl_net_core.c`
  registers it `0644`. Its minimum is `2 * USEC_PER_SEC / HZ`
  (`sysctl_net_core.c:37`), which at `CONFIG_HZ=100` is 20000 us - so writing
  the 2000 us the RX budget was designed for returns `EINVAL`, and `sysctl -p`
  aborts the rest of the file on the first invalid key (that is how
  `tcp_slow_start_after_idle` never applied despite being written down). The
  floor is a function of HZ, not of the kernel version.
- **`CONFIG_HZ`.** Raising it to 250 would lower that floor to 8 ms, and it is
  the only remaining knob in the tick. It would change nothing measurable here:
  `net_rx_action`'s time limit is `jiffies + usecs_to_jiffies(budget_usecs)`
  (20 ms), but a pass ends when `netdev_budget` (2400 packets, ~3-5 ms) runs
  out, so the time limit never binds. The cost would be a full kernel rebuild,
  150 extra ticks per second per busy core, and re-verification of every patch,
  for a change below the noise floor of a cellular bearer that is already
  20-40 ms of RTT.

### QModem voice on the phone port: why the feed pin is `main`, not a tag
SIP needs three packages that only exist in QModem 3.4: `qmodem-voip` (modem
audio), `qmodem-sipd` (SIP transport) and `luci-app-qmodem-voip`. The 3.4 line
has no plain `v3.4.0` tag; the newest tag is `v3.4.0_rc3.1` and its
`application/voipd/files/usr/share/qmodem/modem_supports.json` lists exactly
one modem (RM520N-GL). AW1000 voice is `FUjr/QModem#290` on `main`: it adds
```json
{"model": "RG500Q-EA", "firmware": "RG500QEAAAR13A01M4G", "usb_id": "2c7c:0800",
 "adb_unlock": false,
 "audio": {"method": "pcm_socket", "socket_path": "/var/run/fxsd/pcm.sock", ...}}
```
so `qmodem_voip` attaches to `fxsd`'s PCM socket instead of driving the modem's
serial PCM port itself, and `fxsd` (0.7.0, driver 0.3.0 - both already in the
image) hands it the line. On the tag pin there is no matching profile, so the
daemon starts and then rejects every call: a package bump that looks harmless
silently kills the feature. Gates therefore assert `QMODEM_VERSION >= 3.4.0`,
that the profile file contains `RG500Q-EA` and `pcm_socket`, and that the
`byte-voip` service and its `S19` symlink exist.

Three build-level consequences that are easy to miss:

1. `ubus-at-daemon` takes its version from `feeds/qmodem/version.mk`
   (`PKG_VERSION:=$(QMODEM_VERSION)`), so "at-daemon 3.4.0 or newer" is a pin
   property, not a package choice. `3.4.0_rc3` is what `main` reports; it sorts
   after `3.4.0` in the version comparison, but it *is* a pre-release - upstream
   lists it as "not recommended as production firmware". That is the trade-off
   accepted for the feature; the fallback is turning SIP off, which leaves the
   RJ11 path untouched.
2. `qmodem-voip` needs `alsa-lib`, and `alsa-lib` depends on `kmod-sound-core`.
   The AW1000 kernel ships `CONFIG_SOUND=n`, so selecting the package flips the
   kernel symbol and rebuilds `soundcore.ko` (~10 KB). It cannot be installed on
   demand: a kmod built later would have to match this exact kernel.
3. 3.4.0 builds `libqvoice_media_gate.so` for the *modem's* 32-bit ARM CPU with
   `clang --target=arm-linux-gnueabihf -march=armv7-a -fuse-ld=lld` and pushes
   it over adb. RG500Q-EA has `adb_unlock: false` and never uses it, but the
   build step still runs, so host `clang` + `lld` must exist (CI installs both).
   Do not replace it with `$(TARGET_CC)`: that produces aarch64 and the file is
   meant for the modem side.

Two other changes the 3.4.0 bump forced:

- The dial/driver menu options moved from `luci-app-qmodem` to `qmodem`:
  `PACKAGE_luci-app-qmodem_INCLUDE_vendor-qmi-wwan` is now
  `PACKAGE_qmodem_INCLUDE_vendor-qmi-wwan` (same for the TOM quectel-CM
  choice). defconfig drops an unknown symbol without a warning, so a stale
  preset line would silently fall back to the *generic* QMI driver - the exact
  setup that races `qmi_wwan_q` for `/dev/cdc-wdm0` (see the preset comment).
  A gate forbids any `CONFIG_PACKAGE_luci-app-qmodem_*` line now.
- `luci-app-qmodem-sms` depends on `sms-forwarder-next`, which declares
  `PKG_CONFLICTS:=sms-forwarder` and vice versa. The preset shipped
  `sms-forwarder`; with both selected the image does not assemble. The old
  package is gone from the preset and a gate keeps it out. `qmodem-smsd`
  (event-driven SMS service, new in 3.4.0) plus `qmodem-settings`,
  `libqmodem-sms` and `libsqlite3` come in with it.

`/etc/init.d/byte-voip` (START=19, before `qmodem_init` at 80) repairs the two
things that are *not* package defaults on an upgraded unit:

- `qmodem.<section>.use_ubus=1`. `fxsd` and `qmodem_voip` both drive the modem
  through `ubus-at-daemon`; with the option at `0` the AT port goes to whoever
  opens it first and voice logs `AT transport failed` while the RJ11 line looks
  healthy. Unset sections are set to `1` (LuCI's default), an explicit `0` is
  left alone but logged when SIP is on.
- the fw4 include `firewall.qmodem_voip_sipd`. `qmodem-sipd` registers it from
  `/etc/uci-defaults/90-qmodem-sip-firewall`, and uci-defaults delete
  themselves; after a sysupgrade that deletion is a whiteout over the new
  image's copy, so the include never comes back and inbound SIP/RTP is dropped
  by fw4 with nothing in the log. Same failure mode as `92-byte-steering`, same
  fix: ship the repair in the squashfs with its own rc.d symlink.

SIP is configured off (`qmodem_sip.inbound.enabled=0`, `fxs.main.sip=0`) even
though the packages ship. Turning it on is two clicks; shipping an enabled SIP
listener with an empty password is not something a firmware should decide.

What the built image was checked to contain (local build, `unsquashfs -l` on
`root.squashfs`): `etc/init.d/byte-voip` + `etc/rc.d/S19byte-voip`,
`etc/init.d/byte-steering` + `S24`, `etc/init.d/qmodem_voip`,
`etc/init.d/qmodem_voip_sipd` + `S99`, `usr/sbin/qmodem_voip_sipd`,
`usr/share/qmodem_voip/module/libqvoice_media_gate.so` (32-bit ARM EABI5),
`lib/modules/6.12.94/soundcore.ko`, `usr/share/qmodem/modem_supports.json` with
the `RG500Q-EA`/`pcm_socket` profile, and `/etc/config/qmodem_sip` with both
directions `enabled '0'`. `/etc/config/network` still carries
`packet_steering '1'` / `steering_flows '32768'`, `/etc/config/fxs` `sip '0'`,
and the image's `qca-nss-ecm.init` is the patched reader (no
`disable_packet_steering`, `apply_packet_steering` called from both start and
reload).

The IPv6 overlay was checked the same way in the 1.2.32 build:
`usr/libexec/byte-v6-check` (md5 matches the repo copy), `etc/init.d/byte-v6`
with `USE_PROCD=1` / `START=98` / `--watch`, `etc/rc.d/S98byte-v6` →
`../init.d/byte-v6`, `etc/hotplug.d/iface/30-byte-v6` executable, and no
`95-byte-v6` left anywhere in the image. `odhcpd` is the 2026.06.29 build whose
`config.c` treats `ra_lifetime=0` as "unset", which is why demotion uses
`ra=disabled` plus the unreachable default instead of a lifetime-0 RA.

### LuCI pages
#### modeminfo — shared cache, SA support

The vendored `luci-app-modeminfo` does not poll the modem. `/usr/sbin/byte-status-cache`
already sends one AT batch every 10 s through qmodem's `at-daemon` and saves the
raw replies; the app parses those files on demand:

| file | contents | writer |
|------|----------|--------|
| `/tmp/aw1000-status/live` | `+QENG` serving cell, `+QCAINFO`, `+CSQ`, `+CEREG?`, `+C5GREG?`, `+QSPN`, `+CPMS?`, `+QTEMP` | byte-status-cache |
| `/tmp/aw1000-status/static` | band locks/preferences, `+CGMI`, `+CGMM`, `+CGMR`, `+CGSN`, `+QCCID`, `+QUIMSLOT?`, `+CGCONTRDP` | byte-status-cache |
| `/tmp/aw1000-status/history` | `<epoch> <mode> <lte rsrp> <nr rsrp> <lte sinr> <nr sinr>` | byte-status-cache |
| `/tmp/modeminfo` | the parsed `Key: value` snapshot | rpcd backend |

`/usr/bin/modeminfo` turns the two AT files into one `Key: value` line per
reading plus `PCC:`/`SCCn:` carrier rows, rpcd keys the scalars into JSON and
serves `history` as objects, and the JS view only draws. When neither file
exists (a box without the status service) the collector sends its own batch
with `sms_tool_q` as a last resort. Registration parsing covers both modes:

- **NR5G-SA**: `+QENG: "servingcell","NOCONN","NR5G-SA",...` — RSRP/RSRQ/SINR,
  MCC/MNC, cell ID (hex + decimal) from fields 5/6/7/13/14/15; SA servingcell
  has no LTE anchor columns, which is why the SA and NSA offsets differ.
- **NR5G-NSA**: same fields from the `"NR5G-NSA"` row (fields 2/3/5/6/7/8).
- The view shows an LTE row and a 5G NR row only when that RAT actually
  reported numbers, so a pure-SA camp never shows a row of dashes and an
  LTE-only camp never shows an empty 5G row.

`+QCAINFO` rows are typed `NR5G*` vs `LTE*` and become the CA table, with
bandwidth converted to MHz (index for `+QENG`, resource blocks for `+QCAINFO`).
IPv6 in `+CGCONTRDP` is printed as 16 dotted decimals and is regrouped for
display. Verified with `sh -n` / `node --check`, the rpcd backend against real
cache dumps using the built `jshn`, and a node render harness for LTE-only,
NSA and SA snapshots.

#### ttl page

`files/www/luci-static/resources/view/qmodem/ttl.js` overrides the app's page.
Only the wording changes: the stock text warns that enabling TTL disables NSS
offload, which is no longer what happens. The UCI schema, field names and
datatypes are identical, so `luci-app-qmodem-ttlfw4` remains the owner of the
page and of `/etc/config/qmodem_ttl`.

#### qmodem's TTL is not BYTE's TTL — the package is patched, not just overlaid

Upstream `luci-app-qmodem-ttlfw4` ships an implementation that is wrong for this
firmware in three separate ways:

| | upstream (feed) | BYTE (`files/`) |
|---|---|---|
| match | `iifname "br-lan"` | `oifname "wwan*" / "rmnet*"` |
| router-originated traffic | not rewritten (host TTL leaks) | rewritten |
| chain | `chain postrouting` — the name/hook fw4 already generates, so a reload can fail and TTL silently stops | own `chain byte_ttl` |
| NSS/ECM | `qca-nss-ecm stop`, SFE modules unloaded | never stopped; modem egress is excluded inside ECM (patch `0027`) |
| default | `enable '0'` | `enable '1'` |

`files/` is copied over the package rootfs at image assembly, so the running
system already had the BYTE version. The *package* did not: an
`opkg upgrade luci-app-qmodem-ttlfw4` (or a reinstall from the self-hosted repo)
restored upstream's script, and the unit silently lost NSS offload and the
router-originated rewrite. `apply_preset` now copies the three files into
`feeds/qmodem/luci/luci-app-qmodem-ttlfw4/{root,htdocs}/`, so the published ipk
and the image carry the same code, and a gate fails the build if the packaged
copy differs from `files/` or stops ECM again.

### Local build verification (CI is the release path, not the debugger)

A GitHub run costs about three hours and stops at the first failing package, so
every unknown used to cost a full run: ndisc6's dead URL, then ndisc6's stale
patches, then `qmi_wwan_q`'s undefined `rmnet_nss_callbacks` were three separate
runs for three one-line fixes. That is not a build process, it is a queue.

`scripts/local-verify.sh` reproduces the exact CI job locally and splits it into
ordered gates. Each gate logs to `/tmp/opencode/gate_<name>.log`, records a
stamp in `immortalwrt/.local-verify/<name>.ok`, and is skipped on re-run until
it goes green, so the loop after a fix is minutes instead of hours:

| gate | what it proves | typical cost |
|------|----------------|--------------|
| `download` | no source URL is dead or moved (`ndisc6` class) | 5-10 min |
| `tools`, `toolchain` | host tools and cross gcc build | 20-30 min |
| `config` | `make defconfig` kept every `=y` package `preset` asked for, and names the ones it silently dropped | seconds |
| `target` | qualcommax 6.12.94 plus `nss/target` patches apply and the kernel builds | 15-25 min |
| `kconf` | the *built* kernel config really has `NF_CONNTRACK_DSCPREMARK_EXT` (and `.config.override` carries it), and has no `CONFIG_BONDING` or `ECM_INTERFACE_BOND_ENABLE` left | seconds |
| `packages` | every enabled package compiles, no `*.rej`/`*.orig` anywhere, `qmi_wwan_q`'s NSS hook is guarded (no self-define, no `patches/`), `qca-nss-drv.ko` really exports `nss_rmnet_rx_get_ifnum` | 30-50 min |
| `js` | `node --check` on every shipped LuCI view | seconds |
| `image` | squashfs, sysupgrade tar and manifest assemble | 10-20 min |
| `ondemand`, `repo` | the on-demand package set and the signed opkg repo build | 20-40 min |

### Preflight: run the tree CI runs, not the tree you have
`scripts/local-verify.sh` covers the gates **after** the preset is applied. It
does not run the preset. Three CI failures in a row (`41704830850`,
`41721902711`, `41739864877`) were all defects in `apply_preset()` itself —
`sed`/`awk` matching nothing, a patch applied to rewritten source, a bare
`rmdir` returning 1 under `set -e` — and every local `make -j4` around them
passed, because it ran against a tree whose feeds had drifted from what
`apply_preset()` produces (local ndisc6 stayed `1.0.2` while CI rewrites it to
`1.0.8`). Compiling proved nothing about the step that fails.
`scripts/preflight.sh` closes that hole; it is the pre-push gate now:
```
bash scripts/preflight.sh              # apply_preset -> defconfig -> gates -> make
bash scripts/preflight.sh --no-build   # the three cheap steps, ~2 min
```
It extracts `apply_preset()` and `ci_check_packages()` from
`aw1000_byte.sh` (self-contained; the extraction takes the last `^}$` before the
next top-level function, because the function body contains a heredoc whose
terminator is a bare `}`), runs them with the same globals the script sets,
then `make defconfig` and `make -j$(nproc)`. Log: `/tmp/opencode/preflight.log`.
A push without a green preflight is how this batch burned three CI runs and
about five hours of runner time.

`config` is the gate that catches the quiet failure mode: `make defconfig`
discards a `CONFIG_PACKAGE_x=y` whose package or dependency does not exist and
prints at most a warning, so a missing LuCI app can reach the image without ever
failing a build. Its first run found ten such lines in `preset`, including a
LuCI app that no longer exists in this luci pin — see the changelog.

Only a green `repo` gate justifies a push. CI then re-confirms the same targets
and publishes the artifacts; it no longer discovers problems.

### PassWall v1 is published, never installed
`luci-app-passwall` (PassWall **v1**, Lua, `PKG_VERSION:=4.66-8`) is vendored at
`packages/luci-app-passwall` and built by `.github/build-ondemand-packages.sh`,
so the `.ipk` lands in the release's opkg repo while the image keeps only
passwall2. Reasons:

- **They cannot coexist.** Both install transparent-proxy rules on the same
  nft hook and both want port 53. Whichever reloads last wins, the other is torn
  down and its page reports "not running". Installing v1 is therefore a
  deliberate switch: disable passwall2 first, `reboot`, then enable v1.
- **Lua controllers.** v1 is `luasrc/` (pulls `luci-lua-runtime`,
  `luci-compat`, `luci-lib-jsonc`), which the image otherwise avoids.

It is **vendored, not a feed pin**, so the on-demand build compiles the exact
copy reviewed here and no `opkg upgrade` can swap it for an upstream version -
the failure mode that hit qmodem's TTL script (see above). `ondemand.txt` lists
`dns2socks`, `dns2tcp` and `microsocks` (its only hard deps the image lacks) so
Kconfig keeps the parent selectable, but they are not republished: the same
`dns2tcp 1.1.2-r1` / `microsocks 1.0.5-r2` are in the ImmortalWrt 24.10.6
packages feed that `/etc/opkg/distfeeds.conf` already carries. `dnsmasq-full`,
`chinadns-ng`, `ip-full`, `unzip`, `ipset`, `nftables-json` (provides `nft`)
and `kmod-nft-{socket,tproxy,nat}` are in the image, so v1's **Nftables
Transparent Proxy** variant works as-is and its uci-defaults auto-detects
`use_nft=1`.

Cores are pinned to **Xray only** (the Makefile's header comment says why).
Upstream turns on nine `INCLUDE_*` options for aarch64, which would make every
CI run compile v2ray-core (Go), shadowsocks-libev, shadowsocks-rust (Rust),
shadowsocksr-libev, trojan-plus, simple-obfs and haproxy, then publish ~25 MB
of cores nobody asked for. `xray-core` is already in the image for passwall2,
so v1 has a working core at zero cost; any other core is one
`opkg install shadowsocks-libev-ss-redir` (official feeds) away, and turning an
`INCLUDE_*` default back to `y` is a one-line change.

Gates assert: the package is vendored with version `4.66-8`, every heavy
`INCLUDE_*` default stays `n` while `INCLUDE_Xray` stays `y`, the four names are
in `ondemand.txt`, `luci-app-passwall` stays out of the image `.config`, and no
`src-git passwall1` line sneaks back into `aw1000_byte.sh`.

Local smoke test: `make package/luci-app-passwall/compile
package/feeds/packages/dns2tcp/compile package/feeds/packages/microsocks/compile`
gives `luci-app-passwall_4.66-8_all.ipk` (77 files,
`Depends: ... xray-core, luci-lua-runtime`), plus `dns2tcp_1.1.2-r1` and
`microsocks_1.0.5-r2`.

Two fixes to the vendored copy, both silent failures otherwise:

- `root/etc/uci-defaults/luci-passwall` arrived as `0664`, so the ipk shipped
  it non-executable. That script is what creates `/etc/config/passwall` from
  `0_default_config` and flips `use_nft` to `1`, so v1 would start with no
  config and the iptables path this image does not have. Now `0755`, and a gate
  asserts every script in the package is executable.
- The `INCLUDE_*` sub-options lacked `depends on PACKAGE_$(PKG_NAME)`, so
  `_INCLUDE_Xray=y` survived in the image `.config` with the parent `n`. Adding
  the dependency keeps them out of the image and still defaults `Xray` on for
  the on-demand build.

### IPv6: autodetect, measure, demote, restore

The first IPv6 implementation shipped a one-shot probe and could not do what
the feature promised. Four separate defects, all silent:

1. `/etc/init.d/byte-v6` had no `USE_PROCD`, so its `service_triggers()` never
   ran. `procd_add_reload_trigger "network"` was dead code and the only probe
   was the one fired ~63 s after boot. A carrier that started serving IPv6 ten
   minutes later was never noticed, and a carrier that broke later kept
   advertising a dead prefix until the next reboot.
2. Demotion wrote `dhcp.lan.ra=disabled` and `dhcpv6=disabled`, but *restore*
   re-wrote `ra=server` / `dhcpv6=server` from constants. A unit whose owner had
   deliberately disabled RA got IPv6 forced back on after a single failed
   probe, and every demotion/restore cycle wrote a different config than the
   user had.
3. `has_global_v6()` matched `inet6 2[0-9a-f]`, so a `3fff::/20` address (valid
   global unicast) counted as "no IPv6", and any PD-only carrier - delegated
   prefix present, no global address on the WAN netdev - was demoted even when
   the prefix routed perfectly.
4. Demotion also flushed the br-lan global addresses and added a bogus
   `default dev wwan0_1 metric 2048`. The route lost against netifd's own
   `::/0` at metric 11, so IPv6 traffic still went into the black hole, while
   the flush broke LAN-local IPv6 and made a restore depend on odhcpd
   renumbering the LAN.

The rewrite keeps one decision point (`/usr/libexec/byte-v6-check`) and gives
it three modes: one-shot (manual/fallback), `--watch` (procd service), and
`--kick` (hotplug and reload). Design points:

- **Autodetect.** `ensure_wanv6()` recreates `network.wanv6` when qmodem has
  deleted it, and `ifup wanv6` is retried while the interface settles. Every
  round also re-asserts the MAC-derived link-local on the WAN netdevs, because
  qmi_wwan_q hands every mux interface the base MAC and odhcp6c cannot send a
  SOLICIT without a source.
- **Real connectivity, three probes.** ICMPv6 to two anycast resolvers, then a
  source-bound ICMPv6 for PD-only carriers, then an HTTP GET over IPv6
  (`uclient-fetch -6`, numeric URL) for networks that drop ICMPv6. Busybox
  `nc` is built without `NC_EXTRA`/`NC_110_COMPAT`, so it has no `-w` and no
  family switch - "TCP handshake with a timeout" is not available there;
  `uclient-fetch` is, and it is in the image.
- **PD-only is not a failure.** A delegated prefix with no WAN address is
  probed from a LAN address that belongs to that prefix. The carrier routes
  the prefix to the CPE, so replies arrive; without this step every PD-only
  carrier would look broken.
- **Debounce.** Two consecutive agreeing rounds.
- **Demotion is fail-fast, not fail-silent.** `unreachable default metric 1`
  wins over netifd's `::/0` at metric 11, so both forwarded and
  router-originated IPv6 get an immediate ICMPv6 unreachable and applications
  fall back to IPv4 at once. The br-lan addresses are left in place: the ULA
  is what keeps LAN-local IPv6 working, and a restore that re-adds a prefix
  captured before the outage can re-add a prefix that no longer exists.
- **Restore is a snapshot, not a guess.** `/etc/byte/v6.state` records the
  previous `dhcp.lan.ra` / `dhcp.lan.dhcpv6` including "the key did not
  exist", and restore puts exactly that back (`uci delete` for an absent key).
  The state file lives in `/etc`, so a demotion that spans a reboot is still
  restored correctly.
- **Cadence.** 300 s while healthy, 30 s while demoted, plus `--kick` from
  `/etc/hotplug.d/iface/30-byte-v6` and from a procd raw interface trigger.
  The 95-byte-v6 hotplug runner that started a second one-shot check per ifup
  is gone: two concurrent uci commits against `dhcp` are not safe, and the
  watcher already owns the decision.

`odhcpd`'s `ra_lifetime=0` would be the neatest way to withdraw only the
default route while keeping the LAN prefix advertised, but this odhcpd treats
`0` as "unset" (`config.c`: `if (ra_lifetime != 0)`), so it cannot express it.
`ra=disabled` is the honest signal: clients stop being told to use IPv6 at
all, and the fail-fast route covers the window before their old RA expires.

Verified in a stub harness (fake `uci`/`ip`/`ifstatus`/`ping6`/`wget` driving
the real script), not on hardware: demote writes the snapshot and the three
changes; a repeat round does not churn; restore deletes the keys that were
absent and keeps `ra=disabled` when that was the owner's choice; PD-only with a
working source-bound probe never demotes; `--kick` starts the service when no
watcher holds the pidfile. The watcher's first `trap` did not `exit`, so
`SIGTERM` (procd stop) left it running - fixed to `trap 'exit 0' INT TERM`.

### Open items
- **IPv6 policy is not verified against a live carrier.** What to check on the
  unit: `logread | grep byte-v6` shows the watcher line at boot plus one
  verdict; `ubus call network.interface.wanv6 status` has the same
  `ipv6-prefix` before and after demotion; `ip -6 route | grep unreachable`
  shows the metric-1 route only while demoted; `uci get dhcp.lan.ra` returns
  `disabled` while demoted and the unit's original value after the carrier
  starts passing traffic; `ping6 -c2 2001:4860:4860::8888` on the router fails
  immediately (not after 30 s) while demoted. Delete `/etc/byte/v6.state` to
  simulate a lost snapshot, and reboot while demoted to confirm restore still
  works across a reboot.
- **Untested on hardware.** The changes are build-validated only. Needed on a
  spare unit: `logread | grep byte-selfcheck`, `nss-offload status`, and a
  tcpdump on the modem netdev confirming TTL 64 for both forwarded and
  router-originated traffic.
- **ECM 12.5 on 6.12.94 with bonding off**: compiled locally (ipk produced);
  hardware test still pending.
- **ECM state device** availability at boot is assumed from source, not seen.
- **CPU distribution and the WAN queue bound are build-verified only.** On the
  unit: `logread | grep byte-affinity` must show exactly one `applied=N rps=0f
  rfs=32768 napi=2/20000 xps=... fq=wwan0_1=1981/100` line at boot and nothing
  afterwards while idle (a repeated line means an idempotent write regressed);
  `/sys/class/net/wwan0_1/queues/rx-0/rps_cpus` reads `f`, `rps_flow_cnt`
  `32768`, `napi_defer_hard_irqs` `2`, `gro_flush_timeout` `20000`, and
  `tc qdisc show dev wwan0_1` says `fq ... limit 1981p flow_limit 100p
  initial_quantum 65536`. Then compare `/proc/interrupts | grep xhci` and
  `/proc/softirqs` before and after a 100 MB download: the IRQ count should grow
  slower than the packet count and NET_RX should spread over four CPUs instead
  of one. `byte-fq-measure` run idle and under a saturating upload is the
  latency proof: `backlog` should stay in the low hundreds instead of thousands,
  and p99 should not grow by more than `flow_limit` allows.
- **`busy_poll`/`busy_read` and the neighbour tables are unmeasured.** They are
  asserted by `byte-selfcheck` (`busy_poll`, `busy_read`, `neigh.gc_thresh3`,
  `neigh6.gc_thresh3`), which proves the kernel accepted them, not that they
  help. A before/after on LuCI response time and DNS lookups under load is the
  only honest way to claim anything.
- **`kpti=off` is not shipped, on purpose.** The built kernel has
  `CONFIG_UNMAP_KERNEL_AT_EL0=y`, so every syscall and interrupt entry pays a
  page-table swap on this Cortex-A53, and the WAN path is deliberately not
  offloaded - CPU there is throughput. Disabling it would be the last
  measurable CPU win, but it needs a kernel command line change (a reflash, not
  a sysctl) and it is a security downgrade on a box facing the internet. Decide
  with numbers: `mitigations=off` A/B on a spare unit, sysbench or a plain
  `iperf3` through the WAN path, before/after. If it is ever taken, it belongs
  in this section with the measured delta, not in a silent config line.
- **`multicast_to_unicast` on the WiFi interfaces is not enabled.** It would stop
  multicast being sent at the lowest basic rate to every client, which is a real
  airtime win, but it changes how IPTV multicast reaches WiFi clients - the
  exact path the bridge snooping work above fixed. Ship it only with an IPTV
  regression test on the unit (zap through 5-10 channels, confirm no freeze and
  no `multicast hash table full`), and only on 5 GHz first.
- **Recovery path unconfirmed** on the target unit (no serial session yet), so
  no image has been flashed from this branch.
- **SIP ringing and audio not yet verified on hardware.** Build-level evidence
  only: `ubus call qmodem_voip status`, `ubus call qmodem.sip status`,
  `logread | grep -E 'fxsd|qmodem_voip'`, and a real inbound call answered on
  the RJ11 phone and on a Linphone/Zoiper client (PCMA), plus a call answered
  on SIP while the RJ11 phone still rings. Needs a SIM with VoLTE registered
  (`AT+QCFG="ims"` → `1,1`) and `AT+QCFG="call_control"` at `0,0`.

## Credits

ImmortalWrt, OpenWrt, [qosmio/nss-packages](https://github.com/qosmio/nss-packages),
[VizzleTF/luci-theme-footstrap](https://github.com/VizzleTF/luci-theme-footstrap),
[XT-Martinez/aw1000-feed](https://github.com/XT-Martinez/aw1000-feed) (dashboard widgets),
[Perz3us/openwrt-aw1000-phone](https://github.com/Perz3us/openwrt-aw1000-phone),
QModem, [Openwrt-Passwall](https://github.com/Openwrt-Passwall),
[nikkinikki/OpenWrt-nikki](https://github.com/nikkinikki-org/OpenWrt-nikki),
[dotywrt/dotycat-package](https://github.com/dotywrt/dotycat-package) (Netstat),
[SolomonRicky/luci-app-modeminfo](https://github.com/Ace1337z/luci-app-modeminfo).

**Licensing.** The Skyworks ProSLIC DSP patch is proprietary and not
redistributable; the QCA NSS driver and firmware carry the Qualcomm licence.
Review both before republishing an image built here.

## Changelog

### 1.2.x — 2026-11-04
- **Latency: the WAN egress queue is bounded instead of left at 15 MB.**
  `byte-affinity` used to stop at "the qdisc is `fq`", which meant the kernel
  default `limit 10000` packets - ~15 MB of queue, 0.6 s of delay at 200 Mbit/s
  once a client runs parallel uploads (the per-flow cap only bounds one flow).
  It now sizes the queue from the bearer:
  `limit = 3 * uplink_kbit * rtt_ms / 12112` = 1981 packets at 200 Mbit/s and
  40 ms, `flow_limit=100`, `initial_quantum=65536`, and re-applies it whenever
  the live parameters differ. No shaping: no rate ceiling, no classification.
  Knobs are in the new `/etc/config/byte` (`byte.fq.*`), so re-sizing for a
  different SIM needs no reflash; `enabled=0` restores the old behaviour. The
  boot log line now carries `fq=wwan0_1=1981/100` next to the RPS masks.
  **Verified:** a host harness (`/tmp/opencode/fqtest.sh`, 21 cases) covers the
  sizing maths, the clamp at both ends, the non-numeric and missing values, the
  `enabled=0` path, the "already correct, do not rewrite" path - a rewrite
  resets the qdisc and zeroes its counters, and this runs from a 60 s timer -
  and the parsing of real `tc qdisc show` output, where a pattern match would
  read `flow_limit` as `limit`.
- **Latency: `busy_poll=50` / `busy_read=50`.** Opt-in per socket
  (`SO_BUSY_POLL`/`SO_BUSY_READ`), so forwarded traffic never spins; the point
  is the router's own userspace networking - dnsmasq, AdGuard Home, Xray in
  PassWall, qmodem's AT readers - where a wakeup costs more than the packet.
- **Robustness: neighbour tables sized 512/2048/4096 for IPv4 and IPv6.** The
  default 1024-entry ceiling is reachable with a dozen WiFi clients plus their
  ND entries, IPTV groups and QModem's virtual interfaces; when it is reached
  the kernel collects live entries and the first packet to a known host briefly
  goes nowhere. ~256 KB of table on 884 MB.
- **Doc fix: the `netdev_budget_usecs` comment was wrong.** `sysctl.conf` claimed
  the key is read-only on 6.12. It is `0644`; its *minimum* is
  `2 * USEC_PER_SEC / HZ`, which is 20000 us at `CONFIG_HZ=100`, so the
  `EINVAL` was a floor, not a lock. The behavioural conclusion stands (`sysctl
  -p` still aborts the rest of the file on that error) but the reason matters:
  the old comment would have anyone conclude the knob is dead upstream instead
  of floor-bound by this image's HZ. `CONFIG_HZ` itself is left alone - the RX
  budget (2400 packets) is exhausted in ~3-5 ms, long before the 20 ms time
  limit, so a rebuild would buy nothing measurable; the reasoning is in "The
  WAN queue is bounded, not shaped".
- **New `byte-fq-measure`.** Read-only: prints qdisc parameters, backlog, drops,
  the live sysctls, and p50/p95/p99 to the gateway and `1.1.1.1`, to be run
  idle and during a saturating upload. It changes nothing.
- **Self-check extended:** `busy_poll`, `busy_read`, `neigh.gc_thresh3`,
  `neigh6.gc_thresh3` and the live `flow_limit` on each `fq` modem interface are
  asserted now, with the aggregate `limit` logged beside it.
- **Deliberately not done:** `kpti=off` (security downgrade plus a command line
  change) and `multicast_to_unicast` (needs an IPTV regression test). Both are
  in open items with what it would take to decide them.
- **Size:** sysupgrade `35,318,569` → `35,328,809` bytes (+10,240); rootfs
  squashfs `30,054,525` → `30,059,409` (+4,884). The two new files are 1.4 KB
  (`/etc/config/byte`) and 3.2 KB (`/usr/sbin/byte-fq-measure`); squashfs
  compression absorbs the rest. `make` exit 0 through `scripts/preflight.sh`
  (apply_preset, defconfig 1051 `=y`, `ALL REQUIRED PACKAGES PRESENT IN .config`,
  image assembled), no `*.rej` in the tree, manifest still
  `ndisc6 - 1.0.8-r1`, `kmod-qmi_wwan_q - 6.12.94.1.5-r2`.
- **Build fix: `rmdir` aborted `apply_preset()` under `set -e`, and local
  verification now runs `apply_preset()` itself.** Run `41739864877` died eight
  minutes in, one line after `ndisc6: 1.0.2 -> 1.0.8 ...`, with no message:
  the new cleanup did `rmdir "$(dirname "$qms")/../patches" 2>/dev/null`, and a
  bare `rmdir` returns 1 when the directory is already gone. The script runs
  under `set -e`, so the function aborted silently; `2>/dev/null` hid the
  reason. Both calls carry `|| :` now (also `rm -f`), and only the obsolete
  `0001-disable-qca-nss-hook.patch` is removed, so a future feed pin may still
  ship patches of its own.
  The deeper problem was the verification, not the bug: local `make` had been
  run on a tree whose feeds had **drifted** from what `apply_preset()` produces
  (local `feeds/qmodem/application/ndisc6/Makefile` was still `1.0.2` while CI
  rewrites it to `1.0.8`), and it never executed `apply_preset()` at all — so
  all three CI failures of this batch were in steps local compiles never
  touched. New `scripts/preflight.sh` runs the real sequence against the real
  tree: extract `apply_preset()` + its helpers from `aw1000_byte.sh`, run it,
  `make defconfig`, run the extracted `ci_check_packages()`, then `make -jN`.
  It is now the pre-push gate. **Verified:** all four steps green locally
  (1051 `=y` lines, `ALL REQUIRED PACKAGES PRESENT IN .config`), image
  `35,318,569` bytes, rootfs squashfs `30,054,525`, manifest
  `ndisc6 - 1.0.8-r1`, `kmod-qmi_wwan_q - 6.12.94.1.5-r2`, no `*.rej`/`*.orig`.
- **Build fix: the `qmi_wwan_q` patch is retired, the driver guards the NSS hook
  itself.** The qmodem pin `b4effcd` rewrote `qmi_wwan_q.c`: it no longer
  `#define CONFIG_QCA_NSS_DRV` on IPQ807x, every NSS use now sits behind
  `#ifdef CONFIG_QCA_NSS_DRV`, and the kernel config never sets that symbol, so
  `nss_cb` stays `NULL` and `rmnet_nss_callbacks` is never referenced. The repo
  patch that deleted the two `#define` lines therefore had no context left and
  `apply_preset()` still ran the `$(Build/Patch)` injection, so run `41721902711`
  died at `Hunk #1 FAILED at 58` / `Hunk #2 FAILED at 72`, 1 h 42 m in, after
  ndisc6 had been fixed. The patch file is deleted from the `nss/` overlay, the
  `$(Build/Patch)` injection is gone (the package still overrides
  `Build/Prepare` and still never patches anything), and `apply_preset()` now
  `rm -rf`s any leftover `patches/` plus asserts the driver source: a bare
  `#define CONFIG_QCA_NSS_DRV` is an error, the `#ifdef` guard is required. Both
  checks run before compilation, so a feed bump that reverts the driver fails in
  seconds instead of at modpost an hour in. Verified locally with a from-scratch
  rebuild of the package: `nm -u qmi_wwan_q.ko` reports zero `nss` symbols and
  the packaged source is byte-identical to the feed (`cmp`). **Size:** unchanged
  - sysupgrade `35,318,569`, rootfs squashfs `30,054,513` on the first build,
  `30,054,525` after re-running the whole pre-build chain (12 bytes of rebuild
  jitter, no code change); the patch never reached the image (it removed lines,
  and it was never applied on this tree).
- **Build fix: ndisc6 is pinned by `PKG_HASH` now.** OpenWrt renamed
  `PKG_MD5SUM` to `PKG_HASH` and the qmodem feed copy followed, so the
  `sed`-based pin in `apply_preset()` matched no line and run `41704830850`
  stopped at `ndisc6: could not pin 1.0.8` - before compiling anything. The
  rewrite is key-based (`awk`): version 1.0.8, https URL, exactly one SHA256
  `PKG_HASH` right after the URL, any `PKG_MD5SUM` line dropped (two hashes is
  an error in package.mk), c99 flag dropped, `patches/` removed. The CI gate
  accepts either spelling but forbids the MD5 key, so a tree carrying both
  cannot pass. Verified locally by compiling the package and the full image
  (`ndisc6 - 1.0.8-r1` in the manifest). **Size:** rootfs squashfs `30,054,417`
  → `30,054,513` bytes (+96); sysupgrade unchanged at `35,318,569`.
- **All four cores, no SQM: RPS/RFS kept, NAPI deferral added, XPS told the
  truth.** The modem's xhci interrupt cannot leave one core (the kernel
  collapses `effective_affinity`), so the work moved instead of the IRQ:
  `wwan*`/`rmnet*` RX queues carry RPS mask `0f` and `rps_flow_cnt=32768` on
  every core, and the modem netdev now gets `napi_defer_hard_irqs=2` with
  `gro_flush_timeout=20000` ns so the single hard IRQ stops firing per packet
  (upstream's own `netdev_sw_irq_coalesce_default_on()` values; usbnet never
  asks for them, which is why they were 0). XPS is now probed per device instead
  of assumed: qmi_wwan mux interfaces have one tx queue and the kernel rejects a
  multi-CPU mask, so the verdict is cached and logged
  (`xps=wwan0=unsupported`) rather than rewritten forever. `fq` is asserted on
  the modem netdev - `default_qdisc` only covers devices present at boot, and
  the wwan mux appears after dial - so BBR actually paces. Every sysfs write is
  now idempotent and numeric (`f` vs `0f`), because rewriting an unchanged
  `rps_cpus` still allocates a steering map and schedules `call_rcu`: steady
  state is zero writes, zero `tc` forks, no log spam. The self-reload timer
  drops from 15 s to 60 s; hotplug and the netifd raw trigger already cover
  redial. Latency without SQM stays with `fq` + BBR, plus four fail-fast keys
  that only change time-to-notice on a lossy bearer:
  `tcp_no_metrics_save=1`, `tcp_syn_retries=3`, `tcp_synack_retries=3`,
  `tcp_retries2=8`. `byte-selfcheck` now reports the NAPI/GRO values and the
  four TCP keys. **Size:** sysupgrade `35,318,569` → `35,318,569` bytes (padding
  absorbs it), rootfs squashfs `30,052,777` → `30,054,417` bytes (+1,640).
- **IPv6 autodetect, real health check, self-restoring fallback.** The old
  `byte-v6` service was a one-shot probe whose `service_triggers()` never
  registered (no `USE_PROCD`), so a failed probe stuck until reboot and a
  carrier that started working later was never noticed. It is now a procd
  watcher (`START=98`, respawn, `--watch`) kicked by
  `/etc/hotplug.d/iface/30-byte-v6` and by a raw `interface.*` trigger;
  `ensure_wanv6()` recreates `network.wanv6` when qmodem has deleted it and
  retries `ifup wanv6`. The health check measures traffic, not configuration:
  ICMPv6 to `2001:4860:4860::8888` and `2606:4700:4700::1111`, a source-bound
  ICMPv6 probe from the delegated prefix for PD-only carriers, and an HTTP GET
  over a numeric IPv6 URL (`uclient-fetch -6`; busybox `nc` has no `-w` in this
  image) for networks that drop ICMPv6. Two consecutive agreeing rounds are
  required, and while demoted it re-probes every 30 s (300 s when healthy) so
  IPv6 comes back by itself. Demotion now sets `dhcp.lan.ra`/`dhcpv6` to
  `disabled`, writes `gai.conf` and installs `unreachable default metric 1` -
  metric 1 beats netifd's `::/0` at 11, so IPv6 fails immediately instead of
  blackholing. The br-lan ULA is no longer flushed (it keeps LAN-local IPv6
  working) and restore replays the *snapshot* in `/etc/byte/v6.state`,
  including "the key did not exist", so a user's `ra=disabled` is never
  overwritten. The `95-byte-v6` hotplug one-shot runner is removed; two checks
  committing uci at once was the race. **Size:** sysupgrade `35,328,809` →
  `35,318,569` bytes (-10,240), rootfs squashfs `30,058,085` → `30,052,777`
  bytes (-5,308): two small scripts in, one hotplug script out.
- **SIP calling on the AW1000 phone port, and QModem moved to 3.4.0_rc3.**
  The qmodem feed pin moves from the `v3.3.0` tag to `b4effcda` on `main`,
  because AW1000 voice support (`FUjr/QModem#290`, RG500Q-EA over
  `/var/run/fxsd/pcm.sock`) only exists there: the `v3.4.0_rc3.1` tag's
  `modem_supports.json` has no RG500Q-EA entry, so `qmodem_voip` would start and
  refuse every call. That pin is also what brings `ubus-at-daemon` to
  `3.4.0_rc3`, the >= 3.4.0 that QModem voice and fxsd's SIP mode require (the
  version comes from `feeds/qmodem/version.mk`). The image now ships
  `qmodem-voip`, `qmodem-sipd`, `luci-app-qmodem-voip`, the `qmodem-smsd` stack
  that `luci-app-qmodem-sms` depends on since 3.4.0, plus `alsa-lib`,
  `kmod-sound-core`, pjproject and `adb`. `sms-forwarder` is dropped and
  `sms-forwarder-next` takes its place: the two declare `PKG_CONFLICTS` on each
  other, so the image would not assemble with both. Service state stays off by
  default; `/etc/init.d/byte-voip` (START=19) only prepares what an upgraded
  unit cannot repair by itself (see *Engineering log → QModem voice*).
  **Cost, measured on this build:** sysupgrade image `33,362,729` →
  `35,328,809` bytes (+1.87 MiB), rootfs squashfs `30,058,085` bytes. The
  additions, uncompressed: `libstdcpp6` 2.06 MB (`adb`), `alsa-lib` 1.31 MB,
  `libmbedtls21` 720 KB, pjproject 1.82 MB total (libpj 260 KB, libpjlib-util
  180 KB, libpjmedia 450 KB, libpjnath 220 KB, libpjsip 410 KB,
  libpjsip-simple 120 KB, libpjsip-ua 140 KB), `kmod-sound-core` 500 KB,
  `libsoxr` 130 KB, qmodem voice/sms daemons ~360 KB. Removed: `qmodem-seal`
  30 KB, `sms-forwarder` 50 KB, `libsodium` 280 KB. pjproject's dependency
  chain is why the whole set is required: `qmodem-sipd` links
  `libpjsip-ua` → `libpjsip-simple` + `libpjmedia` → `libpjnath`, and
  `qmodem-voip` links `-lasound` even on the RG500Q (which uses the fxsd PCM
  socket, not ALSA). Dropping `alsa-lib`/`adb` would mean patching the
  upstream packages - a fork, not a build option.
- **Packet steering stays on: `qca-nss-ecm` no longer owns the switch.** On the
  flashed 1.2.30 unit `network.@globals[0].packet_steering` read `0` and
  `steering_flows` was absent, while the image's `/etc/config/network` said
  `1`/`32768`. ECM's init runs at START=26 (and on every `network` reload) and
  called `disable_packet_steering()` - `uci set ...=0`, `uci del
  ...steering_flows`, then `packet-steering.uc -l 0 0`. The one-shot
  `92-byte-steering` had already deleted itself, so nothing put the values
  back. `apply_preset()` now rewrites that ECM block into a reader that
  re-applies whatever UCI says (default 1) and never writes UCI, and the build
  fails if `disable_packet_steering` or `packet_steering=0` returns. A new
  `/etc/init.d/byte-steering` (START=24, before netifd's `packet_steering` at
  25) ships its own `S24` rc.d symlink, because `/etc` is preserved on
  sysupgrade and neither the uci-defaults script nor `/etc/rc.local` can repair
  an upgraded unit. Gates assert the ECM rewrite, the service's order and
  values, the symlink, and the image's `packet_steering '1'` /
  `steering_flows '32768'`. Details in *Engineering log -> Packet steering has
  one owner*.
- **PassWall v1 is published on demand, never installed.** `luci-app-passwall`
  (v1, Lua, `4.66-8`) is vendored at `packages/luci-app-passwall` and built by
  `build-ondemand-packages.sh`, so the ipk ships in the opkg repo while the
  image keeps passwall2 only - the two install the same transparent-proxy
  rules and both want port 53, so running both tears one down and its page
  reports "not running". Vendored rather than feed-pinned, so `opkg upgrade`
  cannot swap it for an upstream copy (the failure mode that hit qmodem's TTL
  script). `ondemand.txt` lists only `dns2socks`, `dns2tcp`, `microsocks`
  (kept selectable in Kconfig, not republished - the same versions are in the
  ImmortalWrt 24.10.6 feed distfeeds already points at); dnsmasq-full,
  chinadns-ng, ip-full, unzip, ipset, nftables-json and
  kmod-nft-{socket,tproxy,nat} are already in the image, so the nftables
  variant works as-is. Build defaults are pinned to **Xray only** instead of
  upstream's nine `INCLUDE_*` defaults for aarch64, which would add a Go +
  Rust + C core build to every CI run and ~25 MB of repo assets for nothing
  (xray-core is already in the image). Smoke-built locally: ipk contains 77
  files and depends on `xray-core` + `luci-lua-runtime`; `dns2tcp` and
  `microsocks` build too. Gates cover the vendored version, the pinned core
  defaults, the on-demand names, the image exclusion, the absence of a
  `src-git passwall1` line, and that every packaged script is executable (the
  vendored uci-defaults script arrived `0664` and would have skipped both
  `/etc/config/passwall` creation and the nftables auto-detect).
- **qmodem's TTL is replaced at the package level, not only in the image.**
  Upstream `luci-app-qmodem-ttlfw4` matched `iifname br-lan` (router-originated
  packets kept the host TTL), wrote its own `chain postrouting` (fw4 generates
  that name itself, so a reload can fail and the rewrite silently stops), ran
  `qca-nss-ecm stop`, and shipped `enable '0'`. `files/` already replaced what
  runs at boot, but the package still carried the upstream copy - so an
  `opkg upgrade luci-app-qmodem-ttlfw4` reinstalled it and the unit lost NSS
  and the router-originated rewrite without saying anything. `apply_preset`
  now patches the three package files (init script, `/etc/config/qmodem_ttl`,
  `ttl.js`) so the published ipk and the image match, and a gate fails if the
  packaged script diverges or stops ECM again.
- **Releases are named after the build, not "FINAL".** The publish step had a
  hardcoded tag (`BYTE_by_ACE-FINAL-...`) and title (`BYTE by ACE — FINAL`), so
  every build landed under the same name regardless of what it contained. Tag,
  title and body header are now derived from the built `.config`
  (`CONFIG_VERSION_CODE` / `CONFIG_VERSION_NUMBER`, written by
  `apply_version()`), the same strings the image filename and LuCI → Status
  report:
  `BYTE_by_ACE-<code>-<branch>-<run>` /
  `BYTE <release> VERSION <code> — AW1000 (ImmortalWrt <branch>, build <run>)`.
  The step fails if the version cannot be read, and fails again if the notes
  header does not match the tag it is about to publish.
- **Release notes describe the current build.** `release-notes-final.sh` no
  longer prints a static body (it claimed "FINAL", kernel 6.12.112 and 24.10.6
  feeds for months). Version, kernel and release come from the built `.config`
  and the change list is the newest `README.md` changelog block, with a
  `git log` fallback for tarball exports. A stale body cannot be published,
  because the header is checked against the tag.
- **IPTV: multicast now follows the port that joined it.** The `wan` port is a
  bridge member, so a set-top box shares L2 with `lan1..lan4`; with snooping off
  every HD channel was flooded to every port *and* to the WiFi APs, and with no
  querier the group aged out mid-programme. `br-lan` now carries
  `igmp_snooping=1`, `multicast_querier=1` (the bridge queries for itself, so no
  daemon) and `hash_max=4096` (netifd's 512-entry default overflows on a full
  channel list and the kernel falls back to flooding). `93-byte-multicast` is
  the upgrade path; keys are only written when absent.
- **`udp-broadcast-relay-redux` is deleted from the preset and gated.** It was
  never in the image - the entry was a dead `is not set` line - but a daemon
  that re-broadcasts every UDP packet to every bridged port is exactly what
  breaks IPTV on a busy LAN. The build now fails if it comes back through a
  dependency or a preset refresh.
- **Packet steering: the upgrade path now turns it on.** Images up to 1.2.0
  shipped `packet_steering '0'`, and sysupgrade without `-n` keeps
  `/etc/config/network`, so upgraded units kept showing *Packet Steering:
  Disabled* and `byte-selfcheck` logged `steering.enabled 1 0` on every boot.
  `92-byte-steering` re-asserts `packet_steering=1` and `steering_flows=32768`
  once, logs the change and restarts the service; `rps_sock_flow_entries` and
  the RFS flow table depend on both. Necessary but not sufficient: ECM
  re-disabled it after the script had run, see the newest entry and
  *Engineering log -> Packet steering has one owner*.
- **Branding: the header says BYTE and wears the B mark.** The theme prints the
  hostname as the wordmark, so the hostname became `BYTE` (was `BYTE_by_ACE`);
  `91-byte-identity` migrates upgraded units and leaves a self-chosen hostname
  alone. The logo could not be fixed with CSS - the theme hardcodes the OpenWrt
  arcs as inline SVG - so
  `files/usr/share/ucode/luci/template/themes/footstrap/partials/brand.ut`
  overrides the theme partial with the same "B" geometry as `logo.svg`, drawn in
  `currentColor` plus the accent underline so it reads on both palettes. A gate
  fails the build if the theme stops shipping or including that partial.
- **luci-app-byte now states what it is for.** It is the AdGuard Home +
  PassWall2 DNS setup page, sitting under Tools next to unrelated apps, and its
  main button moves dnsmasq off port 53: the page opens with an intro banner
  saying so (and where PassWall2 nodes, TTL and modem settings actually live),
  and the menu entry is *BYTE (AdGuard Home + PassWall2)*. A gate asserts both
  strings stay.
- **luci-app-byte: false "not installed" on a working AdGuard Home.** The rpcd
  backend decided "installed" from `/usr/bin/AdGuardHome` and `/usr/sbin/
  AdGuardHome` only. A manual tarball install, a LuCI-app self-update or a
  relocated `adguardhome.config.config_file` left the binary somewhere else, so
  the header badge said *Not installed* while the service was answering on
  port 53. Detection is now four-way - binary (five known paths plus `PATH`),
  init script, YAML config, package metadata (`opkg`/`apk`) - and the version
  falls back to the package version when the binary cannot be executed. The
  YAML path itself is resolved from `uci get adguardhome.config.config_file`
  first, so `web`/`dns_port` are read from the file the service actually uses.
- **UI: page headers moved below the cards in luci-app-byte and
  luci-app-modeminfo.** LuCI pins its toolbar to the top of the viewport; a
  hero rendered as the first child ended up underneath it and both the title
  and the status badge/controls were clipped. Order is now cards, hero, footer
  in both apps.
- **Removed luci-app-vnstat2 ("Traffic Monitor").** Two frontends over one
  vnstat database: *Status → Traffic Monitor* (upstream app) and *Tools →
  VnStats* (the vendored dotycat app, patched for vnstat 2.13). Only the
  patched one stays; `vnstat2`/`vnstati2` binaries remain because netstat needs
  them. Drops the app's views and its `zh-cn` translation. The preset entry and
  its i18n symbol are now `is not set`, with a gate that fails the build if the
  app creeps back.
- **Kept `udp-broadcast-relay-redux` out of the image.** It was never shipped -
  the preset carried only a dead `is not set` line from the original upload -
  but the entry is now deleted outright and gated. The daemon re-floods every
  UDP broadcast onto every bridged port, so attaching an IPTV box (continuous
  IGMP joins, multicast-heavy streams) saturates the LAN bridge and playback
  stalls. IPTV belongs on a dedicated port/bridge with multicast snooping, not
  behind a relay daemon.
- **modeminfo: rewritten to read the shared status cache; CA table, per-RAT
  signal rows, trends.** The page used to run its own AT batch through
  `sms_tool_q` on every poll. That was wrong twice over: two processes reading
  one tty interleave replies and both parse each other's output, and the batch
  costs six round trips per refresh even though `byte-status-cache` already
  polls the same modem every 10 s through qmodem's `at-daemon`. The collector
  (`/usr/bin/modeminfo`) now parses `/tmp/aw1000-status/{live,static}` and only
  falls back to its own AT poll when those files do not exist at all. The rpcd
  plugin caches the parsed snapshot in `/tmp/modeminfo`, re-parses when
  `live` is newer, and serves `history` straight from
  `/tmp/aw1000-status/history`. Result: the page refreshes as often as the UI
  likes without touching the serialiser, and several browser tabs are free.
  The view itself gained a carrier-aggregation table (PCC/SCC with RAT, band,
  bandwidth, ARFCN, PCI, RSRP), separate LTE and 5G NR signal rows so the two
  RATs can never be read against the wrong label, RSRP and SINR trend
  sparklines, and Cell/Data/Modem cards. `+CGSN` was added to the cache's
  static batch so IMEI shows up, and history depth went from 31 to 180 samples
  (about 30 minutes). Two parser bugs surfaced while testing against real
  cache dumps: NR/LTE bandwidth in `+QENG` is an index (0-5 / 0-14) while
  `+QCAINFO` carries resource blocks, and the RG500Q answers `+CGMI/+CGMM/
  +CGMR/+CGSN` with bare lines instead of the `+X: ` prefix. Both handled.
  Verified offline: the rpcd backend against real cache samples with the
  built `jshn`, plus a node render harness for LTE-only, NSA and SA data.
- **WAN IPv6: found and fixed the missing mux link-local; data path still dies
  at the modem.** Chasing "IPv6 does not work" turned up a real bug first:
  `wanv6` could not even run its DHCPv6 exchange, because `wwan0_1` had no
  link-local address - `qmi_wwan_q` hands the mux the base interface's MAC, so
  the EUI-64 address it would generate is already owned by `wwan0`, and the
  interface stayed without `fe80::`. Every SOLICIT and RS then failed with
  `Address not available`. `byte-v6-check` now adds a unique MAC-derived
  link-local before it waits for `wanv6`, after which DHCPv6 completes and the
  gateway is reachable. Above that, IPv6 still does not pass traffic through
  this modem: only the modem's own gateway answers, the ISP resolver behind it
  does not, `Ip6OutRequests` rises with `Ip6InReceives` flat, and
  `AT+QMAP="wwan"` reports `"IPV6","0:0:0:0:0:0:0:0"`. That is the case the
  watcher demotes: probe fails twice, `dhcp.lan.ra`/`dhcpv6` go to `disabled`,
  `gai.conf` prefers IPv4 and `unreachable default metric 1` makes IPv6 fail
  fast; the br-lan ULA stays. It re-probes every 30 s and restores from
  `/etc/byte/v6.state` the moment the modem starts passing IPv6. Details in
  Known limits and *Engineering log → IPv6: autodetect, measure, demote,
  restore*.
- **Dashboard: NSS offload card replaced by Storage; bottom tabs and the layout
  editor hidden.** The NSS counter only refreshes while the NSS clock scales
  itself and clock scaling is off here, so the card always read 0. The card now
  reports overlay used/total from `system.info()` (`root`/`tmp` are in KB) with
  a capacity bar plus a `/tmp` line, and keeps the widget id `nss` so
  `/etc/config/dashboard` written by an older image still resolves - renaming
  the id would silently empty the card row on every upgraded unit. The five
  charts stay. The detail tabs (Internet/Mobile/System/DHCP/Resources) and the
  Layout tab all live in one `.cbi-map` that the dashboard appends after the
  charts, so the shipped `custom.css` hides `.Dashboard > .cbi-map`. That file
  is a copy of luci-mod-dashboard's own stylesheet (it loads exactly that one
  path) with the BYTE rules appended; re-sync it when the feed moves. Verified
  in a headless browser against the live unit: the Storage card reads
  `30.4 MiB / 584.6 MiB`, `overlay · 5% used`, the bar fills 5.2%, and the
  `.cbi-map` computes `display: none`.
- **Netstat: replaced with dotycat's app, patched for vnstat 2.x.** The old
  vendored fork parsed vnstat 1.x text: `DD/MM/YY` dates, `Mon 'YY` months and
  one database file per interface under the database directory. ImmortalWrt
  25.12 ships vnstat2 2.13, which prints ISO dates (`2026-07-02`, `2026-07`),
  keeps every interface in a single `vnstat.db`, and lists interfaces only
  through `vnstat --iflist`. Unpatched, the page rendered an empty selector and
  `0 B` - the reported "netstat does not work". The view now prefers
  `vnstat --json` through `luci.jsonc` (so the selector offers only interfaces
  that actually have data, not `gre0`/`teql0`/`dummy0`), falls back to
  `--iflist`, then to the 1.x per-file layout, and accepts both date formats.
  `Makefile` depends on `+vnstat2 +curl +luci-compat` (upstream's `+vnstat`
  does not exist in these feeds, so defconfig dropped the whole app) and the
  destructive upstream `99-vnstat` (`opkg remove vnstat2 && opkg install
  vnstat` on first boot: needs the network, downgrades the binary, drops the
  DB) is replaced by `99-byte-vnstat`, which only enables the daemon and adds
  the uplink. A new `hotplug.d/iface/92-byte-vnstat` adds the WAN device the
  first time it comes up, because vnstatd runs `--noadd` and the modem dials
  after the LAN. Verified on the unit: daily labels `02 Jul`/`03 Nov`, monthly
  `2026-07`/`2026-11`, selector `br-lan`/`wwan0_1`, vnstatd logging
  `Monitoring (2): wwan0_1 br-lan`.
- **luci-app-byte: buttons were dead and start/stop reported success blindly.**
  Two independent bugs. (1) `ui.showModal(title, children, ...classes)` in
  current LuCI takes CSS classes as the third argument, so passing a buttons
  array there made `classList.add()` throw and the handler died before doing
  anything; the buttons now live inside the modal children in a button row.
  (2) the rpcd `action` method never captured `rc` and always returned
  `"ok":true`, so a failed start looked like a no-op; it now returns the real
  exit code and the reason (`AdGuard Home is not installed yet - run "Install
  and wire" first`). "Install and wire" runs detached (`setsid`, pid file, log
  redirect) and streams its log into a terminal modal that polls
  `ubus call byte log`: mid-run shows `running:true` plus the tail, a failing
  stub returns `exit:3`, the real installer returns `exit:0`. The panel moved
  from a top-level menu entry to *Tools → BYTE* (it previously only sat at the
  top because the removed 5G LED Lua controller created the Tools node), and
  the System-information and Pages cards are gone.
- **Status panel: BYTE branding and a kernel-free version string.** Hostname
  now reads `BYTE by ACE`, the model row is the plain `Arcadyan AW1000` (the
  old code called `getCPUBench`, which does not exist on this build, and
  printed `undefined`), and the firmware row shows
  `BYTE 25.12 VERSION 1.2.x` from `/etc/byte-version`. Kernel version keeps its
  own row, so repeating it in the firmware string was noise.
- **luci-app-modeminfo: shipped invisible (no menu, ACL denied).** The install
  recipe copied `./files/etc` and `./files/www` and the two binaries, but never
  `./files/usr/share`, so `menu.d/luci-app-modeminfo.json` and
  `acl.d/luci-app-modeminfo.json` stayed in the source tree: there was no menu
  entry, and even a direct URL could not call `ubus modeminfo` (the ACL did not
  exist). `Package/*/install` now installs both. Also fixed the doubled unit in
  the signal card (`-88 dBm dBm`): the sampler already prints the unit, so
  `metric()` only appends it when the value does not end with it.
- **Argon theme removed; dotycat 5G LED app removed.** Neither was installed,
  but Argon kept a dead entry in `/etc/config/luci` (`/luci-static/argon` does
  not exist, so selecting it left the UI with no stylesheet) - dropped from the
  shipped config, and `96-byte-dashboard` deletes the key on upgraded units.
  `luci-app-aw1k-led` (`Tools → 5G LED Config`) duplicated the declarative LED
  triggers already in `/etc/config/system`, needed a `led-status` daemon, and
  was the only thing pulling Lua controllers into the image; it is out of the
  preset, out of the required-package gate (a stale `=y` there would have
  failed the build), and now has a forbidden gate so a reused tree cannot
  re-enable it.
- **qmodem: wrong connection status with IPv4+IPv6 in one CGPADDR field.**
  The Overview page showed `Connect Status: No` while the WAN was plainly up
  (`wwan0_1` had an IPv4/IPv6 address and default routes). The Quectel RG500Q
  answers `AT+CGPADDR=1` with both families inside ONE quoted field:
  `+CGPADDR: 1,"10.226.134.159,36.2.180.0.65.251.63.38.0.0.0.0.0.0.0.1"`.
  qmodem's `get_cgpaddr_ipv4()` only matched a whole quoted dotted quad
  (`"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"`), so it returned nothing; the IPv6
  branch greps for `:` groups and found none either (Quectel prints IPv6 in
  dotted decimal). Both empty, so `get_connect_status()` said `No`.
  `apply_preset()` now rewrites the helper to split the field on commas, drop
  quotes/CRs and keep the first standalone 4-octet quad that is not
  `0.0.0.0`. FM350 (separate quoted fields) and the empty-address placeholder
  still behave - qmodem's own `tests/test_core_cmds.sh` fixtures pass - and
  the rewrite hard-fails the build if it does not apply. Verified on the unit:
  `ubus call qmodem get_connect_status '{"config_section":"4_1"}'` now returns
  `{"connection_status": "Yes"}` and `base_info` shows `Connect Status: Yes`.
  **3.4.0 upstreamed the fix**, so the patch is now conditional: the rewrite
  only runs when the function body does not already contain `tr ','`
  (upstream: `tr -d '"' | tr ',' '\n'`). On the pinned feed the patch is
  skipped and the build logs `upstream get_cgpaddr_ipv4 already splits the
  field`; the marker assert only applies to the version BYTE wrote, so a later
  upstream refactor cannot quietly reintroduce the bug without failing the
  build against a body that still looks stock.
- **Build fix (CI-only): duplicate `luci-app-netstat` dropped its i18n
  package.** The vendored app was de-duplicated against the `feeds/luci` copy
  only, but the app also lives in `feeds/dotycat` — whose copy has no `po/`.
  With both scanned, the package scanner kept the dotycat one silently
  (`CONFIG_OVERRIDE_PKGS="luci-app-netstat"` in `.config` was the only trace),
  so `luci-i18n-netstat-zh-cn` never existed and the new preset-index assert
  correctly failed run `41538042529` at 10 min. Reproduced locally by
  restoring the `package/feeds/dotycat/luci-app-netstat` symlink: symbol gone
  from `.config`; removing it: symbol back. `apply_preset()` now removes the
  dotycat copy too, and `ci_check_packages()` fails if any feed copy of the
  app survives in a scanned location.
- **Build fix (CI-only): stray `VERSION_REPO` delete killed run 41536683898
  at 8 min.** The parenthesized-`VERSION_NUMBER` fix accidentally left a
  `sed -i '/^CONFIG_VERSION_REPO=/d'` in `apply_version()`. On CI, where
  `.config` is regenerated from `preset` every run, that delete emptied the
  symbol before `make defconfig`, and `include/version.mk` falls back to
  `https://downloads.immortalwrt.org/releases/25.12.1` — which the existing
  `VERSION_REPO(apk-only-mirror)` forbidden assert then correctly rejected.
  The local tree passed only because its `.config` still carried our repo URL
  from an earlier build: a local-vs-CI divergence this exact class of gate is
  supposed to surface. Line removed; the assert stays.
- **Size: passwall2 geo dependencies dropped (~7.4 MB).** `luci-app-passwall2`
  hard-pulled `geoview` (2 677 KB), `v2ray-geoip` (4 083 KB) and
  `v2ray-geosite` (613 KB). The target node is VLESS over plain WebSocket, so
  no `geoip:`/`geosite:` routing rule ever matches, xray loads the `.dat`
  files lazily, and passwall2 auto-disables geoview when the binary is absent.
  Stripped via an `apply_preset()` DEPENDS rewrite (hard-fails if the feed
  Makefile changes shape), CI asserts all three stay out of `.config`, and
  all four (incl. `chinadns-ng`) are published in the on-demand repo for
  anyone who adds geo routing. `xray-core` itself stays untouched: a trimmed
  `main/distro/all/all.go` was built and measured — 131 072 bytes saved of a
  28.7 MB binary (0.43%), because `infra/conf/` (one Go package importing all
  25 protocol parsers) and `app/dns` (DoQ) keep quic-go/grpc reachable. Not
  worth a permanent fork.
- **Build fix: `25.12(6.12.94)` broke image assembly.** `CONFIG_VERSION_NUMBER`
  flows into `IMG_PREFIX` → every image filename, and `Build/kernel-bin` runs
  `rm -f $@` unquoted: bash parsed the `(` as a subshell token and killed
  `target/install` after all packages had compiled — the failure class that
  costs a whole run to discover, since CI had never reached image assembly.
  The version string is now `25.12.6.12.94` (safe in filenames), and the
  display form `25.12(6.12.94)` is restored at first boot by
  `files/etc/uci-defaults/98-byte-version`, rewriting `DISTRIB_DESCRIPTION`
  from the running kernel's `/proc/version`. LuCI Status still shows
  `BYTE 25.12(6.12.94) <code>`.
- **Gate fix: two false failures in the `packages` post-checks.** (1) With
  `set -o pipefail`, `nm -g <45 MB unstripped .ko> | grep -q` is a SIGPIPE
  race: `grep -q` exits on the first match, nm keeps writing, dies 141, and
  the pipeline "fails" while the symbol is present — the same file printed
  `ok` in one run and `FAIL` in the next. The check now captures `nm` output
  and greps the variable. (2) `config.guess`/`config.sub` `.orig` pairs are
  exempted from the identical-to-`.orig` test:
  `scripts/refresh-config-sub-guess.sh` refreshes them wholesale and a no-op
  refresh leaves the pair identical.
- **Milestone: ECM 12.5 compiled on 6.12.94 with bonding compiled out.** The
  whole NSS stack built locally: `kmod-qca-nss-ecm`, `kmod-qca-nss-drv` (with
  `nss_rmnet_rx_get_ifnum` exported), `kmod-qca-nss-dp`, `kmod-qca-ssdk`, and
  the qmodem vendor drivers (`quectel_QMI_WWAN` patched, `fibocom_QMI_WWAN`,
  `simcom_QMI_WWAN`). This was the biggest open compile risk and it is closed.
- **Gate fix: `packages` false-failed on `.orig` files.** `$(PATCH)` renames
  the pre-image to `.orig` on *success*, so flagging every `.orig` as a failed
  hunk was wrong — 21 of 21 `.orig` files had a matching patched file that
  differed from the backup (patch applied). The gate now only fails on
  `*.rej` (always a failure) or on a file identical to its `.orig` (patch
  produced no change, e.g. the `mtools` `config.guess` refresh).
- **Build fix: `luci-app-modeminfo` died with `Error 127`.** Its vendored
  Makefile used `$(CHMOD) 755 ...` in `Package/install`, but `CHMOD` is not
  defined anywhere in the OpenWrt/ImmortalWrt buildroot (no such variable in
  `rules.mk` or `include/`), so the line expanded to `755 <file>` and bash
  tried to execute it. `Package/install` rewritten with `INSTALL_BIN`, which
  copies and sets 0755 in one step. Confirmed: package builds, ipk produced.
  SA support audited at the same time and it is complete — see
  `luci-app-modeminfo` notes above.
- **Gate fix: `NSS_DRV_*` is not a kernel symbol.** The first `kconf` gate run
  asserted `CONFIG_NSS_DRV_RMNET_ENABLE=y` in the built kernel `.config` and
  failed — correctly, because `qca-nss-drv`'s `KernelPackage` has no `KCONFIG`;
  the options are `PKG_CONFIG_DEPENDS` + `Config.in` that the Makefile turns
  into `DRV_MAKE_OPTS += NSS_DRV_X_ENABLE=n` module defines. They never reach
  any kernel config. The gate now checks the built `qca-nss-drv.ko` for the
  `nss_rmnet_rx_get_ifnum` export (the symbol ECM's RAWIP path calls), and
  `DSCPREMARK` is checked in `.config.override` (where a kmod `KCONFIG` really
  lands). Both green: kernel `6.12.94`, `CONFIG_NF_CONNTRACK_DSCPREMARK_EXT=y`,
  no `CONFIG_BONDING`, no `ECM_INTERFACE_BOND_ENABLE` in ECM source.
- **Config fix: 10 dead `preset` lines removed.** `make defconfig` drops a
  `CONFIG_PACKAGE_x=y` whose symbol no longer exists and only warns, so the
  new `config` gate found lines that had been inert for unknown releases:
  `luci-app-cpufreq` + its zh-cn i18n and `CONFIG_DEFAULT_luci-app-cpufreq`
  (ImmortalWrt's `emortal/cpufreq` is daemon-only, no LuCI app),
  `luci-lib-nixio_openssl` (current luci has a single nixio build),
  `luci-app-diskman_INCLUDE_{btrfs_progs,lsblk}` and
  `luci-app-rclone_INCLUDE_{rclone-webui,rclone-ng}` (parent apps are `not
  set`), `luci-app-passwall2_Basic_Core_Xray` (that option no longer exists;
  `xray-core` is a hard `LUCI_DEPENDS`), and `knot-resolver_dnstap`.
  `ci_check_packages()` now asserts every requested symbol is declared in
  `tmp/.config-package.in`, so this cannot drift again. 320 requested
  symbols, 0 missing.
- **Build fix: the `qmi_wwan_q` patch was never applied.** `quectel_QMI_WWAN`
  overrides `Build/Prepare` and never called `$(Build/Patch)`, so its
  `patches/` directory was inert — run `41469086214` failed at the same
  `modpost: "rmnet_nss_callbacks" ... undefined!` line as `41456411377`.
  `apply_preset()` appends `$(Build/Patch)` after the flattening `$(CP)`, and
  the tree was scanned for the same pattern (this was the only package under
  `feeds/` + `package/` with patches that skipped the patch step). The new
  `packages` gate fails on leftover `*.rej`/`*.orig`, since `$(PATCH)` runs
  with `-f` and a failed hunk is otherwise silent. *(Superseded on 2026-11-04:
  the feed ships a guarded driver now, so the patch and the injection are
  gone — see the top of this changelog.)*
- **New: `scripts/local-verify.sh` — build locally, push once.** CI is a ~3 h
  run that stops at the first failure, so the last four fixes each cost a full
  run to discover. The script reproduces the CI job as ordered gates
  (`download`, `tools`, `toolchain`, `config`, `target`, `kconf`, `packages`,
  `js`, `image`, `ondemand`, `repo`), logs each to
  `/tmp/opencode/gate_<name>.log`, and resumes at the first gate that is not
  yet green. The `config` gate diffs the `=y` set requested by `preset`
  against what `make defconfig` actually kept, and classifies each loss as
  "no such package in any feed" or "dependency unmet" — `defconfig` drops
  those with a warning only. The `kconf` gate asserts the *built* kernel
  config (not the top-level one) has `NF_CONNTRACK_DSCPREMARK_EXT` and
  `NSS_DRV_RMNET_ENABLE` and has no `CONFIG_BONDING`. Pushing only after
  `repo` is green makes CI a publisher instead of a debugger.
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
  with the parentheses display-only (see [Firmware version](#firmware-version)),
  derived from the commit count with the kernel read from the target; the
  passwall2 geo add-ons are published on demand rather than in the image.
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

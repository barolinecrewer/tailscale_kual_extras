# Tailscale for Kindle (KUAL)

This (very) simple repo allows you to connect your kindle remotely from anywhere using Tailscale VPN.

It now also includes a small **KOReader** plugin that can connect, disconnect, and display whether the Kindle is currently connected to Tailscale.

## Prerequisites:

1. Jailbroken Kindle. ([see](https://kindlemodding.gitbook.io/kindlemodding))
2. [KUAL](https://wiki.mobileread.com/wiki/KUAL) installed. ([see](https://kindlemodding.gitbook.io/kindlemodding/post-jailbreak/installing-kual-mrpi))
3. [USBNetworking](https://www.mobileread.com/forums/showthread.php?t=225030) hack installed and [enabled](https://wiki.mobileread.com/wiki/USBNetwork).
4. Set up ssh keys for ease of use.

## My Kindle:

I have a PaperWhite (7th Generation), referred to as [PW3](https://wiki.mobileread.com/wiki/Kindle_Serial_Numbers).

```
[root@kindle root]# uname -a
Linux kindle 3.0.35-lab126 #8 PREEMPT Tue Aug 1 12:49:59 UTC 2023 armv7l GNU/Linux
```

Having tested out on this device only, [YMMV](https://dictionary.cambridge.org/dictionary/english/ymmv).

## Usage:

1. Download the repository.

2. Pick one registration method:

   - **OAuth (preferred):** Create a Tailscale OAuth client with the `auth_keys` scope and at least one allowed tag, then fill `tailscale/bin/oauth.client_secret` with the client secret and `tailscale/bin/oauth.tags` with one or more comma-separated tags such as `tag:kindle`.
   - **Auth key (legacy fallback):** Fill `tailscale/bin/auth.key` with a [Tailscale Auth Key](https://tailscale.com/kb/1085/auth-keys).

3. Place the **tailscale** (not the `tailscale_kual`) folder into the `extensions` folder on your kindle.

4. Optional for KOReader users: place `koreader/tailscale.koplugin` into `koreader/plugins/` on your Kindle so the plugin ends up at `/mnt/us/koreader/plugins/tailscale.koplugin/`.

5. In the KUAL menu, tap **Install / Update Binaries**. This will download the latest `tailscale` and `tailscaled` ARM binaries directly onto the Kindle over Wi-Fi. Alternatively, download them manually for the `arm` architecture from [here](https://pkgs.tailscale.com/stable/#static) and place them in `extensions/tailscale/bin/` yourself.

6. In the KUAL menu, open the **Start Tailscaled** submenu and pick the mode that suits your device (see [Tailscaled Modes](#tailscaled-modes) below). Status messages will appear on the Kindle screen as the daemon starts. Wait a few seconds, then run **Start Tailscale**. You can switch modes at any time without manually stopping tailscaled first — the start scripts handle that automatically.

7. After this, tailscale should add the kindle to your [Machines](https://login.tailscale.com/admin/machines) page on tailscale [admin console](https://login.tailscale.com/welcome).

8. Now you can see the (fairly static) IP address assigned by Tailscale for your kindle. You can use this ip to `ssh root@<kindle-ip>`!

9. **Recommended:** If you used the legacy `auth.key` path and the Kindle is not tagged, open the [Tailscale admin console](https://login.tailscale.com/admin/machines), find your Kindle, click the three-dot menu, and select **Disable key expiry**. If you used OAuth with `oauth.tags`, the Kindle is registered as a tagged device and key expiry is typically already disabled. In either case, once the device is registered successfully, it should reconnect on future boots without needing the `oauth.client_secret` or `auth.key` file again.

10. In case you want to restart fresh, remove the Kindle from the Tailscale admin console, stop `tailscale` and `tailscaled` via KUAL, then delete the state and log files created in `/mnt/us/extensions/tailscale/bin/`: `tailscaled.state`, `tailscale_start_log.txt`, `tailscaled_start_log.txt`, `tailscaled_proxy_start_log.txt`, `tailscaled_tun_start_log.txt`, `tailscale_stop_log.txt`, `tailscaled_stop_log.txt`, and `update_log.txt`. This will fully reset Tailscale's registration on your Kindle.

11. Note: Make sure the kindle screen is on, else the kindle sleeps the wifi. You can also not connect to kindle via ssh when it is connected to PC using the cable.

## KOReader Plugin

The KOReader plugin is a thin UI wrapper around the existing shell scripts in `extensions/tailscale/bin/`. It does not start or stop `tailscaled`; it only manages the `tailscale` client and reports whether the Kindle is currently connected.

Once installed in `/mnt/us/koreader/plugins/tailscale.koplugin/`, the plugin adds a **Tailscale** entry to KOReader's main menu with:

- **Status**: shows whether the device is connected and, when connected, the current Tailscale IPs.
- **Connect**: runs the same `start_tailscale.sh` script used by KUAL.
- **Disconnect**: runs the same `stop_tailscale.sh` script used by KUAL.

How it works:

- The plugin reuses the same binaries and credential files as the KUAL extension under `/mnt/us/extensions/tailscale/bin/`.
- **Connect** calls `start_tailscale.sh`, which first tries a normal `tailscale up --ssh` reconnect and falls back to OAuth or `auth.key` registration if needed.
- **Disconnect** calls `stop_tailscale.sh`, which runs `tailscale down`.
- **Status** checks `tailscale status --json` and treats the device as connected only when `BackendState` is `Running`. When connected, it also shows the output of `tailscale ip`.
- The plugin does not manage `tailscaled`, install binaries, or edit credentials. Those parts still belong to the KUAL extension.

Typical flow:

1. Use KUAL once to install/update the Tailscale binaries.
2. Use KUAL to start `tailscaled` in the mode you want.
3. Use the KOReader plugin for day-to-day **Status**, **Connect**, and **Disconnect** actions.

If **Connect** fails repeatedly from KOReader, `tailscaled` is probably not running yet. Start it once through KUAL, then use the KOReader plugin for day-to-day connect/disconnect checks.


## Tailscaled Modes

The **Start Tailscaled** entry in KUAL is now a submenu with three options. They each map to a different way of running `tailscaled`. Try them in this order if one does not work:

### 1. Standard (Userspace) — default

Runs `tailscaled` with `-tun userspace-networking`. This is what the extension has always done. The kindle joins your tailnet and is reachable by its Tailscale IP (good for SSH), but **outgoing connections from the kindle itself** (e.g. accessing other tailnet nodes) may not work on all devices or firmware versions.

### 2. Proxy Mode (SOCKS5/HTTP)

Runs `tailscaled` in userspace-networking mode but also starts a SOCKS5 and HTTP proxy listener on `localhost:1055`. Outgoing traffic from apps that respect a proxy setting is routed through Tailscale. This is the recommended option if you want to use Tailscale URLs inside **KOReader** (OPDS, the CWA plugin, etc.).

The proxy listen address defaults to `localhost:1055`. To use a different address or port, write it (e.g. `localhost:1080`) into the `proxy.address` file in `extensions/tailscale/bin/` before starting.

After starting tailscaled in this mode and bringing tailscale up, configure KOReader's network proxy:

- Open KOReader → **Settings** → **Network** → **Proxy Settings**
- Set type to **SOCKS5** (or HTTP)
- Host: `localhost`, Port: `1055` (or whatever you set in `proxy.address`)

Once set, any request KOReader makes will go out through your tailnet.

### 3. Kernel TUN (if supported)

Runs `tailscaled` without the userspace-networking flag, relying on the kernel's TUN/TAP module instead. This gives full system-wide outgoing connectivity but requires the `tun` kernel module to be present and loadable. **This is not available on all Kindle firmware versions** — if it fails silently, fall back to Proxy Mode.

## Installing and Updating Tailscale Binaries

The KUAL menu has a single **Install / Update Binaries** entry that handles both cases automatically:

- **Fresh install** (no binaries present): fetches the latest release from the GitHub API, downloads `tailscale_{version}_arm.tgz` from `pkgs.tailscale.com`, installs `tailscale` and `tailscaled` into `extensions/tailscale/bin/`, and creates empty `oauth.client_secret`, `oauth.tags`, and `auth.key` placeholders if they are not already there.
- **Already installed**: reads the current version, skips the download if already up to date, otherwise backs up the existing binaries as `*.bak` and installs the newer version.

Status messages are shown on-screen as the script runs. Full progress and any errors are also written to `update_log.txt` in `extensions/tailscale/bin/`. The Kindle must have an active Wi-Fi connection.

**Tip:** All KUAL actions (start, stop, update) display live status on the Kindle screen and write a corresponding log file in `extensions/tailscale/bin/` — check those logs first when troubleshooting.

**Note:** Stop `tailscale` and `tailscaled` via the KUAL menu first before running this, then start them again afterwards.

## Note:

Check out Open/Closed issues if this does not work right out of the gate.

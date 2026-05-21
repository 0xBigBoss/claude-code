# Diagnostics, Performance, and Networking

Reference for device introspection (lockdown, diagnostics, mounter), live performance metrics (sysmon, processes, energy), SpringBoard control, WebInspector/CDP, and port forwarding.

## Device info

`lockdown` returns the canonical device record — everything Apple's MobileLockdown daemon exposes. Most of this is unauthenticated (no developer mode needed).

```bash
# Full dump (long, paginate)
pymobiledevice3 lockdown info | less

# A single field by domain + key
pymobiledevice3 lockdown get --domain com.apple.disk_usage --key TotalDataAvailable
pymobiledevice3 lockdown get --key ProductVersion          # iOS version
pymobiledevice3 lockdown get --key DeviceName

# Get/set device name
pymobiledevice3 lockdown device-name                       # read
pymobiledevice3 lockdown device-name "Test iPhone"         # write

# Locale and language
pymobiledevice3 lockdown locale
pymobiledevice3 lockdown language
```

The MobileGestalt corpus (huge key/value store backing most Settings fields) is reachable via diagnostics:

```bash
pymobiledevice3 diagnostics mg                       # all known keys
pymobiledevice3 diagnostics mg DeviceColor RegionInfo
```

`bonjour` can discover Wi-Fi-reachable devices without USB:

```bash
pymobiledevice3 bonjour browse
```

## Power, battery, hardware diagnostics

```bash
# Battery health, cycle count, design vs current capacity
pymobiledevice3 diagnostics battery

# IORegistry dump — every hardware service the kernel exposes (huge)
pymobiledevice3 diagnostics ioregistry

# General diagnostics info
pymobiledevice3 diagnostics info
```

Power assertions prevent screen sleep / display dim while running e.g. long instrumentation captures:

```bash
pymobiledevice3 power-assertion --type PreventUserIdleSystemSleep
# (runs until ctrl-c)
```

Reboot / shutdown / sleep are blunt:

```bash
pymobiledevice3 diagnostics restart
pymobiledevice3 diagnostics shutdown
pymobiledevice3 diagnostics sleep
```

## DeveloperDiskImage state

```bash
# Is developer mode on?
pymobiledevice3 mounter query-developer-mode-status

# What images are mounted?
pymobiledevice3 mounter list

# Auto-mount the correct image for the running iOS version
pymobiledevice3 mounter auto-mount

# Manual mount/unmount
pymobiledevice3 mounter mount-developer ...
pymobiledevice3 mounter umount-developer
```

`auto-mount` is what you want 95% of the time after a fresh iOS update — Xcode would normally do this on first connect, but pymobiledevice3 can do it headless.

## Live system performance (sysmon)

`developer dvt sysmon` is the live equivalent of Activity Monitor. Requires tunneld on iOS 17+.

```bash
# One-shot system stats: CPU%, mem pressure, thermal state, uptime
pymobiledevice3 developer dvt sysmon system

# Per-process polling loop — top-like view of CPU/memory per PID
pymobiledevice3 developer dvt sysmon process
```

For PID enumeration and runtime checks:

```bash
pymobiledevice3 developer dvt proclist               # PIDs + names + start times
pymobiledevice3 developer dvt is-running-pid 1234
pymobiledevice3 processes                            # alternate (diagnosticsd-backed) listing
```

Energy monitoring (Instruments' Energy Log equivalent) needs explicit PIDs:

```bash
pymobiledevice3 developer dvt energy 1234 5678
```

Graphics / FPS sampling and notification monitoring:

```bash
pymobiledevice3 developer dvt graphics              # FPS, GPU%, draw call rates
pymobiledevice3 developer dvt notifications         # memory + app lifecycle events
```

## Network / port forwarding

`usbmux forward` is the most useful piece for development: tunnel a TCP port from your host through usbmuxd to the device. Local-only, no tunneld needed. Survives ctrl-c only if you background it.

```bash
# Forward localhost:8080 -> device:8080 (e.g. a dev server inside an app)
pymobiledevice3 usbmux forward 8080 8080

# Different local port to avoid collisions
pymobiledevice3 usbmux forward 9090 8080

# Target a specific device by UDID
pymobiledevice3 usbmux forward --udid 00008101-... 8080 8080
```

For developer-service tunnels (e.g. to talk RemoteXPC directly):

```bash
# Print the RSD HOST:PORT for use with --rsd
pymobiledevice3 remote start-tunnel
```

## WebInspector (Safari + WKWebView debugging)

Requires Safari → Settings → Advanced → "Web Inspector" enabled on the device, and a Mac with the matching Safari Develop menu enabled. `cdp` exposes a Chrome DevTools Protocol endpoint, which is useful for headless WebView automation (Playwright, Puppeteer-style harnesses).

```bash
# See what's debuggable
pymobiledevice3 webinspector opened-tabs

# Open a URL in Safari
pymobiledevice3 webinspector launch https://example.com

# JavaScript REPL bound to a remote target
pymobiledevice3 webinspector js-shell

# Start a CDP server (default port printed on stdout) — point Chrome DevTools or CDP clients at it
pymobiledevice3 webinspector cdp
```

`webinspector shell` drops you into an IPython shell with a `WebView` handle for ad-hoc scripting.

## Notifications

The Darwin notification proxy lets you observe or post system-wide notifications. Useful for triggering app-side handlers (e.g. wallpaper changed, low memory).

```bash
# Observe notifications by name
pymobiledevice3 notifications observe com.apple.UIKit.userActivityActive

# Post a notification (limited — most names require entitlements)
pymobiledevice3 notifications post com.example.MyNotification
```

## Force device conditions (DVT)

Simulate constrained network, low battery, or thermal pressure for testing — same conditions Xcode's "Devices and Simulators → Conditions" exposes.

```bash
# Network conditioning (predefined profiles)
pymobiledevice3 developer developer ...
```

The `developer developer` subcommand handles conditions; see `pymobiledevice3 developer developer --help` for the current profile names — Apple changes them between iOS releases.

## Arbitration

When multiple tools (Xcode, Instruments, automation harnesses) compete for the device, mark/unmark in-use to avoid collisions:

```bash
pymobiledevice3 developer arbitration check-in
pymobiledevice3 developer arbitration check-out
```

# Capture: screenshots, screen content, logs, crashes, traffic

Reference for the read-only capture surface of `pymobiledevice3`. See `SKILL.md` for prerequisites (Developer Mode + tunneld for iOS 17+).

## Screenshots

The modern, iOS 17+-friendly path is the DVT variant — it goes through the developer instrumentation channel and works where the legacy `developer screenshot` (marked Deprecated in the CLI) silently fails.

```bash
# Recommended
pymobiledevice3 developer dvt screenshot ~/Desktop/shot.png

# Specific device when multiple are attached
PYMOBILEDEVICE3_TUNNEL=00008101-001E05A41144001E \
  pymobiledevice3 developer dvt screenshot ~/Desktop/shot.png

# Legacy (older iOS / fallback only)
pymobiledevice3 developer screenshot ~/Desktop/shot.png
```

Timestamped capture-and-open one-liner (macOS):

```bash
OUT="$HOME/Desktop/ios-$(date +%Y%m%d-%H%M%S).png"
pymobiledevice3 developer dvt screenshot "$OUT" && open "$OUT"
```

No native screen-recording subcommand exists in `pymobiledevice3` today; for video, use QuickTime's "Movie Recording → device as camera" over USB on macOS.

## Springboard / wallpaper / icon captures

These don't need tunneld — they're plain lockdown services.

```bash
# Save an app's icon PNG
pymobiledevice3 springboard icon com.example.MyApp ./icon.png

# Save the homescreen wallpaper PNG
pymobiledevice3 springboard wallpaper-home-screen ./wallpaper.png

# Current orientation (portrait/landscape*)
pymobiledevice3 springboard orientation
```

## Live syslog

`syslog live` streams the device's unified log over usbmux. Cheap and stable; first stop when diagnosing crashes that aren't producing crash reports yet, or when watching app lifecycle.

```bash
# Stream forever; ctrl-c to stop
pymobiledevice3 syslog live

# Filter at the shell — pymobiledevice3 doesn't take predicates
pymobiledevice3 syslog live | grep -i 'MyApp\|fault\|error'

# Capture to a .logarchive for later inspection with `log show` / Console.app
pymobiledevice3 syslog collect ~/ios-logs
```

For richer logs (more fields, includes oslog metadata) the DVT-backed variant exists but is flaky:

```bash
pymobiledevice3 developer dvt oslog
```

Prefer `syslog live` unless you specifically need oslog fields.

## Crash reports

The CrashReporter service surfaces both fresh and historical reports. Reports include `.ips` (newer) and `.crash` (older) formats. Symbolicate with Xcode if you need readable stacks.

```bash
# Flush queued reports from the on-device mover into CrashReports/
pymobiledevice3 crash flush

# List
pymobiledevice3 crash ls

# Pull all crashes to a local directory
pymobiledevice3 crash pull ~/ios-crashes

# Watch for new reports as they're generated
pymobiledevice3 crash watch

# Capture a full sysdiagnose (requires holding volume buttons on device — user gesture)
pymobiledevice3 crash sysdiagnose ~/sysdiagnose
```

`crash shell` opens an interactive AFC shell into the crash directory if you want to navigate before pulling.

## Packet capture

The `pcap` service taps interface-level traffic on the device. Output is a standard `.pcap` you can open in Wireshark.

```bash
# Capture everything to a file
pymobiledevice3 pcap --out trace.pcap

# Limit by packet count
pymobiledevice3 pcap --out trace.pcap --count 500

# Filter to a single process — invaluable for diagnosing a misbehaving app's traffic
pymobiledevice3 pcap --out safari.pcap --process Safari

# Filter to an interface (e.g. en0 Wi-Fi)
pymobiledevice3 pcap --out wifi.pcap --interface en0
```

Note: TLS payloads are encrypted at the wire. To see decrypted HTTP/HTTPS, install a CA on the device and route through an MITM proxy (mitmproxy/Charles) — `pcap` alone won't help.

## Location simulation

Spoof GPS for the entire device (not just an app). Useful for region-gated features and map QA.

```bash
# Set a fixed coordinate
pymobiledevice3 developer simulate-location set 37.7749 -122.4194

# Clear and return to real GPS
pymobiledevice3 developer simulate-location clear

# Replay a GPX route (e.g. exported from Maps or recorded with a fitness app)
pymobiledevice3 developer simulate-location play ./route.gpx
```

`simulate-location` also exists under `developer dvt` with the same semantics; prefer the top-level one.

## HAR logging (network from app perspective)

`har` enables network logging at the CFNetwork layer for a target app — closer to "developer tools network tab" than to `pcap`. Output is HAR JSON.

```bash
pymobiledevice3 developer dvt har --process com.example.MyApp --out app.har
```

Caveat: only HTTPS/HTTP traffic going through CFNetwork shows up; sockets and lower-level APIs do not.

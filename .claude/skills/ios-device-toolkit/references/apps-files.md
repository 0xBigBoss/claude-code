# Apps and Files

App lifecycle (list, install, launch, kill), app sandbox file I/O, AFC media access, and debugserver. Most app-lifecycle operations and the app-sandbox AFC require a tunneld session on iOS 17+.

## Listing and querying apps

```bash
# All apps (system + user)
pymobiledevice3 apps list

# Filter flags
pymobiledevice3 apps list --user            # only user-installed
pymobiledevice3 apps list --system          # only system-installed
pymobiledevice3 apps list --hidden          # include hidden

# Metadata for a specific bundle ID (returns dict: version, signing, paths, entitlements)
pymobiledevice3 apps query com.example.MyApp

# Via DVT — different shape; useful when you want the same set the Instruments target picker sees
pymobiledevice3 developer dvt applist
```

## Install / uninstall

`apps install` accepts `.ipa`, an unpacked `.app` bundle, or `.ipcc` carrier bundles. The IPA must be signed for the target device's profile (development or enterprise) — App Store signed builds will be refused.

```bash
pymobiledevice3 apps install ./build/MyApp.ipa
pymobiledevice3 apps uninstall com.example.MyApp
```

## Launch, kill, signal

These go through DVT. On iOS 17+ you'll want a tunneld session running.

```bash
# Launch (returns PID)
pymobiledevice3 developer dvt launch com.example.MyApp

# Resolve a running bundle ID to its PID (empty if not running)
pymobiledevice3 developer dvt process-id-for-bundle-id com.example.MyApp

# Kill by PID
pymobiledevice3 developer dvt kill 1234

# Kill by name substring
pymobiledevice3 developer dvt pkill MyApp

# Send arbitrary signal (e.g. SIGSTOP=17, SIGCONT=19)
pymobiledevice3 developer dvt signal 1234 --signal-name SIGSTOP
```

`memlimitoff` raises a specific PID's jetsam limit — useful for diagnosing low-memory kills during instrumentation:

```bash
pymobiledevice3 developer dvt memlimitoff 1234
```

## App sandbox files (the common case)

`pymobiledevice3 apps {pull,push,rm,afc}` go directly into a specific app's container — no need to know the on-device path layout. The container exposes `Documents/`, `Library/`, `tmp/`, `SystemData/`, etc.

```bash
# Pull a single file
pymobiledevice3 apps pull com.example.MyApp Documents/app.sqlite ./app.sqlite

# Push (overwrites if present)
pymobiledevice3 apps push com.example.MyApp ./seed.json Documents/seed.json

# Remove
pymobiledevice3 apps rm com.example.MyApp Documents/stale.log

# Interactive shell into the container — useful for exploration
pymobiledevice3 apps afc com.example.MyApp

# Restrict to Documents only (UIFileSharingEnabled apps)
pymobiledevice3 apps afc com.example.MyApp --documents
```

App must support file sharing (`UIFileSharingEnabled` in Info.plist) for non-developer builds; development builds expose the full container regardless.

## AFC: device media root

Plain `afc` mounts `/var/mobile/Media` — photos, ringtones, downloads, etc. No tunneld needed (it's a lockdown service).

```bash
pymobiledevice3 afc ls
pymobiledevice3 afc ls -r DCIM
pymobiledevice3 afc pull DCIM/100APPLE/IMG_0001.HEIC ./
pymobiledevice3 afc push ./song.m4a iTunes_Control/Music/
pymobiledevice3 afc shell                        # interactive
```

## debugserver (LLDB attach)

For attaching `lldb` to a running app or launching one under the debugger. iOS 17+ uses RSD (so tunneld); older releases go over usbmux.

```bash
# Show which apps debugserver can target
pymobiledevice3 developer debugserver applist

# Start the server and print the LLDB connect string
pymobiledevice3 developer debugserver start-server

# In another terminal, paste the printed connect string into lldb:
#   (lldb) process connect connect://[FE80::...]:PORT
#   (lldb) process attach --pid 1234
```

The `lldb` subcommand automates this for an Xcode project:

```bash
pymobiledevice3 developer debugserver lldb /path/to/MyApp.xcodeproj
```

## XCUITest

`xcuitest` lets you drive a UI test runner against a built `.app` without Xcode. Mostly relevant for headless CI work.

```bash
pymobiledevice3 developer dvt xcuitest --bundle-id com.example.MyAppUITests.xctrunner ./test-runner.app
```

Refer to upstream docs for the full argument set — semantics evolve with iOS releases.

## Profile / provisioning

Install configuration profiles (MDM payloads, Wi-Fi, certs) and provisioning profiles. Profile install requires the user to approve from Settings → General → VPN & Device Management.

```bash
# Configuration profiles
pymobiledevice3 profile list
pymobiledevice3 profile install ./MyConfig.mobileconfig
pymobiledevice3 profile remove <profile-identifier>

# Provisioning profiles (for sideloaded dev builds)
pymobiledevice3 provision list
pymobiledevice3 provision install ./Dev.mobileprovision
pymobiledevice3 provision remove <UUID>
```

# Platform APIs

## Contents
- Application and context menus
- System tray
- Global events and shutdown lifecycle
- Updater
- Utils
- GlobalShortcut, Screen, Session

## Application Menu

```typescript
import Electrobun, { ApplicationMenu } from "electrobun/bun";

ApplicationMenu.setApplicationMenu([
  { submenu: [{ label: "Quit", role: "quit" }] },
  {
    label: "Edit",
    submenu: [
      { role: "undo" },
      { role: "redo" },
      { type: "separator" },
      { role: "cut" },
      { role: "copy" },
      { role: "paste" },
      { role: "pasteAndMatchStyle" },
      { role: "delete" },
      { role: "selectAll" },
      { type: "separator" },
      { label: "Save", action: "save", accelerator: "s" },
    ],
  },
]);

Electrobun.events.on("application-menu-clicked", (e) => {
  console.log("action", e.data.action);
});
```

Use role-based items to enable native shortcuts (`quit`, `copy`, `paste`, etc.).

## Context Menu

```typescript
import Electrobun, { ContextMenu } from "electrobun/bun";

ContextMenu.showContextMenu([
  { label: "Copy", role: "copy" },
  { label: "Paste", role: "paste" },
  { type: "separator" },
  { label: "Custom", action: "custom", accelerator: "s" },
]);

Electrobun.events.on("context-menu-clicked", (e) => {
  console.log("context action", e.data.action);
});
```

## System Tray

```typescript
import { Tray } from "electrobun/bun";

const tray = new Tray({
  title: "My App",
  image: "views://assets/icon-32-template.png",
  template: true,
  width: 32,
  height: 32,
});

tray.on("tray-clicked", () => {
  tray.setMenu([
    { label: "Show Window", action: "show" },
    { type: "separator" },
    { label: "Quit", role: "quit" },
  ]);
});
```

Related events:
- `tray-clicked`
- `tray-item-clicked`

## Events and Shutdown Lifecycle

```typescript
import Electrobun from "electrobun/bun";

Electrobun.events.on("will-navigate", (e) => {
  e.response = { allow: true };
});

Electrobun.events.on("open-url", (e) => {
  console.log("deep link", e.data.url);
});

Electrobun.events.on("before-quit", async (e) => {
  await saveState();
  // e.response = { allow: false };
});
```

Quit path guidance:
- Use `before-quit` for cleanup and optional quit cancellation.
- `process.on("exit")` is sync-only and should be last-resort.
- Linux caveat: some system-initiated quit paths may not currently fire `before-quit`; programmatic quit (`Utils.quit` / `process.exit`) is reliable.

## Updater

```typescript
import { Updater } from "electrobun/bun";

const local = await Updater.getLocalInfo();
const update = await Updater.checkForUpdate();

if (update.updateAvailable) {
  await Updater.downloadUpdate();
}

if (Updater.updateInfo()?.updateReady) {
  await Updater.applyUpdate();
}
```

Guidance:
- Keep `release.baseUrl` and artifact uploads aligned by channel/os/arch.
- Patching attempts incremental path first and falls back to full bundle when needed.

## Utils

```typescript
import { Utils } from "electrobun/bun";

Utils.moveToTrash(path);
Utils.showItemInFolder(path);
Utils.openExternal("https://example.com");
Utils.openPath("/path/to/file.pdf");

const paths = await Utils.openFileDialog({
  startingFolder: Utils.paths.home,
  allowedFileTypes: "png,jpg",
  canChooseFiles: true,
  canChooseDirectory: false,
  allowsMultipleSelection: true,
});

const { response } = await Utils.showMessageBox({
  type: "question",
  title: "Confirm",
  message: "Continue?",
  buttons: ["Yes", "No"],
  defaultId: 1,
  cancelId: 1,
});

Utils.showNotification({ title: "Done", body: "Task complete", silent: false });
Utils.clipboardWriteText("hello");
const text = Utils.clipboardReadText();
const formats = Utils.clipboardAvailableFormats();

Utils.quit();
```

Persistence paths:
- `Utils.paths.userData`
- `Utils.paths.userCache`
- `Utils.paths.userLogs`

Do not write runtime data into bundle resource paths.

## GlobalShortcut

```typescript
import { GlobalShortcut } from "electrobun/bun";

GlobalShortcut.register("CommandOrControl+Shift+Space", () => {
  console.log("shortcut fired");
});

GlobalShortcut.isRegistered("CommandOrControl+Shift+Space");
GlobalShortcut.unregister("CommandOrControl+Shift+Space");
GlobalShortcut.unregisterAll();
```

## Screen

```typescript
import { Screen } from "electrobun/bun";

const primary = Screen.getPrimaryDisplay();
const all = Screen.getAllDisplays();
const cursor = Screen.getCursorScreenPoint();
```

## Session

```typescript
import { Session } from "electrobun/bun";

const session = Session.fromPartition("persist:myapp");
// or Session.defaultSession

const cookies = session.cookies.get({ domain: "example.com" });
session.cookies.set({ name: "token", value: "abc", domain: "example.com", secure: true });
session.cookies.remove("https://example.com", "token");
session.cookies.clear();
session.clearStorageData(["cookies", "localStorage"]);
```

Use explicit partition naming for account isolation and predictable cookie/storage behavior.

# Window and Webview APIs

## Contents
- BrowserWindow constructor and common methods
- BrowserView methods and events
- `<electrobun-webview>` tag
- Navigation rules and event behavior

## BrowserWindow

```typescript
import { BrowserWindow } from "electrobun/bun";

const win = new BrowserWindow({
  title: "My App",
  url: "views://mainview/index.html",
  frame: { width: 1200, height: 800, x: 100, y: 100 },
  titleBarStyle: "default", // "default" | "hidden" | "hiddenInset"
  transparent: false,
  sandbox: false,            // use true for untrusted content
  partition: "persist:main",
  preload: "views://mainview/preload.js",
  rpc: myRPC,
  styleMask: {
    Titled: true,
    Closable: true,
    Miniaturizable: true,
    Resizable: true,
  },
});
```

Common methods:
- `setTitle`, `close`, `focus`
- `minimize` / `unminimize` / `isMinimized`
- `maximize` / `unmaximize` / `isMaximized`
- `setFullScreen` / `isFullScreen`
- `setAlwaysOnTop` / `isAlwaysOnTop`
- `setPosition`, `setSize`, `setFrame`
- `getFrame`, `getPosition`, `getSize`

Window events:
- `close`
- `resize`
- `move`
- `focus`

Default webview:

```typescript
const webview = win.webview;
```

## BrowserView

Access patterns:
- `win.webview`
- `BrowserView.getById(id)`
- `BrowserView.getAll()`
- `new BrowserView({...})` for advanced use cases

```typescript
import { BrowserView } from "electrobun/bun";

webview.loadURL("views://mainview/page.html");
webview.loadHTML({ html: "<h1>Hello</h1>" });
webview.executeJavascript('document.title = "new"');
webview.openDevTools();
webview.closeDevTools();
webview.toggleDevTools();
webview.findInPage("search term", { forward: true, matchCase: false });
webview.stopFindInPage();
```

Navigation rules:

```typescript
webview.setNavigationRules([
  "^*",                    // block all
  "*://trusted.com/*",     // allow trusted.com
  "^http://*",             // block non-HTTPS
]);
```

Rule semantics:
- Glob-style patterns
- Prefix `^` means block rule
- Last matching rule wins
- If no rule matches, navigation is allowed

Built-in RPC helper:

```typescript
const title = await webview.rpc.request.evaluateJavascriptWithResponse({
  script: "document.title",
});
```

BrowserView events:
- `will-navigate`
- `did-navigate`
- `did-navigate-in-page`
- `did-commit-navigation`
- `dom-ready`
- `new-window-open`
- `download-started`
- `download-progress`
- `download-completed`
- `download-failed`

`will-navigate` note:
- Navigation allow/block decision is made in native code based on `setNavigationRules`.
- Event is informational by the time it fires.

## `<electrobun-webview>` (OOPIF)

Custom tag for process-isolated nested webviews.

```html
<electrobun-webview
  id="child-webview"
  src="https://example.com"
  partition="persist:isolated"
  sandbox
  style="width: 100%; height: 500px;"
></electrobun-webview>
```

Common attributes:
- `src`, `html`, `preload`, `partition`, `sandbox`
- `transparent`, `hidden`, `passthroughEnabled`, `delegateMode`

Common methods:
- `loadURL`, `goBack`, `goForward`, `reload`
- `canGoBack`, `canGoForward`
- `setNavigationRules`
- `callAsyncJavaScript`
- `on`, `off`

Host messaging from preload:

```javascript
// preload script in nested webview context
window.__electrobunSendToHost({ type: "click", x: 10, y: 20 });

// host page
document
  .getElementById("child-webview")
  .on("host-message", (e) => console.log(e.detail));
```

Security posture for nested webviews:
- Use `sandbox` for untrusted content.
- Add explicit navigation allowlists.
- Validate all host-message payloads.

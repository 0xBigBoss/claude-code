# Build Config Reference

## Contents
- electrobun.config.ts baseline
- Build fields and runtime fields
- `views://` bundled assets
- Distribution artifact model
- Build lifecycle hooks

## electrobun.config.ts Baseline

```typescript
import type { ElectrobunConfig } from "electrobun";

export default {
  app: {
    name: "My App",
    identifier: "com.example.myapp",
    version: "1.0.0",
    urlSchemes: ["myapp"], // macOS deep-linking support
  },
  runtime: {
    exitOnLastWindowClosed: true,
    // custom keys are readable at runtime via BuildConfig.get()
  },
  build: {
    bun: {
      entrypoint: "src/bun/index.ts",
      // Bun.build pass-through options supported (plugins/external/sourcemap/minify/etc.)
    },
    views: {
      mainview: {
        entrypoint: "src/mainview/index.ts",
      },
    },
    copy: {
      "src/mainview/index.html": "views/mainview/index.html",
      "src/mainview/style.css": "views/mainview/style.css",
    },
    useAsar: false,
    asarUnpack: ["*.node", "*.dll", "*.dylib", "*.so"],
    // watch: ["scripts"],
    // watchIgnore: ["**/*.generated.*"],
    mac: {
      codesign: true,
      notarize: true,
      bundleCEF: false,
      defaultRenderer: "native", // or "cef" when bundleCEF is true
      entitlements: {},
      icons: "icon.iconset",
    },
  },
  scripts: {
    preBuild: "./scripts/pre-build.ts",
    postBuild: "./scripts/post-build.ts",
    postWrap: "./scripts/post-wrap.ts",
    postPackage: "./scripts/post-package.ts",
  },
  release: {
    baseUrl: "https://storage.example.com/myapp/",
  },
} satisfies ElectrobunConfig;
```

## Runtime Access

```typescript
import { BuildConfig } from "electrobun/bun";

const cfg = await BuildConfig.get();
console.log(cfg.runtime?.exitOnLastWindowClosed);
```

## Bundled Assets (`views://`)

`views://` maps to bundled static assets and works in BrowserWindow/BrowserView URLs plus HTML and CSS references.

```html
<script src="views://mainview/index.js"></script>
<link rel="stylesheet" href="views://mainview/style.css" />
<img src="views://assets/logo.png" />
```

## Distribution Artifacts

Non-dev builds (`canary`/`stable`) produce flat artifacts prefixed:
- `{channel}-{os}-{arch}-update.json`
- platform installers
- `.tar.zst` update bundle
- `.patch` incremental patch (typically from previous version)

General guidance:
- Upload entire `artifacts/` output to static hosting.
- Keep historical patch files if you want chain-style incremental updates available to clients.
- If patch trail is unavailable, updater falls back to full bundle download.

## Build Lifecycle Hooks

Execution order:
- `preBuild`
- `postBuild`
- `postWrap`
- `postPackage`

Common env vars:
- `ELECTROBUN_BUILD_ENV`
- `ELECTROBUN_OS`
- `ELECTROBUN_ARCH`
- `ELECTROBUN_BUILD_DIR`
- `ELECTROBUN_APP_NAME`
- `ELECTROBUN_APP_VERSION`
- `ELECTROBUN_APP_IDENTIFIER`
- `ELECTROBUN_ARTIFACT_DIR`
- `ELECTROBUN_WRAPPER_BUNDLE_PATH` (postWrap only)

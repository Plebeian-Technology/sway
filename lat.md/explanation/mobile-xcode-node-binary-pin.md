---
lat:
  mode: explanation
---

# Why ios/.xcode.env.local must not pin a full node path

`ios/` is generated and gitignored, so `mobile/__tests__/xcodeNodeEnv.test.ts` reads `ios/.xcode.env.local` only when it is there — on CI it is not, and the tests skip.

A full pinned node path (for example `NODE_BINARY=/Users/x/.local/share/mise/installs/node/24.19.0/bin/node`) breaks the build when the version manager removes that version — the error names a missing FILE, not a missing node, since react-native only checks the override for empty. The test still requires `NODE_BINARY` to be set at all, since Xcode falls back to a deprecated search otherwise.

---
mode: reference
summary: "What PrimitiveGalleryScreen is for and why it uses two ThemeProvider subtrees instead of one toggle, working around a NativeWind/ThemeProvider mismatch."
status: agent-extracted
related: []
---

# `PrimitiveGalleryScreen`

`PrimitiveGalleryScreen`
(`mobile/src/screens/__dev__/PrimitiveGalleryScreen.tsx`) is a
developer-only page for eyeballing the shared UI building blocks.

It draws all five of them (Card, Pressable, EmptyState, ListRow,
FormField) twice: once inside a light `ThemeProvider` and once inside a
dark one, stacked one above the other.

## Why two providers instead of one toggle

`ThemeProvider.setMode()` does NOT call NativeWind's `colorScheme.set()`,
so NativeWind's `dark:` classes still follow the operating system's
colour scheme rather than the in-app setting. Giving each theme its own
`ThemeProvider` subtree with an explicit `initialMode` is the right way
around that. Fixing the underlying behaviour is tracked separately.

Each section reads an inline background colour rather than a NativeWind
class, for the same reason: NativeWind's `dark:` classes follow the
operating system, not `ThemeProvider.setMode()`. Reading
`swayTokens[mode].background` directly keeps the two theme sections
clearly apart.

## Visibility

Only when `__DEV__` is true. It can never be reached in a release build.
How it is hooked into navigation — a deep link like
`sway://dev/gallery` or a hidden long press — is left to whoever adds it,
guarded by `if (__DEV__)`.

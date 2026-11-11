---
lat:
  mode: explanation
---

# Why mobile/app.config.ts spells out the .ts extension on its one relative import

`app.config.ts` imports `DEEP_LINK_PATTERNS` and `androidPathData` from `./src/navigation/deepLinkPatterns.ts`. The extension is not decoration and must not be tidied away.

The Expo CLI does not run `app.config.ts` as TypeScript. `@expo/require-utils` transpiles that one entry file to CommonJS and hands the result to Node's CJS loader, writing it as a sibling `app.config.js`. Only the entry file is transpiled — its imports are left as plain `require()` calls, resolved by Node against the real filesystem.

With an extensionless specifier, Node looks for `deepLinkPatterns.js`, finds only `deepLinkPatterns.ts`, and the whole command dies before doing any work:

```
Error: Error reading Expo config at mobile/app.config.ts:
Cannot find module './src/navigation/deepLinkPatterns'
```

Every command that reads the config fails the same way — `expo run:ios`, `expo run:android`, `expo prebuild`, `expo config`, `eas build --local`.

Naming the extension makes Node load the `.ts` file directly, which works because Node strips the type annotations itself. That places one constraint on `deepLinkPatterns.ts`: it must stay **erasable** TypeScript — type annotations, interfaces and `type` aliases only. An `enum`, a `namespace`, a decorator or a constructor parameter property compiles to real runtime code, which Node's stripper refuses, and the config would stop loading again with a different error.

## Why the list is not simply copied into the config

Copying would remove the import and the problem with it, at the cost of the invariant the module exists to hold.

iOS reads the patterns from `associatedDomains`, Android from `intentFilters`, and Rails serves the same set again from `/.well-known/apple-app-site-association`. Those lists drifting apart is exactly the defect fixed once before, where a membership link opened the app on iPhone and the browser on Android. One list, read three times, is worth an explicit file extension.

## Why tsc does not catch this

`mobile/tsconfig.json` lists `src`, `App.tsx`, `index.js`, `__tests__` and the type directories in `include`.

`app.config.ts` is in none of them, so `pnpm --dir mobile run typecheck` never reads the file and cannot report a broken import in it. The only signal is an Expo command failing at startup.

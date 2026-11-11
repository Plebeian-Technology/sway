---
lat:
  mode: explanation
---
# Console channels in the browser

Three console channels carry three different meanings. `logDev` is routine development feedback, `console.warn` a stronger development-only alarm, and `console.error` the only one production forwards to the error tracker.

## Why routine feedback goes through logDev

`logDev` prints only outside production and prefixes each line with `(dev)`. It lives in `app/frontend/sway_utils/index.ts` for the web app and `mobile/src/utils/logging.ts` for the mobile one.

A bare `console.log` differs from it in the way that matters: the call survives into a production bundle, where `SentryUtil.init` has already replaced `window.console.log` with a no-op, so it ships, runs, and prints nothing. The helper makes that outcome visible at the call site instead of only at the one place that neuters it.

It also gives the three routine channels one spelling. `log`, `info` and `debug` were used interchangeably here, so the choice between them recorded who wrote the line rather than how loud it was meant to be.

`app/frontend/__tests__/consoleChannels.test.ts` walks the non-legacy, non-test frontend and reddens when one of the three appears. `logDev`'s own file is the single exemption, because that is where the channels are reached on purpose.

## Why warn and error are left alone

`console.warn` says something louder than routine and is still invisible in production. `console.error` differs in kind: production replaces it with `Sentry.captureException`, so it is the one channel that reaches the tracker.

`SentryUtil.init` no-ops `warn` alongside `log`, `dir` and `table`. What survives the no-op is the distinction a reader sees in development: `warn` marks a setup that looks healthy and is not — a collector address pointing at another machine, for one — and folding it into `logDev` would flatten that.

An `error` call is therefore a decision to raise an issue in the tracker rather than a decision to print. Reserving it for failures that deserve one is what keeps the tracker readable, and it is why the sweep converted neither channel.

## Why the server logger keeps a debug-level twin

The Ruby logging helper offers a debug-level method beside the others, used by
only two callers.

It exists so those two keep logging at debug level. Folding them into the
ordinary helper would promote them to the level everything else uses, which
puts two chatty callers into the output an operator reads for real events, and
the volume is the reason they were at debug in the first place.

## Why the mobile app repeats the helper

`mobile/src/utils/logging.ts` holds its own `logDev`, guarded on `process.env.NODE_ENV` where the web app reads its `IS_NOT_PRODUCTION` constant.

The two trees share no runtime code — the mobile app is a separate pnpm workspace reaching the same Rails backend over JSON — so the helper is duplicated rather than imported.

`mobile/__tests__/consoleChannels.test.ts` is the same gate over `mobile/src`, with the same one exemption. `mobile/scripts/` sits outside it: those are node command-line programs whose output is the console.

[[mobile/src/api/client.ts]] logs the resolved API base URL once in development.
The value is fixed by the build, so seeing it in the simulator log exposes a
build pointed at the wrong server without logging every request.

---
lat:
  mode: explanation
---

# Explaining unexpected dev-server page reloads

Vite's dev client can reload an open page three different ways, and two of them leave nothing in the dev server's log:

- **The socket dropped.** Vite waits for the dev server to answer again,
  then reloads. The server logs nothing — from its side a connection simply
  closed.
- **A full-reload message.** Vite's own file watcher prints
  `page reload <file>`, but a message a plugin sends itself prints nothing
  unless the plugin says so. Sway has one of those, in `vite.config.ts`, and
  it now does.
- **An error overlay.** Vite reloads on the first change after showing one,
  with no message of its own at all.

So a page could reload during a hands-on test and no log anywhere would account for it. All three announce themselves as Vite events (`vite:ws:disconnect`, `vite:beforeFullReload`, `vite:error`) immediately before the reload happens, which is what this diagnostic hooks into.

## How it works

`reportWhyThePageReloaded` (`app/frontend/dev/reportWhyThePageReloaded.ts`) listens for those three events and writes each one down.

`reportWhyThePageReloaded` (`app/frontend/dev/reportWhyThePageReloaded.ts`) listens for those three events and writes each one down — via `appendReloadReason` (`app/frontend/dev/reloadReasonStore.ts`) — before the reload actually happens. On the next page load, `describeReloadReason` (`app/frontend/dev/describeReloadReason.ts`) turns whatever was recorded into one plain-language sentence and prints it to the console.

The recording step is deliberately separated from the judgement step (`describeReloadReason`): the part with all the logic — deciding which reason applies and phrasing it — is the part that's unit-tested, without needing a browser.

## Why sessionStorage, and why per-tab

The record has to survive the reload itself, or it can't answer the only question worth asking afterwards.

`sessionStorage` is the store that does. It's also per-tab, which matters: two tabs open on the same screen reload for their own reasons, and mixing the two up is part of what made the original report unreadable.

Reading and writing both swallow every error and fall back to "nothing recorded" — a browser with storage disabled, or a stray value this code didn't write, both have to degrade quietly. A diagnostic that can itself throw is worse than no diagnostic at all.

## Development only

None of this runs in a built bundle: a production bundle has no `import.meta.hot`, so `reportWhyThePageReloaded` returns immediately.

It also writes to `console` rather than the app's own `logDev` helper, on purpose — a diagnostic shouldn't depend on the application it's watching.

## What describeReloadReason.test.ts is checking

The Bill Creator reloaded itself three times during a hands-on test and no log anywhere could say why.

This is the part that answers the question afterwards, so these examples are about the answer being RIGHT rather than merely present: the sentence has to separate "the dev server did this" from "the dev server did not", because those send a reader to completely different places.

## What reportWhyThePageReloaded.test.ts is checking

The recording half.

If this listens for the wrong event names, or writes nothing, the whole instrument reports "the dev server was not responsible" for every reload — a confident wrong answer, which is worse than the silence it replaces. So these examples fire the real event names Vite raises and read back what was stored. That covers production and the bundle the browser tests run against.

## Why IHotEvents exists

`IHotEvents` names the one thing `reportWhyThePageReloaded` needs from Vite, so a test can supply it.

## Why RECENT_MS is 30 seconds

Vite waits for the dev server to answer again before it reloads, so the gap between the event firing and the reload is not instant.

Vite waits for the dev server to answer again before it reloads, so the gap between the event firing and the reload is not instant; half a minute covers a slow restart without letting an unrelated event from earlier take the credit.

## Why the window ends at this page's load

The reasons `describeReloadReason` considers were recorded by the PAGE BEFORE this one, which is why the window ends at this page's load. Anything later belongs to a reload that has not happened yet.

## Why silence is treated as a finding worth reporting

When Vite recorded no reason, that's worth saying out loud rather than staying quiet. Silence here is a real finding: it rules Vite out and leaves a person, the browser, or something outside the dev server.

## Why the event descriptions are written for a reader who doesn't know Vite

`MEANING` phrases what each Vite event means in words that do not assume the reader knows how Vite's dev client works. All three end in the page reloading; they differ in what set it off.

## Why only the last 10 reasons are kept

A reload loop can announce itself several times in a few seconds, and the oldest entries stop being useful once that starts.

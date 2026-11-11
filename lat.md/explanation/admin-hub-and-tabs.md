---
lat:
  mode: explanation
---
# The admin hub and the Bill Creator's tabs

Sway's admin screens are reached from one page that lists them, and the Bill Creator's tabs are addresses rather than component state.

## Why /admin exists

`/admin` lists every admin tool, so a screen can be found without knowing its address.

The LLM settings page shipped with nothing in the interface linking to it, which
made a finished screen indistinguishable from one that was never built. The
drawer entry that used to read "Creator" now reads "Admin" and points here, and
the run-history screen was reachable only by typing its URL until a card for it
was added.

## Each Bill Creator tab has its own path

A tab is a URL, so a reader can link to one, reload it, or arrive back on it through the browser's history.

There is consequently no address for the tab that was once the default, and an
example demonstrating that a prop ships on every tab has to pick one of the real
tabs to prove it from. On an edit URL the bill id in the path is what the picker
shows; the empty-string default and the echoed query parameter belong to the
create flow, which carries no id in its path.

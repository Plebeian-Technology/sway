---
lat:
  mode: explanation
---

# Why the catch-all redirect spec makes real requests

The last line of `config/routes.rb` sends anything unrecognized to the front page.

That is right for somebody mistyping a link, and wrong for the app's own machinery: a missing route there is a fault, and a 301 hides it completely. (The redirect's own design — which hosts and paths it covers, and why — is documented in `config/routes.rb` itself, next to the route.)

## The fault a catch-all can hide

It can hide one. Every representative's photo is served from `/rails/active_storage`, and while that path reaches the catch-all the pictures vanish site-wide with no error page, nothing in Sentry, and nothing in any log.

## Why every example makes a real request

`spec/routing/catch_all_redirect_spec.rb` deliberately issues real HTTP requests rather than asking the router which route would match via `recognize_path`.

An example built on `recognize_path` passes whether the fault is present or not: the router names the Active Storage route while a real request goes to the redirect. The two disagree, and only the request tells the truth. An example that cannot fail is not a guard.

## Why the "catch-all switched on" example exists separately

The example that checks the redirect stays on whichever host the request named cannot fail on its own: by default the spec never declares a catch-all, so the redirect it describes is never drawn and `next` skips it.

A separate example turns the catch-all on — the only way to watch the redirect choose a host at all — and checks TWO hosts, not one. Sway answers to `sway.vote` and `app.sway.vote`, and a sign-in cookie only goes back to the host that set it, so a redirect that names one host signs out everyone who was on the other. One host cannot show that: a fixed destination and "wherever you were" agree whenever the reader happens to be on the fixed one.

## Why the "declared for production, and nowhere else" example reads the production file

Production still has somewhere to send people, and this example is what says so.

Without it, "no catch-all outside production" could quietly become "no catch-all anywhere" and nobody would find out until a mistyped link on the real site answered 404.

It reads the production environment file rather than restating what that file should say. An example that spells the value out again passes whether or not production declares anything, which would make it a guard in name only — deleting the declaration would not fail it.

Within that example, the assertion that `catch_all_enabled` is blank in the current (test) environment is deliberately `be_blank`, not `be_nil`. Reading any unset name off `config.x` hands back an empty `ActiveSupport::OrderedOptions` rather than `nil`, so `config/routes.rb` has to ask `present?` rather than `nil?`. A guard written as `unless ....nil?` would draw the catch-all in EVERY environment with an empty address, because the unset value comes back `{}`.

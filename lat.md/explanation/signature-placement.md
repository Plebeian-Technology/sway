---
lat:
  mode: explanation
---

# Where a signature is declared

A hand-written signature can sit under `sig/`, under `sig-test/`, or beside the class it describes. The choice follows from which type-check target reads the file, and from what the checker cannot work out on its own.

## Why a spec-only class is declared under sig-test

The `:app` target checks `app/` and `lib/` and ignores one-shot scripts under `db/data`. A class a spec requires therefore has no signature anywhere, while the `:test` target does check `spec/` and needs one.

Declaring it under `sig-test/` rather than `sig/` keeps that ignore meaningful: `sig/` goes on describing the surface the `:app` target answers for, and the declaration sits with the only code that reads it. A helper module reached from spec files alone follows the same rule, as does a seed class whose consumers are specs.

## Why the Sentry cron class methods are declared by hand

`Sentry::Cron::MonitorCheckIns.included` installs its class methods through `base.extend(ClassMethods)`, a shape Steep does not follow, so a job that schedules a monitor check-in reports no such method.

The three names that mixin installs are therefore restated on each job that includes it.

## Why a concern declares the host whose helpers it reaches

A concern reaches a private helper its host acquires from a different include. Steep resolves the call against the concern alone, where the helper does not exist.

Naming both the controller base class and the module that supplies the helper as self-types states what `self` really is at the call site.

## Why a string-keyed record is written as a Hash

RBS accepts a record type whose keys are strings, and `rbs validate` is clean on one. Steep converts a type back to RBS through a factory that raises unless every key is a Symbol, so such a record aborts the check for its whole file.

The abort carries no diagnostic and follows the type alias rather than anything inside it, so a file it stops reading looks covered while nothing in it is checked. The shapes that drive a conversion are therefore written as `Hash` types, and the per-key precision is given up to keep the file checked at all. A sibling record that nothing routes through that conversion has not crashed, and is the first place to look if the abort returns.

## Why only some value objects carry a runtime guard

A union declared on a plain value object is enforced at every call site the checker can see, so a runtime check adds nothing where the only caller is the service that owns the object.

`Litestream::ReplicaReading` takes its status from callers the checker cannot reach and raises `ArgumentError` on anything outside the union. `Litestream::LagDecision` is built only by the check that owns it, from inputs that check controls, and declares the union alone.

## Why a controller action's return type is untyped

`render` answers with Rails-internal types whose shape moves between versions, so pinning an action's return type buys nothing and breaks on the next upgrade.

Controller actions are declared `() -> untyped` throughout. It is an explicit exception to the project's preference for concrete types, taken once rather than argued per action.

## Why a controller restates the helpers a concern mixes in

The shared-props lambda is checked with `self` bound to the controller's singleton, so a helper a concern mixes in is out of scope there unless the controller's own signature declares it.

The methods are restated on the controller, and on its singleton as well where the lambda is the only reader.

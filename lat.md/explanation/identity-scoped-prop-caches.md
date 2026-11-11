# Identity-scoped prop caches

A cached Inertia prop is served to whoever asks for it next. Sway has already shipped one cross-user leak of this kind: three jurisdiction props were marked as once-props, and one reader's list stayed on screen for the next person.

Inertia v3 adds more ways to make the same mistake. `InertiaRails.once` holds a
value across a reader's visits, and `InertiaRails.cache` stores it in
`Rails.cache` under an `inertia_rails/` prefix with the key left entirely to the
caller. A mis-keyed `cache:` is the worse of the two: a once-prop leaks to one
device, a shared cache entry leaks to everybody at once.

The pattern that is safe is not "cache less" but "cache the part that belongs to
nobody". `app/controllers/api/v1/bootstrap_controller.rb` caches the bill of the
week, which is the same for every reader in a locale, and merges the reader's
own vote in after the cache read.

## The gate

`bundle exec rake sway:lint:inertia_prop_cache` fails when a prop cache carries
no user, locale or role in its key.

`lib/inertia_prop_cache_check.rb` parses every Ruby file under `app/` other than
`app/frontend/` with Prism, and looks for a call on `InertiaRails` that either
names `once` or `cache`, or carries a `cache:` or `once:` keyword — the caching
options ride `optional`, `defer` and `merge` props too, so the method name alone
would miss half of them. The arguments' own source text is what is searched for
a discriminator, so an interpolated `current_user.id` counts as one.

A cache of something that genuinely belongs to nobody would be reported too. The
answer for one is a path in `InertiaPropCacheCheck::ALLOWED_PATHS`, which is
empty, because there is no prop cache in the application today — the gate exists
to make the next one a decision somebody made on purpose.

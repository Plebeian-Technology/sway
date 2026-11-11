---
lat:
  mode: explanation
  require-code-mention: true
---

# User preference request tests

Preference request specs distinguish the database-backed theme mode from the signed-cookie theme id and pin both browser and JSON behavior.

## An invalid theme mode uses the JSON validation contract

The bearer request asserts the 422 `validation_failed` envelope for an invalid `theme_mode` and confirms that the stored value remains unchanged.

## An invalid theme id uses the JSON validation contract

The bearer request asserts the 422 `validation_failed` envelope for an invalid `theme_id` and confirms the rejected value is not written to the signed cookie.

The browser path can report validation through an Inertia error prop or a rendered page, so it does not promise one status code. JSON callers have a stable response contract; [[spec/requests/users/preferences_spec.rb]] verifies the error code and that the rejected id is not stored.

## Theme helper examples seed the signed cookie store

The request spec checks the default, valid, and rejected theme ids by seeding `cookies_hash`, the backing store returned by `SessionDouble`'s stubbed `cookies.signed` jar.

The request spec's cookie jar does not expose the signed-cookie interface. Tests that need [[app/helpers/theme_helper.rb#ThemeHelper#theme_id]] to read a value therefore seed the shared test store directly and issue a request that renders the theme.

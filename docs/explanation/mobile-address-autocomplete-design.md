---
mode: explanation
summary: Why AddressAutocomplete uses the native Google Places SDK instead of a plain fetch, the bundle-ID key lock, the missing Android key, and the selectedDescription reopen guard.
status: agent-extracted
related: []
---

# AddressAutocomplete design

One text box that suggests addresses as you type, using the
native Google Places SDK through react-native-google-places-sdk.

## Why the native SDK instead of a plain fetch

Our Google Cloud API key is locked to the app bundle ID vote.sway.app. Google
enforces that lock by checking a signature the SDK adds to every request; a plain
HTTPS fetch carrying an X-Ios-Bundle-Identifier header comes back 403. The SDK does
the signing, so the key stays locked down on Google's side.

The SDK is set up once when the app starts, in App.tsx (see useGooglePlacesInit).
This component is a thin wrapper around fetchPredictions and fetchPlaceByID that
waits for a pause in typing before asking.

## Android note

There is no separate Android key yet — one locked to the package name
and the app's SHA-256 signing fingerprint — so the component still renders on
Android, but Google answers suggestion requests with a permission error.
AddressScreen lets Android users type the address in by hand instead.

## `MIN_QUERY_CHARS`

Fewer calls cost less, and one or two letters only produce useless suggestions.

## `selectedDescription` reopen guard

When the user picks a suggestion we put its text into the box ourselves. Without
remembering that here, the effect below would run again and re-open the dropdown
with the very same suggestions. As soon as the user edits the text so it differs
from selectedDescription, suggestions start again.

## Predictions list: no FlatList

There are at most 5 suggestions, so a plain map is enough. It also
keeps a scrolling list out of the ScrollView above, which React
Native warns about: "VirtualizedLists should never be nested
inside plain ScrollViews".

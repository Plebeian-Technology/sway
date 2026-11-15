---
lat:
  mode: explanation
---

# AddressAutocomplete design

One text box that suggests addresses as you type, using the native Google Places SDK through react-native-google-places-sdk.

## Why the native SDK instead of a plain fetch

Our Google Cloud API key is locked to the app bundle ID vote.sway.app.

Google enforces that lock by checking a signature the SDK adds to every request; a plain HTTPS fetch carrying an X-Ios-Bundle-Identifier header comes back 403. The SDK does the signing, so the key stays locked down on Google's side.

The SDK is set up once when the app starts, in App.tsx (see useGooglePlacesInit). This component is a thin wrapper around fetchPredictions and fetchPlaceByID that waits for a pause in typing before asking.

## Android note

There is no separate Android key yet — one locked to the package name and the app's SHA-256 signing fingerprint — so the component still renders on Android, but Google answers suggestion requests with a permission error.

AddressScreen lets Android users type the address in by hand instead: the screen posts the typed fields without coordinates, and the server accepts them (see [[mobile-auth-and-onboarding-flow#AddressScreen]]).

## MIN_QUERY_CHARS

Fewer calls cost less, and one or two letters only produce useless suggestions.

## selectedDescription reopen guard

When the user picks a suggestion we put its text into the box ourselves.

Without remembering that here, the effect below would run again and re-open the dropdown with the very same suggestions. As soon as the user edits the text so it differs from selectedDescription, suggestions start again.

A box mounted with a saved address starts with that address as selectedDescription. Opening Edit address therefore makes no billed search and shows no list until the user edits the text.

Picking also invalidates any suggestion request still in flight. Otherwise a slow response for the text typed just before the pick would arrive afterwards and reopen the list, or show an error, over a valid choice. The same counter guards the details lookup of the pick itself: a search started before that lookup resolves invalidates it, so a late place cannot overwrite what the user has since typed.

## Editing the search text clears the form

Any edit of the search text, through the box's `onQueryChange` callback, empties the address form on `AddressScreen`, so Submit never posts an address the box no longer shows.

A saved address is prefilled into the box and the form, and a picked place fills both. Without the clear, editing the text without picking a suggestion would leave the old address in the form while the box showed the new text. After the clear Submit stays disabled until the user picks a suggestion or fills the manual fields; the country is kept. The edit also drops selectedDescription, so typing the old text back brings suggestions again, and it invalidates a place lookup still in flight, so a late pick cannot refill the form behind the edited text. The manual path never renders the box and is unaffected.

## Predictions list: no FlatList

There are at most 5 suggestions, so a plain map is enough. It also keeps a scrolling list out of the ScrollView above, which React Native warns about: "VirtualizedLists should never be nested inside plain ScrollViews".

## Every picked place is passed on, and library text never shows

Whatever place the user picks reaches AddressScreen through onSelect, with empty strings or null coordinates for the parts Google did not return.

The server accepts an address as a fact and resolves it generically, so the component has no reason to refuse an incomplete place. A failed search or details lookup tells the user a fixed sentence that points to the typing option; the raw library text (a permission or quota code) is never shown, because it reads as a developer string and tells the user nothing to do.

## The country is the ISO code

A picked place posts its country as the ISO code (`US`), read from the component's short name, not its long name.

The native Places SDK localizes the long name, so a phone set to Spanish reports `Estados Unidos`, which the server's country mapping does not recognise; the state is read as an ISO code for the same reason. A place with no country component still falls back to `United States`.

---
mode: explanation
summary: "Why mobile/src/utils/locale.ts and phone.ts exist as separate, string-based ports of web logic (ISwayLocale formatting, phone-number formatting) rather than shared imports."
status: agent-extracted
related: [docs/explanation/sway-locale-model-design.md]
---

<!-- vale Vale.Spelling = NO -->

# Mobile web-parity utils: locale and phone formatting

## `mobile/src/utils/locale.ts`: matching the web's `ISwayLocale`

The `Locale` type, plus helpers for showing a locale to a person, matches
the web's `ISwayLocale`. The web defines `sway.ISwayLocale` in
`app/frontend/index.d.ts` and has `toFormattedLocaleName` in
`app/frontend/sway_utils/locales.ts`. The bootstrap API
(`/api/v1/bootstrap`) sends the whole shape through `SwayLocale#to_builder`,
so mobile was already receiving every field; it just was not typing them
or turning them into readable text.

`name` is the slug the system uses, such as
`baltimore-maryland-united_states`. Anywhere it is shown to a person, it is
run through `toFormattedLocaleName` to get "Baltimore, Maryland, United
States".

## `mobile/src/utils/phone.ts`: matching the web's phone formatting

Phone-number formatting for mobile is carried over from
`app/frontend/sway_utils/phone.ts`. On the web,
`PHONE_INPUT_TRANSFORMER.output` is handed a React change event; React
Native's `TextInput` hands `onChangeText` a plain string, so the mobile
version works on strings. Everything else — the formatting and the
checks — matches the web exactly, so the two stay in step: US numbers of
10 digits, no `libphonenumber-js`, and a hard stop at 10 bare digits.

`PHONE_INPUT_TRANSFORMER` converts in both directions for a controlled
`TextInput`:

```
value={PHONE_INPUT_TRANSFORMER.input(phone)}
onChangeText={(text) => setPhone(PHONE_INPUT_TRANSFORMER.output(text))}
```

State holds bare digits, up to 10 of them; what the user sees is the
formatted version. A leading `"1"` country code is stripped, so pasting a
number written with `+1` in front does not double up the area code.

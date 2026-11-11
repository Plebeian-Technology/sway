---
mode: explanation
summary: "Why RegionUtil.from_country_name_to_code and COUNTRY_NAMES_CODES were deleted, and what the remaining spec examples pin."
status: agent-extracted
related: []
---

<!-- vale Vale.Spelling = NO -->

# Why `from_country_name_to_code` and `COUNTRY_NAMES_CODES` were deleted

Nothing in the repository called `RegionUtil.from_country_name_to_code` or
referenced `COUNTRY_NAMES_CODES`, and the method gave the wrong answer
anyway: it looked the input up in the code-to-name hash, so passing in
`"United States"` came back as `"United States"` rather than a code.

`spec/lib/region_util_spec.rb` pins the lookups that remain —
`.from_region_name_to_region_code` and `.from_region_code_to_region_name`
— so a later refactor cannot quietly break the region and country
conversions that ARE in use, in `app/models/address.rb`,
`app/models/sway_locale.rb`, and `SwayRegistrationService`.

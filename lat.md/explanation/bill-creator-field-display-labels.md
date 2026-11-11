---
lat:
  mode: explanation
---

# Why Bill Creator field display labels are centralized

Why AUDIO_FIELD_LABELS and BILL_FIELD_LABELS exist as single sources of truth for Bill Creator form field labels, and why fieldDisplayName's titleize fallback is effectively unreachable from BillCreatorOrganizations.

## Why AUDIO_FIELD_LABELS exists as a separate table

The on-screen labels for the two audio fields, in one place.

The only two bill-form fields BILL_INPUTS omits (via TOmitKeys in inputs.ts), so fieldDisplayName can't derive their labels the way it derives every other one.

BillCreatorSummaryAudio renders these, fieldDisplayName reads them, and the test reads them — one spelling, not three, so a rename can't drift out of sync.

## Why BILL_FIELD_LABELS is built once from BILL_INPUTS

The form's own label for each field, keyed by the name the storage hook is handed. Built once from BILL_INPUTS, so a renamed label moves with the field rather than being spelled a second time here.

The two audio fields come from a second source: BILL_INPUTS drops them via inputs.ts's TOmitKeys, but BillCreatorSummaryAudio still renders them inside SummaryField with the same onBlur.

They're imported from the const that component renders them from, so the rule above holds for them too.

## Why fieldDisplayName falls back to titleize, and why BillCreatorOrganizations never reaches it

What to call a field when the draft indicator says which one was just saved.

Looks up BILL_FIELD_LABELS first; falls back to titleize(name, "_") for any name with no entry there, so even an unclaimed field name reads as words instead of raw schema.

BillCreatorOrganizations (via BillCreatorFormHeader) never actually reaches this fallback: it never calls onBlur/storeField, so blurredFieldName stays "" and the indicator stays invisible there.

## Why the "Stored temporary" indicator uses fieldDisplayName instead of the raw field name

The field's own label, not its column name. `titleize` splits on a space, so a snake_case name came back as "Introduced_date_time_utc". See fieldDisplayName.

## Why BillCreatorFormHeader is the V2 form header

The V2 version of the bill creator's form header. It keeps two things from the old header: the "recently saved" indicator, and the "Don't Save + Reset to New" way out.

## inputs.ts / BILL_INPUTS notes

Design notes and conventions governing input configuration constants, validation schemas, and field rendering metadata.

### Why the file stays at this path for now

`inputs.ts` sits at this path because the since-deleted V1 tree imported it from here. It can now move into `components/admin/creator/`; that move has not been made yet.

### Why summary_ai_unreviewed is omitted from TOmitKeys

Not a field anyone fills in. The server works it out from the summary and the model's draft, and sends it so the bill page can show a notice (see [[docs/explanation/ai-unreviewed-notice-component-design.md|Why AiUnreviewedNotice is a single shared component]]).

### Why chamber has no default

Nothing read it, and it was a fourth copy of the wrong "council" guess sitting where a reader would trust it. The real default comes from the jurisdiction, through `ISwayLocale#default_bill_chamber`.

`chamber`'s `disableOn` is off when the jurisdiction has only one chamber, because there is nothing to pick. It is left ON when nobody has declared the jurisdiction: greying a field out is a claim about the place, and Sway has none to make there.

### Why senate_vote_date_time_utc's disableOn reads bill_chambers ??

Off when the jurisdiction has no upper chamber — same rule as `chamber` above for an undeclared place, written the same way.

It used to read `bill_chambers !== null`, which is TRUE for `undefined`, so a payload missing the key threw inside `.includes` — during render, so it took the Bill Creator down. `?? []` makes "nobody declared this" and "the key never arrived" one answer.

### Why the category dropdown was removed

The old single-subject `category` dropdown was removed from the form.

Subject categories are now one feature: they are assigned while the summary is generated, and can be changed per bill on the Summary & Positions screen. The `bills.category` column still exists, defaulting to `""`, but nothing fills it in from this form any more.

## fieldDisplayName.test.ts notes

fieldDisplayName exists because titleize splits on spaces, not underscores, so a raw snake_case column name would render as one long capitalized word.

These three names only became reachable after the SelectField autosave fix — before that fix no field name was set at all.

audio_bucket_path/audio_by_line aren't in BILL_INPUTS but still hit fieldDisplayName via SummaryField's onBlur, so the fallback answered them wrong.

Reads the label off AUDIO_FIELD_LABELS instead of a literal string, so this test can't drift out of sync with what the component actually renders.

Generic test assertions verify fallback formatting for any unclaimed field name rather than binding tests to unused components.

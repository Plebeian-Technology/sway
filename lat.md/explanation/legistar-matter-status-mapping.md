---
lat:
  mode: explanation
---

# Legistar matter status mapping

Baltimore legislation reports thirty-nine upstream `MatterStatusName` values in Legistar. Sway maps each known name onto one of four canonical bill statuses on ingest so legislative progress is reflected without guessing.

## Why Legistar names collapse onto four statuses

Sway bill statuses are a four-word lifecycle summary (`passed`, `failed`, `committee`, `vetoed`), not a translation of Legistar's procedural vocabulary.

Several Legistar status names represent intermediate procedural milestones in the Baltimore City Council (such as readings, hearings, and committee referrals). These active steps map onto `committee`. Enacted legislation, executive signings, and council confirmations map onto `passed`. Expirations, committee discharges at end of term, and formal withdrawals map onto `failed`. Formal mayoral vetoes map onto `vetoed`.

## The Baltimore Legistar status vocabulary

Every distinct `MatterStatusName` observed on Baltimore Legistar matters maps deterministically to a canonical status or maps to nil when unrecognised.

| Legistar `MatterStatusName` | `MatterStatusId` | Legislative Meaning | Sway `Bill#status` |
|---|---|---|---|
| `Adopted` | 8 | Final favorable vote of Council | `passed` |
| `Enacted` | 18 | Signed by Mayor or enacted into law | `passed` |
| `Signed by Mayor` | 21 | Signed by the Mayor | `passed` |
| `Passed` | 72 | Passed, approved, or adopted | `passed` |
| `Confirmed` | 23 | Executive nomination confirmed by Council | `passed` |
| `Confirmed after 3 Meetings without Council Action` | 37 | Confirmed without Council objection | `passed` |
| `Matter Concluded` | 26 | Oversight matter closed | `passed` |
| `Failed` | 65 | Denied passage by Council | `failed` |
| `Failed - End of Term` | 27 | Expired without passage at term end | `failed` |
| `Withdrawn` | 75 | Withdrawn from consideration | `failed` |
| `Rules Withdrawn` | 24 | Council rule change amendment withdrawn | `failed` |
| `Filed` | 74 | Received and filed or procedurally expired | `failed` |
| `Vetoed by Mayor` | 16 | Mayoral return or pocket veto | `vetoed` |
| `In Committee` | 1 | Assigned to committee | `committee` |
| `Referred` | 68 | Referred to committee | `committee` |
| `1st Reader` | 17 | First reading | `committee` |
| `First Reading` | 76 | First reading | `committee` |
| `2nd Reader` | 5 | Scheduled for second reading | `committee` |
| `Second Reading` | 71 | Undergoing second reading | `committee` |
| `3rd Reader, final passage` | 9 | Scheduled for third reading | `committee` |
| `3rd Reader, advance from 2nd on same day` | 12 | Advanced under Rule 1001 | `committee` |
| `3rd Reader, to be held one meeting` | 13 | Held over one meeting | `committee` |
| `3rd Reader, to be held two meetings` | 36 | Held over two meetings | `committee` |
| `3rd Reader, enrolled for final passage` | 14 | Enrolled for final passage | `committee` |
| `3rd Reader, recalled from the Mayor's Office` | 15 | Recalled from Mayor for third reader | `committee` |
| `Introduced In Council` | 6 | Ready for introduction | `committee` |
| `Before the Mayor` | 11 | Awaiting mayoral action | `committee` |
| `Return from Mayor's Desk for Further Consideration Requested` | 38 | Recall requested from Mayor | `committee` |
| `Returned from Mayor's Desk for Further Consideration` | 39 | Returned from Mayor | `committee` |
| `Nominated` | 20 | Executive appointment introduced | `committee` |
| `Introduction of Rule Change` | 22 | Rule change introduced | `committee` |
| `Worksession` | 35 | Committee worksession | `committee` |
| `New Business` | 63 | Ready for initial Council agenda | `committee` |
| `Reported to Council` | 66 | Reported out to Council agenda | `committee` |
| `Public Hearing` | 69 | Scheduled for public hearing | `committee` |
| `Held` | 77 | Postponed by committee | `committee` |
| `Agenda Ready` | 80 | Placed on agenda | `committee` |
| `Consent Agenda` | 84 | Placed on consent agenda | `committee` |
| `Tabled` | 85 | Tabled by Council | `committee` |

## Stored values for repaired bills fifty-eight and fifty-nine

Bills 58 and 59 in the production database held invalid blank statuses that broke validations, requiring authoritative upstream values from Legistar.

Direct inspection of upstream records for both matters provides the exact status values:
- **Bill 58** (`MatterFile 24-0599`, `MatterId 9906`): `MatterStatusName` is `"Failed - End of Term"`, which maps to `"failed"`.
- **Bill 59** (`MatterFile 24-0592`, `MatterId 9895`): `MatterStatusName` is `"Enacted"`, which maps to `"passed"`.

Repairing these rows with their upstream statuses restores valid model state without inventing facts.

## Ingestion pipeline status boundary

The ingestion pipeline maps `MatterStatusName` during metadata extraction, passing nil rather than an empty string when upstream status is absent.

`FetchBillsService#build_metadata` applies `Legistar::StatusMapper.map` to `matter["MatterStatusName"]` and assigns the result to `metadata[:status]`. `FetchBillsService#bill_data_from_metadata` forwards this key to the payload dictionary. In `LegislationIngestionService#apply_bill_attributes`, `status` is copied to the `Bill` record if non-nil. When the upstream record provides no status, the mapped value arrives as `nil`, allowing `bill.status ||= "committee"` to supply the fallback without persisting blank values.

---
lat:
  mode: reference
  require-code-mention: true
---
# Representative history reason tests

These request tests pin how inactive representative links are labelled in history.

## Completed term with recorded end date

A term with an observed end date before today is labelled `term_ended` when its district remains active for the reader.

## Still-running term with inactive link

A deactivated user-legislator link to a term still running in the reader's active district is labelled `link_inactive`.

## Unknown calendar does not imply an ended term

A term with no recorded end date in a locale without a declared calendar is labelled `link_inactive` instead of being guessed as ended.

## Completed term at the fallback calendar boundary

A term without a recorded end date is labelled `term_ended` on the end date supplied by its declared locale calendar.

## Changed district

A term in a district that is no longer active for the reader is labelled `district_changed`, including while that term is running.

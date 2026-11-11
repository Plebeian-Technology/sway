---
lat:
  mode: explanation
  require-code-mention: true
---

# Notification delivery browser coverage

The browser example proves that an opted-in user can complete the notification flow and invoke delivery.

## The system example covers the notification flow

The example drives preference consent, save feedback, persisted state, and notification delivery through the browser.


SMS consent uses the shared control contract in [[sms-consent-copy-verbatim#Why a checkbox and not a toggle]].

## Saving preferences is confirmed at both boundaries

The example waits for the server flash and then checks the persisted preference. The visible response and stored state together prove the save completed.

## The example invokes the delivery service after consent

The system example invokes the notification service after persisting consent so delivery behavior is exercised through the real preference boundary.

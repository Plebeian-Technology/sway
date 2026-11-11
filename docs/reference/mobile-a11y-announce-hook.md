---
mode: reference
summary: Contract for useA11yAnnounce — what it announces to a screen reader, and the privacy limits on what may be passed to it.
status: agent-extracted
related: []
---

# useA11yAnnounce hook

`useA11yAnnounce` (`mobile/src/hooks/useA11yAnnounce.ts`) says a short
message out loud to a screen reader.

It hands you a function. Call it with a brief, throwaway confirmation such
as "Vote saved" or "Following ACLU" and React Native's
`AccessibilityInfo.announceForAccessibility` speaks it.

## Usage

```
const announce = useA11yAnnounce();
announce("Vote saved");
```

## Privacy

Use this only for throwaway confirmations. Never pass personal details,
login tokens, phone numbers, or anything read out of the phone's encrypted
keychain (`expo-secure-store`). `announceForAccessibility` repeats the text
word for word to whichever screen reader is running, and on iOS that text
can be captured in a Voice Control transcript.

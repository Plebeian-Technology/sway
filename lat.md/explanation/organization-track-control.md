---
lat:
  mode: explanation
---
# Organization track control

The control beside an organization is an action button, not a toggle: it says what pressing it does, and the track state itself is shown on the card.

## Why a switch and its badge read different sources

The notification switch reads form state and the badge beside it reads the saved prop, because the two answer different questions.

The switch answers what the operator is choosing, so it has to move the instant
it is clicked. The badge answers what the server has stored, so it must not.
Binding the badge to form state made it flip to Enabled on the click and keep
saying so after a save that failed — reporting a state nothing had recorded.
The badge is therefore never re-bound from the form.

## Why the control carries no aria-pressed

A toggle names its state and reports it with `aria-pressed`; an action button names what it does. This control names what it does — track, or Untrack — so it carries no `aria-pressed`.

It used to carry both conventions at once. The untrack button read "Untrack NAME" to a screen reader and reported `aria-pressed="true"` with it, so the announcement mixed an instruction with a state: the word said do this, the state said this is on.

The state has somewhere better to live. Commit 9f9950497 moved the "tracking" badge onto the organization card, which is where a reader looking for whether they track an organization goes, and left this control to name the one action available. Returning the label to a state word would undo that.

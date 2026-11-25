---
lat:
  mode: explanation
---
# Vote majority vocabulary

Sway calculates how a user's vote aligns with resident tallies using vote-specific majority terminology rather than organization position vocabulary.

## Problem context and terminology divergence

The user-standing helper previously described resident voting tallies using organization position vocabulary, creating an architectural contradiction with Sway's domain canon.

The canonical domain vocabulary in [[docs/terminology.md]] establishes an explicit split between two distinct actors: people cast votes (`For`, `Against`, `Abstain`), while organizations hold positions (`Support`, `Oppose`, `Neutral`). Organizations never vote, and resident voters do not hold organization positions on bills. Describing a community vote tally with "Support leading" or "Opposition leading" conflates these two vocabularies and implies that voters hold positions rather than casting votes.

Additionally, the concept of "standing" is retired across the application. The system represents user alignment through whether a vote stands with or against the resident majority (`withMajority`).

## Architectural decision

The project uses vote-specific majority terminology in the selector API and in its reader-facing labels; the current contract is documented below.

## Replacement architecture

The replacement helper and its associated types establish clear contracts centered on vote majority calculations.

The replacement module [[app/frontend/components/bill/sway_utils/billPositions.ts]] defines the following types and function contract:

### VoteMajorityStatus type

The status union represents the four mutually exclusive outcomes of a resident vote tally:

```typescript
export type VoteMajorityStatus =
    | "No votes yet"
    | "Evenly split"
    | "For leading"
    | "Against leading";
```

### VoteMajorityResult interface

The result interface communicates the voter's participation, vote direction, current tally majority status, and majority alignment:

```typescript
export interface VoteMajorityResult {
    userVoted: boolean;
    userSupports: boolean;
    majorityStatus: VoteMajorityStatus;
    withMajority: boolean | null;
}
```

The property `majorityStatus` replaces `standing`. The property `userSupports` preserves boolean alignment with the database column `user_votes.support` (`userVote?.support === Support.For`).

### selectVoteMajority helper

The helper function computes the majority outcome from a user's cast vote and the bill's rounded For and Against percentages:

```typescript
export const selectVoteMajority = (
    userVote: sway.IUserVote | null | undefined,
    tally: VoteTally,
): VoteMajorityResult => {
    const { forPercent, againstPercent } = tally;
    const userVoted = Boolean(userVote);
    const userSupports = userVote?.support === Support.For;
    const majorityStatus: VoteMajorityStatus =
        forPercent + againstPercent === 0
            ? "No votes yet"
            : forPercent === againstPercent
              ? "Evenly split"
              : forPercent > againstPercent
                ? "For leading"
                : "Against leading";
    const withMajority =
        userVoted && forPercent + againstPercent > 0 && forPercent !== againstPercent
            ? userSupports === forPercent > againstPercent
            : null;
    return { userVoted, userSupports, majorityStatus, withMajority };
};
```

## Implementation

The bill layout and selector implement the majority vocabulary while preserving the tally and alignment rules.

[[app/frontend/components/bill/layouts/BannerBillLayout.tsx]] renders `majorityStatus` from [[app/frontend/components/bill/sway_utils/billPositions.ts#selectVoteMajority]]. The selector returns the four statuses defined by [[vote-majority-vocabulary#Vote majority vocabulary#Replacement architecture#VoteMajorityStatus type]]; the tests pin both leading labels, no-vote and tie outcomes, and the existing alignment cases. `userSupports` continues to reflect the user's `user_votes.support` value, and `withMajority` retains its existing null cases and comparison.

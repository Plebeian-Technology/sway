# Voter privacy threshold

Sway protects voter anonymity by withholding vote tally comparisons until a minimum of ten distinct users have participated on a bill.

When the total number of 'For' and 'Against' votes is below `VoteComparisonPrivacy::MINIMUM_VOTERS` (10), comparison data is suppressed to prevent identification based on small-sample tallies. Payloads include `comparison_suppressed` and `voters_needed` to support placeholder rendering on clients.

// Prints a red verify run's failing examples as file:line plus a one-line
// description, capped at 15 across the WHOLE run rather than per lane,
// so one broken shared factory producing hundreds of failures cannot bury the
// lane table above it. summary.json still carries every one of them, uncapped.
//
// Reads the JSON that scripts/dip/verify-summary.mjs just wrote, so the list
// is assembled in exactly one place. Takes SUMMARY_PATH.
//
// Its own file rather than a `node -e` string inside verify.sh, for the same
// reason as its sibling: a string is invisible to the linter and cannot be run
// against a known input.
import fs from "node:fs";

const CAP = 15;

const summary = JSON.parse(fs.readFileSync(process.env.SUMMARY_PATH, "utf8"));

let shown = 0;
for (const lane of summary.lanes) {
    const failing = lane.failing_examples || [];
    if (failing.length === 0) continue;

    const toShow = failing.slice(0, Math.max(CAP - shown, 0));
    toShow.forEach((line) => console.log(line));
    shown += toShow.length;

    // Named per lane, not once at the end: past the cap the reader needs to
    // know WHICH log holds the rest, and that differs by lane.
    const leftover = failing.length - toShow.length;
    if (leftover > 0) console.log(`+${leftover} more in ${lane.log}`);
}

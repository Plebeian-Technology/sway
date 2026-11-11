// Builds a verify run's summary.json out of the tab-separated lane facts
// scripts/dip/verify.sh writes.
//
// Its own file rather than a `node -e` string inside that script: as a string
// it was invisible to the linter and the formatter, and nothing could run it
// against a known input to see what it produced. It decides what every later
// reader of a run is told, including the failing-example list printed at the
// end of a red run.
//
// Takes six environment variables, which is the interface it already had:
// RUN_ID, STARTED_AT, TOTAL_DURATION, EXIT_CODE, FACTS_FILE, SUMMARY_PATH.
import fs from "node:fs";

// rspec prints one "Failed examples:" block per worker that had any, each line
// already a copy-pasteable rerun command — used verbatim, not
// reformatted. A log that cannot be read yields no examples rather than
// stopping the summary: a lane killed before it wrote one still has a state,
// a duration and an exit code worth recording.
function failingExamplesFrom(log) {
    let text;
    try {
        text = fs.readFileSync(log, "utf8");
    } catch {
        return [];
    }
    return text.match(/^rspec\s+\S+:\d+\s+#.*$/gm) || [];
}

// One line per lane, written by verify.sh in this exact column order. An empty
// column means the lane has no such number — a lane that is not rspec counts
// no examples — and stays null rather than becoming 0, which would read as
// "counted, and there were none".
function laneFrom(line) {
    const [name, state, duration, exitCode, oom, log, rerun, examples, failures, checksRan, checksFailed] =
        line.split("\t");
    const count = (value) => (value === "" || value === undefined ? null : Number(value));

    return {
        name,
        state,
        duration_seconds: Number(duration),
        exit_code: exitCode === "" ? null : Number(exitCode),
        oom_killed: oom === "true",
        examples: count(examples),
        failures: count(failures),
        checks_ran: count(checksRan),
        checks_failed: count(checksFailed),
        failing_examples: name.startsWith("rspec-") ? failingExamplesFrom(log) : [],
        log,
        rerun,
    };
}

const lines = fs.readFileSync(process.env.FACTS_FILE, "utf8").split("\n").filter(Boolean);

const summary = {
    run_id: process.env.RUN_ID,
    started_at: process.env.STARTED_AT,
    duration_seconds: Number(process.env.TOTAL_DURATION),
    exit_code: Number(process.env.EXIT_CODE),
    lanes: lines.map(laneFrom),
};

fs.writeFileSync(process.env.SUMMARY_PATH, JSON.stringify(summary, null, 2) + "\n");

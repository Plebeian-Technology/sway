import { TFeatureNoteGroup } from "app/frontend/components/admin/creator/feature-notes/types";

export const PIPELINE_TAB_NOTES = {
    "pipeline.runSelector": {
        feature: "the run picker",
        note: "Older runs stay on this list so a failure can be compared with the run before it.",
    },
    "pipeline.perBillGrid": {
        feature: "the list of bills in this run",
        note: "A run can touch hundreds of bills, so this is how you find the one you came to watch.",
    },
    "pipeline.stageColumn": {
        feature: "the Stage column",
        note: "This goes blank once a run is over, because naming a stage would suggest work is still going.",
    },
    "pipeline.summaryBatchNotice": {
        feature: "the awaiting-summaries notice",
        note: "Summaries bought in bulk cost half as much but can take a day, so a quiet run is not a stuck one.",
    },
    "pipeline.failureHeader": {
        feature: "the failure banner",
        note: "Names the stage that failed, so you can see what Resume will skip and what it will try again.",
    },
    "pipeline.resumeRestart": {
        feature: "Resume and Restart",
        note: "Resume starts at the stage that failed and keeps the work already done; Restart does all of it again.",
    },
    "pipeline.forceFail": {
        feature: "Force fail",
        note: "Marks a stuck run failed so the Run button works again; typing the phrase is the guard against a slip.",
    },
    "pipeline.stageSelector": {
        feature: "the stage list",
        note: "A run does only the stages ticked here, so you can redo one step without redoing the expensive ones.",
    },
    "pipeline.prerequisiteWarning": {
        feature: "the missing-prerequisites warning",
        note: "Nothing has failed yet — this is what would fail, so you can fix it before starting the run.",
    },
    "pipeline.statusBadge": {
        feature: "the run status word",
        note: "One word for where the run stands, which can still read Running for a run nothing is working on.",
    },
    "pipeline.abandonedNotice": {
        feature: "the notice that nothing is working on this run",
        note: "The progress bar is hidden here because a bar that cannot move reads as work still happening.",
    },
    "pipeline.runningDetail": {
        feature: "the current bill line",
        note: "The bill being worked on now, with how many are left, so a long run is not a black box.",
    },
    "pipeline.cachedStages": {
        feature: "the list of stages in this run",
        note: "Shows which stages Resume will skip because they already succeeded.",
    },
    "pipeline.cancelRunProgress": {
        feature: "Cancel run",
        note: "Stops a run, or clears one nothing is working on, which is what frees the Run button.",
    },
    "pipeline.testimonyReport": {
        feature: "the testimony report",
        note: "Lets you check what the model was actually given before you trust the positions it drafted.",
    },
    "pipeline.recordBar": {
        feature: "the bar showing what reached the model",
        note: "Drawn at true scale, so you can see at a glance how much of the testimony fitted.",
    },
    "pipeline.campaignsTable": {
        feature: "the campaigns table",
        note: "Groups identical letters so a coordinated campaign is not counted as many separate people.",
    },
    "pipeline.pastedTestimony": {
        feature: "the pasted-testimony block",
        note: "Pasted text is joined before the letters, so what gets pushed out is a real letter, not your paste.",
    },
    "pipeline.sendingServiceDecision": {
        feature: "the sending-service label",
        note: "No automatic rule labels a domain — your decision is the only thing that does, and it can be changed.",
    },
    "pipeline.sweepStale": {
        feature: "removing stuck runs",
        note: "Stuck runs are marked failed and kept for the record, so this frees the Run button without losing them.",
    },
    "pipeline.deleteOrphans": {
        feature: "deleting orphan runs",
        note: "This is the one control here that throws rows away for good rather than marking them failed.",
    },
    "pipeline.resourceCache": {
        feature: "the resource cache table",
        note: "Shows which downloaded pieces a re-run would build again and which it would reuse.",
    },
    "pipeline.fetchedBills": {
        feature: "the fetched-bills list",
        note: "Lists bills downloaded to disk even when no bill record exists, the only way to spot a stray download.",
    },
    "pipeline.activityLog": {
        feature: "the activity log",
        note: "The running record of what the pipeline did, kept so a finished run can still be explained.",
    },
    "pipeline.activityLogNewEntries": {
        feature: "the new-entries button",
        note: "New events wait for a click so the page you are reading does not shift under you.",
    },
    "pipeline.activityLogOlder": {
        feature: "the older-entries button",
        note: "Older entries are not loaded yet, so the page numbers alone cannot reach them.",
    },
} as const satisfies TFeatureNoteGroup;

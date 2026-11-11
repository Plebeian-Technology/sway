import { TFeatureNoteGroup } from "app/frontend/components/admin/creator/feature-notes/types";

export const SUMMARY_TAB_NOTES = {
    "summary.publicSummary": {
        feature: "the public summary box",
        note: "A model summary is not publishable as it stands, so this is where a person settles the wording.",
    },
    "summary.sources": {
        feature: "what the model read",
        note: "A summary is only as good as what reached the model, so each input opens the exact text it was sent.",
    },
    "summary.runStatusBadge": {
        feature: "the run status badge",
        note: "One word for where the last summary run got to, including one that stopped with nothing left on it.",
    },
    "summary.saveSummary": {
        feature: "the Save summary button",
        note: "This is the only control here that publishes the text; the ones beside it replace what is in the box.",
    },
    "summary.modelPicker": {
        feature: "choosing the model for this run",
        note: "Spend a stronger model on one hard bill without changing the default for every other summary.",
    },
    "summary.regenerate": {
        feature: "regenerating the summary",
        note: "It throws away the current draft and asks the model again, so it sits under the box it replaces.",
    },
    "summary.pasteSummaryJson": {
        feature: "pasting a summary in",
        note: "Hand the prompt to any other assistant and paste the answer back, with nothing spent on a model.",
    },
    "summary.staleHeader": {
        feature: "the out-of-date warning",
        note: "The bill changed after this summary was written, so what readers see may no longer describe it.",
    },
    "summary.preparePrompt": {
        feature: "preparing the prompt",
        note: "Builds the exact prompt so you can run it in another assistant for free.",
    },
    "summary.generateSummary": {
        feature: "generating the summary",
        note: "Runs only the summary step against data already downloaded, so it is fast and fetches nothing again.",
    },
    "summary.supplementalTestimony": {
        feature: "supplemental testimony",
        note: "Evidence pasted here is read when positions are drafted; the bill summary never sees testimony.",
    },
    "summary.saveTestimony": {
        feature: "saving the testimony",
        note: "Saving replaces what was there, which withdraws the evidence under any position drafted from it.",
    },
    "summary.clearTestimony": {
        feature: "clearing the saved testimony",
        note: "Clearing is its own button so an empty box can never wipe the saved testimony by accident.",
    },
    "summary.draftOrgPositions": {
        feature: "the draft positions",
        note: "What the model read out of the testimony, none of it published until you approve it.",
    },
    "summary.testimonyCoverage": {
        feature: "the testimony coverage notice",
        note: "A prompt holds only so much testimony, so this says how much of it the model actually read.",
    },
    "summary.coverageAcknowledgement": {
        feature: "acknowledging the missing testimony",
        note: "It puts a name against a position approved on evidence the model only partly read.",
    },
    "summary.stanceBadge": {
        feature: "the stance on this card",
        note: "This is the organization's stance as the model read it from their testimony.",
    },
    "summary.approvePosition": {
        feature: "approving this position",
        note: "This is the one action that publishes a named organization's stance, so anything unsettled turns it off.",
    },
    "summary.editPosition": {
        feature: "editing this position",
        note: "Edits stay in this browser until you approve, and rejecting throws them away with the draft.",
    },
    "summary.campaignStamp": {
        feature: "the campaign stamp",
        note: "This is a group of people who sent the same letter, not an organization.",
    },
    "summary.campaignEvidence": {
        feature: "the sender and letter counts",
        note: "Senders and letters differ because a person whose letter was filed twice is only counted once.",
    },
    "summary.campaignLetters": {
        feature: "reading the campaign letters",
        note: "The letters load only when you open them, because carrying every one on each refresh is too much.",
    },
    "summary.campaignOrgLink": {
        feature: "naming the organization behind a campaign",
        note: "Naming who is behind a campaign is a second, harder decision, kept apart from approving it.",
    },
    "summary.claimedAffiliationEvidence": {
        feature: "the evidence behind a claimed organization",
        note: "The sender's own words are here so you can judge the guess yourself rather than trust a score.",
    },
    "summary.categories": {
        feature: "the bill's categories",
        note: "Categories are how readers find this bill when they browse by subject.",
    },
    "summary.pasteDialog": {
        feature: "pasting a summary from another assistant",
        note: "Pasted text is checked against the expected shape before it goes anywhere near the bill.",
    },
} as const satisfies TFeatureNoteGroup;

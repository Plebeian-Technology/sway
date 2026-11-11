import { TFeatureNoteGroup } from "app/frontend/components/admin/creator/feature-notes/types";

export const SHELL_AND_CREATOR_TAB_NOTES = {
    "creator.billPicker": {
        feature: "the bill picker",
        note: "A jurisdiction can hold hundreds of bills, so you search for one here instead of scrolling a list.",
    },
    "creator.pickerSort": {
        feature: "the bill picker sort",
        note: "Recent intro/vote sorts by the latest stored introduction or either chamber's vote date.",
    },
    "creator.localeSelector": {
        feature: "the jurisdiction picker",
        note: "Lets you work on bills outside your own jurisdiction, and remembers the choice for later pages.",
    },
    "creator.cancelRun": {
        feature: "clearing a pipeline run",
        note: "Only one run is allowed at a time, so clearing a stuck one is what frees the Run button.",
    },
    "creator.detailsAccordion": {
        feature: "the Details and Summary section",
        note: "This is the only section that works before the bill exists, so the other three wait until you save it.",
    },
    "creator.legislatorVotesAccordion": {
        feature: "the Legislator Votes section",
        note: "Votes are stored apart from the bill itself, so this section has its own Save button.",
    },
    "creator.argumentsAccordion": {
        feature: "the Supporting and Opposing Arguments section",
        note: "Organizations are shared across the whole jurisdiction, so they save separately from the bill.",
    },
    "creator.llmSummaryAccordion": {
        feature: "the LLM Summary section",
        note: "This keeps the summary in the bill's checklist even though the editing itself happens on another tab.",
    },
    "creator.chamber": {
        feature: "the chamber field",
        note: "Where a jurisdiction has just one chamber there is nothing to choose, so the field greys itself out.",
    },
    "creator.summaryField": {
        feature: "the Sway bill summary",
        note: "Readers see this text on the public bill page, and the panel beside it shows how it will look.",
    },
    "creator.audioSummary": {
        feature: "the audio summary",
        note: "One field takes either an uploaded file or a link, so the audio can live somewhere else.",
    },
    "creator.legislatorVoteLedger": {
        feature: "the vote ledger",
        note: "A legislator holds one position on a bill, so picking one of these clears the other two.",
    },
    "creator.orgCombobox": {
        feature: "the organization list",
        note: "Organizations are shared by every bill in this jurisdiction, and a new one can be made right here.",
    },
    "creator.orgRename": {
        feature: "renaming an organization",
        note: "The new name shows up on every bill in this jurisdiction, not only on this one.",
    },
    "creator.orgRemove": {
        feature: "removing an organization",
        note: "Hides this stance from the public bill page while keeping its history and the organization itself.",
    },
    "creator.orgPositionSwitch": {
        feature: "the For and Against switch",
        note: "Readers only see this stance on the bill page once you save, so nothing changes until then.",
    },
    "creator.orgPositionSummary": {
        feature: "the position summary",
        note: "This is the argument readers get for the stance, so it cannot be left blank.",
    },
} as const satisfies TFeatureNoteGroup;

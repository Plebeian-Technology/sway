import { PIPELINE_TAB_NOTES } from "app/frontend/components/admin/creator/feature-notes/pipelineTab";
import { SCHEDULE_TAB_NOTES } from "app/frontend/components/admin/creator/feature-notes/scheduleTab";
import { SHELL_AND_CREATOR_TAB_NOTES } from "app/frontend/components/admin/creator/feature-notes/shellAndCreatorTab";
import { SUMMARY_TAB_NOTES } from "app/frontend/components/admin/creator/feature-notes/summaryTab";

// @lat: [[bill-creator-shell#The Bill Creator shell#Why a feature note opens in a popover]]
export const FEATURE_NOTES = {
    ...SHELL_AND_CREATOR_TAB_NOTES,
    ...SCHEDULE_TAB_NOTES,
    ...PIPELINE_TAB_NOTES,
    ...SUMMARY_TAB_NOTES,
} as const;

export type TFeatureNoteKey = keyof typeof FEATURE_NOTES;

import { BILL_INPUTS } from "app/frontend/components/bill/creator/inputs";
import { AUDIO_FIELD_LABELS } from "app/frontend/components/admin/creator/audioFieldLabels";
import { titleize } from "app/frontend/sway_utils";

// @lat: [[bill-creator-field-display-labels#Why BILL_FIELD_LABELS is built once from BILL_INPUTS]]
const BILL_FIELD_LABELS: ReadonlyMap<string, string> = new Map([
    ...Object.values(BILL_INPUTS).map((field) => [String(field.name), field.label.trim()] as const),
    ...Object.entries(AUDIO_FIELD_LABELS),
]);

// @lat: [[bill-creator-field-display-labels#Why fieldDisplayName falls back to titleize, and why BillCreatorOrganizations never reaches it]]
export const fieldDisplayName = (name: string): string => BILL_FIELD_LABELS.get(name) || titleize(name, "_");

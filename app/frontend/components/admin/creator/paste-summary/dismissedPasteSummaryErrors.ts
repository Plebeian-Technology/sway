import type { IValidationError } from "app/frontend/types/bill_creator";

// @lat: [[dismissed-paste-summary-errors-tracking#Why identity, not content]]
const dismissed = new WeakSet<IValidationError[]>();

// @lat: [[dismissed-paste-summary-errors-tracking#Why module scope, and why a WeakSet]]
export const dismissPasteSummaryErrors = (errors: IValidationError[]): void => {
    if (errors.length === 0) return;

    dismissed.add(errors);
};

export const arePasteSummaryErrorsDismissed = (errors: IValidationError[]): boolean => dismissed.has(errors);

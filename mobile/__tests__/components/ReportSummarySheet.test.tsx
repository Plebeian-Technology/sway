// @lat: [[bill-summary-reporting#Reader reporting of inaccurate summaries#Reporting from the mobile Bill tab]]
jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

const mockPost = jest.fn();
jest.mock("../../src/api/client", () => ({
    apiClient: { post: (...args: unknown[]) => mockPost(...args) },
}));

import React from "react";
import { StyleSheet } from "react-native";
import { act, fireEvent, render, screen, waitFor } from "@testing-library/react-native";

import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { ApiRequestError, NetworkError, RateLimitedError } from "../../src/api/errors";
import { ReportSummarySheet, type ReportSummarySheetProps } from "../../src/components/ReportSummarySheet";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

const VALID_DETAILS = "The summary says the fee is $50 but the bill sets it at $5.";

const renderSheet = (overrides: Partial<ReportSummarySheetProps> = {}) => {
    const props: ReportSummarySheetProps = { visible: true, billId: 42, onClose: jest.fn(), ...overrides };
    const ui = (p: ReportSummarySheetProps) => (
        <ThemeProvider initialMode="light">
            <ReportSummarySheet {...p} />
        </ThemeProvider>
    );
    const view = render(ui(props));
    return {
        ...view,
        props,
        rerenderWith: (next: Partial<ReportSummarySheetProps>) => view.rerender(ui({ ...props, ...next })),
    };
};

const chooseReason = (reason: string) => fireEvent.press(screen.getByTestId(`report-summary-reason-${reason}`));
const typeDetails = (text: string) => fireEvent.changeText(screen.getByTestId("report-summary-details"), text);
const submitButton = () => screen.getByTestId("report-summary-submit");
const isSubmitDisabled = () => submitButton().props.accessibilityState.disabled === true;
const fillValidForm = () => {
    chooseReason("misleading_tone");
    typeDetails(VALID_DETAILS);
};
const pressSubmit = async () => {
    await act(async () => {
        fireEvent.press(submitButton());
    });
};

describe("ReportSummarySheet", () => {
    beforeEach(() => {
        mockPost.mockReset();
        mockPost.mockResolvedValue({ id: 1 });
    });

    test("renders nothing while not visible", () => {
        const { toJSON } = renderSheet({ visible: false });
        expect(toJSON()).toBeNull();
    });

    describe("the form", () => {
        test("shows the title and description from the shared copy", () => {
            renderSheet();
            expect(screen.getByText(PARITY_COPY.bill.reportDialogTitle)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.bill.reportDialogDescription)).toBeTruthy();
        });

        test("offers the four reasons as radios, none chosen at first", () => {
            renderSheet();
            const reasons = ["factual_inaccuracy", "misleading_tone", "missing_amendment", "other"];

            reasons.forEach((reason) => {
                const radio = screen.getByTestId(`report-summary-reason-${reason}`);
                expect(radio.props.accessibilityRole).toBe("radio");
                expect(radio.props.accessibilityState).toEqual(expect.objectContaining({ checked: false }));
                expect(StyleSheet.flatten(radio.props.style).minHeight).toBeGreaterThanOrEqual(44);
            });
            expect(screen.getByText("Factual inaccuracy")).toBeTruthy();
            expect(screen.getByText("Misleading tone or bias")).toBeTruthy();
            expect(screen.getByText("Missing amendment or outdated text")).toBeTruthy();
            expect(screen.getByText("Other issue")).toBeTruthy();
        });

        test("choosing a reason checks that radio and unchecks the others", () => {
            renderSheet();
            chooseReason("missing_amendment");
            expect(screen.getByTestId("report-summary-reason-missing_amendment").props.accessibilityState).toEqual(
                expect.objectContaining({ checked: true }),
            );
            chooseReason("other");
            expect(screen.getByTestId("report-summary-reason-missing_amendment").props.accessibilityState).toEqual(
                expect.objectContaining({ checked: false }),
            );
            expect(screen.getByTestId("report-summary-reason-other").props.accessibilityState).toEqual(
                expect.objectContaining({ checked: true }),
            );
        });

        test("caps the details field at 2000 characters and counts them", () => {
            renderSheet();
            expect(screen.getByTestId("report-summary-details").props.maxLength).toBe(2000);
            typeDetails("abcde");
            expect(screen.getByTestId("report-summary-details-count")).toHaveTextContent("5/2000");
        });
    });

    describe("the submit button", () => {
        test("is disabled until a reason is chosen and the details hold 10 trimmed characters", () => {
            renderSheet();
            expect(isSubmitDisabled()).toBe(true);

            typeDetails(VALID_DETAILS);
            expect(isSubmitDisabled()).toBe(true);

            chooseReason("factual_inaccuracy");
            expect(isSubmitDisabled()).toBe(false);
        });

        test("stays disabled when the details are shorter than 10 characters once trimmed", () => {
            renderSheet();
            chooseReason("other");
            typeDetails("   too short   ");
            expect(isSubmitDisabled()).toBe(true);

            typeDetails("0123456789");
            expect(isSubmitDisabled()).toBe(false);
        });

        test("does not send a request when pressed while disabled", async () => {
            renderSheet();
            await pressSubmit();
            expect(mockPost).not.toHaveBeenCalled();
        });
    });

    describe("submitting", () => {
        test("POSTs the nested params and shows the thank-you copy on success", async () => {
            renderSheet();
            fillValidForm();
            await pressSubmit();

            expect(mockPost).toHaveBeenCalledWith("/bills/42/summary_reports", {
                bill_summary_report: { reason: "misleading_tone", details: VALID_DETAILS },
            });
            expect(screen.getByTestId("report-summary-confirmation")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.bill.reportSubmittedTitle)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.bill.reportSubmittedMessage)).toBeTruthy();
            expect(screen.queryByTestId("report-summary-submit")).toBeNull();
        });

        test("shows a busy submit button and ignores a second press while the request is in flight", async () => {
            let resolvePost: (value: unknown) => void = () => {};
            mockPost.mockReturnValueOnce(new Promise((resolve) => (resolvePost = resolve)));
            renderSheet();
            fillValidForm();

            await pressSubmit();
            expect(screen.getByText("Submitting…")).toBeTruthy();
            expect(isSubmitDisabled()).toBe(true);
            await pressSubmit();
            expect(mockPost).toHaveBeenCalledTimes(1);

            await act(async () => {
                resolvePost({ id: 1 });
            });
            expect(screen.getByTestId("report-summary-confirmation")).toBeTruthy();
        });

        test("Done on the thank-you view closes the sheet", async () => {
            const { props } = renderSheet();
            fillValidForm();
            await pressSubmit();

            fireEvent.press(screen.getByTestId("report-summary-done"));
            expect(props.onClose).toHaveBeenCalledTimes(1);
        });

        test("a 422 shows the already-submitted copy", async () => {
            mockPost.mockRejectedValueOnce(
                new ApiRequestError(
                    "validation_failed",
                    "A report for this bill summary was already submitted recently.",
                    undefined,
                    422,
                ),
            );
            renderSheet();
            fillValidForm();
            await pressSubmit();

            expect(screen.getByTestId("report-summary-confirmation")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.bill.alreadyReportedNotice)).toBeTruthy();
            expect(screen.queryByText(PARITY_COPY.bill.reportSubmittedMessage)).toBeNull();
        });

        test.each([
            [
                "a 429 rate_limited response",
                new RateLimitedError("rate_limited", "Too many attempts. Please try again shortly.", undefined, 429),
                PARITY_COPY.bill.reportRateLimited,
            ],
            [
                "a network error",
                new NetworkError("network_error", "Network request failed"),
                PARITY_COPY.bill.reportOffline,
            ],
            [
                "a server error",
                new ApiRequestError("http_500", "HTTP 500", undefined, 500),
                PARITY_COPY.bill.reportFailed,
            ],
        ])("%s keeps the form filled and shows its message", async (_label, error, message) => {
            mockPost.mockRejectedValueOnce(error);
            renderSheet();
            fillValidForm();
            await pressSubmit();

            expect(screen.getByTestId("report-summary-error")).toHaveTextContent(message);
            expect(screen.queryByTestId("report-summary-confirmation")).toBeNull();
            expect(screen.getByTestId("report-summary-details").props.value).toBe(VALID_DETAILS);
            expect(screen.getByTestId("report-summary-reason-misleading_tone").props.accessibilityState).toEqual(
                expect.objectContaining({ checked: true }),
            );
            expect(isSubmitDisabled()).toBe(false);
        });

        test("a retry after a failure sends again and clears the message on success", async () => {
            mockPost.mockRejectedValueOnce(new NetworkError("network_error", "Network request failed"));
            renderSheet();
            fillValidForm();
            await pressSubmit();
            expect(screen.getByTestId("report-summary-error")).toBeTruthy();

            await pressSubmit();
            expect(mockPost).toHaveBeenCalledTimes(2);
            expect(screen.queryByTestId("report-summary-error")).toBeNull();
            expect(screen.getByTestId("report-summary-confirmation")).toBeTruthy();
        });
    });

    describe("closing", () => {
        test("Cancel calls onClose", () => {
            const { props } = renderSheet();
            fireEvent.press(screen.getByTestId("report-summary-cancel"));
            expect(props.onClose).toHaveBeenCalledTimes(1);
        });

        test("Cancel is ignored while a request is in flight", async () => {
            mockPost.mockReturnValueOnce(new Promise(() => {}));
            const { props } = renderSheet();
            fillValidForm();
            await pressSubmit();

            fireEvent.press(screen.getByTestId("report-summary-cancel"));
            expect(props.onClose).not.toHaveBeenCalled();
        });

        test("reopening after a close starts from an empty form, not the old thank-you", async () => {
            const { rerenderWith } = renderSheet();
            fillValidForm();
            await pressSubmit();
            expect(screen.getByTestId("report-summary-confirmation")).toBeTruthy();

            rerenderWith({ visible: false });
            expect(screen.queryByTestId("report-summary-confirmation")).toBeNull();
            rerenderWith({ visible: true });

            await waitFor(() => expect(screen.getByTestId("report-summary-details")).toBeTruthy());
            expect(screen.getByTestId("report-summary-details").props.value).toBe("");
            expect(isSubmitDisabled()).toBe(true);
            expect(screen.queryByTestId("report-summary-confirmation")).toBeNull();
        });
    });
});

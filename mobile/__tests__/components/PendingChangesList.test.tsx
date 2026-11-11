// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]
import React from "react";
import { Alert } from "react-native";
import { render, screen, fireEvent, waitFor } from "@testing-library/react-native";

import { PendingChangesList } from "../../src/components/PendingChangesList";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { usePendingChanges } from "../../src/hooks/usePendingChanges";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

jest.mock("../../src/hooks/usePendingChanges", () => ({
    usePendingChanges: jest.fn(),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

const mockUsePendingChanges = usePendingChanges as jest.Mock;

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const sampleChanges = [
    {
        id: 101,
        organization_bill_position_id: 10,
        previous_support: "FOR",
        new_support: "AGAINST",
        previous_summary: "Old summary",
        new_summary: "Updated summary",
        created_at: "2026-09-29T00:00:00Z",
        approved_by_id: null,
    },
];

describe("PendingChangesList", () => {
    jest.setTimeout(20000);
    let mockApprove: jest.Mock;
    let mockReject: jest.Mock;

    beforeEach(() => {
        mockApprove = jest.fn().mockResolvedValue(undefined);
        mockReject = jest.fn().mockResolvedValue(undefined);
        mockUsePendingChanges.mockReturnValue({
            changes: sampleChanges,
            loading: false,
            error: null,
            approve: mockApprove,
            reject: mockReject,
            busy: false,
        });
    });

    test("when reject succeeds and onRefresh throws, does not display Reject failed alert", async () => {
        const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
        const onRefresh = jest.fn().mockRejectedValue(new Error("network error during refresh"));

        wrap(
            <PendingChangesList
                orgId={1}
                membershipId={5}
                isAdmin={true}
                changes={sampleChanges}
                onRefresh={onRefresh}
            />,
        );

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockReject).toHaveBeenCalledWith(101));
        await waitFor(() => expect(onRefresh).toHaveBeenCalledTimes(1));

        expect(alertSpy).not.toHaveBeenCalled();

        alertSpy.mockRestore();
    });

    test("when reject throws, displays Reject failed alert and does not call onRefresh", async () => {
        const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
        mockReject.mockRejectedValueOnce(new Error("cannot reject locked change"));
        const onRefresh = jest.fn().mockResolvedValue(undefined);

        wrap(
            <PendingChangesList
                orgId={1}
                membershipId={5}
                isAdmin={true}
                changes={sampleChanges}
                onRefresh={onRefresh}
            />,
        );

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockReject).toHaveBeenCalledWith(101));
        await waitFor(() => expect(alertSpy).toHaveBeenCalledWith("Reject failed", "cannot reject locked change"));
        expect(onRefresh).not.toHaveBeenCalled();

        alertSpy.mockRestore();
    });

    test("when reject and onRefresh succeed, both are called without alert", async () => {
        const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
        const onRefresh = jest.fn().mockResolvedValue(undefined);

        wrap(
            <PendingChangesList
                orgId={1}
                membershipId={5}
                isAdmin={true}
                changes={sampleChanges}
                onRefresh={onRefresh}
            />,
        );

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockReject).toHaveBeenCalledWith(101));
        await waitFor(() => expect(onRefresh).toHaveBeenCalledTimes(1));
        expect(alertSpy).not.toHaveBeenCalled();

        alertSpy.mockRestore();
    });

    test("when reject succeeds and onRefresh rejects with a custom non-Error object or null, does not throw and does not alert", async () => {
        const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});

        const customObjRefresh = jest.fn().mockRejectedValue({ code: 500, detail: "custom error object" });
        const { unmount } = wrap(
            <PendingChangesList
                orgId={1}
                membershipId={5}
                isAdmin={true}
                changes={sampleChanges}
                onRefresh={customObjRefresh}
            />,
        );

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockReject).toHaveBeenCalledWith(101));
        await waitFor(() => expect(customObjRefresh).toHaveBeenCalledTimes(1));
        expect(alertSpy).not.toHaveBeenCalled();

        unmount();

        const nullRefresh = jest.fn().mockRejectedValue(null);
        wrap(
            <PendingChangesList
                orgId={1}
                membershipId={5}
                isAdmin={true}
                changes={sampleChanges}
                onRefresh={nullRefresh}
            />,
        );

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockReject).toHaveBeenCalledTimes(2));
        await waitFor(() => expect(nullRefresh).toHaveBeenCalledTimes(1));
        expect(alertSpy).not.toHaveBeenCalled();

        alertSpy.mockRestore();
    });

    test("when reject throws a non-Error object or null, displays fallback 'Could not reject change.' alert", async () => {
        const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
        mockReject.mockRejectedValueOnce({ status: 500, error: "Internal DB error" });
        const onRefresh = jest.fn().mockResolvedValue(undefined);

        const { unmount } = wrap(
            <PendingChangesList
                orgId={1}
                membershipId={5}
                isAdmin={true}
                changes={sampleChanges}
                onRefresh={onRefresh}
            />,
        );

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockReject).toHaveBeenCalledWith(101));
        await waitFor(() => expect(alertSpy).toHaveBeenCalledWith("Reject failed", "Could not reject change."));
        expect(onRefresh).not.toHaveBeenCalled();

        unmount();

        mockReject.mockRejectedValueOnce(null);
        wrap(
            <PendingChangesList
                orgId={1}
                membershipId={5}
                isAdmin={true}
                changes={sampleChanges}
                onRefresh={onRefresh}
            />,
        );

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockReject).toHaveBeenCalledTimes(2));
        await waitFor(() => expect(alertSpy).toHaveBeenLastCalledWith("Reject failed", "Could not reject change."));
        expect(onRefresh).not.toHaveBeenCalled();

        alertSpy.mockRestore();
    });
});

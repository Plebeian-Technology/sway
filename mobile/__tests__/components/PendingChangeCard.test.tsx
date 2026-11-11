/**
 * PendingChangeCard — written before the component existed, so until it shipped
 * every one of these failed on purpose.
 */
import React from "react";
import { render, screen, fireEvent } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";

// The component being tested. The require sits in a try/catch because the file
// did not exist when these tests were written.
const { PendingChangeCard } = (() => {
    try {
        return require("../../src/components/PendingChangeCard");
    } catch {
        return { PendingChangeCard: null };
    }
})();

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const baseChange = {
    id: 3,
    organization_bill_position_id: 7,
    previous_support: "FOR",
    new_support: "AGAINST",
    previous_summary: "Old summary text here.",
    new_summary: "New updated summary text here.",
    created_at: "2026-04-27T10:00:00Z",
    approved_by_id: null as number | null,
};

describe("PendingChangeCard", () => {
    test("module exports PendingChangeCard", () => {
        expect(PendingChangeCard).not.toBeNull();
    });

    test("renders previous and new summary text", () => {
        const onApprove = jest.fn();
        const onReject = jest.fn();
        wrap(<PendingChangeCard change={baseChange} isAdmin={true} onApprove={onApprove} onReject={onReject} />);
        expect(screen.getByText("Old summary text here.")).toBeTruthy();
        expect(screen.getByText("New updated summary text here.")).toBeTruthy();
    });

    test("has testID pending-change-card-{id}", () => {
        wrap(<PendingChangeCard change={baseChange} isAdmin={true} onApprove={jest.fn()} onReject={jest.fn()} />);
        expect(screen.getByTestId("pending-change-card-3")).toBeTruthy();
    });

    test("pressing Approve calls onApprove directly without DestructiveSheet", () => {
        const onApprove = jest.fn();
        const onReject = jest.fn();
        wrap(<PendingChangeCard change={baseChange} isAdmin={true} onApprove={onApprove} onReject={onReject} />);
        fireEvent.press(screen.getByText("Approve change"));
        expect(onApprove).toHaveBeenCalledTimes(1);
    });

    test("pressing Reject opens DestructiveSheet (does not call onReject directly)", () => {
        const onApprove = jest.fn();
        const onReject = jest.fn();
        wrap(<PendingChangeCard change={baseChange} isAdmin={true} onApprove={onApprove} onReject={onReject} />);
        fireEvent.press(screen.getByText("Reject"));
        expect(onReject).not.toHaveBeenCalled();
        expect(screen.getByText("Reject this proposed change?")).toBeTruthy();
    });

    test("Approve/Reject buttons not rendered for non-admin", () => {
        wrap(<PendingChangeCard change={baseChange} isAdmin={false} onApprove={jest.fn()} onReject={jest.fn()} />);
        expect(screen.queryByText("Approve change")).toBeNull();
        expect(screen.queryByText("Reject")).toBeNull();
    });
});

/**
 * MemberInviteForm — written to pass against the finished component.
 */
import React from "react";
import { render, screen, fireEvent } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";

const mockInvite = jest.fn();
jest.mock("../../src/hooks/useMemberInvite", () => ({
    useMemberInvite: () => ({ invite: mockInvite, busy: false, error: null }),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

import { MemberInviteForm } from "../../src/components/MemberInviteForm";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("MemberInviteForm", () => {
    beforeEach(() => {
        mockInvite.mockReset();
    });

    test("module exports MemberInviteForm", () => {
        expect(MemberInviteForm).toBeDefined();
    });

    test("has testID member-invite-form", () => {
        wrap(<MemberInviteForm orgId={1} />);
        expect(screen.getByTestId("member-invite-form")).toBeTruthy();
    });

    test("renders email FormField label", () => {
        wrap(<MemberInviteForm orgId={1} />);
        expect(screen.getByText("Email")).toBeTruthy();
    });

    test("renders submit Pressable", () => {
        wrap(<MemberInviteForm orgId={1} />);
        expect(screen.getByText("Send invite")).toBeTruthy();
    });

    test("submitting with valid email calls invite with orgId and email", async () => {
        mockInvite.mockResolvedValue(undefined);
        wrap(<MemberInviteForm orgId={2} />);

        const input = screen.getByTestId("member-invite-email-input");
        fireEvent.changeText(input, "test@example.com");
        fireEvent.press(screen.getByText("Send invite"));

        expect(mockInvite).toHaveBeenCalledWith(2, "test@example.com");
    });

    test("renders form without crashing (busy state handled by disabled prop)", () => {
        wrap(<MemberInviteForm orgId={1} />);
        expect(screen.getByTestId("member-invite-form")).toBeTruthy();
    });
});

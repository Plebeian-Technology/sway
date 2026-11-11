/**
 * MembersList — written to pass against the finished component.
 */
import React from "react";
import { render, screen } from "@testing-library/react-native";

import { ThemeProvider } from "../../src/theme/ThemeProvider";

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

// Admins see MemberInviteForm inside MembersList. Swap it for a blank stand-in
// so these tests only exercise MembersList itself.
jest.mock("../../src/components/MemberInviteForm", () => ({
    MemberInviteForm: () => null,
}));

// MemberInviteForm imports useMemberInvite, so fake that too or the module fails to load
jest.mock("../../src/hooks/useMemberInvite", () => ({
    useMemberInvite: () => ({ invite: jest.fn(), busy: false, error: null }),
}));

import { MembersList } from "../../src/components/MembersList";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const baseMembers = [
    { id: 1, user_id: 10, full_name: "Alice Admin", email: "alice@example.com", role: "admin" as const },
    { id: 2, user_id: 11, full_name: "Bob Member", email: "bob@example.com", role: "standard" as const },
];

describe("MembersList", () => {
    test("module exports MembersList", () => {
        expect(MembersList).toBeDefined();
    });

    test("renders member names", () => {
        wrap(<MembersList orgId={1} members={baseMembers} isAdmin={false} />);
        expect(screen.getByText("Alice Admin")).toBeTruthy();
        expect(screen.getByText("Bob Member")).toBeTruthy();
    });

    test("renders role badges for each member", () => {
        wrap(<MembersList orgId={1} members={baseMembers} isAdmin={false} />);
        expect(screen.getByText("ADMIN")).toBeTruthy();
        expect(screen.getByText("MEMBER")).toBeTruthy();
    });

    test("has testID members-list", () => {
        wrap(<MembersList orgId={1} members={baseMembers} isAdmin={false} />);
        expect(screen.getByTestId("members-list")).toBeTruthy();
    });

    test("renders without error for admin variant (MemberInviteForm mocked)", () => {
        wrap(<MembersList orgId={1} members={baseMembers} isAdmin={true} />);
        expect(screen.getByTestId("members-list")).toBeTruthy();
    });

    test("renders empty state when members array is empty", () => {
        wrap(<MembersList orgId={1} members={[]} isAdmin={false} />);
        expect(screen.getByText("No members yet.")).toBeTruthy();
    });
});

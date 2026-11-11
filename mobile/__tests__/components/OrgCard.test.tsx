// @lat: [[mobile-jest-first-pass-test-notes#OrgCard.test.tsx / OrgDetailScreen.test.tsx]]

// ── Fake modules. These have to be declared before the imports ───────────────

jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

// Fake API client. useOrganizationFollow calls it only on a tap, never on mount.
jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: jest.fn(),
        post: jest.fn(),
        patch: jest.fn(),
        delete: jest.fn(),
    },
}));

import React from "react";
import { render, screen } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { OrgCard } from "../../src/components/OrgCard";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const BASE_ORG = {
    id: 7,
    name: "Civic Alliance",
    sway_locale_slug: "baltimore-maryland-united_states",
    follower_count: 12,
};

describe("OrgCard (Phase 35 D-09 Card-primitive refactor + Phase 61 follow restore)", () => {
    test("renders org name", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={() => {}} />);
        expect(screen.getByText("Civic Alliance")).toBeTruthy();
    });

    test("renders locale name (sway_locale_slug) when available", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={() => {}} />);
        expect(screen.getByText("baltimore-maryland-united_states")).toBeTruthy();
    });

    test("renders follower count ('N followers') — REQ-9", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={() => {}} />);
        expect(screen.getByText("12 followers")).toBeTruthy();
    });

    test("shows 'Follow' CTA for signed-in not-following user (REQ-8)", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={() => {}} isSignedIn={true} initialFollowId={null} />);
        expect(screen.getByTestId(`org-card-follow-btn-${BASE_ORG.id}`)).toBeTruthy();
        expect(screen.getByText("Follow")).toBeTruthy();
    });

    test("member (isMember=true) shows Member label + Preferences, NO follow/unfollow (D-04)", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={() => {}} isSignedIn={true} isMember={true} initialFollowId={null} />);
        expect(screen.getByText("Member")).toBeTruthy();
        expect(screen.queryByText("Follow")).toBeNull();
        expect(screen.queryByText("Following")).toBeNull();
    });

    test("snapshot matches (signed-out view)", () => {
        const { toJSON } = wrap(<OrgCard org={BASE_ORG} onPress={() => {}} isSignedIn={false} />);
        expect(toJSON()).toMatchSnapshot();
    });
});

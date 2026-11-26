// @lat: [[mobile-jest-first-pass-test-notes#OrgCard.test.tsx / OrgDetailScreen.test.tsx]]

// ── Hoisted mocks (must precede import) ──────────────────────────────────────

jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: jest.fn(),
        post: jest.fn(),
        patch: jest.fn(),
        delete: jest.fn(),
    },
}));

jest.mock("../../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("react-native-safe-area-context", () => ({
    useSafeAreaInsets: () => ({ top: 0, bottom: 0, left: 0, right: 0 }),
    SafeAreaProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

import React from "react";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { fireEvent, render, screen, waitFor } from "@testing-library/react-native";
import { Linking } from "react-native";
import OrgDetailScreen from "../../src/screens/OrgDetailScreen";
import { apiClient } from "../../src/api/client";

function makeRoute(id = 42) {
    return { params: { id } };
}

function makeNav() {
    return { navigate: jest.fn(), getParent: jest.fn(() => ({ navigate: jest.fn() })) };
}

const ORG_PAYLOAD = {
    organization: {
        id: 42,
        name: "Civic Alliance",
        sway_locale_slug: "baltimore-maryland-united_states",
    },
    organization_bill_positions: [{ id: 1, bill_id: 10, support: "Supports", summary: "Good policy" }],
    // A signed-in user gets current_user_follow_id; if it is missing, the user is signed out
    current_user_follow_id: 99,
    is_member_of_org_ids: [],
};

const ORG_PAYLOAD_SIGNED_OUT = {
    organization: {
        id: 42,
        name: "Civic Alliance",
        sway_locale_slug: "baltimore-maryland-united_states",
    },
    organization_bill_positions: [],
    // Neither current_user_follow_id nor is_member_of_org_ids, so this user is signed out
};

describe("OrgDetailScreen (Phase 35 parity rebuild + Phase 61 follow restore)", () => {
    const mockGet = apiClient.get as jest.Mock;

    beforeEach(() => {
        jest.clearAllMocks();
        mockGet.mockResolvedValue(ORG_PAYLOAD);
    });

    test("renders testID='org-detail-header' containing the org name", async () => {
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        await waitFor(() => {
            expect(screen.getByTestId("org-detail-header")).toBeTruthy();
        });
        expect(screen.getByText("Civic Alliance")).toBeTruthy();
    });

    test("renders testID='org-detail-positions' (read-only positions list region)", async () => {
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        await waitFor(() => {
            expect(screen.getByTestId("org-detail-positions")).toBeTruthy();
        });
    });

    test("renders 'Following' control for signed-in following user (Phase 61 REQ-8)", async () => {
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        await waitFor(() => {
            expect(screen.getByTestId("org-detail-header")).toBeTruthy();
        });
        expect(screen.getByTestId("org-detail-following-btn")).toBeTruthy();
    });

    test("renders no follower count", async () => {
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        await waitFor(() => {
            expect(screen.getByTestId("org-detail-header")).toBeTruthy();
        });
        expect(screen.queryByTestId("org-detail-follower-count")).toBeNull();
        expect(screen.queryByText(/follower/)).toBeNull();
    });

    // Signed out: no follow section renders here (deliberately unlike OrgCard, which shows a Follow
    // button to signed-out users and opens the sign-in sheet).
    test("hides follow control for signed-out user on detail screen", async () => {
        mockGet.mockResolvedValue(ORG_PAYLOAD_SIGNED_OUT);
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        await waitFor(() => {
            expect(screen.getByTestId("org-detail-header")).toBeTruthy();
        });
        expect(screen.queryByTestId("org-detail-follow-btn")).toBeNull();
        expect(screen.queryByTestId("org-detail-following-btn")).toBeNull();
    });

    test("renders error state without unhandled rejection when fetch fails", async () => {
        mockGet.mockRejectedValueOnce(new Error("network failure"));
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        await waitFor(() => {
            expect(screen.getByTestId("org-detail-error")).toBeTruthy();
        });
    });
});

describe("OrgDetailScreen affiliation labels", () => {
    const mockGet = apiClient.get as jest.Mock;
    const payload = (managed_on_sway: boolean) => ({
        ...ORG_PAYLOAD,
        organization: { ...ORG_PAYLOAD.organization, managed_on_sway },
        organization_bill_positions: [
            { id: 1, bill_id: 10, support: "FOR", summary: "Good policy", source_kind: "organization" },
            { id: 2, bill_id: 11, support: "AGAINST", summary: "Bad policy", source_kind: null },
        ],
    });

    test("says an unmanaged organization is not affiliated with Sway", async () => {
        mockGet.mockResolvedValue(payload(false));
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        expect(await screen.findByText(PARITY_COPY.orgs.notAffiliated("Civic Alliance"))).toBeTruthy();
        expect(screen.queryByText(PARITY_COPY.orgs.managedOnSway("Civic Alliance"))).toBeNull();
    });

    test("shows the managed label instead for a managed organization", async () => {
        mockGet.mockResolvedValue(payload(true));
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        expect(await screen.findByText(PARITY_COPY.orgs.managedOnSway("Civic Alliance"))).toBeTruthy();
        expect(screen.queryByText(PARITY_COPY.orgs.notAffiliated("Civic Alliance"))).toBeNull();
    });

    test("tags each position by who wrote it", async () => {
        mockGet.mockResolvedValue(payload(true));
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);
        const tags = await screen.findAllByTestId("org-position-source-tag");
        expect(tags.map((tag) => tag.props.children)).toEqual(["Posted by Civic Alliance", "Compiled by Sway"]);
    });
});

describe("OrgDetailScreen source line", () => {
    const mockGet = apiClient.get as jest.Mock;

    test("a news position links to its article", async () => {
        const openURL = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
        mockGet.mockResolvedValue({
            ...ORG_PAYLOAD,
            organization: { ...ORG_PAYLOAD.organization, managed_on_sway: false },
            organization_bill_positions: [
                {
                    id: 1,
                    bill_id: 10,
                    support: "FOR",
                    summary: "Good policy",
                    source_kind: "news_article",
                    source_url: "https://news.example/story",
                },
            ],
        });
        render(<OrgDetailScreen route={makeRoute()} navigation={makeNav()} />);

        fireEvent.press(await screen.findByRole("link", { name: PARITY_COPY.orgs.sourceNewsArticle }));
        expect(openURL).toHaveBeenCalledWith("https://news.example/story");
    });
});

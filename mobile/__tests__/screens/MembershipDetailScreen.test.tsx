// @lat: [[mobile-membership-state#Single Authoritative State Boundary]]

const mockGet = jest.fn();
const mockPatch = jest.fn();
const mockPost = jest.fn();
const mockDelete = jest.fn();

jest.mock("../../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...args),
        patch: (...args: unknown[]) => mockPatch(...args),
        post: (...args: unknown[]) => mockPost(...args),
        delete: (...args: unknown[]) => mockDelete(...args),
    },
}));

jest.mock("../../src/hooks/useMembership", () => ({
    useMembership: jest.fn(),
}));
jest.mock("@react-navigation/native", () => ({
    useNavigation: () => ({ setParams: jest.fn() }),
    useRoute: () => ({ params: { orgId: 1, id: 5 } }),
}));
jest.mock("../../src/components/MembersList", () => ({
    // oxlint-disable-next-line @typescript-eslint/no-explicit-any
    MembersList: (props: any) => {
        // oxlint-disable-next-line @typescript-eslint/no-require-imports
        const { View } = require("react-native");
        return <View testID={props.testID ?? "members-list"} />;
    },
}));
jest.mock("../../src/hooks/useInviteAccept", () => {
    const actual = jest.requireActual("../../src/hooks/useInviteAccept");
    return {
        ...actual,
        useInviteAccept: jest.fn(actual.useInviteAccept),
    };
});
jest.mock("../../src/hooks/useReachability", () => ({
    useReachability: () => ({ isOnline: true, isResolved: true }),
}));

import React from "react";
import { Alert } from "react-native";
import { render, fireEvent, waitFor, cleanup, act } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import MembershipDetailScreen from "../../src/screens/MembershipDetailScreen";
import { useMembership } from "../../src/hooks/useMembership";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";
import { organizationPositionTag } from "../../../app/frontend/sway_utils/organizationPositionLabels";

const mockUseMembership = useMembership as jest.Mock;

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const makeMembership = (role: "standard" | "admin", orgName: string) => ({
    membership: {
        id: 5,
        role,
        organization: { id: 1, name: orgName },
        positions: [],
        members: [],
    },
});

const originalDev = (global as Record<string, unknown>).__DEV__;
afterAll(() => {
    (global as Record<string, unknown>).__DEV__ = originalDev;
});

describe("MembershipDetailScreen — non-admin role", () => {
    beforeEach(() => {
        mockUseMembership.mockReset();
    });

    test("renders 2-tab strip with Positions and Pending Changes for non-admin", () => {
        mockUseMembership.mockReturnValue({
            data: makeMembership("standard", "Baltimore Climate Action"),
            loading: false,
            error: null,
            refresh: jest.fn(),
        });

        const { getAllByRole } = wrap(<MembershipDetailScreen />);
        const tabs = getAllByRole("tab");
        expect(tabs).toHaveLength(2);
        expect(tabs[0].props.accessibilityLabel).toMatch(/positions/i);
        expect(tabs[1].props.accessibilityLabel).toMatch(/pending changes/i);
    });

    test("has testID=membership-detail-screen", () => {
        mockUseMembership.mockReturnValue({
            data: makeMembership("standard", "Some Org"),
            loading: false,
            error: null,
            refresh: jest.fn(),
        });
        const { getByTestId } = wrap(<MembershipDetailScreen />);
        expect(getByTestId("membership-detail-screen")).toBeTruthy();
    });
});

describe("MembershipDetailScreen — position tags", () => {
    beforeEach(() => {
        mockUseMembership.mockReset();
    });

    test("tags each position with who posted it, naming the organization shown", () => {
        const data = makeMembership("standard", "Baltimore Climate Action");
        mockUseMembership.mockReturnValue({
            data: {
                membership: {
                    ...data.membership,
                    positions: [{ id: 7, support: "FOR", summary: "We support it.", source_kind: "organization" }],
                },
            },
            loading: false,
            error: null,
            refresh: jest.fn(),
        });

        const { getByTestId } = wrap(<MembershipDetailScreen />);
        expect(getByTestId("org-position-source-tag").props.children).toBe(
            organizationPositionTag("Baltimore Climate Action", "organization"),
        );
    });
});

describe("MembershipDetailScreen — org admin (non-Sway)", () => {
    beforeEach(() => {
        mockUseMembership.mockReset();
    });

    test("renders 3-tab strip for org admin of non-Sway org", () => {
        mockUseMembership.mockReturnValue({
            data: makeMembership("admin", "Baltimore Climate Action"),
            loading: false,
            error: null,
            refresh: jest.fn(),
        });

        const { getAllByRole } = wrap(<MembershipDetailScreen />);
        const tabs = getAllByRole("tab");
        expect(tabs).toHaveLength(3);
        expect(tabs[0].props.accessibilityLabel).toMatch(/positions/i);
        expect(tabs[1].props.accessibilityLabel).toMatch(/pending changes/i);
        expect(tabs[2].props.accessibilityLabel).toMatch(/members/i);
    });
});

describe("MembershipDetailScreen — members-only admin layout", () => {
    beforeEach(() => {
        mockUseMembership.mockReset();
        (global as Record<string, unknown>).__DEV__ = false;
    });

    afterEach(() => {
        (global as Record<string, unknown>).__DEV__ = originalDev;
    });

    test("renders NO tab strip when membersOnlyAdminLayout is active; shows MembersList directly", () => {
        mockUseMembership.mockReturnValue({
            data: makeMembership("admin", "Sway"),
            loading: false,
            error: null,
            refresh: jest.fn(),
        });

        const { queryAllByRole, getByTestId } = wrap(<MembershipDetailScreen />);
        expect(queryAllByRole("tab")).toHaveLength(0);
        expect(getByTestId("members-list")).toBeTruthy();
    });
});

describe("MembershipDetailScreen — membership state consistency across mutations", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockPatch.mockReset();
        mockPost.mockReset();
        mockDelete.mockReset();
        mockUseMembership.mockReset();
        // oxlint-disable-next-line @typescript-eslint/no-require-imports
        const actual = jest.requireActual("../../src/hooks/useMembership");
        mockUseMembership.mockImplementation(actual.useMembership);
    });

    test("approving a pending change refreshes the displayed positions on the screen", async () => {
        const initialMembership = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Baltimore Climate Action", sway_locale_id: 1 },
                positions: [
                    {
                        id: 10,
                        support: "FOR",
                        summary: "Old summary text",
                        organization_bill_position_id: 10,
                    },
                ],
                pending_changes: [
                    {
                        id: 101,
                        organization_bill_position_id: 10,
                        previous_support: "FOR",
                        new_support: "AGAINST",
                        previous_summary: "Old summary text",
                        new_summary: "Updated summary text",
                        created_at: "2026-09-29T00:00:00Z",
                        approved_by_id: null,
                    },
                ],
                members: [],
            },
        };

        const updatedMembership = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Baltimore Climate Action", sway_locale_id: 1 },
                positions: [
                    {
                        id: 10,
                        support: "AGAINST",
                        summary: "Updated summary text",
                        organization_bill_position_id: 10,
                    },
                ],
                pending_changes: [],
                members: [],
            },
        };

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(initialMembership);
            }
            if (url.startsWith("/bills")) {
                return Promise.resolve({ bills: [] });
            }
            return Promise.resolve({});
        });

        const { getByText, getByLabelText, findByText } = wrap(<MembershipDetailScreen />);

        expect(await findByText("Old summary text")).toBeTruthy();

        fireEvent.press(getByText(PARITY_COPY.memberships.tabPendingChanges));
        expect(await findByText("Updated summary text")).toBeTruthy();

        mockPatch.mockResolvedValueOnce({ success: true });
        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(updatedMembership);
            }
            if (url.startsWith("/bills")) {
                return Promise.resolve({ bills: [] });
            }
            return Promise.resolve({});
        });

        fireEvent.press(getByLabelText(PARITY_COPY.pendingChanges.approveLabel));

        await waitFor(() => {
            expect(mockPatch).toHaveBeenCalledWith("/organizations/1/position_changes/101", undefined);
        });

        fireEvent.press(getByText(PARITY_COPY.memberships.tabPositions));

        expect(await findByText("Updated summary text")).toBeTruthy();
    });

    test("rejecting a pending change refreshes the displayed pending changes", async () => {
        const initialMembership = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Baltimore Climate Action", sway_locale_id: 1 },
                positions: [],
                pending_changes: [
                    {
                        id: 101,
                        organization_bill_position_id: 10,
                        previous_support: "FOR",
                        new_support: "AGAINST",
                        previous_summary: "Old summary text",
                        new_summary: "Updated summary text",
                        created_at: "2026-09-29T00:00:00Z",
                        approved_by_id: null,
                    },
                ],
                members: [],
            },
        };

        const emptyMembership = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Baltimore Climate Action", sway_locale_id: 1 },
                positions: [],
                pending_changes: [],
                members: [],
            },
        };

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(initialMembership);
            }
            if (url.startsWith("/bills")) {
                return Promise.resolve({ bills: [] });
            }
            return Promise.resolve({});
        });

        const { getByText, getByLabelText, getByTestId, findByText } = wrap(<MembershipDetailScreen />);

        expect(await findByText(PARITY_COPY.memberships.tabPendingChanges)).toBeTruthy();
        fireEvent.press(getByText(PARITY_COPY.memberships.tabPendingChanges));
        expect(await findByText("Updated summary text")).toBeTruthy();

        mockDelete.mockResolvedValueOnce(undefined);
        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(emptyMembership);
            }
            return Promise.resolve({});
        });

        fireEvent.press(getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));

        fireEvent.press(getByTestId("btn-destructive-confirm"));

        await waitFor(() => {
            expect(mockDelete).toHaveBeenCalledWith("/organizations/1/position_changes/101");
        });

        expect(await findByText(PARITY_COPY.pendingChanges.empty)).toBeTruthy();
    });

    test("proposing a new position in NewPositionModal immediately refreshes the positions list", async () => {
        const initialMembership = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Baltimore Climate Action", sway_locale_id: 1 },
                positions: [],
                pending_changes: [],
                members: [],
            },
        };

        const populatedMembership = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Baltimore Climate Action", sway_locale_id: 1 },
                positions: [
                    {
                        id: 201,
                        support: "FOR",
                        summary: "New position summary",
                        bill: { id: 7, external_id: "HB0007", title: "Clean Air Act" },
                    },
                ],
                pending_changes: [],
                members: [],
            },
        };

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(initialMembership);
            }
            if (url.startsWith("/bills")) {
                return Promise.resolve({
                    bills: [{ id: 7, external_id: "HB0007", title: "Clean Air Act" }],
                    all_categories: [],
                });
            }
            return Promise.resolve({});
        });

        const { getByText, getByTestId, getByLabelText, findByText } = wrap(<MembershipDetailScreen />);

        expect(await findByText(PARITY_COPY.positions.empty)).toBeTruthy();

        fireEvent.press(getByText(PARITY_COPY.positions.newModalTitle));

        expect(await findByText("HB0007")).toBeTruthy();
        fireEvent.press(getByTestId("bill-picker-item-7"));

        fireEvent.changeText(getByTestId("new-position-summary"), "New position summary");

        mockPost.mockResolvedValueOnce({ success: true });
        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(populatedMembership);
            }
            if (url.startsWith("/bills")) {
                return Promise.resolve({ bills: [] });
            }
            return Promise.resolve({});
        });

        fireEvent.press(getByLabelText(PARITY_COPY.positions.newSubmitLabel));

        await waitFor(() => {
            expect(mockPost).toHaveBeenCalledWith(
                "/organizations/1/positions",
                expect.objectContaining({
                    bill_id: 7,
                    support: "FOR",
                    summary: "New position summary",
                }),
            );
        });

        expect(await findByText("New position summary")).toBeTruthy();
    });

    test("mounting MembershipDetailScreen with hidden modal does NOT fetch duplicate membership snapshots", async () => {
        mockGet.mockResolvedValue({
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Baltimore Climate Action", sway_locale_id: 1 },
                positions: [],
                pending_changes: [],
                members: [],
            },
        });

        const { findByText } = wrap(<MembershipDetailScreen />);
        expect(await findByText(PARITY_COPY.positions.empty)).toBeTruthy();

        const membershipGets = mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5");
        expect(membershipGets).toHaveLength(1);
    });
});

describe("review: authoritative membership refresh", () => {
    jest.setTimeout(15000);

    const initial = {
        membership: {
            id: 5,
            role: "admin",
            organization: { id: 1, name: "Audit Org", sway_locale_id: 1 },
            positions: [],
            pending_changes: [],
            members: [],
        },
    };

    beforeEach(() => {
        mockGet.mockReset();
        mockPost.mockReset();
        mockPatch.mockReset();
        mockDelete.mockReset();
        mockUseMembership.mockReset();
        mockUseMembership.mockImplementation(jest.requireActual("../../src/hooks/useMembership").useMembership);
        mockGet.mockImplementation((url: string) =>
            Promise.resolve(
                url.startsWith("/bills")
                    ? { bills: [{ id: 7, external_id: "HB0007", title: "Clean Air Act" }] }
                    : initial,
            ),
        );
    });

    afterEach(() => {
        cleanup();
    });

    test("opening the proposal modal does not fetch another membership snapshot", async () => {
        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.positions.empty);
        fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
        await screen.findByText("HB0007");
        expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(1);
    });

    test("a successful proposal refreshes membership exactly once", async () => {
        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.positions.empty);
        fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
        await screen.findByText("HB0007");
        fireEvent.press(screen.getByTestId("bill-picker-item-7"));
        fireEvent.changeText(screen.getByTestId("new-position-summary"), "Created summary");
        mockGet.mockClear();
        mockPost.mockResolvedValue({ success: true });
        fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
        await waitFor(() => expect(screen.queryByTestId("new-position-modal") === null).toBe(true));
        expect(screen.queryByTestId("new-position-modal")).toBeNull();
        expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(1);
    });

    test("a failed authoritative reload does not silently complete the proposal UI", async () => {
        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.positions.empty);
        fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
        await screen.findByText("HB0007");
        fireEvent.press(screen.getByTestId("bill-picker-item-7"));
        fireEvent.changeText(screen.getByTestId("new-position-summary"), "Created summary");
        mockGet.mockClear();
        mockGet.mockRejectedValue(new Error("audit refresh failed"));
        mockPost.mockResolvedValue({ success: true });
        fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
        await waitFor(() => expect(mockPost).toHaveBeenCalledTimes(1));
        await waitFor(() => expect(screen.queryByTestId("proposal-reload-error-banner")).not.toBeNull());
        expect(screen.queryByTestId("new-position-modal")).not.toBeNull();
    });

    test("retrying proposal refresh calls GET without calling POST again", async () => {
        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.positions.empty);
        fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
        await screen.findByText("HB0007");
        fireEvent.press(screen.getByTestId("bill-picker-item-7"));
        fireEvent.changeText(screen.getByTestId("new-position-summary"), "Created summary");
        mockGet.mockClear();
        mockGet.mockRejectedValueOnce(new Error("audit refresh failed"));
        mockPost.mockResolvedValue({ success: true });
        fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
        await waitFor(() => expect(screen.queryByTestId("proposal-reload-error-banner")).not.toBeNull());
        expect(mockPost).toHaveBeenCalledTimes(1);

        mockGet.mockImplementation((url: string) =>
            Promise.resolve(
                url.startsWith("/bills")
                    ? { bills: [{ id: 7, external_id: "HB0007", title: "Clean Air Act" }] }
                    : initial,
            ),
        );
        fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
        await waitFor(() => expect(screen.queryByTestId("new-position-modal") === null).toBe(true));
        expect(screen.queryByTestId("new-position-modal")).toBeNull();
        expect(mockPost).toHaveBeenCalledTimes(1);
        expect(
            mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5").length,
        ).toBeGreaterThanOrEqual(1);
    });

    test("failed mutation does not trigger reload", async () => {
        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.positions.empty);
        fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
        await screen.findByText("HB0007");
        fireEvent.press(screen.getByTestId("bill-picker-item-7"));
        fireEvent.changeText(screen.getByTestId("new-position-summary"), "Created summary");
        mockGet.mockClear();
        mockPost.mockRejectedValueOnce(new Error("mutation network failure"));
        fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
        await waitFor(() => expect(mockPost).toHaveBeenCalledTimes(1));
        expect(screen.queryByTestId("new-position-modal")).not.toBeNull();
        expect(screen.queryByTestId("proposal-reload-error-banner")).toBeNull();
        expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(0);
    });

    test("failed reload after approving a pending change renders membership-reload-error-banner while retaining last known data, and clicking membership-reload-retry-button refreshes without calling PATCH again", async () => {
        const initialWithPending = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Audit Org", sway_locale_id: 1 },
                positions: [],
                pending_changes: [
                    {
                        id: 101,
                        organization_bill_position_id: 10,
                        previous_support: "FOR",
                        new_support: "AGAINST",
                        previous_summary: "Old summary text",
                        new_summary: "Updated summary text",
                        created_at: "2026-09-29T00:00:00Z",
                        approved_by_id: null,
                    },
                ],
                members: [],
            },
        };

        const resolvedEmpty = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Audit Org", sway_locale_id: 1 },
                positions: [],
                pending_changes: [],
                members: [],
            },
        };

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(initialWithPending);
            }
            return Promise.resolve({});
        });

        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.memberships.tabPendingChanges);
        fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
        expect(await screen.findByText("Updated summary text")).toBeTruthy();

        mockPatch.mockResolvedValueOnce({ success: true });
        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.reject(new Error("authoritative reload failed"));
            }
            return Promise.resolve({});
        });

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));
        await waitFor(() => expect(mockPatch).toHaveBeenCalledWith("/organizations/1/position_changes/101", undefined));

        expect(await screen.findByText("Updated summary text")).toBeTruthy();
        expect(await screen.findByTestId("membership-reload-error-banner", {}, { timeout: 10000 })).toBeTruthy();
        expect(screen.getByTestId("membership-reload-retry-button")).toBeTruthy();

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(resolvedEmpty);
            }
            return Promise.resolve({});
        });

        fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
        await screen.findByText(PARITY_COPY.pendingChanges.empty);
        expect(mockPatch).toHaveBeenCalledTimes(1);
        expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
    });

    test("failed reload after rejecting a pending change renders membership-reload-error-banner without showing a Reject failed alert, and retrying refreshes without calling DELETE again", async () => {
        const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});

        const initialWithPending = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Audit Org", sway_locale_id: 1 },
                positions: [],
                pending_changes: [
                    {
                        id: 101,
                        organization_bill_position_id: 10,
                        previous_support: "FOR",
                        new_support: "AGAINST",
                        previous_summary: "Old summary text",
                        new_summary: "Updated summary text",
                        created_at: "2026-09-29T00:00:00Z",
                        approved_by_id: null,
                    },
                ],
                members: [],
            },
        };

        const resolvedEmpty = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Audit Org", sway_locale_id: 1 },
                positions: [],
                pending_changes: [],
                members: [],
            },
        };

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(initialWithPending);
            }
            return Promise.resolve({});
        });

        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.memberships.tabPendingChanges);
        fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
        expect(await screen.findByText("Updated summary text")).toBeTruthy();

        mockDelete.mockResolvedValueOnce(undefined);
        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.reject(new Error("authoritative reload failed"));
            }
            return Promise.resolve({});
        });

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockDelete).toHaveBeenCalledWith("/organizations/1/position_changes/101"));
        expect(mockDelete).toHaveBeenCalledTimes(1);

        expect(await screen.findByText("Updated summary text")).toBeTruthy();
        expect(await screen.findByTestId("membership-reload-error-banner", {}, { timeout: 10000 })).toBeTruthy();
        expect(screen.getByTestId("membership-reload-retry-button")).toBeTruthy();
        expect(alertSpy).not.toHaveBeenCalled();

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(resolvedEmpty);
            }
            return Promise.resolve({});
        });

        fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
        await screen.findByText(PARITY_COPY.pendingChanges.empty);
        expect(mockDelete).toHaveBeenCalledTimes(1);
        expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();

        alertSpy.mockRestore();
    });

    test("failed rejection DELETE displays rejection error feedback and does not trigger reload", async () => {
        const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});

        const initialWithPending = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Audit Org", sway_locale_id: 1 },
                positions: [],
                pending_changes: [
                    {
                        id: 101,
                        organization_bill_position_id: 10,
                        previous_support: "FOR",
                        new_support: "AGAINST",
                        previous_summary: "Old summary text",
                        new_summary: "Updated summary text",
                        created_at: "2026-09-29T00:00:00Z",
                        approved_by_id: null,
                    },
                ],
                members: [],
            },
        };

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(initialWithPending);
            }
            return Promise.resolve({});
        });

        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.memberships.tabPendingChanges);
        fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
        expect(await screen.findByText("Updated summary text")).toBeTruthy();

        mockGet.mockClear();
        mockDelete.mockRejectedValueOnce(new Error("rejection network error"));

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockDelete).toHaveBeenCalledWith("/organizations/1/position_changes/101"));
        expect(mockDelete).toHaveBeenCalledTimes(1);

        await waitFor(() => expect(alertSpy).toHaveBeenCalledWith("Reject failed", "rejection network error"));
        expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(0);
        expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
        expect(screen.getByText("Updated summary text")).toBeTruthy();

        alertSpy.mockRestore();
    });

    test("rejection controls remain busy while post-rejection reload is in flight", async () => {
        const initialWithPending = {
            membership: {
                id: 5,
                role: "admin",
                organization: { id: 1, name: "Audit Org", sway_locale_id: 1 },
                positions: [],
                pending_changes: [
                    {
                        id: 101,
                        organization_bill_position_id: 10,
                        previous_support: "FOR",
                        new_support: "AGAINST",
                        previous_summary: "Old summary text",
                        new_summary: "Updated summary text",
                        created_at: "2026-09-29T00:00:00Z",
                        approved_by_id: null,
                    },
                ],
                members: [],
            },
        };

        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(initialWithPending);
            }
            return Promise.resolve({});
        });

        const screen = wrap(<MembershipDetailScreen />);
        await screen.findByText(PARITY_COPY.memberships.tabPendingChanges);
        fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
        expect(await screen.findByText("Updated summary text")).toBeTruthy();

        mockDelete.mockResolvedValueOnce(undefined);

        let resolveGet!: (value: unknown) => void;
        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return new Promise((resolve) => {
                    resolveGet = resolve;
                });
            }
            return Promise.resolve({});
        });

        fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

        await waitFor(() => expect(mockDelete).toHaveBeenCalledTimes(1));

        const rejectBtn = screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel);
        expect(rejectBtn.props.accessibilityState?.disabled).toBe(true);

        await act(async () => {
            resolveGet({
                membership: {
                    ...initialWithPending.membership,
                    pending_changes: [],
                },
            });
        });

        await screen.findByText(PARITY_COPY.pendingChanges.empty);
    });
});

describe("Keep accepted invitations saved during membership refresh recovery", () => {
    jest.setTimeout(30000);

    const pendingMembership = {
        membership: {
            id: 5,
            role: "standard",
            status: "pending",
            organization: { id: 1, name: "Civic Coalition", sway_locale_id: 1 },
            positions: [],
            pending_changes: [],
            members: [],
        },
    };

    const activeMembership = {
        membership: {
            ...pendingMembership.membership,
            status: "active",
        },
    };

    beforeEach(() => {
        mockGet.mockReset();
        mockPost.mockReset();
        mockPatch.mockReset();
        mockDelete.mockReset();
        mockUseMembership.mockReset();
        mockUseMembership.mockImplementation(jest.requireActual("../../src/hooks/useMembership").useMembership);
    });

    test("when acceptance POST succeeds and GET reload fails, renders reload error banner, does not render accept error banner, and retrying reload does not repeat POST", async () => {
        let getCount = 0;
        let resolveFinalMembership!: (value: unknown) => void;
        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                getCount += 1;
                if (getCount === 1) return Promise.resolve(pendingMembership);
                if (getCount === 2) {
                    return Promise.reject(new Error("membership refresh unavailable"));
                }
                return new Promise((resolve) => {
                    resolveFinalMembership = resolve;
                });
            }
            return Promise.resolve({});
        });
        mockPost.mockResolvedValue({ success: true });

        const screen = wrap(<MembershipDetailScreen />);

        await screen.findByTestId("membership-reload-error-banner", {}, { timeout: 10000 });

        expect(mockPost).toHaveBeenCalledTimes(1);
        expect(mockPost).toHaveBeenCalledWith("/organizations/1/membership_invites/5/accept", undefined);

        expect(screen.queryByTestId("accept-error-banner")).toBeNull();
        expect(screen.queryByText(/could not accept invite/i)).toBeNull();

        expect(screen.getByText("Could not update membership. Displaying cached data.")).toBeTruthy();
        expect(screen.getByTestId("membership-reload-retry-button")).toBeTruthy();

        await act(async () => {
            fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
            resolveFinalMembership(activeMembership);
        });

        await waitFor(
            () => {
                expect(getCount).toBe(3);
                expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
            },
            { timeout: 10000 },
        );

        expect(mockPost).toHaveBeenCalledTimes(1);
    });

    test("when acceptance POST fails, renders accept-error-banner with retry button and retrying calls POST again", async () => {
        mockGet.mockImplementation((url: string) => {
            if (url === "/organizations/1/memberships/5") {
                return Promise.resolve(pendingMembership);
            }
            return Promise.resolve({});
        });
        mockPost.mockRejectedValueOnce(new Error("Accept failed"));

        const screen = wrap(<MembershipDetailScreen />);

        await screen.findByTestId("accept-error-banner");
        expect(screen.getByText("Could not accept invite. Please try again.")).toBeTruthy();
        expect(mockPost).toHaveBeenCalledTimes(1);
        expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();

        mockPost.mockResolvedValueOnce({ success: true });
        fireEvent.press(screen.getByTestId("accept-retry-button"));

        await waitFor(() => {
            expect(mockPost).toHaveBeenCalledTimes(2);
        });
    });
});

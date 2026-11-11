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

jest.mock("@react-navigation/native", () => ({
    useNavigation: () => ({ setParams: jest.fn() }),
    useRoute: () => ({ params: { orgId: 1, id: 5 } }),
}));
jest.mock("../../src/components/MembersList", () => ({
    MembersList: (props: { testID?: string }) => {
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
import { render, fireEvent, fireEventAsync, waitFor, cleanup, act } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import MembershipDetailScreen from "../../src/screens/MembershipDetailScreen";
import { ApiRequestError } from "../../src/api/errors";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

describe("Refresh the displayed mobile membership after position mutations", () => {
    jest.setTimeout(30000);

    const initialMembership = {
        membership: {
            id: 5,
            role: "admin",
            organization: { id: 1, name: "Civic Coalition", sway_locale_id: 1 },
            positions: [
                {
                    id: 10,
                    support: "FOR",
                    summary: "Existing Position Summary",
                    organization_bill_position_id: 10,
                },
            ],
            pending_changes: [
                {
                    id: 101,
                    organization_bill_position_id: 10,
                    previous_support: "FOR",
                    new_support: "AGAINST",
                    previous_summary: "Existing Position Summary",
                    new_summary: "Proposed Stricter Summary",
                    created_at: "2026-09-30T00:00:00Z",
                    approved_by_id: null,
                },
            ],
            members: [],
        },
    };

    const emptyPendingMembership = {
        membership: {
            id: 5,
            role: "admin",
            organization: { id: 1, name: "Civic Coalition", sway_locale_id: 1 },
            positions: [
                {
                    id: 10,
                    support: "AGAINST",
                    summary: "Proposed Stricter Summary",
                    organization_bill_position_id: 10,
                },
            ],
            pending_changes: [],
            members: [],
        },
    };

    beforeEach(() => {
        mockGet.mockReset();
        mockPost.mockReset();
        mockPatch.mockReset();
        mockDelete.mockReset();

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
    });

    afterEach(() => {
        cleanup();
    });

    // @lat: [[mobile-membership-state#Single authoritative state boundary]]
    test.each(["Close button", "native dismissal"])(
        "%s cannot dismiss a proposal while its POST or membership reload is pending",
        async (dismissal) => {
            let resolveInitialMembership!: (value: unknown) => void;
            mockGet.mockImplementationOnce(
                () =>
                    new Promise((resolve) => {
                        resolveInitialMembership = resolve;
                    }),
            );
            const screen = wrap(<MembershipDetailScreen />);
            await act(async () => {
                resolveInitialMembership(initialMembership);
            });
            await screen.findByText("Existing Position Summary");
            fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
            await screen.findByText("HB0007");
            fireEvent.press(screen.getByTestId("bill-picker-item-7"));
            fireEvent.changeText(screen.getByTestId("new-position-summary-input"), "First draft");

            let resolvePost!: (value: unknown) => void;
            let resolveReload!: (value: unknown) => void;
            mockPost.mockImplementationOnce(
                () =>
                    new Promise((resolve) => {
                        resolvePost = resolve;
                    }),
            );
            mockGet.mockClear();
            mockGet.mockImplementationOnce(
                () =>
                    new Promise((resolve) => {
                        resolveReload = resolve;
                    }),
            );

            const dismiss = () => {
                if (dismissal === "Close button") {
                    fireEvent.press(screen.getByLabelText("Close"));
                } else {
                    fireEvent(screen.getByTestId("new-position-modal"), "requestClose");
                }
            };
            const membershipReads = () =>
                mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5");

            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(membershipReads()).toHaveLength(0);
            dismiss();
            expect(screen.queryByTestId("new-position-modal")).not.toBeNull();
            expect(screen.getByTestId("new-position-summary-input").props.value).toBe("First draft");
            expect(screen.getByLabelText("Close").props.accessibilityState?.disabled).toBe(true);
            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            expect(mockPost).toHaveBeenCalledTimes(1);

            await act(async () => {
                resolvePost({ success: true });
            });
            expect(membershipReads()).toHaveLength(1);
            dismiss();
            expect(screen.queryByTestId("new-position-modal")).not.toBeNull();
            expect(screen.getByTestId("new-position-summary-input").props.value).toBe("First draft");
            expect(screen.getByLabelText("Close").props.accessibilityState?.disabled).toBe(true);
            expect(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel).props.accessibilityState?.disabled).toBe(
                true,
            );
            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            expect(mockPost).toHaveBeenCalledTimes(1);

            await act(async () => {
                resolveReload(initialMembership);
            });
            expect(screen.queryByTestId("new-position-modal")).toBeNull();
            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(membershipReads()).toHaveLength(1);

            fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
            await screen.findByText("HB0007");
            expect(screen.getByTestId("new-position-summary-input").props.value).toBe("");
            expect(screen.getByLabelText("Close").props.accessibilityState?.disabled).toBe(false);
            dismiss();
            expect(screen.queryByTestId("new-position-modal")).toBeNull();

            fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
            await screen.findByText("HB0007");
            fireEvent.press(screen.getByTestId("bill-picker-item-7"));
            fireEvent.changeText(screen.getByTestId("new-position-summary-input"), "Second draft");
            mockPost.mockResolvedValueOnce({ success: true });
            await act(async () => {
                fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            });
            expect(screen.queryByTestId("new-position-modal")).toBeNull();
            expect(mockPost).toHaveBeenCalledTimes(2);
            expect(membershipReads()).toHaveLength(2);
        },
    );

    describe("Challenge 1: Repeated Retry Cycles", () => {
        test("post-mutation reload fails 3 times in a row, then succeeds on 4th try: POST /positions called exactly once", async () => {
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary", {}, { timeout: 10000 });

            fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
            await screen.findByText("HB0007");
            fireEvent.press(screen.getByTestId("bill-picker-item-7"));
            fireEvent.changeText(screen.getByTestId("new-position-summary"), "Adversarial Stress Summary");

            const updatedWithNewPosition = {
                membership: {
                    ...initialMembership.membership,
                    positions: [
                        ...initialMembership.membership.positions,
                        {
                            id: 99,
                            support: "FOR",
                            summary: "Adversarial Stress Summary",
                            bill: { id: 7, external_id: "HB0007", title: "Clean Air Act" },
                        },
                    ],
                },
            };

            let reloadAttempts = 0;
            mockGet.mockClear();
            mockPost.mockResolvedValueOnce({ success: true });
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    reloadAttempts += 1;
                    if (reloadAttempts <= 3) {
                        return Promise.reject(new Error(`Authoritative reload timeout #${reloadAttempts}`));
                    }
                    return Promise.resolve(updatedWithNewPosition);
                }
                if (url.startsWith("/bills")) {
                    return Promise.resolve({
                        bills: [{ id: 7, external_id: "HB0007", title: "Clean Air Act" }],
                        all_categories: [],
                    });
                }
                return Promise.resolve({});
            });

            await fireEventAsync.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            await waitFor(() => expect(mockPost).toHaveBeenCalledTimes(1));
            await waitFor(() => expect(screen.queryByTestId("proposal-reload-error-banner")).not.toBeNull());
            expect(screen.queryByTestId("new-position-modal")).not.toBeNull();
            expect(screen.getByText("Position saved, but updating membership failed. Please retry.")).toBeTruthy();
            expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(1);
            await screen.findByText("Retry refresh");

            await fireEventAsync.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            await waitFor(() => {
                expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(2);
            });
            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("new-position-modal")).not.toBeNull();
            expect(await screen.findByTestId("proposal-reload-error-banner")).toBeTruthy();
            await screen.findByText("Retry refresh");

            await fireEventAsync.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            await waitFor(() => {
                expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(3);
            });
            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("new-position-modal")).not.toBeNull();
            expect(await screen.findByTestId("proposal-reload-error-banner")).toBeTruthy();
            await screen.findByText("Retry refresh");

            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            await waitFor(() => expect(screen.queryByTestId("new-position-modal") === null).toBe(true), {
                timeout: 10000,
            });
            expect(screen.queryByTestId("new-position-modal")).toBeNull();

            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(4);
            expect(await screen.findByText("Adversarial Stress Summary")).toBeTruthy();
        });

        test("post-approval reload fails 3 times then succeeds on 4th retry: PATCH called exactly once", async () => {
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary", {}, { timeout: 10000 });

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            let reloadAttempts = 0;
            mockPatch.mockResolvedValueOnce({ success: true });
            mockGet.mockClear();
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    reloadAttempts += 1;
                    if (reloadAttempts <= 3) {
                        return Promise.reject(new Error(`Authoritative reload 503 #${reloadAttempts}`));
                    }
                    return Promise.resolve(emptyPendingMembership);
                }
                return Promise.resolve({});
            });

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));

            await waitFor(() => expect(mockPatch).toHaveBeenCalledTimes(1), { timeout: 10000 });
            expect(await screen.findByTestId("membership-reload-error-banner")).toBeTruthy();
            expect(screen.getByTestId("membership-reload-retry-button")).toBeTruthy();
            expect(screen.getByText("Proposed Stricter Summary")).toBeTruthy();
            expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(1);

            await fireEventAsync.press(screen.getByTestId("membership-reload-retry-button"));
            await waitFor(
                () => {
                    expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(
                        2,
                    );
                    expect(
                        screen.getByTestId("membership-reload-retry-button").props.accessibilityState?.disabled,
                    ).toBeFalsy();
                },
                { timeout: 10000 },
            );
            expect(mockPatch).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("membership-reload-error-banner")).not.toBeNull();

            await fireEventAsync.press(screen.getByTestId("membership-reload-retry-button"));
            await waitFor(
                () => {
                    expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(
                        3,
                    );
                    expect(
                        screen.getByTestId("membership-reload-retry-button").props.accessibilityState?.disabled,
                    ).toBeFalsy();
                },
                { timeout: 10000 },
            );
            expect(mockPatch).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("membership-reload-error-banner")).not.toBeNull();

            fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
            await screen.findByText(PARITY_COPY.pendingChanges.empty, {}, { timeout: 10000 });

            expect(mockPatch).toHaveBeenCalledTimes(1);
            expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(4);
            expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
        });

        test("post-rejection reload fails 3 times then succeeds on 4th retry: DELETE called exactly once and no alert is shown", async () => {
            const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary", {}, { timeout: 10000 });

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            let reloadAttempts = 0;
            mockDelete.mockResolvedValueOnce(undefined);
            mockGet.mockClear();
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    reloadAttempts += 1;
                    if (reloadAttempts <= 3) {
                        return Promise.reject(new Error(`Authoritative reload 503 #${reloadAttempts}`));
                    }
                    return Promise.resolve(emptyPendingMembership);
                }
                return Promise.resolve({});
            });

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
            fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

            await waitFor(() => expect(mockDelete).toHaveBeenCalledTimes(1), { timeout: 10000 });
            expect(mockDelete).toHaveBeenCalledWith("/organizations/1/position_changes/101");
            expect(await screen.findByTestId("membership-reload-error-banner")).toBeTruthy();
            expect(screen.getByTestId("membership-reload-retry-button")).toBeTruthy();
            expect(screen.getByText("Proposed Stricter Summary")).toBeTruthy();
            expect(alertSpy).not.toHaveBeenCalled();
            expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(1);

            await fireEventAsync.press(screen.getByTestId("membership-reload-retry-button"));
            await waitFor(
                () => {
                    expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(
                        2,
                    );
                    expect(
                        screen.getByTestId("membership-reload-retry-button").props.accessibilityState?.disabled,
                    ).toBeFalsy();
                },
                { timeout: 10000 },
            );
            expect(mockDelete).toHaveBeenCalledTimes(1);
            expect(alertSpy).not.toHaveBeenCalled();
            expect(screen.queryByTestId("membership-reload-error-banner")).not.toBeNull();

            await fireEventAsync.press(screen.getByTestId("membership-reload-retry-button"));
            await waitFor(
                () => {
                    expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(
                        3,
                    );
                    expect(
                        screen.getByTestId("membership-reload-retry-button").props.accessibilityState?.disabled,
                    ).toBeFalsy();
                },
                { timeout: 10000 },
            );
            expect(mockDelete).toHaveBeenCalledTimes(1);
            expect(alertSpy).not.toHaveBeenCalled();
            expect(screen.queryByTestId("membership-reload-error-banner")).not.toBeNull();

            fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
            await screen.findByText(PARITY_COPY.pendingChanges.empty, {}, { timeout: 10000 });

            expect(mockDelete).toHaveBeenCalledTimes(1);
            expect(alertSpy).not.toHaveBeenCalled();
            expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(4);
            expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();

            alertSpy.mockRestore();
        });
    });

    describe("Challenge 2: Concurrent Mutation Stress", () => {
        test("rapid repeated presses on proposal submit button while in flight are locked out", async () => {
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary", {}, { timeout: 10000 });

            fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
            await screen.findByText("HB0007");
            fireEvent.press(screen.getByTestId("bill-picker-item-7"));
            fireEvent.changeText(screen.getByTestId("new-position-summary"), "Concurrent Test Summary");

            let resolvePost!: (value: unknown) => void;
            mockPost.mockImplementation(
                () =>
                    new Promise((resolve) => {
                        resolvePost = resolve;
                    }),
            );

            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            expect(mockPost).toHaveBeenCalledTimes(1);

            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));
            fireEvent.press(screen.getByLabelText(PARITY_COPY.positions.newSubmitLabel));

            await act(async () => {
                resolvePost({ success: true });
            });

            await waitFor(() => expect(screen.queryByTestId("new-position-modal") === null).toBe(true), {
                timeout: 10000,
            });
            expect(screen.queryByTestId("new-position-modal")).toBeNull();

            expect(mockPost).toHaveBeenCalledTimes(1);
        });

        test("rapid repeated presses on pending change approval button while in flight are locked out", async () => {
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary");

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            let resolvePatch!: (value: unknown) => void;
            mockPatch.mockImplementation(
                () =>
                    new Promise((resolve) => {
                        resolvePatch = resolve;
                    }),
            );

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));
            expect(mockPatch).toHaveBeenCalledTimes(1);

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));
            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));
            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));
            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));

            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    return Promise.resolve(emptyPendingMembership);
                }
                return Promise.resolve({});
            });

            await act(async () => {
                resolvePatch({ success: true });
            });

            await screen.findByText(PARITY_COPY.pendingChanges.empty);

            expect(mockPatch).toHaveBeenCalledTimes(1);
        });

        test("rejection button is locked out while in-flight DELETE mutation settles", async () => {
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary");

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            let resolveDelete!: (value: unknown) => void;
            mockDelete.mockImplementation(
                () =>
                    new Promise((resolve) => {
                        resolveDelete = resolve;
                    }),
            );

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
            fireEvent.press(screen.getByTestId("btn-destructive-confirm"));
            expect(mockDelete).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("btn-destructive-confirm")).toBeNull();

            const rejectBtn = screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel);
            expect(rejectBtn.props.accessibilityState?.disabled).toBe(true);
            fireEvent.press(rejectBtn);
            fireEvent.press(rejectBtn);
            expect(mockDelete).toHaveBeenCalledTimes(1);

            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    return Promise.resolve(emptyPendingMembership);
                }
                return Promise.resolve({});
            });

            await act(async () => {
                resolveDelete(undefined);
            });

            await screen.findByText(PARITY_COPY.pendingChanges.empty);
            expect(mockDelete).toHaveBeenCalledTimes(1);
        });
    });

    describe("Challenge 3: Network Abort / Disconnect", () => {
        test("aborted network request (ApiRequestError with code 'aborted') suppresses error banners and preserves cached data", async () => {
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary");

            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    return Promise.reject(new ApiRequestError("aborted", "Request was aborted by client"));
                }
                return Promise.resolve({});
            });

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
            expect(screen.getByText("Proposed Stricter Summary")).toBeTruthy();
        });

        test("aborted network request during post-rejection reload suppresses error banners and never alerts failure", async () => {
            const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary");

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            mockDelete.mockResolvedValueOnce(undefined);
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    return Promise.reject(new ApiRequestError("aborted", "Request was aborted by client"));
                }
                return Promise.resolve({});
            });

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
            fireEvent.press(screen.getByTestId("btn-destructive-confirm"));

            await waitFor(() => expect(mockDelete).toHaveBeenCalledTimes(1));
            expect(alertSpy).not.toHaveBeenCalled();
            expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
            expect(screen.getByText("Proposed Stricter Summary")).toBeTruthy();

            alertSpy.mockRestore();
        });

        test("non-abort network error displays reload error banner while preserving cached data", async () => {
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary");

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            mockPatch.mockResolvedValueOnce({ success: true });
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    return Promise.reject(new ApiRequestError("network_error", "Network connection lost"));
                }
                return Promise.resolve({});
            });

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));

            expect(await screen.findByTestId("membership-reload-error-banner")).toBeTruthy();
            expect(screen.getByText("Could not update membership. Displaying cached data.")).toBeTruthy();
            expect(screen.getByText("Proposed Stricter Summary")).toBeTruthy();
        });
    });

    describe("Challenge 4: Error State Recovery & Cached UI Responsiveness", () => {
        test("cached membership remains fully interactable (tabs switchable, modals openable) during reload error state", async () => {
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary");

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            mockPatch.mockResolvedValueOnce({ success: true });
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    return Promise.reject(new Error("Server 500 error"));
                }
                return Promise.resolve({});
            });

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.approveLabel));
            expect(await screen.findByTestId("membership-reload-error-banner")).toBeTruthy();

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPositions));
            expect(await screen.findByText("Existing Position Summary")).toBeTruthy();
            expect(screen.getByTestId("membership-reload-error-banner")).toBeTruthy();

            fireEvent.press(screen.getByText(PARITY_COPY.positions.newModalTitle));
            expect(screen.getByTestId("new-position-modal")).toBeTruthy();

            fireEvent.press(screen.getByLabelText("Close"));
            expect(screen.queryByTestId("new-position-modal")).toBeNull();

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    return Promise.resolve(emptyPendingMembership);
                }
                return Promise.resolve({});
            });

            fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
            await screen.findByText(PARITY_COPY.pendingChanges.empty);

            expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
        });
    });

    describe("Challenge 5: Failed Mutation Retry", () => {
        // @lat: [[mobile-jest-first-pass-test-notes#Retry controls settle after mutation failure]]
        test("failed rejection DELETE alerts error, does not reload, and can be retried successfully", async () => {
            const alertSpy = jest.spyOn(Alert, "alert").mockImplementation(() => {});
            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByText("Existing Position Summary");

            fireEvent.press(screen.getByText(PARITY_COPY.memberships.tabPendingChanges));
            expect(await screen.findByText("Proposed Stricter Summary")).toBeTruthy();

            mockGet.mockClear();
            mockDelete.mockRejectedValueOnce(new Error("500 Internal Server Error"));

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
            await fireEventAsync.press(await screen.findByTestId("btn-destructive-confirm"));

            await waitFor(() => expect(mockDelete).toHaveBeenCalledTimes(1));
            expect(mockDelete).toHaveBeenCalledWith("/organizations/1/position_changes/101");
            await waitFor(() => expect(alertSpy).toHaveBeenCalledWith("Reject failed", "500 Internal Server Error"));
            await waitFor(() => expect(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel)).toBeEnabled());
            expect(mockGet.mock.calls.filter(([url]) => url === "/organizations/1/memberships/5")).toHaveLength(0);
            expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
            expect(screen.getByText("Proposed Stricter Summary")).toBeTruthy();

            mockDelete.mockResolvedValueOnce(undefined);
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    return Promise.resolve(emptyPendingMembership);
                }
                return Promise.resolve({});
            });

            fireEvent.press(screen.getByLabelText(PARITY_COPY.pendingChanges.rejectLabel));
            fireEvent.press(await screen.findByTestId("btn-destructive-confirm"));

            await waitFor(() => expect(mockDelete).toHaveBeenCalledTimes(2));
            await screen.findByText(PARITY_COPY.pendingChanges.empty);
            expect(alertSpy).toHaveBeenCalledTimes(1);

            alertSpy.mockRestore();
        });
    });

    describe("Challenge 6: Repeated Retry Cycles on Invite Acceptance", () => {
        const pendingMembership = {
            membership: {
                id: 5,
                role: "standard",
                status: "pending",
                organization: { id: 1, name: "Civic Coalition", sway_locale_id: 1 },
                positions: [
                    {
                        id: 10,
                        support: "FOR",
                        summary: "Existing Position Summary",
                        organization_bill_position_id: 10,
                    },
                ],
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

        test("post-acceptance reload fails 3 times in a row, then succeeds on 4th try: POST /accept called exactly once", async () => {
            let reloadAttempts = 0;
            let resolveFinalReload!: (value: unknown) => void;
            mockGet.mockReset();
            mockPost.mockReset();
            mockPost.mockResolvedValue({ success: true });
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    reloadAttempts += 1;
                    if (reloadAttempts === 1) return Promise.resolve(pendingMembership);
                    if (reloadAttempts <= 4) {
                        return Promise.reject(new Error(`Authoritative reload timeout #${reloadAttempts}`));
                    }
                    return new Promise((resolve) => {
                        resolveFinalReload = resolve;
                    });
                }
                return Promise.resolve({});
            });

            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByTestId("membership-reload-error-banner", {}, { timeout: 10000 });

            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(mockPost).toHaveBeenCalledWith("/organizations/1/membership_invites/5/accept", undefined);
            expect(screen.queryByTestId("accept-error-banner")).toBeNull();
            expect(screen.getByText("Could not update membership. Displaying cached data.")).toBeTruthy();
            expect(screen.getByTestId("membership-reload-retry-button")).toBeTruthy();

            await fireEventAsync.press(screen.getByTestId("membership-reload-retry-button"));
            await waitFor(
                () => {
                    expect(reloadAttempts).toBe(3);
                    expect(
                        screen.getByTestId("membership-reload-retry-button").props.accessibilityState?.disabled,
                    ).toBeFalsy();
                },
                { timeout: 10000 },
            );
            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("accept-error-banner")).toBeNull();
            expect(screen.queryByTestId("membership-reload-error-banner")).not.toBeNull();

            await fireEventAsync.press(screen.getByTestId("membership-reload-retry-button"));
            await waitFor(
                () => {
                    expect(reloadAttempts).toBe(4);
                    expect(
                        screen.getByTestId("membership-reload-retry-button").props.accessibilityState?.disabled,
                    ).toBeFalsy();
                },
                { timeout: 10000 },
            );
            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("accept-error-banner")).toBeNull();
            expect(screen.queryByTestId("membership-reload-error-banner")).not.toBeNull();

            await act(async () => {
                fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
                resolveFinalReload(activeMembership);
            });
            await waitFor(
                () => {
                    expect(reloadAttempts).toBe(5);
                    expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
                },
                { timeout: 10000 },
            );
            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("accept-error-banner")).toBeNull();
        });

        test("network flap during invite acceptance: initial POST succeeds, GET reload fails with network error, retry succeeds with active data and zero duplicate POSTs", async () => {
            let reloadAttempts = 0;
            let resolveFinalReload!: (value: unknown) => void;
            mockGet.mockReset();
            mockPost.mockReset();
            mockPost.mockResolvedValue({ success: true });
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    reloadAttempts += 1;
                    if (reloadAttempts === 1) return Promise.resolve(pendingMembership);
                    if (reloadAttempts === 2) {
                        return Promise.reject(new ApiRequestError("network_error", "Network connection lost"));
                    }
                    return new Promise((resolve) => {
                        resolveFinalReload = resolve;
                    });
                }
                return Promise.resolve({});
            });

            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByTestId("membership-reload-error-banner", {}, { timeout: 10000 });

            expect(mockPost).toHaveBeenCalledTimes(1);
            expect(screen.queryByTestId("accept-error-banner")).toBeNull();
            expect(screen.getByText("Could not update membership. Displaying cached data.")).toBeTruthy();

            await act(async () => {
                fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
                resolveFinalReload(activeMembership);
            });
            await waitFor(
                () => {
                    expect(reloadAttempts).toBe(3);
                    expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
                },
                { timeout: 10000 },
            );
            expect(mockPost).toHaveBeenCalledTimes(1);
        });

        test("genuine POST failure displays accept-error-banner and allows retry; retried POST success with failing reload transitions to reload recovery without repeating POST", async () => {
            let reloadAttempts = 0;
            mockGet.mockReset();
            mockPost.mockReset();
            mockGet.mockImplementation((url: string) => {
                if (url === "/organizations/1/memberships/5") {
                    reloadAttempts += 1;
                    if (reloadAttempts === 1) return Promise.resolve(pendingMembership);
                    if (reloadAttempts <= 3) {
                        return Promise.reject(new Error(`Reload 503 attempt #${reloadAttempts}`));
                    }
                    return Promise.resolve(activeMembership);
                }
                return Promise.resolve({});
            });
            mockPost.mockRejectedValueOnce(new Error("Network timeout during accept"));

            const screen = wrap(<MembershipDetailScreen />);
            await screen.findByTestId("accept-error-banner", {}, { timeout: 10000 });
            expect(screen.getByText("Could not accept invite. Please try again.")).toBeTruthy();
            expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
            expect(mockPost).toHaveBeenCalledTimes(1);

            mockPost.mockResolvedValueOnce({ success: true });
            await act(async () => {
                fireEvent.press(screen.getByTestId("accept-retry-button"));
            });

            await screen.findByTestId("membership-reload-error-banner", {}, { timeout: 10000 });
            expect(screen.queryByTestId("accept-error-banner")).toBeNull();
            expect(mockPost).toHaveBeenCalledTimes(2);

            await act(async () => {
                fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
            });
            await waitFor(() => {
                expect(reloadAttempts).toBe(3);
                expect(
                    screen.getByTestId("membership-reload-retry-button").props.accessibilityState?.disabled,
                ).toBeFalsy();
            });
            expect(mockPost).toHaveBeenCalledTimes(2);

            await act(async () => {
                fireEvent.press(screen.getByTestId("membership-reload-retry-button"));
            });
            await waitFor(
                () => {
                    expect(reloadAttempts).toBe(4);
                    expect(screen.queryByTestId("membership-reload-error-banner")).toBeNull();
                },
                { timeout: 10000 },
            );
            expect(mockPost).toHaveBeenCalledTimes(2);
        });
    });
});

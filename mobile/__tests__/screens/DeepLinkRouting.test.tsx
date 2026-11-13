// @lat: [[mobile-jest-first-pass-test-notes#DeepLinkRouting.test.tsx]]

import React from "react";
import { render, renderHook, screen } from "@testing-library/react-native";
import * as Notifications from "expo-notifications";
import { getStateFromPath } from "@react-navigation/native";
import { linking } from "../../src/navigation/linking";
import { useDeepLinkRouter } from "../../src/hooks/useDeepLinkRouter";
import BillDetailScreen from "../../src/screens/BillDetailScreen";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

const mockGet = jest.fn();

jest.mock("../../src/api/client", () => ({
    apiClient: { get: (...args: unknown[]) => mockGet(...args) },
}));
jest.mock("../../src/hooks/useFocusedSync", () => ({
    useFocusedSync: () => undefined,
}));
jest.mock("../../src/hooks/useBootstrap", () => ({
    useBootstrap: () => ({ bootstrap: undefined }),
}));
jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => ({ isAuthenticated: false }),
}));
jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => ({ navigate: jest.fn(), getParent: () => undefined }),
}));

describe("linking config — D-42 universal links + D1 dual-host", () => {
    test("prefixes include BOTH sway.vote AND app.sway.vote (D1)", () => {
        expect(linking.prefixes).toEqual(
            expect.arrayContaining(["https://sway.vote", "https://app.sway.vote", "sway://"]),
        );
    });

    test("FeedStack registers FeedList path and resolves /feed to Feed > FeedList", () => {
        const feed = (linking.config as any).screens.Feed;
        expect(feed.screens.FeedList).toBe("feed");
        expect(feed.screens.BillDetail).toBeUndefined();

        const state = getStateFromPath("/feed", { screens: { Feed: feed } } as typeof linking.config);
        expect(state?.routes[0].name).toBe("Feed");
        expect(state?.routes[0].state?.routes.map((route) => route.name)).toEqual(["FeedList"]);
    });

    test("HomeStack registers BillOfTheMonth + BillDetail paths", () => {
        const home = (linking.config as any).screens.Home.screens;
        expect(home.BillOfTheMonth.path).toBe("bill_of_the_month");
        expect(home.BillDetail.path).toBe("bills/:id");
    });

    test.each(["/bill_of_the_month", "/bill_of_the_week"])(
        "the %s deep link opens the Bill of the Month screen",
        (path) => {
            const home = (linking.config as { screens: Record<string, unknown> }).screens.Home;
            const state = getStateFromPath(path, { screens: { Home: home } } as typeof linking.config);

            expect(state?.routes[0].name).toBe("Home");
            expect(state?.routes[0].state?.routes.map((route) => route.name)).toEqual(["BillOfTheMonth"]);
        },
    );

    test("BillsStack registers BillsList, PastBillsOfTheMonth + BillDetail paths", () => {
        const bills = (linking.config as any).screens.Bills.screens;
        expect(bills.BillsList).toBe("bills");
        expect(bills.PastBillsOfTheMonth).toBe("past_bills_of_the_month");
        expect(bills.BillDetail.path).toBe("bills/:id");
    });

    test("LegislatorsStack registers LegislatorsList + LegislatorDetail paths", () => {
        const legs = (linking.config as any).screens.Legislators.screens;
        expect(legs.LegislatorsList).toBe("legislators");
        expect(legs.LegislatorDetail).toBe("legislators/:id");
    });

    test("OrgsStack registers OrgsList + OrgDetail paths", () => {
        const orgs = (linking.config as any).screens.Orgs.screens;
        expect(orgs.OrgsList).toBe("organizations");
        expect(orgs.OrgDetail).toBe("organizations/:id");
    });

    test("ProfileStack registers Profile path", () => {
        const profile = (linking.config as any).screens.Profile.screens;
        expect(profile.ProfileHub).toBe("profile");
    });

    test("AuthStack registers sign-in path on Auth screen", () => {
        const auth = (linking.config as any).screens.Auth;
        expect(auth).toBe("sign-in");
    });

    test("BillDetail screen is registered in BOTH HomeStack AND BillsStack (cross-tab deep-link surface)", () => {
        const home = (linking.config as any).screens.Home.screens;
        const bills = (linking.config as any).screens.Bills.screens;
        expect(home.BillDetail.path).toBe("bills/:id");
        expect(bills.BillDetail.path).toBe("bills/:id");
    });

    // @lat: [[mobile-jest-first-pass-test-notes#DeepLinkRouting.test.tsx]]
    test("BillsStackParamList no longer includes PreviousBills (Phase 34 D-01 — PARITY-07 vacuous closure)", () => {
        // @ts-expect-error — PreviousBills must NOT be a key of BillsStackParamList
        const _shouldFailToCompile: keyof import("../../src/navigation/types").BillsStackParamList = "PreviousBills";
        void _shouldFailToCompile;

        // And at run time: the screen file is gone from disk.
        expect(() => require("../../src/screens/PreviousBillsScreen")).toThrow();
    });

    test("useDeepLinkRouter navigates directly to top-level Bills and Legislators tabs", () => {
        let capturedListener: ((res: any) => void) | undefined;
        (Notifications.addNotificationResponseReceivedListener as jest.Mock).mockImplementation((cb) => {
            capturedListener = cb;
            return { remove: jest.fn() };
        });

        const navigate = jest.fn();
        const navRef = { current: { navigate } as any };
        renderHook(() => useDeepLinkRouter(navRef));

        expect(capturedListener).toBeDefined();
        capturedListener!({
            notification: { request: { content: { data: { bill_id: "42" } } } },
        });
        expect(navigate).toHaveBeenCalledWith("Bills", {
            screen: "BillDetail",
            params: { id: 42 },
        });

        navigate.mockClear();
        capturedListener!({
            notification: { request: { content: { data: { legislator_id: "9" } } } },
        });
        expect(navigate).toHaveBeenCalledWith("Legislators", {
            screen: "LegislatorDetail",
            params: { id: 9 },
        });
    });
});

describe.each(["Home", "Bills"] as const)(
    "bill deep links in the %s stack resolve the id before the bill is requested",
    (stack) => {
        type StateLike = { routes?: { name: string; params?: Record<string, unknown>; state?: StateLike }[] };

        const billDetailParams = (path: string): Record<string, unknown> | undefined => {
            const screens = (linking.config as { screens: Record<string, unknown> }).screens;
            const find = (state: StateLike | undefined): Record<string, unknown> | undefined => {
                for (const route of state?.routes ?? []) {
                    if (route.name === "BillDetail") return route.params;
                    const found = find(route.state);
                    if (found) return found;
                }
                return undefined;
            };
            const state = getStateFromPath(path, { screens: { [stack]: screens[stack] } } as typeof linking.config);
            return find(state as StateLike);
        };

        const renderBillDetail = (params: Record<string, unknown> | undefined) =>
            render(
                <ThemeProvider initialMode="light">
                    <BillDetailScreen route={{ params: params as { id: number } }} />
                </ThemeProvider>,
            );

        beforeEach(() => {
            mockGet.mockReset();
            mockGet.mockReturnValue(new Promise(() => {}));
        });

        test.each(["..%2Fsomething", "1.5", "Infinity", "-7"])(
            "id %s never requests a path other than /bills/<integer>",
            (segment) => {
                renderBillDetail(billDetailParams(`bills/${segment}`));

                const requested = mockGet.mock.calls.map(([path]) => String(path).split("?")[0]);
                expect(requested.filter((path) => !/^\/bills\/\d+$/.test(path))).toEqual([]);
                expect(screen.getByTestId("bill-detail-error")).toBeTruthy();
            },
        );

        test("a valid integer id opens that bill as a number", () => {
            const params = billDetailParams("bills/42");
            expect(params).toEqual({ id: 42 });

            renderBillDetail(params);

            expect(mockGet.mock.calls[0][0]).toBe("/bills/42?with=legislator");
            expect(screen.getByTestId("bill-detail-skeleton")).toBeTruthy();
        });
    },
);

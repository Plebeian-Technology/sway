import React from "react";
import { Linking } from "react-native";
import { createNavigationContainerRef, NavigationContainer } from "@react-navigation/native";
import { act, render, screen, waitFor } from "@testing-library/react-native";

const mockUseSession = jest.fn();
const mockUseUserProfile = jest.fn();

jest.mock("../../src/hooks/useSession", () => ({ useSession: () => mockUseSession() }));
jest.mock("../../src/hooks/useUserProfile", () => ({ useUserProfile: () => mockUseUserProfile() }));

function mockScreen(testID: string) {
    const { View } = require("react-native");
    return () => <View testID={testID} />;
}

jest.mock("../../src/screens/AuthScreen", () => mockScreen("auth-screen"));
jest.mock("../../src/screens/DeviceUnsupportedScreen", () => mockScreen("device-unsupported-screen"));
jest.mock("../../src/screens/AddressScreen", () => mockScreen("address-screen"));
jest.mock("../../src/screens/FeedScreen", () => mockScreen("feed-screen"));
jest.mock("../../src/screens/BillOfTheMonthScreen", () => mockScreen("bill-of-the-month-screen"));
jest.mock("../../src/screens/BillDetailScreen", () => mockScreen("bill-detail-screen"));
jest.mock("../../src/screens/BillsListScreen", () => mockScreen("bills-list-screen"));
jest.mock("../../src/screens/LegislatorsListScreen", () => mockScreen("legislators-list-screen"));
jest.mock("../../src/screens/LegislatorDetailScreen", () => mockScreen("legislator-detail-screen"));
jest.mock("../../src/screens/OrgsListScreen", () => mockScreen("orgs-list-screen"));
jest.mock("../../src/screens/OrgDetailScreen", () => mockScreen("org-detail-screen"));
jest.mock("../../src/screens/ProfileScreen", () => mockScreen("profile-screen"));
jest.mock("../../src/screens/NotificationPrefsScreen", () => mockScreen("notification-prefs-screen"));
jest.mock("../../src/screens/PasskeyManagementScreen", () => mockScreen("passkey-management-screen"));
jest.mock("../../src/screens/DeleteAccountScreen", () => mockScreen("delete-account-screen"));
jest.mock("../../src/screens/MembershipsListScreen", () => mockScreen("memberships-list-screen"));
jest.mock("../../src/screens/MembershipDetailScreen", () => mockScreen("membership-detail-screen"));

import RootNavigator from "../../src/navigation/RootNavigator";
import { linking } from "../../src/navigation/linking";
import type { RootParamList } from "../../src/navigation/types";
import { inviteAttribution } from "../../src/state/inviteAttribution";

const BILL_LINK = "https://sway.vote/bills/12";

// @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#A link that arrives before the main screens is kept]]
describe("a link received before the main screens", () => {
    const urlListeners = new Set<(event: { url: string }) => void>();
    const navRef = createNavigationContainerRef<RootParamList>();

    const app = () => (
        <NavigationContainer ref={navRef} linking={linking}>
            <RootNavigator />
        </NavigationContainer>
    );

    const signedOut = () => {
        mockUseSession.mockReturnValue({ isAuthenticated: false, loading: false });
        mockUseUserProfile.mockReturnValue({ user: null, loading: false });
    };

    const signedIn = (isRegistrationComplete: boolean) => {
        mockUseSession.mockReturnValue({ isAuthenticated: true, loading: false });
        mockUseUserProfile.mockReturnValue({
            user: { id: 1, is_registration_complete: isRegistrationComplete },
            loading: false,
        });
    };

    const receiveLink = (url: string) => act(() => urlListeners.forEach((listener) => listener({ url })));

    const expectBillDetail = () =>
        waitFor(() =>
            expect(navRef.current?.getCurrentRoute()).toEqual(
                expect.objectContaining({ name: "BillDetail", params: { id: 12 } }),
            ),
        );

    beforeEach(() => {
        urlListeners.clear();
        jest.spyOn(Linking, "getInitialURL").mockResolvedValue(null);
        jest.spyOn(Linking, "addEventListener").mockImplementation(((_event: string, listener: never) => {
            urlListeners.add(listener);
            return { remove: () => urlListeners.delete(listener) };
        }) as never);
        signedOut();
    });

    afterEach(() => {
        jest.restoreAllMocks();
    });

    it("opens the link that launched the app once the person has signed in", async () => {
        jest.spyOn(Linking, "getInitialURL").mockResolvedValue(BILL_LINK);
        const { rerender } = render(app());
        await screen.findByTestId("auth-screen");

        signedIn(true);
        rerender(app());

        await expectBillDetail();
    });

    it("opens a link received while signed out once the person has signed in", async () => {
        const { rerender } = render(app());
        await screen.findByTestId("auth-screen");
        receiveLink(BILL_LINK);

        signedIn(true);
        rerender(app());

        await expectBillDetail();
    });

    it("opens a link received during onboarding once registration is complete", async () => {
        signedIn(false);
        const { rerender } = render(app());
        await screen.findByTestId("address-screen");
        receiveLink(BILL_LINK);

        signedIn(true);
        rerender(app());

        await expectBillDetail();
    });

    it("opens a link at once when the main screens are already showing", async () => {
        signedIn(true);
        render(app());
        await waitFor(() => expect(navRef.current?.getCurrentRoute()).toBeDefined());

        receiveLink(BILL_LINK);

        await expectBillDetail();
    });

    it("discards the kept link when the person signs out before finishing", async () => {
        signedIn(false);
        const { rerender } = render(app());
        await screen.findByTestId("address-screen");
        receiveLink(BILL_LINK);

        signedOut();
        rerender(app());
        await screen.findByTestId("auth-screen");

        signedIn(true);
        rerender(app());

        await waitFor(() => expect(navRef.current?.getCurrentRoute()).toBeDefined());
        expect(navRef.current?.getCurrentRoute()?.name).not.toBe("BillDetail");
    });

    // @lat: [[well-known-controller-notes#Mobile: linking.ts#Invite links store a key and open no screen]]
    it("does not keep an invite link, so its key is not stored again after registration used it", async () => {
        const { rerender } = render(app());
        await screen.findByTestId("auth-screen");
        receiveLink("https://sway.vote/s/abc123");
        expect(inviteAttribution.get()).toBe("s:abc123");
        inviteAttribution.clear();

        signedIn(true);
        rerender(app());

        await waitFor(() => expect(navRef.current?.getCurrentRoute()).toBeDefined());
        expect(inviteAttribution.get()).toBeNull();
    });

    // @lat: [[mobile-auth-and-onboarding-flow#RootNavigator#Signing out forgets the stored invite]]
    describe("the stored invite key", () => {
        afterEach(() => {
            inviteAttribution.clear();
        });

        it("is forgotten when the person signs out, so the next person to register is not credited to that inviter", async () => {
            signedIn(true);
            const { rerender } = render(app());
            await waitFor(() => expect(navRef.current?.getCurrentRoute()).toBeDefined());
            receiveLink("https://sway.vote/s/abc123");
            expect(inviteAttribution.get()).toBe("s:abc123");

            signedOut();
            rerender(app());
            await screen.findByTestId("auth-screen");

            expect(inviteAttribution.get()).toBeNull();
        });

        it("is kept when the app starts signed out, so a launch invite link still credits its inviter", async () => {
            inviteAttribution.set("s:abc123");

            render(app());
            await screen.findByTestId("auth-screen");

            expect(inviteAttribution.get()).toBe("s:abc123");
        });
    });
});

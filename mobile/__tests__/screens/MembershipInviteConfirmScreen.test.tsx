const mockReplace = jest.fn();
const mockNavigation = { replace: mockReplace };

jest.mock("../../src/api/client", () => ({ apiClient: { get: jest.fn(), post: jest.fn() } }));

jest.mock("@react-navigation/native", () => ({
    ...jest.requireActual("@react-navigation/native"),
    useNavigation: () => mockNavigation,
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

jest.mock("../../src/components/SkeletonCard", () => {
    const { View } = require("react-native");
    return { SkeletonCard: () => <View testID="skeleton-card" /> };
});

import React from "react";
import { act, fireEvent, render, screen } from "@testing-library/react-native";

import MembershipInviteConfirmScreen from "../../src/screens/MembershipInviteConfirmScreen";
import { apiClient } from "../../src/api/client";
import { ApiRequestError } from "../../src/api/errors";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const mockGet = apiClient.get as jest.Mock;
const mockPost = apiClient.post as jest.Mock;

const TOKEN = "signed token/with=chars";
const ENCODED_TOKEN = encodeURIComponent(TOKEN);
const confirmation = {
    signed_token: TOKEN,
    organization: { id: 5, name: "Baltimore Bike Coalition" },
    inviter_name: "Ada Admin",
    expires_at: "2026-12-01T00:00:00Z",
};

const open = (params: { orgId?: number; token?: string } = { orgId: 5, token: TOKEN }) =>
    render(
        <ThemeProvider initialMode="light">
            <MembershipInviteConfirmScreen route={{ params }} />
        </ThemeProvider>,
    );

const pressAccept = () =>
    act(async () => {
        fireEvent.press(screen.getByTestId("invite-confirm-accept"));
    });

// @lat: [[membership-invite-accept-flow#Mobile: MembershipInviteConfirmScreen, the confirm step for an emailed link]]
describe("MembershipInviteConfirmScreen", () => {
    beforeEach(() => {
        mockGet.mockReset();
        mockPost.mockReset();
        mockReplace.mockReset();
    });

    it("shows the organization, the inviter and the accept button", async () => {
        mockGet.mockResolvedValue(confirmation);

        open();

        expect(await screen.findByText("Accept invitation to Baltimore Bike Coalition")).toBeTruthy();
        expect(screen.getByText("Invited by Ada Admin")).toBeTruthy();
        expect(screen.getByText(PARITY_COPY.memberships.acceptLabel)).toBeTruthy();
        expect(mockGet).toHaveBeenCalledWith(`/organizations/5/membership_invites/${ENCODED_TOKEN}/confirm_accept`);
    });

    it("accepts with the encoded token and lands on the memberships list", async () => {
        mockGet.mockResolvedValue(confirmation);
        mockPost.mockResolvedValue({ ok: true });
        open();
        await screen.findByTestId("invite-confirm-accept");

        await pressAccept();

        expect(mockPost).toHaveBeenCalledWith(`/organizations/5/membership_invites/${ENCODED_TOKEN}/accept`, undefined);
        expect(mockReplace).toHaveBeenCalledWith("MembershipsList");
    });

    it("shows the server's message when the invitation cannot be confirmed", async () => {
        mockGet.mockRejectedValue(new ApiRequestError("http_410", "Invitation expired.", undefined, 410));

        open();

        expect(await screen.findByText("Invitation expired.")).toBeTruthy();
        expect(screen.queryByTestId("invite-confirm-accept")).toBeNull();
    });

    it("shows the server's message and keeps the button usable when accepting fails", async () => {
        mockGet.mockResolvedValue(confirmation);
        mockPost.mockRejectedValueOnce(
            new ApiRequestError("http_422", "This invitation is no longer valid.", undefined, 422),
        );
        mockPost.mockResolvedValueOnce({ ok: true });
        open();
        await screen.findByTestId("invite-confirm-accept");

        await pressAccept();

        expect(screen.getByText("This invitation is no longer valid.")).toBeTruthy();
        expect(mockReplace).not.toHaveBeenCalled();

        await pressAccept();

        expect(mockReplace).toHaveBeenCalledWith("MembershipsList");
    });

    it.each([{ orgId: Number.NaN, token: TOKEN }, { orgId: 5 }, {}])(
        "shows 'Invitation not found.' without calling the server for the link values %p",
        (params) => {
            open(params);

            expect(screen.getByText("Invitation not found.")).toBeTruthy();
            expect(mockGet).not.toHaveBeenCalled();
        },
    );
});

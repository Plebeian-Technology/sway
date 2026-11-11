// @lat: [[mobile-jest-first-pass-test-notes#MembershipCard.test.tsx / MembershipsListScreen.test.tsx]]

import React from "react";
import { render, fireEvent } from "@testing-library/react-native";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { MembershipCard } from "../../src/components/MembershipCard";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const ACTIVE_MEMBERSHIP = {
    id: 7,
    role: "standard" as const,
    organization: {
        id: 2,
        name: "Baltimore Climate Action",
        member_count: 14,
    },
};

const PENDING_MEMBERSHIP = {
    id: 8,
    role: "standard" as const,
    organization: {
        id: 3,
        name: "Maryland Voters",
        member_count: 5,
    },
};

describe("MembershipCard", () => {
    test("renders org name", () => {
        const { getByText } = wrap(<MembershipCard membership={ACTIVE_MEMBERSHIP} variant="active" />);
        expect(getByText("Baltimore Climate Action")).toBeTruthy();
    });

    test("renders role badge text", () => {
        const { getByText } = wrap(
            <MembershipCard membership={{ ...ACTIVE_MEMBERSHIP, role: "admin" }} variant="active" />,
        );
        // The badge may be in capitals, so match without caring about case
        expect(getByText(/admin/i)).toBeTruthy();
    });

    test("renders member count", () => {
        const { getByText } = wrap(<MembershipCard membership={ACTIVE_MEMBERSHIP} variant="active" />);
        expect(getByText(/14/)).toBeTruthy();
    });

    test("active variant calls onPress when pressed", () => {
        const onPress = jest.fn();
        const { getByTestId } = wrap(
            <MembershipCard membership={ACTIVE_MEMBERSHIP} variant="active" onPress={onPress} />,
        );
        fireEvent.press(getByTestId(`membership-card-${ACTIVE_MEMBERSHIP.id}`));
        expect(onPress).toHaveBeenCalled();
    });

    test("pending variant renders Accept and Decline buttons", () => {
        const { getByText } = wrap(<MembershipCard membership={PENDING_MEMBERSHIP} variant="pending" />);
        // Accept and Decline should both be on screen; what they do is wired up elsewhere
        expect(getByText(/accept/i)).toBeTruthy();
        expect(getByText(/decline/i)).toBeTruthy();
    });

    test("has testID=membership-card-{id}", () => {
        const { getByTestId } = wrap(<MembershipCard membership={ACTIVE_MEMBERSHIP} variant="active" />);
        expect(getByTestId("membership-card-7")).toBeTruthy();
    });
});

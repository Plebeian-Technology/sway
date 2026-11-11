// DestructiveSheet — the "are you sure" sheet shown before an action that cannot be undone.
import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

import { DestructiveSheet } from "../../src/components/DestructiveSheet";

describe("DestructiveSheet", () => {
    test("renders the title, body, and actionLabel verbatim", () => {
        render(
            <DestructiveSheet
                visible
                title="Delete account"
                body="This permanently removes your votes, profile, and history. This cannot be undone."
                actionLabel="Delete Account"
                onConfirm={jest.fn()}
                onDismiss={jest.fn()}
            />,
        );
        expect(screen.getByTestId("destructive-sheet-title")).toHaveTextContent("Delete account");
        expect(screen.getByTestId("destructive-sheet-body")).toHaveTextContent(
            "This permanently removes your votes, profile, and history. This cannot be undone.",
        );
        expect(screen.getByLabelText("Delete Account")).toBeTruthy();
    });

    test("confirm button fires onConfirm", () => {
        const onConfirm = jest.fn();
        render(
            <DestructiveSheet
                visible
                title="Sign out all devices"
                body="You'll be signed out on every device."
                actionLabel="Sign Out All Devices"
                onConfirm={onConfirm}
                onDismiss={jest.fn()}
            />,
        );
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));
        expect(onConfirm).toHaveBeenCalledTimes(1);
    });

    test("cancel link fires onDismiss", () => {
        const onDismiss = jest.fn();
        render(
            <DestructiveSheet
                visible
                title="Remove passkey"
                body="You'll need your phone number to sign back in."
                actionLabel="Remove Passkey"
                onConfirm={jest.fn()}
                onDismiss={onDismiss}
            />,
        );
        fireEvent.press(screen.getByTestId("btn-destructive-cancel"));
        expect(onDismiss).toHaveBeenCalledTimes(1);
    });

    test("busy=true prevents the confirm button from invoking onConfirm", () => {
        const onConfirm = jest.fn();
        render(
            <DestructiveSheet
                visible
                title="Delete account"
                body="…"
                actionLabel="Delete Account"
                busy
                onConfirm={onConfirm}
                onDismiss={jest.fn()}
            />,
        );
        fireEvent.press(screen.getByTestId("btn-destructive-confirm"));
        expect(onConfirm).not.toHaveBeenCalled();
    });
});

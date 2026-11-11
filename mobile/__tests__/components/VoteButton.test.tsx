import React from "react";
import { fireEvent, render, screen } from "@testing-library/react-native";

// @lat: [[user-vote-submission#Mobile vote controls]]
const mockImpactAsync = jest.fn(async (..._args: unknown[]) => {});
jest.mock("expo-haptics", () => ({
    impactAsync: (...args: unknown[]) => mockImpactAsync(...args),
    ImpactFeedbackStyle: { Light: "Light", Medium: "Medium", Heavy: "Heavy" },
}));

import { VoteButton } from "../../src/components/VoteButton";
import { VotePanel } from "../../src/components/VotePanel";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => ({ isAuthenticated: true, loading: false, signOut: jest.fn(), signOutAll: jest.fn() }),
}));

jest.mock("../../src/hooks/useCastUserVote", () => ({
    useCastUserVote: () => ({ submit: jest.fn(), isOnline: true, pending: false }),
}));

jest.mock("../../src/cache/voteCache", () => ({
    get: jest.fn(async () => null),
    set: jest.fn(async () => {}),
}));

describe("VoteButton", () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    test("triggers Haptics.impactAsync(Light) before invoking onPress (D-39)", async () => {
        const onPress = jest.fn();
        render(<VoteButton userVote={null} onPress={onPress} billTitle="HB 1234" label="For" />);
        const button = screen.getByRole("button", { name: /vote for HB 1234/i });
        await fireEvent.press(button);
        expect(mockImpactAsync).toHaveBeenCalledWith("Light");
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test("casts the vote in the same tick, without waiting for the haptic", () => {
        const onPress = jest.fn();
        mockImpactAsync.mockImplementationOnce(() => new Promise<void>(() => {}));
        render(<VoteButton userVote={null} onPress={onPress} billTitle="HB 1234" label="For" />);
        fireEvent.press(screen.getByLabelText("Vote for HB 1234"));
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test("still casts the vote when the haptic engine rejects", async () => {
        const onPress = jest.fn();
        mockImpactAsync.mockRejectedValueOnce(new Error("haptics unavailable"));
        render(<VoteButton userVote={null} onPress={onPress} billTitle="HB 1234" label="For" />);
        fireEvent.press(screen.getByLabelText("Vote for HB 1234"));
        await new Promise((resolve) => setImmediate(resolve));
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test("still casts the vote when the haptic call throws", () => {
        const onPress = jest.fn();
        mockImpactAsync.mockImplementationOnce(() => {
            throw new Error("haptics unavailable");
        });
        render(<VoteButton userVote={null} onPress={onPress} billTitle="HB 1234" label="Against" />);
        fireEvent.press(screen.getByLabelText("Vote against HB 1234"));
        expect(onPress).toHaveBeenCalledTimes(1);
    });

    test.each(["For", "Against"] as const)(
        "%s label caps text scaling and shrinks to one line instead of breaking mid-word",
        (label) => {
            render(<VoteButton userVote={null} onPress={() => {}} billTitle="HB 1" label={label} />);
            const props = screen.getByText(label).props;
            expect(props.maxFontSizeMultiplier).toBe(1.3);
            expect(props.numberOfLines).toBe(1);
            expect(props.adjustsFontSizeToFit).toBe(true);
        },
    );

    test('renders accessibilityLabel "Vote for {bill}" when label="For"', () => {
        render(<VoteButton userVote={null} onPress={() => {}} billTitle="HB 1234" label="For" />);
        expect(screen.getByLabelText("Vote for HB 1234")).toBeTruthy();
    });

    test('renders accessibilityLabel "Vote against {bill}" when label="Against"', () => {
        render(<VoteButton userVote={null} onPress={() => {}} billTitle="HB 9000" label="Against" />);
        expect(screen.getByLabelText("Vote against HB 9000")).toBeTruthy();
    });

    test("does not call onPress when disabled", async () => {
        const onPress = jest.fn();
        render(<VoteButton userVote={null} onPress={onPress} disabled billTitle="HB 1" label="For" />);
        const button = screen.getByLabelText("Vote for HB 1");
        await fireEvent.press(button);
        expect(onPress).not.toHaveBeenCalled();
        expect(mockImpactAsync).not.toHaveBeenCalled();
    });

    test("marks accessibilityState.selected=true when userVote matches the button label", () => {
        render(<VoteButton userVote="for" onPress={() => {}} billTitle="HB 1" label="For" />);
        const button = screen.getByLabelText("Vote for HB 1");
        expect(button.props.accessibilityState).toEqual(expect.objectContaining({ selected: true }));
    });

    test("does not claim a generic disabled button is offline", () => {
        render(<VoteButton userVote={null} onPress={() => {}} disabled billTitle="HB 1" label="For" />);
        expect(screen.getByLabelText("Vote for HB 1").props.accessibilityHint).toBeUndefined();
    });

    test("uses the caller's explicit offline reason when no vote is recorded", () => {
        render(
            <VoteButton
                userVote={null}
                onPress={() => {}}
                disabled
                disabledHint="You're offline — votes require a connection."
                billTitle="HB 1"
                label="For"
            />,
        );
        expect(screen.getByLabelText("Vote for HB 1").props.accessibilityHint).toBe(
            "You're offline — votes require a connection.",
        );
    });

    test.each(["For", "Against"] as const)("explains the recorded vote on the %s button, even offline", (label) => {
        render(
            <VoteButton
                userVote="for"
                onPress={() => {}}
                disabled
                disabledHint="You're offline — votes require a connection."
                billTitle="HB 1"
                label={label}
            />,
        );
        expect(screen.getByLabelText(`Vote ${label.toLowerCase()} HB 1`).props.accessibilityHint).toBe(
            "Your vote has already been recorded.",
        );
    });

    test("VotePanel resets userVote to null when switching from a voted bill to an unvoted bill", () => {
        const { rerender } = render(
            <ThemeProvider initialMode="light">
                <VotePanel bill={{ id: 1, title: "HB 1" }} user_vote={{ support: "for" }} />
            </ThemeProvider>,
        );
        expect(screen.getByTestId("vote-panel-for").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: true, disabled: true }),
        );

        rerender(
            <ThemeProvider initialMode="light">
                <VotePanel bill={{ id: 2, title: "HB 2" }} user_vote={null} />
            </ThemeProvider>,
        );
        expect(screen.getByTestId("vote-panel-for").props.accessibilityState).toEqual(
            expect.objectContaining({ selected: false, disabled: false }),
        );
    });
});

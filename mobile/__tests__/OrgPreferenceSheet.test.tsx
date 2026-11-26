// ── Fake modules. These have to be declared before the imports ───────────────

jest.mock("../src/theme/ThemeProvider", () => ({
    useTheme: () => ({ colorScheme: "light" }),
    ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

// @lat: [[mobile-organization-follow-test-notes#OrgPreferenceSheet.test.tsx and OrgCard]]
const mockPost = jest.fn();
const mockGet = jest.fn();
const mockPatch = jest.fn();
const mockDelete = jest.fn();

jest.mock("../src/api/client", () => ({
    apiClient: {
        get: (...args: unknown[]) => mockGet(...args),
        post: (...args: unknown[]) => mockPost(...args),
        patch: (...args: unknown[]) => mockPatch(...args),
        delete: (...args: unknown[]) => mockDelete(...args),
    },
}));

import React from "react";
import { fireEvent, render, screen, act } from "@testing-library/react-native";
import { ThemeProvider } from "../src/theme/ThemeProvider";
import { OrgPreferenceSheet } from "../src/components/OrgPreferenceSheet";
import { OrgCard } from "../src/components/OrgCard";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const BASE_ORG = {
    id: 7,
    name: "Civic Alliance",
    sway_locale_slug: "baltimore-maryland-united_states",
};

describe("OrgPreferenceSheet", () => {
    beforeEach(() => {
        mockPatch.mockReset();
        mockPost.mockReset();
        mockGet.mockReset();
        mockDelete.mockReset();
    });

    test("renders title 'Notification preferences'", () => {
        wrap(<OrgPreferenceSheet visible={true} orgName="Civic Alliance" onSave={jest.fn()} onClose={jest.fn()} />);
        expect(screen.getByTestId("org-pref-sheet-title")).toBeTruthy();
        expect(screen.getByText("Notification preferences")).toBeTruthy();
    });

    test("renders subtitle with org name", () => {
        wrap(<OrgPreferenceSheet visible={true} orgName="Civic Alliance" onSave={jest.fn()} onClose={jest.fn()} />);
        expect(screen.getByText("Choose what you hear about from Civic Alliance.")).toBeTruthy();
    });

    test("renders all 3 PreferenceToggle rows (new position, support change, summary update)", () => {
        wrap(<OrgPreferenceSheet visible={true} orgName="Civic Alliance" onSave={jest.fn()} onClose={jest.fn()} />);
        expect(screen.getByTestId("pref-toggle-new-position")).toBeTruthy();
        expect(screen.getByTestId("pref-toggle-support-change")).toBeTruthy();
        expect(screen.getByTestId("pref-toggle-summary-change")).toBeTruthy();
    });

    test("describes every event as Sway recording it, never the organization acting", () => {
        wrap(<OrgPreferenceSheet visible={true} orgName="Civic Alliance" onSave={jest.fn()} onClose={jest.fn()} />);
        expect(
            screen.getByText("When Sway records a change in this organization's for/against position."),
        ).toBeTruthy();
        expect(screen.getByText("When Sway records a change to this organization's position summary.")).toBeTruthy();
        expect(screen.queryByText(/this org (changes|updates)/)).toBeNull();
    });

    test("renders cadence picker with all 3 options", () => {
        wrap(<OrgPreferenceSheet visible={true} orgName="Civic Alliance" onSave={jest.fn()} onClose={jest.fn()} />);
        expect(screen.getByTestId("cadence-picker")).toBeTruthy();
        expect(screen.getByTestId("cadence-every_change")).toBeTruthy();
        expect(screen.getByTestId("cadence-daily")).toBeTruthy();
        expect(screen.getByTestId("cadence-weekly")).toBeTruthy();
    });

    test("renders Save button", () => {
        wrap(<OrgPreferenceSheet visible={true} orgName="Civic Alliance" onSave={jest.fn()} onClose={jest.fn()} />);
        expect(screen.getByTestId("org-pref-sheet-save")).toBeTruthy();
        expect(screen.getByText("Save preferences")).toBeTruthy();
    });

    test("Save calls onSave with current prefs and closes", async () => {
        const onSave = jest.fn().mockResolvedValue(undefined);
        const onClose = jest.fn();
        wrap(
            <OrgPreferenceSheet
                visible={true}
                orgName="Civic Alliance"
                onSave={onSave}
                onClose={onClose}
                initialPrefs={{
                    notify_on_new_position: true,
                    notify_on_support_change: false,
                    notify_on_summary_change: true,
                    notification_cadence: "daily",
                }}
            />,
        );
        await act(async () => {
            fireEvent.press(screen.getByTestId("org-pref-sheet-save"));
        });
        expect(onSave).toHaveBeenCalledWith({
            notify_on_new_position: true,
            notify_on_support_change: false,
            notify_on_summary_change: true,
            notification_cadence: "daily",
        });
        expect(onClose).toHaveBeenCalled();
    });

    test("does NOT render 'Skip for now' when isFirstFollow is false (default)", () => {
        wrap(
            <OrgPreferenceSheet
                visible={true}
                orgName="Civic Alliance"
                isFirstFollow={false}
                onSave={jest.fn()}
                onClose={jest.fn()}
            />,
        );
        expect(screen.queryByTestId("org-pref-sheet-skip")).toBeNull();
    });

    test("renders 'Skip for now' when isFirstFollow is true", () => {
        wrap(
            <OrgPreferenceSheet
                visible={true}
                orgName="Civic Alliance"
                isFirstFollow={true}
                onSave={jest.fn()}
                onClose={jest.fn()}
            />,
        );
        expect(screen.getByTestId("org-pref-sheet-skip")).toBeTruthy();
        expect(screen.getByText("Skip for now")).toBeTruthy();
    });

    test("Skip for now calls onClose without saving", async () => {
        const onSave = jest.fn();
        const onClose = jest.fn();
        wrap(
            <OrgPreferenceSheet
                visible={true}
                orgName="Civic Alliance"
                isFirstFollow={true}
                onSave={onSave}
                onClose={onClose}
            />,
        );
        fireEvent.press(screen.getByTestId("org-pref-sheet-skip"));
        expect(onClose).toHaveBeenCalled();
        expect(onSave).not.toHaveBeenCalled();
    });

    test("shows error copy on save failure", async () => {
        const onSave = jest.fn().mockRejectedValue(new Error("network error"));
        wrap(<OrgPreferenceSheet visible={true} orgName="Civic Alliance" onSave={onSave} onClose={jest.fn()} />);
        await act(async () => {
            fireEvent.press(screen.getByTestId("org-pref-sheet-save"));
        });
        expect(screen.getByTestId("org-pref-sheet-error")).toBeTruthy();
        expect(screen.getByText("Couldn't save preferences. Try again.")).toBeTruthy();
    });
});

describe("OrgCard follow control", () => {
    beforeEach(() => {
        mockPatch.mockReset();
        mockPost.mockReset();
        mockGet.mockReset();
        mockDelete.mockReset();
    });

    // The member state is driven by isMember alone, never by followId.
    test("member (isMember=true) renders 'Member' label and Preferences CTA — no Track/Untrack", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={jest.fn()} isSignedIn={true} isMember={true} initialFollowId={123} />);
        expect(screen.getByTestId(`org-card-member-label-${BASE_ORG.id}`)).toBeTruthy();
        expect(screen.getByText("Member")).toBeTruthy();
        expect(screen.getByTestId(`org-card-preferences-${BASE_ORG.id}`)).toBeTruthy();
        expect(screen.queryByTestId(`org-card-follow-btn-${BASE_ORG.id}`)).toBeNull();
        expect(screen.queryByTestId(`org-card-following-btn-${BASE_ORG.id}`)).toBeNull();
    });

    test("member with no followId (D-05) still renders 'Member' state — no Untrack", () => {
        wrap(
            <OrgCard
                org={BASE_ORG}
                onPress={jest.fn()}
                isSignedIn={true}
                isMember={true}
                initialFollowId={null} // not following, but is a member
            />,
        );
        expect(screen.getByText("Member")).toBeTruthy();
        expect(screen.getByTestId(`org-card-preferences-${BASE_ORG.id}`)).toBeTruthy();
        expect(screen.queryByTestId(`org-card-follow-btn-${BASE_ORG.id}`)).toBeNull();
        expect(screen.queryByTestId(`org-card-following-btn-${BASE_ORG.id}`)).toBeNull();
    });

    test("signed-out track tap shows AuthPromptSheet with 'Sign in to track' heading", async () => {
        wrap(<OrgCard org={BASE_ORG} onPress={jest.fn()} isSignedIn={false} isMember={false} initialFollowId={null} />);
        // @lat: [[mobile-organization-follow-test-notes#OrgPreferenceSheet.test.tsx and OrgCard]]
        expect(screen.getByTestId(`org-card-follow-btn-${BASE_ORG.id}`)).toBeTruthy();
        await act(async () => {
            fireEvent.press(screen.getByTestId(`org-card-follow-btn-${BASE_ORG.id}`));
        });
        expect(screen.getByText("Sign in to track")).toBeTruthy();
    });

    test("tracking non-member shows 'Tracking' button (not Member)", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={jest.fn()} isSignedIn={true} isMember={false} initialFollowId={456} />);
        expect(screen.getByTestId(`org-card-following-btn-${BASE_ORG.id}`)).toBeTruthy();
        expect(screen.getByText("Tracking")).toBeTruthy();
        expect(screen.queryByTestId(`org-card-follow-btn-${BASE_ORG.id}`)).toBeNull();
    });

    test("not-tracking signed-in shows 'Track' CTA", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={jest.fn()} isSignedIn={true} isMember={false} initialFollowId={null} />);
        expect(screen.getByTestId(`org-card-follow-btn-${BASE_ORG.id}`)).toBeTruthy();
        expect(screen.getByText("Track")).toBeTruthy();
    });

    test("renders no follower count", () => {
        wrap(<OrgCard org={BASE_ORG} onPress={jest.fn()} isSignedIn={false} />);
        expect(screen.queryByTestId(`org-card-follower-count-${BASE_ORG.id}`)).toBeNull();
        expect(screen.queryByText(/follower/)).toBeNull();
    });

    // The prompt sheet gets track-specific wording here, not its usual voting wording.
    test("AuthPromptSheet receives heading='Sign in to track' and correct body (D-11)", async () => {
        wrap(<OrgCard org={BASE_ORG} onPress={jest.fn()} isSignedIn={false} />);
        await act(async () => {
            fireEvent.press(screen.getByTestId(`org-card-follow-btn-${BASE_ORG.id}`));
        });
        // Heading is replaced: "Sign in to track", not the usual "Sign in to vote"
        expect(screen.getByText("Sign in to track")).toBeTruthy();
        expect(
            screen.getByText(
                "Track civic organizations and get notified when Sway records their positions on legislation.",
            ),
        ).toBeTruthy();
    });

    test("AuthPromptSheet 'Sign in' calls onRequestSignIn and closes sheet (WR-16)", async () => {
        const onRequestSignIn = jest.fn();
        wrap(<OrgCard org={BASE_ORG} onPress={jest.fn()} isSignedIn={false} onRequestSignIn={onRequestSignIn} />);
        await act(async () => {
            fireEvent.press(screen.getByTestId(`org-card-follow-btn-${BASE_ORG.id}`));
        });
        expect(screen.getByText("Sign in to track")).toBeTruthy();

        await act(async () => {
            fireEvent.press(screen.getByTestId("btn-auth-prompt-sign-in"));
        });
        expect(onRequestSignIn).toHaveBeenCalledTimes(1);
    });

    test("AuthPromptSheet 'Continue browsing' dismisses without calling onRequestSignIn (WR-16)", async () => {
        const onRequestSignIn = jest.fn();
        wrap(<OrgCard org={BASE_ORG} onPress={jest.fn()} isSignedIn={false} onRequestSignIn={onRequestSignIn} />);
        await act(async () => {
            fireEvent.press(screen.getByTestId(`org-card-follow-btn-${BASE_ORG.id}`));
        });
        await act(async () => {
            fireEvent.press(screen.getByTestId("btn-auth-prompt-continue-browsing"));
        });
        expect(onRequestSignIn).not.toHaveBeenCalled();
    });

    test("OrgPreferenceSheet seeded from initialPrefs when org has a follow row (CR-05)", async () => {
        const onSave = jest.fn().mockResolvedValue(undefined);
        // Pass settings that differ from the everything-on defaults
        wrap(
            <OrgPreferenceSheet
                visible={true}
                orgName="Civic Alliance"
                onSave={onSave}
                onClose={jest.fn()}
                initialPrefs={{
                    notify_on_new_position: false,
                    notify_on_support_change: false,
                    notify_on_summary_change: true,
                    notification_cadence: "weekly",
                }}
            />,
        );
        // Save right away without touching a toggle — the saved values should match
        await act(async () => {
            fireEvent.press(screen.getByTestId("org-pref-sheet-save"));
        });
        expect(onSave).toHaveBeenCalledWith({
            notify_on_new_position: false,
            notify_on_support_change: false,
            notify_on_summary_change: true,
            notification_cadence: "weekly",
        });
    });
});

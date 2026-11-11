// AddressScreen.test.tsx does not check address suggestions or post-submit destination — see AddressScreen.parity.test.tsx.

const mockUseUserProfile = jest.fn();
const mockSignOut = jest.fn(async () => {});

jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => ({ isAuthenticated: true, loading: false, signOut: mockSignOut, signOutAll: jest.fn() }),
}));

jest.mock("../../src/hooks/useUserProfile", () => ({
    useUserProfile: () => mockUseUserProfile(),
}));

jest.mock("../../src/navigation/onboardingHandoff", () => ({
    onboardingHandoff: {
        setLandOnLegislators: jest.fn(),
        consumeLandOnLegislators: jest.fn(() => false),
    },
}));

jest.mock("../../src/api/client", () => ({
    apiClient: { post: jest.fn(async () => ({ ok: true })) },
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

jest.mock("expo-constants", () => ({
    expoConfig: {
        extra: {
            googlePlacesApiKeyIOS: "test-key",
            googlePlacesApiKeyAndroid: "test-key-android",
        },
    },
}));

let mockOnSelectAddress: ((parsed: Record<string, unknown>) => void) | null = null;

// Replace AddressAutocomplete so the native Google Places SDK is never loaded.
// `__esModule: true` tells jest to hand back `.default` for a default import,
// which is how AddressScreen writes `import AddressAutocomplete from ...`.
jest.mock("../../src/components/AddressAutocomplete", () => ({
    __esModule: true,
    default: ({ onSelect }: { onSelect: (parsed: Record<string, unknown>) => void }) => {
        mockOnSelectAddress = onSelect;
        return null;
    },
}));

jest.mock("react-native-google-places-sdk", () => ({
    default: {
        fetchPredictions: jest.fn(async () => []),
        fetchPlaceByID: jest.fn(async () => ({})),
        initialize: jest.fn(),
    },
    PLACE_FIELDS: {
        ADDRESS_COMPONENTS: "ADDRESS_COMPONENTS",
        FORMATTED_ADDRESS: "FORMATTED_ADDRESS",
        COORDINATE: "COORDINATE",
        TYPES: "TYPES",
    },
}));

const mockNavigation = {
    navigate: jest.fn(),
    goBack: jest.fn(),
    canGoBack: jest.fn(() => true),
};
jest.mock("@react-navigation/native", () => ({
    useNavigation: () => mockNavigation,
    useIsFocused: () => true,
}));

import React from "react";
import { act, render, fireEvent, screen, waitFor } from "@testing-library/react-native";
import { Linking } from "react-native";
import { apiClient } from "../../src/api/client";
import AddressScreen from "../../src/screens/AddressScreen";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const baseUser = {
    id: 1,
    is_registration_complete: false,
};

let openURLSpy: jest.SpyInstance;

beforeEach(() => {
    jest.clearAllMocks();
    openURLSpy = jest.spyOn(Linking, "openURL").mockResolvedValue(undefined);
});

afterEach(() => {
    openURLSpy.mockRestore();
});

describe("AddressScreen", () => {
    describe("onboarding mode (user.address absent)", () => {
        beforeEach(() => {
            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser, address: undefined },
                loading: false,
                refresh: jest.fn(),
            });
        });

        it("Test 1 — renders onboarding heading block + 'Find My Representatives' CTA", () => {
            wrap(<AddressScreen />);

            expect(screen.getByTestId("address-onboarding-heading")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.complete.heading)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.complete.lead)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.complete.cta)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.complete.cancelCta)).toBeTruthy();
        });

        it("Test 1b — cancel CTA ('Log Out') calls signOut() in onboarding mode", () => {
            wrap(<AddressScreen />);

            fireEvent.press(screen.getByTestId("address-cancel-cta"));
            expect(mockSignOut).toHaveBeenCalledTimes(1);
            expect(mockNavigation.goBack).not.toHaveBeenCalled();
        });

        it("keeps a saved address in onboarding while registration is incomplete", () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: false,
                    address: {
                        street1: "100 N Holliday St",
                        city: "Baltimore",
                        region_code: "MD",
                        postal_code: "21202",
                        country: "United States",
                    },
                },
                loading: false,
                refresh: jest.fn(),
            });

            wrap(<AddressScreen />);

            expect(screen.getByTestId("address-onboarding-heading")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.complete.cta)).toBeTruthy();
        });

        it("Test 2c — renders the voter-registration address confirmation, unticked by default", () => {
            wrap(<AddressScreen />);

            const toggle = screen.getByTestId("registered-voter-address-confirmation");
            expect(toggle).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.helper.registeredVoterConfirmation.label)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.helper.registeredVoterConfirmation.description)).toBeTruthy();

            const toggleSwitch = screen.getByTestId("pref-switch-registered-voter-address-confirmation");
            expect(toggleSwitch.props.value).toBe(false);
        });

        it("Test 3 — renders helper block with all 3 external link Pressables + advisory paragraph", () => {
            wrap(<AddressScreen />);

            expect(screen.getByTestId("address-helper-block")).toBeTruthy();
            expect(screen.getByTestId("address-register-to-vote")).toBeTruthy();
            expect(screen.getByTestId("address-check-registration")).toBeTruthy();
            expect(screen.getByTestId("address-view-github")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.helper.registeredVoterAdvisory)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.helper.viewOnGitHubIntro)).toBeTruthy();
        });

        it("Test 4 — each helper-block Pressable calls Linking.openURL with the canonical URL", () => {
            wrap(<AddressScreen />);

            fireEvent.press(screen.getByTestId("address-register-to-vote"));
            expect(openURLSpy).toHaveBeenCalledWith(PARITY_COPY.address.helper.registerToVoteUrl);

            fireEvent.press(screen.getByTestId("address-check-registration"));
            expect(openURLSpy).toHaveBeenCalledWith(PARITY_COPY.address.helper.checkRegistrationUrl);

            fireEvent.press(screen.getByTestId("address-view-github"));
            expect(openURLSpy).toHaveBeenCalledWith(PARITY_COPY.address.helper.viewOnGitHubUrl);
        });
    });

    describe("edit mode (user.address present)", () => {
        beforeEach(() => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: {
                        street1: "123 Main St",
                        city: "Baltimore",
                        region_code: "MD",
                        postal_code: "21201",
                        country: "United States",
                    },
                },
                loading: false,
                refresh: jest.fn(),
            });
        });

        it("Test 2 — does not render onboarding heading; uses 'Save address' / 'Cancel' CTAs and shared editLead", () => {
            wrap(<AddressScreen />);

            expect(screen.queryByTestId("address-onboarding-heading")).toBeNull();
            expect(screen.getByText(PARITY_COPY.address.switchConfirm.editLead)).toBeTruthy();
            expect(screen.queryByText(/your votes will be deleted/i)).toBeNull();
            expect(screen.getByText(PARITY_COPY.address.edit.saveCta)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.edit.cancelCta)).toBeTruthy();
        });

        it("Test 2b — cancel CTA calls nav.goBack() in edit mode, not signOut()", () => {
            wrap(<AddressScreen />);

            fireEvent.press(screen.getByTestId("address-cancel-cta"));
            expect(mockNavigation.goBack).toHaveBeenCalledTimes(1);
            expect(mockSignOut).not.toHaveBeenCalled();
        });

        it("shows shared switchConfirm card on submit, hides on cancel, and posts confirm_deactivate_legislators on confirm", async () => {
            wrap(<AddressScreen />);

            act(() => {
                mockOnSelectAddress?.({
                    street1: "100 N Holliday St",
                    street2: "",
                    city: "Baltimore",
                    region_code: "MD",
                    postal_code: "21202",
                    country: "United States",
                    latitude: 39.29105,
                    longitude: -76.61069,
                    place_types: ["street_address"],
                });
            });
            fireEvent.press(screen.getByTestId("address-submit-cta"));

            expect(screen.getByTestId("address-switch-confirm")).toBeTruthy();
            expect(screen.getAllByText(PARITY_COPY.address.switchConfirm.title)).toHaveLength(2);
            expect(screen.getByText(PARITY_COPY.address.switchConfirm.body)).toBeTruthy();
            expect(screen.getAllByText(PARITY_COPY.address.switchConfirm.confirmCta)).toHaveLength(2);
            expect(screen.getByText(PARITY_COPY.address.switchConfirm.cancelCta)).toBeTruthy();
            expect(apiClient.post).not.toHaveBeenCalled();

            fireEvent.press(screen.getByTestId("address-cancel-deactivate-cta"));
            expect(screen.queryByTestId("address-switch-confirm")).toBeNull();
            expect(apiClient.post).not.toHaveBeenCalled();

            fireEvent.press(screen.getByTestId("address-submit-cta"));
            expect(screen.getByTestId("address-switch-confirm")).toBeTruthy();

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-confirm-deactivate-cta"));
            });

            await waitFor(() => {
                expect(apiClient.post).toHaveBeenCalledWith(
                    "/sway_registration",
                    expect.objectContaining({
                        sway_registration: expect.objectContaining({
                            confirm_deactivate_legislators: true,
                        }),
                    }),
                );
            });
        });
    });

    describe("processing state", () => {
        it("Test 5 — renders processing Card, polls refresh every 3s, and lets user cancel and sign out", () => {
            jest.useFakeTimers();
            const refresh = jest.fn();
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    registration_status: "processing",
                    address: undefined,
                },
                loading: false,
                refresh,
            });

            wrap(<AddressScreen />);

            expect(screen.getByTestId("address-processing")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.processing.title)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.processing.message)).toBeTruthy();

            jest.advanceTimersByTime(3000);
            expect(refresh).toHaveBeenCalledTimes(1);

            fireEvent.press(screen.getByTestId("address-processing-signout-cta"));
            expect(mockSignOut).toHaveBeenCalledTimes(1);
            jest.useRealTimers();
        });
    });

    describe("failed state", () => {
        it("Test 6 — renders failed Card with retry and sign out actions", () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    registration_status: "failed",
                    address: undefined,
                },
                loading: false,
                refresh: jest.fn(),
            });

            wrap(<AddressScreen />);

            expect(screen.getByTestId("address-failed")).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.failed.title)).toBeTruthy();
            expect(screen.getByText(PARITY_COPY.address.failed.message)).toBeTruthy();

            fireEvent.press(screen.getByTestId("address-failed-signout-cta"));
            expect(mockSignOut).toHaveBeenCalledTimes(1);

            fireEvent.press(screen.getByTestId("address-failed-retry-cta"));
            expect(screen.queryByTestId("address-failed")).toBeNull();
            expect(screen.getByTestId("address-submit-cta")).toBeTruthy();
        });

        it("keeps user on the form and shows address-error when a retry submission fails", async () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    registration_status: "failed",
                    address: undefined,
                },
                loading: false,
                refresh: jest.fn(),
            });
            (apiClient.post as jest.Mock).mockRejectedValueOnce(new Error("Network failure"));

            wrap(<AddressScreen />);

            fireEvent.press(screen.getByTestId("address-failed-retry-cta"));
            expect(screen.queryByTestId("address-failed")).toBeNull();

            act(() => {
                mockOnSelectAddress?.({
                    street1: "100 N Holliday St",
                    street2: "",
                    city: "Baltimore",
                    region_code: "MD",
                    postal_code: "21202",
                    country: "United States",
                    latitude: 39.29105,
                    longitude: -76.61069,
                    place_types: ["street_address"],
                });
            });

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            await waitFor(() => {
                expect(screen.getByTestId("address-error")).toBeTruthy();
            });
            expect(screen.getByText("Network failure")).toBeTruthy();
            expect(screen.queryByTestId("address-failed")).toBeNull();
            expect(screen.getByTestId("address-submit-cta")).toBeTruthy();
        });
    });

    describe("manual mode toggle", () => {
        it("allows switching to manual entry and back to address search when autocomplete is available", () => {
            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser, address: undefined },
                loading: false,
                refresh: jest.fn(),
            });

            wrap(<AddressScreen />);

            fireEvent.press(screen.getByTestId("btn-edit-address-manually"));
            expect(screen.getByTestId("address-input-street1")).toBeTruthy();
            expect(screen.getByTestId("btn-search-address-autocomplete")).toBeTruthy();

            fireEvent.press(screen.getByTestId("btn-search-address-autocomplete"));
            expect(screen.queryByTestId("address-input-street1")).toBeNull();
            expect(screen.getByTestId("btn-edit-address-manually")).toBeTruthy();
        });
    });
});

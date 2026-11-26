// AddressScreen.test.tsx does not check address suggestions or post-submit destination — see AddressScreen.parity.test.tsx.

const mockUseUserProfile = jest.fn();
const mockSignOut = jest.fn(async () => {});

jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => ({ isAuthenticated: true, loading: false, signOut: mockSignOut, signOutAll: jest.fn() }),
}));

jest.mock("../../src/hooks/useUserProfile", () => ({
    useUserProfile: () => mockUseUserProfile(),
}));

jest.mock("../../src/api/client", () => ({
    apiClient: { post: jest.fn(async () => ({ ok: true })) },
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

const mockPlacesKeys: { googlePlacesApiKeyIOS?: string; googlePlacesApiKeyAndroid?: string } = {};

jest.mock("expo-constants", () => ({
    expoConfig: {
        get extra() {
            return mockPlacesKeys;
        },
    },
}));

let mockOnSelectAddress: ((parsed: Record<string, unknown>) => void) | null = null;
let mockOnAutocompleteError: ((message: string | null) => void) | null = null;

// Replace AddressAutocomplete so the native Google Places SDK is never loaded.
// `__esModule: true` tells jest to hand back `.default` for a default import,
// which is how AddressScreen writes `import AddressAutocomplete from ...`.
jest.mock("../../src/components/AddressAutocomplete", () => ({
    __esModule: true,
    default: ({
        onSelect,
        onError,
    }: {
        onSelect: (parsed: Record<string, unknown>) => void;
        onError: (message: string | null) => void;
    }) => {
        mockOnSelectAddress = onSelect;
        mockOnAutocompleteError = onError;
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
import { inviteAttribution } from "../../src/state/inviteAttribution";
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
    mockPlacesKeys.googlePlacesApiKeyIOS = "test-key";
    mockPlacesKeys.googlePlacesApiKeyAndroid = "test-key-android";
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
                        street: "100 N Holliday St",
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
                        street: "123 Main St",
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
            expect(
                screen.getByText(
                    "Your past votes stay on your account and will count toward your new district and representatives.",
                ),
            ).toBeTruthy();
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

    // @lat: [[mobile-auth-and-onboarding-flow#AddressScreen#Onboarding sends the invite the app was opened with]]
    describe("edit mode with a stored invite attribution key", () => {
        afterEach(() => {
            inviteAttribution.clear();
        });

        it("never sends the key for an address change", async () => {
            inviteAttribution.set("s:abc123");
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: { street: "1 Old St", city: "Baltimore" },
                },
                loading: false,
                refresh: jest.fn(),
            });
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
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-confirm-deactivate-cta"));
            });

            const posted = (apiClient.post as jest.Mock).mock.calls[0][1].sway_registration;
            expect(posted).not.toHaveProperty("invite_attribution_key");
            expect(inviteAttribution.get()).toBe("s:abc123");
        });
    });

    describe("processing state", () => {
        it("renders the address form without polling when registration_status is processing", () => {
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

            expect(screen.queryByTestId("address-processing")).toBeNull();
            expect(screen.getByTestId("address-submit-cta")).toBeTruthy();

            jest.advanceTimersByTime(9000);
            expect(refresh).not.toHaveBeenCalled();
            jest.useRealTimers();
        });
    });

    describe("failed state", () => {
        it("renders the address form directly instead of an error card when registration_status is failed", () => {
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

            expect(screen.queryByTestId("address-failed")).toBeNull();
            expect(screen.getByTestId("address-submit-cta")).toBeTruthy();
        });

        it("keeps user on the form and shows address-error when a submission fails", async () => {
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
            expect(screen.getByText("Could not update address.")).toBeTruthy();
            expect(screen.queryByText("Network failure")).toBeNull();
            expect(screen.queryByTestId("address-failed")).toBeNull();
            expect(screen.getByTestId("address-submit-cta")).toBeTruthy();
        });
    });

    describe("manual entry without a Google Places key", () => {
        const holliday = {
            street1: "100 N Holliday St",
            street2: "",
            city: "Baltimore",
            region_code: "MD",
            postal_code: "21202",
            country: "United States",
            latitude: 39.29105,
            longitude: -76.61069,
            place_types: ["street_address"],
        };

        const type = (field: string, text: string) =>
            fireEvent.changeText(screen.getByTestId(`address-input-${field}-input`), text);

        const postedRegistration = () =>
            (apiClient.post as jest.Mock).mock.calls[0][1].sway_registration as Record<string, unknown>;

        beforeEach(() => {
            mockPlacesKeys.googlePlacesApiKeyIOS = undefined;
            mockPlacesKeys.googlePlacesApiKeyAndroid = undefined;
            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser, address: undefined },
                loading: false,
                refresh: jest.fn(),
            });
        });

        // @lat: [[mobile-auth-and-onboarding-flow#AddressScreen#Onboarding sends the invite the app was opened with]]
        describe("invite attribution key", () => {
            const submitTypedAddress = async () => {
                wrap(<AddressScreen />);
                type("street1", "100 N Holliday St");
                type("city", "Baltimore");
                type("region_code", "MD");
                type("postal_code", "21202");
                await act(async () => {
                    fireEvent.press(screen.getByTestId("address-submit-cta"));
                });
            };

            afterEach(() => {
                inviteAttribution.clear();
            });

            it("sends a stored key in onboarding and clears it once the address is saved", async () => {
                inviteAttribution.set("s:abc123");

                await submitTypedAddress();

                expect(postedRegistration().invite_attribution_key).toBe("s:abc123");
                expect(inviteAttribution.get()).toBeNull();
            });

            it("sends no key when none is stored", async () => {
                await submitTypedAddress();

                expect(postedRegistration()).not.toHaveProperty("invite_attribution_key");
            });

            it("keeps the key when the request fails", async () => {
                inviteAttribution.set("s:abc123");
                (apiClient.post as jest.Mock).mockRejectedValueOnce(new Error("Network failure"));

                await submitTypedAddress();

                expect(inviteAttribution.get()).toBe("s:abc123");
            });

            it("keeps the key when the address was not located", async () => {
                inviteAttribution.set("s:abc123");
                (apiClient.post as jest.Mock).mockResolvedValueOnce({ address_located: false, message: "Not found" });

                await submitTypedAddress();

                expect(inviteAttribution.get()).toBe("s:abc123");
            });

            it("clears the key when the person continues with an address that was not located", async () => {
                inviteAttribution.set("s:abc123");
                (apiClient.post as jest.Mock).mockResolvedValueOnce({ address_located: false, message: "Not found" });

                await submitTypedAddress();
                await act(async () => {
                    fireEvent.press(screen.getByTestId("address-not-located-continue-cta"));
                });

                expect(inviteAttribution.get()).toBeNull();
            });
        });

        it("enables the submit button once the typed fields are filled and posts them with null coordinates", async () => {
            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            type("city", "Baltimore");
            type("region_code", "MD");
            type("postal_code", "21202");

            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBeFalsy();

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(apiClient.post).toHaveBeenCalledWith(
                "/sway_registration",
                expect.objectContaining({
                    sway_registration: expect.objectContaining({
                        street: "100 N Holliday St",
                        city: "Baltimore",
                        region_code: "MD",
                        postal_code: "21202",
                        latitude: null,
                        longitude: null,
                    }),
                }),
            );
        });

        it("enables the submit button with only a street typed and posts blank other fields", async () => {
            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(postedRegistration()).toEqual(
                expect.objectContaining({ street: "100 N Holliday St", city: "", region_code: "", postal_code: "" }),
            );
            expect(postedRegistration().latitude).toBeNull();
        });

        it("posts the apartment as street2 and keeps the street line to the street alone", async () => {
            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            type("street2", "Apt 2");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(postedRegistration()).toEqual(
                expect.objectContaining({ street: "100 N Holliday St", street2: "Apt 2" }),
            );
        });

        it("posts a null street2 when no apartment is typed", async () => {
            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(postedRegistration().street2).toBeNull();
        });

        it("posts the apartment of a picked suggestion as street2", async () => {
            mockPlacesKeys.googlePlacesApiKeyIOS = "test-key";
            wrap(<AddressScreen />);

            act(() => {
                mockOnSelectAddress?.({ ...holliday, street2: "Unit 4B" });
            });
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(postedRegistration()).toEqual(
                expect.objectContaining({ street: "100 N Holliday St", street2: "Unit 4B", latitude: 39.29105 }),
            );
        });

        it("keeps the submit button disabled while the street is empty", async () => {
            wrap(<AddressScreen />);

            type("city", "Baltimore");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(apiClient.post).not.toHaveBeenCalled();
            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBe(true);
        });

        it("posts null coordinates when a field is edited after a suggestion was picked", async () => {
            mockPlacesKeys.googlePlacesApiKeyIOS = "test-key";
            wrap(<AddressScreen />);

            act(() => {
                mockOnSelectAddress?.(holliday);
            });
            fireEvent.press(screen.getByTestId("btn-edit-address-manually"));
            type("street1", "200 N Holliday St");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(postedRegistration()).toEqual(
                expect.objectContaining({
                    street: "200 N Holliday St",
                    latitude: null,
                    longitude: null,
                    place_types: [],
                }),
            );
        });

        it("posts the coordinates of a picked suggestion", async () => {
            mockPlacesKeys.googlePlacesApiKeyIOS = "test-key";
            wrap(<AddressScreen />);

            act(() => {
                mockOnSelectAddress?.(holliday);
            });
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(postedRegistration()).toEqual(
                expect.objectContaining({ street: "100 N Holliday St", latitude: 39.29105, longitude: -76.61069 }),
            );
        });

        it("enables Save for a picked suggestion that has coordinates but no street", async () => {
            mockPlacesKeys.googlePlacesApiKeyIOS = "test-key";
            wrap(<AddressScreen />);

            act(() => {
                mockOnSelectAddress?.({ ...holliday, street1: "" });
            });
            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBeFalsy();
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(postedRegistration()).toEqual(
                expect.objectContaining({ street: "", latitude: 39.29105, longitude: -76.61069 }),
            );
        });

        it("keeps Save disabled in edit mode until a field differs from the saved address", () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: { street: "123 Main St", city: "Baltimore", region_code: "MD", postal_code: "21201" },
                },
                loading: false,
                refresh: jest.fn(),
            });
            wrap(<AddressScreen />);

            type("street1", "123 Main St");
            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBe(true);
            fireEvent.press(screen.getByTestId("address-submit-cta"));
            expect(screen.queryByTestId("address-switch-confirm")).toBeNull();

            type("city", "Towson");
            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBeFalsy();

            type("city", "Baltimore");
            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBe(true);
            expect(apiClient.post).not.toHaveBeenCalled();
        });

        it("keeps Save disabled when the saved street is the typed street and apartment joined", () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: {
                        street: "123 Main St Apt 2",
                        city: "Baltimore",
                        region_code: "MD",
                        postal_code: "21201",
                    },
                },
                loading: false,
                refresh: jest.fn(),
            });
            wrap(<AddressScreen />);

            type("street1", "123 Main St");
            type("street2", "Apt 2");

            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBe(true);
        });

        it("keeps Save disabled for a prefilled address whose apartment is saved separately", () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: {
                        street: "123 Main St",
                        street2: "Apt 2",
                        city: "Baltimore",
                        region_code: "MD",
                        postal_code: "21201",
                    },
                },
                loading: false,
                refresh: jest.fn(),
            });
            wrap(<AddressScreen />);

            expect(screen.getByTestId("address-input-street1-input").props.value).toBe("123 Main St");
            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBe(true);
        });

        it("asks for the switch confirmation before posting a typed address in edit mode", async () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: { street: "123 Main St", city: "Baltimore", region_code: "MD", postal_code: "21201" },
                },
                loading: false,
                refresh: jest.fn(),
            });
            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            fireEvent.press(screen.getByTestId("address-submit-cta"));

            expect(screen.getByTestId("address-switch-confirm")).toBeTruthy();
            expect(apiClient.post).not.toHaveBeenCalled();

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-confirm-deactivate-cta"));
            });

            expect(postedRegistration()).toEqual(
                expect.objectContaining({
                    street: "100 N Holliday St",
                    latitude: null,
                    longitude: null,
                    confirm_deactivate_legislators: true,
                }),
            );
        });

        it("shows the not-located card and manual fields without refreshing or navigating when address_located is false", async () => {
            const refresh = jest.fn();
            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser, address: undefined },
                loading: false,
                refresh,
            });
            (apiClient.post as jest.Mock).mockResolvedValueOnce({
                ok: true,
                registration_status: "completed",
                address_located: false,
                message: "M",
            });
            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(screen.getByTestId("address-not-located")).toBeTruthy();
            expect(screen.getByText("M")).toBeTruthy();
            expect(screen.getByTestId("address-input-street1-input").props.value).toBe("100 N Holliday St");
            expect(screen.getByTestId("address-input-city-input")).toBeTruthy();
            expect(screen.getByTestId("address-input-postal_code-input")).toBeTruthy();
            expect(refresh).not.toHaveBeenCalled();
            expect(mockNavigation.goBack).not.toHaveBeenCalled();

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-not-located-continue-cta"));
            });

            expect(refresh).toHaveBeenCalledTimes(1);
            expect(mockNavigation.goBack).toHaveBeenCalledTimes(1);
        });

        it("clears caches and refreshes immediately on address_located: false in edit mode while keeping the not-located card visible", async () => {
            const useBills = require("../../src/hooks/useBills") as typeof import("../../src/hooks/useBills");
            const legislatorCache =
                require("../../src/cache/legislatorCache") as typeof import("../../src/cache/legislatorCache");
            const billCache = require("../../src/cache/billCache") as typeof import("../../src/cache/billCache");
            const callOrder: string[] = [];
            const catSpy = jest
                .spyOn(useBills, "clearCapturedCategories")
                .mockImplementation(() => callOrder.push("clearCapturedCategories"));
            const legSpy = jest
                .spyOn(legislatorCache, "clear")
                .mockImplementation(async () => void callOrder.push("legislatorCache.clear"));
            const billSpy = jest
                .spyOn(billCache, "clear")
                .mockImplementation(async () => void callOrder.push("billCache.clear"));
            const refresh = jest.fn(async () => {
                callOrder.push("refresh");
                return true;
            });

            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: {
                        street: "123 Main St",
                        city: "Baltimore",
                        region_code: "MD",
                        postal_code: "21201",
                        country: "United States",
                    },
                },
                loading: false,
                refresh,
            });
            (apiClient.post as jest.Mock).mockResolvedValueOnce({
                ok: true,
                registration_status: "completed",
                address_located: false,
                message: "M",
            });

            try {
                wrap(<AddressScreen />);

                type("street1", "100 N Holliday St");
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                expect(screen.getByTestId("address-switch-confirm")).toBeTruthy();

                await act(async () => {
                    fireEvent.press(screen.getByTestId("address-confirm-deactivate-cta"));
                });

                expect(catSpy).toHaveBeenCalledTimes(1);
                expect(legSpy).toHaveBeenCalledTimes(1);
                expect(billSpy).toHaveBeenCalledTimes(1);
                expect(refresh).toHaveBeenCalledTimes(1);
                expect(callOrder.indexOf("clearCapturedCategories")).toBeLessThan(callOrder.indexOf("refresh"));
                expect(callOrder.indexOf("legislatorCache.clear")).toBeLessThan(callOrder.indexOf("refresh"));
                expect(callOrder.indexOf("billCache.clear")).toBeLessThan(callOrder.indexOf("refresh"));
                expect(screen.getByTestId("address-not-located")).toBeTruthy();
                expect(screen.getByText("M")).toBeTruthy();
                expect(screen.getByTestId("address-input-street1-input").props.value).toBe("100 N Holliday St");
                expect(mockNavigation.goBack).not.toHaveBeenCalled();

                fireEvent.press(screen.getByTestId("address-cancel-cta"));
                expect(mockNavigation.goBack).toHaveBeenCalledTimes(1);
            } finally {
                catSpy.mockRestore();
                legSpy.mockRestore();
                billSpy.mockRestore();
            }
        });

        it("navigates back cleanly when tapping continue on the not-located card in edit mode", async () => {
            const refresh = jest.fn(async () => true);
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: {
                        street: "123 Main St",
                        city: "Baltimore",
                        region_code: "MD",
                        postal_code: "21201",
                        country: "United States",
                    },
                },
                loading: false,
                refresh,
            });
            (apiClient.post as jest.Mock).mockResolvedValueOnce({
                ok: true,
                registration_status: "completed",
                address_located: false,
                message: "M",
            });

            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            fireEvent.press(screen.getByTestId("address-submit-cta"));
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-confirm-deactivate-cta"));
            });

            expect(screen.getByTestId("address-not-located")).toBeTruthy();
            expect(mockNavigation.goBack).not.toHaveBeenCalled();

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-not-located-continue-cta"));
            });

            expect(screen.queryByTestId("address-not-located")).toBeNull();
            expect(mockNavigation.goBack).toHaveBeenCalledTimes(1);
        });

        it("posts the edited ZIP code on resubmit, hides the not-located card, refreshes, and goes back", async () => {
            const refresh = jest.fn();
            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser, address: undefined },
                loading: false,
                refresh,
            });
            (apiClient.post as jest.Mock)
                .mockResolvedValueOnce({
                    ok: true,
                    registration_status: "completed",
                    address_located: false,
                    message: "M",
                })
                .mockResolvedValueOnce({
                    ok: true,
                    registration_status: "completed",
                });
            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(screen.getByTestId("address-not-located")).toBeTruthy();

            type("postal_code", "21202");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect((apiClient.post as jest.Mock).mock.calls[1][1].sway_registration).toEqual(
                expect.objectContaining({
                    street: "100 N Holliday St",
                    postal_code: "21202",
                }),
            );
            expect(screen.queryByTestId("address-not-located")).toBeNull();
            expect(refresh).toHaveBeenCalledTimes(1);
            expect(mockNavigation.goBack).toHaveBeenCalledTimes(1);
        });

        it("refreshes and goes back on the first post when the answer does not have address_located false", async () => {
            const refresh = jest.fn();
            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser, address: undefined },
                loading: false,
                refresh,
            });
            (apiClient.post as jest.Mock).mockResolvedValueOnce({
                ok: true,
                registration_status: "completed",
            });
            wrap(<AddressScreen />);

            type("street1", "100 N Holliday St");
            type("postal_code", "21202");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
            });

            expect(screen.queryByTestId("address-not-located")).toBeNull();
            expect(refresh).toHaveBeenCalledTimes(1);
            expect(mockNavigation.goBack).toHaveBeenCalledTimes(1);
        });
    });

    describe("prefill from the saved address", () => {
        it("fills the street lines from the street and street2 keys the server sends", () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: false,
                    address: {
                        street: "100 N Holliday St",
                        street2: "Apt 2",
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
            fireEvent.press(screen.getByTestId("btn-edit-address-manually"));

            expect(screen.getByTestId("address-input-street1-input").props.value).toBe("100 N Holliday St");
            expect(screen.getByTestId("address-input-street2-input").props.value).toBe("Apt 2");
        });

        it("prefills once, so a later profile refresh does not overwrite a picked suggestion", () => {
            const profileFor = (street: string, city: string) => ({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: { street, city, region_code: "MD", postal_code: "21401", country: "United States" },
                },
                loading: false,
                refresh: jest.fn(),
            });
            mockUseUserProfile.mockReturnValue(profileFor("1 Old St", "Annapolis"));
            const ui = (
                <ThemeProvider initialMode="light">
                    <AddressScreen />
                </ThemeProvider>
            );
            const { rerender } = render(ui);

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
            mockUseUserProfile.mockReturnValue(profileFor("2 New St", "Towson"));
            rerender(ui);
            fireEvent.press(screen.getByTestId("btn-edit-address-manually"));

            expect(screen.getByTestId("address-input-street1-input").props.value).toBe("100 N Holliday St");
            expect(screen.getByTestId("address-input-city-input").props.value).toBe("Baltimore");
        });
    });

    describe("autocomplete errors", () => {
        it("clears an earlier autocomplete error when a suggestion is picked", () => {
            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser, address: undefined },
                loading: false,
                refresh: jest.fn(),
            });
            wrap(<AddressScreen />);

            act(() => {
                mockOnAutocompleteError?.("Address search is unavailable.");
            });
            expect(screen.getByText("Address search is unavailable.")).toBeTruthy();

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

            expect(screen.queryByTestId("address-error")).toBeNull();
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

    describe("edge cases for platform, nullish address prefill, unlocated fallback, and cache failures", () => {
        it("checks googlePlacesApiKeyAndroid on android", () => {
            const { Platform } = require("react-native") as typeof import("react-native");
            const restorePlatform = jest.replaceProperty(Platform, "OS", "android").restore;
            mockPlacesKeys.googlePlacesApiKeyAndroid = undefined;
            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser, address: undefined },
                loading: false,
                refresh: jest.fn(),
            });
            try {
                wrap(<AddressScreen />);
                expect(screen.getByTestId("address-input-street1")).toBeTruthy();
                expect(screen.queryByTestId("btn-search-address-autocomplete")).toBeNull();
            } finally {
                restorePlatform();
            }
        });

        it("prefills empty strings for missing address fields and matches saved address with null city/state", () => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...baseUser,
                    is_registration_complete: true,
                    address: {
                        street: undefined,
                        city: undefined,
                        region_code: undefined,
                        postal_code: "21202",
                        country: "United States",
                    },
                },
                loading: false,
                refresh: jest.fn(),
            });
            wrap(<AddressScreen />);
            fireEvent.press(screen.getByTestId("btn-edit-address-manually"));

            expect(screen.getByTestId("address-input-street1-input").props.value).toBe("");
            expect(screen.getByTestId("address-input-city-input").props.value).toBe("");
            expect(screen.getByTestId("address-input-region_code-input").props.value).toBe("");
            expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBe(true);
        });

        it("handles address_located: false without message, defaults blank country from autocomplete, and tolerates cache clear errors", async () => {
            const legislatorCache =
                require("../../src/cache/legislatorCache") as typeof import("../../src/cache/legislatorCache");
            const billCache = require("../../src/cache/billCache") as typeof import("../../src/cache/billCache");
            const legSpy = jest.spyOn(legislatorCache, "clear").mockRejectedValueOnce(new Error("db locked"));
            const billSpy = jest.spyOn(billCache, "clear").mockRejectedValueOnce(new Error("db locked"));
            const refreshMock = jest.fn(async () => true);

            mockUseUserProfile.mockReturnValue({
                user: { ...baseUser },
                loading: false,
                refresh: refreshMock,
            });
            (apiClient.post as jest.Mock)
                .mockResolvedValueOnce({ address_located: false })
                .mockResolvedValueOnce({ ok: true });

            try {
                wrap(<AddressScreen />);
                act(() => {
                    mockOnSelectAddress?.({
                        street1: "100 N Holliday St",
                        street2: "",
                        city: "Baltimore",
                        region_code: "MD",
                        postal_code: "21202",
                        country: "",
                        latitude: 39.29,
                        longitude: -76.61,
                        place_types: ["street_address"],
                    });
                });

                await act(async () => {
                    fireEvent.press(screen.getByTestId("address-submit-cta"));
                });
                expect(screen.getByTestId("address-input-country-input").props.value).toBe("United States");

                await act(async () => {
                    fireEvent.press(screen.getByTestId("address-submit-cta"));
                });
                expect(legSpy).toHaveBeenCalled();
                expect(billSpy).toHaveBeenCalled();
                expect(refreshMock).toHaveBeenCalled();
            } finally {
                legSpy.mockRestore();
                billSpy.mockRestore();
            }
        });
    });
});

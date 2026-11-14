// @lat: [[sway-registration-controller-notes#What AddressScreen.parity.test.tsx deliberately does not cover]]
// @lat: [[mobile-jest-first-pass-test-notes#AddressScreen.parity.test.tsx]]

// Jest lifts jest.mock factories to the top of the file, and they may only mention variables whose
// names begin with `mock` (any capitalisation) — which is why the names below start with "mock".

// Order must match the web app's @react-google-maps/api Autocomplete for the same search — both hit
// the same Google Places service. Keep this and the web fixture in sync if that ever changes.
const mockHollidayFixture = [
    {
        placeID: "PLACE_HOLLIDAY_1",
        primaryText: "100 N Holliday St",
        secondaryText: "Baltimore, MD, USA",
        description: "100 N Holliday St, Baltimore, MD, USA",
    },
    {
        placeID: "PLACE_HOLLIDAY_2",
        primaryText: "300 Holliday St",
        secondaryText: "Baltimore, MD, USA",
        description: "300 Holliday St, Baltimore, MD, USA",
    },
];

// The place details that come back when PLACE_HOLLIDAY_1 is looked up. They
// carry a latitude and longitude, which is what lets the AddressScreen form be
// submitted (canSubmit turns true).
const mockHollidayPlaceDetail = {
    addressComponents: [
        { types: ["street_number"], name: "100", shortName: "100" },
        { types: ["route"], name: "N Holliday St", shortName: "N Holliday St" },
        { types: ["locality"], name: "Baltimore", shortName: "Baltimore" },
        { types: ["administrative_area_level_1"], name: "Maryland", shortName: "MD" },
        { types: ["postal_code"], name: "21202", shortName: "21202" },
        { types: ["country"], name: "United States", shortName: "US" },
    ],
    coordinate: { latitude: 39.29105, longitude: -76.61069 },
    formattedAddress: "100 N Holliday St, Baltimore, MD 21202, USA",
    types: ["street_address", "geocode"],
};

const mockUseUserProfile = jest.fn();
const mockApiPost = jest.fn(async (..._args: unknown[]): Promise<unknown> => ({ ok: true }));
const mockGoBack = jest.fn();
const mockCanGoBack = jest.fn(() => false);
const mockNavigate = jest.fn();
const mockRefresh = jest.fn(async (): Promise<boolean | void> => {});

jest.mock("../../src/hooks/useUserProfile", () => ({
    useUserProfile: () => mockUseUserProfile(),
}));

jest.mock("../../src/api/client", () => ({
    apiClient: { post: (...args: unknown[]) => mockApiPost(...args) },
}));

const mockClearCapturedCategories = jest.fn();
jest.mock("../../src/hooks/useBills", () => ({
    clearCapturedCategories: (...args: unknown[]) => mockClearCapturedCategories(...args),
}));

const mockLegislatorCacheClear = jest.fn(async () => {});
jest.mock("../../src/cache/legislatorCache", () => ({
    clear: () => mockLegislatorCacheClear(),
    get: jest.fn(async () => []),
    set: jest.fn(async () => {}),
}));

const mockBillCacheClear = jest.fn(async () => {});
jest.mock("../../src/cache/billCache", () => ({
    clear: () => mockBillCacheClear(),
    clearOne: jest.fn(async () => {}),
    get: jest.fn(async () => []),
    set: jest.fn(async () => {}),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

// expo-constants is loaded the older CommonJS way, so this fake is a plain object
// with no `.default` wrapper — the same as in useBootstrap.test.ts.
jest.mock("expo-constants", () => ({
    expoConfig: {
        extra: {
            googlePlacesApiKeyIOS: "test-key-ios",
            googlePlacesApiKeyAndroid: "test-key-android",
        },
    },
}));

// @lat: [[mobile-jest-first-pass-test-notes#AddressScreen.parity.test.tsx]]
jest.mock("react-native-google-places-sdk", () => {
    const sdk = {
        fetchPredictions: jest.fn(async (q: string) => (q.includes("Holliday") ? mockHollidayFixture : [])),
        fetchPlaceByID: jest.fn(async () => mockHollidayPlaceDetail),
        initialize: jest.fn(),
    };
    return {
        __esModule: true,
        default: sdk,
        PLACE_FIELDS: {
            ADDRESS_COMPONENTS: "ADDRESS_COMPONENTS",
            FORMATTED_ADDRESS: "FORMATTED_ADDRESS",
            COORDINATE: "COORDINATE",
            TYPES: "TYPES",
        },
    };
});

const mockNavigation = {
    navigate: (...args: unknown[]) => mockNavigate(...args),
    goBack: () => mockGoBack(),
    canGoBack: () => mockCanGoBack(),
};
jest.mock("@react-navigation/native", () => ({
    useNavigation: () => mockNavigation,
    useIsFocused: () => true,
}));

import React from "react";
import { render, fireEvent, screen, waitFor, act } from "@testing-library/react-native";
import AddressScreen from "../../src/screens/AddressScreen";
import { ThemeProvider } from "../../src/theme/ThemeProvider";
import { PARITY_COPY } from "../../../app/frontend/sway_constants/parityCopy";

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const mockOnboardingUser = {
    id: 1,
    is_registration_complete: false,
    address: undefined,
};

const mockEditUser = {
    id: 2,
    is_registration_complete: true,
    address: {
        street: "123 Main St",
        city: "Baltimore",
        region_code: "MD",
        postal_code: "21201",
        country: "United States",
    },
};

beforeEach(() => {
    jest.clearAllMocks();
    mockRefresh.mockResolvedValue(undefined);
    mockApiPost.mockResolvedValue({ ok: true });
    jest.useFakeTimers();
});

afterEach(() => {
    jest.useRealTimers();
});

// Helper: waits out the 250ms debounce before predictions appear.
async function typeAndWaitForPredictions(query: string) {
    const input = screen.getByTestId("address-autocomplete-input");
    fireEvent.changeText(input, query);
    // Move past AddressAutocomplete's 250ms pause (DEBOUNCE_MS).
    await act(async () => {
        jest.advanceTimersByTime(350);
        await Promise.resolve();
        await Promise.resolve();
    });
}

/**
 * Helper: tap one of the suggestions and wait for fetchPlaceByID to finish. That
 * fills in the latitude and longitude, which switches the submit button on.
 */
async function pickPrediction(testID: string) {
    await act(async () => {
        fireEvent.press(screen.getByTestId(testID));
        await Promise.resolve();
        await Promise.resolve();
    });
}

// @lat: [[mobile-test-infrastructure-notes#Why two examples carry an explicit 30-second timeout]]
const RENDER_BOUND_TIMEOUT_MS = 30_000;

describe("AddressScreen parity tests (Codex Concern 2 PARITY-13)", () => {
    describe("Test 1 — SC-2 autocomplete fixture parity", () => {
        it(
            "react-native-google-places-sdk returns same N predictions in same order for canonical 'Holliday' query",
            async () => {
                mockUseUserProfile.mockReturnValue({
                    user: mockOnboardingUser,
                    loading: false,
                    refresh: mockRefresh,
                });
                mockCanGoBack.mockReturnValue(false);

                wrap(<AddressScreen />);

                await typeAndWaitForPredictions("100 N Holliday");

                // Exactly 2 suggestions should appear, in the order of the sample data.
                // Their testIDs are built as address-suggestion-{placeID} inside
                // AddressAutocomplete.tsx.
                await waitFor(() => {
                    expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
                    expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_2")).toBeTruthy();
                });

                // Order: first item matches "100 N Holliday St", second matches "300 Holliday St".
                expect(screen.getByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
                expect(screen.getByTestId("address-suggestion-PLACE_HOLLIDAY_2")).toBeTruthy();

                const sdk = jest.requireMock("react-native-google-places-sdk").default as {
                    fetchPredictions: jest.Mock;
                };
                expect(sdk.fetchPredictions).toHaveBeenCalledWith(
                    expect.stringContaining("Holliday"),
                    expect.any(Object),
                );
            },
            RENDER_BOUND_TIMEOUT_MS,
        );
    });

    describe("Test 2 — SC-3 onboarding-mode post-submit destination parity", () => {
        it("refreshes the profile on success so the app opens on the feed (mirrors web redirect to feed_path)", async () => {
            mockUseUserProfile.mockReturnValue({
                user: mockOnboardingUser,
                loading: false,
                refresh: mockRefresh,
            });
            mockCanGoBack.mockReturnValue(false);

            wrap(<AddressScreen />);

            await typeAndWaitForPredictions("100 N Holliday");

            await waitFor(() => {
                expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
            });

            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });

            await waitFor(() => {
                expect(mockApiPost).toHaveBeenCalledWith("/sway_registration", expect.any(Object));
                expect(mockRefresh).toHaveBeenCalledTimes(1);
            });

            // During first-time setup there is no earlier screen (canGoBack is
            // false), so goBack is never called.
            expect(mockGoBack).not.toHaveBeenCalled();
        });

        it("keeps onboarding open and shows the no-representatives response on 422", async () => {
            const message = "No representatives were found for this address. Check that it is in a supported area.";
            mockUseUserProfile.mockReturnValue({
                user: {
                    ...mockOnboardingUser,
                    address: { street: "100 N Holliday St", city: "Baltimore", region_code: "MD" },
                },
                loading: false,
                refresh: mockRefresh,
            });
            mockApiPost.mockRejectedValueOnce(new Error(message));

            wrap(<AddressScreen />);
            expect(screen.getByTestId("address-onboarding-heading")).toBeTruthy();
            await typeAndWaitForPredictions("100 N Holliday");
            await waitFor(() => expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy());
            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });

            await waitFor(() => expect(screen.getByText(message)).toBeTruthy());
            expect(mockRefresh).not.toHaveBeenCalled();
            expect(mockGoBack).not.toHaveBeenCalled();
        });
    });

    describe("Test 2b — the bootstrap refresh after a saved address fails", () => {
        async function submitPickedHollidayAddress() {
            await typeAndWaitForPredictions("100 N Holliday");
            await waitFor(() => {
                expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
            });
            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");
            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });
        }

        // @lat: [[mobile-auth-and-onboarding-flow#AddressScreen#Why a failed refresh after a saved address shows a recovery card]]
        it("shows a recovery card instead of the address form when refresh resolves false", async () => {
            mockUseUserProfile.mockReturnValue({ user: mockOnboardingUser, loading: false, refresh: mockRefresh });
            mockCanGoBack.mockReturnValue(false);
            mockRefresh.mockResolvedValue(false);

            wrap(<AddressScreen />);
            await submitPickedHollidayAddress();

            await waitFor(() => expect(screen.getByTestId("address-saved-recovery")).toBeTruthy());
            expect(screen.getByText("Your address was saved")).toBeTruthy();
            expect(
                screen.getByText("We could not load your account yet. Check your connection and try again."),
            ).toBeTruthy();
            expect(screen.getByTestId("address-saved-recovery-retry-cta")).toBeTruthy();
            expect(screen.queryByTestId("address-submit-cta")).toBeNull();
        });

        it("retry reloads the account and posts nothing", async () => {
            mockUseUserProfile.mockReturnValue({ user: mockOnboardingUser, loading: false, refresh: mockRefresh });
            mockCanGoBack.mockReturnValue(false);
            mockRefresh.mockResolvedValue(false);

            wrap(<AddressScreen />);
            await submitPickedHollidayAddress();
            await waitFor(() => expect(screen.getByTestId("address-saved-recovery")).toBeTruthy());
            expect(mockApiPost).toHaveBeenCalledTimes(1);
            expect(mockRefresh).toHaveBeenCalledTimes(1);

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-saved-recovery-retry-cta"));
                await Promise.resolve();
            });

            expect(mockRefresh).toHaveBeenCalledTimes(2);
            expect(mockApiPost).toHaveBeenCalledTimes(1);
        });

        it.each([
            ["true", true],
            ["no value", undefined],
        ])("shows no recovery card when refresh resolves with %s", async (_label, resolved) => {
            mockUseUserProfile.mockReturnValue({ user: mockOnboardingUser, loading: false, refresh: mockRefresh });
            mockCanGoBack.mockReturnValue(true);
            mockRefresh.mockResolvedValue(resolved);

            wrap(<AddressScreen />);
            await submitPickedHollidayAddress();

            await waitFor(() => expect(mockGoBack).toHaveBeenCalledTimes(1));
            expect(screen.queryByTestId("address-saved-recovery")).toBeNull();
        });
    });

    describe("Test 3 — SC-3 edit-mode post-submit destination parity", () => {
        it("nav.goBack invoked after confirming address switch (edit mode pop-back)", async () => {
            mockUseUserProfile.mockReturnValue({
                user: mockEditUser,
                loading: false,
                refresh: mockRefresh,
            });
            mockCanGoBack.mockReturnValue(true);

            wrap(<AddressScreen />);

            await typeAndWaitForPredictions("100 N Holliday");

            await waitFor(() => {
                expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
            });

            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
            });

            expect(screen.getByTestId("address-switch-confirm")).toBeTruthy();
            expect(screen.getAllByText(PARITY_COPY.address.switchConfirm.title)).toHaveLength(2);
            expect(screen.getByText(PARITY_COPY.address.switchConfirm.body)).toBeTruthy();
            expect(screen.getAllByText(PARITY_COPY.address.switchConfirm.confirmCta)).toHaveLength(2);
            expect(screen.getByText(PARITY_COPY.address.switchConfirm.cancelCta)).toBeTruthy();
            expect(mockApiPost).not.toHaveBeenCalled();

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-confirm-deactivate-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });

            await waitFor(() => {
                expect(mockApiPost).toHaveBeenCalledWith(
                    "/sway_registration",
                    expect.objectContaining({
                        sway_registration: expect.objectContaining({
                            confirm_deactivate_legislators: true,
                        }),
                    }),
                );
            });

            // When editing there is a screen to return to (canGoBack is true),
            // so nav.goBack() does run.
            expect(mockGoBack).toHaveBeenCalledTimes(1);
        });
    });

    describe("Test 4 — voter-registration address confirmation", () => {
        it("leaving the confirmation unticked still sends the registration, with a false answer", async () => {
            mockUseUserProfile.mockReturnValue({
                user: mockOnboardingUser,
                loading: false,
                refresh: mockRefresh,
            });
            mockCanGoBack.mockReturnValue(false);

            wrap(<AddressScreen />);

            await typeAndWaitForPredictions("100 N Holliday");

            await waitFor(() => {
                expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
            });

            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });

            await waitFor(() => {
                expect(mockApiPost).toHaveBeenCalledWith(
                    "/sway_registration",
                    expect.objectContaining({
                        sway_registration: expect.objectContaining({
                            is_voter_registration_address_confirmed: false,
                        }),
                    }),
                );
            });

            expect(mockRefresh).toHaveBeenCalledTimes(1);
        });

        it("ticking the confirmation sends a true answer with the registration", async () => {
            mockUseUserProfile.mockReturnValue({
                user: mockOnboardingUser,
                loading: false,
                refresh: mockRefresh,
            });
            mockCanGoBack.mockReturnValue(false);

            wrap(<AddressScreen />);

            await typeAndWaitForPredictions("100 N Holliday");

            await waitFor(() => {
                expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
            });

            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");

            fireEvent(screen.getByTestId("pref-switch-registered-voter-address-confirmation"), "valueChange", true);

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });

            await waitFor(() => {
                expect(mockApiPost).toHaveBeenCalledWith(
                    "/sway_registration",
                    expect.objectContaining({
                        sway_registration: expect.objectContaining({
                            is_voter_registration_address_confirmed: true,
                        }),
                    }),
                );
            });
        });
    });

    describe("Test 5 — place types from Google Places", () => {
        it("asks the Places SDK for the types field and posts the values it returns", async () => {
            mockUseUserProfile.mockReturnValue({
                user: mockOnboardingUser,
                loading: false,
                refresh: mockRefresh,
            });
            mockCanGoBack.mockReturnValue(false);

            wrap(<AddressScreen />);

            await typeAndWaitForPredictions("100 N Holliday");

            await waitFor(() => {
                expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
            });

            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");

            const sdk = jest.requireMock("react-native-google-places-sdk").default as {
                fetchPlaceByID: jest.Mock;
            };
            expect(sdk.fetchPlaceByID).toHaveBeenCalledWith("PLACE_HOLLIDAY_1", expect.arrayContaining(["TYPES"]));

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });

            await waitFor(() => {
                expect(mockApiPost).toHaveBeenCalledWith(
                    "/sway_registration",
                    expect.objectContaining({
                        sway_registration: expect.objectContaining({
                            place_types: ["street_address", "geocode"],
                        }),
                    }),
                );
            });
        });
    });

    describe("Test 6 — mobile SQLite and in-memory cache eviction on address change", () => {
        // @lat: [[mobile-sqlite-cache-design#Why address changes evict mobile SQLite caches]]
        it("evicts legislatorCache, billCache, and captured categories before refreshing", async () => {
            const callOrder: string[] = [];
            mockClearCapturedCategories.mockImplementation(() => {
                callOrder.push("clearCapturedCategories");
            });
            mockLegislatorCacheClear.mockImplementation(async () => {
                callOrder.push("legislatorCache.clear");
            });
            mockBillCacheClear.mockImplementation(async () => {
                callOrder.push("billCache.clear");
            });
            mockRefresh.mockImplementation(async () => {
                callOrder.push("refresh");
            });

            mockUseUserProfile.mockReturnValue({
                user: mockOnboardingUser,
                loading: false,
                refresh: mockRefresh,
            });
            mockCanGoBack.mockReturnValue(false);

            wrap(<AddressScreen />);

            await typeAndWaitForPredictions("100 N Holliday");
            await waitFor(() => {
                expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
            });
            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });

            await waitFor(() => {
                expect(mockApiPost).toHaveBeenCalled();
            });

            expect(mockClearCapturedCategories).toHaveBeenCalledTimes(1);
            expect(mockLegislatorCacheClear).toHaveBeenCalledTimes(1);
            expect(mockBillCacheClear).toHaveBeenCalledTimes(1);
            expect(mockRefresh).toHaveBeenCalledTimes(1);

            expect(callOrder.indexOf("clearCapturedCategories")).toBeLessThan(callOrder.indexOf("refresh"));
            expect(callOrder.indexOf("legislatorCache.clear")).toBeLessThan(callOrder.indexOf("refresh"));
            expect(callOrder.indexOf("billCache.clear")).toBeLessThan(callOrder.indexOf("refresh"));
        });

        it("does not evict caches when registration API returns an error", async () => {
            mockUseUserProfile.mockReturnValue({
                user: mockOnboardingUser,
                loading: false,
                refresh: mockRefresh,
            });
            mockApiPost.mockRejectedValueOnce(new Error("Address invalid"));

            wrap(<AddressScreen />);

            await typeAndWaitForPredictions("100 N Holliday");
            await waitFor(() => {
                expect(screen.queryByTestId("address-suggestion-PLACE_HOLLIDAY_1")).toBeTruthy();
            });
            await pickPrediction("address-suggestion-PLACE_HOLLIDAY_1");

            await act(async () => {
                fireEvent.press(screen.getByTestId("address-submit-cta"));
                await Promise.resolve();
                await Promise.resolve();
            });

            await waitFor(() => {
                expect(screen.getByText("Address invalid")).toBeTruthy();
            });

            expect(mockClearCapturedCategories).not.toHaveBeenCalled();
            expect(mockLegislatorCacheClear).not.toHaveBeenCalled();
            expect(mockBillCacheClear).not.toHaveBeenCalled();
            expect(mockRefresh).not.toHaveBeenCalled();
        });
    });
});

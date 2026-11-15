// @lat: [[mobile-auth-and-onboarding-flow#AddressScreen]]

const mockUseUserProfile = jest.fn();
const mockRefresh = jest.fn(async (): Promise<boolean | void> => {});

jest.mock("../../src/hooks/useSession", () => ({
    useSession: () => ({ isAuthenticated: true, loading: false, signOut: jest.fn(), signOutAll: jest.fn() }),
}));

jest.mock("../../src/hooks/useUserProfile", () => ({
    useUserProfile: () => mockUseUserProfile(),
}));

jest.mock("expo-haptics", () => ({
    impactAsync: jest.fn(async () => {}),
    ImpactFeedbackStyle: { Light: "Light" },
}));

jest.mock("expo-constants", () => ({
    expoConfig: { extra: {} },
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
import { act, fireEvent, render, screen } from "@testing-library/react-native";
import AddressScreen from "../../src/screens/AddressScreen";
import { ThemeProvider } from "../../src/theme/ThemeProvider";

const CONNECTION_SENTENCE = "Could not reach Sway. Check your connection and try again.";
const FRIENDLY_FALLBACK_SENTENCE = "Something went wrong. Please try again.";
const CONFIRMATION_SENTENCE =
    "Switching your address deactivates your current representative links. Please confirm to continue.";
const COOLDOWN_SENTENCE =
    "You recently changed your address. To prevent cross-district voting abuse, please wait before switching addresses again.";

function mockFetchResponse(body: unknown, init: { status: number; contentType?: string }) {
    const text = typeof body === "string" ? body : JSON.stringify(body);
    return {
        ok: init.status >= 200 && init.status < 300,
        status: init.status,
        headers: { get: () => init.contentType ?? "application/json" },
        text: async () => text,
    } as unknown as Response;
}

const wrap = (ui: React.ReactElement) => render(<ThemeProvider initialMode="light">{ui}</ThemeProvider>);

const fetchMock = () => global.fetch as jest.Mock;

const type = (field: string, text: string) =>
    fireEvent.changeText(screen.getByTestId(`address-input-${field}-input`), text);

const typeAddress = () => {
    type("street1", "100 N Holliday St");
    type("city", "Baltimore");
    type("region_code", "MD");
    type("postal_code", "21202");
};

const press = async (testID: string) => {
    await act(async () => {
        fireEvent.press(screen.getByTestId(testID));
    });
};

const expectFormUsable = () => {
    expect(screen.getByTestId("address-input-street1-input").props.value).toBe("100 N Holliday St");
    expect(screen.getByTestId("address-input-city-input").props.value).toBe("Baltimore");
    expect(screen.getByTestId("address-submit-cta").props.accessibilityState?.disabled).toBeFalsy();
    expect(mockNavigation.goBack).not.toHaveBeenCalled();
};

const originalFetch = global.fetch;

describe("AddressScreen submit failures through the real API client", () => {
    beforeEach(() => {
        jest.clearAllMocks();
        global.fetch = jest.fn() as unknown as typeof fetch;
    });

    afterEach(() => {
        jest.useRealTimers();
    });

    afterAll(() => {
        global.fetch = originalFetch;
    });

    describe("onboarding", () => {
        beforeEach(() => {
            mockUseUserProfile.mockReturnValue({
                user: { id: 1, is_registration_complete: false, address: undefined },
                loading: false,
                refresh: mockRefresh,
            });
        });

        it("shows a connection sentence, not the platform text, when the request times out", async () => {
            jest.useFakeTimers();
            fetchMock().mockImplementation(
                (_url: string, init: RequestInit) =>
                    new Promise((_resolve, reject) => {
                        init.signal?.addEventListener("abort", () => reject(new Error("Aborted")));
                    }),
            );
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");
            await act(async () => {
                await jest.advanceTimersByTimeAsync(15_000);
            });

            expect(screen.getByTestId("address-error").props.children).toBe(CONNECTION_SENTENCE);
            expectFormUsable();
        });

        it("reloads the account before it shows a timeout, in case the server finished the registration", async () => {
            jest.useFakeTimers();
            fetchMock().mockImplementation(
                (_url: string, init: RequestInit) =>
                    new Promise((_resolve, reject) => {
                        init.signal?.addEventListener("abort", () => reject(new Error("Aborted")));
                    }),
            );
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");
            await act(async () => {
                await jest.advanceTimersByTimeAsync(15_000);
            });

            expect(mockRefresh).toHaveBeenCalledTimes(1);
            expect(screen.getByTestId("address-error").props.children).toBe(CONNECTION_SENTENCE);
        });

        it("reloads the account when an edited resubmit is refused with confirmation_required", async () => {
            fetchMock().mockResolvedValue(
                mockFetchResponse(
                    { error: { code: "confirmation_required", message: CONFIRMATION_SENTENCE } },
                    { status: 422 },
                ),
            );
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");

            expect(mockRefresh).toHaveBeenCalledTimes(1);
            expect(screen.getByTestId("address-error").props.children).toBe(CONFIRMATION_SENTENCE);
            expectFormUsable();
        });

        it("shows the recovery card when the reload after confirmation_required fails, since onboarding has no confirm control", async () => {
            fetchMock().mockResolvedValue(
                mockFetchResponse(
                    { error: { code: "confirmation_required", message: CONFIRMATION_SENTENCE } },
                    { status: 422 },
                ),
            );
            mockRefresh.mockResolvedValueOnce(false);
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");

            expect(mockRefresh).toHaveBeenCalledTimes(1);
            expect(screen.getByTestId("address-saved-recovery")).toBeTruthy();
            expect(screen.queryByText(CONFIRMATION_SENTENCE)).toBeNull();
            expect(screen.queryByTestId("address-submit-cta")).toBeNull();
        });

        it("keeps the form and the connection sentence when the reload after a timeout fails", async () => {
            jest.useFakeTimers();
            fetchMock().mockImplementation(
                (_url: string, init: RequestInit) =>
                    new Promise((_resolve, reject) => {
                        init.signal?.addEventListener("abort", () => reject(new Error("Aborted")));
                    }),
            );
            mockRefresh.mockResolvedValueOnce(false);
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");
            await act(async () => {
                await jest.advanceTimersByTimeAsync(15_000);
            });

            expect(screen.queryByTestId("address-saved-recovery")).toBeNull();
            expect(screen.getByTestId("address-error").props.children).toBe(CONNECTION_SENTENCE);
            expectFormUsable();
        });

        it("shows the recovery card when the reload after confirmation_required throws", async () => {
            fetchMock().mockResolvedValue(
                mockFetchResponse(
                    { error: { code: "confirmation_required", message: CONFIRMATION_SENTENCE } },
                    { status: 422 },
                ),
            );
            mockRefresh.mockRejectedValueOnce(new Error("storage failure"));
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");

            expect(mockRefresh).toHaveBeenCalledTimes(1);
            expect(screen.getByTestId("address-saved-recovery")).toBeTruthy();
            expect(screen.queryByTestId("address-submit-cta")).toBeNull();
        });

        it("keeps the form and the connection sentence when the reload after a timeout throws", async () => {
            jest.useFakeTimers();
            fetchMock().mockImplementation(
                (_url: string, init: RequestInit) =>
                    new Promise((_resolve, reject) => {
                        init.signal?.addEventListener("abort", () => reject(new Error("Aborted")));
                    }),
            );
            mockRefresh.mockRejectedValueOnce(new Error("storage failure"));
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");
            await act(async () => {
                await jest.advanceTimersByTimeAsync(15_000);
            });

            expect(screen.queryByTestId("address-saved-recovery")).toBeNull();
            expect(screen.getByTestId("address-error").props.children).toBe(CONNECTION_SENTENCE);
            expectFormUsable();
        });

        it("does not reload the account for a refusal that cannot mean the address was saved", async () => {
            fetchMock().mockResolvedValue(
                mockFetchResponse("<html><body>Bad Request</body></html>", { status: 400, contentType: "text/html" }),
            );
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");

            expect(mockRefresh).not.toHaveBeenCalled();
        });

        it("shows the friendly fallback sentence for an HTML 500 page", async () => {
            fetchMock().mockResolvedValue(
                mockFetchResponse("<html><body>Internal Server Error</body></html>", {
                    status: 500,
                    contentType: "text/html",
                }),
            );
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");

            expect(screen.getByTestId("address-error").props.children).toBe(FRIENDLY_FALLBACK_SENTENCE);
            expectFormUsable();
        });

        it("shows the friendly fallback sentence for a 400 HTML page", async () => {
            fetchMock().mockResolvedValue(
                mockFetchResponse("<html><body>Bad Request</body></html>", { status: 400, contentType: "text/html" }),
            );
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");

            expect(screen.getByTestId("address-error").props.children).toBe(FRIENDLY_FALLBACK_SENTENCE);
            expectFormUsable();
        });

        it("posts again on a second press after a failure", async () => {
            fetchMock()
                .mockResolvedValueOnce(mockFetchResponse("<html></html>", { status: 500, contentType: "text/html" }))
                .mockResolvedValueOnce(mockFetchResponse({ ok: true }, { status: 200 }));
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");
            expect(screen.getByTestId("address-error")).toBeTruthy();
            await press("address-submit-cta");

            expect(fetchMock()).toHaveBeenCalledTimes(2);
            expect(screen.queryByTestId("address-error")).toBeNull();
        });
    });

    describe("edit mode", () => {
        beforeEach(() => {
            mockUseUserProfile.mockReturnValue({
                user: {
                    id: 1,
                    is_registration_complete: true,
                    address: {
                        street: "1 Old St",
                        street1: "1 Old St",
                        city: "Annapolis",
                        region_code: "MD",
                        postal_code: "21401",
                        country: "United States",
                    },
                },
                loading: false,
                refresh: mockRefresh,
            });
        });

        it("shows the server sentence for an address_switch_cooldown envelope", async () => {
            fetchMock().mockResolvedValue(
                mockFetchResponse(
                    { error: { code: "address_switch_cooldown", message: COOLDOWN_SENTENCE } },
                    { status: 422 },
                ),
            );
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");
            await press("address-confirm-deactivate-cta");

            expect(screen.getByTestId("address-error").props.children).toBe(COOLDOWN_SENTENCE);
            expectFormUsable();
            expect(mockRefresh).not.toHaveBeenCalled();
        });

        it("does not reload the account after a timeout, because the user is already registered", async () => {
            fetchMock().mockRejectedValue(new TypeError("Network request failed"));
            wrap(<AddressScreen />);
            typeAddress();

            await press("address-submit-cta");
            await press("address-confirm-deactivate-cta");

            expect(screen.getByTestId("address-error").props.children).toBe(CONNECTION_SENTENCE);
            expect(mockRefresh).not.toHaveBeenCalled();
        });
    });
});
